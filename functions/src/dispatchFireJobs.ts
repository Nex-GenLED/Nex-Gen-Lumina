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
import { fireJobDocId } from "./commandSafety";
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
  decideDispatch,
  jobStateForCommandStatus,
  rollup,
} from "./fireJobs";

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

interface TickStats {
  reconciled: number;
  completed: number;
  failed: number;
  expired: number;
  dispatched: number;
  skippedTransient: Record<string, number>;
  skippedTerminal: Record<string, number>;
  errors: number;
}

const bump = (m: Record<string, number>, k: string) => {
  m[k] = (m[k] ?? 0) + 1;
};

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
      skippedTransient: {},
      skippedTerminal: {},
      errors: 0,
    };

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
        if (!cmd.exists) {
          await jobSnap.ref.update({
            state: "expired",
            outcome: "command_document_absent",
            reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          stats.reconciled++;
          stats.expired++;
          continue;
        }

        const nextState = jobStateForCommandStatus(cmd.get("status"));
        if (nextState === null) continue; // still pending/executing — leave it

        const createdMs = toMs(cmd.get("createdAt"));
        const completedMs = toMs(cmd.get("completedAt"));
        const latencyMs =
          createdMs !== null && completedMs !== null && completedMs >= createdMs
            ? completedMs - createdMs
            : null;
        if (latencyMs !== null && nextState === "completed") e2eSamples.push(latencyMs);

        await jobSnap.ref.update({
          state: nextState,
          outcome: String(cmd.get("status")),
          commandError: String(cmd.get("error") ?? "").slice(0, 300),
          latencyMs,
          reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        stats.reconciled++;
        if (nextState === "completed") stats.completed++;
        else if (nextState === "failed") stats.failed++;
        else if (nextState === "expired") stats.expired++;
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
    const pendingByUid = new Map<
      string,
      Array<{ controllerId?: unknown; status?: unknown }>
    >();

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
          } else {
            bump(stats.skippedTransient, decision.reason.split(":")[0]);
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
              snap.docs.map((d) => d.data() as { controllerId?: unknown; status?: unknown })
            );
          } catch (err) {
            // FAIL CLOSED. If we cannot prove the queue is clear, do not add to
            // it — a fire must never queue behind or ahead of customer traffic.
            logger.warn(`dispatchFireJobs: in-flight read failed for ${uid}; skipping`, err);
            pendingByUid.set(uid, [{ status: "pending" }]); // forces a block
          }
        }
        const pending = pendingByUid.get(uid)!;
        if (hasInFlightCommand(pending, controllerId)) {
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

        const { doc, expiresAtMs } = buildFireCommand({
          type: job.type as FireType,
          payload: String(job.payload ?? "{}"),
          controllerId,
          controllerIp,
          jobId: jobSnap.id,
          eventId: String(job.eventId ?? ""),
          dispatchAtMs: nowMs,
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

        // Block any further job for this controller on this same tick.
        pending.push({ controllerId, status: "pending" });

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
