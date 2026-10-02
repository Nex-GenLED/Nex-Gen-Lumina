/**
 * commandSafety — shared contract for /users/{uid}/commands documents.
 *
 * WHY THIS EXISTS
 * ---------------
 * The command collection is the only path by which anything outside the home
 * network can drive a customer's controller. Three defects were live in
 * production when this module was written (audit/COMMAND_SAFETY.md):
 *
 *   1. The ESP32 bridge has NO command-age check of any kind. executeCommand()
 *      (esp32-bridge/src/main.cpp:763-845) reads `type` and `controllerIp` and
 *      fires. It never reads createdAt or expiresAt.
 *
 *   2. The Cloud Function's 5-minute age check (functions/index.js:348-360)
 *      sits AFTER the bridge-mode early return (:338-343). Every production
 *      account is bridge-mode, so that check is dead code fleet-wide.
 *
 *   3. `expiresAt` is already written by three server-side writers with a 60 s
 *      TTL (functions/index.js:1423, google-home/functions/index.js:362,
 *      alexa-skill/lambda/utils/firebase.js:129) and is READ BY NOBODY. The
 *      TTL convention was designed and the enforcement half was never built.
 *
 * Net effect: a bridge offline for hours reconnects, polls, and fires the whole
 * accumulated backlog — in unspecified order, because the bridge's query has no
 * orderBy (main.cpp:692-698) and command ids are non-sortable Firestore auto-ids.
 * An ON and an OFF can invert.
 *
 * This module is the enforcement half. It is deliberately PURE (no firebase-admin
 * import at module scope for the predicate helpers) so functions/test/unit can
 * exercise the expiry logic against compiled lib/ with no emulator.
 *
 * WHAT THIS DOES NOT CLOSE — see audit/COMMAND_SAFETY.md §6. Anything needing a
 * firmware change is out of reach until an OTA mechanism exists (there is none:
 * esp32-bridge/src/main.cpp registers six routes and none is an update path):
 *   - bridge-side expiry check
 *   - ordered draining (orderBy on the poll)
 *   - drain-and-discard on reconnect
 * Residual exposure is one sweeper tick (~60 s). Stated plainly, not hidden.
 */

/**
 * Terminal status for a command that was never picked up in time.
 *
 * MUST stay distinct from "failed". The distinction carries real diagnostic
 * signal and SCHEDULING_ARCHITECTURE_V2.md §6 telemetry depends on it:
 *
 *   expired → the BRIDGE was unreachable (nobody picked the command up)
 *   failed  → the CONTROLLER was unreachable (bridge picked it up, WLED refused
 *             or timed out; the bridge writes the HTTP code into `error`)
 *
 * Collapsing them would destroy the only fleet-visible way to tell "customer's
 * bridge is down" from "customer's controller is down".
 */
export const STATUS_EXPIRED = "expired";

/** Statuses the bridge will act on. Its poll filters `status == "pending"`. */
export const STATUS_PENDING = "pending";

/** Set once the bridge has claimed a command; it is no longer sweepable. */
export const STATUS_EXECUTING = "executing";

/**
 * Default TTL for a command whose writer did not set `expiresAt`.
 *
 * WHY 120 s — this number is chosen against three measured constraints, not
 * picked for roundness:
 *
 *   - The app's own command watchdog is 45 s, sized from a MEASURED worst case
 *     of 30-32 s under queue pressure
 *     (lib/features/wled/cloud_relay_repository.dart:44-52). A TTL below that
 *     would expire commands the app is still legitimately waiting on, turning a
 *     slow-but-successful command into a spurious failure.
 *
 *   - 120 s is ~2.7x that watchdog and ~4x the measured worst case, so the
 *     sweeper only ever acts on commands the app has ALREADY given up on. That
 *     is the key property: expiring an app-written command is invisible to the
 *     user, because the app stopped waiting 75 s earlier and has already run its
 *     own reconcile-and-report path (the #52 late-result-wins logic at
 *     cloud_relay_repository.dart `_reconcileAfterWatchdog`).
 *
 *   - It is still far below any plausible bridge outage, so a bridge that
 *     reconnects after a real outage finds nothing pending.
 *
 * A NOTE ON THE "BAD LTE" CONCERN: a user on poor mobile data does not eat into
 * this budget. `createdAt` is a serverTimestamp — it is stamped by Firestore
 * when the write COMMITS, not when the phone starts the request. Slow uplink
 * delays the write itself; the TTL clock starts after. The only actor whose
 * slowness this TTL measures is the bridge.
 *
 * Voice-integration writers keep their explicit 60 s and are unaffected by this
 * default — a voice command executing a minute late is unwanted, and their
 * shorter window is correct for that surface.
 */
