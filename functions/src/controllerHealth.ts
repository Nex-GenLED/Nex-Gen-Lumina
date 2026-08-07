/**
 * controllerHealth — S6 shared contract. PURE (no firebase-admin at module
 * scope) so functions/test/unit can exercise every decision against compiled
 * lib/ with no emulator and no IO.
 *
 * WHY THIS EXISTS
 * ---------------
 * audit/OFF_LAN_CAPABILITY.md §3.3: "There is no controller-health signal in
 * the fleet at all... A bridge can be perfectly green while the controller
 * behind it has unhealed presets, a dead NTP host, and stale timers."
 *
 * On 2026-08-05 that cost was itemised for the first time (audit/BRIDGE_TRIAGE.md):
 * two customer bridges had been dark for 15.0 and 21.4 days, and a third
 * customer had a powered, ONLINE, never-paired bridge for five days with 17
 * failed commands. Nobody knew — not the customer, not the dealer, not Tyler.
 * Everyday lighting is device-resident, so the lights worked perfectly every
 * night and nothing surfaced the failure. The triage was a hand-written script.
 *
 * THE MECHANISM, DEMONSTRATED BEFORE IT WAS BUILT
 * -----------------------------------------------
 * The same evening, pairing that third bridge produced this, unprompted:
 *
 *   21:15:58Z  getInfo  completed
 *     result={"ver":"0.15.1","vid":2507300,"cn":"Kōsen","release":"ESP32_Ethernet"}
 *
 * A command's `result` field carries WLED's own response body, relayed back
 * from a controller nobody could otherwise reach — the customer's firmware
 * version and build id, for free, with ZERO firmware work. That is exactly what
 * SCHEDULING_ARCHITECTURE_V2.md §6 predicted, and it is what this module turns
 * from an accident into a daily measurement.
 *
 * WHAT THIS DOES NOT COVER — the app half (P5a). Anything requiring /json/cfg —
 * the timer table digest, preset digests, gamma/config state — is LAN-only
 * (CloudRelayRepository.applyConfig throws CfgWriteUnsupportedException; the
 * bridge has no cfg dispatch branch). Those still need a customer who comes
 * home with the app open. This module deliberately covers only the half that
 * needs nobody: reachability, version, and fire outcomes.
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** `source` stamped on every probe command, so they are trivially separable. */
export const PROBE_SOURCE = "health_probe";

/** Probe command type. GET /json/info — READ-ONLY on the device. */
export const PROBE_TYPE = "getInfo";

/**
 * Explicit grace window for a probe command: `expiresAt = fireAt + this`.
 *
 * WHY NOT THE 120 s DEFAULT. `DEFAULT_COMMAND_TTL_MS` is sized for an
 * APP-written command — it must exceed the app's own 45 s watchdog so expiry is
 * invisible to a waiting user (commandSafety.ts). A probe has no user waiting on
 * it and the opposite requirement: it is a LIVENESS MEASUREMENT, so a probe that
 * executes ten minutes late does not tell you the bridge was healthy at the
 * probe instant — it tells you almost nothing. V2 §4 Layer 2 specifies
 * `fireAt + graceWindow`, and this is that window, set explicitly rather than
 * inherited.
 *
 * WHY 90 s specifically, against three measured constraints:
 *   - ~3x the MEASURED 30-32 s worst case under queue pressure
 *     (lib/features/wled/cloud_relay_repository.dart:44-52), so a genuinely
 *     healthy-but-loaded bridge is never marked expired.
 *   - >= MIN_SWEEPABLE_AGE_MS (60 s). The sweeper will not even QUERY commands
 *     younger than that age floor, so a grace below 60 s would be unenforceable
 *     — the probe would claim an expiry the sweeper cannot act on. Locked by a
 *     test so a future edit cannot silently break it.
 *   - Far inside the probe→collect gap (15 min), so every probe is terminal by
 *     the time the collector reads it back.
 */
export const PROBE_GRACE_MS = 90_000;

/**
 * Minutes between the probe pass and the collect pass. Must exceed
 * PROBE_GRACE_MS plus one sweeper tick (60 s) plus headroom, or the collector
 * would read probes that are still `pending` and mis-record them as unknown.
 * 15 min is ~6x the required minimum — generous, and it costs nothing.
 */
export const COLLECT_DELAY_MINUTES = 15;

/**
 * Consecutive failed probes before a controller is reported at each level.
 *
 * TWO TIERS, DELIBERATELY. The brief asked for day-1 detection ("would have
 * caught Ellie at day 1 instead of day 15"), but a single missed probe is also
 * what a router reboot or a five-minute power cut looks like. Paging on one
 * miss trains the reader to ignore the digest, which recreates the exact
 * failure this system exists to fix.
 *
 * So: WARN at 1 (visible in the next digest — day-1 detection, as asked), ALERT
 * at 2 (act on it). Ellie would have appeared as a warning on day 1 and an
 * alert on day 2, instead of being invisible for 15 days.
 */
