/**
 * fireJobs — S3 shared contract. PURE (no firebase-admin at module scope) so
 * functions/test/unit can exercise every decision against compiled lib/ with no
 * emulator and no IO.
 *
 * WHAT S3 IS FOR
 * --------------
 * Game Day and Neighborhood Sync are 100% app-open-only today:
 * `kSportsBackgroundServiceEnabled = false` compiles out both background
 * workers (audit/UNATTENDED_OPERATION.md §0), and iOS background fetch is
 * opportunistic — it will not wake an app for a specific wall-clock instant. A
 * server-side dispatcher is the only mechanism that can fire an event into a
 * house whose owner is away with the app closed.
 *
 * WHAT THIS MODULE DOES NOT DO — deliberately, per the brief:
 *   - no Game Day logic (S5, and it needs S3b's channel denormalization first)
 *   - no sync fanout (gated on consent parity + the windowed-consent model)
 *   - no state-mutating jobs. COMMAND_SAFETY §4.2 is a standing constraint, and
 *     [assertPayloadIsFireSafe] enforces it in code rather than in prose.
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Collection under each user. See audit/S3_DISPATCHER.md §1 for the shape. */
export const FIRE_JOBS_COLLECTION = "fire_jobs";

/** `source` stamped on dispatched commands, so they are trivially separable. */
export const FIRE_SOURCE = "fire_job";

/**
 * How late a job may be dispatched before it is abandoned.
 *
 * Beyond this the event boundary has meaningfully passed: firing "sunset
 * lighting" four minutes into full dark is worse than not firing it, because
 * the customer sees a change with no cause. Terminal — a too-late job is never
 * retried.
 */
export const MAX_FIRE_LATENESS_MS = 90_000;

/**
 * Bridge budget: how long the bridge has to pick a fire command up.
 *
 * WHY THIS IS MEASURED FROM DISPATCH TIME, NOT FROM fireAt — a correction to
 * SCHEDULING_ARCHITECTURE_V2 §4 Layer 2.
 *
 * V2 specifies `expiresAt = fireAt + graceWindow`. With a MINUTE cron that
 * silently shrinks the bridge's budget by however late the tick ran: a job due
 * at 19:00:00 dispatched at 19:00:45 would have only 45 s left of a 90 s
 * window — below the MEASURED 30-32 s worst case plus any margin, so a
 * perfectly healthy bridge under load would be marked `expired` and the fire
 * silently dropped. The lateness of the DISPATCHER would be charged to the
 * BRIDGE, which is both wrong and undetectable.
 *
 * Splitting it into two independent knobs fixes that:
 *   - MAX_FIRE_LATENESS_MS bounds how stale a fire may be when it starts
 *   - FIRE_GRACE_MS gives the bridge a CONSTANT, adequate budget
 * Worst-case execution is therefore fireAt + 90 s + 90 s = 3 min, bounded by
 * construction, while the bridge always gets its full window.
 *
 * 90 s, against the same three constraints S6 used:
 *   - ~3x the measured 30-32 s tail under queue pressure
 *   - >= MIN_SWEEPABLE_AGE_MS (60 s), or the sweeper could not enforce it
 *   - below DEFAULT_COMMAND_TTL_MS (120 s): a scheduled fire must not outlive a
 *     command a human is actually waiting on
 */
export const FIRE_GRACE_MS = 90_000;

/**
 * Command types a fire job may use. NOT an open set.
 *
 * `ping` exists for the Part 3 shadow run — the bridge acknowledges it locally
 * with no WLED request (esp32-bridge/src/main.cpp), so it measures the transport
 * end to end at zero customer risk.
 */
export const ALLOWED_FIRE_TYPES = ["applyJson", "ping"] as const;
export type FireType = (typeof ALLOWED_FIRE_TYPES)[number];

/**
 * Top-level WLED keys a scheduled fire may NEVER carry.
 *
 * COMMAND_SAFETY §4.2: "Route only fire jobs through the scheduled path. Never a
 * state-mutating operation — no psave, no applyConfig, no pairing — where
 * 'executed 60 s late' is not equivalent to 'executed'."
 *
 * That was written as prose and would have stayed prose. A `type: "applyJson"`
 * whose PAYLOAD is `{"psave": 5}` sails past a type allowlist and reaches
 * POST /json/state, which is exactly how a preset gets written by a cron. So the
 * payload is inspected, not just the type.
 *
 *   psave → writes a preset (and can capture frz:true, poisoning it — see
 *           audit/FROZEN_SEGMENT.md; a preset that fires dark forever)
 *   pdel  → deletes a preset
 *   rb    → reboots the controller, which boots the strip LIT (def.on)
 *
 * `ps` (preset LOAD) is deliberately ALLOWED: it is an absolute state load, the
 * same idempotent shape as any other fire.
 */
