/**
 * audit_fleet_schedules.js — READ-ONLY fleet schedule census
 *
 * WHY: We disabled ~40 dow:0 "poisoned" schedules with
 * repair_empty_repeatdays.js (P0 2.5.1 fast-follow). Before we run any MORE
 * cleanup we want the actual shape of the fleet's schedule data: are there
 * still enabled dow:0 stragglers written by pre-2.5.1 apps? Structurally
 * corrupt docs that crash ScheduleItem.fromJson at boot? Duplicate pairs both
 * armed? This census answers "is targeted cleanup even needed, and of what?"
 * so each class gets its own deliberate disposition instead of a blind sweep.
 *
 * WHAT: Scans every user doc's `schedules` array (ScheduleItem.toJson shape,
 * same storage location the repair script mutates) and classifies each entry
 * into exactly one primary class, plus a cross-cutting DUPLICATE overlay:
 *
 *   HEALTHY            enabled, structurally sound, armable time(s), dow != 0
 *   DISABLED-CLEAN     enabled:false, no repairReason, otherwise sound
 *                        (user toggled it off — inert, not a defect)
 *   DISABLED-REPAIRED  repairReason present — our ~40 (or later repairs)
 *   DOW-DEAD           enabled:true + repeatDays map to WLED dow:0
 *                        (straggler dead timer: takes a slot, never fires)
 *   ORPHAN/MALFORMED   fromJson would throw (missing/mistyped required field),
 *                        OR an unparseable on/off time, OR a preset ref outside
 *                        the valid 1–250 range (dangling macro)
 *   DUPLICATE          (overlay) same content fingerprint as another entry in
 *                        the SAME user, both enabled
 *
 * Precedence (first match wins) for the PRIMARY class:
 *   1. structural error  → ORPHAN/MALFORMED   (can't safely read the rest)
 *   2. repairReason set  → DISABLED-REPAIRED  (known, already dispositioned)
 *   3. unparseable time  → ORPHAN/MALFORMED
 *   4. dangling presetId → ORPHAN/MALFORMED
 *   5. enabled & dow:0   → DOW-DEAD
 *   6. enabled           → HEALTHY
 *   7. else              → DISABLED-CLEAN
 * DUPLICATE is computed separately (a HEALTHY doc can also be a duplicate) and
 * reported as its own overlay so totals over the 7 primary classes still sum
 * to the fleet doc count.
 *
 * The dow-mask, time-armability, and preset-range checks are byte-for-byte
 * mirrors of the app's arm-boundary logic — wledDowMaskForDayList()
 * (wled_dow.dart), _isArmableTimeLabel()/_parseTimeLabel() and the 1–250 macro
 * range (schedule_sync.dart), and ScheduleItem.fromJson()'s casts
 * (schedule_models.dart) — so a "DOW-DEAD" / "unparseable" / "malformed"
 * verdict here means the same thing the running app would decide.
 *
 * NO WRITES. This script never mutates Firestore. The census informs
 * disposition; it does not perform it. Follow-ups:
 *   • DOW-DEAD stragglers → disable via repair_empty_repeatdays.js --confirm
 *   • DUPLICATE           → dedupe with a rule we choose (cleanup_schedules.js)
 *   • ORPHAN/MALFORMED    → review case-by-case (these can crash fromJson)
 *
 * Run:
 *   node scripts/audit_fleet_schedules.js                 # full fleet
 *   node scripts/audit_fleet_schedules.js --user=<uid>    # one user (spot check)
 *   node scripts/audit_fleet_schedules.js --paths         # print doc paths only
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
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

const userArg = process.argv.find((a) => a.startsWith('--user='));
const ONLY_USER = userArg ? userArg.slice('--user='.length) : null;
const PATHS_ONLY = process.argv.includes('--paths');

// ── WLED dow bitmask — byte-for-byte mirror of wled_dow.dart ────────────────
// (identical to repair_empty_repeatdays.js so the two scripts agree on "dead")
const DOW_BITS = {
  mon: 1, monday: 1,
  tue: 2, tues: 2, tuesday: 2,
  wed: 4, wednesday: 4,
  thu: 8, thurs: 8, thursday: 8,
  fri: 16, friday: 16,
  sat: 32, saturday: 32,
  sun: 64, sunday: 64,
};

/** Mirror of wledDowMaskForDayList: any "daily" substring → 127; else OR the
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

// ── Time armability — mirror of _isArmableTimeLabel/_parseTimeLabel ─────────
const AMPM_RE = /^(\d{1,2}):(\d{2})\s*([ap]m)$/i;
const H24_RE = /^(\d{1,2}):(\d{2})$/;

/** True iff WLED could actually arm this label: a solar keyword or a clock
 *  time the app's parser recognizes (12h with valid am/pm, or 24h in range). */
