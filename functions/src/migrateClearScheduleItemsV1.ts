/**
 * migrateClearScheduleItemsV1 — One-time migration callable. **RETIRED.**
 *
 * ⛔ DO NOT RUN post-subcollection migration. This function clears ONLY the
 *    `schedules` ARRAY field on each user doc — it does not touch the
 *    /users/{uid}/schedules subcollection. Once the array→subcollection
 *    dual-write / backfill is live, running this would wipe the array while
 *    leaving the subcollection populated, DESYNCING the two shapes (and, with
 *    the flag on, the subcollection is the source of truth, so the clear would
 *    silently accomplish nothing while corrupting the migration invariant).
 *    It is retained only as a completed historical record of the Item #72 dow
 *    fix; its idempotency doc keeps a re-invocation a no-op, but treat this as
 *    dead code — do not deploy or invoke it again. No logic change here.
 *
 * ── Original (Item #72) documentation follows ──
 *
 * One-time migration callable.
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

/**
 * AUTH MODEL
 *
 * This callable requires one of:
 *   1. An email on the kMigrationAdminAllowlist (currently:
 *      honeycutt.tylerg@gmail.com — Tyler's Firebase Auth account)
 *   2. An email ending with @nex-genled.com (case-insensitive)
 *
 * Update kMigrationAdminAllowlist if additional admin accounts
 * need invocation rights before @Nex-GenLED.com Firebase Auth
 * identities are provisioned.
 *
 * The function is intended for one-time invocation to clear
 * production ScheduleItems after the Item #72 dow fix. Idempotency
 * tracking at config/migrations/items/migrateClearScheduleItemsV1
 * prevents accidental re-runs.
 */
const kMigrationAdminAllowlist = new Set<string>([
  "honeycutt.tylerg@gmail.com",
]);

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
    //
    // Accept the caller if EITHER their email is on the explicit
    // allowlist (kMigrationAdminAllowlist above) OR their email
    // ends with @nex-genled.com. The allowlist exists because
    // @Nex-GenLED.com isn't yet wired as a Firebase Auth identity
    // provider — only as an outbound email domain — so the founder
    // account (Tyler's Gmail) needs explicit recognition. Domain
    // check is preserved for future admins once the @Nex-GenLED.com
    // identity provider is provisioned.
    const callerEmail = (
      request.auth?.token?.email as string | undefined
    )?.toLowerCase();

    const isAllowlisted =
      callerEmail != null && kMigrationAdminAllowlist.has(callerEmail);

    const isNexGenLedDomain =
      callerEmail != null && callerEmail.endsWith("@nex-genled.com");

    if (!isAllowlisted && !isNexGenLedDomain) {
      throw new HttpsError(
        "permission-denied",
        "migrateClearScheduleItemsV1 requires an authenticated " +
          "caller on the admin allowlist or the @Nex-GenLED.com " +
          "domain.",
      );
    }

    // Resolved (lowercased) email used downstream in the audit log
    // and the completion-doc triggeredBy field. Non-null at this
    // point because both branches above required callerEmail != null.
    const resolvedCallerEmail = callerEmail as string;

    console.log(
      `migrateClearScheduleItemsV1: auth passed for ` +
        `${resolvedCallerEmail} (allowlist=${isAllowlisted}, ` +
        `domain=${isNexGenLedDomain})`,
    );

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
      triggeredBy: resolvedCallerEmail,
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