export const WARN_AFTER_CONSECUTIVE_FAILURES = 1;
export const ALERT_AFTER_CONSECUTIVE_FAILURES = 2;

/**
 * Q3 (Tyler, 2026-08-07) — dark-controller backoff.
 *
 * After this many consecutive failures, drop from daily to weekly probing.
 * Daily writes carry no new information after day two, but going fully silent
 * would miss the recovery; a weekly retry catches a repaired bridge within seven
 * days without a permanent daily write per dark controller.
 *
 * A SUCCESS AT ANY CADENCE RESETS TO DAILY, because success sets
 * consecutiveFailures to 0 and this threshold is read off that counter — there
 * is no separate cadence state to get out of sync.
 */
export const BACKOFF_AFTER_CONSECUTIVE_FAILURES = 3;
export const BACKOFF_RETRY_INTERVAL_MS = 7 * 86_400_000;

/** A registry row `paired` but silent longer than this is a disagreement. */
export const REGISTRY_SILENT_HOURS = 24;

/** A registry row `unpaired` but seen inside this window is heartbeating now. */
export const REGISTRY_FRESH_MINUTES = 60;

/** Terminal command statuses, mirrored from commandSafety for local clarity. */
export const OUTCOME_COMPLETED = "completed";
export const OUTCOME_FAILED = "failed";
export const OUTCOME_EXPIRED = "expired";
/** Written by the APP's 45 s watchdog, never by the bridge or the sweeper. */
export const OUTCOME_TIMEOUT = "timeout";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TimestampLike {
  toMillis(): number;
}

/** The subset of a command document the collector reads. */
export interface ProbeCommandDoc {
  status?: unknown;
  result?: unknown;
  error?: unknown;
  createdAt?: TimestampLike | null;
  completedAt?: TimestampLike | null;
  controllerId?: unknown;
  controllerIp?: unknown;
}

export type ProbeOutcome =
  | "completed"
  | "failed"
  | "expired"
  | "timeout"
  | "pending"
  | "missing";

export interface ProbeClassification {
  outcome: ProbeOutcome;
  /** createdAt → completedAt, in ms. Null when either end is unavailable. */
  latencyMs: number | null;
  /** Bridge-supplied error string, truncated. Empty when none. */
  error: string;
  /** True only for `completed` — the one outcome that counts as a success. */
  success: boolean;
  /**
   * Which layer the failure implicates. This is the whole reason S2 keeps
   * `expired` distinct from `failed`, and it is the single most useful field
   * in the health record:
   *   bridge     → nobody picked the command up
   *   controller → the bridge picked it up and WLED refused or was unreachable
   *   app        → an app watchdog wrote `timeout`; says nothing about a probe
   *   none       → success
   *   unknown    → still pending, or the document is absent
   */
  blame: "none" | "bridge" | "controller" | "app" | "unknown";
}

/** Parsed subset of a WLED /json/info body. Deliberately NOT including `cn`. */
export interface WledInfo {
  wledVersion: string | null;
  wledVid: number | null;
  ledCount: number | null;
  rgbw: boolean | null;
  /** e.g. "ESP32_Ethernet" — build flavour, useful for fleet segmentation. */
  release: string | null;
}

/**
 * Whether this account has a bridge at all, and if so whether it is alive.
 * Q1 (Tyler, 2026-08-07) turns on this distinction:
 *   live   → registry row seen recently
 *   silent → a bridge exists or once reported, but is not reporting now
 *   never  → no registry row AND no bridge_status/current has ever existed
 *
 * `never` is the suppression key: those accounts' probes expire every time, by
 * construction, and alerting on them daily forever would drown the list. They
 * still get PROBED — option (a), skipping them, would have hidden The Iron
 * Reserve, which is the exact case this system exists to catch.
 */
export type BridgePresence = "live" | "silent" | "never";

