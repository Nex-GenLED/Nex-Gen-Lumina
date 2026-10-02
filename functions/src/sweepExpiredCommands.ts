/**
 * sweepExpiredCommands — Scheduled Firebase Cloud Function (every 1 minute)
 *
 * Transitions stale `pending` commands to `expired` so the ESP32 bridge never
 * sees them. The bridge's poll filters `status == "pending"`
 * (esp32-bridge/src/main.cpp:692-698), so flipping the status is a complete
 * remedy that requires NO firmware change — which matters, because there is no
 * OTA mechanism in the bridge firmware and "deploy firmware" currently means
 * visiting each unit with a USB cable.
 *
 * THE FAILURE THIS PREVENTS
 * -------------------------
 * A bridge offline for hours reconnects, polls, and fires every accumulated
 * pending command. There is no age check anywhere in the current path:
 *   - bridge:   none at all (main.cpp:763-845)
 *   - function: 5-minute check sits after the bridge-mode early return
 *               (functions/index.js:338-360), so it is dead code fleet-wide
 *   - retention: 7 days (functions/index.js:1000) — a pending command stays
 *               eligible for pickup that entire time
 * Combined with an unordered poll, an ON and an OFF can fire inverted.
 *
 * A1 (2026-10-02) — STUCK `executing`. The bridge claims a command
 * (`executing`) just before its WLED request and reports straight after. A
 * reboot or a failed PATCH in that window left the doc `executing` forever, and
 * the one-in-flight guard counted it with no age limit, so a single bridge
 * hiccup blocked that controller's scheduled fires until 7-day retention. The
 * second pass terminates those as `failed` / `stuck_executing` once they are
 * older than STUCK_EXECUTING_AFTER_MS (180 s — rationale in commandSafety.ts).
 *
 * IDEMPOTENT. A second run finds nothing pending past its expiry and nothing
 * executing past the threshold. Safe to re-run, safe to overlap (a doc already
 * flipped no longer matches either query).
 *
 * SCOPE DISCIPLINE. Two passes, each writing only `status`, `error` and one
 * timestamp, and each only on a document still in the state it was read in:
 *   1. pending   → expired                (past its effective expiry)
 *   2. executing → failed/stuck_executing (older than the stuck threshold)
 * It never deletes and never touches a terminal command.
 *
 * THE GUARD (corrected 2026-10-02). The first version "re-checked the status
 * read in the query" before a batched update. That re-check read the same
 * snapshot the query had just filtered on, so it could never fail: a bridge
 * claim landing between the read and the commit WAS overwritten. Every write is
 * now an update with a `lastUpdateTime` precondition (commandHygiene.ts), so a
 * doc the bridge touched after our read is left exactly as the bridge left it —
 * "completed wins". That matters more now that the fire dispatcher retries on
 * `expired` and `stuck_executing` (A2): a wrong intermediate state would mint a
 * duplicate fire.
 *
 * ERROR TEXT (2026-09-30). The text now says which of two different things
 * happened: a paired bridge that did not poll in time ("bridge offline or
 * unreachable"), or an account with no bridge paired at all ("no bridge is
 * paired to this account"). Before, every expiry read as a bridge outage,
 * which put five bridge-less accounts on the fleet-health call list as if a
 * bridge had failed. One registry read per user per run, memoised; a lookup
 * error keeps the bridge-offline wording (fail open).
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:sweepExpiredCommands
 *
 * REQUIRES the COLLECTION_GROUP composite index on `commands` (status, createdAt)
 * declared in firestore.indexes.json. Deploy indexes BEFORE this function or
 * every invocation fails with FAILED_PRECONDITION. Both passes use that SAME
 * index: an equality on `status` (any value) plus a range on `createdAt`.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {
  DEFAULT_COMMAND_TTL_MS,
  MIN_SWEEPABLE_AGE_MS,
  STATUS_EXECUTING,
  STATUS_PENDING,
  STUCK_EXECUTING_AFTER_MS,
  isExpiredCommand,
  isStuckExecuting,
} from "./commandSafety";
import { mapLimit, markExpired, markStuckExecuting } from "./commandHygiene";
import {
  EXPIRED_BRIDGE_OFFLINE_TEXT,
  EXPIRED_NO_BRIDGE_TEXT,
  PairedBridgeCache,
} from "./relayEligibility";

// admin.initializeApp() is called in index.js — do not call again here.

/**
 * Concurrent guarded writes per pass. Per-doc, not batched: one failed
 * precondition in a batch would abort every other write in it.
 */
