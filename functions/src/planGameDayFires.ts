/**
 * planGameDayFires — S5. The producer S3 was waiting for.
 *
 * Reads users/{uid}/game_day_autopilot/{teamSlug}, polls ESPN, and writes
 * fire_jobs that dispatchFireJobs turns into commands.
 *
 * SHIPS IN LOG-ONLY MODE. `config/gameday_planner.write_jobs` defaults FALSE, so
 * the planner records what it WOULD have done to /gameday_plan_log/{day} and
 * writes no fire jobs at all. ESPN's semantics under delays, suspensions and
 * doubleheaders are UNVERIFIED, and a wrong-early `final` is the one genuinely
 * bad outcome — it ends the show mid-game in front of a customer who is not
 * there. A flag, not a promise: the flip is a console edit with no deploy.
 *
 * ─── QUERY SCOPES AND INDEX REQUIREMENTS ────────────────────────────────────
 * Stated explicitly per the S3 lesson: the bench's --uid scoping takes the
 * plain-COLLECTION path and CANNOT reveal a COLLECTION_GROUP index requirement.
 * S3 shipped with every tick throwing because a bare single-field equality at
 * collection-group scope needs its own COLLECTION_GROUP_ASC exemption, and 28/28
 * bench tests passed against a query shape that does not exist in production.
 *
 *   1. db.collection("users").get()
 *        scope COLLECTION, no filter            → no index
 *   2. users/{uid}/game_day_autopilot .where("enabled","==",true)
 *        scope COLLECTION, single-field equality → automatic single-field index
 *   3. users/{uid}/fire_jobs .where("eventId","==",X)
 *        scope COLLECTION, single-field equality → automatic single-field index
 *
 * **NO collection-group query is used anywhere in this file.** That is a
 * deliberate constraint, not a coincidence: iterating users and then reading
 * each subcollection costs one extra read per user per tick and buys immunity
 * from the exact class of failure that broke S3 on deploy. At 24 users that is
 * a trade worth making; if the fleet reaches thousands it should be revisited
 * WITH the index deployed and verified READY first.
 *
 * Deployment:
 *   cd functions && npm run build
 *   firebase deploy --only functions:planGameDayFires
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { participationForFire } from "./participationForFire";
import {
  evaluateAccountReadiness,
  graduationEvents,
  gateSummary,
  summarizeGate,
  formatGateSummary,
  GateBlockingReason,
  GateVerdict,
} from "./gameDayGate";
import { assertPayloadIsFireSafe, FIRE_JOBS_COLLECTION } from "./fireJobs";
import {
  DEFAULT_LEAD_MINUTES,
  PLAN_HORIZON_MS,
  argbToRgb,
  buildParticipatingSegArray,
  buildFullPartitionSegArray,
  decideEndSignal,
  startJobConfirmsFired,
  estimatedDurationMs,
  isDaylightOnlyGame,
  savedDesignUsable,
  baseRestorePayload,
  toRgbwSlots,
} from "./gameDayPlanning";
import { fetchTeamGame, EspnGame } from "./espnClient";

// admin.initializeApp() is called in index.js — do not call again here.

/**
 * Every 5 minutes.
 *
 * Two requirements pull in opposite directions and 5 satisfies both:
 *   - A start job must EXIST before the dispatcher needs it. The dispatcher
 *     ticks每 minute and refuses a job more than 90 s late (MAX_FIRE_LATENESS),
 *     so the planner must write a job comfortably before its fireAt. A 5-minute
 *     cadence with a 6-hour horizon means every start is planned hours early.
 *   - The END signal needs two consecutive polls. At 5 minutes that confirms a
 *     real final within ~10 minutes of the whistle. A game ending 10 minutes
 *     before the lights change is invisible to someone who is away; a 15-minute
 *     cadence would be 30, which starts to be noticed on a re-watch.
 * ESPN state changes on the order of minutes, so polling faster buys nothing and
 * costs a request per team per tick.
 */
const PLANNER_SCHEDULE = "*/5 * * * *";

const PLAN_LOG_COLLECTION = "gameday_plan_log";
const SESSION_COLLECTION = "game_day_sessions";

