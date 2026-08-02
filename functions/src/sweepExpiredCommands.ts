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
 * IDEMPOTENT. A second run finds nothing pending past its expiry. Safe to
 * re-run, safe to overlap (a doc already flipped no longer matches the query).
 *
 * SCOPE DISCIPLINE. This function only ever writes `status`, `error` and
 * `expiredAt`, and only on documents that are still `pending`. It never
 * deletes, never touches a command the bridge has claimed (`executing`), and
 * never touches a terminal command. The status transition is guarded inside the
 * batch by re-checking the value read in the query — a command the bridge
 * claimed between our read and our write keeps its claim (last-writer-wins on a
 * 1-minute cadence against a 1-second poll is overwhelmingly in the bridge's
 * favour, and the guard makes the rare loss harmless rather than wrong).
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:sweepExpiredCommands
 *
 * REQUIRES the COLLECTION_GROUP composite index on `commands` (status, createdAt)
 * declared in firestore.indexes.json. Deploy indexes BEFORE this function or
 * every invocation fails with FAILED_PRECONDITION.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {
  DEFAULT_COMMAND_TTL_MS,
  MIN_SWEEPABLE_AGE_MS,
  STATUS_EXPIRED,
  STATUS_PENDING,
  isExpiredCommand,
} from "./commandSafety";

// admin.initializeApp() is called in index.js — do not call again here.

/** Firestore batch limit is 500; keep headroom. */
const WRITE_BATCH_SIZE = 450;

/**
 * Cap per invocation. At a 1-minute cadence this is far above any plausible
 * steady-state backlog (commands normally complete in ~2 s). A run that hits
 * the cap logs loudly and the next tick continues — we never silently truncate.
 */
const MAX_DOCS_PER_RUN = 2000;

export const sweepExpiredCommands = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "UTC",
    region: "us-central1",
    // Generous but bounded: the query is selective and the writes are batched.
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const nowMs = Date.now();

    // Only consider commands old enough that SOME TTL could have elapsed. The
    // smallest TTL in use is the voice writers' 60 s, so nothing younger can be
    // expired and the query stays selective.
    const cutoff = admin.firestore.Timestamp.fromMillis(
      nowMs - MIN_SWEEPABLE_AGE_MS
    );

    let snap;
    try {
      snap = await db
        .collectionGroup("commands")
        .where("status", "==", STATUS_PENDING)
        .where("createdAt", "<", cutoff)
        .limit(MAX_DOCS_PER_RUN)
        .get();
    } catch (err) {
      // A missing index surfaces here as FAILED_PRECONDITION. Fail loudly —
      // a silently-not-running sweeper is exactly the class of defect this
      // whole change exists to eliminate.
      console.error(
        "sweepExpiredCommands: QUERY FAILED — stale commands are NOT being " +
          "expired. Check the COLLECTION_GROUP index on commands(status, createdAt).",
        err
      );
      throw err;
    }

    if (snap.empty) {
      console.log("sweepExpiredCommands: nothing pending past the age floor");
      return;
    }

    // Second-stage filter: the query bounds AGE, this bounds EXPIRY. A command
    // carrying an explicit expiresAt longer than the default keeps it, and one
    // with the 60 s voice TTL is caught earlier than the 120 s default would.
    const doomed = snap.docs.filter((d) =>
      isExpiredCommand(
        d.data() as { createdAt?: admin.firestore.Timestamp },
        nowMs,
        DEFAULT_COMMAND_TTL_MS
      )
    );

    if (doomed.length === 0) {
      console.log(
        `sweepExpiredCommands: ${snap.size} aged doc(s) examined, none past ` +
          "their effective expiry"
      );
      return;
    }

    let written = 0;
    const perUser = new Map<string, number>();

    for (let i = 0; i < doomed.length; i += WRITE_BATCH_SIZE) {
      const chunk = doomed.slice(i, i + WRITE_BATCH_SIZE);
      const batch = db.batch();
      for (const d of chunk) {
        // Re-check the status we read. If the bridge claimed it in the interim
        // the snapshot is stale — leave the claim alone.
        if ((d.data() as { status?: string }).status !== STATUS_PENDING) continue;

        batch.update(d.ref, {
          status: STATUS_EXPIRED,
          error:
            "Command expired before the bridge picked it up (bridge offline " +
            "or unreachable at fire time).",
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // users/{uid}/commands/{id} → parent.parent is the user doc.
        const uid = d.ref.parent.parent?.id ?? "unknown";
        perUser.set(uid, (perUser.get(uid) ?? 0) + 1);
        written++;
      }
      await batch.commit();
    }

    // Per-user counts are the signal worth having: a user whose commands expire
    // repeatedly has a bridge problem, and that is the fleet-health input
    // described in SCHEDULING_ARCHITECTURE_V2.md §6.
    const summary = Array.from(perUser.entries())
      .map(([uid, n]) => `${uid}:${n}`)
      .join(" ");
    console.log(
      `sweepExpiredCommands: expired ${written} command(s) across ` +
        `${perUser.size} user(s) — ${summary}`
    );

    if (snap.size >= MAX_DOCS_PER_RUN) {
      console.warn(
        `sweepExpiredCommands: hit the ${MAX_DOCS_PER_RUN}-doc cap; a backlog ` +
          "remains and will be swept on the next tick. This is not normal — " +
          "investigate why so many commands are pending."
      );
    }
  }
);
