/**
 * gameDayPreflight — B1 (2026-10-02). PURE: no firebase-admin, no network.
 * Plan §3.7 (docs/gameday_server_authority_plan_2026-10-01.md).
 *
 * WHY. The uid allowlist decides WHO the server may fire for. It says nothing
 * about whether a given house can actually be fired into tonight: a bridge
 * that has not heartbeated for an hour, a controller whose channel facts are
 * months old, a base ladder nobody has verified. Allowlisting a customer is
 * only safe with an automatic skip for those, and the skip must be NAMED —
 * the app (step C) shows "Phone" with the reason, and the scorecard lists every
 * allowlisted account with either its fires or the reason it was skipped.
 *
 * WHAT A SKIP MEANS. Pre-flight gates the minting of NEW START jobs only. An
 * account that fails is not served: the server does not start its game, and
 * (once C ships) the phone path runs as it does today. It never suppresses the
 * END of a game this system already started — leaving team colours up because
 * a heartbeat went stale mid-game would turn a degraded bridge into a stuck
 * house. (The plan's text says "writeJobs = false"; that would also block
 * ends. Deliberately narrowed, and recorded.)
 *
 * THE CHECKS (plan §3.7)
 *   P1 bridge paired     a bridge_registry row with pairedUid == uid
 *                        (relayEligibility; never users/{uid}.bridge_paired).
 *                        A lookup ERROR passes — fail open, as every caller of
 *                        that predicate does.
 *   P2 bridge healthy    users/{uid}/bridge_status/current server updateTime
 *                        within 5 min. The heartbeat PATCH carries no
 *                        timestamp field, so the server's updateTime IS the
 *                        heartbeat clock.
 *   P3 participation     participating_channels a non-empty int array,
 *                        participating_channels_at within 30 days,
 *                        participating_channels_device_ids non-empty.
 *   P4 base ladder       base_ladder_asserts_segments === true. Stricter than
 *                        the gate (which treats absent as advisory).
 *   P5 gate              the readiness gate is armed (gameday_gate_blocking
 *                        empty).
 *   P6 reachable         a getInfo probe when the start is minted; two
 *                        consecutive failures 5 min apart skip that event's
 *                        start. See decideP6.
 *   P7 app build ≥ 113   INFORMATIONAL ONLY (`lease_hygiene_unknown`). Never
 *                        a skip.
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** `source` on a P6 probe command. The health collector folds only health_probe. */
export const PREFLIGHT_PROBE_SOURCE = "gameday_preflight";
/** Doc-id stem for a P6 probe: fire_gdpre_<controllerId>_<seconds>. */
export const PREFLIGHT_PROBE_ID_PREFIX = "gdpre";

/** P2: the heartbeat is every 30 s; ten missed beats is not a blip. */
export const BRIDGE_STALE_MS = 5 * 60_000;
/** P3: stricter than the 90-day fire floor (participationForFire). */
export const PREFLIGHT_PARTICIPATION_MAX_AGE_MS = 30 * 86_400_000;
/** P6: the second probe is written no sooner than this after the first. */
export const P6_RETRY_GAP_MS = 5 * 60_000;
/**
 * P6: no probe is written this close to the start's fireAt. A probe in flight
 * at fire time would hold the start behind the one-in-flight guard; a check
 * that delays the thing it protects is worse than no check.
 */
export const P6_MIN_LEAD_MS = 3 * 60_000;
/** P7: the first app build that retracts a served account's lease (step C). */
export const MIN_SERVED_APP_BUILD = 113;

export type PreflightReason =
  | "preflight_no_bridge"
  | "preflight_bridge_stale"
  | "preflight_no_participation"
  | "preflight_ladder_unknown"
  | "preflight_ladder_bad"
  | "preflight_gated"
  | "preflight_controller_unreachable";

export const INFO_LEASE_HYGIENE_UNKNOWN = "lease_hygiene_unknown";

