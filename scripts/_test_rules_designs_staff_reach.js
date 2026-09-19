// _test_rules_designs_staff_reach.js
//
// Firestore Security Rules verification for the 2026-09-19 change to
//   /users/{userId}/designs/{designId}
// (create/update: owner OR staffMayReach(userId); read/delete: owner only).
// Design-studio audit F6 — an installer in "Existing Customer" mode saves into
// the CUSTOMER's subtree while authenticated as staff.
//
// Uses the Firebase Security Rules REST :test endpoint against the LOCAL
// firestore.rules content — the same engine as the Console's Rules
// Playground. It also surfaces compile errors, so it doubles as a syntax
// check before any deploy.
//
// READ-ONLY: :test publishes nothing and touches no Firestore data.
//
// IT DOES NOT PROVE THE APP CAN WRITE THROUGH THE DEPLOYED RULES. That needs a
// real client credential after deploy (see feedback: verify with a CLIENT
// credential, not admin).
//
// Usage (gcloud ADC — no service-account key, no node_modules):
//   RULES_TEST_TOKEN=$(gcloud auth print-access-token) \
//     node scripts/_test_rules_designs_staff_reach.js

'use strict';

const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');
const D = '/databases/(default)/documents';

const CUSTOMER = 'customer-uid';      // provisioned, dealer_code '01'
const SELF_SIGNUP = 'selfsignup-uid'; // provisioned, NO dealer_code
const STUB = 'stub-uid';              // FCM stub doc: no owner_id
const STAFF = 'staff_installer_0101';

const staffAuth = (dealerCode, role = 'installer') =>
  ({ uid: STAFF, token: { dealerCode, role } });

// get()/exists() on the parent user doc, as staffMayReach() resolves it.
const userDocMocks = (uid, data) => {
  const arg = { exact_value: `${D}/users/${uid}` };
  return [
    { function: 'exists', args: [arg], result: { value: data !== null } },
    ...(data === null ? [] : [
      { function: 'get', args: [arg], result: { value: { data } } },
    ]),
  ];
};
const PROVISIONED = { owner_id: CUSTOMER, dealer_code: '01' };

const design = { data: { name: 'Demo', owner_id: CUSTOMER, per_pixel: true } };
const at = (uid) => `${D}/users/${uid}/designs/d1`;