interface PlanStats {
  usersScanned: number;
  configsEnabled: number;
  startsPlanned: number;
  endsPlanned: number;
  /**
   * START-phase outcomes. **Exactly one bucket per enabled config**, so the
   * invariant is `sum(skipped) + startsPlanned === configsEnabled` (less any
   * config that threw — see `errors`).
   *
   * END outcomes are deliberately NOT in here. A config that plans a start
   * then falls through to the end guards would increment twice and the sum
   * would exceed configsEnabled. That fall-through is CORRECT and must not be
   * `continue`d away: during a live game every config sits on
   * `start_already_planned` and still has to reach `decideEndSignal` to fire
   * its end. The two phases are separate accounting dimensions, not one.
   */
  skipped: Record<string, number>;
  /** END-phase outcomes. Reconciles against `endsPlanned`, not against START. */
  endSkipped: Record<string, number>;
  espnErrors: number;
  errors: number;
}

const bump = (m: Record<string, number>, k: string) => {
  m[k] = (m[k] ?? 0) + 1;
};

/**
 * The write-jobs policy: globally armed, or armed for a named set of uids.
 *
 * `allowlist === null` means "no list" — every uid is armed once `write_jobs`
 * is true. A non-null list arms ONLY those uids; everyone else stays log-only
 * and still logs what WOULD have been planned, so the dry-run corpus keeps
 * growing for the eventual global audit.
 */
export interface WriteJobsPolicy {
  enabled: boolean;
  allowlist: string[] | null;
}

export const WRITE_JOBS_OFF: WriteJobsPolicy = { enabled: false, allowlist: null };

/**
 * PURE. Derive the policy from the flag document's data.
 *
 * FAIL-SAFE IN EVERY DIRECTION — the four shapes, plus the malformed one:
 *
 *   doc absent / undefined data      -> OFF
 *   write_jobs !== true              -> OFF regardless of any allowlist
 *   write_jobs true, list present    -> armed for those uids ONLY
 *   write_jobs true, list absent     -> armed globally
 *   write_jobs true, list MALFORMED  -> OFF, loudly
 *
 * The malformed case is off rather than global on purpose. A `uid_allowlist`
 * that is a string, an object, or an array with a non-string in it means
 * somebody INTENDED to scope the flip and the scoping did not parse. Treating
 * that as "global" would turn a typo into a fleet-wide arm — the opposite of
 * what the author was reaching for. An empty array is NOT malformed: it is a
 * deliberate "armed for nobody", and it is honoured as such.
 */
export function writeJobsPolicyFrom(
  data: Record<string, unknown> | undefined
): WriteJobsPolicy {
  if (!data || data.write_jobs !== true) return WRITE_JOBS_OFF;

  const raw = data.uid_allowlist;
  if (raw === undefined || raw === null) {
    return { enabled: true, allowlist: null }; // global
  }
  if (!Array.isArray(raw) || raw.some((u) => typeof u !== "string" || u === "")) {
    logger.error(
      "planGameDayFires: uid_allowlist is MALFORMED (expected string[]); " +
        "refusing to write jobs. Fix or remove the field to arm. Value: " +
        JSON.stringify(raw)
    );
    return WRITE_JOBS_OFF;
  }
  return { enabled: true, allowlist: raw as string[] };
}

/** True when THIS uid may have jobs written for it. */
export function writesJobsFor(policy: WriteJobsPolicy, uid: string): boolean {
  if (!policy.enabled) return false;
  if (policy.allowlist === null) return true;
  return policy.allowlist.includes(uid);
}

/** Read the write-jobs policy. Defaults OFF — log-only until deliberately on. */
async function readWriteJobsPolicy(
  db: admin.firestore.Firestore
): Promise<WriteJobsPolicy> {
  try {
    const d = await db.collection("config").doc("gameday_planner").get();
    if (!d.exists) return WRITE_JOBS_OFF;
    return writeJobsPolicyFrom(d.data());
  } catch (err) {
    logger.warn("planGameDayFires: flag read failed; staying LOG-ONLY", err);
    return WRITE_JOBS_OFF;
  }
}

/**
 * Build the fire payload for a config. Returns the JSON string a fire job
 * carries, or a refusal reason.
 */
