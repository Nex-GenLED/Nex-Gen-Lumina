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
 *   B1/B2 (2026-10-02), allowlisted accounts only:
 *   4. bridge_registry .where("pairedUid","==",uid).limit(1)       (P1)
 *        scope COLLECTION, single-field equality → automatic index (the same
 *        query relayEligibility already runs in production)
 *   5. users/{uid}/debug_errors .orderBy("timestamp","desc").limit(25)  (P7)
 *        scope COLLECTION, single-field order → automatic index; the context
 *        filter is applied in memory precisely so no composite is needed
 *   6. users/{uid}/commands .where("status","in",[pending,executing])  (P6)
 *        scope COLLECTION, single-field `in` → automatic index (as the probe)
 *   7. users/{uid}/fire_jobs .where("state","==","scheduled")      (B2 next_fire)
 *        scope COLLECTION, single-field equality → automatic index
 *   ESPN slate fix (2026-10-02), only with `track_started_by_id` on:
 *   8. users/{uid}/game_day_sessions .where("gameStartMs",">=",now − 12 h)
 *        scope COLLECTION, single-field range → automatic index. One query per
 *        account with an enabled config and a controller, per tick.
 *
 * ─── ESPN FLAGS (config/gameday_planner, each default OFF) ──────────────────
 *   espn_college_slate   college football from the dated FBS slate, not the
 *                        featured list (espnClient.fetchCollegeSlateGame)
 *   track_started_by_id  a started, not-ended session follows its own game by
 *                        id (espnClient.fetchEventById) until its end fires
 *   status_aware_cap     the hard cap is held while ESPN says the game is on,
 *                        up to the sport's ceiling (gameDayPlanning)
 * Only exactly `true` turns one on. With all three off the planner makes the
 * same decisions and the same writes it made before them; the one difference
 * is the per-tick URL cache (fewer identical ESPN requests) and the
 * `espnFetches` count it reports in the tick summary.
 *
 * ─── BRIDGE WRITE-GAP FLAGS (2026-10-05, each default OFF, `true` | uid list) ─
 *   preflight_bridge_grace  fix A: P2's heartbeat window is 15 min, not 5
 *   served_sticky           B2 sticky: `gameday_server.served` stays true
 *                           through a P2 failure shorter than 30 min; the state
 *                           is `gameday_server.stale_since`
 * See gameDayPreflight (decideServedSticky). With both absent nothing here
 * reads or writes anything it did not before.
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
import {
  assertPayloadIsFireSafe,
  endRetryUntilMs,
  FIRE_JOBS_COLLECTION,
  startRetryUntilMs,
  teamSlugFromEventId,
} from "./fireJobs";
import {
  LadderLitMode,
  LadderLitSetting,
  NextFire,
  PreflightMode,
  PreflightVerdict,
  PREFLIGHT_PROBE_ID_PREFIX,
  PREFLIGHT_PROBE_SOURCE,
  SCORECARD_COLLECTION,
  SCORECARD_ENTRIES,
  ServerStatusCore,
  bridgeGraceScopeFrom,
  bridgeStaleMsFor,
  decideP6,
  decideServedSticky,
  evaluatePreflight,
  ladderDarkChannels,
  ladderLitModeFor,
  ladderLitSettingFrom,
  p6HoldsAccount,
  p6RecordFrom,
  preflightModeFrom,
  publishServerStatusFrom,
  scorecardDateKey,
  scorecardEntryId,
  serverStatusKey,
  servedStickyScopeFrom,
  storedServerStatusKey,
} from "./gameDayPreflight";
import { hasPairedBridge } from "./relayEligibility";
import { probeOneController } from "./probeControllerHealth";
import {
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
  capBoundMs,
  capCeilingMs,
  espnReportsLive,
  CAP_RELEASE_STATUS_NAMES,
  gameDayPaletteFor,
  FlagScope,
  flagOnFor,
  flagScopeFrom,
} from "./gameDayPlanning";
import {
  EspnCache,
  EspnGame,
  fetchCollegeSlateGame,
  fetchCollegeTeamDivision,
  fetchEventById,
  fetchTeamGame,
  defaultScoreboardAnswered,
} from "./espnClient";
import {
  TeamRow,
  TeamWindow,
  deriveTeamPriority,
  handoffWinner,
  leadMinutesFor,
  orderByPriority,
  outrankedBy,
  profileNamesFrom,
  rankOf,
  startDecision,
  tzOffsetResolverFor,
  windowEndMs,
  windowStartFor,
} from "./gameDayHierarchy";

// admin.initializeApp() is called in index.js — do not call again here.

/**
 * Every 5 minutes.
 *
 * Two requirements pull in opposite directions and 5 satisfies both:
 *   - A start job must EXIST before the dispatcher needs it. The dispatcher
 *     ticks every minute and (before A2's retry budget) refused a job more
 *     than 90 s late (MAX_FIRE_LATENESS),
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
   * Ends that HANDED OFF the house to another team's design instead of
   * restoring base. A subset of `endsPlanned` — an end was planned either way.
   */
  handoffsPlanned: number;
  /**
   * Ends ESPN never confirmed: the hard cap fired at start + estimatedDuration
   * + 60 min. A subset of `endsPlanned`. Non-zero means the feed let a game run
   * out — worth reading, because every one is a game the house would otherwise
   * have held in team colours indefinitely.
   */
  hardCapsPlanned: number;
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
  /**
   * B1. Allowlisted, gate-armed accounts whose NEW starts pre-flight withheld
   * this tick (enforce mode), plus P6 skips of an already-minted start. Not a
   * START bucket: the config still counts once in `skipped`/`startsPlanned`.
   */
  preflightSkips: number;
  /** B1. The same failures in observe mode — logged, nothing withheld. */
  preflightObserved: number;
  /** B1 P6. Reachability probes written this tick. */
  p6Probes: number;
  /** B2. users/{uid}.gameday_server writes this tick. */
  serverStatusWrites: number;
  /**
   * B2 sticky (`served_sticky`). Accounts whose `served` was HELD true this
   * tick through a bridge write gap. Present only when non-zero, so a tick
   * with the flag off (or nothing held) has exactly the summary it always had.
   */
  servedHeld?: number;
  espnErrors: number;
  /**
   * Distinct ESPN URLs requested this tick — one request each, whatever the
   * number of accounts and teams that read it (the per-tick URL cache). The
   * production read-back for the rate question.
   */
  espnFetches: number;
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

/**
 * The three ESPN slate-fix flags, as SCOPES (#157): each field is exactly
 * `true` (every account) or a uid list (only those accounts); anything else is
 * off. See gameDayPlanning.flagScopeFrom and the file header.
 */
export interface EspnFlags {
  espnCollegeSlate: FlagScope | null;
  trackStartedById: FlagScope | null;
  statusAwareCap: FlagScope | null;
}

export const ESPN_FLAGS_OFF: EspnFlags = {
  espnCollegeSlate: null,
  trackStartedById: null,
  statusAwareCap: null,
};

/**
 * PURE. Absent, `false`, `"true"`, `1`, a malformed list — off. A deploy
 * therefore changes nothing until the owner writes a field, and a malformed
 * write disarms rather than arms (or widens).
 */
export function espnFlagsFrom(data: Record<string, unknown> | undefined): EspnFlags {
  return {
    espnCollegeSlate: flagScopeFrom(data?.espn_college_slate),
    trackStartedById: flagScopeFrom(data?.track_started_by_id),
    statusAwareCap: flagScopeFrom(data?.status_aware_cap),
  };
}

/** The ESPN flags as they apply to ONE account this tick. */
export interface EspnFlagsForUid {
  espnCollegeSlate: boolean;
  trackStartedById: boolean;
  statusAwareCap: boolean;
}

export function espnFlagsFor(flags: EspnFlags, uid: string): EspnFlagsForUid {
  return {
    espnCollegeSlate: flagOnFor(flags.espnCollegeSlate, uid),
    trackStartedById: flagOnFor(flags.trackStartedById, uid),
    statusAwareCap: flagOnFor(flags.statusAwareCap, uid),
  };
}

/** Everything the planner reads from `config/gameday_planner`, once per tick. */
export interface PlannerFlags {
  policy: WriteJobsPolicy;
  /** B2 — write users/{uid}.gameday_server. Default true. */
  publishServerStatus: boolean;
  /** B1 — enforce (default) or observe. */
  preflightMode: PreflightMode;
  /** The ESPN slate fix. All default off. */
  espn: EspnFlags;
  /** P4b (#146), `preflight_ladder_lit`. Default off. */
  ladderLit: LadderLitSetting;
  /**
   * `payload_full_state` (true or a uid list; default off): the start and
   * hand-off payloads state every segment field the app's Game Day paths do
   * (gameDayPlanning, "Full segment state").
   */
  payloadFullState: FlagScope | null;
  /**
   * `preflight_bridge_grace` (true or a uid list; default off): fix A, P2's
   * window is 15 min instead of 5 (gameDayPreflight.bridgeStaleMsFor).
   */
  preflightBridgeGrace: FlagScope | null;
  /**
   * `served_sticky` (true or a uid list; default off): B2 sticky, `served`
   * rides through a P2 failure shorter than 30 min
   * (gameDayPreflight.decideServedSticky).
   */
  servedSticky: FlagScope | null;
}

