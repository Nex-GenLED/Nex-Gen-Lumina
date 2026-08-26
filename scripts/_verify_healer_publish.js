// _verify_healer_publish.js
//
// READ-ONLY verification of the HEALER PUBLISH (audit/HEALER_PUBLISH.md §7.2b).
// Modifies NOTHING — no Firestore write, no device write.
//
// Reads users/{uid}/controllers/{controllerId} with a CLIENT credential and
// prints the two device-fact families plus their publish history, then
// cross-checks the base boundaries against the controller's live
// /json/cfg timers.ins.
//
// ── WHY A CLIENT CREDENTIAL AND NOT THE ADMIN SDK ───────────────────────────
// The Admin SDK bypasses security rules, so an admin readback proves the field
// EXISTS — never that the app can read it. That distinction already cost a full
// day on the solar flag (config/solar_scheduling was written and verified with
// admin, while the client got 403 and the feature stayed off fleet-wide).
//
// So: admin is used ONLY to mint a custom token for the target uid; every read
// of the controller document goes through the Firestore REST API as that user,
// which means rules apply exactly as they do in the app.
//
// ── USAGE ───────────────────────────────────────────────────────────────────
//   # 1. BEFORE opening the app on the phone — capture the baseline
//   node scripts/_verify_healer_publish.js --save=before.json
//
//   # 2. Open the app on home Wi-Fi, let it connect to the controller.
//   #    Do NOT run a Neighborhood Sync or a Game Day apply — those publish
//   #    through the OLD path and would invalidate step 1.
//
//   # 3. AFTER — diff against the baseline
//   node scripts/_verify_healer_publish.js --before=before.json
//
// Flags:
//   --uid=<uid>            default: the bench account
//   --controller=<docId>   default: 192_168_1_150
//   --ip=<addr>            controller IP for the timers cross-check ('' skips)
//   --save=<file>          write this reading to a file
//   --before=<file>        compare against a saved reading
//   --key=<path>           service-account json (else GOOGLE_APPLICATION_CREDENTIALS)

'use strict';

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');
const { resolveServiceAccountPath } = require('./_service_account');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const WEB_API_KEY = 'AIzaSyCWwqffD-ggRh5-IYwR2ldjaztd-Jgz0JY'; // android key, firebase_options.dart
const DEFAULT_SA = resolveServiceAccountPath();

const DEFAULT_UID = 'wrQRUUKyXyc0deyuu0ORS6wsovO2';
const DEFAULT_CONTROLLER = '192_168_1_150';
const DEFAULT_IP = '192.168.1.150';

const PART = 'participating_channels';
const BASE = 'base_boundaries';

/// Shipped in +72. Written on EVERY facts-publish attempt including `offered`,
/// so its ABSENCE means the running build predates the mirror (or the healer
/// never attempted). That makes it a build-identity witness as well as an
/// outcome witness.
const DISP = 'participation_publish_disposition';

function parseArgs(argv) {
  const a = {
    uid: DEFAULT_UID, controller: DEFAULT_CONTROLLER, ip: DEFAULT_IP,
    save: null, before: null, keyPath: null,
  };
  for (const s of argv.slice(2)) {
    if (s.startsWith('--uid=')) a.uid = s.slice(6);
    else if (s.startsWith('--controller=')) a.controller = s.slice(13);
    else if (s.startsWith('--ip=')) a.ip = s.slice(5);
    else if (s.startsWith('--save=')) a.save = s.slice(7);
    else if (s.startsWith('--before=')) a.before = s.slice(9);
    else if (s.startsWith('--key=')) a.keyPath = s.slice(6);
    else if (s === '-h' || s === '--help') {
      console.log(fs.readFileSync(__filename, 'utf8')
        .split('\n').filter(l => l.startsWith('//')).join('\n'));
      process.exit(0);
    } else { console.error(`Unknown argument: ${s}`); process.exit(1); }
  }
  return a;
}

/** Firestore REST -> plain JS. Only the shapes this document uses. */
function decode(v) {
  if (v === null || v === undefined) return null;
  if ('nullValue' in v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decode);
  if ('mapValue' in v) {
    const o = {};
    for (const [k, val] of Object.entries(v.mapValue.fields || {})) o[k] = decode(val);
    return o;
  }
  return v;
}

async function idTokenFor(uid) {
  const customToken = await admin.auth().createCustomToken(uid);
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  });
  const json = await resp.json();
  if (!resp.ok) {
    console.error('Custom-token exchange FAILED:', JSON.stringify(json, null, 2));
    process.exit(1);
  }
  return json.idToken;
}