export function buildGameDayPayload(args: {
  config: Record<string, unknown>;
  participatingChannels: number[];
  /**
   * #67. The controller's full channel set, from the healer's published facts.
   * Present → the payload asserts the FULL PARTITION. Absent/empty → falls back
   * to naming only the participating channels (pre-#67 behaviour) and reports
   * `partitioned:false` so the caller can log `partition_unavailable`.
   * Never guess a partial: a fabricated device set would darken a channel the
   * customer actually has.
   */
  deviceChannelIds?: number[] | null;
}): { payload: string; partitioned: boolean } | { refuse: string } {
  const c = args.config;

  // Saved design takes priority, exactly as the client's selectDesign does.
  if (c.design_mode === "saved" && c.saved_design_payload) {
    const v = savedDesignUsable(c.saved_design_payload);
    if (!v.usable) return { refuse: v.reason };
    const raw =
      typeof c.saved_design_payload === "string"
        ? c.saved_design_payload
        : JSON.stringify(c.saved_design_payload);
    // A saved blob carries its own seg shape and is NOT re-expanded across
    // channels — the client documents the same carve-out (selectDesign's
    // saved branch bypasses _buildWledPayload and is not participation
    // filtered). Re-expanding would flatten a multi-seg design onto bus 0.
    // #67 does NOT partition a saved design either: the blob carries its own
    // multi-segment shape, and overlaying an exclusion set built for the
    // channel model would fight it. Recorded as partitioned:false so a saved
    // design is never mistaken for a partitioned fire in the log.
    return { payload: raw, partitioned: false };
  }

  if (args.participatingChannels.length === 0) {
    return { refuse: "no_participating_channels" };
  }

  const primary = typeof c.primary_color === "number" ? c.primary_color : 0xffffffff;
  const secondary =
    typeof c.secondary_color === "number" ? c.secondary_color : 0xffffffff;

  const look = {
    effectId: typeof c.effect_id === "number" ? c.effect_id : 0,
    speed: typeof c.speed === "number" ? c.speed : 128,
    intensity: typeof c.intensity === "number" ? c.intensity : 128,
    colorSlots: toRgbwSlots([argbToRgb(primary), argbToRgb(secondary)]),
  };

  // #67 — assert the full partition when the device set is known, so an
  // excluded channel goes DARK rather than merely unchanged. Without the facts
  // we cannot know what to exclude, and inventing it is worse than the old
  // behaviour, so we fall back and say so.
  const deviceIds = args.deviceChannelIds;
  const canPartition = Array.isArray(deviceIds) && deviceIds.length > 0;

  const seg = canPartition
    ? buildFullPartitionSegArray({
        deviceChannelIds: deviceIds as number[],
        participatingChannelIds: args.participatingChannels,
        ...look,
      })
    : buildParticipatingSegArray({
        participatingChannelIds: args.participatingChannels,
        ...look,
      });

  return {
    payload: JSON.stringify({
      on: true,
      bri: typeof c.brightness === "number" ? c.brightness : 200,
      seg,
    }),
    partitioned: canPartition,
  };
}

/** The state that makes the end-signal guards survive a retry. */
function sessionRef(
  db: admin.firestore.Firestore,
  uid: string,
  eventId: string
): admin.firestore.DocumentReference {
  return db
    .collection("users")
    .doc(uid)
    .collection(SESSION_COLLECTION)
    .doc(eventId);
}

/** Stable per-game identity. One event = one team's one game. */
export function eventIdFor(teamSlug: string, gameId: string): string {
  return `gd_${teamSlug}_${gameId}`;
}