export const DEFAULT_COMMAND_TTL_MS = 120_000;

/**
 * Age below which the sweeper will not even query. Must be <= the smallest TTL
 * in use anywhere (the voice writers' 60 s), so the query never has to consider
 * a command that could not possibly be expired yet.
 */
export const MIN_SWEEPABLE_AGE_MS = 60_000;

/**
 * A1 (2026-10-02) — how long a command may sit in `executing` before the
 * server treats it as abandoned.
 *
 * THE DEFECT. The bridge flips a command to `executing` immediately before its
 * own WLED request and PATCHes `completed`/`failed` straight after
 * (esp32-bridge/src/main.cpp executeCommand). If the bridge reboots, loses
 * Wi-Fi, or its PATCH fails in that window, the doc stays `executing` FOREVER:
 * the bridge's poll only reads `pending`, the sweeper only touched `pending`,
 * and the one-in-flight guard counted `executing` with no age limit. One
 * customer bridge carried eleven such docs, and every one of them blocked that
 * controller's scheduled fires until the 7-day retention sweep.
 *
 * WHY 180 s. A healthy bridge spends one WLED request (WLED_HTTP_TIMEOUT_MS,
 * 10 s) plus one Firestore PATCH (TLS client timeout 15 s; the worst completion
 * measured under load is ~45 s) on a claimed command — the claim is per
 * command, not per poll batch, so queue depth does not stretch it. 180 s is
 * ~4x that worst case, so a slow-but-alive bridge is never declared stuck, and
 * it is 4x the app's own 45 s watchdog, so an app-written command was given up
 * by the app long before the server touches it.
 *
 * Measured from `createdAt`: the fielded bridge writes no claim timestamp.
 */
export const STUCK_EXECUTING_AFTER_MS = 180_000;

/**
 * The `error` a stuck command is terminated with. Matched by PREFIX
 * ([isStuckExecutingError]) so a longer explanatory text written by another
 * sweeper of the same condition classifies identically.
 */
export const STUCK_EXECUTING_ERROR = "stuck_executing";

/** Age of a command at [nowMs], from `createdAt`. Null when unreadable. */
export function commandAgeMs(
  doc: { createdAt?: { toMillis(): number } | null },
  nowMs: number
): number | null {
  const c = doc.createdAt;
  if (!c || typeof c.toMillis !== "function") return null;
  return nowMs - c.toMillis();
}

/**
 * True when [doc] is `executing` and older than the stuck threshold.
 *
 * An unreadable age returns false — never terminate on a guess (the same rule
 * [effectiveExpiryMs] follows for `pending`).
 */
export function isStuckExecuting(
  doc: { status?: unknown; createdAt?: { toMillis(): number } | null },
  nowMs: number,
  thresholdMs: number = STUCK_EXECUTING_AFTER_MS
): boolean {
  if (doc.status !== STATUS_EXECUTING) return false;
  const age = commandAgeMs(doc, nowMs);
  return age !== null && age > thresholdMs;
}

