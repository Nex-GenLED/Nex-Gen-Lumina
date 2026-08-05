// _test_rules_deploy_gate.js
//
// STEP 3 deploy gate for the 2026-08-05 rules deploy (solar + controller_ips).
// Unlike _test_rules_diff.js (which asserts only the OLD-vs-NEW delta), this
// asserts ABSOLUTE expectations against the CANDIDATE (working-tree) rules:
//
//   Part A — 15-case controllerIp matrix (S1 command-safety, mid-soak)
//   Part B — solar_scheduling flag cases (the new block) + sibling control
//
// Read-only. Uses the Security Rules :test endpoint — nothing is deployed and
// no Firestore document is read or written. Every get()/exists() is satisfied
// by an explicit functionMock, so results depend only on the rules text.
//
// Usage: node scripts/_test_rules_deploy_gate.js
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

const MOCKS = [
  { function: 'exists', args: [{ exactValue: USER_DOC }], result: { value: true } },
  {
    function: 'get',
    args: [{ exactValue: USER_DOC }],
    result: {
      value: {
        data: {
          controller_ips: ['192.168.1.150', '192.168.1.151'],
          bridge_email: 'bridge@lumina.local',
          dealer_code: '01',
          user_role: 'customer',
        },
      },
    },
  },
];

const doc = (p) => `${D}${p}`;
const c = (label, expect, auth, p, method, data) => ({
  label,
  expect,
  request: {
    ...(auth ? { auth } : {}),
    path: doc(p),
    method,
    ...(data ? { resource: { data } } : {}),
  },
});

const CMD = `/users/${UID}/commands/cmd1`;

// ── Part A — controllerIp matrix ────────────────────────────────────────
// The S1 rule: a command carrying a controllerIp may only be written if that
// IP is in the owner's controller_ips allowlist. Commands with NO controllerIp
// (pairing pings, health checks, whole-account ops) must remain writable —
// that is the regression the deploy is most likely to cause.
const partA = [
  // registered IPs — both entries of the allowlist
  c('A01 owner create, registered ip .150', 'ALLOW', owner, CMD, 'create',
    { type: 'applyJson', controllerIp: '192.168.1.150', status: 'pending' }),
  c('A02 owner create, registered ip .151', 'ALLOW', owner, CMD, 'create',
    { type: 'power', controllerIp: '192.168.1.151', status: 'pending' }),
  // unregistered IP — the whole point of the rule
  c('A03 owner create, UNREGISTERED ip', 'DENY', owner, CMD, 'create',
    { type: 'applyJson', controllerIp: '192.168.1.99', status: 'pending' }),
  c('A04 owner create, LAN-adjacent unregistered', 'DENY', owner, CMD, 'create',
    { type: 'power', controllerIp: '10.0.0.5', status: 'pending' }),
  // no controllerIp at all — MUST still work (STEP 5b/5c hand-verify these)
  c('A05 owner create, NO controllerIp (ping)', 'ALLOW', owner, CMD, 'create',
    { type: 'ping', status: 'pending' }),
  c('A06 owner create, EMPTY controllerIp (pairing verify)', 'ALLOW', owner, CMD, 'create',
    { type: 'ping', controllerId: '', status: 'pending' }),
  c('A07 owner create, brightness w/ registered ip', 'ALLOW', owner, CMD, 'create',
    { type: 'brightness', controllerIp: '192.168.1.150', bri: 128, status: 'pending' }),
  // updates
  c('A08 owner update, registered ip', 'ALLOW', owner, CMD, 'update',
    { type: 'ping', controllerIp: '192.168.1.150', status: 'pending' }),
  c('A09 owner update, UNREGISTERED ip', 'DENY', owner, CMD, 'update',
    { type: 'ping', controllerIp: '192.168.1.99', status: 'pending' }),
  c('A10 bridge update status only', 'ALLOW', bridge, CMD, 'update',
    { status: 'completed' }),
  // reads / deletes unaffected by the allowlist
  c('A11 owner read', 'ALLOW', owner, CMD, 'get'),
  c('A12 owner delete', 'ALLOW', owner, CMD, 'delete'),
  // isolation
  c('A13 stranger create, registered ip', 'DENY', stranger, CMD, 'create',
    { type: 'ping', controllerIp: '192.168.1.150', status: 'pending' }),
  c('A14 stranger read', 'DENY', stranger, CMD, 'get'),
  c('A15 unauth create', 'DENY', null, CMD, 'create',
    { type: 'ping', status: 'pending' }),
];