export const FORBIDDEN_PAYLOAD_KEYS = ["psave", "pdel", "rb"] as const;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TimestampLike {
  toMillis(): number;
}

export type FireJobState =
  | "scheduled"
  | "dispatched"
  | "completed"
  | "failed"
  | "expired"
  | "skipped";

export interface FireJobDoc {
  /** Stable identity of the logical event this fire belongs to. */
  eventId?: unknown;
  /** Which fire within the event: "start", "end", "reassert", … */
  seq?: unknown;
  controllerId?: unknown;
  fireAt?: TimestampLike | null;
  /** JSON STRING, not a map. See buildFireCommand for why. */
  payload?: unknown;
  type?: unknown;
  state?: unknown;
  commandId?: unknown;
  attempts?: unknown;
}

export interface DispatchDecision {
  dispatch: boolean;
  /** Set when dispatch is false. */
  reason: string;
  /** True when the job can never be dispatched and should be terminalized. */
  terminal: boolean;
}

// ---------------------------------------------------------------------------
// Payload safety
// ---------------------------------------------------------------------------

export interface PayloadCheck {
  ok: boolean;
  reason: string;
}

/**
 * Enforce the §4.2 constraint against the actual payload.
 *
 * Two layers, because the parse can fail on a payload that still contains a
 * dangerous key:
 *   1. a raw substring scan (catches a malformed body that never parses)
 *   2. a parsed top-level key check
 *
 * Fails CLOSED: anything unparseable is refused. A scheduled writer has no user
 * present to notice a malformed fire, so "refuse" is the only safe default.
 */
export function assertPayloadIsFireSafe(
  type: unknown,
  payload: unknown
): PayloadCheck {
  if (typeof type !== "string" || !(ALLOWED_FIRE_TYPES as readonly string[]).includes(type)) {
    return { ok: false, reason: `type_not_allowed:${String(type)}` };
  }

  // ping carries no body the bridge ever reads.
  if (type === "ping") return { ok: true, reason: "" };

  if (typeof payload !== "string" || payload.length === 0) {
    return { ok: false, reason: "payload_not_a_json_string" };
  }

  const lowered = payload.toLowerCase();
  for (const key of FORBIDDEN_PAYLOAD_KEYS) {
    if (lowered.includes(`"${key}"`)) {
      return { ok: false, reason: `forbidden_key_in_raw_payload:${key}` };
    }
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(payload);
  } catch {
    return { ok: false, reason: "payload_not_parseable" };
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { ok: false, reason: "payload_not_an_object" };
  }
  for (const key of Object.keys(parsed as Record<string, unknown>)) {
    if ((FORBIDDEN_PAYLOAD_KEYS as readonly string[]).includes(key)) {
      return { ok: false, reason: `forbidden_key:${key}` };
    }
  }
  return { ok: true, reason: "" };
}

// ---------------------------------------------------------------------------
// Dispatch decision
// ---------------------------------------------------------------------------

/**
 * Should this job be dispatched on this tick?
 *
 * TERMINAL vs TRANSIENT is the distinction that matters and is easy to get
 * wrong. A job blocked by the in-flight guard must stay `scheduled` and be
 * retried on the next tick — the guard is a momentary condition. A job that is
 * too late, or unsafe, or has no resolvable target, can never succeed and must
 * be terminalized so it stops being re-read every minute forever.
 */
export function decideDispatch(args: {
  job: FireJobDoc;
  nowMs: number;
  maxLatenessMs?: number;
}): DispatchDecision {
  const { job, nowMs } = args;
  const maxLateness = args.maxLatenessMs ?? MAX_FIRE_LATENESS_MS;

  if (job.state !== "scheduled") {
    return { dispatch: false, reason: `state_not_scheduled:${String(job.state)}`, terminal: false };
  }

  const fireAt = job.fireAt;
  if (!fireAt || typeof fireAt.toMillis !== "function") {
    return { dispatch: false, reason: "no_fireAt", terminal: true };
  }
  const fireAtMs = fireAt.toMillis();

  if (fireAtMs > nowMs) {
    return { dispatch: false, reason: "not_yet_due", terminal: false };
  }

  if (nowMs - fireAtMs > maxLateness) {
    return {
      dispatch: false,
      reason: `too_late:${Math.round((nowMs - fireAtMs) / 1000)}s`,
      terminal: true,
    };
  }

  const safety = assertPayloadIsFireSafe(job.type, job.payload);
  if (!safety.ok) {
    return { dispatch: false, reason: `unsafe:${safety.reason}`, terminal: true };
  }

  if (typeof job.controllerId !== "string" || job.controllerId.length === 0) {
    return { dispatch: false, reason: "no_controllerId", terminal: true };
  }

  return { dispatch: true, reason: "due", terminal: false };
}

