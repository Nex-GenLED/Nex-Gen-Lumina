/**
 * read_migration_status.js
 *
 * Reads the Item #72 migration tracking doc at
 *   config/migrations/items/migrateClearScheduleItemsV1
 *
 * Used to confirm idempotency state — whether the migration has run
 * and what its completion summary looks like. Safe to run any time,
 * before or after invocation; does not mutate anything.
 *
 * Auth: same as count_schedules_pre_migration.js — relies on
 *   Application Default Credentials via gcloud.
 *
 * Usage:
 *   cd functions
 *   node scripts/read_migration_status.js
 */

const admin = require('firebase-admin');

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

(async () => {
  const docRef = db.doc(
    'config/migrations/items/migrateClearScheduleItemsV1',
  );
  const snap = await docRef.get();

  if (!snap.exists) {
    console.log('MIGRATION DOC: does not exist');
    process.exit(1);
  }

  console.log('MIGRATION DOC STATE:');
  console.log(JSON.stringify(snap.data(), null, 2));
  process.exit(0);
})().catch((err) => {
  console.error('Read failed:', err);
  process.exit(1);
});
