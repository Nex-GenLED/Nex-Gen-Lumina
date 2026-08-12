/**
 * gameDayPlanning — S5 shared contract. PURE (no firebase-admin, no network at
 * module scope) so every decision is unit-testable against compiled lib/.
 *
 * S3 shipped a dispatcher with no producer. This is the producer's brain.
 *
 * SCOPE DECISION — which of the three Game Day implementations this ports.
 * ------------------------------------------------------------------------
 * Three exist (audit/UNATTENDED_OPERATION.md §1.1):
 *   1. GameDayAutopilotService          — foreground, 1-min evaluateConfigs
 *   2. GameDayAutopilotBackgroundWorker — INERT, never ran in a shipped build
 *   3. EphemeralGameSessionService      — foreground, the mid-game-join machine
 *
 * V2's estimate cited #2, which is the wrong target — it has never executed.
 *
 * **This ports #1. #3 is DECLARED OUT OF SCOPE for unattended operation, and
 * that is a statement about what the feature can be, not an omission.**
 *
 * #3 exists to light a house when its owner opens the app *during* a game
 * already in progress. Unattended operation has no analogue: there is no join,
 * because the planner schedules from the game schedule before the game starts.
 * A server-side "mid-game join" would mean firing at an arbitrary instant for a
 * customer who did nothing — the opposite of what #3 is for.
 *
 * The d753ea7 lesson still applies and is respected: that bug was score
 * CELEBRATIONS reading only the autopilot session and being blind to the
 * ephemeral machine. Celebrations are S5b and are NOT built here, so the
 * blindness has no surface. If S5b ships, it MUST read both.
 *
 * **UI obligation:** the Game Day screen must say that unattended firing covers
 * scheduled starts and ends only — not mid-game joins and not celebrations —
 * or a customer whose lights came on when they opened the app mid-game will
 * expect that away from home. Tracked in audit/S5_GAMEDAY.md §7.
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/**
 * How far ahead a start fire is planned. Must exceed the planner's own cadence
 * so a job always exists before the dispatcher's minute tick needs it.
 */
export const PLAN_HORIZON_MS = 6 * 3600_000; // 6 hours

/** Default pre-game lead, matching the client's `_kPreGameLeadTimeMinutes`. */
export const DEFAULT_LEAD_MINUTES = 30;

/**
 * Consecutive ESPN polls reporting `final` before the end fire is written.
 *
 * ONE IS NOT ENOUGH. A wrong-early `final` is the single genuinely bad outcome:
 * it ends the show while the game is still on, in front of a customer who is not
 * there to correct it. Two consecutive polls at the planner cadence costs at
 * most one extra cadence of delay on a correct final — invisible — and removes
 * every single-sample glitch.
 */
export const REQUIRED_FINAL_POLLS = 2;

/**
 * A `final` is never believed before gameStart + this. Guards against ESPN
 * reporting a stale `final` from the PREVIOUS meeting of the same two teams,
 * which is the failure mode that produces a fire at first pitch.
 */
export const MIN_PLAUSIBLE_DURATION_MS: Record<string, number> = {
  nfl: 2 * 3600_000,
  ncaaFB: 2 * 3600_000,
  mlb: 2 * 3600_000,
  nba: 1.5 * 3600_000,
  ncaaMB: 1.5 * 3600_000,
  nhl: 1.5 * 3600_000,
  mls: 1.5 * 3600_000,
  epl: 1.5 * 3600_000,
  fifa: 1.5 * 3600_000,
  nwsl: 1.5 * 3600_000,
  wnba: 1.5 * 3600_000,
};
export const MIN_PLAUSIBLE_DURATION_DEFAULT_MS = 1.5 * 3600_000;

/** Serialized payload ceiling for a single fire command. */
export const MAX_FIRE_PAYLOAD_BYTES = 4096;

// ---------------------------------------------------------------------------
// Payload construction — the TS half of S3b
// ---------------------------------------------------------------------------

export type ColorSlot = number[];

