// _verify_controller_health.js — S6 bench verification harness.
//
// Exercises the REAL compiled functions (functions/lib/*), not a reimplementation:
//   probeOneController()  from lib/probeControllerHealth
//   collectAll()          from lib/collectControllerHealth
//   classifyProbe()       from lib/controllerHealth
//
// SCOPE: every write is confined to the BENCH account via --uid, and every probe
// is a getInfo — a GET, read-only on the device. It cannot change a light, a
// preset, a timer or a config.
//
// Auth: GOOGLE_APPLICATION_CREDENTIALS or gcloud ADC.
//   node scripts/_verify_controller_health.js --uid <benchUid> [--dead-ip 192.168.1.199]
//
// Requires: cd functions && npm run build   (this loads functions/lib)

const path = require('path');

// MUST resolve the SAME firebase-admin instance that functions/lib/* loads.
// Requiring plain 'firebase-admin' picks up the repo-root copy, which is a
// DIFFERENT @google-cloud/firestore instance — its FieldValue.serverTimestamp()
// sentinel is then unrecognisable to the copy inside functions/, and every write
// fails with "Couldn't serialize object of type ServerTimestampTransform".
const admin = require(
  path.resolve(__dirname, '..', 'functions', 'node_modules', 'firebase-admin')
);

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const args = process.argv.slice(2);
const arg = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : dflt;
};
const UID = arg('--uid', null);
const DEAD_IP = arg('--dead-ip', null);
if (!UID) { console.error('--uid is required (bench account only)'); process.exit(1); }

admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
const db = admin.firestore();

const L = path.resolve(__dirname, '..', 'functions', 'lib');
const { probeOneController } = require(path.join(L, 'probeControllerHealth'));
const { collectAll } = require(path.join(L, 'collectControllerHealth'));
const { classifyProbe, parseWledInfo, PROBE_SOURCE } = require(path.join(L, 'controllerHealth'));

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log(`  PASS  ${label}`); }
  else { fail++; console.log(`  FAIL  ${label}${detail ? ' — ' + detail : ''}`); }
};
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function readPending(uid) {
  const s = await db.collection('users').doc(uid).collection('commands')
    .where('status', 'in', ['pending', 'executing']).get();
  return s.docs.map(d => d.data());
}

/** Poll a command doc until it reaches a terminal status, or time out. */
async function awaitTerminal(ref, timeoutMs = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const d = await ref.get();
    const st = d.exists ? d.get('status') : null;
    if (['completed', 'failed', 'expired', 'timeout'].includes(st)) return d;
    await sleep(2000);
  }
  return await ref.get();
}

