// _verify_fire_dispatcher.js — S3 bench verification harness.
//
// Drives the REAL compiled dispatcher (functions/lib/dispatchFireJobs.runDispatchTick),
// not a reimplementation. Every read and write is scoped to the bench account via
// --uid, and every job uses type "ping" — which the bridge acknowledges LOCALLY
// with no WLED request, so nothing touches the lights.
//
//   node scripts/_verify_fire_dispatcher.js --uid <benchUid>
//
// Requires: cd functions && npm run build

const path = require('path');
// Same firebase-admin instance the compiled functions load — see the note in
// _verify_controller_health.js. The repo-root copy is a DIFFERENT
// @google-cloud/firestore whose serverTimestamp() sentinel this one rejects.
const admin = require(path.resolve(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };
const UID = arg('--uid', null);
if (!UID) { console.error('--uid is required (bench account only)'); process.exit(1); }

admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
const db = admin.firestore();

const L = path.resolve(__dirname, '..', 'functions', 'lib');
const { runDispatchTick } = require(path.join(L, 'dispatchFireJobs'));
const { MAX_FIRE_LATENESS_MS, FIRE_GRACE_MS } = require(path.join(L, 'fireJobs'));

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log(`  PASS  ${label}`); }
  else { fail++; console.log(`  FAIL  ${label}${detail ? ' — ' + detail : ''}`); }
};
const sleep = ms => new Promise(r => setTimeout(r, ms));
const jobsRef = () => db.collection('users').doc(UID).collection('fire_jobs');
const created = [];

async function mkJob(id, fireAtMs, over = {}) {
  const ref = jobsRef().doc(id);
  await ref.set({
    eventId: 'BENCH_VERIFY',
    seq: id,
    controllerId: null,           // filled by caller
    fireAt: admin.firestore.Timestamp.fromMillis(fireAtMs),
    payload: '{}',
    type: 'ping',
    state: 'scheduled',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...over,
  });
  created.push(ref);
  return ref;
}

const tick = (nowMs) =>
  runDispatchTick(db, nowMs ?? Date.now(), { onlyUid: UID, metricsSuffix: '_bench' });

