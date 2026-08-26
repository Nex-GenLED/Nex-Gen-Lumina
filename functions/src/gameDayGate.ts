/**
 * gameDayGate — per-account readiness for unattended Game Day fires. PURE.
 *
 * WHAT THIS REPLACES. `base_layer_gate.dart` was a client prompt that says of
 * itself: *"⚠️ NOT A GUARD. If anything here fails — no context, dialog throws,
 * provider unavailable — the enable PROCEEDS."* It rendered only on the enable
 * toggle, was session-dismissible, and every one of the nine live Game Day
 * accounts predates it, so it has never gated anybody. Seven of those nine have
 * no everyday schedule at all.
 *
 * WHY THE PLANNER IS THE ENFORCEMENT POINT. A client-side guard can only cover
 * the paths it is attached to — and enablement has at least three (the toggle,
 * the create-and-enable path, the AI recurring-sports handler). The planner
 * iterates every `enabled == true` config every five minutes, so it covers all
 * of them, plus grandfathered accounts, plus any enable path added later,
 * without knowing they exist. The client UI reflects this verdict; it never
 * enforces it.
 *
 * WHAT FAILING MEANS. Not a refusal and not a warning — the account's configs
 * run LOG-ONLY, which is the same shape the `uid_allowlist` already produces
 * for a scoped-out account. One mechanism, two reasons to use it: the allowlist
 * protects the FLEET from unproven code, this gate protects a CUSTOMER from
 * unattended wrong lighting. They compose; neither replaces the other.
 *
 * THE TWO CHECKS
 *
 *   R1 FLOOR — REMOVED 2026-08-26. It required an everyday schedule to exist
 *      before Game Day could fire, and that was wrong as product: Game Day must
 *      work with ZERO recurring schedules configured. Single-day use and
 *      Game-Day-only accounts (no recurring schedule, ever) are both legitimate
 *      and common, and this check treated them as broken. It was also the
 *      single largest source of gating in production — 7 of the surveyed
 *      accounts were held in log-only on `no_floor` alone, the reviewer account
 *      among them.
 *
 *      The reason string survives in `GateBlockingReason` on purpose; see the
 *      note there. Nothing produces it any more.
 *
 *   R2 BASE LADDER — the account's presets provably assert per-segment state.
 *      This is the #67 leak condition: an exclusion darkens a channel for the
 *      event, and the end-fire restore is a preset load, so a preset that does
 *      NOT assert per-segment state leaves that channel dark afterwards.
 *      TRI-STATE, and the asymmetry is deliberate: `true` passes, `false` fails
 *      CLOSED because known-bad is the one thing worth blocking on, and
 *      absent is unknown-and-ALLOWED. Unknown is not a small case today — the
 *      fact does not exist yet, so every account is unknown, and failing closed
 *      on it would put the entire fleet in log-only awaiting a healer pass that
 *      only happens when each customer next opens the app on their LAN.
 *      Recorded as an advisory so "allowed" never reads as "verified".
 *
 *   R3 PARTICIPATION FACTS — the healer has published
 *      `participating_channels_device_ids` for the account's controller. #67's
 *      partition needs it; the `partition_unavailable` fallback exists, but an
 *      armed unattended fire should not lean on a fallback.
 *
 * Every refusal is its own reason string. That is the #68 lesson: a bucket that
 * increments without naming who or why reconciles perfectly and tells you
 * nothing.
 */

/** Blocking reasons — any one of these puts the account in log-only. */
export type GateBlockingReason =
  /**
   * HISTORICAL ONLY — no longer produced (R1 removed 2026-08-26).
   *
   * Retained in the union deliberately. ~7 live accounts have
   * `["gated_no_floor"]` persisted in `users/{uid}.gameday_gate_blocking` from
   * before the removal, and `graduationEvents` reads that stored array as
   * `GateBlockingReason[]`. Keeping the literal is what lets those accounts
   * emit `graduated_gated_no_floor` on their next tick instead of silently
   * flipping to armed — the un-gating shows up in the plan log, which is the
   * whole reason graduation events exist. Delete this only once no persisted
   * verdict contains it.
   */
  | "gated_no_floor"
  | "gated_no_facts"
  | "gated_ladder_bad";

/** Non-blocking. Recorded so an allowed-but-unverified account is visible. */
export const GATE_ADVISORY_LADDER_UNKNOWN = "gated_no_ladder_unknown";

export interface ReadinessInputs {
  // `hasScheduleArray` / `hasScheduleSubcollection` were removed with R1. They
  // are not deprecated-but-accepted: leaving them would have kept
  // planGameDayFires paying for a per-account subcollection read every tick to
  // feed a check that no longer exists.
  /** `participating_channels_device_ids` present and non-empty. */
  hasParticipationFacts: boolean;
  /**
   * R2 tri-state. `true` verified good, `false` verified BAD, `null`/`undefined`
   * not published. Never coerce: `!ladderAssertsSegments` would collapse
   * unknown into bad and log-only the fleet.
   */
  ladderAssertsSegments?: boolean | null;
}

