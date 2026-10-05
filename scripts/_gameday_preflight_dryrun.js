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
// config/gameday_planner.preflight_ladder_lit exactly as the planner reads it,
// per uid (true, "strict", or a uid list that names the account — #157).
// LADDER_LIT=on|strict|off overrides it, to preview a mode BEFORE flipping it:
//   LADDER_LIT=on node scripts/_gameday_preflight_dryrun.js <uid>
//
// The bridge write gap (2026-10-05): P2's window follows
// config/gameday_planner.preflight_bridge_grace per uid (5 min, or 15 min when
// on); BRIDGE_GRACE=on|off overrides it. `served_sticky` is reported with what
// the planner would PUBLISH for the account on a tick taken right now, from
// the stored gameday_server (decideServedSticky). SERVED_STICKY=on|off
// overrides it. Neither changes the verdict's reasons.

const path = require('path');
const fn = path.join(__dirname, '..', 'functions');
const admin = require(path.join(fn, 'node_modules', 'firebase-admin'));
const {
  evaluatePreflight, p6HoldsAccount, ladderLitModeFrom, ladderDarkChannels,
  bridgeGraceScopeFrom, bridgeStaleMsFor, servedStickyScopeFrom, decideServedSticky,
} = require(path.join(fn, 'lib', 'gameDayPreflight'));
const { flagOnFor } = require(path.join(fn, 'lib', 'gameDayPlanning'));
const { evaluateAccountReadiness } = require(path.join(fn, 'lib', 'gameDayGate'));

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'icrt6menwsv2d8all8oijs021b06s5',
});
const db = admin.firestore();

const onOff = (v) => (v === 'on' ? true : v === 'off' ? false : null);

/** One read of config/gameday_planner; each flag as the planner resolves it per uid. */
async function flagResolver() {
  const cfg = await db.collection('config').doc('gameday_planner').get();
  const data = cfg.exists ? cfg.data() : undefined;
  const forcedLit = process.env.LADDER_LIT;
  const forcedGrace = onOff(process.env.BRIDGE_GRACE);
  const forcedSticky = onOff(process.env.SERVED_STICKY);
  return (uid) => ({
    lit:
      forcedLit === 'on' || forcedLit === 'strict' || forcedLit === 'off'
        ? { mode: forcedLit, source: 'env' }
        : { mode: ladderLitModeFrom(data, uid), source: 'config' },
    grace:
      forcedGrace !== null
        ? { on: forcedGrace, source: 'env' }
        : { on: flagOnFor(bridgeGraceScopeFrom(data), uid), source: 'config' },
    sticky:
      forcedSticky !== null
        ? { on: forcedSticky, source: 'env' }
        : { on: flagOnFor(servedStickyScopeFrom(data), uid), source: 'config' },
    enforce: !data || data.preflight_mode !== 'observe',
  });
}

async function dryRun(uid, nowMs, flagsFor) {
  const { lit, grace, sticky, enforce } = flagsFor(uid);
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
  const bridgeStaleMs = bridgeStaleMsFor(grace.on);
  const verdict = evaluatePreflight({
    bridgePaired: !reg.empty,
    bridgeStatusUpdateMs: bs.exists && bs.updateTime ? bs.updateTime.toMillis() : null,
    controller,
    gate,
    p6Unreachable: sessions.docs.some((s) => p6HoldsAccount(s.data(), nowMs)),
    appVersion: appDoc ? appDoc.get('app_version') : null,
    nowMs,
    ladderLit: lit.mode,
    bridgeStaleMs,
  });
  // What a planner tick taken now would publish as `served`, for an account
  // the allowlist and the gate arm. Read-only: nothing is stored.
  const stored = user.get('gameday_server');
  const hold = decideServedSticky({
    stickyOn: sticky.on,
    preflight: verdict,
    startsWithheld: enforce && !verdict.ok,
    stored,
    nowMs,
  });
  const storedSince = stored && stored.stale_since && typeof stored.stale_since.toMillis === 'function'
    ? stored.stale_since.toMillis()
    : null;
  return {
    uid,
    ok: verdict.ok,
    reasons: verdict.reasons,
    info: verdict.info,
    facts: {
      controllers: controllers.size,
      gate: gate.blocking.length ? gate.blocking : 'armed',
      heartbeatAgeS: bs.exists && bs.updateTime ? Math.round((nowMs - bs.updateTime.toMillis()) / 1000) : null,
      bridgeStaleWindowS: `${bridgeStaleMs / 1000} (grace ${grace.on ? 'on' : 'off'}, ${grace.source})`,
      ladder: controller ? controller.base_ladder_asserts_segments : undefined,
      ladderLitMode: `${lit.mode} (${lit.source})`,
      ladderRestoreLit: controller ? controller.base_ladder_restore_lit : undefined,
      ladderDarkChannels: ladderDarkChannels(controller),
      participation: controller ? controller.participating_channels : undefined,
      appVersion: appDoc ? appDoc.get('app_version') : null,
    },
    served: {
      sticky: `${sticky.on ? 'on' : 'off'} (${sticky.source})`,
      storedServed: stored ? stored.served === true : null,
      storedStaleSince: storedSince !== null ? new Date(storedSince).toISOString() : null,
      wouldPublish: verdict.ok || !enforce ? true : hold.hold,
      held: hold.hold,
      holdExpired: hold.expired,
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
  const flagsFor = await flagResolver();
  for (const uid of uids) {
    const r = await dryRun(uid, nowMs, flagsFor);
    console.log(JSON.stringify(r));
  }
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
