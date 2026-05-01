/**
 * enforceScheduleLimits — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 19:00 UTC. Scans every user document and trims the
 * `schedules` array to a maximum of MAX_SCHEDULES entries, keeping the most
 * recently appended items.
 *
 * Server-side defense-in-depth for the same cap enforced at write-time by
 * SchedulesNotifier.addAll on the client. Catches users on older app builds
 * that don't enforce the cap, and any drift that the client-side dedup
 * doesn't catch.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:enforceScheduleLimits
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

const MAX_SCHEDULES = 50;

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
    const errors: { userId: string; error: string }[] = [];

    for (const userDoc of usersSnap.docs) {
      const data = userDoc.data();
      const schedules: unknown = data.schedules;

      if (!Array.isArray(schedules)) continue;
      if (schedules.length <= MAX_SCHEDULES) continue;

      const trimmed = schedules.slice(-MAX_SCHEDULES);
      const removed = schedules.length - trimmed.length;

      try {
        await userDoc.ref.update({ schedules: trimmed });
        console.log(
          `[enforceScheduleLimits] ${userDoc.id}: ` +
            `${schedules.length} → ${trimmed.length} (removed ${removed})`,
        );
        trimmedCount++;
        totalRemoved += removed;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(
          `[enforceScheduleLimits] FAILED ${userDoc.id}: ${msg}`,
        );
        errors.push({ userId: userDoc.id, error: msg });
      }
    }

    console.log(
      `[enforceScheduleLimits] done — usersTrimmed=${trimmedCount}, ` +
        `totalEntriesRemoved=${totalRemoved}, errors=${errors.length}`,
    );

    if (errors.length > 0) {
      console.error(
        `[enforceScheduleLimits] errors:`,
        JSON.stringify(errors),
      );
    }
  },
);