const WRITE_CONCURRENCY = 25;

/**
 * Cap per invocation, per pass. At a 1-minute cadence this is far above any
 * plausible steady-state backlog (commands normally complete in ~2 s). A run
 * that hits the cap logs loudly and the next tick continues — we never
 * silently truncate.
 */
const MAX_DOCS_PER_RUN = 2000;

/** The `error` text for one expired command. Pure. */
export function expiryErrorText(bridgePaired: boolean): string {
  return bridgePaired ? EXPIRED_BRIDGE_OFFLINE_TEXT : EXPIRED_NO_BRIDGE_TEXT;
}

export interface SweepStats {
  pendingExamined: number;
  expired: number;
  noBridge: number;
  stuckExamined: number;
  stuck: number;
  /** Writes refused because the doc changed after our read — the bridge won. */
  raced: number;
  pendingQueryFailed: boolean;
  stuckQueryFailed: boolean;
  expiredPerUser: Record<string, number>;
  stuckPerUser: Record<string, number>;
}

/**
 * One sweeper tick. Exported so tests (and the bench harness) drive the REAL
 * code path. A query failure in one pass does not stop the other; the tick
 * reports it and the scheduled wrapper rethrows so it is loud in Cloud Logging.
 */
export async function runSweepTick(
  db: admin.firestore.Firestore,
  nowMs: number
): Promise<SweepStats> {
  const stats: SweepStats = {
    pendingExamined: 0,
    expired: 0,
    noBridge: 0,
    stuckExamined: 0,
    stuck: 0,
    raced: 0,
    pendingQueryFailed: false,
    stuckQueryFailed: false,
    expiredPerUser: {},
    stuckPerUser: {},
  };
  // users/{uid}/commands/{id} → parent.parent is the user doc.
  const uidOf = (d: admin.firestore.QueryDocumentSnapshot) =>
    d.ref.parent.parent?.id ?? "unknown";

  // ── Pass 1: pending past expiry → expired ──────────────────────────────
  // Only consider commands old enough that SOME TTL could have elapsed. The
  // smallest TTL in use is the voice writers' 60 s, so nothing younger can be
  // expired and the query stays selective.
  let pendingSnap: admin.firestore.QuerySnapshot | null = null;
  try {
    pendingSnap = await db
      .collectionGroup("commands")
      .where("status", "==", STATUS_PENDING)
      .where("createdAt", "<", admin.firestore.Timestamp.fromMillis(nowMs - MIN_SWEEPABLE_AGE_MS))
      .limit(MAX_DOCS_PER_RUN)
      .get();
  } catch (err) {
    // A missing index surfaces here as FAILED_PRECONDITION. Fail loudly — a
    // silently-not-running sweeper is exactly the class of defect this whole
    // function exists to eliminate.
    stats.pendingQueryFailed = true;
    console.error(
      "sweepExpiredCommands: PENDING QUERY FAILED — stale commands are NOT being " +
        "expired. Check the COLLECTION_GROUP index on commands(status, createdAt).",
      err
    );
  }

  if (pendingSnap && !pendingSnap.empty) {
    stats.pendingExamined = pendingSnap.size;
    // Second-stage filter: the query bounds AGE, this bounds EXPIRY. A command
    // carrying an explicit expiresAt longer than the default keeps it, and one
    // with the 60 s voice TTL is caught earlier than the 120 s default would.
    const doomed = pendingSnap.docs.filter((d) =>
      isExpiredCommand(
        d.data() as { createdAt?: admin.firestore.Timestamp },
        nowMs,
        DEFAULT_COMMAND_TTL_MS
      )
    );
    const pairing = new PairedBridgeCache(db);
    await mapLimit(doomed, WRITE_CONCURRENCY, async (d) => {
      const uid = uidOf(d);
      // Which of the two truths applies. A lookup error reads as "paired": the
      // legacy wording is the safe default.
      let bridgePaired = true;
      try {
        bridgePaired = await pairing.lookup(uid);
      } catch (err) {
        console.warn(
          `sweepExpiredCommands: registry lookup failed for ${uid}; ` +
            "using bridge-offline wording",
          err
        );
      }
      const res = await markExpired(d.ref, d.updateTime, expiryErrorText(bridgePaired));
      if (res === "raced") {
        stats.raced++;
        return;
      }
      if (!bridgePaired) stats.noBridge++;
      stats.expired++;
      stats.expiredPerUser[uid] = (stats.expiredPerUser[uid] ?? 0) + 1;
    });
    if (pendingSnap.size >= MAX_DOCS_PER_RUN) {
      console.warn(
        `sweepExpiredCommands: hit the ${MAX_DOCS_PER_RUN}-doc cap on pending; a ` +
          "backlog remains and will be swept on the next tick. This is not normal — " +
          "investigate why so many commands are pending."
      );
    }
  }

  // ── Pass 2 (A1): executing past STUCK_EXECUTING_AFTER_MS → stuck ────────
  let stuckSnap: admin.firestore.QuerySnapshot | null = null;
  try {
    stuckSnap = await db
      .collectionGroup("commands")
      .where("status", "==", STATUS_EXECUTING)
      .where(
        "createdAt",
        "<",
        admin.firestore.Timestamp.fromMillis(nowMs - STUCK_EXECUTING_AFTER_MS)
      )
      .limit(MAX_DOCS_PER_RUN)
      .get();
  } catch (err) {
    stats.stuckQueryFailed = true;
    console.error(
      "sweepExpiredCommands: EXECUTING QUERY FAILED — stuck commands are NOT being " +
        "cleared, and each one keeps its controller's fires blocked until the " +
        "in-flight guard's age cap. Check the COLLECTION_GROUP index on " +
        "commands(status, createdAt).",
      err
    );
  }

  if (stuckSnap && !stuckSnap.empty) {
    stats.stuckExamined = stuckSnap.size;
    // Defensive re-filter on the same predicate the in-flight guard uses, so
    // the sweeper and the guard can never disagree about what "stuck" means.
    const stuck = stuckSnap.docs.filter((d) =>
      isStuckExecuting(
        d.data() as { status?: unknown; createdAt?: admin.firestore.Timestamp },
        nowMs
      )
    );
    await mapLimit(stuck, WRITE_CONCURRENCY, async (d) => {
      const res = await markStuckExecuting(d.ref, d.updateTime);
      if (res === "raced") {
        stats.raced++;
        return;
      }
      const uid = uidOf(d);
      stats.stuck++;
      stats.stuckPerUser[uid] = (stats.stuckPerUser[uid] ?? 0) + 1;
    });
    if (stuckSnap.size >= MAX_DOCS_PER_RUN) {
      console.warn(
        `sweepExpiredCommands: hit the ${MAX_DOCS_PER_RUN}-doc cap on executing; ` +
          "the rest will be cleared on the next tick."
      );
    }
  }

  // Per-user counts are the signal worth having: a user whose commands expire
  // or stick repeatedly has a bridge problem, and that is the fleet-health
  // input described in SCHEDULING_ARCHITECTURE_V2.md §6.
  const fmt = (m: Record<string, number>) =>
    Object.entries(m)
      .map(([uid, n]) => `${uid}:${n}`)
      .join(" ");
  if (stats.expired + stats.stuck + stats.raced > 0) {
    console.log(
      `sweepExpiredCommands: expired ${stats.expired} (${stats.noBridge} with no ` +
        `bridge paired) [${fmt(stats.expiredPerUser)}]; stuck_executing ` +
        `${stats.stuck} [${fmt(stats.stuckPerUser)}]; raced ${stats.raced} ` +
        "(the bridge wrote first)"
    );
  } else {
    console.log("sweepExpiredCommands: nothing to sweep");
  }
  return stats;
}

export const sweepExpiredCommands = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "UTC",
    region: "us-central1",
    // Generous but bounded: the queries are selective and the writes are few.
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const stats = await runSweepTick(admin.firestore(), Date.now());
    if (stats.pendingQueryFailed || stats.stuckQueryFailed) {
      throw new Error(
        "sweepExpiredCommands: a sweep query failed (logged above); the other " +
          "pass still ran"
      );
    }
  }
);