/**
 * Server-side equivalent of Dart's `buildParticipatingSegArray`.
 *
 * REPLICATES THE SHIPPED RENDERING DELIBERATELY, INCLUDING ITS ODDITY.
 *
 * One WLED segment per participating channel, each carrying the same `fx`. That
 * means a multi-channel install runs the effect once PER CHANNEL, each from its
 * own origin — the "effect doubling" a two-channel house sees. It is not a
 * transcription error here; it is what `applyChannelFilter` /
 * `buildParticipatingSegArray` do today on every foreground and background
 * apply.
 *
 * **The port replicates it rather than fixing it, and that is the decision.**
 * Fixing it server-side only would make an unattended fire render DIFFERENTLY
 * from the same design fired from the app — the customer would see one thing at
 * home and another away, with nothing to explain it. Whether the doubling is
 * desirable is a product question; whichever way it is answered, both paths must
 * change together. Filed in audit/S5_GAMEDAY.md §8.
 *
 * NO `start` / `stop`. The Dart contract is explicit that WLED retains the
 * install-time ranges set by `wled_config_pusher`, and that sending ranges risks
 * the Item #82 wrong-range stomp. The server could not send them anyway — bus
 * ranges live behind /json/cfg, which is LAN-only.
 *
 * Per-segment `on: true` is REQUIRED: a segment left `on:false` is not re-lit by
 * a top-level `on:true` (the channel-2-dark class).
 */
export function buildParticipatingSegArray(args: {
  participatingChannelIds: number[];
  effectId: number;
  speed: number;
  intensity: number;
  colorSlots: ColorSlot[];
}): Array<Record<string, unknown>> {
  return args.participatingChannelIds.map((ch) => ({
    id: ch,
    on: true,
    fx: args.effectId,
    sx: args.speed,
    ix: args.intensity,
    col: args.colorSlots,
  }));
}

/** RGB → the RGBW 4-slot shape the fleet uses (W=0; WLED's gamma owns white). */
export function toRgbwSlots(colors: number[][]): ColorSlot[] {
  return colors.map((c) => [c[0] ?? 0, c[1] ?? 0, c[2] ?? 0, 0]);
}

/** Split an ARGB int into [r,g,b], matching the Dart colour storage. */
export function argbToRgb(argb: number): number[] {
  return [(argb >> 16) & 0xff, (argb >> 8) & 0xff, argb & 0xff];
}

// ---------------------------------------------------------------------------
// Saved-design carve-out
// ---------------------------------------------------------------------------

export interface SavedDesignVerdict {
  usable: boolean;
  reason: string;
}

/**
 * Decide whether a config's `saved_design_payload` may be fired by the server.
 *
 * THE DECISION: **accept effect-shaped saved designs, REFUSE per-pixel ones.**
 * Not blanket refusal, and not chunking.
 *
 * Why not chunk. A Design Studio per-pixel design exceeds one command and is
 * chunked over the relay (337 px / 6 KB ceiling, chunk = 224). Chunking from a
 * scheduled path multiplies the failure surface and, worse, has no atomicity: a
 * run that lands 3 of 5 chunks leaves the strip in a state that is neither the
 * old design nor the new one, unattended, with no one to correct it. S3's
 * one-in-flight guard also makes a multi-command sequence awkward by design.
 *
 * Why not pre-stage a preset. That needs `psave`, and COMMAND_SAFETY §4.2
 * forbids state-mutating operations on the scheduled path outright — "executed
 * 60 s late" is not equivalent to "executed" for a preset write.
 *
 * So: refuse, loudly, with a reason the operator can act on. A refusal is
 * visible and fixable; a truncated per-pixel payload is a house lit wrongly.
 *
 * Refuses when the payload is oversized, carries a per-pixel `i` array in any
 * segment, is unparseable, or is not an object.
 */
export function savedDesignUsable(payload: unknown): SavedDesignVerdict {
  if (payload === null || payload === undefined) {
    return { usable: false, reason: "no_saved_payload" };
  }
  let obj: Record<string, unknown>;
  if (typeof payload === "string") {
    try {
      const p: unknown = JSON.parse(payload);
      if (!p || typeof p !== "object" || Array.isArray(p)) {
        return { usable: false, reason: "saved_payload_not_an_object" };
      }
      obj = p as Record<string, unknown>;
    } catch {
      return { usable: false, reason: "saved_payload_unparseable" };
    }
  } else if (typeof payload === "object" && !Array.isArray(payload)) {
    obj = payload as Record<string, unknown>;
  } else {
    return { usable: false, reason: "saved_payload_not_an_object" };
  }

  const serialized = JSON.stringify(obj);
  if (serialized.length > MAX_FIRE_PAYLOAD_BYTES) {
    return {
      usable: false,
      reason: `saved_payload_too_large:${serialized.length}b`,
    };
  }

  // Per-pixel: WLED's `i` array inside a segment. This is the Design Studio
  // shape that requires chunking.
  const seg = obj.seg;
  if (Array.isArray(seg)) {
    for (const s of seg) {
      if (s && typeof s === "object" && "i" in (s as Record<string, unknown>)) {
        return { usable: false, reason: "saved_payload_per_pixel" };
      }
    }
  }
  return { usable: true, reason: "ok" };
}

