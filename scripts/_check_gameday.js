// Game Day shadow-run checkpoint reader. Read-only.
//
//   node scripts/_check_gameday.js start [firstPitchUTC]   ← window 1
//   node scripts/_check_gameday.js end   [firstPitchUTC]   ← window 2
//
// `firstPitchUTC` is any Date-parsable instant (ISO 8601 preferred) and is used
// ONLY to report the lead time of each planned start. It was hardcoded per run
// and went stale every time; pass it instead:
//
//   node scripts/_check_gameday.js start 2026-08-12T17:40:00Z
//
// Omitting it falls back to DEFAULT_FIRST_PITCH_UTC below and prints a warning,
// so a stale default can never masquerade as the real first pitch again.
//
// Run from the repo root with functions/node_modules on hand (the admin SDK
// MUST come from functions/, not the root — two instances reject each other's
// server timestamps).
//
// ⚠️ Uses a PLAIN .get() with NO orderBy. An orderBy on a field some documents
// lack silently drops them; `gameday_plan_log` looked empty for two days that
// way (audit/S4_RESTORE.md, eighth instance).

const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'icrt6menwsv2d8all8oijs021b06s5',
});
const db = admin.firestore();

const MODE = (process.argv[2] || 'start').toLowerCase();

// Today's Twins run. Used only for the lead-time report; pass argv[3] to override.
const DEFAULT_FIRST_PITCH_UTC = '2026-08-12T17:40:00Z';

const FIRST_PITCH_UTC = (() => {
  const arg = process.argv[3];
  if (!arg) {
    console.log('NOTE: no firstPitchUTC argument — using default ' +
      DEFAULT_FIRST_PITCH_UTC + '. Pass one to be sure it matches the run.');
    return DEFAULT_FIRST_PITCH_UTC;
  }
  if (Number.isNaN(new Date(arg).getTime())) {
    console.error('BAD firstPitchUTC: "' + arg + '" is not a parsable instant. ' +
      'Expected e.g. 2026-08-12T17:40:00Z.');
    process.exit(1);
  }
  return arg;
})();

(async () => {
  // ── plan log: PLAIN get, no orderBy ──────────────────────────────────
  const snap = await db.collection('gameday_plan_log').get();
  const docs = snap.docs.sort((a, b) => (a.id < b.id ? 1 : -1));
  console.log('plan-log docs:', docs.map((d) => d.id).join(', ') || '(none)');

  const latest = docs[0];
  if (!latest) { console.log('NO PLAN-LOG DOCS — planner has not written today.'); process.exit(0); }

  const v = latest.data();
  const rows = v.rows || [];
  const sum = v.lastSummary || null;

  // ── counters ─────────────────────────────────────────────────────────
  console.log('');
  console.log('=== latest tick summary (' + latest.id + ') ===');
  if (!sum) {
    console.log('(no lastSummary — running pre-unconditional-log code)');
  } else {
    // START phase only. END outcomes live in `endSkipped` and are a SEPARATE
    // dimension: a config that plans a start still falls through to the end
    // guards (it must — during a live game every config sits on
    // start_already_planned and still has to reach decideEndSignal). Summing
    // both against configsEnabled would double-count by design.
    const sk = sum.skipped || {};
    const esk = sum.endSkipped || {};
    const skipTotal = Object.values(sk).reduce((a, b) => a + b, 0);
    const accounted = skipTotal + (sum.startsPlanned || 0);
    const errs = sum.errors || 0;
    console.log('  usersScanned   :', sum.usersScanned);
    console.log('  configsEnabled :', sum.configsEnabled);
    console.log('  startsPlanned  :', sum.startsPlanned, '  endsPlanned:', sum.endsPlanned);
    console.log('  espnErrors     :', sum.espnErrors, '  errors:', errs);
    console.log('  skipped (START):', JSON.stringify(sk));
    console.log('  endSkipped     :', JSON.stringify(esk));
    // A config that THREW is counted in errors and may never have reached a
    // bucket, so it can legitimately leave the sum short by up to `errors`.
    const ok = accounted === sum.configsEnabled ||
      (accounted < sum.configsEnabled && accounted + errs >= sum.configsEnabled);
    console.log('  RECONCILES     :', accounted, '/', sum.configsEnabled,
      accounted === sum.configsEnabled ? '✓'
        : ok ? '✓ (short by ' + (sum.configsEnabled - accounted) + ', within errors=' + errs + ')'
          : '✗ UNACCOUNTED CONFIGS');
    if (sum.endSkipped === undefined) {
      console.log('  NOTE: no endSkipped field — this doc predates the ' +
        '2026-08-11 accounting fix; its skipped map may still carry stale ' +
        'keys from the merge bug and will not reconcile.');
    }
  }

  // ── the rows this window cares about ─────────────────────────────────
  const want = MODE === 'end' ? 'plan_end' : 'plan_start';
  const hits = rows.filter((r) => r.action === want);
  console.log('');
  console.log('=== ' + want + ' rows: ' + hits.length + ' ===');
  for (const r of hits) {
    console.log('  ' + (r.teamSlug || '?') + '  uid=' + String(r.uid).slice(0, 8) +
      '  fireAt=' + r.fireAt + (r.reason ? '  reason=' + r.reason : '') +
      (r.channels ? '  channels=' + JSON.stringify(r.channels) : ''));
    if (MODE === 'start' && r.fireAt) {
      const lead = (new Date(FIRST_PITCH_UTC) - new Date(r.fireAt)) / 60000;
      console.log('        first pitch ' + FIRST_PITCH_UTC +
        '  → fires ' + Math.round(lead) + ' min before first pitch');
    }
  }
  if (!hits.length) console.log('  (none yet)');

  // consecutive-finals evidence lives on the session docs
  if (MODE === 'end') {
    const ss = await db.collectionGroup('game_day_sessions').get().catch(() => null);
    if (ss && !ss.empty) {
      console.log('');
      console.log('=== end-signal guard state ===');
      ss.docs.forEach((d) => {
        const s = d.data();
        console.log('  ' + d.id + '  consecutiveFinalPolls=' + (s.consecutiveFinalPolls ?? '-') +
          '  endFiredAt=' + (s.endFiredAt ? new Date(s.endFiredAt.toMillis()).toISOString() : 'null') +
          '  startPlannedAt=' + (s.startPlannedAt ? 'set' : 'null'));
      });
    }
    const endSkips = rows.filter((r) => String(r.reason || '').startsWith('end:'));
    if (endSkips.length) {
      console.log('  end-guard skips:', JSON.stringify(endSkips.map((r) => r.reason)));
    }
  }

  // ── the safety invariant ─────────────────────────────────────────────
  const fj = await db.collectionGroup('fire_jobs').get();
  console.log('');
  console.log('fire_jobs docs:', fj.size,
    fj.size === 0 ? '✓ log-only held' : '*** UNEXPECTED — write_jobs may be ON ***');

  const flag = await db.collection('config').doc('gameday_planner').get();
  console.log('write_jobs   :', flag.exists ? JSON.stringify(flag.data()) : 'doc absent → LOG-ONLY ✓');
  process.exit(0);
})().catch((e) => { console.error('CHECK FAILED:', e.message); process.exit(1); });
