// _test_rules_integrations_crews_live.js
//
// LIVE end-to-end verification of the 2026-09-17 rules additions against the
// DEPLOYED ruleset, using real CLIENT credentials and real Firestore
// reads/writes.
//
// WHY THIS EXISTS AND WHY IT IS NOT AN ADMIN READBACK. The admin SDK bypasses
// security rules entirely, so an admin write proves a document can exist and
// proves nothing about whether the app can write it. Every request below is
// made with a user ID token minted through Identity Toolkit, so it is subject
// to exactly the rules a phone is subject to.
//
// Each ALLOW case is paired with a negative control from a SECOND user. The
// negative controls are what prove the credential is genuinely constrained —
// if the DENY cases passed too, the token would be over-privileged and the
// ALLOW results would be meaningless.
//
// The two synthetic users are created and deleted by this script, and every
// document it writes is removed in the cleanup phase.
//
// Usage:
//   NODE_PATH=<repo>/node_modules node scripts/_test_rules_integrations_crews_live.js

'use strict';

const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const API_KEY = 'AIzaSyCWwqffD-ggRh5-IYwR2ldjaztd-Jgz0JY'; // web client key
const SA = path.join(os.homedir(), '.lumina',
  'icrt6menwsv2d8all8oijs021b06s5-firebase-adminsdk-fbsvc-2e0cb54335.json');

const A_UID = 'rulestest-owner-2026-09-17';
const B_UID = 'rulestest-attacker-2026-09-17';
const CREW_ID = 'rulestest-crew-2026-09-17';

const DOCS = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}` +
  `/databases/(default)/documents`;

admin.initializeApp({
  credential: admin.credential.cert(require(SA)),
  projectId: PROJECT_ID,
});

async function idTokenFor(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
    { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }) });
  const j = await res.json();
  if (!res.ok) throw new Error('signInWithCustomToken failed: ' + JSON.stringify(j));
  return j.idToken;
}

async function req(method, url, token, body) {
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  let payload = null;
  try { payload = await res.json(); } catch { /* 200 delete returns {} */ }
  return { status: res.status, payload };
}

const S = (v) => ({ stringValue: v });
const B = (v) => ({ booleanValue: v });
const T = (v) => ({ timestampValue: v });
const ARR = (vals) => ({ arrayValue: { values: vals } });

let pass = 0, fail = 0;
function check(label, expect, got, extra) {
  // expect: 'ALLOW' -> 2xx ; 'DENY' -> 403
  const ok = expect === 'ALLOW' ? (got >= 200 && got < 300) : got === 403;
  ok ? pass++ : fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}  [expected ${expect}, HTTP ${got}]`);
  if (!ok && extra) {
    console.log('        ', JSON.stringify(extra).slice(0, 300));
  }
}

