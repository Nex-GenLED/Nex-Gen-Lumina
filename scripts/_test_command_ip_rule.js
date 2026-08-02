// _test_command_ip_rule.js
//
// Read-only Firestore Security Rules verification for the S1 commands
// controllerIp guard (audit/COMMAND_SAFETY.md). Same engine/pattern as
// _test_rules_block.js and _test_sync_fanout_rule.js: POSTs the LOCAL
// firestore.rules to firebaserules.googleapis.com/v1/projects/{id}:test.
//
// Does NOT deploy. Does NOT read or mutate any project data — every get()/
// exists() the ruleset performs is satisfied by an explicit functionMock, so
// the result depends only on the rules text and is reproducible on any machine.
//
// Usage: node scripts/_test_command_ip_rule.js
// Gitignored / untracked — diag script convention.

'use strict';

const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');
const SERVICE_ACCOUNT_PATH = path.resolve(
  __dirname,
  '..',
  'android',
  'app',
  'icrt6menwsv2d8all8oijs021b06s5-firebase-adminsdk-fbsvc-2e0cb54335.json',
);

const UID = 'u_owner';
const OTHER_UID = 'u_other';
const DOC = `/databases/(default)/documents/users/${UID}/commands/cmd1`;
const USER_DOC = `/databases/(default)/documents/users/${UID}`;

// The customer's own registered controllers.
const OWN_IP_A = '192.168.1.150';
const OWN_IP_B = '192.168.1.151';
// A host on the same LAN that is NOT one of their controllers — the attack
// target the guard exists to refuse (a NAS, a router admin page, a camera).
const FOREIGN_LAN_IP = '192.168.1.1';
// Another customer's controller IP.
const OTHER_CUSTOMER_IP = '10.0.0.42';

const auth = { uid: UID, token: { email: 'owner@example.com' } };

// ── functionMocks ───────────────────────────────────────────────────
// The ruleset calls exists()/get() on the user doc. Mock both so the test is
// hermetic. `controller_ips` is the allowlist syncControllerIps.ts maintains.
const userDocMocks = (controllerIps) => [
  {
    function: 'exists',
    args: [{ exactValue: USER_DOC }],
    result: { value: true },
  },
  {
    function: 'get',
    args: [{ exactValue: USER_DOC }],
    result: {
      value: {
        data: {
          controller_ips: controllerIps,
          // isBridgeForUser() reads this; a non-matching value keeps the
          // bridge branch false so we test the OWNER branch in isolation.
          bridge_email: 'bridge@lumina.local',
        },
      },
    },
  },
];

// A user doc that does not exist — the P0-5 shape.
const missingUserDocMocks = [
  {
    function: 'exists',
    args: [{ exactValue: USER_DOC }],
    result: { value: false },
  },
];

const cmd = (extra) => ({
  type: 'applyJson',
  payload: '{"on":true}',
  controllerId: 'ctrl_a',
  webhookUrl: '',
  status: 'pending',
  ...extra,
});

const testCases = [
  // ── The four cases named in the S1 brief ──────────────────────────
  {
    label: '1. valid registered controllerIp → ALLOW',
    expectation: 'ALLOW',
    functionMocks: userDocMocks([OWN_IP_A, OWN_IP_B]),
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: OWN_IP_A }) },
    },
  },
  {
    label: '2. unregistered LAN host as controllerIp → DENY',
    expectation: 'DENY',
    functionMocks: userDocMocks([OWN_IP_A, OWN_IP_B]),
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: FOREIGN_LAN_IP }) },
    },
  },
  {
    label: '3. controllerIp field OMITTED → ALLOW (unredirectable)',
    expectation: 'ALLOW',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: {
      auth,
      path: DOC,
      method: 'create',
      // No controllerIp key at all — the bridge falls back to its paired IP.
      resource: { data: cmd({}) },
    },
  },
  {
    label: "4. another customer's controller IP → DENY",
    expectation: 'DENY',
    functionMocks: userDocMocks([OWN_IP_A, OWN_IP_B]),
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: OTHER_CUSTOMER_IP }) },
    },
  },

  // ── Regressions the two breaking app writers demand ───────────────
  {
    label: '5. empty-string controllerIp → ALLOW (bridge_setup_screen shape)',
    expectation: 'ALLOW',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: '', controllerId: '' }) },
    },
  },
  {
    label:
      '6. registered IP with NO controllerId → ALLOW (bridge_health_service shape)',
    expectation: 'ALLOW',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: {
        data: {
          type: 'ping',
          controllerIp: OWN_IP_A,
          status: 'pending',
        },
      },
    },
  },
  {
    label:
      '7. UPDATE re-pointing to an unregistered IP → DENY (the .set() bypass)',
    expectation: 'DENY',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: {
      auth,
      path: DOC,
      method: 'update',
      resource: { data: cmd({ controllerIp: FOREIGN_LAN_IP }) },
    },
  },
  {
    label: '8. UPDATE keeping a registered IP → ALLOW',
    expectation: 'ALLOW',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: {
      auth,
      path: DOC,
      method: 'update',
      resource: { data: cmd({ controllerIp: OWN_IP_A }) },
    },
  },

  // ── Pre-existing isolation must not regress ───────────────────────
  {
    label: "9. another user writing into this user's commands → DENY",
    expectation: 'DENY',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: {
      auth: { uid: OTHER_UID, token: {} },
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: OWN_IP_A }) },
    },
  },
  {
    label: '10. unauthenticated create → DENY',
    expectation: 'DENY',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: {
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: OWN_IP_A }) },
    },
  },
  {
    label: '11. owner read own command → ALLOW (read path untouched)',
    expectation: 'ALLOW',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: { auth, path: DOC, method: 'get' },
  },
  {
    label: '12. owner delete own command → ALLOW (cleanup path untouched)',
    expectation: 'ALLOW',
    functionMocks: userDocMocks([OWN_IP_A]),
    request: { auth, path: DOC, method: 'delete' },
  },

  // ── Missing user doc (P0-5 shape) ─────────────────────────────────
  {
    label: '13. targeted write with NO user doc → DENY (conservative)',
    expectation: 'DENY',
    functionMocks: missingUserDocMocks,
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: OWN_IP_A }) },
    },
  },
  {
    label: '14. untargeted write with NO user doc → ALLOW (still unredirectable)',
    expectation: 'ALLOW',
    functionMocks: missingUserDocMocks,
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: { data: cmd({}) },
    },
  },

  // ── Allowlist absent (pre-backfill) — proves the deploy-order hazard ──
  {
    label:
      '15. PRE-BACKFILL: user doc with no controller_ips, targeted → DENY ' +
      '(this is why the rule ships AFTER the backfill)',
    expectation: 'DENY',
    functionMocks: [
      { function: 'exists', args: [{ exactValue: USER_DOC }], result: { value: true } },
      {
        function: 'get',
        args: [{ exactValue: USER_DOC }],
        result: { value: { data: { bridge_email: 'bridge@lumina.local' } } },
      },
    ],
    request: {
      auth,
      path: DOC,
      method: 'create',
      resource: { data: cmd({ controllerIp: OWN_IP_A }) },
    },
  },
];