export async function runPlannerTick(
  db: admin.firestore.Firestore,
  nowMs: number,
  opts: {
    onlyUid?: string;
    forceWriteJobs?: boolean;
    forcePolicy?: WriteJobsPolicy;
  } = {}
): Promise<PlanStats & { logRows: Array<Record<string, unknown>> }> {
  // Policy, not a boolean: `write_jobs` can be armed globally or scoped to a
  // uid allowlist. forceWriteJobs is kept for existing callers/tests and means
  // "globally armed".
  const policy: WriteJobsPolicy =
    opts.forcePolicy ??
    (opts.forceWriteJobs === undefined
      ? await readWriteJobsPolicy(db)
      : { enabled: opts.forceWriteJobs, allowlist: null });
  const stats: PlanStats = {
    usersScanned: 0,
    configsEnabled: 0,
    startsPlanned: 0,
    endsPlanned: 0,
    skipped: {},
    endSkipped: {},
    espnErrors: 0,
    errors: 0,
  };
  const logRows: Array<Record<string, unknown>> = [];
  // The SINGLE source for both the per-account gate rows and the aggregate
  // tick line. Summarising a second pass over the inputs is how a summary and
  // its own detail rows come to disagree.
  const gateVerdicts: GateVerdict[] = [];

  const users = await db.collection("users").get(); // scope COLLECTION, no index
  const gameCache = new Map<string, EspnGame | null>();

  for (const u of users.docs) {
    const uid = u.id;
    // Per-uid arming. A scoped-out account still runs the whole planner and
    // still logs what WOULD have been planned — the dry-run corpus must keep
    // growing for the eventual global audit, which is the only thing that can
    // clear F1 (the end path has never executed) fleet-wide.
    const allowlisted = writesJobsFor(policy, uid);
    if (opts.onlyUid && uid !== opts.onlyUid) continue;

    const configs = await db
      .collection("users")
      .doc(uid)
      .collection("game_day_autopilot")
      .where("enabled", "==", true) // COLLECTION scope → automatic index
      .get();
    if (configs.empty) continue;
    stats.usersScanned++;

    // One controller read per user, shared by every config.
    const controllers = await db.collection("users").doc(uid).collection("controllers").get();
    const controller = controllers.docs[0] ?? null;

    // ── READINESS GATE ────────────────────────────────────────────────
    // Evaluated for EVERY account with an enabled config, on every tick —
    // not on the enable toggle. That is the whole point: all nine live
    // accounts predate the old client prompt, so a toggle-time check would
    // still gate nobody. An already-enabled account is evaluated here with
    // no user action, and graduates the tick after it becomes ready.
    const udata = u.data() || {};
    const hasScheduleArray =
      Array.isArray(udata.schedules) && udata.schedules.length > 0;
    // Only pay for the subcollection read when the array is empty — the
    // #TD-1 dual state means either counts, but most accounts answer on the
    // cheap side.
    let hasScheduleSubcollection = false;
    if (!hasScheduleArray) {
      try {
        const sub = await db
          .collection("users").doc(uid).collection("schedules").limit(1).get();
        hasScheduleSubcollection = !sub.empty;
      } catch (_) {
        /* unreadable → treat as absent; the gate fails safe toward log-only */
      }
    }
    const cdata = controller?.data() || {};
    const gate = evaluateAccountReadiness({
      hasScheduleArray,
      hasScheduleSubcollection,
      hasParticipationFacts:
        Array.isArray(cdata.participating_channels_device_ids) &&
        cdata.participating_channels_device_ids.length > 0,
      // Tri-state, read straight through. The fact is not published yet, so
      // this is `undefined` fleet-wide today = unknown-and-allowed.
      ladderAssertsSegments:
        typeof cdata.base_ladder_asserts_segments === "boolean"
          ? (cdata.base_ladder_asserts_segments as boolean)
          : null,
    });

    // Log-only for THIS account when gated — the same shape the allowlist
    // produces, deliberately not a second mechanism.
    const writeJobs = allowlisted && gate.armed;

    const priorGate = Array.isArray(udata.gameday_gate_blocking)
      ? (udata.gameday_gate_blocking as GateBlockingReason[])
      : null;
    gateVerdicts.push(gate);
    for (const g of graduationEvents(priorGate, gate.blocking)) {
      logRows.push({ uid, action: "gate", reason: g });
      bump(stats.skipped, g);
    }
    for (const r of gate.blocking) {
      logRows.push({ uid, action: "gate", reason: r, summary: gateSummary(gate) });
    }
    for (const a of gate.advisory) {
      logRows.push({ uid, action: "gate", reason: a, advisory: true });
    }
    // Persist ONLY on change: the verdict is the input to the next tick's
    // graduation check, and a write every tick for every user would cost more
    // than the gate saves.
    const changed =
      JSON.stringify(priorGate ?? []) !== JSON.stringify(gate.blocking);
    if (changed) {
      try {
        await u.ref.set(
          { gameday_gate_blocking: gate.blocking },
          { merge: true }
        );
      } catch (_) {
        /* a failed state write must never stop planning */
      }
    }

    for (const cfgDoc of configs.docs) {
      stats.configsEnabled++;
      const c = cfgDoc.data();
      const teamSlug = cfgDoc.id;
      const sport = String(c.sport ?? "");
      const espnTeamId = String(c.espn_team_id ?? "");

      try {
        if (!controller) {
          bump(stats.skipped, "no_controller");
          // ATTRIBUTABLE (2026-08-11): counter-only buckets were nameable but
          // not attributable — "2 configs have no controller" with no way to
          // say whose. Rows go through arrayUnion, which DEDUPES identical
          // objects, so a row carrying no per-tick-varying field collapses to
          // one entry for the whole day however many ticks run. Volume is
          // bounded by DISTINCT (uid, teamSlug, reason) — at most
          // configsEnabled rows/day from these three buckets, not
          // ticks × configs. That is why no cap is needed; adding a timestamp
          // here would defeat the dedupe and is exactly what not to do.
          logRows.push({ uid, teamSlug, action: "skip", reason: "no_controller" });
          continue;
        }

        // ── ESPN, cached per (sport, team) across users ──────────────────
        const key = `${sport}/${espnTeamId}`;
        if (!gameCache.has(key)) {
          try {
            gameCache.set(key, await fetchTeamGame(sport, espnTeamId));
          } catch (err) {
            gameCache.set(key, null);
            stats.espnErrors++;
            logger.warn(`planGameDayFires: ESPN failed for ${key}`, err);
          }
        }
        const game = gameCache.get(key) ?? null;
        if (!game) {
          bump(stats.skipped, "no_game");
          // The biggest bucket (11 of 19 on 2026-08-11) and still bounded: one
          // row per (uid, teamSlug), deduped by arrayUnion across every tick.
          // No eventId exists here — there is no game to name.
          logRows.push({ uid, teamSlug, action: "skip", reason: "no_game" });
          continue;
        }

        const eventId = eventIdFor(teamSlug, game.gameId);
        const sRef = sessionRef(db, uid, eventId);
        const session = (await sRef.get()).data() ?? {};

        // ── Participation — S3b's consumer, wired here for the first time ─
        const part = participationForFire(controller.data(), nowMs);
        if (!part.usable) {
          bump(stats.skipped, `participation:${part.reason.split(":")[0]}`);
          logRows.push({
            uid, teamSlug, eventId, action: "skip",
            reason: `participation_${part.reason}`,
          });
          continue;
        }

        // ── Daylight filter ──────────────────────────────────────────────
        if (c.skip_day_games === true) {
          const lat = u.get("latitude");
          const lon = u.get("longitude");
          if (typeof lat === "number" && typeof lon === "number") {
            if (
              isDaylightOnlyGame({
                gameStartMs: game.startMs,
                estimatedDurationMs: estimatedDurationMs(sport),
                latitude: lat,
                longitude: lon,
                // The user doc carries no tz offset; US Central is the fleet's
                // reality today and a ±1 h error only matters within 30 min of
                // sunset. Recorded as a limitation rather than hidden.
                tzOffsetHours: -5,
              })
            ) {
              bump(stats.skipped, "daylight_game");
              // ATTRIBUTABLE (#90). The second silent skip, and the one that
              // swallowed mlb_royals on 2026-08-16: the 08-16 summary read
              // `daylight_game: 9` and named not one team, so "your team played
              // and we deliberately sat it out" was indistinguishable from
              // "nothing happened" — which is exactly why a scoring game with
              // an enabled config read as a celebrations failure.
              //
              // The skip itself is CORRECT behaviour (per-config `skip_day_games`
              // opt-in + user lat/lon); only its invisibility is the defect.
              // Batched with C10's `start_time_passed` row deliberately: two of
              // the planner's skip reasons wrote rows and two did not, and the
              // ASYMMETRY is the bug, not either row on its own.
              //
              // No lead is applied here — this branch is upstream of the START
              // block that computes `startFireAt` — so the row names the game's
              // own start, which is the time the user would look for.
              logRows.push({
                uid, teamSlug, eventId, action: "skip", reason: "daylight_game",
                fireAt: new Date(game.startMs).toISOString(),
              });
              continue;
            }
          }
        }

        // ── START ────────────────────────────────────────────────────────
        const lead =
          (typeof c.lead_time_minutes === "number"
            ? c.lead_time_minutes
            : DEFAULT_LEAD_MINUTES) * 60_000;
        const startFireAt = game.startMs - lead;

        // OBSERVABILITY (2026-08-11): every path out of this block must
        // increment something. Before this, a config that passed participation
        // and then failed the horizon test fell through with NO counter — the
        // stats reconciled to 18 of 19 and "waiting for the horizon" was
        // indistinguishable from "vanished". That is precisely the state being
        // read during a live shadow run, so it must be nameable.
        const startAlreadyPlanned = !!session.startPlannedAt;
        const startInPast = startFireAt <= nowMs - 60_000;
        const startBeyondHorizon = startFireAt >= nowMs + PLAN_HORIZON_MS;

        if (
          !startAlreadyPlanned &&
          !startInPast &&
          !startBeyondHorizon
        ) {
          const built = buildGameDayPayload({
            config: c,
            participatingChannels: part.channels,
            // #67 — the device's own channel set, so the payload can name
            // every channel and darken the excluded ones.
            deviceChannelIds: part.deviceChannelIds,
          });
          if ("refuse" in built) {
            bump(stats.skipped, `payload:${built.refuse.split(":")[0]}`);
            logRows.push({ uid, teamSlug, eventId, action: "skip", reason: built.refuse });
          } else {
            const safety = assertPayloadIsFireSafe("applyJson", built.payload);
            if (!safety.ok) {
              // Should be unreachable — Game Day is inline state everywhere and
              // carries no psave/pdel/rb. Asserted rather than assumed.
              bump(stats.skipped, "unsafe_payload");
              logger.error(
                `planGameDayFires: UNSAFE payload for ${uid}/${teamSlug}: ${safety.reason}`
              );
            } else {
              logRows.push({
                uid, teamSlug, eventId, action: "plan_start",
                fireAt: new Date(startFireAt).toISOString(),
                channels: part.channels, bytes: built.payload.length,
                // #67 — false means the fire named only the participating
                // channels because the device set was unknown, so an excluded
                // channel was left UNCHANGED rather than darkened. A partial
                // exclusion must be legible in the corpus, not inferred.
                partitioned: built.partitioned,
                ...(built.partitioned ? {} : { partitionNote: "partition_unavailable" }),
                // Armed globally/for this uid, or held back by the allowlist.
                // Without this a scoped-out row is indistinguishable from a
                // log-only-era row, and the corpus stops being auditable the
                // moment the flip is partial.
                ...(policy.enabled && !writeJobs ? { scopedOut: true } : {}),
              });
              if (writeJobs) {
                await db
                  .collection("users").doc(uid)
                  .collection(FIRE_JOBS_COLLECTION).doc(`${eventId}_start`)
                  .create({
                    eventId, seq: "start",
                    controllerId: controller.id,
                    fireAt: admin.firestore.Timestamp.fromMillis(startFireAt),
                    type: "applyJson", payload: built.payload,
                    state: "scheduled",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    source: "game_day",
                  })
                  .catch((e) => {
                    if (e.code !== 6 && e.code !== "already-exists") throw e;
                  });
                await sRef.set(
                  {
                    startPlannedAt: admin.firestore.FieldValue.serverTimestamp(),
                    gameStartMs: game.startMs,
                    teamSlug, sport,
                  },
                  { merge: true }
                );
              }
              stats.startsPlanned++;
            }
          }
        } else if (startAlreadyPlanned) {
          // Not a skip in the error sense — the job already exists. Counted so
          // a steady-state tick still reconciles.
          bump(stats.skipped, "start_already_planned");
        } else if (startBeyondHorizon) {
          // THE ONE THAT WAS INVISIBLE. Correct behaviour: the game is real and
          // participation resolved, it is simply further out than
          // PLAN_HORIZON_MS. It will plan on a later tick.
          bump(stats.skipped, "outside_horizon");
          // Now attributable. fireAt is derived from the game start and the
          // config's lead, so it is CONSTANT for a given game — the row dedupes
          // across ticks instead of accumulating one per tick.
          logRows.push({
            uid, teamSlug, eventId, action: "skip", reason: "outside_horizon",
            fireAt: new Date(startFireAt).toISOString(),
          });
        } else if (startInPast) {
          // Fire time already elapsed — a late deploy, a long outage, a start
          // time that moved earlier, or (the 2026-08-13 Dodgers case) a config
          // created AFTER its own fire time. Distinct from beyond-horizon and
          // materially worse, so it must not share a bucket.
          bump(stats.skipped, "start_time_passed");
          // ATTRIBUTABLE. This branch bumped the counter and wrote no row,
          // while `outside_horizon` directly above it wrote one — so the
          // Dodgers cycle reconciled perfectly (21/21) while naming no team,
          // and "which config lost its start?" was unanswerable from the log.
          // Same silent-skip class as #68; the 2026-08-11 "every path must
          // increment something" pass added the counter here and left the row.
          // fireAt is derived from game start + lead, so it is constant for a
          // given game and the row dedupes across ticks.
          logRows.push({
            uid, teamSlug, eventId, action: "skip", reason: "start_time_passed",
            fireAt: new Date(startFireAt).toISOString(),
          });
        }

        // ── END — the guards. GUARD 0 (#66) first: never end a show this
        // system did not start. startPlannedAt is the ONLY evidence that a
        // start job was actually written; it is set inside `if (writeJobs)`
        // beside the create, so it cannot be true for a log-only-era session.
        const decision = decideEndSignal({
          espnIsFinal: game.isFinal,
          state: {
            consecutiveFinalPolls: session.consecutiveFinalPolls,
            endFiredAt: session.endFiredAt,
            gameStartMs: session.gameStartMs ?? game.startMs,
            startPlannedAt: session.startPlannedAt,
          },
          sport,
          nowMs,
        });

        // #66: every stale session the guard catches is free evidence. Counted
        // and logged as its own reason so "the guard is holding" is observable
        // rather than inferred from an absence — the same rule the disposition
        // mirror established: a skip must be legible, not silent.
        // NOTE: no bump here. The else-if below already buckets this as
        // `end:no_start` (reason is neither not_final nor already_fired), and
        // counting it twice would break the stats reconciliation this file has
        // already been burned by once (the 20/19 lastSummary bug).
        if (decision.reason === "no_start") {
          logRows.push({
            uid, teamSlug, eventId, action: "skip",
            reason: "end_skipped_no_start",
          });
        }

        if (writeJobs || session.startPlannedAt) {
          await sRef.set(
            { consecutiveFinalPolls: decision.nextConsecutive, gameStartMs: game.startMs },
            { merge: true }
          );
        }

        // GUARD 0b (#66) — the end is about to fire; confirm the START job this
        // system wrote actually reached the device. One read, only at the
        // moment it matters. A created-but-never-dispatched start leaves the
        // house exactly as a never-started one does.
        if (decision.fireEnd) {
          const startJob = await db
            .collection("users").doc(uid)
            .collection(FIRE_JOBS_COLLECTION).doc(`${eventId}_start`)
            .get();
          if (!startJobConfirmsFired(startJob.data()?.state)) {
            bump(stats.endSkipped, "end:start_never_dispatched");
            logRows.push({
              uid, teamSlug, eventId, action: "skip",
              reason: "end_skipped_start_never_dispatched",
              startJobState: startJob.exists
                ? String(startJob.data()?.state)
                : "missing",
            });
            continue;
          }
        }

        if (decision.fireEnd) {
          logRows.push({
            uid, teamSlug, eventId, action: "plan_end",
            fireAt: new Date(nowMs).toISOString(), reason: decision.reason,
            ...(policy.enabled && !writeJobs ? { scopedOut: true } : {}),
          });
          if (writeJobs) {
            // S4: the end fire returns the house to BASE, not to off — a
            // customer whose everyday schedule is warm white from sunset must
            // get warm white back, not darkness. See baseRestorePayload.
            const restore = baseRestorePayload({
              nowMs,
              latitude: typeof u.get("latitude") === "number" ? u.get("latitude") : null,
              longitude: typeof u.get("longitude") === "number" ? u.get("longitude") : null,
              tzOffsetHours: -5,
            });
            await db
              .collection("users").doc(uid)
              .collection(FIRE_JOBS_COLLECTION).doc(`${eventId}_end`)
              .create({
                eventId, seq: "end",
                controllerId: controller.id,
                fireAt: admin.firestore.Timestamp.fromMillis(nowMs),
                type: "applyJson",
                payload: restore.payload,
                state: "scheduled",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                source: "game_day",
              })
              .catch((e) => {
                if (e.code !== 6 && e.code !== "already-exists") throw e;
              });
            await sRef.set(
              { endFiredAt: admin.firestore.FieldValue.serverTimestamp() },
              { merge: true }
            );
          }
          stats.endsPlanned++;
        } else if (decision.reason !== "not_final" && decision.reason !== "already_fired") {
          // endSkipped, NOT skipped: this config has already been counted once
          // in the START dimension and counting it again there would break
          // `sum(skipped) + startsPlanned === configsEnabled`.
          bump(stats.endSkipped, `end:${decision.reason.split(":")[0]}`);
        }
      } catch (err) {
        stats.errors++;
        logger.error(`planGameDayFires: ${uid}/${teamSlug} failed`, err);
      }
    }
  }

  // The log-only surface. Written every tick that had anything to say, so a
  // full homestand can be reviewed before the flag is ever flipped.
  // WRITTEN UNCONDITIONALLY (2026-08-10).
  //
  // ⚠️ CORRECTED JUSTIFICATION 2026-08-11. The original comment here claimed
  // the log was SILENT on a fully-skipped night and that this collection was
  // empty. **That was wrong.** `gameday_plan_log` has held data since
  // 2026-08-08 and was never empty: participation skips DO produce rows, so
  // the old `logRows.length > 0` gate was satisfied on every real night. The
  // collection only LOOKED empty because the query used `orderBy("at")` while
  // these documents carry `updatedAt` — and Firestore silently DROPS documents
  // missing the orderBy field rather than erroring. The surface was not silent;
  // the query was wrong.
  //
  // The change is still worth keeping, on the narrower and true justification:
  // a per-tick SUMMARY (counts + skip breakdown by category + espnErrors) beats
  // reconstructing those numbers from Cloud Logging log lines, which is
  // error-prone — the 12/5/2 breakdown was misread exactly that way. It also
  // guarantees an artifact on a genuinely row-less tick.
  //
  // The summary is additive: per-row detail is still appended when rows exist.
  const day = new Date(nowMs).toISOString().slice(0, 10);
  const summary = {
    at: admin.firestore.FieldValue.serverTimestamp(),
    usersScanned: stats.usersScanned,
    configsEnabled: stats.configsEnabled,
    startsPlanned: stats.startsPlanned,
    endsPlanned: stats.endsPlanned,
    // Skip reasons by category — the field whose absence cost the most.
    // START phase, one bucket per config. See PlanStats.skipped.
    skipped: stats.skipped,
    // END phase, counted separately so the START sum stays exact.
    endSkipped: stats.endSkipped,
    espnErrors: stats.espnErrors,
    errors: stats.errors,
  };
  await db
    .collection(PLAN_LOG_COLLECTION)
    .doc(day)
    .set(
      {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        // Policy-level, not per-uid: `writeJobs` is whether the flag is armed
        // at all, `writeJobsScope` names who it is armed FOR. A reader of this
        // doc has to be able to tell a global arm from a scoped one.
        writeJobs: policy.enabled,
        writeJobsScope: policy.allowlist === null ? "global" : policy.allowlist,
        // Every tick, planned or not. arrayUnion so a day accumulates the
        // shape of the whole run rather than only its last tick.
        ticks: admin.firestore.FieldValue.arrayUnion(
          JSON.parse(JSON.stringify({ ...summary, at: new Date(nowMs).toISOString() }))
        ),
        ...(logRows.length > 0
          ? { rows: admin.firestore.FieldValue.arrayUnion(...logRows) }
          : {}),
      },
      { merge: true }
    );

  // lastSummary is written SEPARATELY, with update(), and that is load-bearing.
  //
  // ⚠️ THE 20/19 BUG (found 2026-08-11). It was written inside the set(...,
  // {merge:true}) above, and Firestore merges nested maps KEY BY KEY. `bump()`
  // only ever creates keys, so a bucket that stopped occurring was never
  // cleared — it was frozen into lastSummary forever.
  //
  // Exactly what happened that day: for 31 ticks the Royals game sat beyond the
  // horizon (`outside_horizon: 1`). At 19:40Z it came inside, the planner
  // dropped that key and set `startsPlanned: 1` — but the stale
  // `outside_horizon: 1` survived the merge and kept being added to the total.
  // The checker read 20 of 19 and reported an "unaccounted config" that did not
  // exist, and reported a config "waiting on the horizon" when none was.
  //
  // Every one of the 42 per-tick snapshots in `ticks` reconciled 19/19 — the
  // planner's accounting was correct all along; only the merged view lied.
  // update() on a top-level field REPLACES it, so a bucket that stops occurring
  // now disappears. It runs after the set() above, which creates the doc, so
  // there is no missing-document failure mode.
  await db.collection(PLAN_LOG_COLLECTION).doc(day).update({ lastSummary: summary });

  const quiet = stats.configsEnabled === 0;
  if (!quiet) {
    logger.info(
      `planGameDayFires[${
        !policy.enabled
          ? "LOG-ONLY"
          : policy.allowlist === null
            ? "LIVE"
            : `LIVE:scoped(${policy.allowlist.length})`
      }]: ${JSON.stringify(stats)}`
    );
    // Aggregate gate line, alongside the per-account rows rather than instead
    // of them. Advisory is stated separately: today every account carries
    // no_ladder_unknown, so a merged figure would read "10 blocked" when 7 are
    // blocked and the rest are ARMED — a summary that overstates a block sends
    // someone to fix nothing.
    logger.info(formatGateSummary(summarizeGate(gateVerdicts)));
  }
  return { ...stats, logRows };
}

export const planGameDayFires = onSchedule(
  {
    schedule: PLANNER_SCHEDULE,
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    await runPlannerTick(admin.firestore(), Date.now());
  }
);
