// _test_rules_diff.js
//
// DIFFERENTIAL Security Rules regression for the S1 commands change
// (audit/COMMAND_SAFETY.md).
//
// WHY DIFFERENTIAL: the emulator rules suite (functions/test/emulator/**, ~170
// cases) cannot run on this machine — firebase-tools 15.x requires JDK 21 and
// this box has 17. Rather than claim a regression that did not run, this does
// something stronger for a rules edit: it evaluates the SAME broad request set
// against `git show HEAD:firestore.rules` and against the working-tree rules,
// then asserts the ONLY behavioural differences are on /commands paths.
//
// That needs no knowledge of each rule's intent — it proves the blast radius
// directly. A rules edit that accidentally widened or narrowed an unrelated
// match block shows up as a diff on a path it has no business touching.
//
// Read-only. Does NOT deploy. Every get()/exists() is satisfied by an explicit
// functionMock so results depend only on the rules text.
//
// Usage: node scripts/_test_rules_diff.js
// Gitignored / untracked — diag script convention.

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const REPO = path.resolve(__dirname, '..');
const RULES_PATH = path.join(REPO, 'firestore.rules');

const UID = 'u_owner';
const OTHER = 'u_other';
const D = '/databases/(default)/documents';
const USER_DOC = `${D}/users/${UID}`;

const owner = { uid: UID, token: { email: 'owner@example.com' } };
const stranger = { uid: OTHER, token: { email: 'other@example.com' } };
const bridge = { uid: 'bridge_uid', token: { email: 'bridge@lumina.local' } };
const installer = {
  uid: 'staff_installer_0101',
  token: { role: 'installer', dealerCode: '01' },
};

// One mock set reused everywhere: the owner's user doc, with a controller
// allowlist and the bridge email the bridge branch matches on.
const MOCKS = [
  { function: 'exists', args: [{ exactValue: USER_DOC }], result: { value: true } },
  {
    function: 'get',
    args: [{ exactValue: USER_DOC }],
    result: {
      value: {
        data: {
          controller_ips: ['192.168.1.150'],
          bridge_email: 'bridge@lumina.local',
          dealer_code: '01',
          user_role: 'customer',
        },
      },
    },
  },
];

const doc = (p) => `${D}${p}`;
const c = (label, auth, p, method, data) => ({
  label,
  request: {
    ...(auth ? { auth } : {}),
    path: doc(p),
    method,
    ...(data ? { resource: { data } } : {}),
  },
});

