/**
 * census_solar_schedules.js — READ-ONLY census (P0 hour:24/25 investigation)
 *
 * WHY: Schedules whose on/off time is the literal label 'Sunset' / 'Sunrise'
 * are written to the controller as WLED timer hour 25 / 24. That encoding is
 * WRONG for WLED: hour 24 means "fire hourly", hour 25 never matches the RTC,
 * and WLED's real sunrise/sunset timers use dedicated sentinels (not 24/25).
 * So EVERY solar-labeled schedule on the fleet is a dead timer that never
 * fires — regardless of the controller's coordinates. Two sources feed this:
 *   1. AI creation defaulting a MISSING time to 'Sunset' (fixed in-app:
 *      "never invent 'Sunset' for a missing time"). Those are clock-intended
 *      schedules mis-stored as solar — id prefix 'ai-'.
 *   2. Genuinely solar-intended schedules — also non-functional under the
 *      current encoding, but the intent was real.
 *
 * WHAT: Scans every user doc's `schedules` array (ScheduleItem.toJson shape)
 * for entries whose `timeLabel` OR `offTimeLabel` is 'sunrise'/'sunset'
 * (case-insensitive). Reports uid / index / id / ai-created? / enabled /
 * name / on/off / repeatDays, plus totals split by AI-created vs manual.
 *
 * READ-ONLY BY DESIGN — there is NO --confirm / repair path. We CANNOT know
 * the intended clock time from the corrupted doc (the 13:20 was lost when the
 * AI stored 'Sunset'), so repair needs user re-entry via the schedule edit UI.
 * This script only tells Tyler HOW MANY customers are affected and which docs.
 *
 * Run:
 *   node scripts/census_solar_schedules.js
 *   node scripts/census_solar_schedules.js --key="C:\\path\\to\\serviceAccount.json"
 */

const path = require('path');
const admin = require('firebase-admin');

const { resolveServiceAccountPath } = require('./_service_account');
const keyArg = process.argv.find((a) => a.startsWith('--key='));
const keyPath = keyArg
  ? keyArg.slice('--key='.length)
  : resolveServiceAccountPath();
const serviceAccount = require(path.resolve(keyPath));
console.log(`Using service account: ${path.resolve(keyPath)}\n`);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

/** A label is solar when it is exactly 'sunrise' or 'sunset' (case/space
 *  insensitive) — the two strings schedule_sync maps to hour 24 / 25. */
function isSolar(label) {
  if (typeof label !== 'string') return false;
  const l = label.trim().toLowerCase();
  return l === 'sunrise' || l === 'sunset';
}

/** True for an AI-created schedule (buildScheduleItemsFromIntents stamps
 *  `id: 'ai-<batchTs>-<i>'`). */
function isAiCreated(sched) {
  return typeof sched?.id === 'string' && sched.id.startsWith('ai-');
}

async function main() {
  console.log('READ-ONLY census of solar-labeled schedules (no writes, ever).\n');

  const usersSnap = await db.collection('users').get();
  console.log(`Scanning ${usersSnap.size} users…\n`);

  let usersAffected = 0;
  let total = 0;
  let aiCreated = 0;
  let manual = 0;
  let enabledCount = 0;

  for (const userDoc of usersSnap.docs) {
    const schedules = userDoc.data().schedules;
    if (!Array.isArray(schedules) || schedules.length === 0) continue;

    const hits = [];
    schedules.forEach((s, i) => {
      if (!s) return;
      if (isSolar(s.timeLabel) || isSolar(s.offTimeLabel)) {
        hits.push({ i, s });
      }
    });

    if (hits.length === 0) continue;

    usersAffected++;
    console.log(`user ${userDoc.id} — ${hits.length} solar schedule(s):`);
    for (const { i, s } of hits) {
      total++;
      const ai = isAiCreated(s);
      if (ai) aiCreated++; else manual++;
      if (s.enabled === true) enabledCount++;
      console.log(
        `    [${i}] id=${s.id || '(none)'}`
        + ` ${ai ? 'AI' : 'manual'}`
        + ` ${s.enabled === true ? 'ENABLED' : 'disabled'}`
        + ` name=${JSON.stringify(s.actionLabel)}`
        + ` on=${JSON.stringify(s.timeLabel)} off=${JSON.stringify(s.offTimeLabel)}`
        + ` repeatDays=${JSON.stringify(s.repeatDays)}`
      );
    }
    console.log('');
  }

  console.log('Done.');
  console.log(`  Users with solar schedules:   ${usersAffected}`);
  console.log(`  Solar schedules total:        ${total}`);
  console.log(`    · AI-created (id 'ai-'):     ${aiCreated}  ← clock-intended, mis-stored`);
  console.log(`    · manual/other:              ${manual}`);
  console.log(`  Enabled (actively dead timers): ${enabledCount}`);
  console.log(
    '\n  NOTE: all of the above never fire under the current WLED encoding.'
    + '\n  No auto-repair — the intended clock time was lost; users must re-enter'
    + '\n  it via the schedule edit UI. This census only sizes the impact.'
  );
  process.exit(0);
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
