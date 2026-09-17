// _test_rules_integrations_crews.js
//
// Firestore Security Rules verification for the 2026-09-17 additions:
//   - users/{uid}/integrations/{provider}   (Alexa / Google Home linking)
//   - game_day_crews/{crewId}               (Game Day crews)
//
// Uses the Firebase Security Rules REST :test endpoint against the LOCAL
// firestore.rules content. This is the same engine the Console's Rules
// Playground drives. It also surfaces compile errors, so it doubles as a
// syntax check before any deploy.
//
// READ-ONLY: :test publishes nothing and touches no Firestore data.
//
// A real end-to-end write test against the DEPLOYED rules lives in
// _test_rules_integrations_crews_live.js — run that after deploying.
//
// Usage: NODE_PATH=<repo>/node_modules node scripts/_test_rules_integrations_crews.js

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');
const SA = path.join(os.homedir(), '.lumina',
  'icrt6menwsv2d8all8oijs021b06s5-firebase-adminsdk-fbsvc-2e0cb54335.json');

const ME = 'user-me-uid';
const OTHER = 'user-other-uid';
const D = '/databases/(default)/documents';

const now = { __time__: '2026-09-17T12:00:00Z' };

const testCases = [
  // ───────────────────────── integrations ─────────────────────────
  {
    label: 'INT-1 owner GET own integrations/alexa',
    expectation: 'ALLOW',
    request: { auth: { uid: ME }, method: 'get',
      path: `${D}/users/${ME}/integrations/alexa` },
    resource: { data: { isLinked: true, accessToken: 'secret' } },
  },
  {
    label: 'INT-2 OTHER user GET my integrations/alexa (token exfil)',
    expectation: 'DENY',
    request: { auth: { uid: OTHER }, method: 'get',
      path: `${D}/users/${ME}/integrations/alexa` },
    resource: { data: { isLinked: true, accessToken: 'secret' } },
  },
  {
    label: 'INT-3 owner CREATE with client-owned keys only',
    expectation: 'ALLOW',
    request: { auth: { uid: ME }, method: 'create',
      path: `${D}/users/${ME}/integrations/alexa`,
      resource: { data: { linkInitiated: true, initiatedAt: now } } },
  },
  {
    label: 'INT-4 owner CREATE forging isLinked (must be refused)',
    expectation: 'DENY',
    request: { auth: { uid: ME }, method: 'create',
      path: `${D}/users/${ME}/integrations/alexa`,
      resource: { data: { linkInitiated: true, isLinked: true } } },
  },
  {
    label: 'INT-5 owner UPDATE injecting a token field (must be refused)',
    expectation: 'DENY',
    request: { auth: { uid: ME }, method: 'update',
      path: `${D}/users/${ME}/integrations/alexa`,
      resource: { data: { linkInitiated: true, accessToken: 'attacker' } } },
    resource: { data: { linkInitiated: true } },
  },
  {
    label: 'INT-6 owner DELETE own integration (unlink)',
    expectation: 'ALLOW',
    request: { auth: { uid: ME }, method: 'delete',
      path: `${D}/users/${ME}/integrations/google_home` },
    resource: { data: { isLinked: true } },
  },
  {
    label: 'INT-7 owner CREATE unknown provider',
    expectation: 'DENY',
    request: { auth: { uid: ME }, method: 'create',
      path: `${D}/users/${ME}/integrations/dropbox`,
      resource: { data: { linkInitiated: true, initiatedAt: now } } },
  },
  {
    label: 'INT-8 unauthenticated GET',
    expectation: 'DENY',
    request: { auth: null, method: 'get',
      path: `${D}/users/${ME}/integrations/alexa` },
    resource: { data: { isLinked: true } },
  },

  // ─────────────────────────── crews ──────────────────────────────
  {
    label: 'CREW-1 member GET crew',
    expectation: 'ALLOW',
    request: { auth: { uid: ME }, method: 'get',
      path: `${D}/game_day_crews/crew1` },
    resource: { data: { host_uid: OTHER, member_uids: [OTHER, ME],
      invite_code: 'ABC123' } },
  },
  {
    label: 'CREW-2 non-member GET crew (invite-code harvesting)',
    expectation: 'DENY',
    request: { auth: { uid: OTHER }, method: 'get',
      path: `${D}/game_day_crews/crew1` },
    resource: { data: { host_uid: ME, member_uids: [ME],
      invite_code: 'ABC123' } },
  },
  {
    label: 'CREW-3 CREATE as host, self as only member',
    expectation: 'ALLOW',
    request: { auth: { uid: ME }, method: 'create',
      path: `${D}/game_day_crews/crew2`,
      resource: { data: { host_uid: ME, member_uids: [ME],
        team_slug: 'kc', invite_code: 'XYZ789' } } },
  },
  {
    label: 'CREW-4 CREATE naming someone else as host',
    expectation: 'DENY',
    request: { auth: { uid: ME }, method: 'create',
      path: `${D}/game_day_crews/crew3`,
      resource: { data: { host_uid: OTHER, member_uids: [OTHER] } } },
  },
  {
    label: 'CREW-5 CREATE conscripting another member',
    expectation: 'DENY',
    request: { auth: { uid: ME }, method: 'create',
      path: `${D}/game_day_crews/crew4`,
      resource: { data: { host_uid: ME, member_uids: [ME, OTHER] } } },
  },
  {
    label: 'CREW-6 member UPDATE design, host_uid preserved',
    expectation: 'ALLOW',
    request: { auth: { uid: ME }, method: 'update',
      path: `${D}/game_day_crews/crew1`,
      resource: { data: { host_uid: OTHER, member_uids: [OTHER, ME],
        design_name: 'Fireworks' } } },
    resource: { data: { host_uid: OTHER, member_uids: [OTHER, ME],
      design_name: 'Old' } },
  },
  {
    label: 'CREW-7 member UPDATE promoting self to host',
    expectation: 'DENY',
    request: { auth: { uid: ME }, method: 'update',
      path: `${D}/game_day_crews/crew1`,
      resource: { data: { host_uid: ME, member_uids: [OTHER, ME] } } },
    resource: { data: { host_uid: OTHER, member_uids: [OTHER, ME] } },
  },
  {
    label: 'CREW-8 non-member UPDATE (drive strangers’ lights)',
    expectation: 'DENY',
    request: { auth: { uid: OTHER }, method: 'update',
      path: `${D}/game_day_crews/crew1`,
      resource: { data: { host_uid: ME, member_uids: [ME],
        live_scoring: true } } },
    resource: { data: { host_uid: ME, member_uids: [ME] } },
  },
  {
    label: 'CREW-9 host DELETE (dissolve)',
    expectation: 'ALLOW',
    request: { auth: { uid: ME }, method: 'delete',
      path: `${D}/game_day_crews/crew1` },
    resource: { data: { host_uid: ME, member_uids: [ME, OTHER] } },
  },
  {
    label: 'CREW-10 non-host member DELETE',
    expectation: 'DENY',
    request: { auth: { uid: OTHER }, method: 'delete',
      path: `${D}/game_day_crews/crew1` },
    resource: { data: { host_uid: ME, member_uids: [ME, OTHER] } },
  },
  {
    label: 'CREW-11 member LEAVE via arrayRemove update',
    expectation: 'ALLOW',
    request: { auth: { uid: OTHER }, method: 'update',
      path: `${D}/game_day_crews/crew1`,
      resource: { data: { host_uid: ME, member_uids: [ME] } } },
    resource: { data: { host_uid: ME, member_uids: [ME, OTHER] } },
  },
];