// ---------------------------------------------------------------------------
// ESPN end-signal guards
// ---------------------------------------------------------------------------

export interface EndSignalState {
  /** Consecutive polls that reported `final`. Persisted, not function-local. */
  consecutiveFinalPolls?: unknown;
  /** Written once the end fire has been planned. The once-per-event marker. */
  endFiredAt?: unknown;
  gameStartMs?: unknown;
  /**
   * Set when THIS system actually wrote the start job for this event. Written
   * only inside `if (writeJobs)`, so it is absent for every session that was
   * only ever observed in log-only mode. See GUARD 0.
   */
  startPlannedAt?: unknown;
}

/**
 * GUARD 0b — did the start job this system wrote actually reach the device?
 *
 * `startPlannedAt` proves a start job was CREATED (it is written immediately
 * after the `create()`, in the same block). It does not prove the job was ever
 * dispatched. A start that was created and then never dispatched leaves the
 * house in exactly the state a never-started show does — so ending it is the
 * same unrequested command #66 was about, one step further along.
 *
 * `undefined` state means the job document is missing entirely, which is
 * stronger evidence of "never fired" than any status string.
 *
 * Deliberately NOT called on every tick: it is one extra read, and it only
 * matters at the instant an end would actually fire. Call it after the other
 * guards pass.
 */
export function startJobConfirmsFired(startJobState: unknown): boolean {
  return startJobState === "dispatched" || startJobState === "completed";
}

export interface EndSignalDecision {
  fireEnd: boolean;
  reason: string;
  nextConsecutive: number;
}

/**
 * The three mandatory guards, evaluated together.
 *
 * All three read PERSISTED state, never function-local variables. Cloud
 * Functions retry, and a retried invocation with in-memory counters would either
 * lose the count (never firing) or double it (firing on one real poll). The
 * `endFiredAt` marker is what makes "never more than once per event" survive a
 * retry — S3's deterministic command id protects the transport, not the plan.
 */
export function decideEndSignal(args: {
  espnIsFinal: boolean;
  state: EndSignalState;
  sport: string;
  nowMs: number;
}): EndSignalDecision {
  const { espnIsFinal, state, sport, nowMs } = args;

  const prior =
    typeof state.consecutiveFinalPolls === "number" && state.consecutiveFinalPolls > 0
      ? state.consecutiveFinalPolls
      : 0;

  // GUARD 0 — NEVER end a show this system did not start. INCIDENT #66.
  //
  // An end fire is a RESTORE. Restoring a house that was never put into a Game
  // Day design is not a restore, it is an unrequested command — and because
  // `baseRestorePayload` resolves to a preset load, that command turns lights
  // ON.
  //
  // 2026-08-12, bench: the scoped flip was written 05:45:21Z. `startPlannedAt`
  // and `consecutiveFinalPolls` are both written only when
  // `writeJobs || session.startPlannedAt` (planGameDayFires :494), so through
  // the whole log-only era the counter was pinned at 0 and no end could ever
  // qualify. Arming opened that gate: 05:50:04Z counter -> 1, 05:55:04Z -> 2,
  // REQUIRED_FINAL_POLLS met, `plan_end reason=confirmed_final`, job dispatched
  // COMPLETED with payload {"ps":1} = preset "NGL On". The bench strip came on
  // at 01:00 local for a game that finished hours earlier and whose START this
  // system never fired. Two ticks, ten minutes after arming.
  //
  // Under a GLOBAL flip that was a simultaneous 1am lights-on across all ten
  // Game-Day-enabled accounts, seven of which have no base layer to correct it.
  //
  // The other four guards all passed honestly — endFiredAt unset, ESPN final,
  // gameStartMs known, well past minimum duration, two consecutive finals. Every
  // one was true. None of them asked the question that mattered: did we start
  // this? So this guard runs FIRST, ahead of even `already_fired`, because a
  // show we did not start is not ours to end regardless of any other state.
  //
  // PERMANENTLY ineligible, not merely deferred: `startPlannedAt` is only ever
  // written alongside a start job, so a session that reaches a terminal state
  // without one can never acquire it — the start path refuses on
  // `start_time_passed` and `already_planned` long before it would write.
  // Stale sessions therefore age out by the event passing out of the planner's
  // 6-hour horizon and the team's schedule, not by any counter re-tripping.
  if (state.startPlannedAt === null || state.startPlannedAt === undefined) {
    return { fireEnd: false, reason: "no_start", nextConsecutive: prior };
  }

  // GUARD 3 — once per event, from a written marker.
  if (state.endFiredAt !== null && state.endFiredAt !== undefined) {
    return { fireEnd: false, reason: "already_fired", nextConsecutive: prior };
  }

  if (!espnIsFinal) {
    // A non-final poll RESETS the run. Two finals separated by a non-final are
    // not two consecutive finals, and treating them as such would defeat the
    // guard on exactly the flapping case it exists for.
    return { fireEnd: false, reason: "not_final", nextConsecutive: 0 };
  }

  const next = prior + 1;

  // GUARD 2 — never before gameStart + minimum plausible duration.
  const startMs = typeof state.gameStartMs === "number" ? state.gameStartMs : null;
  if (startMs === null) {
    return { fireEnd: false, reason: "no_game_start", nextConsecutive: next };
  }
  const minMs = MIN_PLAUSIBLE_DURATION_MS[sport] ?? MIN_PLAUSIBLE_DURATION_DEFAULT_MS;
  if (nowMs < startMs + minMs) {
    return {
      fireEnd: false,
      reason: `too_early:${Math.round((nowMs - startMs) / 60000)}m`,
      nextConsecutive: next,
    };
  }

  // GUARD 1 — two consecutive finals.
  if (next < REQUIRED_FINAL_POLLS) {
    return { fireEnd: false, reason: `awaiting_confirmation:${next}`, nextConsecutive: next };
  }

  return { fireEnd: true, reason: "confirmed_final", nextConsecutive: next };
}