function isArmableTimeLabel(label) {
  if (typeof label !== 'string') return false;
  const l = label.trim().toLowerCase();
  if (l === 'sunrise' || l === 'sunset') return true;

  const m = AMPM_RE.exec(l);
  if (m) {
    const hh = parseInt(m[1], 10);
    const mm = parseInt(m[2], 10);
    return hh >= 1 && hh <= 12 && mm >= 0 && mm <= 59;
  }

  const m24 = H24_RE.exec(l);
  if (m24) {
    const hh = parseInt(m24[1], 10);
    const mm = parseInt(m24[2], 10);
    return hh <= 23 && mm <= 59; // regex guarantees non-negative
  }

  return false;
}

// hasOffTime mirror: non-null AND non-empty (ScheduleItem.hasOffTime).
function hasOffTime(s) {
  return typeof s.offTimeLabel === 'string' && s.offTimeLabel.length > 0;
}

/**
 * Structural validity — replicates the casts in ScheduleItem.fromJson().
 * Returns a human reason string if fromJson WOULD throw (so the app can't even
 * load this user's schedule list), else null. Kept faithful to every `as`
 * cast the model performs, including the nullable-but-typed extras.
 */
function structuralError(s) {
  if (s === null || typeof s !== 'object' || Array.isArray(s)) {
    return 'entry is not a JSON object';
  }
  if (typeof s.id !== 'string') return 'id missing / non-string';
  if (typeof s.timeLabel !== 'string') return 'timeLabel missing / non-string';
  if (!Array.isArray(s.repeatDays)) return 'repeatDays missing / non-array';
  if (typeof s.actionLabel !== 'string') return 'actionLabel missing / non-string';
  if (typeof s.enabled !== 'boolean') return 'enabled missing / non-bool';
  if (s.offTimeLabel != null && typeof s.offTimeLabel !== 'string') {
    return 'offTimeLabel present but non-string';
  }
  if (s.presetId != null && !Number.isInteger(s.presetId)) {
    return 'presetId present but non-integer';
  }
  if (s.useAudioReactive != null && typeof s.useAudioReactive !== 'boolean') {
    return 'useAudioReactive present but non-bool';
  }
  if (s.sourcePromptId != null && typeof s.sourcePromptId !== 'string') {
    return 'sourcePromptId present but non-string';
  }
  return null;
}

/** repairReason is stamped only by repair_empty_repeatdays.js --confirm. */
function hasRepairReason(s) {
  return typeof s.repairReason === 'string' && s.repairReason.length > 0;
}

/**
 * A preset macro WLED can honor is 1–250 (schedule_sync.dart doc + _presetFor
 * Action). A presetId present but outside that range points at no loadable
 * preset — a dangling macro. (Structural non-int presetIds are caught earlier.)
 */
function danglingPresetId(s) {
  return s.presetId != null && (s.presetId < 1 || s.presetId > 250);
}

/** Content fingerprint for duplicate detection — same key cleanup_schedules.js
 *  dedupes on: on-time | off-time | repeatDays | actionLabel. */