/** Reads the controller doc AS THE USER, so rules apply. */
async function readAsClient(idToken, uid, controllerId) {
  const docPath = `users/${uid}/controllers/${controllerId}`;
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}` +
    `/databases/(default)/documents/${docPath}`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${idToken}` } });
  const text = await resp.text();
  if (resp.status === 403) {
    console.error(`\n*** CLIENT READ DENIED (403) on ${docPath} ***`);
    console.error('The field may exist and still be unreachable by the app.');
    console.error(text.slice(0, 600));
    process.exit(2);
  }
  if (resp.status === 404) {
    console.error(`\n*** DOCUMENT NOT FOUND: ${docPath}`);
    process.exit(2);
  }
  if (!resp.ok) {
    console.error(`HTTP ${resp.status}`, text.slice(0, 600));
    process.exit(1);
  }
  const doc = JSON.parse(text);
  const out = {};
  for (const [k, v] of Object.entries(doc.fields || {})) out[k] = decode(v);
  return out;
}

/** Live timers.ins, for the cross-check. Null when unreachable. */
async function readTimers(ip) {
  if (!ip) return null;
  try {
    const ctl = AbortSignal.timeout(8000);
    const resp = await fetch(`http://${ip}/json/cfg`, { signal: ctl });
    if (!resp.ok) return null;
    const cfg = await resp.json();
    const ins = cfg && cfg.timers && cfg.timers.ins;
    return Array.isArray(ins) ? { ins, gc: cfg.light && cfg.light.gc } : null;
  } catch (e) {
    console.log(`  (controller unreachable: ${e.message})`);
    return null;
  }
}

function show(label, d) {
  const has = k => Object.prototype.hasOwnProperty.call(d, k);
  console.log(`\n── ${label} ──`);
  console.log(`  ${PART}            : ${has(PART) ? JSON.stringify(d[PART]) : 'ABSENT (never published)'}`);
  console.log(`  ..._device_ids     : ${JSON.stringify(d[`${PART}_device_ids`] ?? null)}`);
  console.log(`  ..._source         : ${d[`${PART}_source`] ?? '—'}`);
  console.log(`  ..._at             : ${d[`${PART}_at`] ?? '—'}`);
  console.log(`  ..._publish_count  : ${d[`${PART}_publish_count`] ?? '—'}`);
  console.log(`  ..._previous       : ${has(`${PART}_previous`) ? JSON.stringify(d[`${PART}_previous`]) : 'absent (first write of a session)'}`);
  console.log(`  ${BASE}            : ${has(BASE) ? `${d[BASE].length} row(s)` : 'ABSENT'}`);
  for (const r of d[BASE] || []) {
    const when = r.kind === 'clock'
      ? `${String(r.hour).padStart(2, '0')}:${String(r.minute).padStart(2, '0')}`
      : `${r.offset_minutes >= 0 ? '+' : ''}${r.offset_minutes} min`;
    console.log(`      [${r.index}] ${String(r.kind).padEnd(7)} ${when.padEnd(9)} macro ${String(r.macro).padEnd(4)} ${String(r.role).padEnd(12)} dow ${r.dow}`);
  }
  console.log(`  ..._slots_read     : ${d[`${BASE}_slots_read`] ?? '—'}`);
  console.log(`  ..._indices_are_slots: ${d[`${BASE}_indices_are_slots`] ?? '—'}`);
  console.log(`  ..._dow_bit0       : ${d[`${BASE}_dow_bit0`] ?? '—'}`);
  console.log(`  ..._source / _at   : ${d[`${BASE}_source`] ?? '—'} / ${d[`${BASE}_at`] ?? '—'}`);
  console.log(`  ..._publish_count  : ${d[`${BASE}_publish_count`] ?? '—'}`);
  console.log('');
  if (!has(DISP)) {
    console.log(`  ${DISP}`);
    console.log('      ABSENT — the healer has never attempted a publish here,');
    console.log('      OR the running build PREDATES the +72 disposition mirror.');
    console.log('      The mirror writes on EVERY attempt including "offered", so');
    console.log('      an absent field on a build >= +72 is impossible.');
  } else {
    console.log(`  ${DISP}`);
    console.log(`      ${d[DISP]}`);
    console.log(`      at: ${d[`${DISP}_at`] ?? '—'}`);
    if (String(d[DISP]).startsWith('SKIPPED')) {
      console.log('      ^^ LEGIBLE RED. Diagnose from this label; do not re-run blindly.');
    }
  }
}

