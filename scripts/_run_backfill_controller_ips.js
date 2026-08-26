// _run_backfill_controller_ips.js
//
// Invokes the DEPLOYED backfillControllerIps callable (audit/COMMAND_SAFETY.md
// deploy steps 3-4). Untracked diag/ops script convention.
//
// AUTH NOTE — read before running. The callable requires a Firebase ID token
// carrying the `admin: true` custom claim. Verified 2026-08-01: **zero** of the
// 124 auth users hold that claim, so the callable (and its siblings
// backfillUserLocations / backfillUserDealerCodes, which use the same guard)
// is otherwise uninvokable.
//
// Rather than grant a persistent admin claim to a real production account, this
// mints a SHORT-LIVED custom token for a throwaway uid:
//   - admin.auth().createCustomToken(uid, {admin: true}) puts the claim in the
//     TOKEN ONLY. It does NOT write persistent customClaims on the user record.
//   - The token is exchanged for a 1-hour ID token, used once, and discarded.
//   - The throwaway auth user is DELETED at the end of the run.
// Net residue after a successful run: none.
//
// Usage:
//   node scripts/_run_backfill_controller_ips.js --dry
//   node scripts/_run_backfill_controller_ips.js --commit

'use strict';

const admin = require('firebase-admin');
const path = require('path');
const { resolveServiceAccountPath } = require('./_service_account');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const WEB_API_KEY = 'AIzaSyCWwqffD-ggRh5-IYwR2ldjaztd-Jgz0JY';
const FN_URL =
  `https://us-central1-${PROJECT_ID}.cloudfunctions.net/backfillControllerIps`;
const TOOL_UID = 'tool_backfill_controller_ips';

const SERVICE_ACCOUNT = resolveServiceAccountPath();

const args = process.argv.slice(2);
const DRY = args.includes('--dry');
const COMMIT = args.includes('--commit');
if (DRY === COMMIT) {
  console.error('Specify exactly one of --dry | --commit');
  process.exit(2);
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.cert(require(SERVICE_ACCOUNT)),
  });

  console.log(`Mode: ${DRY ? 'DRY RUN (writes nothing)' : 'COMMIT (writes)'}`);
  console.log(`Minting short-lived admin token for throwaway uid ${TOOL_UID}...`);

  const customToken = await admin
    .auth()
    .createCustomToken(TOOL_UID, { admin: true });

  const exchange = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );
  const exchanged = await exchange.json();
  if (!exchange.ok || !exchanged.idToken) {
    console.error('Token exchange failed:', JSON.stringify(exchanged, null, 2));
    process.exit(1);
  }
  console.log('ID token acquired.\n');

  let result;
  try {
    const resp = await fetch(FN_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${exchanged.idToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ data: { dryRun: DRY } }),
    });
    const text = await resp.text();
    if (!resp.ok) {
      console.error(`HTTP ${resp.status}:`);
      console.error(text);
      process.exitCode = 1;
    } else {
      result = JSON.parse(text).result;
      console.log('─'.repeat(64));
      console.log('  backfillControllerIps result');
      console.log('─'.repeat(64));
      console.log(JSON.stringify(result, null, 2));
      console.log('─'.repeat(64));
    }
  } finally {
    // Always clean up the throwaway principal, even on failure.
    try {
      await admin.auth().deleteUser(TOOL_UID);
      console.log(`\nCleaned up: deleted throwaway auth user ${TOOL_UID}`);
    } catch (e) {
      console.warn(
        `\nWARNING: could not delete ${TOOL_UID} — ${e.message}. ` +
          'Delete it manually; it holds no persistent claims but should not linger.',
      );
    }
  }

  process.exit(process.exitCode || 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