/**
 * `config/gameday_planner.preflight_mode`.
 *   enforce (default) — a failing account's starts are not minted.
 *   observe           — everything is evaluated, logged and published, but no
 *                       start is withheld and no P6 skip happens. The escape
 *                       hatch for a first deploy: one tick of evidence before
 *                       pre-flight can change what fires.
 * Anything other than exactly "observe" is enforce: a typo must not disarm it.
 */
export type PreflightMode = "enforce" | "observe";
export function preflightModeFrom(data: Record<string, unknown> | undefined): PreflightMode {
  return data?.preflight_mode === "observe" ? "observe" : "enforce";
}

/**
 * `config/gameday_planner.publish_server_status` — B2's writer. Default ON;
 * only an explicit `false` stops it (then every app falls back within the
 * staleness window, no build needed).
 */
export function publishServerStatusFrom(data: Record<string, unknown> | undefined): boolean {
  return data?.publish_server_status !== false;
}

// ---------------------------------------------------------------------------
// P1–P5, P7
// ---------------------------------------------------------------------------

const asIntArray = (v: unknown): number[] | null => {
  if (!Array.isArray(v)) return null;
  for (const x of v) if (typeof x !== "number" || !Number.isInteger(x) || x < 0) return null;
  return v as number[];
};
const millis = (t: unknown): number | null => {
  const v = t as { toMillis?: () => number } | null | undefined;
  return v && typeof v.toMillis === "function" ? v.toMillis() : null;
};

/** P1. `null` = the lookup errored → pass (fail open). */
export function checkBridgePaired(paired: boolean | null): PreflightReason | null {
  return paired === false ? "preflight_no_bridge" : null;
}

/** P2. `updateMs` null = no bridge_status/current at all. */
export function checkBridgeFresh(updateMs: number | null, nowMs: number): PreflightReason | null {
  if (updateMs === null) return "preflight_bridge_stale";
  return nowMs - updateMs > BRIDGE_STALE_MS ? "preflight_bridge_stale" : null;
}

/** P3, over the controller document the planner fires into. */
export function checkParticipation(
  controller: Record<string, unknown> | null,
  nowMs: number
): PreflightReason | null {
  if (!controller) return "preflight_no_participation";
  const chans = asIntArray(controller.participating_channels);
  const devs = asIntArray(controller.participating_channels_device_ids);
  const at = millis(controller.participating_channels_at);
  if (!chans || chans.length === 0) return "preflight_no_participation";
  if (!devs || devs.length === 0) return "preflight_no_participation";
  if (at === null || nowMs - at > PREFLIGHT_PARTICIPATION_MAX_AGE_MS) {
    return "preflight_no_participation";
  }
  return null;
}

/** P4. Tri-state input, two failure reasons. */
export function checkLadder(controller: Record<string, unknown> | null): PreflightReason | null {
  const v = controller?.base_ladder_asserts_segments;
  if (v === true) return null;
  return v === false ? "preflight_ladder_bad" : "preflight_ladder_unknown";
}

/** P5. */
export function checkGate(gate: { armed: boolean }): PreflightReason | null {
  return gate.armed ? null : "preflight_gated";
}

/** "2.5.10+112" → 112. Null when there is no build number. */
export function appBuildNumber(version: unknown): number | null {
  if (typeof version !== "string") return null;
  const m = /\+(\d+)\s*$/.exec(version);
  return m ? Number(m[1]) : null;
}

/** P7 — informational. */
export function checkAppBuild(version: unknown): string | null {
  const b = appBuildNumber(version);
  return b !== null && b >= MIN_SERVED_APP_BUILD ? null : INFO_LEASE_HYGIENE_UNKNOWN;
}

export interface PreflightInputs {
  bridgePaired: boolean | null;
  bridgeStatusUpdateMs: number | null;
  controller: Record<string, unknown> | null;
  gate: { armed: boolean };
  /** True when one of the account's upcoming events has a P6 `unreachable` verdict. */
  p6Unreachable: boolean;
  appVersion: unknown;
  nowMs: number;
}

export interface PreflightVerdict {
  ok: boolean;
  /** Skip reasons, in check order (P1 → P6). Empty when ok. */
  reasons: PreflightReason[];
  /** Informational (P7). Never affects `ok`. */
  info: string[];
}