export interface ControllerHealthRecord {
  controllerId: string;
  lastProbeAt: number | null;
  lastProbeOutcome: ProbeOutcome | null;
  lastProbeBlame: ProbeClassification["blame"] | null;
  lastSuccessAt: number | null;
  /**
   * When the CURRENT run of failures began — stamped on the 0→1 transition and
   * cleared on success.
   *
   * WHY THIS EXISTS (Q3). Under weekly backoff, `consecutiveFailures` counts
   * PROBES, not days: a controller dark 60 days reads as ~11 failures, which
   * badly understates the outage. The counter is still honest about what it
   * measures, so it is not "fixed" — instead duration is read from a real
   * timestamp. `lastSuccessAt` covers a controller that once worked;
   * `firstFailureAt` covers one that never has. Together they make the reported
   * age independent of the sampling rate.
   */
  firstFailureAt: number | null;
  /** Always advanced by the collector, even on `missing`. Proves it ran. */
  lastCollectedAt: number | null;
  consecutiveFailures: number;
  /** Derived from consecutiveFailures; recorded so a skip is auditable. */
  probeCadence: "daily" | "weekly";
  bridgePresence: BridgePresence;
  probeLatencyMs: number | null;
  lastError: string;
  wledVersion: string | null;
  wledVid: number | null;
  ledCount: number | null;
  rgbw: boolean | null;
  wledRelease: string | null;
  bridgeDeviceId: string | null;
  bridgeLastSeen: number | null;
  bridgeFirmwareVersion: string | null;
  bridgeStatus: string | null;
  /**
   * How the probe addressed the controller. Only one value is produced —
   * `server_resolved_ip`. A `bridge_paired_fallback` variant existed and was
   * REMOVED after the bench proved the bridge's paired-IP fallback is stale;
   * see [resolveProbeTarget]. Kept as a recorded field so a future change of
   * strategy is visible in the data rather than silent.
   */
  probeTargeting: "server_resolved_ip" | null;
}

export type AlertKind =
  | "controller_unreachable"
  | "bridge_paired_but_silent"
  | "bridge_superseded_orphan"
  | "bridge_unpaired_but_heartbeating"
  | "bridge_claims_unknown_uid";

export interface HealthAlert {
  kind: AlertKind;
  severity: "warn" | "alert";
  uid: string | null;
  email: string | null;
  displayName: string | null;
  controllerId: string | null;
  deviceId: string | null;
  /** One line, already human-readable. The digest prints these verbatim. */
  detail: string;
  /** Days since the relevant thing last worked. Null when not applicable. */
  ageDays: number | null;
}

// ---------------------------------------------------------------------------
// Probe classification
// ---------------------------------------------------------------------------

/** Trim an error/result string so one bad payload cannot bloat a health doc. */
export function truncate(value: unknown, max = 300): string {
  if (typeof value !== "string") return "";
  return value.length <= max ? value : value.slice(0, max);
}

/**
 * Classify a probe command document read back after the fact.
 *
 * A MISSING document is NOT a failure. `.doc(id).create()` can legitimately
 * have been skipped (one-in-flight guard) or the retention sweep can have
 * deleted it — neither means the controller is unhealthy, and inventing a
 * failure from an absence is how a monitoring system starts lying. `missing`
 * is its own outcome and never increments consecutiveFailures.
 */
export function classifyProbe(
  doc: ProbeCommandDoc | null | undefined
): ProbeClassification {
  if (!doc) {
    return {
      outcome: "missing",
      latencyMs: null,
      error: "",
      success: false,
      blame: "unknown",
    };
  }

  const status = typeof doc.status === "string" ? doc.status : "";
  const error = truncate(doc.error);

  let latencyMs: number | null = null;
  const created = doc.createdAt;
  const completed = doc.completedAt;
  if (
    created &&
    typeof created.toMillis === "function" &&
    completed &&
    typeof completed.toMillis === "function"
  ) {
    const delta = completed.toMillis() - created.toMillis();
    // A negative delta means clock skew or a malformed doc. Report null rather
    // than a nonsense latency — a wrong number is worse than no number.
    latencyMs = delta >= 0 ? delta : null;
  }

  switch (status) {
    case OUTCOME_COMPLETED:
      return { outcome: "completed", latencyMs, error, success: true, blame: "none" };
    case OUTCOME_FAILED:
      return { outcome: "failed", latencyMs, error, success: false, blame: "controller" };
    case OUTCOME_EXPIRED:
      return { outcome: "expired", latencyMs, error, success: false, blame: "bridge" };
    case OUTCOME_TIMEOUT:
      return { outcome: "timeout", latencyMs, error, success: false, blame: "app" };
    default:
      // "pending" or "executing" — the collector ran too early, or the bridge
      // claimed it and never finished. Not counted as a failure.
      return { outcome: "pending", latencyMs, error, success: false, blame: "unknown" };
  }
}