// The :test endpoint needs `firebaserules.rulesets.test`. The android/app
// adminsdk service account does NOT hold it (verified 2026-08-01: HTTP 403
// IAM_PERMISSION_DENIED), so prefer gcloud ADC — Tyler's own credentials, the
// same ones the LEASE_EXPOSURE audit used. Falls back to the SA key so the
// script still works anywhere that key is granted the permission later.
async function getAccessToken() {
  try {
    // shell:true is required on Windows — Node >=18 refuses to execFile a
    // .cmd shim directly (EINVAL).
    const { execSync } = require('child_process');
    const token = execSync(
      'gcloud auth application-default print-access-token',
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    ).trim();
    if (token) {
      console.log('Auth: gcloud application-default credentials');
      return token;
    }
  } catch (err) {
    console.log(`Auth: ADC unavailable (${err.message.split('\n')[0]}), ` +
      'falling back to the service-account key');
  }
  const gauth = new GoogleAuth({
    keyFile: SERVICE_ACCOUNT_PATH,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await gauth.getClient();
  const { token } = await client.getAccessToken();
  console.log('Auth: service-account key');
  return token;
}

async function main() {
  const rulesContent = fs.readFileSync(RULES_PATH, 'utf8');
  const accessToken = await getAccessToken();

  const body = {
    source: { files: [{ name: 'firestore.rules', content: rulesContent }] },
    testSuite: {
      testCases: testCases.map((t) => ({
        expectation: t.expectation,
        request: t.request,
        ...(t.functionMocks ? { functionMocks: t.functionMocks } : {}),
      })),
    },
  };

  const url = `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}:test`;
  console.log(`POST ${url}`);
  console.log(`Rules size: ${rulesContent.length} bytes`);
  console.log(`Test cases: ${testCases.length}`);
  console.log('');

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const respText = await resp.text();
  let respJson;
  try {
    respJson = JSON.parse(respText);
  } catch (err) {
    console.error(`HTTP ${resp.status} — non-JSON response:`);
    console.error(respText);
    process.exit(1);
  }
  if (!resp.ok) {
    console.error(`HTTP ${resp.status}:`);
    console.error(JSON.stringify(respJson, null, 2));
    process.exit(1);
  }

  // Compilation errors come back here and would otherwise be mistaken for
  // silent passes.
  const issues = respJson.issues || [];
  const errors = issues.filter((i) => i.severity === 'ERROR');
  if (errors.length) {
    console.error('RULES DID NOT COMPILE:');
    console.error(JSON.stringify(errors, null, 2));
    process.exit(1);
  }
  if (issues.length) {
    console.log('Non-fatal issues:');
    console.log(JSON.stringify(issues, null, 2));
    console.log('');
  }

  const testResults = respJson.testResults || [];
  let allPassed = true;

  console.log('━'.repeat(72));
  console.log('  S1 commands controllerIp guard — Rules :test results');
  console.log('━'.repeat(72));
  for (let i = 0; i < testCases.length; i++) {
    const tc = testCases[i];
    const result = testResults[i] || {};
    const state = result.state || 'NO_RESULT';
    const expected = tc.expectation;

    let actualLabel;
    if (state === 'SUCCESS') {
      actualLabel = expected;
    } else if (state === 'FAILURE') {
      actualLabel = expected === 'ALLOW' ? 'DENY' : 'ALLOW';
    } else {
      actualLabel = state;
    }

    const pass = state === 'SUCCESS';
    if (!pass) allPassed = false;
    console.log(
      `${pass ? 'PASS' : 'FAIL'}  expected=${expected.padEnd(5)} ` +
        `actual=${String(actualLabel).padEnd(5)}  ${tc.label}`,
    );
    if (!pass && result.errorPosition) {
      console.log(`        at line ${result.errorPosition.line}`);
    }
  }
  console.log('━'.repeat(72));
  console.log(allPassed ? 'ALL PASSED' : 'FAILURES PRESENT');
  process.exit(allPassed ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