// ---------------------------------------------------------------------------
// Sunset — ported, not imported
// ---------------------------------------------------------------------------

/**
 * Local sunset for a date/lat/lon. A direct port of Dart's
 * `SunUtils.sunsetLocal` (lib/utils/sun_utils.dart), same algorithm, same
 * zenith, same approximations.
 *
 * PORTED RATHER THAN TAKING A LIBRARY, deliberately. `skip_day_games` must
 * decide identically on the server and in the app: if a published solar library
 * disagreed with the shipped Dart by even a few minutes, a game near the
 * boundary would be skipped attended and fired unattended (or the reverse), and
 * nothing in the product would explain it. Agreeing with the app matters more
 * than being astronomically better, and it adds no dependency.
 *
 * Returns epoch ms, or null when the sun does not set that day at that latitude.
 */
export function sunsetUtcMs(
  latitude: number,
  longitude: number,
  dateMs: number,
  tzOffsetHours: number
): number | null {
  const d = new Date(dateMs);
  const year = d.getUTCFullYear();
  const month = d.getUTCMonth() + 1;
  const day = d.getUTCDate();

  const n1 = Math.floor((275 * month) / 9);
  const n2 = Math.floor((month + 9) / 12);
  const n3 = Math.floor(1 + (year - 4 * Math.floor(year / 4) + 2) / 3);
  const N = n1 - n2 * n3 + day - 30;

  const lngHour = longitude / 15.0;
  const t = N + (18 - lngHour) / 24;

  const M = 0.9856 * t - 3.289;
  const rad = Math.PI / 180;
  let L =
    M + 1.916 * Math.sin(M * rad) + 0.020 * Math.sin(2 * M * rad) + 282.634;
  L = ((L % 360) + 360) % 360;

  let RA = Math.atan(0.91764 * Math.tan(L * rad)) / rad;
  RA = ((RA % 360) + 360) % 360;
  const Lquadrant = Math.floor(L / 90) * 90;
  const RAquadrant = Math.floor(RA / 90) * 90;
  RA = (RA + (Lquadrant - RAquadrant)) / 15;

  const sinDec = 0.39782 * Math.sin(L * rad);
  const cosDec = Math.cos(Math.asin(sinDec));

  const zenith = 90.83333; // official sunset
  const cosH =
    (Math.cos(zenith * rad) - sinDec * Math.sin(latitude * rad)) /
    (cosDec * Math.cos(latitude * rad));
  if (cosH > 1 || cosH < -1) return null; // sun never sets / never rises

  // SUNSET uses H = acos(cosH); SUNRISE is the 360-acos variant. Getting this
  // backwards returns a sunrise — which is what the first port did, putting
  // "sunset" at 05:52 local and making every evening game look like a day game.
  const H = Math.acos(cosH) / rad / 15;
  const T = H + RA - 0.06571 * t - 6.622;
  let UT = T - lngHour;
  UT = ((UT % 24) + 24) % 24;

  // UT is the sunset instant in UTC hours. For western longitudes an evening
  // sunset lands on the FOLLOWING UTC date, so the naive construction can be a
  // day out. Anchor to whichever wrap is nearest the date being asked about.
  let instant = Date.UTC(year, month - 1, day) + UT * 3600_000;
  const DAY_MS = 86_400_000;
  while (instant - dateMs > DAY_MS / 2) instant -= DAY_MS;
  while (dateMs - instant > DAY_MS / 2) instant += DAY_MS;
  void tzOffsetHours; // retained in the signature: callers reason in local time
  return instant;
}