/**
 * Parse the `result` string the bridge copied out of WLED's /json/info response.
 *
 * DELIBERATELY DOES NOT READ `cn`. On 2026-08-05 The Iron Reserve's controller
 * reported `"cn":"Kōsen"` — byte-identical to the bench controller's name. It
 * is a flash-image default, not a per-install identifier, and treating it as one
 * would silently merge two sites. Recorded here so nobody re-adds it.
 *
 * Never throws: a malformed body yields all-nulls, because a probe that
 * round-tripped successfully is still evidence of reachability even if the
 * payload cannot be parsed.
 */
export function parseWledInfo(result: unknown): WledInfo {
  const empty: WledInfo = {
    wledVersion: null,
    wledVid: null,
    ledCount: null,
    rgbw: null,
    release: null,
  };
  if (typeof result !== "string" || result.length === 0) return empty;

  let parsed: Record<string, unknown>;
  try {
    const raw: unknown = JSON.parse(result);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return empty;
    parsed = raw as Record<string, unknown>;
  } catch {
    return empty;
  }

  const leds =
    parsed.leds && typeof parsed.leds === "object" && !Array.isArray(parsed.leds)
      ? (parsed.leds as Record<string, unknown>)
      : {};

  const num = (v: unknown): number | null =>
    typeof v === "number" && Number.isFinite(v) ? v : null;

  return {
    wledVersion: typeof parsed.ver === "string" ? parsed.ver : null,
    wledVid: num(parsed.vid),
    ledCount: num(leds.count),
    rgbw: typeof leds.rgbw === "boolean" ? leds.rgbw : null,
    release: typeof parsed.release === "string" ? parsed.release : null,
  };
}

/**
 * Fold one probe result into the previous health record.
 *
 * `consecutiveFailures` increments ONLY on a definite failure
 * (failed/expired/timeout) and resets to 0 on success. `missing` and `pending`
 * leave the counter untouched — see [classifyProbe] for why an absence must not
 * manufacture a failure.
 *
 * Version fields are STICKY: a failed probe carries no /json/info body, and
 * blanking the last-known version on every failure would destroy exactly the
 * fleet-build signal this system exists to collect. The version you can see is
 * the last one observed, and `lastSuccessAt` tells you how old it is.
 */
export function foldProbeIntoHealth(args: {
  controllerId: string;
  previous: Partial<ControllerHealthRecord> | null;
  classification: ProbeClassification;
  info: WledInfo;
  probedAtMs: number;
  bridge: {
    deviceId: string | null;
    lastSeenMs: number | null;
    firmwareVersion: string | null;
    status: string | null;
  };
  targeting: ControllerHealthRecord["probeTargeting"];
  bridgePresence: BridgePresence;
}): ControllerHealthRecord {
  const {
    controllerId,
    previous,
    classification,
    info,
    probedAtMs,
    bridge,
    targeting,
    bridgePresence,
  } = args;

  const prevFailures =
    typeof previous?.consecutiveFailures === "number" ? previous.consecutiveFailures : 0;

  const isDefiniteFailure =
    classification.outcome === "failed" ||
    classification.outcome === "expired" ||
    classification.outcome === "timeout";

  let consecutiveFailures = prevFailures;
  if (classification.success) consecutiveFailures = 0;
  else if (isDefiniteFailure) consecutiveFailures = prevFailures + 1;

  const observed = classification.success;

  // A `missing` outcome means NO probe document was found — either the
  // one-in-flight guard skipped it, the weekly backoff skipped it, or retention
  // deleted it. It is NOT an observation, so it must not advance the probe
  // fields.
  //
  // THIS IS LOAD-BEARING FOR THE BACKOFF. If `lastProbeAt` were bumped on every
  // collect, a backed-off controller's "7 days since the last probe" clock would
  // reset daily and the weekly retry would NEVER fire — the controller would go
  // permanently dark to us. `lastCollectedAt` carries the "the collector ran"
  // signal instead, so nothing is lost.
  const wasObservedAtAll = classification.outcome !== "missing";

  const firstFailureAt = classification.success
    ? null
    : isDefiniteFailure && prevFailures === 0
      ? probedAtMs // 0 → 1 transition: stamp the start of this dark run
      : previous?.firstFailureAt ?? null;

  return {
    controllerId,
    lastProbeAt: wasObservedAtAll ? probedAtMs : previous?.lastProbeAt ?? null,
    lastProbeOutcome: wasObservedAtAll
      ? classification.outcome
      : previous?.lastProbeOutcome ?? null,
    lastProbeBlame: wasObservedAtAll
      ? classification.blame
      : previous?.lastProbeBlame ?? null,
    lastSuccessAt: observed ? probedAtMs : previous?.lastSuccessAt ?? null,
    firstFailureAt,
    lastCollectedAt: probedAtMs,
    consecutiveFailures,
    probeCadence:
      consecutiveFailures >= BACKOFF_AFTER_CONSECUTIVE_FAILURES ? "weekly" : "daily",
    bridgePresence,
    probeLatencyMs: observed ? classification.latencyMs : previous?.probeLatencyMs ?? null,
    lastError: classification.error,
    // Sticky — see the docstring.
    wledVersion: observed ? info.wledVersion : previous?.wledVersion ?? null,
    wledVid: observed ? info.wledVid : previous?.wledVid ?? null,
    ledCount: observed ? info.ledCount : previous?.ledCount ?? null,
    rgbw: observed ? info.rgbw : previous?.rgbw ?? null,
    wledRelease: observed ? info.release : previous?.wledRelease ?? null,
    bridgeDeviceId: bridge.deviceId,
    bridgeLastSeen: bridge.lastSeenMs,
    bridgeFirmwareVersion: bridge.firmwareVersion,
    bridgeStatus: bridge.status,
    probeTargeting: targeting,
  };
}