/** A forced P4b mode (tests, bench) in the production field's terms. */
function forcedLadderLit(v: LadderLitMode | string[] | undefined): LadderLitSetting {
  if (v === "strict") return "strict";
  if (v === "on") return { all: true };
  return Array.isArray(v) ? flagScopeFrom(v) : null;
}

/**
 * A flag field that is PRESENT but parses as off (a typo, `"true"`, a list
 * with a number in it) is almost certainly an attempted flip that did not
 * take. Logged so it is seen; never armed.
 */
function warnMalformedFlags(data: Record<string, unknown> | undefined): void {
  for (const key of [
    "espn_college_slate", "track_started_by_id", "status_aware_cap", "payload_full_state",
    "preflight_bridge_grace", "served_sticky",
  ]) {
    const v = data?.[key];
    if (v !== undefined && v !== false && flagScopeFrom(v) === null) {
      logger.warn(`planGameDayFires: config/gameday_planner.${key} is malformed (want true or [uid, …]); OFF. Value: ${JSON.stringify(v)}`);
    }
  }
  const lit = data?.preflight_ladder_lit;
  if (lit !== undefined && lit !== false && ladderLitSettingFrom(data) === null) {
    logger.warn(`planGameDayFires: config/gameday_planner.preflight_ladder_lit is malformed (want true, "strict" or [uid, …]); OFF. Value: ${JSON.stringify(lit)}`);
  }
}

/**
 * Read the flags. Defaults: write-jobs OFF (log-only until deliberately on),
 * publish ON, pre-flight ENFORCE, every ESPN flag, P4b and both bridge
 * write-gap flags OFF. A read failure
 * keeps log-only AND stops the status publish for that tick: a transient error
 * must not flip every account to `served:false` — the app's staleness window
 * covers a longer outage.
 */
async function readPlannerFlags(db: admin.firestore.Firestore): Promise<PlannerFlags> {
  try {
    const d = await db.collection("config").doc("gameday_planner").get();
    const data = d.exists ? d.data() : undefined;
    warnMalformedFlags(data);
    return {
      policy: d.exists ? writeJobsPolicyFrom(data) : WRITE_JOBS_OFF,
      publishServerStatus: publishServerStatusFrom(data),
      preflightMode: preflightModeFrom(data),
      espn: espnFlagsFrom(data),
      ladderLit: ladderLitSettingFrom(data),
      payloadFullState: flagScopeFrom(data?.payload_full_state),
      preflightBridgeGrace: bridgeGraceScopeFrom(data),
      servedSticky: servedStickyScopeFrom(data),
    };
  } catch (err) {
    logger.warn("planGameDayFires: flag read failed; staying LOG-ONLY", err);
    return {
      policy: WRITE_JOBS_OFF,
      publishServerStatus: false,
      preflightMode: "enforce",
      espn: ESPN_FLAGS_OFF,
      ladderLit: null,
      payloadFullState: null,
      preflightBridgeGrace: null,
      servedSticky: null,
    };
  }
}

/**
 * How far back a session's `gameStartMs` may lie and still be tracked by id.
 * Longer than any sport's cap ceiling (gameDayPlanning.CAP_CEILING_MS, 7 h at
 * most), so a tracked game stays in view until its end or its cap fires; a
 * session older than this is left to the scoreboard path, as before.
 */
export const TRACK_LOOKBACK_MS = 12 * 3600_000;

/** A started, not-ended session the planner follows by its ESPN id. */
export interface TrackedSession {
  eventId: string;
  gameId: string;
  gameStartMs: number;
}

/**
 * PURE. From the sessions query (#8), the session each enabled team should
 * follow: `startPlannedAt` set (this system started it, or handed the house to
 * it), `endFiredAt` unset, `gameStartMs` known, and an id of the form
 * `gd_<slug>_<gameId>` for an enabled slug. Two open sessions for one team
 * (a doubleheader) → the earlier game, which ends first.
 */
export function openSessionsByTeam(
  sessions: Array<{ id: string; data: Record<string, unknown> }>,
  enabledSlugs: string[]
): Map<string, TrackedSession> {
  const out = new Map<string, TrackedSession>();
  for (const s of sessions) {
    const d = s.data;
    if (d.startPlannedAt === null || d.startPlannedAt === undefined) continue;
    if (d.endFiredAt !== null && d.endFiredAt !== undefined) continue;
    if (typeof d.gameStartMs !== "number") continue;
    for (const slug of enabledSlugs) {
      const prefix = `gd_${slug}_`;
      if (!s.id.startsWith(prefix)) continue;
      const gameId = s.id.slice(prefix.length);
      // A longer slug sharing this prefix (nfl_a vs nfl_a_b) leaves an
      // underscore in the remainder; ESPN game ids are digits.
      if (gameId.length === 0 || gameId.includes("_")) continue;
      const prior = out.get(slug);
      if (
        prior === undefined ||
        d.gameStartMs < prior.gameStartMs ||
        (d.gameStartMs === prior.gameStartMs && s.id < prior.eventId)
      ) {
        out.set(slug, { eventId: s.id, gameId, gameStartMs: d.gameStartMs });
      }
    }
  }
  return out;
}

/**
 * How a config's game was found this tick. `via` is "default" for every read
 * the planner made before the ESPN flags existed.
 */
interface ResolvedGame {
  game: EspnGame | null;
  via: "default" | "college_slate" | "tracked";
  /**
   * The game is a CLOCK-ONLY stand-in for a started session (its kickoff,
   * nothing final, no status). "silent": ESPN answered and the game is not in
   * it (single-game 404, or a full scoreboard / slate without it).
   * "unavailable" (#159): ESPN could not be read for it this tick.
   */
  espnState?: "silent" | "unavailable";
  /** College slate: every date answered 2xx with an events array. */
  answered?: boolean;
  /** College slate read in full, the id never on it, and ESPN says it is not FBS. */
  notOnSlate?: string;
}

/**
 * B1 — the I/O half of pre-flight for one account: P1 (registry), P2 (heartbeat
 * update time), P7 (last app version). Every read fails SOFT: an error makes
 * P1 pass (fail open, the relay predicate's rule), P2 read as no heartbeat,
 * and P7 unknown. The decision itself is gameDayPreflight.evaluatePreflight.
 */
async function readPreflightFacts(
  db: admin.firestore.Firestore,
  uid: string
): Promise<{
  bridgePaired: boolean | null;
  bridgeStatusUpdateMs: number | null;
  bridgeFw: string | null;
  appVersion: string | null;
}> {
  let bridgePaired: boolean | null = null;
  try {
    bridgePaired = await hasPairedBridge(db, uid);
  } catch (err) {
    logger.warn(`planGameDayFires: preflight P1 lookup failed for ${uid}; failing open`, err);
  }
  let bridgeStatusUpdateMs: number | null = null;
  let bridgeFw: string | null = null;
  try {
    const bs = await db.collection("users").doc(uid).collection("bridge_status").doc("current").get();
    if (bs.exists) {
      bridgeStatusUpdateMs = bs.updateTime ? bs.updateTime.toMillis() : null;
      const v = bs.get("version");
      bridgeFw = typeof v === "string" ? v : null;
    }
  } catch (err) {
    logger.warn(`planGameDayFires: preflight P2 read failed for ${uid}`, err);
  }
  let appVersion: string | null = null;
  try {
    // The routing-diagnostics batches carry app_version. No composite index:
    // newest 25 by the single-field timestamp index, filtered in memory.
    const recent = await db
      .collection("users").doc(uid).collection("debug_errors")
      .orderBy("timestamp", "desc").limit(25).get();
    for (const d of recent.docs) {
      if (d.get("context") === "routing_decisions" && typeof d.get("app_version") === "string") {
        appVersion = d.get("app_version") as string;
        break;
      }
    }
  } catch (err) {
    logger.warn(`planGameDayFires: preflight P7 read failed for ${uid}`, err);
  }
  return { bridgePaired, bridgeStatusUpdateMs, bridgeFw, appVersion };
}