function crossCheck(d, timers) {
  console.log('\n── STEP 2 · base boundaries vs live timers.ins ──');
  if (!timers) { console.log('  SKIPPED — controller not reachable'); return; }
  const armed = timers.ins.filter(t => (t.en === 1 || t.en === true) && t.macro !== 0);
  if (!Object.prototype.hasOwnProperty.call(d, BASE)) {
    console.log(`  NOT YET PUBLISHED — device has ${armed.length} armed row(s).`);
    console.log('  Expected on a BASELINE reading (before the app has connected');
    console.log('  on a build carrying the healer publish). Not a mismatch.');
    return;
  }
  const rows = d[BASE] || [];
  console.log(`  device armed rows : ${armed.length}`);
  console.log(`  published rows    : ${rows.length}`);
  let ok = armed.length === rows.length;
  armed.forEach((t, i) => {
    const r = rows[i];
    if (!r) { ok = false; return; }
    const solar = t.hour === 255;
    const agree = solar
      ? r.kind !== 'clock' && r.macro === t.macro && r.dow === t.dow
      : r.kind === 'clock' && r.hour === t.hour && r.minute === t.min &&
        r.macro === t.macro && r.dow === t.dow;
    if (!agree) ok = false;
    console.log(`   ${agree ? 'OK  ' : 'MISMATCH'} slot-order ${i}: device en=${t.en} hour=${t.hour} min=${t.min} macro=${t.macro} dow=${t.dow}`);
  });
  console.log(`  => ${ok ? 'MATCH' : '*** MISMATCH ***'}`);
  console.log('\n── STEP 3 · gamma ──');
  const col = timers.gc && timers.gc.col;
  console.log(`  light.gc.col = ${col} ${col === 2.8 ? '(OK — still 2.8)' : '*** EXPECTED 2.8 ***'}`);
}

/// Order-independent stringify.
///
/// Firestore does not guarantee map key order between reads, so a plain
/// JSON.stringify of `base_boundaries` (an array of maps) reported
/// "value changed: YES" for a byte-identical value. A false change signal in a
/// verification tool is worse than no signal — it is the thing that gets
/// believed. Keys are sorted recursively before comparison.
function canon(v) {
  if (Array.isArray(v)) return `[${v.map(canon).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${canon(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v ?? null);
}

function diff(before, after) {
  console.log('\n── PUBLISH HISTORY · before → after ──');
  for (const fam of [PART, BASE]) {
    const b = before[`${fam}_publish_count`] ?? 0;
    const a = after[`${fam}_publish_count`] ?? 0;
    const valB = canon(before[fam] ?? null);
    const valA = canon(after[fam] ?? null);
    const delta = a - b;
    console.log(`  ${fam}`);
    console.log(`      publish_count : ${b} → ${a}  (${delta >= 0 ? '+' : ''}${delta})`);
    console.log(`      value changed : ${valB === valA ? 'no' : 'YES'}`);
    if (delta === 0) {
      console.log('      → DEDUPED. Correct for a second connect in the SAME app session.');
    } else if (delta === 1 && valB === valA) {
      console.log('      → REPUBLISHED, value unchanged. Correct after a RELAUNCH');
      console.log('        (process-scoped memo, the deliberate self-heal). NOT a bug.');
    } else if (delta === 1) {
      console.log('      → PUBLISHED a changed value.');
    } else {
      console.log(`      → *** ${delta} writes. Expected 0 or 1; investigate dedup. ***`);
    }
  }
}

async function main() {
  const args = parseArgs(process.argv);
  const saPath = args.keyPath || process.env.GOOGLE_APPLICATION_CREDENTIALS || DEFAULT_SA;
  admin.initializeApp({
    credential: admin.credential.cert(require(path.resolve(saPath))),
    projectId: PROJECT_ID,
  });

  console.log(`Reading users/${args.uid}/controllers/${args.controller}`);
  console.log('as a CLIENT (rules apply) — admin is used only to mint the token.');

  const idToken = await idTokenFor(args.uid);
  const doc = await readAsClient(idToken, args.uid, args.controller);
  console.log('  client read OK — the app can see this document.');

  show('CURRENT', doc);
  crossCheck(doc, await readTimers(args.ip));

  if (args.before) {
    const before = JSON.parse(fs.readFileSync(args.before, 'utf8'));
    diff(before, doc);
    const b = before[DISP] ?? '(absent)';
    const a = doc[DISP] ?? '(absent)';
    console.log(`  ${DISP}`);
    console.log(`      ${b}  ->  ${a}`);
    if (b === '(absent)' && a !== '(absent)') {
      console.log('      -> FIRST MIRRORED OUTCOME. The running build carries +72.');
    } else if (a === '(absent)') {
      console.log('      -> still absent: the build that ran does NOT contain the');
      console.log('         mirror, so it is NOT +72. Check the in-app version.');
    }
  }
  if (args.save) {
    fs.writeFileSync(args.save, JSON.stringify(doc, null, 2));
    console.log(`\nSaved to ${args.save}`);
  }
  console.log('\nRead-only: nothing was written.');
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
