// Game Day PRE-FLIGHT dry run. READ-ONLY: every call is a plain .get().
//
//   node scripts/_gameday_preflight_dryrun.js <uid> [<uid> ...]
//
// Evaluates plan step B1's pre-flight (P1–P5, P7; P6 needs a live probe and is
// reported from the stored session verdicts only) for each uid against
// PRODUCTION data, using the SAME compiled evaluator the planner runs
// (functions/lib/gameDayPreflight.js + gameDayGate.js). Use it:
//   - before deploying steps A+B: the bench account must come back `ok` or the
//     first tick after the deploy withholds its next start (enforce mode);
//   - before plan step D: pick the friendly accounts that pass.
//
// Run from the repo root after `npm --prefix functions run build`. Credentials
// come from ADC (gcloud auth application-default login). Writes nothing.
// Prints uids you passed in; it never lists accounts on its own.
//
// P4b (#146, fix/gameday-espn-slate): the ladder-lights check follows
// config/gameday_planner.preflight_ladder_lit exactly as the planner reads it.
// LADDER_LIT=on|strict|off overrides it, to preview a mode BEFORE flipping it:
//   LADDER_LIT=on node scripts/_gameday_preflight_dryrun.js <uid>

const path = require('path');
const fn = path.join(__dirname, '..', 'functions');
const admin = require(path.join(fn, 'node_modules', 'firebase-admin'));
const { evaluatePreflight, p6HoldsAccount, ladderLitModeFrom, ladderDarkChannels } =
  require(path.join(fn, 'lib', 'gameDayPreflight'));
const { evaluateAccountReadiness } = require(path.join(fn, 'lib', 'gameDayGate'));

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'icrt6menwsv2d8all8oijs021b06s5',
});
const db = admin.firestore();

async function ladderLitMode() {
  const forced = process.env.LADDER_LIT;
  if (forced === 'on' || forced === 'strict' || forced === 'off') return { mode: forced, source: 'env' };
  const cfg = await db.collection('config').doc('gameday_planner').get();
  return { mode: ladderLitModeFrom(cfg.exists ? cfg.data() : undefined), source: 'config' };
}

async function dryRun(uid, nowMs, lit) {
  const user = await db.collection('users').doc(uid).get();
  if (!user.exists) return { uid, error: 'no user doc' };
  const controllers = await db.collection('users').doc(uid).collection('controllers').get();
  const controller = controllers.docs[0] ? controllers.docs[0].data() : null;
  const gate = evaluateAccountReadiness({
    hasParticipationFacts:
      !!controller &&
      Array.isArray(controller.participating_channels_device_ids) &&
      controller.participating_channels_device_ids.length > 0,
    ladderAssertsSegments:
      controller && typeof controller.base_ladder_asserts_segments === 'boolean'
        ? controller.base_ladder_asserts_segments
        : null,
  });
  const reg = await db.collection('bridge_registry').where('pairedUid', '==', uid).limit(1).get();
  const bs = await db.collection('users').doc(uid).collection('bridge_status').doc('current').get();
  const recent = await db.collection('users').doc(uid).collection('debug_errors')
    .orderBy('timestamp', 'desc').limit(25).get();
  const appDoc = recent.docs.find((d) => d.get('context') === 'routing_decisions');
  const sessions = await db.collection('users').doc(uid).collection('game_day_sessions').get();
  const verdict = evaluatePreflight({
    bridgePaired: !reg.empty,
    bridgeStatusUpdateMs: bs.exists && bs.updateTime ? bs.updateTime.toMillis() : null,
    controller,
    gate,
    p6Unreachable: sessions.docs.some((s) => p6HoldsAccount(s.data(), nowMs)),
    appVersion: appDoc ? appDoc.get('app_version') : null,
    nowMs,
    ladderLit: lit.mode,
  });
  return {
    uid,
    ok: verdict.ok,
    reasons: verdict.reasons,
    info: verdict.info,
    facts: {
      controllers: controllers.size,
      gate: gate.blocking.length ? gate.blocking : 'armed',
      heartbeatAgeS: bs.exists && bs.updateTime ? Math.round((nowMs - bs.updateTime.toMillis()) / 1000) : null,
      ladder: controller ? controller.base_ladder_asserts_segments : undefined,
      ladderLitMode: `${lit.mode} (${lit.source})`,
      ladderRestoreLit: controller ? controller.base_ladder_restore_lit : undefined,
      ladderDarkChannels: ladderDarkChannels(controller),
      participation: controller ? controller.participating_channels : undefined,
      appVersion: appDoc ? appDoc.get('app_version') : null,
    },
  };
}

(async () => {
  const uids = process.argv.slice(2);
  if (uids.length === 0) {
    console.error('usage: node scripts/_gameday_preflight_dryrun.js <uid> [<uid> ...]');
    process.exit(2);
  }
  const nowMs = Date.now();
  const lit = await ladderLitMode();
  for (const uid of uids) {
    const r = await dryRun(uid, nowMs, lit);
    console.log(JSON.stringify(r));
  }
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
