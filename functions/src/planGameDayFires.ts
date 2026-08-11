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
import { assertPayloadIsFireSafe, FIRE_JOBS_COLLECTION } from "./fireJobs";
import {
  DEFAULT_LEAD_MINUTES,
  PLAN_HORIZON_MS,
  argbToRgb,
  buildParticipatingSegArray,
  decideEndSignal,
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
  skipped: Record<string, number>;
  espnErrors: number;
  errors: number;
}

const bump = (m: Record<string, number>, k: string) => {
  m[k] = (m[k] ?? 0) + 1;
};

/** Read the write-jobs flag. Defaults FALSE — log-only until deliberately on. */
async function writeJobsEnabled(db: admin.firestore.Firestore): Promise<boolean> {
  try {
    const d = await db.collection("config").doc("gameday_planner").get();
    return d.exists && d.data()?.write_jobs === true;
  } catch (err) {
    logger.warn("planGameDayFires: flag read failed; staying LOG-ONLY", err);
    return false;
  }
}

/**
 * Build the fire payload for a config. Returns the JSON string a fire job
 * carries, or a refusal reason.
 */
export function buildGameDayPayload(args: {
  config: Record<string, unknown>;
  participatingChannels: number[];
}): { payload: string } | { refuse: string } {
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
    return { payload: raw };
  }

  if (args.participatingChannels.length === 0) {
    return { refuse: "no_participating_channels" };
  }

  const primary = typeof c.primary_color === "number" ? c.primary_color : 0xffffffff;
  const secondary =
    typeof c.secondary_color === "number" ? c.secondary_color : 0xffffffff;

  const seg = buildParticipatingSegArray({
    participatingChannelIds: args.participatingChannels,
    effectId: typeof c.effect_id === "number" ? c.effect_id : 0,
    speed: typeof c.speed === "number" ? c.speed : 128,
    intensity: typeof c.intensity === "number" ? c.intensity : 128,
    colorSlots: toRgbwSlots([argbToRgb(primary), argbToRgb(secondary)]),
  });

  return {
    payload: JSON.stringify({
      on: true,
      bri: typeof c.brightness === "number" ? c.brightness : 200,
      seg,
    }),
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
  opts: { onlyUid?: string; forceWriteJobs?: boolean } = {}
): Promise<PlanStats & { logRows: Array<Record<string, unknown>> }> {
  const writeJobs = opts.forceWriteJobs ?? (await writeJobsEnabled(db));
  const stats: PlanStats = {
    usersScanned: 0,
    configsEnabled: 0,
    startsPlanned: 0,
    endsPlanned: 0,
    skipped: {},
    espnErrors: 0,
    errors: 0,
  };
  const logRows: Array<Record<string, unknown>> = [];

  const users = await db.collection("users").get(); // scope COLLECTION, no index
  const gameCache = new Map<string, EspnGame | null>();

  for (const u of users.docs) {
    const uid = u.id;
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

    for (const cfgDoc of configs.docs) {
      stats.configsEnabled++;
      const c = cfgDoc.data();
      const teamSlug = cfgDoc.id;
      const sport = String(c.sport ?? "");
      const espnTeamId = String(c.espn_team_id ?? "");

      try {
        if (!controller) {
          bump(stats.skipped, "no_controller");
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
        } else if (startInPast) {
          // Fire time already elapsed — a late deploy, a long outage, or a
          // start time that moved earlier. Distinct from beyond-horizon and
          // materially worse, so it must not share a bucket.
          bump(stats.skipped, "start_time_passed");
        }

        // ── END — the three guards ───────────────────────────────────────
        const decision = decideEndSignal({
          espnIsFinal: game.isFinal,
          state: {
            consecutiveFinalPolls: session.consecutiveFinalPolls,
            endFiredAt: session.endFiredAt,
            gameStartMs: session.gameStartMs ?? game.startMs,
          },
          sport,
          nowMs,
        });

        if (writeJobs || session.startPlannedAt) {
          await sRef.set(
            { consecutiveFinalPolls: decision.nextConsecutive, gameStartMs: game.startMs },
            { merge: true }
          );
        }

        if (decision.fireEnd) {
          logRows.push({
            uid, teamSlug, eventId, action: "plan_end",
            fireAt: new Date(nowMs).toISOString(), reason: decision.reason,
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
          bump(stats.skipped, `end:${decision.reason.split(":")[0]}`);
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
    skipped: stats.skipped,
    espnErrors: stats.espnErrors,
    errors: stats.errors,
  };
  await db
    .collection(PLAN_LOG_COLLECTION)
    .doc(day)
    .set(
      {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        writeJobs,
        // Every tick, planned or not. arrayUnion so a day accumulates the
        // shape of the whole run rather than only its last tick.
        ticks: admin.firestore.FieldValue.arrayUnion(
          JSON.parse(JSON.stringify({ ...summary, at: new Date(nowMs).toISOString() }))
        ),
        lastSummary: summary,
        ...(logRows.length > 0
          ? { rows: admin.firestore.FieldValue.arrayUnion(...logRows) }
          : {}),
      },
      { merge: true }
    );

  const quiet = stats.configsEnabled === 0;
  if (!quiet) {
    logger.info(
      `planGameDayFires[${writeJobs ? "LIVE" : "LOG-ONLY"}]: ${JSON.stringify(stats)}`
    );
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