// ---------------------------------------------------------------------------
// Probe targeting
// ---------------------------------------------------------------------------

/**
 * Resolve the IP a probe should target. ALWAYS names it, server-side.
 *
 * THIS RULE WAS CHANGED BY THE BENCH VERIFICATION — the earlier version is
 * recorded here because the reasoning behind it was sound and someone will
 * propose it again.
 *
 * SCHEDULING_ARCHITECTURE_V2.md §8 advised every server writer to OMIT
 * `controllerIp`, calling it "free, and strictly best": a command naming no
 * target cannot be redirected, because the bridge falls back to its own paired
 * IP (esp32-bridge/src/main.cpp:795-800). audit/COMMAND_SAFETY.md §1.3 narrowed
 * that — the bridge holds exactly ONE paired IP, so omission is only right when
 * the intended target IS that paired controller — but kept omission as correct
 * for the single-controller case. Every account in the fleet has exactly one
 * controller, so that would have made omission the universal path.
 *
 * IT DOES NOT WORK ON THE CURRENT FLEET. Bench, 2026-08-06 01:34 UTC: an
 * untargeted probe returned `ERROR: HTTP -1` — a connection failure — while 282
 * commands NAMING 192.168.1.150 completed against the same bridge and the same
 * controller, one of them 30 minutes later. The error string is diagnostic: the
 * firmware answers an EMPTY fallback with `"No controller IP specified"`
 * (main.cpp:806-811), so `pairedWledIp` was populated and simply wrong —
 * stale NVS, most plausibly from the bench controller's .250 → .150 move.
 *
 * The deeper point: NO shipping app writer omits the field. CloudRelayRepository,
 * bridge_health_service and bridge_setup_screen all set it. Only the three voice
 * integrations omit it, and they are barely exercised. **The omit path was
 * reasoned about extensively and never actually tested against a bridge.** The
 * "unredirectable" property is real, but it buys safety by making the target
 * UNVERIFIABLE — and an unverifiable target that is silently stale turns every
 * probe into a false "controller unreachable" alert. For a health monitor that
 * is the worst possible failure: it would have reported the entire fleet dark.
 *
 * SO: always name the IP, resolved SERVER-SIDE from the user's own controllers
 * subcollection, never from client input. That is precisely the provenance
 * argument audit/COMMAND_SAFETY.md §1.3 already established as what makes
 * applySyncPattern's fan-out safe (writers #6/#7) — safety from where the value
 * came from, not from its absence. It is also self-correcting: the same
 * subcollection feeds `controller_ips`, so a DHCP move updates both together.
 *
 * A controller document with no IP cannot be probed at all. Return null
 * targeting so the caller SKIPS and reports it, rather than guessing.
 */
export function resolveProbeTarget(args: {
  controllerId: string;
  controllerIp: string | null;
  totalControllersForUser: number;
}): { controllerIp: string | null; targeting: ControllerHealthRecord["probeTargeting"] } {
  const ip =
    typeof args.controllerIp === "string" && args.controllerIp.length > 0
      ? args.controllerIp
      : null;
  if (!ip) return { controllerIp: null, targeting: null };
  return { controllerIp: ip, targeting: "server_resolved_ip" };
}

/**
 * Q3 — is this controller due for a probe today?
 *
 * Healthy or recently-failing (< 3 consecutive failures) → daily.
 * Persistently dark (>= 3) → weekly, keyed off `lastProbeAt`, which
 * [foldProbeIntoHealth] only advances when a probe was actually observed.
 *
 * A success at any cadence sets consecutiveFailures to 0, so recovery returns to
 * daily on the very next run with no separate state to reconcile.
 */