// ── Part B — solar_scheduling flag + sibling control ────────────────────
const SOLAR = '/config/solar_scheduling';
const partB = [
  // THE fix: an authenticated client must be able to READ the flag.
  c('B01 authed read solar flag', 'ALLOW', owner, SOLAR, 'get'),
  c('B02 stranger (any authed user) read solar flag', 'ALLOW', stranger, SOLAR, 'get'),
  c('B03 UNAUTH read solar flag', 'DENY', null, SOLAR, 'get'),
  // bootstrap create with the safe default only
  c('B04 authed create with enabled=false', 'ALLOW', owner, SOLAR, 'create',
    { enabled: false }),
  c('B05 authed create with enabled=TRUE', 'DENY', owner, SOLAR, 'create',
    { enabled: true }),
  c('B06 unauth create', 'DENY', null, SOLAR, 'create', { enabled: false }),
  // the flip stays console-only
  c('B07 authed update (the flip)', 'DENY', owner, SOLAR, 'update', { enabled: true }),
  c('B08 authed update to false', 'DENY', owner, SOLAR, 'update', { enabled: false }),
  c('B09 authed delete', 'DENY', owner, SOLAR, 'delete'),
  // sibling control — must behave identically, proving the new block matches
  c('B10 sibling sync_fanout authed read', 'ALLOW', owner, '/config/sync_fanout', 'get'),
  c('B11 sibling calendar_leases authed read', 'ALLOW', owner, '/config/calendar_leases', 'get'),
  c('B12 sibling schedules_subcollection authed read', 'ALLOW', owner,
    '/config/schedules_subcollection', 'get'),
  c('B13 sibling sync_fanout unauth read', 'DENY', null, '/config/sync_fanout', 'get'),
  // an undeclared config doc must STILL be denied — the block must not have
  // been written as a wildcard by accident
  c('B14 undeclared config doc authed read', 'DENY', owner, '/config/not_a_real_flag', 'get'),
];

const cases = [...partA, ...partB];

function getToken() {
  return execSync('gcloud auth application-default print-access-token', {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

async function main() {
  const token = getToken();
  const rules = fs.readFileSync(RULES_PATH, 'utf8');

  const body = {
    source: { files: [{ name: 'firestore.rules', content: rules }] },
    testSuite: {
      testCases: cases.map((t) => ({
        // Uniform ALLOW so SUCCESS === allowed, FAILURE === denied; the
        // per-case expectation is asserted below, not by the API.
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
    console.error(`HTTP ${resp.status}:`, JSON.stringify(json, null, 2));
    process.exit(1);
  }
  const errs = (json.issues || []).filter((i) => i.severity === 'ERROR');
  if (errs.length) {
    console.error('RULES DID NOT COMPILE:', JSON.stringify(errs, null, 2));
    process.exit(1);
  }

  const actual = (json.testResults || []).map((r) =>
    r.state === 'SUCCESS' ? 'ALLOW' : r.state === 'FAILURE' ? 'DENY' : r.state || 'NO_RESULT',
  );

  let failed = 0;
  const emit = (title, subset, offset) => {
    console.log(`\n${title}`);
    console.log('─'.repeat(76));
    subset.forEach((t, i) => {
      const got = actual[offset + i];
      const ok = got === t.expect;
      if (!ok) failed++;
      console.log(
        `  ${ok ? 'PASS' : 'FAIL'}  ${t.label.padEnd(46)} expect=${t.expect.padEnd(5)} got=${got}`,
      );
    });
  };

  console.log(`Candidate rules: ${rules.length} bytes · ${cases.length} cases`);
  emit('PART A — controllerIp matrix (S1 command safety)', partA, 0);
  emit('PART B — config/solar_scheduling + sibling control', partB, partA.length);

  console.log('\n' + '━'.repeat(76));
  console.log(failed === 0 ? 'ALL CASES PASS — deploy gate GREEN' : `${failed} CASE(S) FAILED — DO NOT DEPLOY`);
  console.log('━'.repeat(76));
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('ERR', e && e.message);
  process.exit(1);
});