/** The whole pre-flight for one account on one tick. */
export function evaluatePreflight(i: PreflightInputs): PreflightVerdict {
  const reasons: PreflightReason[] = [];
  const push = (r: PreflightReason | null) => {
    if (r !== null) reasons.push(r);
  };
  push(checkBridgePaired(i.bridgePaired));
  push(checkBridgeFresh(i.bridgeStatusUpdateMs, i.nowMs));
  push(checkParticipation(i.controller, i.nowMs));
  push(checkLadder(i.controller));
  push(checkGate(i.gate));
  if (i.p6Unreachable) reasons.push("preflight_controller_unreachable");
  const info: string[] = [];
  const p7 = checkAppBuild(i.appVersion);
  if (p7 !== null) info.push(p7);
  return { ok: reasons.length === 0, reasons, info };
}

// ---------------------------------------------------------------------------
// P6 — controller reachability, per event
// ---------------------------------------------------------------------------

export interface P6Probe {
  commandId: string;
  writtenAtMs: number;
}

/** Persisted on the session as `preflight_p6`. */
export interface P6Record {
  probes: P6Probe[];
  verdict: "pending" | "ok" | "unreachable";
}

export type P6Action =
  | { kind: "write_probe"; n: 1 | 2 }
  | { kind: "wait" }
  | { kind: "ok" }
  | { kind: "unreachable" }
  | { kind: "too_close" };

const IN_FLIGHT = new Set(["pending", "executing"]);

/** Parse a stored record defensively; anything malformed reads as "no probes yet". */
export function p6RecordFrom(raw: unknown): P6Record | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const verdict =
    r.verdict === "ok" || r.verdict === "unreachable" || r.verdict === "pending"
      ? r.verdict
      : "pending";
  const probes = Array.isArray(r.probes)
    ? (r.probes as unknown[])
        .filter(
          (p): p is P6Probe =>
            !!p &&
            typeof (p as P6Probe).commandId === "string" &&
            typeof (p as P6Probe).writtenAtMs === "number"
        )
        .slice(0, 2)
    : [];
  return { probes, verdict };
}

/**
 * The next P6 step for one event. PURE.
 *
 * `statuses[i]` is the status of `record.probes[i]`'s command, or null when the
 * command document is missing (never written, or swept) — a missing probe is
 * re-written, never read as a failure.
 *
 *   no probe yet                     → write probe 1 (unless too close to fire)
 *   probe in flight                  → wait
 *   probe completed                  → ok (sticky)
 *   probe 1 failed, < 5 min ago      → wait
 *   probe 1 failed, ≥ 5 min ago      → write probe 2 (unless too close)
 *   probe 2 failed                   → unreachable (sticky)
 *   too close to the start's fireAt  → too_close: no more probing, the
 *                                      verdict stays pending (= pass). One
 *                                      failure alone never skips a start.
 */
export function decideP6(args: {
  record: P6Record | null;
  statuses: Array<string | null>;
  nowMs: number;
  startFireAtMs: number;
}): P6Action {
  const { record, statuses, nowMs, startFireAtMs } = args;
  if (record?.verdict === "ok") return { kind: "ok" };
  if (record?.verdict === "unreachable") return { kind: "unreachable" };
  const tooClose = startFireAtMs - nowMs < P6_MIN_LEAD_MS;
  const probes = record?.probes ?? [];

  if (probes.length === 0) return tooClose ? { kind: "too_close" } : { kind: "write_probe", n: 1 };

  const s1 = statuses[0] ?? null;
  if (s1 === null) return tooClose ? { kind: "too_close" } : { kind: "write_probe", n: 1 };
  if (IN_FLIGHT.has(s1)) return { kind: "wait" };
  if (s1 === "completed") return { kind: "ok" };

  // Probe 1 reached a failure (failed / expired / timeout).
  if (probes.length === 1) {
    if (nowMs - probes[0].writtenAtMs < P6_RETRY_GAP_MS) return { kind: "wait" };
    return tooClose ? { kind: "too_close" } : { kind: "write_probe", n: 2 };
  }
  const s2 = statuses[1] ?? null;
  if (s2 === null) return tooClose ? { kind: "too_close" } : { kind: "write_probe", n: 2 };
  if (IN_FLIGHT.has(s2)) return { kind: "wait" };
  if (s2 === "completed") return { kind: "ok" };
  return { kind: "unreachable" };
}