(async () => {
  console.log('Project :', PROJECT_ID);
  const rel = await (await fetch(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/releases/cloud.firestore`,
    { headers: { Authorization: `Bearer ${(await admin.app().options.credential
        .getAccessToken()).access_token}` } })).json();
  console.log('Live ruleset :', rel.rulesetName);
  console.log('Released     :', rel.updateTime);
  console.log('');

  const [tA, tB] = [await idTokenFor(A_UID), await idTokenFor(B_UID)];
  console.log('Minted client ID tokens for two synthetic users.\n');

  // ─────────────── integrations/{provider} ───────────────
  console.log('--- users/{uid}/integrations/{provider} ---');

  let r = await req('POST',
    `${DOCS}/users/${A_UID}/integrations?documentId=alexa`, tA,
    { fields: { linkInitiated: B(true), initiatedAt: T('2026-09-17T12:00:00Z') } });
  check('INT-1 owner CREATE integrations/alexa (the write that used to throw)',
    'ALLOW', r.status, r.payload);

  r = await req('GET', `${DOCS}/users/${A_UID}/integrations/alexa`, tA);
  check('INT-2 owner GET own link status', 'ALLOW', r.status, r.payload);

  r = await req('GET', `${DOCS}/users/${A_UID}/integrations/alexa`, tB);
  check('INT-3 NEGATIVE CONTROL other user GET (token exfil)', 'DENY',
    r.status, r.payload);

  r = await req('PATCH',
    `${DOCS}/users/${A_UID}/integrations/alexa` +
    `?updateMask.fieldPaths=isLinked`, tA,
    { fields: { isLinked: B(true) } });
  check('INT-4 NEGATIVE CONTROL owner forging isLinked', 'DENY',
    r.status, r.payload);

  r = await req('POST',
    `${DOCS}/users/${A_UID}/integrations?documentId=dropbox`, tA,
    { fields: { linkInitiated: B(true) } });
  check('INT-5 NEGATIVE CONTROL unknown provider', 'DENY', r.status, r.payload);

  r = await req('DELETE', `${DOCS}/users/${A_UID}/integrations/alexa`, tA);
  check('INT-6 owner DELETE (unlink)', 'ALLOW', r.status, r.payload);

  // ─────────────────── game_day_crews ────────────────────
  console.log('\n--- game_day_crews/{crewId} ---');

  r = await req('POST', `${DOCS}/game_day_crews?documentId=${CREW_ID}`, tA,
    { fields: { host_uid: S(A_UID), member_uids: ARR([S(A_UID)]),
      team_slug: S('rulestest'), invite_code: S('ZZZ999'),
      design_name: S('Original') } });
  check('CREW-1 host CREATE crew (used to be denied outright)',
    'ALLOW', r.status, r.payload);

  r = await req('GET', `${DOCS}/game_day_crews/${CREW_ID}`, tA);
  check('CREW-2 member GET own crew', 'ALLOW', r.status, r.payload);

  r = await req('GET', `${DOCS}/game_day_crews/${CREW_ID}`, tB);
  check('CREW-3 NEGATIVE CONTROL non-member GET (invite-code harvest)',
    'DENY', r.status, r.payload);

  r = await req('PATCH',
    `${DOCS}/game_day_crews/${CREW_ID}?updateMask.fieldPaths=design_name`, tA,
    { fields: { design_name: S('Fireworks') } });
  check('CREW-4 member UPDATE shared design', 'ALLOW', r.status, r.payload);

  r = await req('PATCH',
    `${DOCS}/game_day_crews/${CREW_ID}?updateMask.fieldPaths=live_scoring`, tB,
    { fields: { live_scoring: B(true) } });
  check('CREW-5 NEGATIVE CONTROL non-member UPDATE (drive strangers’ lights)',
    'DENY', r.status, r.payload);

  r = await req('PATCH',
    `${DOCS}/game_day_crews/${CREW_ID}?updateMask.fieldPaths=host_uid`, tA,
    { fields: { host_uid: S(B_UID) } });
  check('CREW-6 NEGATIVE CONTROL host_uid is immutable', 'DENY',
    r.status, r.payload);

  r = await req('DELETE', `${DOCS}/game_day_crews/${CREW_ID}`, tB);
  check('CREW-7 NEGATIVE CONTROL non-host DELETE', 'DENY', r.status, r.payload);

  r = await req('DELETE', `${DOCS}/game_day_crews/${CREW_ID}`, tA);
  check('CREW-8 host DELETE (dissolve) + cleanup', 'ALLOW', r.status, r.payload);

  // ───────────────────── cleanup ─────────────────────────
  console.log('\n--- cleanup ---');
  const db = admin.firestore();
  for (const p of [`users/${A_UID}/integrations/alexa`,
    `users/${A_UID}/integrations/dropbox`,
    `game_day_crews/${CREW_ID}`]) {
    await db.doc(p).delete().catch(() => {});
  }
  await db.doc(`users/${A_UID}`).delete().catch(() => {});
  await db.doc(`users/${B_UID}`).delete().catch(() => {});
  for (const uid of [A_UID, B_UID]) {
    await admin.auth().deleteUser(uid).catch(() => {});
  }
  console.log('synthetic users and test documents removed');

  console.log(`\n${pass}/${pass + fail} passed, ${fail} failed`);
  if (fail) process.exitCode = 1;
})().catch((e) => { console.error(e); process.exitCode = 1; });