function fingerprint(s) {
  return [
    s.timeLabel,
    s.offTimeLabel || '',
    (Array.isArray(s.repeatDays) ? s.repeatDays : []).join(','),
    s.actionLabel,
  ].join('|');
}

/** Assign the single primary class (precedence order documented in header). */
function classify(s) {
  const structural = structuralError(s);
  if (structural) return { cls: 'ORPHAN/MALFORMED', reason: structural };

  if (hasRepairReason(s)) return { cls: 'DISABLED-REPAIRED', reason: null };

  const badTimes = [];
  if (!isArmableTimeLabel(s.timeLabel)) badTimes.push(s.timeLabel);
  if (hasOffTime(s) && !isArmableTimeLabel(s.offTimeLabel)) {
    badTimes.push(s.offTimeLabel);
  }
  if (badTimes.length > 0) {
    return {
      cls: 'ORPHAN/MALFORMED',
      reason: `unparseable time (${badTimes.map((t) => JSON.stringify(t)).join(', ')})`,
    };
  }

  if (danglingPresetId(s)) {
    return { cls: 'ORPHAN/MALFORMED', reason: `dangling presetId ${s.presetId}` };
  }

  if (s.enabled === true && dowMaskForDayList(s.repeatDays) === 0) {
    return { cls: 'DOW-DEAD', reason: `repeatDays ${JSON.stringify(s.repeatDays)} → dow:0` };
  }

  if (s.enabled === true) return { cls: 'HEALTHY', reason: null };
  return { cls: 'DISABLED-CLEAN', reason: null };
}

// Short one-line description of an entry for the report.
function describe(s, i) {
  const id = (s && typeof s.id === 'string' && s.id) ? s.id : '(no id)';
  const name = s ? JSON.stringify(s.actionLabel) : '(unreadable)';
  const on = s ? (s.timeLabel || '?') : '?';
  const off = s && hasOffTime(s) ? s.offTimeLabel : '—';
  const days = s ? JSON.stringify(s.repeatDays) : '?';
  const en = s && s.enabled === true ? 'on' : 'off';
  const preset = s && s.presetId != null ? ` preset=${s.presetId}` : '';
  return `[${i}] id=${id} name=${name} on=${on} off=${off} `
    + `days=${days} enabled=${en}${preset}`;
}