/**
 * The command document a dispatched job produces.
 *
 * `payload` is a JSON STRING, matching every existing writer. That is not
 * stylistic: the iOS Firestore SDK crashes on deeply-nested arrays (the #84
 * class), which is why `applySyncPattern` and `CloudRelayRepository` both
 * stringify. A fire job that stored a map would reintroduce it the first time a
 * payload carried `col: [[r,g,b,w]]`.
 *
 * `controllerIp` is ALWAYS set, from a server-resolved value. The omit path is
 * bench-refuted: an untargeted probe got `ERROR: HTTP -1` while 282 named
 * commands to the same controller succeeded, because the bridge's paired IP can
 * be stale or — as measured on the bench — literally `0.0.0.0`
 * (audit/CONTROLLER_HEALTH.md §1.1, §9 Q4).
 */
export function buildFireCommand(args: {
  type: FireType;
  payload: string;
  controllerId: string;
  controllerIp: string;
  jobId: string;
  eventId: string;
  dispatchAtMs: number;
  graceMs?: number;
}): { doc: Record<string, unknown>; expiresAtMs: number } {
  const grace = args.graceMs ?? FIRE_GRACE_MS;
  const expiresAtMs = args.dispatchAtMs + grace;
  return {
    expiresAtMs,
    doc: {
      type: args.type,
      payload: args.type === "ping" ? "{}" : args.payload,
      controllerId: args.controllerId,
      controllerIp: args.controllerIp,
      status: "pending",
      source: FIRE_SOURCE,
      webhookUrl: null,
      fireJobId: args.jobId,
      eventId: args.eventId,
    },
  };
}

// ---------------------------------------------------------------------------
// Reconciliation
// ---------------------------------------------------------------------------

/** Map a terminal command status onto the job state that records it. */
export function jobStateForCommandStatus(status: unknown): FireJobState | null {
  switch (status) {
    case "completed":
      return "completed";
    case "failed":
      return "failed";
    case "expired":
      return "expired";
    case "timeout":
      // Written by the APP's watchdog, never by the bridge or sweeper. A fire
      // has no app waiting on it, so this should not occur — recorded as failed
      // rather than silently ignored, so it shows up if it ever does.
      return "failed";
    default:
      return null; // pending / executing / absent — still in flight
  }
}

// ---------------------------------------------------------------------------
// Metrics (Part 3)
// ---------------------------------------------------------------------------

/**
 * Nearest-rank percentile over an unsorted sample array.
 * Returns null for an empty sample rather than 0 — a fabricated zero latency
 * would read as "instant" instead of "unmeasured".
 */
export function percentile(samples: number[], p: number): number | null {
  const clean = samples.filter((n) => typeof n === "number" && Number.isFinite(n) && n >= 0);
  if (clean.length === 0) return null;
  const sorted = [...clean].sort((a, b) => a - b);
  const rank = Math.ceil((p / 100) * sorted.length);
  const idx = Math.min(sorted.length - 1, Math.max(0, rank - 1));
  return sorted[idx];
}

export interface MetricsRollup {
  count: number;
  p50: number | null;
  p95: number | null;
  min: number | null;
  max: number | null;
}

export function rollup(samples: number[]): MetricsRollup {
  const clean = samples.filter((n) => typeof n === "number" && Number.isFinite(n) && n >= 0);
  return {
    count: clean.length,
    p50: percentile(clean, 50),
    p95: percentile(clean, 95),
    min: clean.length ? Math.min(...clean) : null,
    max: clean.length ? Math.max(...clean) : null,
  };
}

/**
 * Cap a growing sample array. Keeps the MOST RECENT samples — a fire path that
 * degrades over a day should be visible in that day's percentiles rather than
 * being masked by the healthy morning.
 */
export const MAX_SAMPLES_PER_DAY = 500;

export function appendSamples(
  existing: unknown,
  incoming: number[],
  cap: number = MAX_SAMPLES_PER_DAY
): number[] {
  const prev = Array.isArray(existing)
    ? (existing as unknown[]).filter((n): n is number => typeof n === "number")
    : [];
  const merged = [...prev, ...incoming];
  return merged.length <= cap ? merged : merged.slice(merged.length - cap);
}