(async () => {
  const rules = fs.readFileSync(RULES_PATH, 'utf8');
  const auth = new GoogleAuth({
    keyFile: SA,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  // The admin SDK service account has firebaserules.rulesets.get but NOT
  // .test, so prefer an owner token when one is supplied:
  //   RULES_TEST_TOKEN=$(gcloud auth print-access-token)
  let token = process.env.RULES_TEST_TOKEN;
  if (!token) {
    const client = await auth.getClient();
    token = (await client.getAccessToken()).token;
  }

  const body = {
    source: { files: [{ name: 'firestore.rules', content: rules }] },
    testSuite: {
      testCases: testCases.map((t) => ({
        expectation: t.expectation,
        request: t.request,
        ...(t.resource ? { resource: t.resource } : {}),
      })),
    },
  };

  const res = await fetch(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}:test`,
    { method: 'POST',
      headers: { Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        // User (ADC) credentials need an explicit quota project for this API.
        ...(process.env.RULES_TEST_TOKEN
          ? { 'x-goog-user-project': PROJECT_ID } : {}) },
      body: JSON.stringify(body) });

  const json = await res.json();
  if (!res.ok) {
    console.error('HTTP', res.status);
    console.error(JSON.stringify(json, null, 2));
    process.exit(1);
  }

  if (json.issues && json.issues.length) {
    console.error('\n*** RULES COMPILE ISSUES ***');
    for (const i of json.issues) {
      console.error(`  [${i.severity}] ${i.sourcePosition?.line}:` +
        `${i.sourcePosition?.column} ${i.description}`);
    }
    const fatal = json.issues.filter((i) => i.severity === 'ERROR');
    if (fatal.length) process.exit(1);
  } else {
    console.log('rules compiled clean (no issues)\n');
  }

  const results = json.testResults || [];
  let pass = 0, fail = 0;
  results.forEach((r, i) => {
    const t = testCases[i];
    const ok = r.state === 'SUCCESS';
    ok ? pass++ : fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${t.label}` +
      `  (expected ${t.expectation}, engine=${r.state})`);
    if (!ok && r.debugMessages) {
      r.debugMessages.slice(0, 3).forEach((m) => console.log('        ', m));
    }
  });

  console.log(`\n${pass}/${results.length} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
