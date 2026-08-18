// _fix_bench_participation.js
//
// Restores a channel that participation has locked out, by repairing the
// ROOFLINE INPUT the resolver derives from — not by writing participation
// itself. See audit/PARTICIPATION_REENTRY.md for the full trace.
//
// WHY THIS EXISTS
// ---------------
// `resolveParticipatingChannels` (channel_participation_resolver.dart) runs a
// default policy with `explicit: null` at every shipped call site:
//
//     channels with segments but NO isPrimary segment are EXCLUDED
//
// On the bench rig, `pixelMap/1` was hand-written on 2026-08-12 (BUILD_LEDGER
// §7.2d Leg B) with `is_primary: false`, to make the rig discriminating for the
// roofline leg. That is durable Firestore state, so every recompute since has
// returned `[0]` — and the reconciler compares the cache against that SAME
// recompute, so it never classifies it stale and never clears it. Channel 1 is
// locked out of design applies, including "All Zones", with no UI path back.
//
// DEFAULT IS DRY-RUN. Nothing is written without --commit.
//
// Usage:
//   node scripts/_fix_bench_participation.js --key=C:\path\to\service-account.json
//   node scripts/_fix_bench_participation.js --key=... --commit
//   node scripts/_fix_bench_participation.js --key=... --mode=delete --commit
//
// Or set GOOGLE_APPLICATION_CREDENTIALS in the environment.
//
// Modes:
//   flip   (default) — set is_primary:true on every segment of the target
//                      channel doc. Keeps the doc, its geometry, and
//                      source_pixel_count. Reversible by flipping one boolean,
//                      which is why it is the default: it is the cheapest way
//                      back to a discriminating rig.
//   delete           — delete the channel doc entirely. The channel becomes
//                      "untraced", which the resolver defaults IN. Same end
//                      state for participation; loses the doc.
//
// AFTER RUNNING: full app restart on LAN, not a backgrounding. The phone's
// SharedPreferences cache still holds the old value; the reconciler is
// once-per-PROCESS and needs both deviceChannelsProvider and the roofline to be
// ready before it can notice the cache is stale and clear it.

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';

// Bench defaults — Tyler's account, bench controller, the Leg B channel doc.
const DEFAULTS = {
  uid: 'wrQRUUKyXyc0deyuu0ORS6wsovO2',
  controllerId: '192_168_1_150',
  channel: '1',
};

function parseArgs(argv) {
  const args = {
    ...DEFAULTS,
    keyPath: null,
    commit: false,
    mode: 'flip',
  };
  for (const a of argv.slice(2)) {
    if (a.startsWith('--uid=')) args.uid = a.slice('--uid='.length);
    else if (a.startsWith('--controller=')) args.controllerId = a.slice('--controller='.length);
    else if (a.startsWith('--channel=')) args.channel = a.slice('--channel='.length);
    else if (a.startsWith('--key=')) args.keyPath = a.slice('--key='.length);
    else if (a.startsWith('--mode=')) args.mode = a.slice('--mode='.length);
    else if (a === '--commit') args.commit = true;
    else if (a === '--help' || a === '-h') {
      console.log(
        'Usage: node scripts/_fix_bench_participation.js [--uid=] [--controller=] ' +
          '[--channel=] [--mode=flip|delete] [--key=<path>] [--commit]'
      );
      process.exit(0);
    } else {
      console.error(`Unknown argument: ${a}`);
      process.exit(1);
    }
  }
  if (args.mode !== 'flip' && args.mode !== 'delete') {
    console.error(`--mode must be "flip" or "delete" (got "${args.mode}")`);
    process.exit(1);
  }
  return args;
}

function initFirebase(keyPath) {
  if (keyPath) {
    const creds = require(path.resolve(keyPath));
    admin.initializeApp({
      credential: admin.credential.cert(creds),
      projectId: PROJECT_ID,
    });
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
    });
  } else {
    console.error(
      'No credentials found. Set GOOGLE_APPLICATION_CREDENTIALS or pass --key=<path>.'
    );
    process.exit(1);
  }
}