export function shouldProbeToday(
  previous: Partial<ControllerHealthRecord> | null,
  nowMs: number
): { probe: boolean; reason: string } {
  if (!previous) return { probe: true, reason: "first_probe" };

  const failures =
    typeof previous.consecutiveFailures === "number" ? previous.consecutiveFailures : 0;
  if (failures < BACKOFF_AFTER_CONSECUTIVE_FAILURES) {
    return { probe: true, reason: "daily" };
  }

  const last = typeof previous.lastProbeAt === "number" ? previous.lastProbeAt : null;
  // No recorded probe despite a failure count — probe rather than stall forever.
  if (last === null) return { probe: true, reason: "weekly_no_last_probe" };

  if (nowMs - last >= BACKOFF_RETRY_INTERVAL_MS) {
    return { probe: true, reason: "weekly_retry" };
  }
  return { probe: false, reason: "backoff_weekly" };
}

/**
 * How long this controller has been dark, in ms — INDEPENDENT of probe cadence.
 *
 * Prefers `lastSuccessAt` (it once worked), falls back to `firstFailureAt` (it
 * never has). Returns null when neither is known. This is the number the digest
 * reports; `consecutiveFailures` is a probe count and would understate a 60-day
 * outage as ~11 under weekly backoff.
 */
export function darkForMs(
  record: Partial<ControllerHealthRecord>,
  nowMs: number
): number | null {
  const since =
    typeof record.lastSuccessAt === "number"
      ? record.lastSuccessAt
      : typeof record.firstFailureAt === "number"
        ? record.firstFailureAt
        : null;
  return since === null ? null : Math.max(0, nowMs - since);
}

/**
 * One-in-flight guard. True when a probe must NOT be written.
 *
 * The contract audit/COMMAND_SAFETY.md §3.4 specified but deliberately left
 * unimplemented ("an uncalled guard is untestable") — S6 is its first caller.
 *
 * DELIBERATELY CONSERVATIVE. It blocks on ANY pending/executing command that
 * could be for this controller, not just a prior probe:
 *   - same controllerId                    → obviously ours
 *   - no controllerId at all               → bridge_health_service.dart writes
 *     none, and bridge_setup_screen.dart writes ''; both target the paired
 *     controller, which on a single-controller account is this one
 *
 * Why so cautious: the measured tail under queue pressure is 30-32 s because
 * MAX_COMMANDS_PER_POLL = 5 are processed SERIALLY. A probe is worth nothing
 * and must never be the command that pushes a customer's brightness drag into
 * that tail. Skipping a probe costs one day of one controller's telemetry;
 * competing with customer traffic costs the customer.
 */
export function hasInFlightCommand(
  pending: Array<{ controllerId?: unknown; status?: unknown }>,
  controllerId: string
): boolean {
  return pending.some((c) => {
    const s = typeof c.status === "string" ? c.status : "";
    if (s !== "pending" && s !== "executing") return false;
    const cid = typeof c.controllerId === "string" ? c.controllerId : "";
    return cid === "" || cid === controllerId;
  });
}

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

const MS_PER_DAY = 86_400_000;

export interface AlertInputs {
  health: Array<{
    uid: string;
    email: string | null;
    displayName: string | null;
    record: ControllerHealthRecord;
  }>;
  registry: Array<{
    deviceId: string;
    status: string | null;
    pairedUid: string;
    pendingUid: string;
    lastSeenMs: number | null;
    /** email/displayName of pairedUid, when it resolves. */
    email: string | null;
    displayName: string | null;
  }>;
  /** Every uid that has a user document. Used for the F-5b stranded check. */
  knownUids: Set<string>;
  nowMs: number;
}

/**
 * The two alerts the brief asked for, plus one that costs nothing.
 *
 * ALERT 1 — a controller not successfully probed recently. Would have surfaced
 * Ellie Cochran as a warning on day 1 and an alert on day 2 rather than at day
 * 15, and Chris Paschall likewise rather than at day 21.
 *
 * ALERT 2 — a bridge registry row that disagrees with reality, in both
 * directions:
 *   • paired but silent          → the bucket-B shape (Ellie, Paschall)
 *   • unpaired but heartbeating  → the IRON RESERVE shape. Five days powered,
 *     online, unclaimed, 17 failed commands, and nothing anywhere said so.
 *     This is the one that would have been caught on day 1 for the price of a
 *     single comparison.
 *
 * ALERT 3 (free) — a registry row claiming a uid with no user document. That is
 * the F-5b stranded-bridge shape (audit/COMPLIANCE_AND_SECURITY.md §F-5b, P0).
 * The fleet has zero of these today; the value is in noticing the FIRST one,
 * because the remedy is a truck roll and it gets cheaper the sooner it is known.
 */
