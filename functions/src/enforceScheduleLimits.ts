/**
 * enforceScheduleLimits — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 19:00 UTC. Scans every user document and trims the
 * `schedules` array to a maximum of MAX_SCHEDULES entries, keeping the most
 * recently appended items.
 *
 * Server-side defense-in-depth for the same cap enforced at write-time by
 * SchedulesNotifier.addAll on the client
 * (lib/features/schedule/schedule_providers.dart:461). Catches users on older
 * app builds that don't enforce the cap, and any drift the client-side dedup
 * doesn't catch.
 *
 * TWO correctness properties this file guarantees:
 *
 *   1. TRANSACTIONAL. The array read-trim-write runs inside a per-user
 *      runTransaction. This is the LAST blind whole-array overwrite in the
 *      system — a third writer the client-side per-uid lock cannot see (it
 *      runs in this Cloud Functions process). Wrapping it in a transaction
 *      means a concurrent client remove/update can't be silently clobbered:
 *      the trim re-reads inside the txn and Firestore retries on conflict.
 *
 *   2. MIGRATION-AWARE. If (and only if) trimming occurred, the identical trim
 *      is applied to the /users/{uid}/schedules subcollection via batched
 *      deletes of the removed ids (translated through the same scheduleSubDocId
 *      contract the client uses). This keeps both shapes convergent during the
 *      array→subcollection dual-write window. Users with no subcollection docs
 *      yet just no-op the deletes.
 *
 * Idempotent (a second run finds length <= cap and does nothing); users
 * without a `schedules` array field are skipped.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:enforceScheduleLimits
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {
  MAX_SCHEDULES,
  planScheduleTrim,
  scheduleSubDocId,
} from "./scheduleMigrationShared";

// admin.initializeApp() is called in index.js — do not call again here.

// Firestore batch limit is 500; keep headroom.
const DELETE_BATCH_SIZE = 450;

export const enforceScheduleLimits = onSchedule(
  {
    schedule: "every sunday 19:00",
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const usersSnap = await db.collection("users").get();

    console.log(
      `[enforceScheduleLimits] scanning ${usersSnap.size} users, ` +
        `cap=${MAX_SCHEDULES}`,
    );

    let trimmedCount = 0;
    let totalRemoved = 0;
    let subDocsDeleted = 0;
    const errors: { userId: string; error: string }[] = [];

    for (const userDoc of usersSnap.docs) {
      // Cheap pre-filter to avoid a transaction for the overwhelming majority
      // of users who are within the cap. The transaction re-reads and
      // re-checks authoritatively, so this is just an optimization.
      const preSchedules: unknown = userDoc.data().schedules;
      if (!Array.isArray(preSchedules)) continue;
      if (preSchedules.length <= MAX_SCHEDULES) continue;

      const userRef = userDoc.ref;

      try {
        // ── 1. Transactional array trim ─────────────────────────────
        const removedIds = await db.runTransaction(async (txn) => {
          const snap = await txn.get(userRef);
          const schedules: unknown = snap.get("schedules");
          const plan = planScheduleTrim(schedules, MAX_SCHEDULES);
          if (!plan.trimmed) return [] as string[];
          txn.update(userRef, { schedules: plan.kept });
          return plan.removedIds;
        });

        if (removedIds.length === 0) continue; // raced away; nothing to do

        trimmedCount++;
        totalRemoved += removedIds.length;
        console.log(
          `[enforceScheduleLimits] ${userDoc.id}: trimmed ${removedIds.length} ` +
            `entr${removedIds.length === 1 ? "y" : "ies"}`,
        );

        // ── 2. Mirror the trim to the subcollection ─────────────────
        const schedulesCol = userRef.collection("schedules");
        for (let i = 0; i < removedIds.length; i += DELETE_BATCH_SIZE) {
          const batch = db.batch();
          for (const rawId of removedIds.slice(i, i + DELETE_BATCH_SIZE)) {
            batch.delete(schedulesCol.doc(scheduleSubDocId(rawId)));
          }
          await batch.commit();
          subDocsDeleted += Math.min(
            DELETE_BATCH_SIZE,
            removedIds.length - i,
          );
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[enforceScheduleLimits] FAILED ${userDoc.id}: ${msg}`);
        errors.push({ userId: userDoc.id, error: msg });
      }
    }

    console.log(
      `[enforceScheduleLimits] done — usersTrimmed=${trimmedCount}, ` +
        `totalEntriesRemoved=${totalRemoved}, ` +
        `subDocsDeleted=${subDocsDeleted}, errors=${errors.length}`,
    );

    if (errors.length > 0) {
      console.error(
        `[enforceScheduleLimits] errors:`,
        JSON.stringify(errors),
      );
    }
  },
);