/**
 * Does a P6 `unreachable` verdict on this session still hold the ACCOUNT out?
 * Until that game's kickoff: the controller is the same for every team, so a
 * house that cannot be reached for one start is not served for another in the
 * same window. After kickoff the next event gets its own probes.
 */
export function p6HoldsAccount(
  session: Record<string, unknown> | undefined,
  nowMs: number
): boolean {
  if (!session) return false;
  const rec = p6RecordFrom(session.preflight_p6);
  if (rec?.verdict !== "unreachable") return false;
  const start = typeof session.gameStartMs === "number" ? session.gameStartMs : null;
  return start !== null && nowMs < start;
}

// ---------------------------------------------------------------------------
// B2 — the users/{uid}.gameday_server contract (the server half)
// ---------------------------------------------------------------------------

export interface NextFire {
  event_id: string;
  team_slug: string | null;
  seq: string;
  fire_at_ms: number;
}

export interface ServerStatusCore {
  served: boolean;
  teams: string[];
  preflight: { ok: boolean; reasons: string[]; info: string[]; mode: PreflightMode } | null;
  next_fire: NextFire | null;
}

/**
 * The comparable part of `gameday_server` — everything except the clocks
 * (`checked_at`, `preflight.at`) and the dispatcher-owned `last_fire`. A
 * non-served account is rewritten only when this changes; a served one every
 * tick (D1: the heartbeat that lets the app distrust a dead planner).
 */
export function serverStatusKey(core: ServerStatusCore): string {
  return JSON.stringify({
    served: core.served,
    teams: [...core.teams].sort(),
    preflight: core.preflight
      ? {
          ok: core.preflight.ok,
          reasons: core.preflight.reasons,
          info: core.preflight.info,
          mode: core.preflight.mode,
        }
      : null,
    next_fire: core.next_fire,
  });
}

/** The same key, read back from a stored `gameday_server` map. */
export function storedServerStatusKey(stored: unknown): string | null {
  if (!stored || typeof stored !== "object") return null;
  const s = stored as Record<string, unknown>;
  const pf = s.preflight as Record<string, unknown> | null | undefined;
  const nf = s.next_fire as Record<string, unknown> | null | undefined;
  const nfMs = nf ? millis(nf.fire_at) : null;
  return serverStatusKey({
    served: s.served === true,
    teams: Array.isArray(s.teams) ? (s.teams as unknown[]).filter((t): t is string => typeof t === "string") : [],
    preflight: pf
      ? {
          ok: pf.ok === true,
          reasons: Array.isArray(pf.reasons) ? (pf.reasons as string[]) : [],
          info: Array.isArray(pf.info) ? (pf.info as string[]) : [],
          mode: pf.mode === "observe" ? "observe" : "enforce",
        }
      : null,
    next_fire:
      nf && typeof nf.event_id === "string" && typeof nf.seq === "string" && nfMs !== null
        ? {
            event_id: nf.event_id,
            team_slug: typeof nf.team_slug === "string" ? nf.team_slug : null,
            seq: nf.seq,
            fire_at_ms: nfMs,
          }
        : null,
  });
}

// ---------------------------------------------------------------------------
// B3 — scorecard identity
// ---------------------------------------------------------------------------

export const SCORECARD_COLLECTION = "gameday_scorecard";
export const SCORECARD_ENTRIES = "entries";

/** The game's LOCAL date ("YYYY-MM-DD") — a 7:15 PM Thursday game is Thursday's. */
export function scorecardDateKey(gameStartMs: number, offsetHours: number): string {
  return new Date(gameStartMs + offsetHours * 3_600_000).toISOString().slice(0, 10);
}

export function scorecardEntryId(uid: string, eventId: string): string {
  return `${uid}_${eventId}`;
}