export function evaluateHealthAlerts(inputs: AlertInputs): HealthAlert[] {
  const { health, registry, knownUids, nowMs } = inputs;
  const alerts: HealthAlert[] = [];

  // ── 1. Controllers not successfully probed ──────────────────────────────
  for (const row of health) {
    const r = row.record;
    if (r.consecutiveFailures < WARN_AFTER_CONSECUTIVE_FAILURES) continue;

    // Q1 SUPPRESSION. An account with no bridge on record will fail every probe
    // forever, by construction. Alerting on it daily would put a permanent
    // standing item in front of every real outage and train the reader to skim.
    // They are still probed (so a newly installed bridge surfaces on its own)
    // and they still appear in the digest's roster — just not as an alert.
    if (r.bridgePresence === "never") continue;

    const darkMs = darkForMs(r, nowMs);
    const ageDays = darkMs === null ? null : +(darkMs / MS_PER_DAY).toFixed(1);

    const layer =
      r.lastProbeBlame === "bridge"
        ? "bridge unreachable"
        : r.lastProbeBlame === "controller"
          ? "controller unreachable behind a live bridge"
          : "unknown layer";

    // Report DURATION first and the probe count second. Under weekly backoff the
    // count understates the outage (60 days dark ≈ 11 failures), so the days —
    // computed from a timestamp, not from the sampling rate — lead.
    const durationText =
      ageDays === null
        ? "duration unknown"
        : r.lastSuccessAt !== null
          ? `dark ${ageDays}d (last success)`
          : `dark ${ageDays}d (never successfully probed)`;

    alerts.push({
      kind: "controller_unreachable",
      severity:
        r.consecutiveFailures >= ALERT_AFTER_CONSECUTIVE_FAILURES ? "alert" : "warn",
      uid: row.uid,
      email: row.email,
      displayName: row.displayName,
      controllerId: r.controllerId,
      deviceId: r.bridgeDeviceId,
      ageDays,
      detail:
        `${durationText} — ${layer}` +
        (r.lastProbeOutcome ? ` (last outcome: ${r.lastProbeOutcome})` : "") +
        `; ${r.consecutiveFailures} failed probe(s) at ${r.probeCadence} cadence`,
    });
  }

  // ── 2 & 3. Registry disagreements ───────────────────────────────────────
  for (const d of registry) {
    const ageMs = d.lastSeenMs === null ? null : nowMs - d.lastSeenMs;
    const ageDays = ageMs === null ? null : +(ageMs / MS_PER_DAY).toFixed(1);

    if (d.pairedUid && !knownUids.has(d.pairedUid)) {
      alerts.push({
        kind: "bridge_claims_unknown_uid",
        severity: "alert",
        uid: d.pairedUid,
        email: null,
        displayName: null,
        controllerId: null,
        deviceId: d.deviceId,
        ageDays,
        detail:
          `registry row claims uid ${d.pairedUid}, which has NO user document ` +
          "— F-5b stranded-bridge shape; the pairing cannot be released " +
          "server-side (firestore.rules bridge_registry delete:false, and the " +
          "device re-asserts pairedUid from NVS every heartbeat)",
      });
      continue;
    }

    if (
      d.status === "paired" &&
      ageMs !== null &&
      ageMs > REGISTRY_SILENT_HOURS * 3_600_000
    ) {
      // SUPERSEDED-ORPHAN DISCRIMINATOR. A silent paired row whose account has
      // ANOTHER paired row that is currently fresh is a replaced-in-place unit,
      // not an outage — the customer is fine and the stale row is a data
      // cleanup task.
      //
      // This exists because the 2026-08-05 triage produced exactly this
      // ambiguity: Brooke Rozenberg's superseded bridge (0070077E8F60, silent
      // 22d) sat beside her live replacement, and it was close enough to two
      // genuine outages (21.4d and 15.0d) to make "whose bridge is dark?" a
      // real question. Without this branch the digest would put a healthy
      // customer at the top of the call list — which is the specific failure a
      // triage list must never have.
      const hasLiveSibling = registry.some(
        (o) =>
          o.deviceId !== d.deviceId &&
          o.pairedUid === d.pairedUid &&
          o.lastSeenMs !== null &&
          nowMs - o.lastSeenMs <= REGISTRY_FRESH_MINUTES * 60_000
      );

      alerts.push({
        kind: hasLiveSibling ? "bridge_superseded_orphan" : "bridge_paired_but_silent",
        // An orphan is NOT urgent: nothing routes by registry row, so the
        // customer is unaffected. Its cost is that it inflates every
        // fleet-offline count until someone clears it.
        severity: hasLiveSibling ? "warn" : "alert",
        uid: d.pairedUid || null,
        email: d.email,
        displayName: d.displayName,
        controllerId: null,
        deviceId: d.deviceId,
        ageDays,
        detail: hasLiveSibling
          ? `superseded registry row, silent ${ageDays}d, while this account's ` +
            "replacement bridge is live — NOT a customer outage; clear the stale " +
            "row so it stops inflating the offline count"
          : `paired bridge has not reported in ${ageDays}d`,
      });
      continue;
    }

    if (
      d.status === "unpaired" &&
      ageMs !== null &&
      ageMs <= REGISTRY_FRESH_MINUTES * 60_000
    ) {
      alerts.push({
        kind: "bridge_unpaired_but_heartbeating",
        severity: "alert",
        uid: null,
        email: null,
        displayName: null,
        controllerId: null,
        deviceId: d.deviceId,
        ageDays: 0,
        detail:
          "bridge is ONLINE and heartbeating but UNPAIRED — installed and " +
          "powered, pairing never completed (the 2026-08-05 Iron Reserve shape: " +
          "5 days, 17 failed commands, invisible to everyone)",
      });
    }
  }

  // Most severe first, then oldest first — the call list order.
  const rank = (a: HealthAlert) => (a.severity === "alert" ? 0 : 1);
  return alerts.sort(
    (a, b) => rank(a) - rank(b) || (b.ageDays ?? 0) - (a.ageDays ?? 0)
  );
}

