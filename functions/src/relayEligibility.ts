/**
 * relayEligibility — does this account have a Lumina Bridge at all?
 *
 * THE DEFECT (read-only analysis, 2026-09-30). A relay command in bridge mode
 * is only ever picked up by an ESP32 bridge paired to the account. Nothing on
 * the client, in the rules, or in Cloud Functions asked whether such a bridge
 * existed before a command was queued, so five live accounts with no bridge
 * wrote 124 commands in a week that sat `pending` until the sweeper expired
 * them, and the server's own daily health probe queued a doomed `getInfo` for
 * every one of those controllers every day.
 *
 * ONE PREDICATE, THREE CALLERS:
 *   - executeWledCommand (index.js) — fail a bridge-mode command FAST when no
 *     bridge is paired, instead of letting it sit 120 s until expiry.
 *   - sweepExpiredCommands — say "no bridge on record" rather than "bridge
 *     offline" when that is the truth.
 *   - probeControllerHealth — do not queue a probe nothing can answer.
 *
 * EXISTENCE, NOT FRESHNESS (owner decision). `hasPairedBridge` is "a
 * bridge_registry row exists with pairedUid == uid". It deliberately ignores
 * lastSeen: a paired customer whose bridge is briefly offline must keep the
 * ordinary "unreachable" path and recover when the bridge returns. Never read
 * users/{uid}.bridge_paired or bridge_ip for this — one live account carries
 * bridge_paired: true for a registry row deleted on 2026-09-18.
 *
 * FAIL OPEN. Every caller treats a lookup ERROR as "paired". A transient
 * Firestore error must never fail a paired customer's command.
 */

import * as admin from "firebase-admin";

/** The `error` value a fail-fast command carries. Stable: the app matches on it. */
export const NO_BRIDGE_PAIRED_ERROR = "no_bridge_paired";

/** Sweeper wording for a command nothing could ever have picked up. */
export const EXPIRED_NO_BRIDGE_TEXT =
  "Command expired: no bridge is paired to this account, so nothing could " +
  "pick it up.";

/** Sweeper wording for a paired bridge that did not poll in time. */
export const EXPIRED_BRIDGE_OFFLINE_TEXT =
  "Command expired before the bridge picked it up (bridge offline or " +
  "unreachable at fire time).";

/** A skip reason, or null to proceed. Pure. */
export function probeSkipReason(args: {
  bridgePaired: boolean;
  monitoringExcluded: boolean;
}): string | null {
  if (args.monitoringExcluded) return "monitoring_excluded";
  if (!args.bridgePaired) return "no_paired_bridge";
  return null;
}

/**
 * The pairing wizard's verification ping: `type: "ping"` with an empty
 * `controllerIp`. It is written the instant the bridge flips the registry row
 * to `paired` and exists to prove that round trip, so it is never failed fast
 * (a registry read racing that flip would call a successful pairing a
 * failure). The app-side twin is `lib/services/pairing_ping.dart`.
 */
export function isPairingPing(doc: Record<string, unknown>): boolean {
  const ip = doc.controllerIp;
  return doc.type === "ping" && (ip === undefined || ip === null || ip === "");
}

/**
 * True when `users/{uid}.monitoring_exclude === true`. Read-only: nothing in
 * this codebase sets the flag; it is for the reviewer/demo and bench accounts,
 * set by hand.
 */
export function isMonitoringExcluded(
  userDoc: { get: (field: string) => unknown } | null | undefined
): boolean {
  return userDoc?.get("monitoring_exclude") === true;
}

/**
 * Does a `bridge_registry` row with `pairedUid == uid` exist?
 *
 * One `limit(1)` query on the single-field auto-index. Throws on a Firestore
 * error — callers decide what "unknown" means for them (all three fail open).
 */
export async function hasPairedBridge(
  db: admin.firestore.Firestore,
  uid: string
): Promise<boolean> {
  if (!uid) return false;
  const snap = await db
    .collection("bridge_registry")
    .where("pairedUid", "==", uid)
    .limit(1)
    .get();
  return !snap.empty;
}

/** Memoised [hasPairedBridge] for a pass that touches many users. */
export class PairedBridgeCache {
  private readonly cache = new Map<string, Promise<boolean>>();

  constructor(private readonly db: admin.firestore.Firestore) {}

  lookup(uid: string): Promise<boolean> {
    let p = this.cache.get(uid);
    if (!p) {
      p = hasPairedBridge(this.db, uid);
      this.cache.set(uid, p);
    }
    return p;
  }
}

export type FailFastOutcome =
  | "failed_no_bridge"
  | "passthrough_paired"
  | "passthrough_pairing_ping"
  | "passthrough_not_pending"
  | "passthrough_lookup_error";

/**
 * executeWledCommand's bridge-mode branch.
 *
 * When no bridge is paired to `uid`, the command is marked terminal NOW:
 *   status: "failed", error: "no_bridge_paired", completedAt.
 * The app's relay listener resolves on `failed` at once (no 45 s watchdog),
 * and the reconcile transaction honours the terminal status rather than
 * relabelling it `timeout`.
 *
 * The write is transactional and re-checks `status == "pending"`, so a bridge
 * that claimed the doc between the trigger firing and this read keeps its
 * claim. Every error path returns a passthrough: the legacy behaviour (leave
 * the doc for the bridge) is always the fallback.
 */
export async function failFastIfNoPairedBridge(
  db: admin.firestore.Firestore,
  uid: string,
  commandRef: admin.firestore.DocumentReference,
  commandData: Record<string, unknown>
): Promise<FailFastOutcome> {
  if (isPairingPing(commandData)) return "passthrough_pairing_ping";

  let paired: boolean;
  try {
    paired = await hasPairedBridge(db, uid);
  } catch (err) {
    console.warn(
      `relayEligibility: registry lookup failed for ${uid}; leaving the ` +
        "command for the bridge",
      err
    );
    return "passthrough_lookup_error";
  }
  if (paired) return "passthrough_paired";

  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(commandRef);
      if (!snap.exists) return "passthrough_not_pending" as FailFastOutcome;
      const status = snap.get("status");
      if (status !== "pending") return "passthrough_not_pending" as FailFastOutcome;
      tx.update(commandRef, {
        status: "failed",
        error: NO_BRIDGE_PAIRED_ERROR,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return "failed_no_bridge" as FailFastOutcome;
    });
  } catch (err) {
    console.warn(
      `relayEligibility: fail-fast transaction failed for ${commandRef.path}; ` +
        "leaving the command for the sweeper",
      err
    );
    return "passthrough_lookup_error";
  }
}