/** B3 — one scorecard entry, merged. Never throws: observability must not stop planning. */
async function mergeScorecard(
  db: admin.firestore.Firestore,
  dateKey: string,
  uid: string,
  eventId: string,
  data: Record<string, unknown>
): Promise<void> {
  try {
    const day = db.collection(SCORECARD_COLLECTION).doc(dateKey);
    await day.set(
      { date: dateKey, updated_at: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    await day
      .collection(SCORECARD_ENTRIES)
      .doc(scorecardEntryId(uid, eventId))
      .set({ ...data, updated_at: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  } catch (err) {
    logger.warn(`planGameDayFires: scorecard write failed for ${uid}/${eventId}`, err);
  }
}

/** The reserved / zeroed fields every new scorecard entry starts with. */
function scorecardSkeleton(): Record<string, unknown> {
  return {
    controllers_fired: 0,
    // E (Policy B re-assert) is not built; zeroes, so a reader never sees undefined.
    reasserts: { planned: 0, completed: 0, user_override: 0 },
    // G (server celebrations) is not built.
    celebrations: null,
    stuck_executing_count: 0,
    // C (app build 114, #150) owns these; null = not measured, never "zero".
    lease_residue_rows: null,
    app_foreground_during_game: null,
  };
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
  /**
   * `payload_full_state`: every participating segment states pal grp spc bri
   * frz and three colour slots; an excluded one adds frz:false. A saved design
   * is unaffected (it carries its own shape). Absent/false = the shipped shape.
   */
  fullState?: boolean;
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

  const effectId = typeof c.effect_id === "number" ? c.effect_id : 0;
  const look = {
    effectId,
    speed: typeof c.speed === "number" ? c.speed : 128,
    intensity: typeof c.intensity === "number" ? c.intensity : 128,
    colorSlots: toRgbwSlots([argbToRgb(primary), argbToRgb(secondary)]),
    ...(args.fullState === true ? { fullState: { palette: gameDayPaletteFor(effectId) } } : {}),
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

/**
 * B1 P6 — one step of the reachability check for one event (gameDayPreflight
 * .decideP6 decides; this does the reads and writes). Called at mint and on
 * every later tick while this system's start is still `scheduled`.
 *
 * `unreachable` in ENFORCE mode skips the start (state `skipped`, never
 * `cancelled`: per the #98 convention `cancelled` means a HUMAN retracted a
 * fire; this is the system declining). The skip is transactional on the job
 * still being `scheduled`, so a start the dispatcher already fired is never
 * rewritten. In OBSERVE mode the verdict is recorded and logged and nothing is
 * skipped.
 */
async function stepP6(a: {
  db: admin.firestore.Firestore;
  uid: string;
  eventId: string;
  teamSlug: string;
  sRef: admin.firestore.DocumentReference;
  controller: admin.firestore.QueryDocumentSnapshot;
  controllersTotal: number;
  record: ReturnType<typeof p6RecordFrom>;
  startFireAtMs: number;
  nowMs: number;
  mode: PreflightMode;
  bridgePaired: boolean | null;
  scorecardKey: string | null;
  logRows: Array<Record<string, unknown>>;
  stats: PlanStats;
}): Promise<void> {
  const { db, uid, eventId, teamSlug, sRef, nowMs } = a;
  try {
    if (a.record?.verdict === "ok" || a.record?.verdict === "unreachable") return;
    const startRef = db.collection("users").doc(uid)
      .collection(FIRE_JOBS_COLLECTION).doc(`${eventId}_start`);
    const startSnap = await startRef.get();
    if (startSnap.get("state") !== "scheduled") return;

    const cmds = db.collection("users").doc(uid).collection("commands");
    const statuses: Array<string | null> = [];
    for (const p of a.record?.probes ?? []) {
      const d = await cmds.doc(p.commandId).get();
      statuses.push(d.exists ? String(d.get("status")) : null);
    }
    const action = decideP6({
      record: a.record,
      statuses,
      nowMs,
      startFireAtMs: a.startFireAtMs,
    });

    if (action.kind === "wait" || action.kind === "too_close") return;

    if (action.kind === "ok") {
      await sRef.set(
        { preflight_p6: { probes: a.record?.probes ?? [], verdict: "ok" } },
        { merge: true }
      );
      return;
    }

    if (action.kind === "write_probe") {
      const inflight = await cmds.where("status", "in", ["pending", "executing"]).get();
      const ipRaw = a.controller.get("ip");
      const res = await probeOneController({
        db, uid,
        controllerId: a.controller.id,
        controllerIp: typeof ipRaw === "string" && ipRaw.length > 0 ? ipRaw : null,
        totalControllersForUser: a.controllersTotal,
        pendingCommands: inflight.docs.map((d) => ({
          controllerId: d.get("controllerId"),
          status: d.get("status"),
          createdAt: d.get("createdAt") ?? null,
        })),
        nowMs,
        // P1's own answer (a lookup error fails open as paired).
        bridgePaired: a.bridgePaired !== false,
        // A Game Day check, not health monitoring: the exclusion flag is for
        // digests and the daily cadence, not for "can tonight's fire land".
        monitoringExcluded: false,
        source: PREFLIGHT_PROBE_SOURCE,
        skipBackoff: true,
        idPrefix: PREFLIGHT_PROBE_ID_PREFIX,
      });
      if (!res.commandId) {
        // in_flight / unresolvable_target / no_paired_bridge: try next tick.
        a.logRows.push({ uid, teamSlug, eventId, action: "preflight_probe_deferred", reason: res.reason });
        return;
      }
      const keep = action.n === 1 ? [] : (a.record?.probes ?? []).slice(0, 1);
      await sRef.set(
        {
          preflight_p6: {
            probes: [...keep, { commandId: res.commandId, writtenAtMs: nowMs }],
            verdict: "pending",
          },
        },
        { merge: true }
      );
      if (res.written) a.stats.p6Probes++;
      return;
    }

    // unreachable — two consecutive failures, five minutes apart.
    await sRef.set(
      {
        preflight_p6: { probes: a.record?.probes ?? [], verdict: "unreachable" },
        served: false,
        served_reason: "preflight_controller_unreachable",
      },
      { merge: true }
    );
    if (a.mode === "observe") {
      a.logRows.push({
        uid, teamSlug, eventId, action: "preflight_skip",
        reason: "preflight_controller_unreachable", observeOnly: true,
      });
      a.stats.preflightObserved++;
      return;
    }
    const skipped = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(startRef);
      if (fresh.get("state") !== "scheduled") return false;
      tx.update(startRef, {
        state: "skipped",
        skipReason: "preflight_controller_unreachable",
        skippedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!skipped) return;
    a.logRows.push({
      uid, teamSlug, eventId, action: "preflight_skip",
      reason: "preflight_controller_unreachable",
    });
    a.stats.preflightSkips++;
    if (a.scorecardKey) {
      await mergeScorecard(db, a.scorecardKey, uid, eventId, {
        served: false,
        preflight_ok: false,
        preflight_reasons: admin.firestore.FieldValue.arrayUnion("preflight_controller_unreachable"),
        start: { state: "skipped", outcome: "preflight_controller_unreachable" },
      });
    }
  } catch (err) {
    // P6 is a check, never a reason to stop planning. A failed step retries
    // on the next tick; the start stands.
    logger.warn(`planGameDayFires: P6 step failed for ${uid}/${eventId}`, err);
  }
}

export async function runPlannerTick(
  db: admin.firestore.Firestore,
  nowMs: number,
  opts: {
    onlyUid?: string;
    forceWriteJobs?: boolean;
    forcePolicy?: WriteJobsPolicy;
    /**
     * Overrides for the B1/B2 flags, the ESPN flags and P4b when the policy is
     * forced (tests, bench). Each ESPN flag and P4b defaults OFF, as in
     * production with the field absent. An ESPN flag takes the production
     * field's shapes: `true` (every account) or a uid list (#157).
     */
    forceFlags?: {
      publishServerStatus?: boolean;
      preflightMode?: PreflightMode;
      espnCollegeSlate?: boolean | string[];
      trackStartedById?: boolean | string[];
      statusAwareCap?: boolean | string[];
      ladderLit?: LadderLitMode | string[];
      payloadFullState?: boolean | string[];
      /** Fix A, `preflight_bridge_grace`: `true` or a uid list. Default off. */
      preflightBridgeGrace?: boolean | string[];
      /** B2 sticky, `served_sticky`: `true` or a uid list. Default off. */
      servedSticky?: boolean | string[];
    };
  } = {}
): Promise<PlanStats & { logRows: Array<Record<string, unknown>> }> {
  // Policy, not a boolean: `write_jobs` can be armed globally or scoped to a
  // uid allowlist. forceWriteJobs is kept for existing callers/tests and means
  // "globally armed". A forced policy takes the documented flag DEFAULTS
  // (publish on, pre-flight enforce) unless forceFlags says otherwise — the
  // production path, not a test-only shape.
  const forced =
    opts.forcePolicy !== undefined || opts.forceWriteJobs !== undefined;
  const flags: PlannerFlags = forced
    ? {
        policy:
          opts.forcePolicy ?? { enabled: opts.forceWriteJobs === true, allowlist: null },
        publishServerStatus: opts.forceFlags?.publishServerStatus ?? true,
        preflightMode: opts.forceFlags?.preflightMode ?? "enforce",
        espn: {
          espnCollegeSlate: flagScopeFrom(opts.forceFlags?.espnCollegeSlate),
          trackStartedById: flagScopeFrom(opts.forceFlags?.trackStartedById),
          statusAwareCap: flagScopeFrom(opts.forceFlags?.statusAwareCap),
        },
        ladderLit: forcedLadderLit(opts.forceFlags?.ladderLit),
        payloadFullState: flagScopeFrom(opts.forceFlags?.payloadFullState),
        preflightBridgeGrace: flagScopeFrom(opts.forceFlags?.preflightBridgeGrace),
        servedSticky: flagScopeFrom(opts.forceFlags?.servedSticky),
      }
    : await readPlannerFlags(db);
  const policy: WriteJobsPolicy = flags.policy;
  const stats: PlanStats = {
    usersScanned: 0,
    configsEnabled: 0,
    startsPlanned: 0,
    endsPlanned: 0,
    handoffsPlanned: 0,
    hardCapsPlanned: 0,
    skipped: {},
    endSkipped: {},
    preflightSkips: 0,
    preflightObserved: 0,
    p6Probes: 0,
    serverStatusWrites: 0,
    espnErrors: 0,
    espnFetches: 0,
    errors: 0,
  };
  const logRows: Array<Record<string, unknown>> = [];
  // The SINGLE source for both the per-account gate rows and the aggregate
  // tick line. Summarising a second pass over the inputs is how a summary and
  // its own detail rows come to disagree.
  const gateVerdicts: GateVerdict[] = [];

  const users = await db.collection("users").get(); // scope COLLECTION, no index
  const gameCache = new Map<string, EspnGame | null>();
  // ONE request per ESPN URL per tick, shared by every account and team (the
  // default scoreboard was fetched once per distinct sport/team before).
  const espnCache: EspnCache = new Map();
  // Flagged reads, cached at the same tick level: the college pick per team id,
  // the single-game lookup per sport/game.
  const collegeCache = new Map<string, ResolvedGame>();
  const trackedCache = new Map<string, ResolvedGame | null>();

  for (const u of users.docs) {
    const uid = u.id;
    // Per-uid arming. A scoped-out account still runs the whole planner and
    // still logs what WOULD have been planned — the dry-run corpus must keep
    // growing for the eventual global audit, which is the only thing that can
    // clear F1 (the end path has never executed) fleet-wide.
    const allowlisted = writesJobsFor(policy, uid);
    // #157: each ESPN flag is fleet-wide (`true`) or a uid list; resolved per
    // account. With every field absent all three are false here.
    const espnOn = espnFlagsFor(flags.espn, uid);
    const fullStateOn = flagOnFor(flags.payloadFullState, uid);
    if (opts.onlyUid && uid !== opts.onlyUid) continue;
    const udata = u.data() || {};

    const configs = await db
      .collection("users")
      .doc(uid)
      .collection("game_day_autopilot")
      .where("enabled", "==", true) // COLLECTION scope → automatic index
      .get();
    if (configs.empty) {
      // B2: an account the server WAS serving, whose last team was disabled
      // or deleted, must stop saying so now — not when the app's staleness
      // window lapses. Only accounts carrying served:true pay a write.
      const prior = udata.gameday_server as Record<string, unknown> | undefined;
      if (flags.publishServerStatus && prior?.served === true) {
        try {
          await u.ref.update({
            "gameday_server.served": false,
            "gameday_server.teams": [],
            "gameday_server.next_fire": null,
            "gameday_server.checked_at": admin.firestore.FieldValue.serverTimestamp(),
            // B2 sticky: no pre-flight runs for an account with no team, so a
            // stale run cannot be continuing. Only a doc that carries the
            // field pays for its removal (never one, with the flag never on).
            ...(prior.stale_since !== undefined
              ? { "gameday_server.stale_since": admin.firestore.FieldValue.delete() }
              : {}),
          });
          stats.serverStatusWrites++;
        } catch (_) {
          /* a failed status write must never stop planning */
        }
      }
      continue;
    }
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
    // The R1 floor check and its `/users/{uid}/schedules` probe were removed
    // 2026-08-26. That read ran per account per tick purely to feed R1, so it
    // goes with it rather than lingering as an unused cost.
    const cdata = controller?.data() || {};
    const gate = evaluateAccountReadiness({
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

    // ── THE HIERARCHY (defect 1 — +106's missing server half) ─────────
    // The app decides which team's game owns the house from the user's
    // ordered slug list. Until now the planner read neither priority field
    // and planned every team alone. Rank is derived exactly as the app's
    // heal-on-read does (stored slugs → profile names → remaining configs),
    // so an account that has not opened Game Day since +106 ranks the same
    // way here as it does in the app's memory. See gameDayHierarchy.ts.
    const priority = deriveTeamPriority({
      storedSlugs: udata.game_day_team_priority,
      profileNames: profileNamesFrom(udata),
      configs: configs.docs.map(
        (d): TeamRow => ({
          slug: d.id,
          teamName:
            typeof d.get("team_name") === "string" ? (d.get("team_name") as string) : null,
        })
      ),
    });
    // Walk the hierarchy, not document-id order — orderConfigsByPriority's
    // reason: the #1 team must plan first so a lower team evaluated on the
    // same tick sees it holding the house and defers.
    const orderedDocs = orderByPriority(configs.docs, priority, (d) => d.id);

    // ESPN, cached per (sport, team) across users — unchanged; lifted into a
    // closure so the pre-pass and the loop share one read and one error count.
    const gameFor = async (sport: string, espnTeamId: string): Promise<EspnGame | null> => {
      const key = `${sport}/${espnTeamId}`;
      if (!gameCache.has(key)) {
        try {
          gameCache.set(key, await fetchTeamGame(sport, espnTeamId, espnCache));
        } catch (err) {
          gameCache.set(key, null);
          stats.espnErrors++;
          logger.warn(`planGameDayFires: ESPN failed for ${key}`, err);
        }
      }
      return gameCache.get(key) ?? null;
    };

    // ── Started, not-ended sessions (query #8) ───────────────────────────
    // Read once per account per tick when `track_started_by_id` (follow the
    // game by id) or `status_aware_cap` (#159: the clock guarantee) is on for
    // this account, and only with a controller to fire into (without one no
    // config reaches ESPN at all). A failed read finds nothing this tick: every
    // team falls back to the scoreboard, which is the pre-flag behaviour.
    let openSessions = new Map<string, TrackedSession>();
    if ((espnOn.trackStartedById || espnOn.statusAwareCap) && controller) {
      try {
        const open = await db
          .collection("users").doc(uid).collection(SESSION_COLLECTION)
          .where("gameStartMs", ">=", nowMs - TRACK_LOOKBACK_MS) // COLLECTION scope → automatic index
          .get();
        openSessions = openSessionsByTeam(
          open.docs.map((d) => ({ id: d.id, data: d.data() as Record<string, unknown> })),
          configs.docs.map((d) => d.id)
        );
      } catch (err) {
        logger.warn(`planGameDayFires: open-session read failed for ${uid}; scoreboard only`, err);
      }
    }

    /** A started session's game with nothing known but its kickoff (#159). */
    const clockGame = (t: TrackedSession): EspnGame => ({
      gameId: t.gameId, startMs: t.gameStartMs,
      isFinal: false, isInProgress: false, statusName: "", statusState: "",
      homeTeamId: "", awayTeamId: "",
    });

    // A started game, followed by id (track_started_by_id). Cached per
    // sport/game across accounts. ESPN 404 = the game is gone ("silent"): the
    // session's own kickoff stands in, nothing is final, and the cap decides.
    // Any other failure answers null and the caller falls back to the
    // scoreboard — tracking only ever adds information.
    const trackedGame = async (sport: string, t: TrackedSession): Promise<ResolvedGame | null> => {
      const key = `${sport}/${t.gameId}`;
      if (!trackedCache.has(key)) {
        const r = await fetchEventById(sport, t.gameId, espnCache);
        if (r.kind === "found") {
          trackedCache.set(key, { game: r.game, via: "tracked" });
        } else if (r.kind === "absent") {
          trackedCache.set(key, { game: clockGame(t), via: "tracked", espnState: "silent" });
        } else {
          stats.espnErrors++;
          trackedCache.set(key, null);
        }
      }
      return trackedCache.get(key) ?? null;
    };

    // espn_college_slate: the dated FBS slate and the deterministic pick. A
    // final stays pickable until the latest instant its end could fire (the
    // football ceiling), so a long game's final is never dropped mid-count.
    // `answered` = every slate date came back 2xx with an events array (#159).
    const collegeGame = async (espnTeamId: string): Promise<ResolvedGame> => {
      const cached = collegeCache.get(espnTeamId);
      if (cached) return cached;
      let r: ResolvedGame = { game: null, via: "college_slate", answered: false };
      try {
        const slate = await fetchCollegeSlateGame(
          espnTeamId, nowMs, espnCache, (g) => capCeilingMs(g.startMs, "ncaaFB")
        );
        r = { ...r, answered: slate.complete };
        if (slate.game) {
          r = { ...r, game: slate.game };
        } else if (!slate.onSlate && slate.complete && espnTeamId) {
          // Never on three full days of the FBS slate. A bye week looks the
          // same, so ask ESPN whether this id is an FBS team at all; only a
          // definite "no" (FCS / unknown id) is named. An error claims nothing.
          const div = await fetchCollegeTeamDivision(espnTeamId, espnCache);
          if (div.kind === "unknown_team") r = { ...r, notOnSlate: "unknown_team" };
          if (div.kind === "not_fbs") r = { ...r, notOnSlate: `not_fbs:${div.group}` };
        }
      } catch (err) {
        stats.espnErrors++;
        logger.warn(`planGameDayFires: ESPN college slate failed for ${espnTeamId}`, err);
      }
      collegeCache.set(espnTeamId, r);
      return r;
    };

    // The one entry point for "which game is this config's, this tick". With
    // every ESPN flag off it is exactly `gameFor`.
    const resolveGame = async (
      sport: string, espnTeamId: string, teamSlug: string
    ): Promise<ResolvedGame> => {
      const t = openSessions.get(teamSlug);
      let byIdFailed = false;
      if (t && espnOn.trackStartedById) {
        const r = await trackedGame(sport, t);
        if (r) return r;
        byIdFailed = true;
      }
      const base: ResolvedGame =
        sport === "ncaaFB" && espnOn.espnCollegeSlate
          ? await collegeGame(espnTeamId)
          : { game: await gameFor(sport, espnTeamId), via: "default" };
      // #159 — THE CLOCK GUARANTEE (status_aware_cap). A started, not-ended
      // session whose game this tick's lookups did not return — ESPN down,
      // erroring, rate limiting, answering nothing usable, or no longer listing
      // the game — still reaches the end path, as a clock-only game. SILENT when
      // ESPN answered in full and the game is not in it (the cap fires at the
      // bound, as shipped); UNAVAILABLE when it could not be read (the cap is
      // held and the clock fires the ceiling). gameDayPlanning
      // .decideEndWithoutEspn has the full table.
      if (t && espnOn.statusAwareCap && (base.game === null || base.game.gameId !== t.gameId)) {
        const answered =
          !byIdFailed &&
          (base.via === "college_slate"
            ? base.answered === true
            : await defaultScoreboardAnswered(sport, espnCache));
        return {
          game: clockGame(t),
          via: base.via,
          espnState: answered ? "silent" : "unavailable",
        };
      }
      return base;
    };

    // Pre-pass: every enabled team's window and session, so each START and
    // END below is decided against the WHOLE FIELD rather than in isolation.
    // The session read moves here from the loop (same count — one per config
    // per tick); the loop reads the cached snapshot and keeps it current as
    // it writes, so a team walked later this tick sees what an earlier one did.
    const windows: TeamWindow[] = [];
    const windowByEvent = new Map<string, TeamWindow>();
    const sessionByEvent = new Map<string, Record<string, unknown>>();
    const configByEvent = new Map<string, Record<string, unknown>>();
    // B4: the user's own zone when usable (IANA), else the fleet's UTC−5.
    // Shared by the pre-pass window and the B3 scorecard date.
    const offsetHoursAt = tzOffsetResolverFor(udata);
    if (controller) {
      const lat = u.get("latitude");
      const lon = u.get("longitude");
      for (let order = 0; order < orderedDocs.length; order++) {
        const d = orderedDocs[order];
        const c = d.data();
        const sport = String(c.sport ?? "");
        const resolvedPre = await resolveGame(sport, String(c.espn_team_id ?? ""), d.id);
        const game = resolvedPre.game;
        if (!game) continue;
        const eventId = eventIdFor(d.id, game.gameId);
        const session = (await sessionRef(db, uid, eventId).get()).data() ?? {};
        sessionByEvent.set(eventId, session);
        configByEvent.set(eventId, c);
        // The daylight filter, decided once here; the loop reads the flag.
        // The user doc carries no tz offset; US Central is the fleet's
        // reality today and a ±1 h error only matters within 30 min of
        // sunset. Recorded as a limitation rather than hidden.
        const daylightOnly =
          c.skip_day_games === true &&
          typeof lat === "number" &&
          typeof lon === "number" &&
          isDaylightOnlyGame({
            gameStartMs: game.startMs,
            estimatedDurationMs: estimatedDurationMs(sport),
            latitude: lat,
            longitude: lon,
            tzOffsetHours: -5,
          });
        const w: TeamWindow = {
          teamSlug: d.id,
          eventId,
          rank: rankOf(d.id, priority),
          order,
          // B4: `on_time_override` (the app's "always 5:00 PM") replaces
          // kickoff − lead, on the game's local date, in the user's IANA zone
          // when the profile carries one (else the fleet's UTC−5).
          windowStartMs: windowStartFor(c, game.startMs, offsetHoursAt),
          gameStartMs: game.startMs,
          // status_aware_cap: the window closes when the cap fires, which a
          // live game holds up to its ceiling — so a held game keeps the house
          // (a lower team defers, nothing restores base under it). Off: the
          // shipped bound.
          windowEndMs: espnOn.statusAwareCap
            ? capBoundMs({
                gameStartMs: game.startMs, sport,
                statusAware: true, espnLive: espnReportsLive(game),
                espnUnavailable: resolvedPre.espnState === "unavailable",
              })
            : windowEndMs(game.startMs, sport),
          statusName: game.statusName,
          eligible: !daylightOnly,
          startPlanned:
            session.startPlannedAt !== null && session.startPlannedAt !== undefined,
          endFired: session.endFiredAt !== null && session.endFiredAt !== undefined,
        };
        windows.push(w);
        windowByEvent.set(eventId, w);
      }
    }

    // ── B1 PRE-FLIGHT (plan §3.7) ──────────────────────────────────────
    // Allowlisted accounts only: a scoped-out account fires nothing, so it
    // pays none of these reads. Evaluated every tick; gates the minting of NEW
    // starts (`writeStarts`) and never an end — see gameDayPreflight.ts.
    let preflight: PreflightVerdict | null = null;
    let bridgePairedForProbe: boolean | null = null;
    let bridgeFw: string | null = null;
    if (allowlisted) {
      const facts = await readPreflightFacts(db, uid);
      bridgePairedForProbe = facts.bridgePaired;
      bridgeFw = facts.bridgeFw;
      preflight = evaluatePreflight({
        bridgePaired: facts.bridgePaired,
        bridgeStatusUpdateMs: facts.bridgeStatusUpdateMs,
        controller: controller ? (controller.data() as Record<string, unknown>) : null,
        gate,
        p6Unreachable: [...sessionByEvent.values()].some((s) => p6HoldsAccount(s, nowMs)),
        appVersion: facts.appVersion,
        nowMs,
        ladderLit: ladderLitModeFor(flags.ladderLit, uid),
        // Fix A (`preflight_bridge_grace`): 15 min for a flagged account; the
        // shipped 5 min for every other.
        bridgeStaleMs: bridgeStaleMsFor(flagOnFor(flags.preflightBridgeGrace, uid)),
      });
    }
    const preflightBlocks =
      preflight !== null && !preflight.ok && flags.preflightMode === "enforce";
    // Starts are minted only for an account the allowlist arms, the gate
    // arms, and (in enforce mode) pre-flight passes. Ends keep `writeJobs`.
    const writeStarts = writeJobs && !preflightBlocks;
    // B2 sticky (`served_sticky`): a P2 failure shorter than 30 min does not
    // change what is PUBLISHED. It changes nothing about what is minted:
    // `writeStarts` above is final, and a held tick mints no start.
    const sticky = decideServedSticky({
      stickyOn: flagOnFor(flags.servedSticky, uid),
      preflight,
      startsWithheld: writeJobs && preflightBlocks,
      stored: udata.gameday_server,
      nowMs,
    });
    const servedHeld = !writeStarts && sticky.hold;
    if (servedHeld || sticky.expired) {
      // One row per stale run (no per-tick field, so arrayUnion dedupes it):
      // when the run began, and whether `served` is still held through it.
      logRows.push({
        uid,
        action: servedHeld ? "served_held" : "served_hold_expired",
        reason: "preflight_bridge_stale",
        staleSince: new Date(sticky.staleSinceMs ?? nowMs).toISOString(),
      });
      if (servedHeld) stats.servedHeld = (stats.servedHeld ?? 0) + 1;
    }
    if (writeJobs && preflight !== null && !preflight.ok) {
      // One row per (uid, reasons) per day — no per-tick field, so arrayUnion
      // dedupes it exactly like the gate rows.
      logRows.push({
        uid, action: "preflight_skip", reasons: preflight.reasons,
        ...(flags.preflightMode === "observe" ? { observeOnly: true } : {}),
      });
      // #146: name the buses the ladder leaves dark, so the row says what to
      // fix (the app's on-connect repair, or a schedule re-sync). Constant for
      // a given controller state, so it dedupes like the row above.
      if (preflight.reasons.includes("preflight_ladder_dark")) {
        logRows.push({
          uid, action: "preflight_ladder_dark",
          controllerId: controller ? controller.id : null,
          base_ladder_dark_channels: ladderDarkChannels(
            controller ? (controller.data() as Record<string, unknown>) : null
          ),
          ...(flags.preflightMode === "observe" ? { observeOnly: true } : {}),
        });
      }
      if (preflightBlocks) stats.preflightSkips++;
      else stats.preflightObserved++;
    }
    const preflightFields = {
      preflight_ok: preflight ? preflight.ok : null,
      preflight_reasons: preflight ? preflight.reasons : [],
      preflight_info: preflight ? preflight.info : [],
      preflight_mode: flags.preflightMode,
    };
    // B2: the teams the server can fire for this account (D2, per team).
    const servableTeams: string[] = [];

    for (const cfgDoc of orderedDocs) {
      stats.configsEnabled++;
      const c = cfgDoc.data();
      const teamSlug = cfgDoc.id;
      const sport = String(c.sport ?? "");
      const espnTeamId = String(c.espn_team_id ?? "");

      try {
        // B2: a team is "served" when the server could build its fire at all —
        // participation usable and a payload the server path accepts (a
        // per-pixel saved design is refused). Independent of whether a game is
        // on the board today. A held tick (B2 sticky) lists them as the last
        // good tick did: the list is a property of the config and the
        // controller, not of the heartbeat.
        if (controller && (writeStarts || servedHeld)) {
          const pv = participationForFire(controller.data(), nowMs);
          if (
            pv.usable &&
            !("refuse" in buildGameDayPayload({
              config: c,
              participatingChannels: pv.channels,
              deviceChannelIds: pv.deviceChannelIds,
              fullState: fullStateOn,
            }))
          ) {
            servableTeams.push(teamSlug);
          }
        }

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

        // ── ESPN, cached per URL (and per sport/team, per game) across users ─
        const resolved = await resolveGame(sport, espnTeamId, teamSlug);
        const game = resolved.game;
        if (!game && resolved.notOnSlate !== undefined) {
          // espn_college_slate (decision 3): three full days of the FBS slate
          // without this id, and ESPN says the id is not an FBS team (FCS, or
          // unknown to ESPN). It can never appear, so it is NAMED rather than
          // read as `no_game` forever. Its own START bucket, in place of
          // no_game, so the reconciliation still holds. Deduped per day.
          bump(stats.skipped, "team_not_on_slate");
          logRows.push({
            uid, teamSlug, action: "skip", reason: "team_not_on_slate",
            sport, espnTeamId, slate: "fbs", detail: resolved.notOnSlate,
          });
          continue;
        }
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
        // The pre-pass read this; a hand-off earlier this tick may have
        // updated it in memory, which is exactly what this team must see.
        const session = sessionByEvent.get(eventId) ?? (await sRef.get()).data() ?? {};
        const win = windowByEvent.get(eventId);
        if (!win) {
          // Unreachable: the pre-pass builds a window for every config with a
          // game and a controller, and both were just checked. Counted rather
          // than assumed.
          stats.errors++;
          logger.error(`planGameDayFires: no window for ${uid}/${eventId}`);
          continue;
        }

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
        // Decided in the pre-pass (skip_day_games + user lat/lon). An
        // ineligible window also takes no part in the hierarchy: it neither
        // owns, blocks, nor receives the house.
        if (!win.eligible) {
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

        // ── START ────────────────────────────────────────────────────────
        // DEFECT 2: the app writes `lead_time_minutes_override`; this read
        // `lead_time_minutes`, which nothing writes, so every fire went out at
        // the 30-minute default. leadMinutesFor holds the precedence, and B4's
        // windowStartFor puts `on_time_override` ahead of both; the pre-pass
        // applied it when it built the window.
        const startFireAt = win.windowStartMs; // on-time, else game.startMs − lead
        // Rules 2/3: would a lit, higher-ranked (or first-come) team already
        // hold the house when this start fired? Then this team DEFERS — no
        // start job; tracked for hand-off.
        const start = startDecision(win, windows);

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
          !startBeyondHorizon &&
          espnOn.statusAwareCap &&
          CAP_RELEASE_STATUS_NAMES.has(game.statusName)
        ) {
          // #158 (status_aware_cap). ESPN already says this game will not be
          // played tonight — postponed, cancelled, suspended, forfeited,
          // abandoned — so no start is minted: it would light the house for
          // nothing, and the cap would restore base hours later. One START
          // bucket, so the reconciliation holds. Re-evaluated every tick: a
          // game ESPN reschedules (status back to scheduled) mints as usual.
          // A start ALREADY minted is not withdrawn here (#158, decision).
          bump(stats.skipped, "game_not_played");
          logRows.push({
            uid, teamSlug, eventId, action: "skip", reason: "game_not_played",
            espnStatus: game.statusName,
            fireAt: new Date(startFireAt).toISOString(),
          });
        } else if (
          !startAlreadyPlanned &&
          !startInPast &&
          !startBeyondHorizon &&
          start.defer
        ) {
          // DEFERRED — the app's "tracked, not lit". Writing a start here is
          // exactly the bug: it would put this team's design on a house the
          // higher team already owns. One START bucket, so the reconciliation
          // holds. No session write: the window is recomputed every tick and
          // the hand-off does not need a marker to find this team.
          bump(stats.skipped, "deferred_to_higher_priority");
          logRows.push({
            uid, teamSlug, eventId, action: "skip",
            reason: "deferred_to_higher_priority",
            deferredTo: start.to.teamSlug,
            fireAt: new Date(startFireAt).toISOString(),
          });
        } else if (
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
            fullState: fullStateOn,
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
                // B1: armed and allowlisted, but pre-flight withheld the start.
                ...(writeJobs && !writeStarts ? { preflightSkipped: true } : {}),
              });
              const startRetryUntil = startRetryUntilMs({
                fireAtMs: startFireAt,
                leadMs: leadMinutesFor(c) * 60_000,
                gameStartMs: game.startMs,
              });
              const scorecardKey = scorecardDateKey(game.startMs, offsetHoursAt(game.startMs));
              if (writeJobs && !writeStarts && preflight !== null) {
                // B3: an allowlisted account pre-flight skipped still appears on
                // the scorecard, with its reasons — no silent absences. Written
                // when the reasons change, not every tick.
                const reasonsKey = JSON.stringify(preflight.reasons);
                if (session.preflight_skip_reasons_key !== reasonsKey) {
                  await sRef.set(
                    {
                      preflight_skip_reasons_key: reasonsKey,
                      scorecard_key: scorecardKey,
                      gameStartMs: game.startMs,
                      teamSlug, sport,
                    },
                    { merge: true }
                  );
                  await mergeScorecard(db, scorecardKey, uid, eventId, {
                    uid, event_id: eventId, team_slug: teamSlug, sport,
                    game_start: admin.firestore.Timestamp.fromMillis(game.startMs),
                    served: false,
                    ...preflightFields,
                    controllers_total: controllers.size,
                    bridge_fw: bridgeFw,
                    start: null,
                    end: null,
                    ...scorecardSkeleton(),
                  });
                }
              }
              if (writeStarts) {
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
                    // A2: the dispatcher may retry a transient failure until
                    // this instant (fireJobs.startRetryUntilMs). The ONLY field
                    // added to the start job; payload and every other field
                    // are unchanged.
                    retryUntil: admin.firestore.Timestamp.fromMillis(startRetryUntil),
                  })
                  .catch((e) => {
                    if (e.code !== 6 && e.code !== "already-exists") throw e;
                  });
                await sRef.set(
                  {
                    startPlannedAt: admin.firestore.FieldValue.serverTimestamp(),
                    gameStartMs: game.startMs,
                    teamSlug, sport,
                    // B3: the dispatcher finds this event's scorecard entry here.
                    scorecard_key: scorecardKey,
                  },
                  { merge: true }
                );
                // B3: the entry, at mint. The dispatcher fills start.* / end.*.
                await mergeScorecard(db, scorecardKey, uid, eventId, {
                  uid, event_id: eventId, team_slug: teamSlug, sport,
                  game_start: admin.firestore.Timestamp.fromMillis(game.startMs),
                  served: true,
                  ...preflightFields,
                  controllers_total: controllers.size,
                  bridge_fw: bridgeFw,
                  start: {
                    job_id: `${eventId}_start`,
                    fire_at: admin.firestore.Timestamp.fromMillis(startFireAt),
                    retry_until: admin.firestore.Timestamp.fromMillis(startRetryUntil),
                    state: "scheduled",
                    attempts: 0,
                  },
                  end: null,
                  ...scorecardSkeleton(),
                });
                // B1 P6: probe 1, in the same tick the start is minted.
                await stepP6({
                  db, uid, eventId, teamSlug, sRef, controller,
                  controllersTotal: controllers.size,
                  record: null,
                  startFireAtMs: startFireAt,
                  nowMs, mode: flags.preflightMode,
                  bridgePaired: bridgePairedForProbe,
                  scorecardKey, logRows, stats,
                });
              }
              stats.startsPlanned++;
              // Visible to every team walked after this one, this tick: they
              // now resolve against a house this team holds. In log-only mode
              // this is in-memory only, so the dry-run corpus shows same-tick
              // deferrals and not cross-tick ones.
              win.startPlanned = true;
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
            // A deferred team lands here every tick after its window opens:
            // it never lost a start, it yielded one. Say so, or the row reads
            // as the Dodgers case.
            ...(start.defer ? { deferredTo: start.to.teamSlug } : {}),
          });
        }

        // ── B1 P6 — reachability, while this system's own start is still
        // scheduled. Runs for allowlisted, gate-armed accounts (writeJobs)
        // whose start this system minted; a hand-off "start" (another team's
        // end job) is not probed — the house is already lit.
        if (
          writeJobs &&
          session.startPlannedAt &&
          (typeof session.startJobId !== "string" || session.startJobId === `${eventId}_start`)
        ) {
          await stepP6({
            db, uid, eventId, teamSlug, sRef, controller,
            controllersTotal: controllers.size,
            record: p6RecordFrom(session.preflight_p6),
            startFireAtMs: startFireAt,
            nowMs, mode: flags.preflightMode,
            bridgePaired: bridgePairedForProbe,
            scorecardKey:
              typeof session.scorecard_key === "string" ? session.scorecard_key : null,
            logRows, stats,
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
          // status_aware_cap: hold the cap while ESPN says the game is on. A
          // silent (gone) game reports nothing, so its cap fires at the bound.
          ...(espnOn.statusAwareCap
            ? {
                cap: {
                  statusAware: true,
                  espnLive: espnReportsLive(game),
                  // #159: no usable ESPN answer this tick — held, clock ceiling.
                  espnUnavailable: resolved.espnState === "unavailable",
                },
              }
            : {}),
        });

        if (decision.reason === "cap_held_unavailable" || decision.reason === "espn_unavailable") {
          // #159. Constant fields, so one row per reason per day: ESPN could
          // not be read for a started game, and when the clock will end it.
          logRows.push({
            uid, teamSlug, eventId, action: "skip", reason: decision.reason,
            ceilingAt: new Date(
              capCeilingMs(
                typeof session.gameStartMs === "number" ? session.gameStartMs : game.startMs,
                sport
              )
            ).toISOString(),
          });
        }

        if (decision.reason === "cap_held_live") {
          // Legible, and bounded: ESPN's status name is the only varying
          // field, so a held game adds a row per status it passes through
          // (in progress, delayed, halftime …), not one per tick.
          logRows.push({
            uid, teamSlug, eventId, action: "skip", reason: "cap_held_live",
            espnStatus: game.statusName,
            ceilingAt: new Date(
              capCeilingMs(
                typeof session.gameStartMs === "number" ? session.gameStartMs : game.startMs,
                sport
              )
            ).toISOString(),
          });
        }

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
            // A deferred team ends here by design: it never lit, so there is
            // nothing to restore — the owner's end handles the house.
            ...(start.defer ? { deferredTo: start.to.teamSlug } : {}),
          });
        }

        // B3: when ESPN first said final (for the scorecard's
        // final→restore latency). Reset if ESPN takes the final back.
        const finalSeenAtMs =
          decision.nextConsecutive > 0
            ? typeof session.finalSeenAtMs === "number"
              ? session.finalSeenAtMs
              : nowMs
            : null;
        if (writeJobs || session.startPlannedAt) {
          await sRef.set(
            {
              consecutiveFinalPolls: decision.nextConsecutive,
              gameStartMs: game.startMs,
              finalSeenAtMs,
            },
            { merge: true }
          );
        }
        const sessionScorecardKey =
          typeof session.scorecard_key === "string" ? session.scorecard_key : null;

        // GUARD 0b (#66) — the end is about to fire; confirm the START job this
        // system wrote actually reached the device. One read, only at the
        // moment it matters. A created-but-never-dispatched start leaves the
        // house exactly as a never-started one does.
        if (decision.fireEnd) {
          // The job that lit THIS team's design: its own start, or — for a team
          // that received the house by hand-off — the relinquisher's end job,
          // recorded on the session as `startJobId` when the hand-off was
          // planned.
          const startJobId =
            typeof session.startJobId === "string" && session.startJobId.length > 0
              ? session.startJobId
              : `${eventId}_start`;
          const startJob = await db
            .collection("users").doc(uid)
            .collection(FIRE_JOBS_COLLECTION).doc(startJobId)
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
          // ── THE HIERARCHY AT THE END ───────────────────────────────────
          // Before this, every team's end base-restored at its own final, so
          // with two games the first to finish put the house back to base
          // part-way through the second. Two questions now, in order.
          //
          // 1. Is this team the OWNER? If a higher-ranked lit team is still
          //    playing, the house is theirs; restoring it would be the bug.
          //    The end is recorded (endFiredAt, so it never re-fires) and no
          //    job is written. The app's analogue: a deferred or preempted
          //    session completes without calling onResumeNormalSchedule.
          //    Asked of THIS team rather than "who owns the house now": a
          //    hard-capped team's own window has just closed, and a lower
          //    team still playing must receive the hand-off, not outrank it.
          const owner = outrankedBy(windows, win, nowMs);
          if (owner !== null) {
            bump(stats.endSkipped, "end:not_owner");
            logRows.push({
              uid, teamSlug, eventId, action: "skip",
              reason: "end_suppressed_not_owner", owner: owner.teamSlug,
              ...(policy.enabled && !writeJobs ? { scopedOut: true } : {}),
            });
            if (writeJobs) {
              await sRef.set(
                {
                  endFiredAt: admin.firestore.FieldValue.serverTimestamp(),
                  endOutcome: "not_owner",
                  endYieldedTo: owner.eventId,
                },
                { merge: true }
              );
              win.endFired = true;
              if (sessionScorecardKey) {
                await mergeScorecard(db, sessionScorecardKey, uid, eventId, {
                  end: { reason: "not_owner", owner: owner.teamSlug, state: "suppressed" },
                });
              }
            }
            continue;
          }

          // 2. Is another ranked team STILL PLAYING? Then the house is HANDED
          //    OFF: this end job carries the survivor's design instead of the
          //    base restore, and the survivor's session is marked started so
          //    its own end can fire later (GUARD 0 / 0b read that marker).
          //    Only when no team remains does the base look come back — the
          //    app's rule 5, handoffWinner.
          const winner = handoffWinner(windows, eventId, nowMs);
          let handoff: { payload: string; to: TeamWindow } | null = null;
          if (winner !== null) {
            const built = buildGameDayPayload({
              config: configByEvent.get(winner.eventId) ?? {},
              participatingChannels: part.channels,
              deviceChannelIds: part.deviceChannelIds,
              fullState: fullStateOn,
            });
            if ("refuse" in built) {
              // The survivor cannot be lit by this path (e.g. a per-pixel
              // saved design). Legible, and the end falls back to base rather
              // than leaving the finished team's colours up.
              logRows.push({
                uid, teamSlug, eventId, action: "skip",
                reason: `handoff_refused:${built.refuse.split(":")[0]}`,
                handoffTo: winner.teamSlug,
              });
            } else {
              const safety = assertPayloadIsFireSafe("applyJson", built.payload);
              if (!safety.ok) {
                logger.error(
                  `planGameDayFires: UNSAFE hand-off payload for ${uid}/${winner.teamSlug}: ${safety.reason}`
                );
              } else {
                handoff = { payload: built.payload, to: winner };
              }
            }
          }

          logRows.push({
            uid, teamSlug, eventId, action: "plan_end",
            fireAt: new Date(nowMs).toISOString(), reason: decision.reason,
            ...(handoff ? { handoffTo: handoff.to.teamSlug } : {}),
            ...(policy.enabled && !writeJobs ? { scopedOut: true } : {}),
            // Only the flagged paths add these, so a flags-off row is unchanged.
            ...(resolved.via === "tracked" ? { espnVia: "tracked" } : {}),
            ...(espnOn.statusAwareCap && decision.reason.startsWith("hard_cap")
              ? {
                  capStatus:
                    resolved.espnState === "silent"
                      ? "silent"
                      : resolved.espnState === "unavailable"
                        ? "espn_unavailable"
                        : game.statusName,
                }
              : {}),
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
                payload: handoff ? handoff.payload : restore.payload,
                state: "scheduled",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                source: "game_day",
                // A2: an end retries for 15 min (fireJobs.endRetryUntilMs).
                retryUntil: admin.firestore.Timestamp.fromMillis(endRetryUntilMs(nowMs)),
                // Audit: an `end` whose payload is a design rather than a
                // preset load must say which team it lit.
                ...(handoff
                  ? { handoffTo: handoff.to.eventId, handoffToTeam: handoff.to.teamSlug }
                  : {}),
              })
              .catch((e) => {
                if (e.code !== 6 && e.code !== "already-exists") throw e;
              });
            await sRef.set(
              {
                endFiredAt: admin.firestore.FieldValue.serverTimestamp(),
                ...(handoff ? { handedOffTo: handoff.to.eventId } : {}),
              },
              { merge: true }
            );
            win.endFired = true;
            if (sessionScorecardKey) {
              await mergeScorecard(db, sessionScorecardKey, uid, eventId, {
                end: {
                  job_id: `${eventId}_end`,
                  reason: decision.reason,
                  espn_final_seen_at:
                    finalSeenAtMs !== null
                      ? admin.firestore.Timestamp.fromMillis(finalSeenAtMs)
                      : null,
                  fire_at: admin.firestore.Timestamp.fromMillis(nowMs),
                  retry_until: admin.firestore.Timestamp.fromMillis(endRetryUntilMs(nowMs)),
                  state: "scheduled",
                  attempts: 0,
                  ...(handoff ? { handoff_to: handoff.to.teamSlug } : {}),
                },
              });
            }
            if (handoff) {
              // The survivor now holds the house. `startPlannedAt` is what
              // GUARD 0 requires before its own end may fire, and `startJobId`
              // is what GUARD 0b reads to confirm the design reached the
              // device. Neither is overwritten when the survivor had fired its
              // own start — that job already confirms it.
              const toSession = sessionByEvent.get(handoff.to.eventId) ?? {};
              const alreadyStarted =
                toSession.startPlannedAt !== null && toSession.startPlannedAt !== undefined;
              // B3: a survivor lit by hand-off gets its own scorecard entry,
              // whose `start` is this end job (the dispatcher mirrors it).
              const toScorecardKey = scorecardDateKey(
                handoff.to.gameStartMs,
                offsetHoursAt(handoff.to.gameStartMs)
              );
              const startFields = alreadyStarted
                ? {}
                : {
                    startPlannedAt: admin.firestore.FieldValue.serverTimestamp(),
                    startJobId: `${eventId}_end`,
                    scorecard_key: toScorecardKey,
                  };
              if (!alreadyStarted) {
                const toSport = String(configByEvent.get(handoff.to.eventId)?.sport ?? "");
                await mergeScorecard(db, toScorecardKey, uid, handoff.to.eventId, {
                  uid, event_id: handoff.to.eventId, team_slug: handoff.to.teamSlug,
                  sport: toSport,
                  game_start: admin.firestore.Timestamp.fromMillis(handoff.to.gameStartMs),
                  served: true,
                  ...preflightFields,
                  controllers_total: controllers.size,
                  bridge_fw: bridgeFw,
                  start: {
                    job_id: `${eventId}_end`,
                    via_handoff_from: teamSlug,
                    fire_at: admin.firestore.Timestamp.fromMillis(nowMs),
                    state: "scheduled",
                    attempts: 0,
                  },
                  end: null,
                  ...scorecardSkeleton(),
                });
              }
              await sessionRef(db, uid, handoff.to.eventId).set(
                {
                  ...startFields,
                  gameStartMs: handoff.to.gameStartMs,
                  teamSlug: handoff.to.teamSlug,
                  sport: String(configByEvent.get(handoff.to.eventId)?.sport ?? ""),
                  handedOffFrom: eventId,
                },
                { merge: true }
              );
              // Keep this tick's view coherent for the survivor's own pass.
              Object.assign(toSession, startFields, { gameStartMs: handoff.to.gameStartMs });
              sessionByEvent.set(handoff.to.eventId, toSession);
              handoff.to.startPlanned = true;
              stats.handoffsPlanned++;
            }
          }
          stats.endsPlanned++;
          if (decision.reason === "hard_cap" || decision.reason === "hard_cap_ceiling") {
            stats.hardCapsPlanned++;
          }
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

    // ── B2: users/{uid}.gameday_server ──────────────────────────────────
    // served = this account's starts are minted by the server this tick — or,
    // with `served_sticky` on, were until a bridge write gap began less than
    // 30 min ago (`servedHeld`; the verdict itself is published unchanged in
    // `preflight`).
    // Written EVERY tick for a served account, held or not (D1: `checked_at`
    // is the heartbeat the app uses to distrust a dead planner) and ON CHANGE
    // otherwise. Dotted-path update: each named field is replaced whole, and
    // the dispatcher-owned `last_fire` is never touched. Inside a catch, like
    // the gate persist above — a failed status write must never stop planning.
    if (flags.publishServerStatus) {
      try {
        const served = writeStarts || servedHeld;
        // B2 sticky: `stale_since` exactly as decideServedSticky defines it. A
        // time while P2 is failing with the flag on; otherwise removed, and
        // only from a doc that carries it — with the flag never on, this adds
        // no field to any write.
        const storedSince =
          (udata.gameday_server as Record<string, unknown> | undefined)?.stale_since;
        const staleSincePatch: Record<string, unknown> =
          sticky.staleSinceMs !== null
            ? { "gameday_server.stale_since": admin.firestore.Timestamp.fromMillis(sticky.staleSinceMs) }
            : storedSince !== undefined
              ? { "gameday_server.stale_since": admin.firestore.FieldValue.delete() }
              : {};
        let nextFire: NextFire | null = null;
        if (served) {
          const sched = await db
            .collection("users").doc(uid)
            .collection(FIRE_JOBS_COLLECTION)
            .where("state", "==", "scheduled") // COLLECTION scope → automatic index
            .get();
          for (const j of sched.docs) {
            const ev = j.get("eventId");
            const at = (j.get("fireAt") as { toMillis?: () => number } | undefined)?.toMillis?.();
            if (typeof ev !== "string" || teamSlugFromEventId(ev) === null) continue;
            if (typeof at !== "number") continue;
            if (nextFire === null || at < nextFire.fire_at_ms) {
              nextFire = {
                event_id: ev,
                team_slug: teamSlugFromEventId(ev),
                seq: String(j.get("seq") ?? ""),
                fire_at_ms: at,
              };
            }
          }
        }
        const core: ServerStatusCore = {
          served,
          teams: served ? servableTeams : [],
          preflight: preflight
            ? { ok: preflight.ok, reasons: preflight.reasons, info: preflight.info, mode: flags.preflightMode }
            : null,
          next_fire: nextFire,
        };
        if (served || storedServerStatusKey(udata.gameday_server) !== serverStatusKey(core)) {
          await u.ref.update({
            "gameday_server.served": core.served,
            "gameday_server.teams": core.teams,
            "gameday_server.checked_at": admin.firestore.FieldValue.serverTimestamp(),
            "gameday_server.preflight": core.preflight
              ? { ...core.preflight, at: admin.firestore.FieldValue.serverTimestamp() }
              : null,
            "gameday_server.next_fire": core.next_fire
              ? {
                  event_id: core.next_fire.event_id,
                  team_slug: core.next_fire.team_slug,
                  seq: core.next_fire.seq,
                  fire_at: admin.firestore.Timestamp.fromMillis(core.next_fire.fire_at_ms),
                }
              : null,
            ...staleSincePatch,
          });
          stats.serverStatusWrites++;
        }
      } catch (_) {
        /* a failed status write must never stop planning */
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
  stats.espnFetches = espnCache.size;
  const day = new Date(nowMs).toISOString().slice(0, 10);
  const summary = {
    at: admin.firestore.FieldValue.serverTimestamp(),
    usersScanned: stats.usersScanned,
    configsEnabled: stats.configsEnabled,
    startsPlanned: stats.startsPlanned,
    endsPlanned: stats.endsPlanned,
    // Ends that handed the house to another team rather than restoring base.
    handoffsPlanned: stats.handoffsPlanned,
    // Ends the hard cap fired because ESPN never said final.
    hardCapsPlanned: stats.hardCapsPlanned,
    // Skip reasons by category — the field whose absence cost the most.
    // START phase, one bucket per config. See PlanStats.skipped.
    skipped: stats.skipped,
    // END phase, counted separately so the START sum stays exact.
    endSkipped: stats.endSkipped,
    // B1/B2 — pre-flight and the published server status.
    preflightSkips: stats.preflightSkips,
    preflightObserved: stats.preflightObserved,
    p6Probes: stats.p6Probes,
    serverStatusWrites: stats.serverStatusWrites,
    // B2 sticky: only on a tick that held someone, so every other tick's
    // summary is the one it always was.
    ...(stats.servedHeld ? { servedHeld: stats.servedHeld } : {}),
    espnErrors: stats.espnErrors,
    // Distinct ESPN URLs requested — one request each (the per-tick cache).
    espnFetches: stats.espnFetches,
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