async function main() {
  console.log('READ-ONLY census — no writes.\n');

  let usersSnap;
  if (ONLY_USER) {
    const doc = await db.collection('users').doc(ONLY_USER).get();
    if (!doc.exists) {
      console.log(`User ${ONLY_USER} not found.`);
      process.exit(1);
    }
    usersSnap = { docs: [doc], size: 1 };
    console.log(`Scanning single user ${ONLY_USER}…\n`);
  } else {
    usersSnap = await db.collection('users').get();
    console.log(`Scanning ${usersSnap.size} users…\n`);
  }

  // Fleet tallies.
  const CLASSES = [
    'HEALTHY',
    'DISABLED-CLEAN',
    'DISABLED-REPAIRED',
    'DOW-DEAD',
    'ORPHAN/MALFORMED',
  ];
  const totals = Object.fromEntries(CLASSES.map((c) => [c, 0]));
  let totalDocs = 0;
  let usersWithSchedules = 0;
  let usersFlagged = 0;
  let dupGroupsFleet = 0; // distinct fingerprints with >1 enabled copy
  let dupDocsFleet = 0;   // total docs participating in a dup group
  let dupExtraFleet = 0;  // removable copies (docs − one keeper per group)

  for (const userDoc of usersSnap.docs) {
    const schedules = userDoc.data().schedules;
    if (!Array.isArray(schedules) || schedules.length === 0) continue;
    usersWithSchedules++;

    const rows = schedules.map((s, i) => ({ i, s, ...classify(s) }));
    for (const r of rows) totals[r.cls]++;
    totalDocs += rows.length;

    // Duplicate overlay: fingerprint groups among ENABLED, structurally-sound
    // entries (a garbage entry has no meaningful fingerprint).
    const groups = new Map();
    for (const r of rows) {
      if (r.s && r.s.enabled === true && !structuralError(r.s)) {
        const fp = fingerprint(r.s);
        if (!groups.has(fp)) groups.set(fp, []);
        groups.get(fp).push(r);
      }
    }
    const dupGroups = [...groups.values()].filter((g) => g.length > 1);
    const dupIdx = new Set();
    for (const g of dupGroups) {
      dupGroupsFleet++;
      dupExtraFleet += g.length - 1; // removable copies beyond the keeper
      for (const r of g) { dupIdx.add(r.i); dupDocsFleet++; }
    }

    const flagged = rows.filter((r) => r.cls !== 'HEALTHY' && r.cls !== 'DISABLED-CLEAN');
    if (flagged.length === 0 && dupGroups.length === 0) continue;
    usersFlagged++;

    if (PATHS_ONLY) {
      for (const r of flagged) {
        console.log(`users/${userDoc.id} · schedules[${r.i}]  ${r.cls}`);
      }
      for (const g of dupGroups) {
        for (const r of g) {
          console.log(`users/${userDoc.id} · schedules[${r.i}]  DUPLICATE`);
        }
      }
      continue;
    }

    console.log(`user ${userDoc.id} — ${schedules.length} schedule(s):`);
    for (const r of flagged) {
      const dupTag = dupIdx.has(r.i) ? ' +DUPLICATE' : '';
      console.log(`    ${r.cls}${dupTag}  ${describe(r.s, r.i)}`);
      if (r.reason) console.log(`        ↳ ${r.reason}`);
    }
    // Duplicates that are otherwise HEALTHY/clean (not already printed above).
    for (const g of dupGroups) {
      for (const r of g) {
        if (r.cls === 'HEALTHY' || r.cls === 'DISABLED-CLEAN') {
          console.log(`    DUPLICATE (${r.cls})  ${describe(r.s, r.i)}`);
        }
      }
    }
    console.log('');
  }

  // ── Fleet summary ─────────────────────────────────────────────────────────
  console.log('─'.repeat(60));
  console.log('FLEET CENSUS');
  console.log('─'.repeat(60));
  console.log(`  Users scanned:            ${usersSnap.size}`);
  console.log(`  Users with schedules:     ${usersWithSchedules}`);
  console.log(`  Users with flagged docs:  ${usersFlagged}`);
  console.log(`  Total schedule docs:      ${totalDocs}`);
  console.log('');
  console.log('  Primary class (mutually exclusive — sums to total docs):');
  for (const c of CLASSES) {
    console.log(`    ${c.padEnd(20)} ${totals[c]}`);
  }
  const sum = CLASSES.reduce((a, c) => a + totals[c], 0);
  console.log(`    ${'(sum)'.padEnd(20)} ${sum}${sum === totalDocs ? '  ✓' : '  ✗ MISMATCH'}`);
  console.log('');
  console.log('  Overlay:');
  console.log(`    DUPLICATE            ${dupDocsFleet} doc(s) across ${dupGroupsFleet} group(s) `
    + `— ${dupExtraFleet} removable`);
  console.log('');
  console.log('  Disposition (NOT performed by this script):');
  console.log('    DOW-DEAD          → repair_empty_repeatdays.js --confirm');
  console.log('    DUPLICATE         → dedupe rule of our choosing');
  console.log('    ORPHAN/MALFORMED  → review case-by-case (may crash fromJson)');
  if (totals['DOW-DEAD'] === 0 && totals['ORPHAN/MALFORMED'] === 0 && dupExtraFleet === 0) {
    console.log('\n  Fleet is clean — no targeted cleanup needed.');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
