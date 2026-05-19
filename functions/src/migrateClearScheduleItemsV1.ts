/**
 * migrateClearScheduleItemsV1 — One-time migration callable.
 *
 * Clears every user's `schedules` array so the entire production
 * fleet starts from a clean slate after the WLED dow off-by-one fix
 * (Item #72). CalendarEntries are NOT affected — they fire on
 * specific dates so the off-by-one had different symptoms and a
 * different fix path.
 *
 * Rationale:
 *   WLED firmware's cfg.timers.ins[].dow uses Monday=bit 0 through
 *   Sunday=bit 6. Lumina previously assumed Sun=bit 0, so every
 *   non-Daily recurring schedule has been firing one weekday LATER
 *   than the user intended (Monday schedules fired on Tuesday, etc.)
 *   Daily masks (127) worked under both conventions because all bits
 *   were set, which is why this went undetected for months. Once the
 *   fix lands, existing stored ScheduleItems may carry preset IDs
 *   that pointed at the old (wrong-day) timers — easier to nuke and
 *   let users re-create than to schema-migrate every record.
 *
 * Idempotent: tracks completion in
 *   config/migrations/items/migrateClearScheduleItemsV1
 * with a `completed` boolean. Second invocation is a no-op.
 *
 * Trigger: callable. Invoke manually via Firebase Console or
 *   `firebase functions:shell` after the new build is in production.
 *
 * Auth gate: caller must have an @nex-genled.com email on their
 *   Firebase Auth account. No bypass via client. No
 *   in-app surface — admin-only.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:migrateClearScheduleItemsV1
 *
 * Invocation (firebase functions:shell):
 *   migrateClearScheduleItemsV1({})
 *
 * Item #72.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

const MIGRATION_DOC_PATH =
  "config/migrations/items/migrateClearScheduleItemsV1";

// Firestore batch limit is 500. Keep headroom for the migration-
// tracking doc write that follows the user-doc updates.
const BATCH_SIZE = 400;

export const migrateClearScheduleItemsV1 = onCall(
  {
    region: "us-central1",
    // Walking the entire users collection can take a while on real
    // production data — give it room. 9 min is the v2 max.
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (request) => {
    // ── Auth gate ────────────────────────────────────────────────
    const callerEmail = request.auth?.token?.email as string | undefined;
    if (
      !callerEmail ||
      !callerEmail.toLowerCase().endsWith("@nex-genled.com")
    ) {
      throw new HttpsError(
        "permission-denied",
        "migrateClearScheduleItemsV1 requires an @nex-genled.com " +
          "authenticated caller.",
      );
    }

    const db = admin.firestore();
    const migrationDoc = db.doc(MIGRATION_DOC_PATH);

    // ── Idempotency check ───────────────────────────────────────
    const snap = await migrationDoc.get();
    if (snap.exists && snap.data()?.completed === true) {
      const data = snap.data();
      return {
        status: "already_completed",
        completedAt: data?.completedAt ?? null,
        usersAffected: data?.usersAffected ?? null,
        totalSchedulesCleared: data?.totalSchedulesCleared ?? null,
        triggeredBy: data?.triggeredBy ?? null,
      };
    }

    // ── Walk users in batches ───────────────────────────────────
    const usersSnap = await db.collection("users").get();
    let usersAffected = 0;
    let totalSchedulesCleared = 0;
    const errors: string[] = [];

    for (let i = 0; i < usersSnap.docs.length; i += BATCH_SIZE) {
      const batch = db.batch();
      const slice = usersSnap.docs.slice(i, i + BATCH_SIZE);

      for (const userDoc of slice) {
        const data = userDoc.data();
        const schedulesField = data["schedules"];

        if (
          Array.isArray(schedulesField) &&
          schedulesField.length > 0
        ) {
          totalSchedulesCleared += schedulesField.length;
          usersAffected += 1;
          batch.update(userDoc.ref, { schedules: [] });
        }
      }

      try {
        await batch.commit();
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        errors.push(
          `Batch starting at index ${i} (size ${slice.length}): ${msg}`,
        );
        console.error(
          `[migrateClearScheduleItemsV1] batch ${i / BATCH_SIZE} ` +
            `failed: ${msg}`,
        );
      }
    }

    // ── Mark migration complete ─────────────────────────────────
    await migrationDoc.set({
      completed: true,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      triggeredBy: callerEmail,
      usersAffected,
      totalSchedulesCleared,
      errors,
      notes:
        "WLED dow off-by-one fix (Item #72). ScheduleItems cleared " +
        "so users start with a clean slate on the corrected " +
        "Mon=bit 0 convention. CalendarEntries unaffected.",
    });

    console.log(
      `[migrateClearScheduleItemsV1] complete — ` +
        `usersAffected=${usersAffected}, ` +
        `totalSchedulesCleared=${totalSchedulesCleared}, ` +
        `errors=${errors.length}`,
    );

    return {
      status: "completed",
      usersAffected,
      totalSchedulesCleared,
      errors,
    };
  },
);