(async () => {
  console.log('S3 FIRE-JOB DISPATCHER — bench verification');
  console.log('uid:', UID, '| started', new Date().toISOString(), '\n');

  const ctrls = await db.collection('users').doc(UID).collection('controllers').get();
  const c0 = ctrls.docs[0];
  const CID = c0.id, CIP = c0.get('ip');
  console.log('controller:', CID, '@', CIP, '\n');

  // ── TEST 1 — a due job fires ────────────────────────────────────────────
  console.log('TEST 1 — a job fires at its fireAt');
  const t0 = Date.now();
  const j1 = await mkJob('bench_fire_1', t0, { controllerId: CID });
  const s1 = await tick(t0);
  check('dispatched exactly 1', s1.dispatched === 1, JSON.stringify(s1));
  const j1d = await j1.get();
  check('job state → dispatched', j1d.get('state') === 'dispatched', j1d.get('state'));
  const cmdId = j1d.get('commandId');
  console.log('  commandId:', cmdId, '| writeHopMs:', j1d.get('writeHopMs'),
    '| latenessMs:', j1d.get('dispatchLatenessMs'));
  check('deterministic id shape', /^fire_bench_fire_1_\d+$/.test(String(cmdId)), String(cmdId));

  const cmdRef = db.collection('users').doc(UID).collection('commands').doc(cmdId);
  const cmd = await cmdRef.get();
  check('command exists', cmd.exists);
  check('controllerIp NAMED = controllers-subcollection value',
    cmd.get('controllerIp') === CIP, `${cmd.get('controllerIp')} vs ${CIP}`);
  check('source = fire_job', cmd.get('source') === 'fire_job', cmd.get('source'));
  const graceMs = cmd.get('expiresAt').toMillis() - cmd.get('createdAt').toMillis();
  check(`expiresAt EXPLICIT ≈ dispatch + ${FIRE_GRACE_MS / 1000}s (got ${Math.round(graceMs / 1000)}s)`,
    graceMs > FIRE_GRACE_MS - 15000 && graceMs < FIRE_GRACE_MS + 15000, graceMs + 'ms');
  check('ADMIN-SDK WRITE HOP measured (V2 UNVERIFIED #13)',
    typeof j1d.get('writeHopMs') === 'number', String(j1d.get('writeHopMs')));

  // Let the first command reach a terminal status so the guard is not the thing
  // under test in TEST 2 — the two defences are independent and must be
  // isolated, or the guard silently masks the idempotency barrier.
  console.log('\n  (waiting for the first command to go terminal…)');
  for (let i = 0; i < 20; i++) {
    const st = (await cmdRef.get()).get('status');
    if (['completed', 'failed', 'expired'].includes(st)) break;
    await sleep(2000);
  }
  console.log('  first command status:', (await cmdRef.get()).get('status'));

  // ── TEST 2 — retried dispatch does not double-write ─────────────────────
  console.log('\nTEST 2 — retried dispatch cannot double-fire (the .create() barrier)');
  // Force the job back to `scheduled` with the SAME fireAt, exactly as a retried
  // invocation of a crashed tick would see it. The queue is now clear, so the
  // guard cannot be what stops the second write — only the deterministic id can.
  await j1.update({ state: 'scheduled' });
  const beforeCount = (await db.collection('users').doc(UID).collection('commands')
    .where('source', '==', 'fire_job').get()).size;
  const s2 = await tick(t0 + 1000);
  const afterCount = (await db.collection('users').doc(UID).collection('commands')
    .where('source', '==', 'fire_job').get()).size;
  const j1r = await j1.get();
  console.log('  fire_job commands before/after retry:', beforeCount, '/', afterCount,
    '| guard blocks this tick:', JSON.stringify(s2.skippedTransient));
  check('NO second command document written', afterCount === beforeCount,
    `${beforeCount} → ${afterCount}`);
  check('the guard was NOT what stopped it (queue was clear)',
    !(s2.skippedTransient || {}).in_flight, JSON.stringify(s2.skippedTransient));
  check('retry still marks the job dispatched', j1r.get('state') === 'dispatched',
    j1r.get('state'));
  check('commandId unchanged by the retry', j1r.get('commandId') === cmdId,
    `${j1r.get('commandId')} vs ${cmdId}`);

  // ── TEST 3 — one-in-flight guard, same tick, deterministic ──────────────
  console.log('\nTEST 3 — the guard blocks a competing job for the same controller');
  // Two jobs, same controller, both due, ONE tick. Exactly one may dispatch.
  // This does not race the bridge: the block comes from the in-tick pending
  // list, so the result is deterministic.
  const now3 = Date.now();
  const jA = await mkJob('bench_guard_a', now3, { controllerId: CID });
  const jB = await mkJob('bench_guard_b', now3, { controllerId: CID });
  const s3 = await tick(now3);
  const [jAd, jBd] = [await jA.get(), await jB.get()];
  const states = [jAd.get('state'), jBd.get('state')].sort();
  console.log('  states:', JSON.stringify(states), '| skips:', JSON.stringify(s3.skippedTransient));
  check('exactly ONE of the two dispatched',
    states.join(',') === 'dispatched,scheduled', states.join(','));
  check('the blocked one has NO commandId',
    (jAd.get('state') === 'scheduled' ? jAd : jBd).get('commandId') === undefined,
    String((jAd.get('state') === 'scheduled' ? jAd : jBd).get('commandId')));
  check('blocked TRANSIENTLY — still `scheduled` for the next tick',
    states.includes('scheduled'));
  check('guard block counted', (s3.skippedTransient || {}).in_flight >= 1,
    JSON.stringify(s3.skippedTransient));

  // ── TEST 4 — a too-late job is never picked up ──────────────────────────
  console.log('\nTEST 4 — a job past the lateness bound never produces a command');
  const staleAt = Date.now() - MAX_FIRE_LATENESS_MS - 60_000;
  const j3 = await mkJob('bench_fire_stale', staleAt, { controllerId: CID });
  await tick();
  const j3d = await j3.get();
  check('stale job terminalized as skipped', j3d.get('state') === 'skipped', j3d.get('state'));
  check('skipReason = too_late', String(j3d.get('skipReason')).startsWith('too_late'),
    String(j3d.get('skipReason')));
  // Assert against THIS job, not a fleet-wide count — other jobs legitimately
  // dispatch on the same tick and would mask the result.
  check('the stale job has NO commandId', j3d.get('commandId') === undefined,
    String(j3d.get('commandId')));
  const staleCmd = await db.collection('users').doc(UID).collection('commands')
    .doc(`fire_bench_fire_stale_${Math.floor(staleAt / 1000)}`).get();
  check('no command document exists at the stale job\'s deterministic id',
    !staleCmd.exists);

  // ── TEST 5 — an unsafe payload is refused (the §4.2 constraint) ─────────
  console.log('\nTEST 5 — a state-mutating payload is refused, not fired');
  const j4 = await mkJob('bench_fire_unsafe', Date.now(), {
    controllerId: CID, type: 'applyJson', payload: JSON.stringify({ psave: 9, on: true }),
  });
  await tick();
  const j4d = await j4.get();
  check('psave job terminalized as skipped', j4d.get('state') === 'skipped', j4d.get('state'));
  check('skipReason names the forbidden key',
    String(j4d.get('skipReason')).includes('psave'), String(j4d.get('skipReason')));

  // ── TEST 6 — reconcile records the outcome and the latency ──────────────
  console.log('\nTEST 6 — reconcile records outcome + end-to-end latency');
  // Use a FRESH job so this tick is the one that reconciles it. Asserting on an
  // earlier job would race the reconcile that already happened on a prior tick.
  const jR = await mkJob('bench_reconcile', Date.now(), { controllerId: CID });
  // Tick until it actually dispatches. Earlier tests leave jobs contending for
  // the same controller, and the guard blocks TRANSIENTLY by design — so a
  // single tick is not guaranteed to dispatch. Looping is what the real
  // minute cron does, and exercising it here proves the retry path works.
  let jRd0 = null, ticks = 0;
  for (; ticks < 6; ticks++) {
    await tick();
    jRd0 = await jR.get();
    if (typeof jRd0.get('commandId') === 'string') break;
    await sleep(1500);
  }
  check('a transiently-blocked job eventually dispatches on a later tick',
    typeof jRd0.get('commandId') === 'string', `still ${jRd0.get('state')} after ${ticks + 1} ticks`);
  const rCmdRef = db.collection('users').doc(UID).collection('commands')
    .doc(String(jRd0.get('commandId')));
  console.log('  dispatched as', jRd0.get('commandId'), 'after', ticks + 1, 'tick(s)');
  for (let i = 0; i < 25; i++) {
    const st = (await rCmdRef.get()).get('status');
    if (['completed', 'failed', 'expired'].includes(st)) break;
    await sleep(2000);
  }
  console.log('  command status:', (await rCmdRef.get()).get('status'));
  const s6 = await tick();
  const jRf = await jR.get();
  console.log('  job state:', jRf.get('state'), '| latencyMs:', jRf.get('latencyMs'));
  check('reconcile counted on THIS tick', s6.reconciled >= 1, JSON.stringify({
    reconciled: s6.reconciled, completed: s6.completed,
  }));
  check('job reconciled to a terminal state',
    ['completed', 'failed', 'expired'].includes(jRf.get('state')), jRf.get('state'));
  check('end-to-end latency recorded',
    typeof jRf.get('latencyMs') === 'number', String(jRf.get('latencyMs')));

  // ── TEST 7 — metrics doc ────────────────────────────────────────────────
  console.log('\nTEST 7 — shadow-run metrics');
  const dayKey = new Date().toISOString().slice(0, 10) + '_bench';
  const m = await db.collection('fire_metrics').doc(dayKey).get();
  check('metrics doc written', m.exists);
  if (m.exists) {
    console.log('  ', JSON.stringify({
      ticks: m.get('ticks'), dispatched: m.get('dispatched'), completed: m.get('completed'),
      inFlightBlocks: m.get('inFlightBlocks'), tooLate: m.get('tooLate'), unsafe: m.get('unsafe'),
      e2e: m.get('e2e'), writeHop: m.get('writeHop'),
    }));
    check('write-hop percentiles present (the never-measured hop)',
      m.get('writeHop') && typeof m.get('writeHop').p50 === 'number',
      JSON.stringify(m.get('writeHop')));
  }

  // ── CLEANUP ─────────────────────────────────────────────────────────────
  console.log('\nCLEANUP');
  for (const ref of created) { await ref.delete(); }
  console.log('  deleted', created.length, 'bench fire_jobs');
  console.log('  NOTE: the ping command documents are left for the 7-day retention sweep,');
  console.log('        and fire_metrics/' + dayKey + ' is kept as the bench record.');

  console.log(`\n${'='.repeat(56)}\nRESULT: ${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(async e => {
  console.error('FATAL', e);
  for (const ref of created) { try { await ref.delete(); } catch (_) { } }
  process.exit(1);
});