// Broad sweep across the ruleset. Expectations are deliberately NOT asserted —
// only the OLD-vs-NEW delta matters here.
const cases = [
  // ── /commands — the paths this change is allowed to move ──────────
  c('commands: owner create, registered ip', owner, `/users/${UID}/commands/x`, 'create',
    { type: 'applyJson', controllerIp: '192.168.1.150', status: 'pending' }),
  c('commands: owner create, UNREGISTERED ip', owner, `/users/${UID}/commands/x`, 'create',
    { type: 'applyJson', controllerIp: '192.168.1.1', status: 'pending' }),
  c('commands: owner create, no ip', owner, `/users/${UID}/commands/x`, 'create',
    { type: 'ping', status: 'pending' }),
  c('commands: owner update, UNREGISTERED ip', owner, `/users/${UID}/commands/x`, 'update',
    { type: 'ping', controllerIp: '192.168.1.1', status: 'pending' }),
  c('commands: bridge update status', bridge, `/users/${UID}/commands/x`, 'update',
    { status: 'completed' }),
  c('commands: owner read', owner, `/users/${UID}/commands/x`, 'get'),
  c('commands: owner delete', owner, `/users/${UID}/commands/x`, 'delete'),
  c('commands: stranger create', stranger, `/users/${UID}/commands/x`, 'create',
    { type: 'ping', controllerIp: '192.168.1.150', status: 'pending' }),
  c('commands: unauth create', null, `/users/${UID}/commands/x`, 'create',
    { type: 'ping', status: 'pending' }),

  // ── Everything below MUST be identical old vs new ─────────────────
  c('user doc: owner read', owner, `/users/${UID}`, 'get'),
  c('user doc: stranger read', stranger, `/users/${UID}`, 'get'),
  c('user doc: owner update', owner, `/users/${UID}`, 'update', { name: 'x' }),
  c('controllers: owner create', owner, `/users/${UID}/controllers/c1`, 'create',
    { ip: '192.168.1.150' }),
  c('controllers: stranger create', stranger, `/users/${UID}/controllers/c1`, 'create',
    { ip: '10.0.0.1' }),
  c('controllers: owner read', owner, `/users/${UID}/controllers/c1`, 'get'),
  c('controllers: owner delete', owner, `/users/${UID}/controllers/c1`, 'delete'),
  c('pixelMap: owner read', owner, `/users/${UID}/controllers/c1/pixelMap/ch0`, 'get'),
  c('pixelMap: stranger read', stranger, `/users/${UID}/controllers/c1/pixelMap/ch0`, 'get'),
  c('pixelMap: installer write', installer, `/users/${UID}/controllers/c1/pixelMap/ch0`, 'create',
    { pixels: 10 }),
  c('schedules: owner create', owner, `/users/${UID}/schedules/s1`, 'create', { id: 's1' }),
  c('schedules: stranger read', stranger, `/users/${UID}/schedules/s1`, 'get'),
  c('bridge_status: bridge write', bridge, `/users/${UID}/bridge_status/current`, 'create',
    { online: true }),
  c('bridge_status: owner read', owner, `/users/${UID}/bridge_status/current`, 'get'),
  c('bridge_status: stranger read', stranger, `/users/${UID}/bridge_status/current`, 'get'),
  c('geofences: owner create', owner, `/users/${UID}/geofences/g1`, 'create', { r: 100 }),
  c('properties: owner create', owner, `/users/${UID}/properties/p1`, 'create', { name: 'home' }),
  c('game_day_autopilot: owner write', owner, `/users/${UID}/game_day_autopilot/cfg`, 'create',
    { teamSlug: 'royals' }),
  c('ephemeral_game_sessions: owner write', owner, `/users/${UID}/ephemeral_game_sessions/s`, 'create',
    { phase: 'live' }),
  c('brand_profile: owner read', owner, `/users/${UID}/brand_profile/main`, 'get'),
  c('commercial_events: owner create', owner, `/users/${UID}/commercial_events/e1`, 'create',
    { name: 'x' }),
  c('commercial_locations: owner read', owner, `/users/${UID}/commercial_locations/l1`, 'get'),
  c('referrals: owner read', owner, `/users/${UID}/referrals/r1`, 'get'),
  c('ai_usage: owner read', owner, `/users/${UID}/ai_usage/u1`, 'get'),
  c('roofline_config: owner write', owner, `/users/${UID}/roofline_config/cfg`, 'create', { v: 1 }),
  c('bridge_registry: bridge update', bridge, '/bridge_registry/AABBCC', 'update',
    { pairedUid: UID, deviceId: 'AABBCC' }),
  c('bridge_registry: stranger read', stranger, '/bridge_registry/AABBCC', 'get'),
  c('favorites: owner create', owner, `/users/${UID}/favorites/f1`, 'create', { patternId: 'p' }),
  c('designs: owner create', owner, `/users/${UID}/designs/d1`, 'create', { name: 'd' }),
  c('patterns: owner read', owner, `/users/${UID}/patterns/p1`, 'get'),
  c('suggestions: owner read', owner, `/users/${UID}/suggestions/s1`, 'get'),
  c('installers: stranger read', stranger, '/installers/i1', 'get'),
  c('installations: owner read', owner, '/installations/inst1', 'get'),
  c('invitations: owner read', owner, '/invitations/inv1', 'get'),
  c('dealers: stranger read', stranger, '/dealers/01', 'get'),
  c('app_config master pin: owner read', owner, '/app_config/master_sales_pin', 'get'),
  c('app_config announcements: owner read', owner, '/app_config/announcements', 'get'),
  c('referral_codes: owner read', owner, '/referral_codes/ABC123', 'get'),
  c('referral_payouts: owner read', owner, '/referral_payouts/p1', 'get'),
  c('demo_leads: unauth create', null, '/demo_leads/l1', 'create', { email: 'a@b.c' }),
  c('email_notifications: owner create', owner, '/email_notifications/n1', 'create', { to: 'x' }),
  c('debug_errors: owner create', owner, `/users/${UID}/debug_errors/e1`, 'create', { msg: 'x' }),
  c('sites: owner read', owner, '/sites/s1', 'get'),
  c('devices: owner read', owner, '/devices/d1', 'get'),
];