const testCases = [
  { label: 'D-1  owner CREATE own design', expectation: 'ALLOW',
    request: { auth: { uid: CUSTOMER }, method: 'create', path: at(CUSTOMER), resource: design } },
  { label: 'D-2  owner UPDATE own design', expectation: 'ALLOW',
    request: { auth: { uid: CUSTOMER }, method: 'update', path: at(CUSTOMER), resource: design },
    resource: design },
  { label: 'D-3  owner READ / DELETE own design', expectation: 'ALLOW',
    request: { auth: { uid: CUSTOMER }, method: 'delete', path: at(CUSTOMER) }, resource: design },

  { label: "D-4  installer of the customer's dealer CREATE (the F6 case)", expectation: 'ALLOW',
    request: { auth: staffAuth('01'), method: 'create', path: at(CUSTOMER), resource: design },
    functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },
  { label: "D-5  installer of the customer's dealer UPDATE", expectation: 'ALLOW',
    request: { auth: staffAuth('01'), method: 'update', path: at(CUSTOMER), resource: design },
    resource: design, functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },
  { label: 'D-6  salesperson of the same dealer CREATE', expectation: 'ALLOW',
    request: { auth: staffAuth('01', 'salesperson'), method: 'create', path: at(CUSTOMER), resource: design },
    functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },

  { label: 'D-7  installer of ANOTHER dealer CREATE (cross-dealer)', expectation: 'DENY',
    request: { auth: staffAuth('02'), method: 'create', path: at(CUSTOMER), resource: design },
    functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },
  { label: 'D-8  staff CREATE on a self-signup customer (no dealer_code)', expectation: 'DENY',
    request: { auth: staffAuth('01'), method: 'create', path: at(SELF_SIGNUP), resource: design },
    functionMocks: userDocMocks(SELF_SIGNUP, { owner_id: SELF_SIGNUP }) },
  { label: 'D-9  staff READ a customer design (read stays owner-only)', expectation: 'DENY',
    request: { auth: staffAuth('01'), method: 'get', path: at(CUSTOMER) },
    resource: design, functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },
  { label: 'D-10 staff DELETE a customer design (delete stays owner-only)', expectation: 'DENY',
    request: { auth: staffAuth('01'), method: 'delete', path: at(CUSTOMER) },
    resource: design, functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },
  { label: 'D-11 ordinary signed-in user CREATE in someone else\'s designs', expectation: 'DENY',
    request: { auth: { uid: 'rando-uid' }, method: 'create', path: at(CUSTOMER), resource: design },
    functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },
  { label: 'D-12 signed-in user with a forged role but NO dealerCode', expectation: 'DENY',
    request: { auth: { uid: 'rando-uid', token: { role: 'installer' } }, method: 'create',
      path: at(CUSTOMER), resource: design },
    functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },
  { label: 'D-13 unauthenticated CREATE', expectation: 'DENY',
    request: { method: 'create', path: at(CUSTOMER), resource: design },
    functionMocks: userDocMocks(CUSTOMER, PROVISIONED) },

  // staffMayReach's documented residual: an un-provisioned (absent / stub)
  // user doc is reachable by any STAFF session — same as pixelMap.
  { label: 'D-14 staff CREATE under a stub user doc (no owner_id) — documented residual', expectation: 'ALLOW',
    request: { auth: staffAuth('01'), method: 'create', path: at(STUB), resource: design },
    functionMocks: userDocMocks(STUB, { fcmToken: 't' }) },
  { label: 'D-15 NON-staff CREATE under a stub user doc', expectation: 'DENY',
    request: { auth: { uid: 'rando-uid' }, method: 'create', path: at(STUB), resource: design },
    functionMocks: userDocMocks(STUB, { fcmToken: 't' }) },
];

(async () => {
  const token = process.env.RULES_TEST_TOKEN;
  if (!token) {
    console.error('Set RULES_TEST_TOKEN=$(gcloud auth print-access-token)');
    process.exit(2);
  }
  const rules = fs.readFileSync(RULES_PATH, 'utf8');
  const body = {
    source: { files: [{ name: 'firestore.rules', content: rules }] },
    testSuite: {
      testCases: testCases.map((t) => ({
        expectation: t.expectation,
        request: t.request,
        ...(t.resource ? { resource: t.resource } : {}),
        ...(t.functionMocks ? { functionMocks: t.functionMocks } : {}),
      })),
    },
  };
  const res = await fetch(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}:test`,
    { method: 'POST',
      headers: { Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        'x-goog-user-project': PROJECT_ID },
      body: JSON.stringify(body) });
  const json = await res.json();
  if (!res.ok) {
    console.error('HTTP', res.status, JSON.stringify(json, null, 2));
    process.exit(1);
  }
  const issues = json.issues || [];
  const fatal = issues.filter((i) => i.severity === 'ERROR');
  if (issues.length) {
    for (const i of issues) {
      console.error(`  [${i.severity}] ${i.sourcePosition?.line}:${i.sourcePosition?.column} ${i.description}`);
    }
    if (fatal.length) process.exit(1);
  } else {
    console.log('rules compiled clean (no issues)\n');
  }
  let pass = 0, fail = 0;
  (json.testResults || []).forEach((r, i) => {
    const t = testCases[i];
    const ok = r.state === 'SUCCESS';
    ok ? pass++ : fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${t.label}  (expected ${t.expectation}, engine=${r.state})`);
    if (!ok && r.debugMessages) r.debugMessages.slice(0, 3).forEach((m) => console.log('        ', m));
  });
  console.log(`\n${pass}/${testCases.length} passed, ${fail} failed`);
  process.exitCode = fail ? 1 : 0; // (not process.exit — libuv asserts on Windows)
})();
