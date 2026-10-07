/**
 * dispatchFireJobs — S3. The minute cron.
 *
 * Each tick does two things, in this order:
 *   1. RECONCILE — for jobs already `dispatched`, read their command back. If it
 *      reached a terminal status, record the outcome and the end-to-end latency,
 *      and move the job to completed / failed / expired.
 *   2. DISPATCH — find `scheduled` jobs that are due, and write ONE command each.
 *
 * Reconcile runs FIRST so a job's outcome is recorded before the same tick can
 * consider anything else for that controller, and so the metrics for a fire
 * land on the tick after it, not a day later.
 *
 * WHY A SECOND COLLECTION AND NOT JUST COMMANDS
 * ----------------------------------------------
 * The command collection is the transport; it is swept by retention after 7
 * days and its documents are written by ten different writers. A fire job is
 * *intent* — it must survive its command, be cancellable before it fires, and
 * carry the identity that makes the dispatch idempotent. Conflating the two
 * would mean the plan disappears when the transport is cleaned up.
 *
 * Deployment (INDEX FIRST — the query throws without it):
 *   firebase deploy --only firestore:indexes
 *   cd functions && npm run build
 *   firebase deploy --only functions:dispatchFireJobs
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { fireJobDocId, isStuckExecuting, isStuckExecutingError } from "./commandSafety";
import { markStuckExecuting } from "./commandHygiene";
// hasInFlightCommand lives in controllerHealth because that is where it is
// tested and where it got its first caller (S6). It is a command-layer concern
// shared by both schedulers, not a health-specific one — imported rather than
// duplicated so there is exactly one definition of "is this controller busy".
import { hasInFlightCommand } from "./controllerHealth";
import {
  FIRE_JOBS_COLLECTION,
  FireType,
  appendSamples,
  buildFireCommand,
  checkTeamConfigGate,
  endFirstDueMs,
  startSupersedesEnd,
  SUPERSEDED_BY_START_REASON,
  classifyFireOutcome,
  decideDispatch,
  decideRetry,
  jobStateForCommandStatus,
  rollup,
  teamSlugFromEventId,
  toMillisOrNull,
  FIRE_GRACE_MS,
} from "./fireJobs";
import {
  SCORECARD_COLLECTION,
  SCORECARD_ENTRIES,
  publishServerStatusFrom,
  scorecardEntryId,
} from "./gameDayPreflight";

// admin.initializeApp() is called in index.js — do not call again here.

const DISPATCH_SCHEDULE = "* * * * *"; // every minute

/** Runaway guard. Far above any plausible fleet-wide minute. */
const MAX_JOBS_PER_TICK = 200;

/** Daily metrics doc. Part 3's shadow-run surface. */
const METRICS_COLLECTION = "fire_metrics";

const toMs = (t: unknown): number | null => {
  const v = t as { toMillis?: () => number } | null | undefined;
  return v && typeof v.toMillis === "function" ? v.toMillis() : null;
};

/** One in-flight command as the guard sees it, plus what A3 needs to clear it. */
interface InFlightDoc {
  controllerId?: unknown;
  status?: unknown;
  createdAt?: admin.firestore.Timestamp | null;
  ref?: admin.firestore.DocumentReference;
  updateTime?: admin.firestore.Timestamp;
}

interface TickStats {
  reconciled: number;
  completed: number;
  failed: number;
  expired: number;
  dispatched: number;
  /** A3: stuck `executing` docs this tick terminated before firing past them. */
  stuckCleared: number;
  /** A2: jobs put back to `scheduled` for another attempt, and why. */
  retried: number;
  retriedBy: Record<string, number>;
  skippedTransient: Record<string, number>;
  skippedTerminal: Record<string, number>;
  errors: number;
}

const bump = (m: Record<string, number>, k: string) => {
  m[k] = (m[k] ?? 0) + 1;
};

/**
 * B2 + B3 — what the dispatcher tells the world about a Game Day fire, beyond
 * the job itself: `users/{uid}.gameday_server.last_fire` (the app's "Last
 * fire: 6:45 PM, 2 s") and the scorecard entry's `start.*` / `end.*`.
 *
 * OBSERVABILITY ONLY. Every write here is best-effort and swallowed: a failed
 * scorecard update must never change what fired. The scorecard entry is found
 * through the session's `scorecard_key` (written by the planner at mint), and
 * updated with update(): an event minted before this shipped has no entry, and
 * the update simply finds nothing — no partial entries invented here.
 */
