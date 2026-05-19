/**
 * count_schedules_pre_migration.js
 *
 * Snapshot helper used during the Item #72 dow-fix migration. Counts
 * every user document's `schedules` array length, sums totals, and
 * lists a per-user breakdown.
 *
 * Run pre-invocation to capture a baseline of what
 * migrateClearScheduleItemsV1 is about to clear; run again
 * post-invocation to verify all counts are zero.
 *
 * Auth:
 *   admin.initializeApp() relies on Application Default Credentials.
 *   On Tyler's workstation: `gcloud auth application-default login`
 *   sets these. Without credentials the script exits with an error.
 *
 * Usage:
 *   cd functions
 *   node scripts/count_schedules_pre_migration.js
 */

const admin = require('firebase-admin');

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

(async () => {
  const usersSnap = await db.collection('users').get();
  let usersWithSchedules = 0;
  let totalSchedules = 0;
  const userBreakdown = [];

  for (const userDoc of usersSnap.docs) {
    const data = userDoc.data();
    const schedules = data.schedules;
    if (Array.isArray(schedules) && schedules.length > 0) {
      usersWithSchedules += 1;
      totalSchedules += schedules.length;
      userBreakdown.push({
        uid: userDoc.id,
        email: data.email || '(no email)',
        scheduleCount: schedules.length,
      });
    }
  }

  console.log('PRE-MIGRATION SNAPSHOT');
  console.log(`Users scanned: ${usersSnap.size}`);
  console.log(`Users with schedules: ${usersWithSchedules}`);
  console.log(`Total schedules: ${totalSchedules}`);
  console.log('Breakdown:');
  userBreakdown.forEach((u) => {
    console.log(
      `  ${u.email} (${u.uid}): ${u.scheduleCount} schedules`,
    );
  });
  process.exit(0);
})().catch((err) => {
  console.error('Snapshot failed:', err);
  process.exit(1);
});
