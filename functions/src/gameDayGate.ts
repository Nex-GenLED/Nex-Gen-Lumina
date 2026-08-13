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
 * THE THREE CHECKS
 *
 *   R1 FLOOR — an everyday schedule exists. Deliberately NOT `base_boundaries`:
 *      those are device timers the healer published, and an account can have
 *      boundaries with no schedule (Ellie does). Read from BOTH
 *      `users/{uid}.schedules` (array) and the `/schedules` subcollection —
 *      the #TD-1 dual state is live, and either counts.
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
  | "gated_no_floor"
  | "gated_no_facts"
  | "gated_ladder_bad";

/** Non-blocking. Recorded so an allowed-but-unverified account is visible. */
export const GATE_ADVISORY_LADDER_UNKNOWN = "gated_no_ladder_unknown";

export interface ReadinessInputs {
  /** `users/{uid}.schedules` is a non-empty array. */
  hasScheduleArray: boolean;
  /** The `/users/{uid}/schedules` subcollection has at least one doc. */
  hasScheduleSubcollection: boolean;
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

  if (!i.hasScheduleArray && !i.hasScheduleSubcollection) {
    blocking.push("gated_no_floor");
  }
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