/** True when a command's `error` records a stuck-executing termination. */
export function isStuckExecutingError(error: unknown): boolean {
  return typeof error === "string" && error.startsWith(STUCK_EXECUTING_ERROR);
}

/** Minimal shape the expiry predicates need. Both fields may be absent. */
export interface CommandTimestamps {
  createdAt?: { toMillis(): number } | null;
  expiresAt?: { toMillis(): number } | null;
}

/**
 * Resolve the instant a command stops being safe to execute.
 *
 * Precedence: an explicit `expiresAt` always wins (the voice writers' 60 s is
 * intentional and must not be widened to 120 s by this default). Otherwise
 * `createdAt + defaultTtlMs`.
 *
 * Returns null when neither field is readable — the caller MUST treat null as
 * "cannot determine, do not expire". A command with no createdAt is anomalous
 * and is left to the 7-day retention sweep (functions/index.js:1000) rather
 * than being expired on a guess. It also never matches the sweeper's query,
 * which filters on createdAt, so this branch is defensive rather than load-bearing.
 */
export function effectiveExpiryMs(
  doc: CommandTimestamps,
  defaultTtlMs: number = DEFAULT_COMMAND_TTL_MS
): number | null {
  const explicit = doc.expiresAt;
  if (explicit && typeof explicit.toMillis === "function") {
    return explicit.toMillis();
  }
  const created = doc.createdAt;
  if (created && typeof created.toMillis === "function") {
    return created.toMillis() + defaultTtlMs;
  }
  return null;
}

/**
 * True when [doc] is past its effective expiry at [nowMs].
 *
 * Undeterminable age (see [effectiveExpiryMs]) returns false — never expire on
 * a guess.
 */
export function isExpiredCommand(
  doc: CommandTimestamps,
  nowMs: number,
  defaultTtlMs: number = DEFAULT_COMMAND_TTL_MS
): boolean {
  const expiry = effectiveExpiryMs(doc, defaultTtlMs);
  if (expiry === null) return false;
  return expiry < nowMs;
}

/**
 * Deterministic document id for a scheduled fire job (S3's dispatcher).
 *
 * THE DEFECT THIS CLOSES: every existing writer uses `.add()`, which mints a
 * random id. A retried Cloud Function invocation therefore writes a SECOND
 * document and the bridge fires TWICE. For a single absolute-state load a
 * double fire is harmless, but for a SEQUENCE (fire Game Day, then fire Warm
 * White) an out-of-order duplicate is not — and the bridge's poll has no
 * orderBy, so ordering of a two-document backlog is unspecified.
 *
 * Paired with `.doc(id).create()` (see [buildFireJobDoc]'s contract), which
 * FAILS with already-exists rather than overwriting, this makes a duplicate
 * fire structurally impossible: the write itself becomes the idempotency
 * barrier, and a retry is unambiguously distinguishable from a genuine second
 * fire.
 *
 * Second-granularity is deliberate — fire jobs are scheduled to the minute, so
 * seconds are ample and the id stays human-readable in the console.
 */
export function fireJobDocId(eventId: string, fireAtEpochSeconds: number): string {
  const safeEvent = eventId.replace(/[^A-Za-z0-9_-]/g, "_");
  return `fire_${safeEvent}_${Math.floor(fireAtEpochSeconds)}`;
}

/**
 * Extract the registered-controller IP allowlist from a user's `controllers`
 * subcollection docs. This is the value denormalized onto `users/{uid}.controller_ips`
 * and consulted by the firestore.rules `commands` create/update guard.
 *
 * Deduped and sorted so the trigger's write is stable — an unstable ordering
 * would rewrite the user doc on every controller touch and burn writes for
 * nothing.
 */
export function controllerIpsFrom(
  docs: Array<{ ip?: unknown }>
): string[] {
  const out = new Set<string>();
  for (const d of docs) {
    const ip = d?.ip;
    if (typeof ip === "string" && ip.length > 0) out.add(ip);
  }
  return Array.from(out).sort();
}