class GameDayObservers {
  private readonly keyCache = new Map<string, Promise<string | null>>();

  constructor(
    private readonly db: admin.firestore.Firestore,
    private readonly publishLastFire: boolean
  ) {}

  /** A start or end of a Game Day event — the only jobs observed. */
  static isGameDayFire(eventId: unknown, seq: unknown): eventId is string {
    return (
      typeof eventId === "string" &&
      teamSlugFromEventId(eventId) !== null &&
      (seq === "start" || seq === "end")
    );
  }

  private entryKey(uid: string, eventId: string): Promise<string | null> {
    const k = `${uid}/${eventId}`;
    let p = this.keyCache.get(k);
    if (!p) {
      p = this.db
        .collection("users").doc(uid)
        .collection("game_day_sessions").doc(eventId)
        .get()
        .then((d) => {
          const v = d.exists ? d.get("scorecard_key") : null;
          return typeof v === "string" && v.length > 0 ? v : null;
        })
        .catch(() => null);
      this.keyCache.set(k, p);
    }
    return p;
  }

  private async entryRef(uid: string, eventId: string) {
    const key = await this.entryKey(uid, eventId);
    if (!key) return null;
    return this.db
      .collection(SCORECARD_COLLECTION).doc(key)
      .collection(SCORECARD_ENTRIES).doc(scorecardEntryId(uid, eventId));
  }

  /** update() the event's entry; absent entry or any error → nothing. */
  async scorecard(uid: string, eventId: string, data: Record<string, unknown>): Promise<void> {
    try {
      const ref = await this.entryRef(uid, eventId);
      if (ref) await ref.update(data);
    } catch (_) {
      /* observability only */
    }
  }

  /** An end's final→completed latency needs the planner's espn_final_seen_at. */
  async endFinalLatency(uid: string, eventId: string, completedMs: number): Promise<number | null> {
    try {
      const ref = await this.entryRef(uid, eventId);
      if (!ref) return null;
      const snap = await ref.get();
      const finalMs = toMillisOrNull(snap.get("end.espn_final_seen_at"));
      return finalMs !== null && completedMs >= finalMs ? completedMs - finalMs : null;
    } catch (_) {
      return null;
    }
  }

  async lastFire(uid: string, data: Record<string, unknown>): Promise<void> {
    if (!this.publishLastFire) return;
    try {
      // Dotted path: replaces last_fire whole and touches nothing the planner owns.
      await this.db.collection("users").doc(uid).update({ "gameday_server.last_fire": data });
    } catch (_) {
      /* observability only */
    }
  }
}

/** B2's flag, read once per tick. Read failure → do not publish (planner rule). */
async function readPublishLastFire(db: admin.firestore.Firestore): Promise<boolean> {
  try {
    const d = await db.collection("config").doc("gameday_planner").get();
    return publishServerStatusFrom(d.exists ? d.data() : undefined);
  } catch (_) {
    return false;
  }
}

/**
 * One dispatcher tick. Exported so the bench harness drives the REAL code path
 * rather than a reimplementation (the discipline S6 established).
 *
 * `onlyUid` scopes every read and write to a single account so an end-to-end
 * bench run cannot touch customer data. `metricsSuffix` diverts the metrics doc
 * so synthetic bench traffic does not pollute the shadow-run percentiles.
 */