function getToken() {
  return execSync('gcloud auth application-default print-access-token', {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

async function evaluate(token, rulesContent, label) {
  const body = {
    source: { files: [{ name: 'firestore.rules', content: rulesContent }] },
    testSuite: {
      testCases: cases.map((t) => ({
        // Expectation is irrelevant to the diff; ALLOW is used uniformly so
        // state SUCCESS === "the rule allowed" and FAILURE === "denied".
        expectation: 'ALLOW',
        request: t.request,
        functionMocks: MOCKS,
      })),
    },
  };

  const resp = await fetch(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}:test`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    },
  );
  const json = JSON.parse(await resp.text());
  if (!resp.ok) {
    console.error(`[${label}] HTTP ${resp.status}:`);
    console.error(JSON.stringify(json, null, 2));
    process.exit(1);
  }
  const errs = (json.issues || []).filter((i) => i.severity === 'ERROR');
  if (errs.length) {
    console.error(`[${label}] RULES DID NOT COMPILE:`);
    console.error(JSON.stringify(errs, null, 2));
    process.exit(1);
  }
  return (json.testResults || []).map((r) =>
    r.state === 'SUCCESS' ? 'ALLOW' : r.state === 'FAILURE' ? 'DENY' : r.state || 'NO_RESULT',
  );
}

async function main() {
  const token = getToken();
  const newRules = fs.readFileSync(RULES_PATH, 'utf8');
  const oldRules = execSync('git show HEAD:firestore.rules', {
    cwd: REPO,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });

  console.log(`Cases: ${cases.length}`);
  console.log(`HEAD rules: ${oldRules.length} bytes`);
  console.log(`Working-tree rules: ${newRules.length} bytes`);
  console.log('');

  const before = await evaluate(token, oldRules, 'HEAD');
  const after = await evaluate(token, newRules, 'WORKING');

  const changed = [];
  const unchanged = [];
  for (let i = 0; i < cases.length; i++) {
    (before[i] === after[i] ? unchanged : changed).push({
      label: cases[i].label,
      before: before[i],
      after: after[i],
    });
  }

  console.log('━'.repeat(76));
  console.log('  DIFFERENTIAL: HEAD firestore.rules vs working tree');
  console.log('━'.repeat(76));
  if (changed.length === 0) {
    console.log('  (no behavioural differences on any probed path)');
  }
  for (const ch of changed) {
    const scoped = ch.label.startsWith('commands:');
    console.log(
      `${scoped ? 'IN-SCOPE ' : 'OUT-OF-SCOPE!'}  ${ch.before} → ${ch.after}   ${ch.label}`,
    );
  }
  console.log('━'.repeat(76));

  const strays = changed.filter((ch) => !ch.label.startsWith('commands:'));
  console.log(`Probed:        ${cases.length}`);
  console.log(`Unchanged:     ${unchanged.length}`);
  console.log(`Changed:       ${changed.length}  (all should be /commands)`);
  console.log(`Out-of-scope:  ${strays.length}`);
  console.log('');
  console.log(strays.length === 0 ? 'BLAST RADIUS CONTAINED' : 'STRAY CHANGES PRESENT');
  process.exit(strays.length === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
