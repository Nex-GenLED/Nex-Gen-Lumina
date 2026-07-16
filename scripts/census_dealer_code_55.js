// census_dealer_code_55.js
//
// READ-ONLY census: how many docs carry dealer_code "55"
// (DealerCode.masterReserved / staffAuth MASTER_DEALER_CODE, staffAuth.ts:119).
//
// Master installer/admin PINs mint dealerCode '55'. Installing a customer under
// such a PIN stamps '55' onto the customer's three linked docs, attributing
// them to the fleet-shared master scope where any master-PIN holder can read
// them. This counts the blast radius and lists the affected ids so a customer
// can be restamped to their real dealer.
//
// The RESTAMP UNIT is the three docs this prints per customer:
//   • users/{uid}.dealer_code                 (installer_setup_wizard.dart:962)
//   • installations/{id}.dealer_code          (:917)
//   • installation_records/{id}.dealer_code   (:1164)
//
// Writes nothing. Mirrors the scripts/_diag_* / backfill auth pattern.
//
// Usage:
//   node scripts/census_dealer_code_55.js --key=/path/to/service-account.json
//   # or: export GOOGLE_APPLICATION_CREDENTIALS=... && node scripts/census_dealer_code_55.js
//
// Gitignored outputs: none — this prints to stdout only.

const admin = require('firebase-admin');
const path = require('path');

const CODE = process.env.CENSUS_CODE || '55';

const keyArg = process.argv.find((a) => a.startsWith('--key='));
if (keyArg) {
  const creds = require(path.resolve(keyArg.slice('--key='.length)));
  admin.initializeApp({ credential: admin.credential.cert(creds) });
} else {
  admin.initializeApp({ credential: admin.credential.applicationDefault() });
}
const db = admin.firestore();

async function countCollection(col, field) {
  const snap = await db.collection(col).where(field, '==', CODE).get();
  console.log(`\n${col}: ${snap.size} doc(s) with ${field}="${CODE}"`);
  snap.forEach((d) => {
    const x = d.data();
    const label =
      x.email || x.primary_user_email || x.primary_user_id || x.customer_id || '';
    console.log(`  ${d.id}  ${label}`);
  });
  return snap.size;
}

(async () => {
  const summary = {};
  for (const [col, field] of [
    ['users', 'dealer_code'],
    ['installations', 'dealer_code'],
    ['installation_records', 'dealer_code'],
  ]) {
    summary[col] = await countCollection(col, field);
  }

  console.log('\n== SUMMARY ==');
  console.log(JSON.stringify(summary, null, 2));
  console.log(
    `\nusers = customers attributed to the shared master code "${CODE}". ` +
      'Each customer needs all three docs above restamped together to move ' +
      'them to their real dealer.'
  );
  process.exit(0);
})().catch((e) => {
  console.error('census failed:', e);
  process.exit(1);
});