export async function runDispatchTick(
  db: admin.firestore.Firestore,
  nowMs: number,
  opts: { onlyUid?: string; metricsSuffix?: string } = {}
): Promise<TickStats & { e2eSamples: number[]; writeHopSamples: number[] }> {
  {
    const stats: TickStats = {
      reconciled: 0,
      completed: 0,
      failed: 0,
      expired: 0,
      dispatched: 0,
      stuckCleared: 0,
      retried: 0,
      retriedBy: {},
      skippedTransient: {},
      skippedTerminal: {},
      errors: 0,
    };

    const observers = new GameDayObservers(db, await readPublishLastFire(db));

    /** end-to-end: command createdAt → completedAt */
    const e2eSamples: number[] = [];
    /** PART 3 / V2 UNVERIFIED #13: the Admin-SDK write hop, never measured */
    const writeHopSamples: number[] = [];

    // ── 1. RECONCILE ────────────────────────────────────────────────────
    // SCOPED (bench) vs FLEET (production) queries.
    //
    // Scoped runs hit the user's own subcollection with a single equality, which
    // uses the automatic single-field index and needs NO index deploy — so an
    // end-to-end bench run is possible before the composite ships. The fleet
    // path uses the COLLECTION_GROUP composite, because reading every scheduled
    // job in existence each minute would not scale past a few weeks of plan.
    let dispatchedSnap;
    try {
      dispatchedSnap = opts.onlyUid
        ? await db
            .collection("users")
            .doc(opts.onlyUid)
            .collection(FIRE_JOBS_COLLECTION)
            .where("state", "==", "dispatched")
            .limit(MAX_JOBS_PER_TICK)
            .get()
        : await db
            .collectionGroup(FIRE_JOBS_COLLECTION)
            .where("state", "==", "dispatched")
            // orderBy is REQUIRED, not cosmetic. A bare single-field equality at
            // COLLECTION_GROUP scope needs its own COLLECTION_GROUP_ASC
            // single-field exemption — Firestore auto-creates single-field
            // indexes at COLLECTION scope only. Adding the sort makes this use
            // the (state, fireAt) composite that is already deployed, so no
            // second index is needed.
            //
            // Shipped without it on 2026-08-08 and EVERY tick threw
            // FAILED_PRECONDITION: reconcile runs first, so the whole tick died
            // before dispatch. Oldest-first is also the right order to reconcile.
            .orderBy("fireAt")
            .limit(MAX_JOBS_PER_TICK)
            .get();
    } catch (err) {
      logger.error(
        "dispatchFireJobs: RECONCILE QUERY FAILED — fire outcomes are not being " +
          "recorded. Check the COLLECTION_GROUP index on fire_jobs(state, fireAt).",
        err
      );
      throw err;
    }

    // An end never fires into the next game (2026-10-07 review). Before an
    // END is dispatched, retried or (in the planner) re-minted: has a start on
    // the same controller COMPLETED since this end was first due? Then the
    // house is a newer team's, and a base restore would wipe it. A start that
    // is merely dispatched has lit nothing yet; it holds the end back through
    // the one-in-flight guard below, transiently, and never closes it. One read
    // per end checked; ends are a handful a night. Only for an end the planner
    // wrote under the end guarantee (`endGuarantee: true`): the 90-minute
    // budget and the re-mints are what let an end outlive its game. A job
    // without the marker is dispatched and retried exactly as rev 00005 does.
    const supersedingStart = async (
      uid: string,
      jobSnap: admin.firestore.QueryDocumentSnapshot
    ): Promise<{ by: string; dispatchedAtMs: number } | null> => {
      if (jobSnap.get("endGuarantee") !== true) return null;
      const ctrl = jobSnap.get("controllerId");
      const due = endFirstDueMs({
        firstDueAt: jobSnap.get("firstDueAt"),
        firstFireAt: jobSnap.get("firstFireAt"),
        fireAt: jobSnap.get("fireAt"),
      });
      if (typeof ctrl !== "string" || ctrl.length === 0 || due === null) return null;
      const q = await db
        .collection("users").doc(uid).collection(FIRE_JOBS_COLLECTION)
        .where("state", "==", "completed") // COLLECTION scope → automatic index
        .get();
      const ownEvent = jobSnap.get("eventId");
      const r = startSupersedesEnd({
        jobs: q.docs.map((d) => ({
          id: d.id, eventId: d.get("eventId"), seq: d.get("seq"), state: d.get("state"),
          controllerId: d.get("controllerId"), dispatchedAt: d.get("dispatchedAt"), handoffTo: d.get("handoffTo"),
        })),
        controllerId: ctrl,
        endFirstDueMs: due,
        ...(typeof ownEvent === "string" ? { exceptEventId: ownEvent } : {}),
      });
      return r.superseded ? { by: r.by, dispatchedAtMs: r.dispatchedAtMs } : null;
    };

    for (const jobSnap of dispatchedSnap.docs) {
      try {
        const uid = jobSnap.ref.parent.parent?.id;
        if (opts.onlyUid && uid !== opts.onlyUid) continue;
        const commandId = jobSnap.get("commandId");
        if (!uid || typeof commandId !== "string" || !commandId) continue;

        const cmd = await db
          .collection("users")
          .doc(uid)
          .collection("commands")
          .doc(commandId)
          .get();

        // The command is GONE — retention swept it before we reconciled. That is
        // an absence, not a failure; do not invent an outcome. Terminalize as
        // `expired` ONLY if we can prove it was never picked up; otherwise mark
        // it unknown and stop re-reading it.
        const jobEventId = jobSnap.get("eventId");
        const jobSeq = jobSnap.get("seq");
        const observed = GameDayObservers.isGameDayFire(jobEventId, jobSeq);
        if (!cmd.exists) {
          await jobSnap.ref.update({
            state: "expired",
            outcome: "command_document_absent",
            reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          stats.reconciled++;
          stats.expired++;
          if (observed) {
            await observers.scorecard(uid, jobEventId as string, {
              [`${jobSeq}.state`]: "expired",
              [`${jobSeq}.outcome`]: "command_document_absent",
            });
          }
          continue;
        }

        const cmdStatus = cmd.get("status");
        const nextState = jobStateForCommandStatus(cmdStatus);
        if (nextState === null) continue; // still pending/executing — leave it

        const createdMs = toMs(cmd.get("createdAt"));
        const completedMs = toMs(cmd.get("completedAt"));
        const latencyMs =
          createdMs !== null && completedMs !== null && completedMs >= createdMs
            ? completedMs - createdMs
            : null;
        if (latencyMs !== null && nextState === "completed") e2eSamples.push(latencyMs);

        // A1: a command the server terminated as stuck is named as such, so the
        // retry path and the scorecard can tell "the bridge died mid-command"
        // from "WLED refused it". A `completed` doc reports no error even if a
        // stuck termination's text survived the bridge's later PATCH (its
        // update mask carries no `error` on success).
        const cmdError = cmdStatus === "completed" ? "" : String(cmd.get("error") ?? "");
        const outcome =
          cmdStatus === "failed" && isStuckExecutingError(cmdError)
            ? "stuck_executing"
            : String(cmdStatus);
        const cls = classifyFireOutcome(cmdStatus, cmdError);

        // ── A2: retry, when the outcome is transient and the budget allows ──
        const retry = decideRetry({
          job: {
            seq: jobSnap.get("seq"),
            attempts: jobSnap.get("attempts"),
            retryUntil: jobSnap.get("retryUntil"),
          },
          outcome: cls,
          nowMs,
        });
        if (retry.retry && jobSeq === "end") {
          const sup = await supersedingStart(uid, jobSnap);
          if (sup) {
            await jobSnap.ref.update({
              state: "skipped",
              skipReason: SUPERSEDED_BY_START_REASON,
              supersededBy: sup.by,
              outcome,
              outcomeClass: cls.outcome,
              commandError: cmdError.slice(0, 300),
              reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
              skippedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            stats.reconciled++;
            bump(stats.skippedTerminal, SUPERSEDED_BY_START_REASON);
            if (observed) {
              await observers.scorecard(uid, jobEventId as string, {
                [`${jobSeq}.state`]: "skipped",
                [`${jobSeq}.outcome`]: SUPERSEDED_BY_START_REASON,
                [`${jobSeq}.superseded_by`]: sup.by,
              });
            }
            continue;
          }
        }
        if (retry.retry && retry.nextFireAtMs !== undefined) {
          const nextFireAtMs = retry.nextFireAtMs;
          // Transactional, and only if the job is STILL dispatched on THIS
          // command: an overlapping invocation that already rescheduled it, or a
          // teardown that cancelled it, wins. The original fireAt is kept once,
          // so the scorecard measures latency from when the fire was first due.
          const rescheduled = await db.runTransaction(async (tx) => {
            const fresh = await tx.get(jobSnap.ref);
            if (fresh.get("state") !== "dispatched" || fresh.get("commandId") !== commandId) {
              return false;
            }
            tx.update(jobSnap.ref, {
              state: "scheduled",
              fireAt: admin.firestore.Timestamp.fromMillis(nextFireAtMs),
              firstFireAt: fresh.get("firstFireAt") ?? fresh.get("fireAt"),
              lastOutcome: cls.outcome,
              lastCommandId: commandId,
              lastCommandError: cmdError.slice(0, 300),
              retries: admin.firestore.FieldValue.increment(1),
              rescheduledAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return true;
          });
          if (rescheduled) {
            stats.retried++;
            bump(stats.retriedBy, cls.outcome);
            if (observed) {
              await observers.scorecard(uid, jobEventId as string, {
                [`${jobSeq}.state`]: "scheduled",
                [`${jobSeq}.retries`]: admin.firestore.FieldValue.increment(1),
                [`${jobSeq}.last_outcome`]: cls.outcome,
                ...(cls.outcome === "stuck_executing"
                  ? { stuck_executing_count: admin.firestore.FieldValue.increment(1) }
                  : {}),
              });
            }
          }
          continue;
        }

        await jobSnap.ref.update({
          state: nextState,
          outcome,
          outcomeClass: cls.outcome,
          commandError: cmdError.slice(0, 300),
          latencyMs,
          reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
          // A retryable outcome that ran out of budget says so, so "it failed"
          // and "it failed after every retry" are distinguishable.
          ...(cls.retryable ? { retryVerdict: retry.reason } : {}),
        });

        stats.reconciled++;
        if (nextState === "completed") stats.completed++;
        else if (nextState === "failed") stats.failed++;
        else if (nextState === "expired") stats.expired++;

        if (observed) {
          // fireAt → completed: measured from when the fire was FIRST due, so
          // a retried start reports the delay the house actually saw.
          const dueMs =
            toMillisOrNull(jobSnap.get("firstFireAt")) ?? toMillisOrNull(jobSnap.get("fireAt"));
          const fireLatencyMs =
            nextState === "completed" && completedMs !== null && dueMs !== null
              ? completedMs - dueMs
              : null;
          const completedAt =
            completedMs !== null ? admin.firestore.Timestamp.fromMillis(completedMs) : null;
          const fields: Record<string, unknown> = {
            [`${jobSeq}.state`]: nextState,
            [`${jobSeq}.outcome`]: cls.outcome,
            [`${jobSeq}.completed_at`]: completedAt,
            [`${jobSeq}.latency_ms`]: fireLatencyMs,
            [`${jobSeq}.command_latency_ms`]: latencyMs,
            ...(cls.outcome === "stuck_executing"
              ? { stuck_executing_count: admin.firestore.FieldValue.increment(1) }
              : {}),
            ...(jobSeq === "start" && nextState === "completed" ? { controllers_fired: 1 } : {}),
          };
          if (jobSeq === "end" && nextState === "completed" && completedMs !== null) {
            fields["end.latency_from_final_ms"] = await observers.endFinalLatency(
              uid, jobEventId as string, completedMs
            );
          }
          await observers.scorecard(uid, jobEventId as string, fields);
          // A hand-off end is the survivor's START: mirror it onto theirs.
          const handoffTo = jobSnap.get("handoffTo");
          if (jobSeq === "end" && typeof handoffTo === "string") {
            await observers.scorecard(uid, handoffTo, {
              "start.state": nextState,
              "start.outcome": cls.outcome,
              "start.completed_at": completedAt,
              "start.latency_ms": fireLatencyMs,
              ...(nextState === "completed" ? { controllers_fired: 1 } : {}),
            });
          }
          await observers.lastFire(uid, {
            event_id: jobEventId,
            seq: jobSeq,
            state: nextState,
            completed_at: completedAt,
            latency_ms: fireLatencyMs,
          });
        }
      } catch (err) {
        stats.errors++;
        logger.error(`dispatchFireJobs: reconcile failed for ${jobSnap.ref.path}`, err);
      }
    }

    // ── 2. DISPATCH ─────────────────────────────────────────────────────
    let dueSnap;
    try {
      dueSnap = opts.onlyUid
        ? // Equality only; fireAt filtered in memory by decideDispatch, which
          // already returns `not_yet_due` for a future job. No index required.
          await db
            .collection("users")
            .doc(opts.onlyUid)
            .collection(FIRE_JOBS_COLLECTION)
            .where("state", "==", "scheduled")
            .limit(MAX_JOBS_PER_TICK)
            .get()
        : await db
            .collectionGroup(FIRE_JOBS_COLLECTION)
            .where("state", "==", "scheduled")
            .where("fireAt", "<=", admin.firestore.Timestamp.fromMillis(nowMs))
            .limit(MAX_JOBS_PER_TICK)
            .get();
    } catch (err) {
      logger.error(
        "dispatchFireJobs: DUE QUERY FAILED — NOTHING IS FIRING. Check the " +
          "COLLECTION_GROUP index on fire_jobs(state, fireAt).",
        err
      );
      throw err;
    }

    // One in-flight read per user per tick, shared across that user's jobs.
    const pendingByUid = new Map<string, InFlightDoc[]>();

    for (const jobSnap of dueSnap.docs) {
      const uid = jobSnap.ref.parent.parent?.id;
      if (!uid) continue;
      if (opts.onlyUid && uid !== opts.onlyUid) continue;

      try {
        const job = {
          eventId: jobSnap.get("eventId"),
          seq: jobSnap.get("seq"),
          controllerId: jobSnap.get("controllerId"),
          fireAt: jobSnap.get("fireAt"),
          payload: jobSnap.get("payload"),
          type: jobSnap.get("type"),
          state: jobSnap.get("state"),
          commandId: jobSnap.get("commandId"),
          attempts: jobSnap.get("attempts"),
          // A2: the per-job lateness bound. Absent → the fixed 90 s window.
          retryUntil: jobSnap.get("retryUntil"),
        };

        const decision = decideDispatch({ job, nowMs });
        if (!decision.dispatch) {
          if (decision.terminal) {
            await jobSnap.ref.update({
              state: "skipped",
              skipReason: decision.reason,
              skippedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            bump(stats.skippedTerminal, decision.reason.split(":")[0]);
            if (GameDayObservers.isGameDayFire(job.eventId, job.seq)) {
              await observers.scorecard(uid, job.eventId, {
                [`${job.seq}.state`]: "skipped",
                [`${job.seq}.outcome`]: decision.reason.split(":")[0],
              });
            }
          } else {
            bump(stats.skippedTransient, decision.reason.split(":")[0]);
          }
          continue;
        }

        // ── #99: dispatch-time team-config gate ─────────────────────────
        // Planning-time consent is not dispatch-time consent. A Game Day job
        // outlives the config that planned it (the Royals case: config deleted
        // after planning, job still armed with a real payload 4 h out), so the
        // team is re-read HERE, immediately before the job is allowed to fire.
        //
        // Placed AFTER decideDispatch on purpose: decideDispatch is pure and
        // free, and it has already discarded not-yet-due and too-late jobs.
        // Reading the config first would spend a Firestore read per tick on
        // every future job in the table to answer a question that only matters
        // for the ones about to fire.
        // An END written by the end guarantee (`endGuarantee: true`) is a
        // restore for a house this system lit: it is exempt from the config
        // gate, which was written for STARTS (a deleted team must not fire a
        // new show; it must still get its old one put back). Any other end,
        // and every start, is gated exactly as before.
        if (job.seq === "end") {
          const sup = await supersedingStart(uid, jobSnap);
          if (sup) {
            await jobSnap.ref.update({
              state: "skipped",
              skipReason: SUPERSEDED_BY_START_REASON,
              supersededBy: sup.by,
              skippedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            bump(stats.skippedTerminal, SUPERSEDED_BY_START_REASON);
            if (GameDayObservers.isGameDayFire(job.eventId, job.seq)) {
              await observers.scorecard(uid, job.eventId, {
                [`${job.seq}.state`]: "skipped",
                [`${job.seq}.outcome`]: SUPERSEDED_BY_START_REASON,
                [`${job.seq}.superseded_by`]: sup.by,
              });
            }
            continue;
          }
        }
        const endGuaranteed = job.seq === "end" && jobSnap.get("endGuarantee") === true;
        const gate = endGuaranteed
          ? { ok: true as const }
          : await checkTeamConfigGate({ db, uid, eventId: job.eventId });
        if (!gate.ok) {
          await jobSnap.ref.update({
            state: "skipped",
            skipReason: gate.reason,
            skippedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          bump(stats.skippedTerminal, gate.reason as string);
          if (GameDayObservers.isGameDayFire(job.eventId, job.seq)) {
            await observers.scorecard(uid, job.eventId, {
              [`${job.seq}.state`]: "skipped",
              [`${job.seq}.outcome`]: gate.reason,
            });
          }
          continue;
        }

        const controllerId = job.controllerId as string;

        // ── Resolve the target IP SERVER-SIDE, always. Never omit. ───────
        const ctrl = await db
          .collection("users")
          .doc(uid)
          .collection("controllers")
          .doc(controllerId)
          .get();
        const ipRaw = ctrl.exists ? ctrl.get("ip") : null;
        const controllerIp = typeof ipRaw === "string" && ipRaw.length > 0 ? ipRaw : null;
        if (!controllerIp) {
          await jobSnap.ref.update({
            state: "skipped",
            skipReason: "unresolvable_target",
            skippedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          bump(stats.skippedTerminal, "unresolvable_target");
          continue;
        }

        // ── One-in-flight-per-controller ─────────────────────────────────
        if (!pendingByUid.has(uid)) {
          try {
            const snap = await db
              .collection("users")
              .doc(uid)
              .collection("commands")
              .where("status", "in", ["pending", "executing"])
              .get();
            pendingByUid.set(
              uid,
              snap.docs.map((d) => ({
                controllerId: d.get("controllerId"),
                status: d.get("status"),
                createdAt: d.get("createdAt") ?? null,
                ref: d.ref,
                updateTime: d.updateTime,
              }))
            );
          } catch (err) {
            // FAIL CLOSED. If we cannot prove the queue is clear, do not add to
            // it — a fire must never queue behind or ahead of customer traffic.
            logger.warn(`dispatchFireJobs: in-flight read failed for ${uid}; skipping`, err);
            pendingByUid.set(uid, [{ status: "pending" }]); // forces a block
          }
        }
        const pending = pendingByUid.get(uid)!;

        // ── A3: at most ONE non-terminal command per controller ──────────
        // The guard below ignores an `executing` doc older than the stuck
        // threshold (A1). Terminate it HERE, before firing past it, rather than
        // waiting up to a minute for the sweeper: the invariant "a controller
        // never has more than one non-terminal server command" then holds at
        // every instant, not merely within a sweeper tick. Same guarded write as
        // the sweeper — if the bridge reports first, its state stands.
        for (const d of pending) {
          if (!d.ref || !isStuckExecuting(d, nowMs)) continue;
          const cid = typeof d.controllerId === "string" ? d.controllerId : "";
          if (cid !== "" && cid !== controllerId) continue;
          const res = await markStuckExecuting(d.ref, d.updateTime);
          if (res === "written") stats.stuckCleared++;
          // Either way it is no longer this tick's concern.
          d.status = res === "written" ? "failed" : d.status;
          d.ref = undefined;
        }

        if (hasInFlightCommand(pending, controllerId, nowMs)) {
          // TRANSIENT — leave `scheduled`, retry next tick until too-late.
          bump(stats.skippedTransient, "in_flight");
          continue;
        }

        // ── Deterministic id, keyed on the JOB'S fireAt, not on `now` ─────
        // Using `now` would mint a NEW id on a retried invocation and the bridge
        // would fire TWICE. The job's own fireAt is stable across retries, so
        // .create() collides exactly when it should.
        const fireAtMs = (job.fireAt as { toMillis(): number }).toMillis();
        const commandId = fireJobDocId(jobSnap.id, Math.floor(fireAtMs / 1000));

        // `holdUntil` (2026-10-06, #179): an END job the planner wrote under
        // `end_ignores_gate` carries the instant until which its command must
        // stay pickable. The command's `expiresAt` is set there, so the sweeper
        // (which honours an explicit expiresAt) never expires it while the job
        // is within budget, and a bridge that comes back an hour later finds
        // the restore still waiting. The bridge checks no expiry itself. A job
        // without the field, or one whose hold is already past, gets the
        // 90-second grace exactly as before.
        const holdUntilMs = toMillisOrNull(jobSnap.get("holdUntil"));
        const { doc, expiresAtMs } = buildFireCommand({
          type: job.type as FireType,
          payload: String(job.payload ?? "{}"),
          controllerId,
          controllerIp,
          jobId: jobSnap.id,
          eventId: String(job.eventId ?? ""),
          dispatchAtMs: nowMs,
          ...(holdUntilMs !== null && holdUntilMs - nowMs > FIRE_GRACE_MS
            ? { graceMs: holdUntilMs - nowMs }
            : {}),
        });

        const cmdRef = db
          .collection("users")
          .doc(uid)
          .collection("commands")
          .doc(commandId);

        // PART 3 / V2 UNVERIFIED #13 — the Admin-SDK write hop, measured here.
        const t0 = Date.now();
        let created = true;
        try {
          await cmdRef.create({
            ...doc,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
          });
        } catch (err) {
          const code = (err as { code?: unknown })?.code;
          if (code === 6 || code === "already-exists") {
            // A retried invocation. The command exists, which was the goal.
            created = false;
          } else {
            throw err;
          }
        }
        const writeHopMs = Date.now() - t0;
        if (created) writeHopSamples.push(writeHopMs);

        await jobSnap.ref.update({
          state: "dispatched",
          commandId,
          dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
          dispatchLatenessMs: nowMs - fireAtMs,
          writeHopMs,
          attempts: admin.firestore.FieldValue.increment(1),
        });

        if (GameDayObservers.isGameDayFire(job.eventId, job.seq)) {
          const dispatchedFields = (prefix: string) => ({
            [`${prefix}.state`]: "dispatched",
            [`${prefix}.dispatched_at`]: admin.firestore.FieldValue.serverTimestamp(),
            [`${prefix}.attempts`]: admin.firestore.FieldValue.increment(1),
          });
          await observers.scorecard(uid, job.eventId, dispatchedFields(String(job.seq)));
          const handoffTo = jobSnap.get("handoffTo");
          if (job.seq === "end" && typeof handoffTo === "string") {
            await observers.scorecard(uid, handoffTo, dispatchedFields("start"));
          }
        }

        // Block any further job for this controller on this same tick.
        pending.push({
          controllerId,
          status: "pending",
          createdAt: admin.firestore.Timestamp.fromMillis(nowMs),
        });

        stats.dispatched++;
      } catch (err) {
        stats.errors++;
        logger.error(`dispatchFireJobs: dispatch failed for ${jobSnap.ref.path}`, err);
      }
    }

    // ── 3. METRICS (Part 3) ─────────────────────────────────────────────
    const dayKey =
      new Date(nowMs).toISOString().slice(0, 10) + (opts.metricsSuffix ?? "");
    const metricsRef = db.collection(METRICS_COLLECTION).doc(dayKey);
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(metricsRef);
        const prev = snap.exists ? snap.data() ?? {} : {};
        const e2e = appendSamples(prev.e2eSamples, e2eSamples);
        const hop = appendSamples(prev.writeHopSamples, writeHopSamples);
        tx.set(
          metricsRef,
          {
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ticks: admin.firestore.FieldValue.increment(1),
            dispatched: admin.firestore.FieldValue.increment(stats.dispatched),
            completed: admin.firestore.FieldValue.increment(stats.completed),
            failed: admin.firestore.FieldValue.increment(stats.failed),
            expired: admin.firestore.FieldValue.increment(stats.expired),
            inFlightBlocks: admin.firestore.FieldValue.increment(
              stats.skippedTransient.in_flight ?? 0
            ),
            tooLate: admin.firestore.FieldValue.increment(stats.skippedTerminal.too_late ?? 0),
            unsafe: admin.firestore.FieldValue.increment(stats.skippedTerminal.unsafe ?? 0),
            stuckCleared: admin.firestore.FieldValue.increment(stats.stuckCleared),
            retried: admin.firestore.FieldValue.increment(stats.retried),
            errors: admin.firestore.FieldValue.increment(stats.errors),
            e2eSamples: e2e,
            writeHopSamples: hop,
            e2e: rollup(e2e),
            writeHop: rollup(hop),
          },
          { merge: true }
        );
      });
    } catch (err) {
      // Metrics must never fail the dispatch whose writes already landed.
      logger.error("dispatchFireJobs: metrics write failed", err);
    }

    const quiet =
      stats.dispatched === 0 &&
      stats.reconciled === 0 &&
      stats.retried === 0 &&
      Object.keys(stats.skippedTransient).length === 0 &&
      Object.keys(stats.skippedTerminal).length === 0;
    if (!quiet || stats.errors > 0) {
      logger.info(`dispatchFireJobs: ${JSON.stringify(stats)}`);
    }

    return { ...stats, e2eSamples, writeHopSamples };
  }
}

export const dispatchFireJobs = onSchedule(
  {
    schedule: DISPATCH_SCHEDULE,
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    await runDispatchTick(admin.firestore(), Date.now());
  }
);
