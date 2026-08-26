/**
 * repair_empty_repeatdays.js — one-off admin repair (P0 2.5.1 fast-follow)
 *
 * WHY: Enabled schedules whose repeatDays produce a WLED dow bitmask of 0
 * (empty list, or only unrecognized day names) arm a controller timer that
 * takes one of the 8 slots but NEVER fires. They accumulate until the timer
 * table is full and new schedules can't arm (field: 6/8 slots dead, dow:0,
 * fingerprints 20:44 / 20:45 / 23:20, macros 11-16). The app fix (commit
 * "kill dead dow:0 timers …") stops NEW ones and reclaims slots on the next
 * sync, but existing poisoned docs keep re-arming a dow:0 timer every sync
 * until the stored data is repaired — that's what this script does.
 *
 * WHAT: Scans every user doc's `schedules` array (ScheduleItem.toJson shape)
 * for entries with `enabled === true` whose repeatDays map to dow:0.
 *   • DRY-RUN (default): prints uid / index / id / name / on/off times /
 *     repeatDays for each poisoned entry. Writes NOTHING.
 *   • --confirm: sets `enabled: false` and stamps `repairReason` on each
 *     poisoned entry, then writes the array back. DISABLE, never delete — the
 *     user can see the entry in their schedule list and re-add valid days.
 *
 * Mirrors wledDowMaskForDayList() in lib/features/wled/wled_dow.dart exactly
 * (Mon=bit0..Sun=bit6; any "daily" substring → 127; unrecognized → 0) so the
 * script's "poisoned" verdict matches the app's arm-boundary guard.
 *
 * Idempotent: an already-disabled entry is not flagged (only enabled ones can
 * arm a live dead timer), so a second run finds nothing new to repair.
 *
 * Run (SAME protocol as the neighborhood wipe — dry-run, review, then confirm):
 *   node scripts/repair_empty_repeatdays.js              # dry-run, no writes
 *   node scripts/repair_empty_repeatdays.js --confirm    # apply the disable
 *
 * Service account: defaults to the in-repo admin-sdk JSON; override with
 *   --key="C:\\path\\to\\serviceAccount.json"
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
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const CONFIRM = process.argv.includes('--confirm');

// ── WLED dow bitmask — byte-for-byte mirror of wled_dow.dart ──────────────
const DOW_BITS = {
  mon: 1, monday: 1,
  tue: 2, tues: 2, tuesday: 2,
  wed: 4, wednesday: 4,
  thu: 8, thurs: 8, thursday: 8,
  fri: 16, friday: 16,
  sat: 32, saturday: 32,
  sun: 64, sunday: 64,
};

/** Mirror of wledDowMaskForDayList: "daily" substring wins (127); else OR the
 *  recognized day bits; unrecognized entries contribute 0. */
function dowMaskForDayList(days) {
  if (!Array.isArray(days)) return 0;
  if (days.some((d) => String(d).toLowerCase().includes('daily'))) return 127;
  let mask = 0;
  for (const d of days) {
    mask |= DOW_BITS[String(d).toLowerCase().trim()] || 0;
  }
  return mask;
}

/** An enabled schedule whose repeatDays produce dow:0 is a dead timer. */
function isPoisoned(sched) {
  return sched
    && sched.enabled === true
    && dowMaskForDayList(sched.repeatDays) === 0;
}

async function main() {
  console.log(
    CONFIRM
      ? '*** --confirm: poisoned schedules will be DISABLED (enabled:false) ***'
      : 'DRY-RUN (no writes). Re-run with --confirm to apply.'
  );

  const usersSnap = await db.collection('users').get();
  console.log(`Scanning ${usersSnap.size} users…\n`);

  const stamp = new Date().toISOString();
  let usersAffected = 0;
  let entriesFound = 0;

  for (const userDoc of usersSnap.docs) {
    const schedules = userDoc.data().schedules;
    if (!Array.isArray(schedules) || schedules.length === 0) continue;

    const hits = [];
    const repaired = schedules.map((s, i) => {
      if (!isPoisoned(s)) return s;
      hits.push({ i, s });
      return {
        ...s,
        enabled: false,
        repairReason:
          `auto-disabled ${stamp}: empty/invalid repeatDays produced a dead `
          + `WLED timer (dow:0, never fired) — re-pick days to re-enable `
          + `(P0 2.5.1)`,
      };
    });

    if (hits.length === 0) continue;

    usersAffected++;
    entriesFound += hits.length;
    console.log(`user ${userDoc.id} — ${hits.length} poisoned schedule(s):`);
    for (const { i, s } of hits) {
      console.log(
        `    [${i}] id=${s.id || '(none)'} name=${JSON.stringify(s.actionLabel)}`
        + ` on=${s.timeLabel || '?'} off=${s.offTimeLabel || '—'}`
        + ` repeatDays=${JSON.stringify(s.repeatDays)}`
      );
    }

    if (CONFIRM) {
      await userDoc.ref.update({ schedules: repaired });
      console.log(`    → disabled ${hits.length} entr(y|ies).`);
    }
    console.log('');
  }

  console.log('Done.');
  console.log(`  Users with poisoned schedules: ${usersAffected}`);
  console.log(`  Poisoned schedules ${CONFIRM ? 'disabled' : 'found'}: ${entriesFound}`);
  if (!CONFIRM && entriesFound > 0) {
    console.log('\n  Review the list above, then re-run with --confirm to disable them.');
  }
  process.exit(0);
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