export interface GateVerdict {
  armed: boolean;
  blocking: GateBlockingReason[];
  advisory: string[];
}

/** PURE. The whole gate. */
export function evaluateAccountReadiness(i: ReadinessInputs): GateVerdict {
  const blocking: GateBlockingReason[] = [];
  const advisory: string[] = [];

  // R1 (floor) intentionally absent — see the header. An account with no
  // schedule of any kind is a legitimate Game Day account and arms normally.
  if (!i.hasParticipationFacts) {
    blocking.push("gated_no_facts");
  }
  if (i.ladderAssertsSegments === false) {
    blocking.push("gated_ladder_bad");
  } else if (i.ladderAssertsSegments !== true) {
    advisory.push(GATE_ADVISORY_LADDER_UNKNOWN);
  }

  return { armed: blocking.length === 0, blocking, advisory };
}

/**
 * PURE. What turned green since the last evaluation.
 *
 * Graduation is automatic and requires no re-toggle: the account is re-evaluated
 * every tick, so setting a schedule arms it on the next one. This exists so the
 * transition is LEGIBLE — an account that silently starts firing is as hard to
 * explain as one that silently stops.
 *
 * `prev` null means never evaluated, which is not a graduation: a first
 * evaluation that passes was never gated, and reporting it as having graduated
 * would invent a history the account does not have.
 */
export function graduationEvents(
  prev: GateBlockingReason[] | null | undefined,
  next: GateBlockingReason[]
): string[] {
  if (!prev || prev.length === 0) return [];
  const still = new Set(next);
  return prev.filter((r) => !still.has(r)).map((r) => `graduated_${r}`);
}

/**
 * A one-line human summary for the plan log and the in-app reflection.
 *
 * Names what is missing rather than that something is. "Game Day is on, fires
 * begin when your everyday schedule is set" is actionable; "not ready" is not.
 */
export function gateSummary(v: GateVerdict): string {
  if (v.armed) {
    return v.advisory.length > 0
      ? "armed (base ladder unverified)"
      : "armed";
  }
  const parts: string[] = [];
  // Historical verdicts only — R1 no longer produces this. Kept so a stored
  // pre-removal verdict still renders as a sentence rather than as "log-only: ".
  if (v.blocking.includes("gated_no_floor")) {
    parts.push("no everyday schedule");
  }
  if (v.blocking.includes("gated_no_facts")) {
    parts.push("controller has not reported its channels");
  }
  if (v.blocking.includes("gated_ladder_bad")) {
    parts.push("base presets do not assert per-segment state");
  }
  return `log-only: ${parts.join("; ")}`;
}

/** Aggregate counts for the tick line. Derived, never independently recounted. */
export interface GateSummaryCounts {
  evaluated: number;
  gated: number;
  armed: number;
  blocking: Record<string, number>;
  advisory: Record<string, number>;
}

/**
 * PURE. Fold the SAME verdicts the per-account rows were built from.
 *
 * Single source by construction. The alternative — recomputing counts from the
 * inputs a second time — is how a summary and its own detail rows come to
 * disagree, and then neither can be trusted. The caller pushes rows from this
 * array and summarises this array; nothing is counted twice.
 */
export function summarizeGate(verdicts: GateVerdict[]): GateSummaryCounts {
  const c: GateSummaryCounts = {
    evaluated: verdicts.length,
    gated: 0,
    armed: 0,
    blocking: {},
    advisory: {},
  };
  for (const v of verdicts) {
    if (v.armed) c.armed++;
    else c.gated++;
    for (const b of v.blocking) c.blocking[b] = (c.blocking[b] ?? 0) + 1;
    for (const a of v.advisory) c.advisory[a] = (c.advisory[a] ?? 0) + 1;
  }
  return c;
}

/**
 * One operator-readable line.
 *
 * ADVISORY IS COUNTED SEPARATELY AND SAID SEPARATELY. Today every account
 * carries `no_ladder_unknown`, so a line that merged the two would read as
 * "10 blocked" when the true figure is 7 — the advisory ones are ARMED. A
 * summary that overstates a block is worse than no summary: it invites someone
 * to go fix nothing.
 */
export function formatGateSummary(c: GateSummaryCounts): string {
  const fmt = (m: Record<string, number>) =>
    Object.keys(m)
      .sort()
      .map((k) => `${k.replace(/^gated_/, "")}:${m[k]}`)
      .join(", ");
  const parts = [`gate: ${c.gated} accounts gated {${fmt(c.blocking)}}`];
  const adv = Object.values(c.advisory).reduce((a, b) => a + b, 0);
  if (adv > 0) parts.push(`${adv} advisory {${fmt(c.advisory)}}`);
  parts.push(`${c.armed} armed`);
  // ASCII-ONLY SEPARATOR. This line exists to be scanned through tooling, and
  // a middot renders as "?" in the gcloud console — the first thing it did in
  // production was become unreadable in the place it is read.
  return parts.join(" | ");
}