/**
 * True when the whole game is in daylight — the `skip_day_games` condition.
 * Mirrors the client: a game is daylight-only when it ENDS more than 30 minutes
 * before local sunset.
 */
export function isDaylightOnlyGame(args: {
  gameStartMs: number;
  estimatedDurationMs: number;
  latitude: number;
  longitude: number;
  tzOffsetHours: number;
}): boolean {
  const sunset = sunsetUtcMs(
    args.latitude,
    args.longitude,
    args.gameStartMs,
    args.tzOffsetHours
  );
  if (sunset === null) return false;
  const gameEnd = args.gameStartMs + args.estimatedDurationMs;
  return gameEnd < sunset - 30 * 60_000;
}

/**
 * System preset ids the schedule layer maintains on every controller.
 * Confirmed on the rig: `macro:1` is the base ON row, `macro:2` the base OFF row
 * (bench `timers.ins` — 20:23 macro 1, 06:22 macro 2).
 */
export const BASE_ON_PRESET = 1;
export const BASE_OFF_PRESET = 2;

/**
 * What an event's `endsAt` job sends to return the house to base.
 *
 * THE SERVER CANNOT RECONSTRUCT THE BASE STATE, and does not try. The base layer
 * lives in `timers.ins` + presets on the controller — device-resident cfg behind
 * `/json/cfg`, which is LAN-only. There is no off-LAN read.
 *
 * It does not need to. The schedule layer already maintains the base as PRESETS,
 * and a preset load is exactly the primitive required: `{ps:N}` is an absolute
 * state load, idempotent, allowed by `assertPayloadIsFireSafe` (`ps` is
 * permitted; `psave` is not), and A1 proved an identical-state preset load is
 * visually silent — byte-identical readback, no flash, three trials. So the
 * restore is a preset id, not a reconstruction.
 *
 * CHOOSING BETWEEN ON AND OFF. Loading base-ON at 07:00 would light a house that
 * should be dark. The server does not know the base boundaries, but it does know
 * the customer's lat/lon and carries the same sunset port the daylight filter
 * uses — and the overwhelmingly common base layer is sunset-on / sunrise-off. So
 * the choice is made solarly: dark outside → base ON, daylight → base OFF.
 *
 * RESIDUAL, stated rather than hidden: a customer whose base is a CLOCK schedule
 * (the bench's 20:23) rather than solar can be up to ~30 minutes out at the
 * edges — an event ending at 20:00 against a 20:23 base ON would restore to ON
 * slightly early. That is a wrong-by-minutes at a boundary, not a wrong state,
 * and it is strictly better than the alternative of sending `{on:false}` and
 * leaving a house dark that its owner expects lit.
 */
export function baseRestorePayload(args: {
  nowMs: number;
  latitude: number | null;
  longitude: number | null;
  tzOffsetHours: number;
}): { payload: string; preset: number; basis: string } {
  if (args.latitude === null || args.longitude === null) {
    // No coordinates — cannot reason about dark. Base ON is the safer default:
    // a house briefly lit when it should be dark is a smaller failure than a
    // house dark on an evening its owner expects it lit, and the base layer's
    // own next boundary corrects it either way.
    return {
      payload: JSON.stringify({ ps: BASE_ON_PRESET }),
      preset: BASE_ON_PRESET,
      basis: "no_coordinates_default_on",
    };
  }
  const sunset = sunsetUtcMs(args.latitude, args.longitude, args.nowMs, args.tzOffsetHours);
  // Dark = after today's sunset, or before it by more than 12 h (i.e. the small
  // hours, which the anchoring in sunsetUtcMs maps to the same day).
  const isDark = sunset === null ? true : args.nowMs >= sunset;
  return {
    payload: JSON.stringify({ ps: isDark ? BASE_ON_PRESET : BASE_OFF_PRESET }),
    preset: isDark ? BASE_ON_PRESET : BASE_OFF_PRESET,
    basis: isDark ? "after_sunset" : "daylight",
  };
}

/** Estimated duration per sport, mirroring the client's `_estimatedDuration`. */
export function estimatedDurationMs(sport: string): number {
  switch (sport) {
    case "nfl":
    case "ncaaFB":
      return 3.5 * 3600_000;
    case "mlb":
      return 3 * 3600_000;
    case "nba":
    case "nhl":
    case "ncaaMB":
      return 2.5 * 3600_000;
    default:
      return 3 * 3600_000;
  }
}