export interface RosterEntry {
  uid: string;
  who: string;
  controllerId: string;
  presence: BridgePresence;
  deviceId: string | null;
  /** Days since the bridge last reported. Null for `never`. */
  silentDays: number | null;
}

/**
 * Q1 — the roster. Every controller whose bridge is NOT currently live, split by
 * whether a bridge was ever there at all.
 *
 * The split is the point: **"never had a bridge" and "had one, now silent" are
 * different conversations.** The first is a sales/records question — was one
 * ever sold? The second is a support call. Collapsing them into one "offline"
 * count is what made the 2026-08-05 fleet look uniformly broken when in fact 7
 * accounts had simply never been fitted.
 *
 * Accounts in `never` have their alerts suppressed, so this roster is the ONLY
 * place they appear — which is precisely why it has to be in the digest rather
 * than only in the snapshot document.
 */
export function buildRoster(
  health: AlertInputs["health"],
  nowMs: number
): { never: RosterEntry[]; silent: RosterEntry[] } {
  const never: RosterEntry[] = [];
  const silent: RosterEntry[] = [];

  // `??` is not enough here: `staff_installer_5502` carries display_name: ""
  // (an empty string, not null), which `??` passes through and renders as a
  // BLANK roster line — a row you cannot act on because it names nobody.
  const nonEmpty = (...vals: Array<string | null | undefined>): string => {
    for (const v of vals) if (typeof v === "string" && v.trim().length > 0) return v;
    return "(unnamed account)";
  };

  for (const row of health) {
    const r = row.record;
    if (r.bridgePresence === "live") continue;

    const entry: RosterEntry = {
      uid: row.uid,
      who: nonEmpty(row.email, row.displayName, row.uid),
      controllerId: r.controllerId,
      presence: r.bridgePresence,
      deviceId: r.bridgeDeviceId,
      silentDays:
        r.bridgeLastSeen === null
          ? null
          : +((nowMs - r.bridgeLastSeen) / MS_PER_DAY).toFixed(1),
    };
    if (r.bridgePresence === "never") never.push(entry);
    else silent.push(entry);
  }

  never.sort((a, b) => a.who.localeCompare(b.who));
  silent.sort((a, b) => (b.silentDays ?? 0) - (a.silentDays ?? 0));
  return { never, silent };
}

/**
 * True when a digest should be sent at all.
 *
 * "A signal nobody reads is not a signal" cuts both ways: a digest that arrives
 * every day saying nothing is one the reader stops opening, and by the time it
 * says something real it is invisible. So the rule is:
 *
 *   - any alert or warning       → send
 *   - nothing to report, Monday  → send an ALL-CLEAR anyway
 *   - nothing to report, else    → send nothing
 *
 * The Monday all-clear is NOT decoration. Without it, a silent inbox is
 * ambiguous between "the fleet is healthy" and "the function has been throwing
 * for three weeks" — and this repo has already shipped one scheduled routine
 * that never ran and was not noticed for months (scheduledDataCleanup, D2). A
 * heartbeat that must arrive weekly makes the failure of the monitor itself
 * detectable.
 */
export function shouldSendDigest(alertCount: number, utcDayOfWeek: number): boolean {
  if (alertCount > 0) return true;
  return utcDayOfWeek === 1; // Monday
}