/// Mirrors resolveParticipatingChannels(explicit: null, ...) exactly.
/// Kept as a projection so the script can state the consequence of the write
/// before making it — this is the whole reason to run it dry first.
function resolveDefaultPolicy(segmentsByChannel, deviceChannelIds) {
  const traced = new Set();
  const primary = new Set();
  for (const [ch, segs] of segmentsByChannel) {
    traced.add(ch);
    if (segs.some((s) => (s.is_primary ?? s.isPrimary ?? true) === true)) primary.add(ch);
  }
  if (traced.size === 0) return [...deviceChannelIds].sort((a, b) => a - b);
  const untraced = deviceChannelIds.filter((id) => !traced.has(id));
  return [...new Set([...primary, ...untraced])].sort((a, b) => a - b);
}

async function readPixelMap(db, uid, controllerId) {
  const snap = await db
    .collection('users').doc(uid)
    .collection('controllers').doc(controllerId)
    .collection('pixelMap')
    .get();
  const byChannel = new Map();
  for (const doc of snap.docs) {
    const d = doc.data();
    const ch = d.channel_index ?? Number(doc.id);
    byChannel.set(ch, d.segments ?? []);
  }
  return { snap, byChannel };
}

async function main() {
  const args = parseArgs(process.argv);
  initFirebase(args.keyPath);
  const db = admin.firestore();

  console.log('════════════════════════════════════════════════════════════════');
  console.log('  Participation re-entry repair — ' + (args.commit ? 'COMMIT' : 'DRY RUN'));
  console.log('════════════════════════════════════════════════════════════════');
  console.log(`  uid:        ${args.uid}`);
  console.log(`  controller: ${args.controllerId}`);
  console.log(`  channel:    ${args.channel}`);
  console.log(`  mode:       ${args.mode}`);
  console.log(`  project:    ${PROJECT_ID}`);
  console.log(`  time:       ${new Date().toISOString()}`);

  // ── 1. The controller doc's published facts (server-read; informational) ──
  const ctrlRef = db
    .collection('users').doc(args.uid)
    .collection('controllers').doc(args.controllerId);
  const ctrlSnap = await ctrlRef.get();
  console.log('\n═══ 1. PUBLISHED FACTS (server-side fires read these) ══════════');
  if (!ctrlSnap.exists) {
    console.log('   controller doc DOES NOT EXIST — check --uid/--controller.');
    process.exit(1);
  }
  const c = ctrlSnap.data();
  for (const f of [
    'participating_channels',
    'participating_channels_device_ids',
    'participating_channels_previous',
    'participating_channels_source',
    'participating_channels_publish_count',
  ]) {
    console.log(`   ${f.padEnd(38)} ${JSON.stringify(c[f] ?? null)}`);
  }
  const at = c.participating_channels_at;
  console.log(`   ${'participating_channels_at'.padEnd(38)} ${at ? at.toDate().toISOString() : 'null'}`);
  console.log('   NOTE: the app UI does NOT read these. The dashboard gate reads');
  console.log('   the SharedPreferences cache on the phone. These are for fires.');

  // ── 2. The roofline input the resolver actually derives from ─────────────
  const { snap, byChannel } = await readPixelMap(db, args.uid, args.controllerId);
  console.log('\n═══ 2. ROOFLINE INPUT — pixelMap docs ══════════════════════════');
  if (snap.empty) {
    console.log('   pixelMap is EMPTY → every device channel participates already.');
    console.log('   Nothing to repair. Exiting.');
    process.exit(0);
  }
  for (const [ch, segs] of [...byChannel.entries()].sort((a, b) => a[0] - b[0])) {
    const prim = segs.filter((s) => (s.is_primary ?? s.isPrimary ?? true) === true).length;
    console.log(`   • channel_index ${ch} — ${segs.length} segment(s), is_primary=true × ${prim}`);
    console.log(`       → default policy: ${prim > 0 ? 'PARTICIPATES' : '*** EXCLUDED ***'}`);
    for (const s of segs) {
      console.log(`       - "${s.name ?? s.id ?? '(unnamed)'}" is_primary=${s.is_primary ?? s.isPrimary ?? true}`);
    }
  }

  // Device shape: prefer the published device ids (device truth at publish
  // time); fall back to the traced channels. Only used for the projection.
  const deviceIds = Array.isArray(c.participating_channels_device_ids)
    ? c.participating_channels_device_ids
    : [...byChannel.keys()];
  const before = resolveDefaultPolicy(byChannel, deviceIds);

  // ── 3. Projection ────────────────────────────────────────────────────────
  const target = Number(args.channel);
  const after = new Map(byChannel);
  if (args.mode === 'delete') {
    after.delete(target);
  } else {
    const segs = (byChannel.get(target) ?? []).map((s) => ({ ...s, is_primary: true }));
    after.set(target, segs);
  }
  const projected = resolveDefaultPolicy(after, deviceIds);

  console.log('\n═══ 3. PROJECTION ══════════════════════════════════════════════');
  console.log(`   device channel ids:      ${JSON.stringify(deviceIds)}`);
  console.log(`   resolver BEFORE:         ${JSON.stringify(before)}`);
  console.log(`   resolver AFTER ${args.mode.padEnd(7)}   ${JSON.stringify(projected)}`);
  if (JSON.stringify(before) === JSON.stringify(projected)) {
    console.log('   ⚠ NO CHANGE — this write would not restore anything. Check --channel.');
  }

  if (!byChannel.has(target) && args.mode === 'flip') {
    console.log(`\n   ✗ channel doc "${args.channel}" does not exist — nothing to flip.`);
    console.log('     A channel with no doc is "untraced" and already defaults IN.');
    process.exit(1);
  }

  // ── 4. Write ─────────────────────────────────────────────────────────────
  const docRef = db
    .collection('users').doc(args.uid)
    .collection('controllers').doc(args.controllerId)
    .collection('pixelMap').doc(args.channel);

  console.log('\n═══ 4. WRITE ═══════════════════════════════════════════════════');
  if (!args.commit) {
    console.log('   DRY RUN — nothing written. Re-run with --commit to apply:');
    if (args.mode === 'delete') {
      console.log(`     DELETE ${docRef.path}`);
    } else {
      const segs = (byChannel.get(target) ?? []).map((s) => ({ ...s, is_primary: true }));
      console.log(`     SET (merge) ${docRef.path}`);
      console.log(`       segments  = ${JSON.stringify(segs, null, 2).split('\n').join('\n       ')}`);
      console.log('       updated_at = <now>');
    }
    process.exit(0);
  }

  if (args.mode === 'delete') {
    await docRef.delete();
    console.log(`   ✓ DELETED ${docRef.path}`);
  } else {
    // Firestore cannot patch an array element in place, so the whole
    // `segments` array is rewritten. merge:true keeps source_pixel_count,
    // map_version, name, photo_path and everything else untouched.
    const segs = (byChannel.get(target) ?? []).map((s) => ({ ...s, is_primary: true }));
    await docRef.set(
      { segments: segs, updated_at: admin.firestore.Timestamp.now() },
      { merge: true }
    );
    console.log(`   ✓ WROTE ${docRef.path} — ${segs.length} segment(s) now is_primary:true`);
  }

  console.log('\n   NEXT: full app restart on LAN with the controller reachable.');
  console.log('   The reconciler runs once per PROCESS and needs deviceChannelsProvider');
  console.log('   + the roofline both ready; it will then see the cached value diverge');
  console.log('   from the recompute and clear it. The next resolve republishes.');
  console.log('   This also un-discriminates the rig\'s roofline leg (BUILD_LEDGER');
  console.log('   §7.2d Leg B) — flip the one boolean back when you need it again.');

  process.exit(0);
}

main().catch((e) => {
  console.error('Repair failed:', e);
  process.exit(2);
});