(async () => {
  console.log('S6 CONTROLLER HEALTH — bench verification');
  console.log('uid:', UID, '| started', new Date().toISOString(), '\n');

  const ctrls = await db.collection('users').doc(UID).collection('controllers').get();
  console.log('controllers:', ctrls.docs.map(c => `${c.id}@${c.get('ip')}`).join(', '), '\n');
  const c0 = ctrls.docs[0];

  // ── TEST 1 — probe writes, targeting omits the IP ────────────────────────
  console.log('TEST 1 — probe write + targeting');
  const before = await readPending(UID);
  const r1 = await probeOneController({
    db, uid: UID,
    controllerId: c0.id,
    controllerIp: c0.get('ip') || null,
    totalControllersForUser: ctrls.size,
    pendingCommands: before,
    nowMs: Date.now(),
  });
  check('probe written', r1.written === true, JSON.stringify(r1));
  check('targets the server-resolved IP (never the bridge paired fallback)',
    r1.reason === 'server_resolved_ip', r1.reason);

  // locate the doc we just wrote
  const probeSnap = await db.collection('users').doc(UID).collection('commands')
    .where('source', '==', PROBE_SOURCE).get();
  const newest = probeSnap.docs
    .map(d => ({ d, ms: d.get('createdAt')?.toMillis?.() ?? 0 }))
    .sort((a, b) => b.ms - a.ms)[0].d;
  console.log('  probe doc:', newest.id);
  check('deterministic id shape fire_health_<controllerId>_<epoch>',
    /^fire_health_.+_\d+$/.test(newest.id), newest.id);
  check('controllerIp NAMED, and equal to the controllers-subcollection value',
    newest.get('controllerIp') === c0.get('ip'),
    `${newest.get('controllerIp')} vs ${c0.get('ip')}`);
  check('expiresAt set EXPLICITLY', !!newest.get('expiresAt'));
  const graceMs = newest.get('expiresAt').toMillis() - newest.get('createdAt').toMillis();
  check(`expiresAt ≈ createdAt + 90s (got ${Math.round(graceMs / 1000)}s, not the 120s default)`,
    graceMs > 80000 && graceMs < 100000, graceMs + 'ms');

  // ── TEST 2 — one-in-flight guard ─────────────────────────────────────────
  console.log('\nTEST 2 — one-in-flight guard (while the first is still pending)');
  const nowPending = await readPending(UID);
  const r2 = await probeOneController({
    db, uid: UID,
    controllerId: c0.id,
    controllerIp: c0.get('ip') || null,
    totalControllersForUser: ctrls.size,
    pendingCommands: nowPending,
    nowMs: Date.now() + 1000,
  });
  const guardFired = r2.written === false && r2.reason === 'in_flight';
  check('second probe refused with reason=in_flight', guardFired,
    `written=${r2.written} reason=${r2.reason} (pending seen: ${nowPending.length})`);
  if (!guardFired && nowPending.length === 0) {
    console.log('    NOTE: the bridge completed the first probe before this read — ' +
      'the queue was genuinely empty, so the guard had nothing to block. ' +
      'Re-run for a tighter race, or rely on the unit tests for the predicate.');
  }

  // ── TEST 3 — the probe completes and carries a real /json/info body ───────
  console.log('\nTEST 3 — end-to-end delivery');
  const done = await awaitTerminal(newest.ref);
  const cls = classifyProbe({
    status: done.get('status'), result: done.get('result'), error: done.get('error'),
    createdAt: done.get('createdAt'), completedAt: done.get('completedAt'),
  });
  console.log('  status:', done.get('status'), '| latencyMs:', cls.latencyMs);
  check('outcome=completed', cls.outcome === 'completed', done.get('status'));
  check('blame=none', cls.blame === 'none');
  const info = parseWledInfo(done.get('result'));
  console.log('  parsed info:', JSON.stringify(info));
  check('wledVersion parsed from the live controller', !!info.wledVersion, String(info.wledVersion));
  check('wledVid parsed', typeof info.wledVid === 'number', String(info.wledVid));
  check('latency measured', typeof cls.latencyMs === 'number', String(cls.latencyMs));

  // ── TEST 4 — collector writes the health document ────────────────────────
  console.log('\nTEST 4 — collectAll writes controller_health');
  const res = await collectAll(db, Date.now(), { seedOnly: false, dryRun: false, onlyUid: UID });
  console.log('  stats:', JSON.stringify(res.stats));
  const hs = await db.collection('users').doc(UID)
    .collection('controller_health').doc(c0.id).get();
  check('health doc exists', hs.exists);
  if (hs.exists) {
    const h = hs.data();
    console.log('  health:', JSON.stringify({
      lastProbeOutcome: h.lastProbeOutcome, lastProbeBlame: h.lastProbeBlame,
      consecutiveFailures: h.consecutiveFailures, probeLatencyMs: h.probeLatencyMs,
      wledVersion: h.wledVersion, wledVid: h.wledVid, ledCount: h.ledCount, rgbw: h.rgbw,
      bridgeDeviceId: h.bridgeDeviceId, bridgeStatus: h.bridgeStatus,
      probeTargeting: h.probeTargeting,
    }, null, 2).replace(/\n/g, '\n  '));
    check('lastProbeOutcome=completed', h.lastProbeOutcome === 'completed');
    check('consecutiveFailures reset to 0', h.consecutiveFailures === 0);
    check('wledVersion recorded', !!h.wledVersion);
    check('bridge facts recorded', !!h.bridgeDeviceId && !!h.bridgeStatus);
    check('cn NOT recorded anywhere in the health doc',
      !JSON.stringify(h).includes('Kōsen') && !('cn' in h));
  }

  // ── TEST 5 — forced controller-unreachable → failed, blame=controller ─────
  if (DEAD_IP) {
    console.log(`\nTEST 5 — forced failure against unreachable ${DEAD_IP}`);
    const badId = `fire_health_VERIFY_DEADIP_${Math.floor(Date.now() / 1000)}`;
    const badRef = db.collection('users').doc(UID).collection('commands').doc(badId);
    await badRef.create({
      type: 'getInfo', payload: '{}', controllerId: c0.id, controllerIp: DEAD_IP,
      status: 'pending', createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 90000),
      source: 'health_probe_verify', webhookUrl: null,
    });
    const badDone = await awaitTerminal(badRef, 90000);
    const badCls = classifyProbe({
      status: badDone.get('status'), error: badDone.get('error'),
      createdAt: badDone.get('createdAt'), completedAt: badDone.get('completedAt'),
    });
    console.log('  status:', badDone.get('status'), '| error:', badDone.get('error'));
    check('outcome=failed (NOT expired)', badCls.outcome === 'failed', badDone.get('status'));
    check('blame=controller (bridge was alive and picked it up)',
      badCls.blame === 'controller', badCls.blame);
    check('failed is distinguishable from expired',
      badCls.blame !== classifyProbe({ status: 'expired' }).blame);
    // Remove it — source is deliberately NOT health_probe so the real collector
    // would ignore it anyway, but leave nothing behind.
    await badRef.delete();
    console.log('  cleaned up', badId);
  } else {
    console.log('\nTEST 5 — skipped (no --dead-ip supplied)');
  }

  // ── TEST 6 — expired classification against REAL production data ─────────
  console.log('\nTEST 6 — expired vs failed against real production documents');
  // Scoped to one account rather than a collectionGroup query: a bare
  // collection-group equality on `status` needs a COLLECTION_GROUP_ASC
  // single-field index that does not exist (only the sweeper's
  // (status, createdAt) composite does), and this harness must not require
  // an index deploy to run.
  const grp = await db.collection('users').doc('r0iBwg8byeTqmROJgob8RK72DZm2')
    .collection('commands').where('status', '==', 'expired').limit(1).get();
  if (grp.empty) {
    console.log('  no expired command in the fleet right now — skipped');
  } else {
    const d = grp.docs[0];
    const c = classifyProbe({ status: d.get('status'), error: d.get('error') });
    console.log('  sample:', d.ref.path.split('/').slice(0, 2).join('/'), '| error:',
      String(d.get('error')).slice(0, 60));
    check('real expired doc → blame=bridge', c.blame === 'bridge', c.blame);
    check('real expired doc → not a success', c.success === false);
  }

  console.log(`\n${'='.repeat(56)}\nRESULT: ${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
