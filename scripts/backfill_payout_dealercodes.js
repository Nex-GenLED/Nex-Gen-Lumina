#!/usr/bin/env node
/**
 * backfill_payout_dealercodes.js
 *
 * One-shot operational script to populate the new `dealerCode` field
 * on existing /referral_payouts documents that predate the model
 * change in commit 3bbb6da. Idempotent — running it twice in a row
 * results in zero writes on the second run.
 *
 * Why: firestore.rules `hasStaffClaim()` scopes payout reads by the
 * caller's `dealerCode` claim. Until every payout doc carries a
 * dealerCode field, the rule branch can't authorize staff sessions
 * to read those legacy docs.
 *
 * Source of truth for dealerCode is the linked sales_job:
 *   referral_payouts/{id}.jobId  →  sales_jobs/{jobId}.dealerCode
 *
 * -------------------------------------------------------------------
 * SETUP
 * -------------------------------------------------------------------
 * 1. Firebase Console → Project Settings → Service accounts →
 *    "Generate new private key". Save the JSON somewhere OUTSIDE the
 *    repo (it grants admin access to Firestore and Auth).
 *
 * 2. Make the credentials available in one of two ways:
 *
 *      a. Environment variable (recommended):
 *         export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *
 *      b. CLI flag:
 *         --key=/path/to/service-account.json
 *
 * 3. DRY RUN (default — safe, no writes):
 *      node scripts/backfill_payout_dealercodes.js
 *      node scripts/backfill_payout_dealercodes.js --limit=5
 *
 * 4. APPLY backfill (irreversible — writes dealerCode field on docs):
 *      node scripts/backfill_payout_dealercodes.js --commit
 *      node scripts/backfill_payout_dealercodes.js --commit --limit=5
 *
 * Target project: icrt6menwsv2d8all8oijs021b06s5
 *
 * Output categories per payout:
 *   skipped (already has dealerCode)
 *   would update / updated
 *   ORPHAN     — payout.jobId references a missing sales_job
 *   MALFORMED  — sales_job exists but has no dealerCode field
 * -------------------------------------------------------------------
 */

'use strict';

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const BATCH_SIZE = 500; // Firestore batched-write maximum per commit

// ── Args ───────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = { dryRun: true, keyPath: null, limit: null };
  for (const a of argv.slice(2)) {
    if (a === '--commit') {
      args.dryRun = false;
    } else if (a === '--dry-run') {
      args.dryRun = true;
    } else if (a.startsWith('--limit=')) {
      const n = parseInt(a.slice('--limit='.length), 10);
      if (Number.isNaN(n) || n <= 0) {
        console.error(`Invalid --limit value: ${a}`);
        process.exit(1);
      }
      args.limit = n;
    } else if (a.startsWith('--key=')) {
      args.keyPath = a.slice('--key='.length);
    } else if (a === '--help' || a === '-h') {
      console.log(
        'Usage: node scripts/backfill_payout_dealercodes.js [--commit] [--dry-run] [--limit=N] [--key=PATH]\n' +
          '\n' +
          '  --commit     Apply writes. Default is dry-run.\n' +
          '  --dry-run    Explicit dry run (default).\n' +
          '  --limit=N    Stop after processing N payouts (testing).\n' +
          '  --key=PATH   Path to service-account JSON. Alternatively set\n' +
          '               GOOGLE_APPLICATION_CREDENTIALS in the environment.\n'
      );
      process.exit(0);
    } else {
      console.error(`Unknown argument: ${a}`);
      process.exit(1);
    }
  }
  return args;
}

function prefix(dryRun) {
  return dryRun ? '[DRY RUN] ' : '';
}

// ── Init ───────────────────────────────────────────────────────────────────

function initializeAdmin(keyPath) {
  if (admin.apps.length > 0) return; // already initialized
  if (keyPath) {
    const resolved = path.resolve(keyPath);
    const serviceAccount = require(resolved);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: PROJECT_ID,
    });
    console.log(`Initialized with key: ${resolved}`);
    return;
  }
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      'No credentials configured. Either pass --key=PATH or set\n' +
        'GOOGLE_APPLICATION_CREDENTIALS in the environment.'
    );
    process.exit(1);
  }
  admin.initializeApp({ projectId: PROJECT_ID });
  console.log(
    `Initialized with GOOGLE_APPLICATION_CREDENTIALS=${process.env.GOOGLE_APPLICATION_CREDENTIALS}`
  );
}

// ── Core ───────────────────────────────────────────────────────────────────

/**
 * Read sales_jobs/{jobId} and return its dealerCode (string or null).
 * Returns the sentinel { missing: true } if the doc doesn't exist so
 * the caller can categorize ORPHAN vs MALFORMED.
 */
async function lookupJobDealerCode(db, jobId, jobCache) {
  if (jobCache.has(jobId)) {
    return jobCache.get(jobId);
  }
  const snap = await db.collection('sales_jobs').doc(jobId).get();
  if (!snap.exists) {
    const result = { missing: true };
    jobCache.set(jobId, result);
    return result;
  }
  const dealerCode = snap.data() && snap.data().dealerCode;
  const result =
    typeof dealerCode === 'string' && dealerCode.length > 0
      ? { missing: false, dealerCode }
      : { missing: false, dealerCode: null };
  jobCache.set(jobId, result);
  return result;
}

async function backfill(args) {
  const db = admin.firestore();

  console.log(
    `\n${prefix(args.dryRun)}Scanning referral_payouts collection${
      args.limit ? ` (limit=${args.limit})` : ''
    }...\n`
  );

  const stats = {
    scanned: 0,
    skipped: 0,
    wouldUpdate: 0,
    updated: 0,
    orphans: 0,
    malformed: 0,
  };

  // jobId → { missing, dealerCode } cache so we don't re-fetch the same
  // sales_job for every payout that references it.
  const jobCache = new Map();

  let batch = db.batch();
  let pendingInBatch = 0;

  // No orderBy / pagination needed for typical dev-scale collections.
  // For production use consider streaming with .stream() if the
  // collection grows past ~10k docs, but for now a single .get() is
  // simpler and atomic w.r.t. concurrent writes during the run.
  const allSnap = await db.collection('referral_payouts').get();

  for (const doc of allSnap.docs) {
    if (args.limit && stats.scanned >= args.limit) break;
    stats.scanned++;

    const data = doc.data() || {};
    const existing = data.dealerCode;
    if (typeof existing === 'string' && existing.length > 0) {
      stats.skipped++;
      console.log(
        `  skipped (already has dealerCode=${existing}): payout ${doc.id}`
      );
      continue;
    }

    const jobId = data.jobId;
    if (typeof jobId !== 'string' || jobId.length === 0) {
      stats.orphans++;
      console.warn(
        `  ORPHAN: payout ${doc.id} has no jobId field, skipping`
      );
      continue;
    }

    const jobLookup = await lookupJobDealerCode(db, jobId, jobCache);
    if (jobLookup.missing) {
      stats.orphans++;
      console.warn(
        `  ORPHAN: payout ${doc.id} references missing job ${jobId}, skipping`
      );
      continue;
    }
    if (!jobLookup.dealerCode) {
      stats.malformed++;
      console.warn(
        `  MALFORMED: job ${jobId} has no dealerCode field (referenced by payout ${doc.id}), skipping`
      );
      continue;
    }

    if (args.dryRun) {
      stats.wouldUpdate++;
      console.log(
        `  ${prefix(args.dryRun)}would update payout ${doc.id} -> dealerCode=${jobLookup.dealerCode}`
      );
    } else {
      batch.update(doc.ref, { dealerCode: jobLookup.dealerCode });
      pendingInBatch++;
      stats.updated++;
      console.log(
        `  updating payout ${doc.id} -> dealerCode=${jobLookup.dealerCode}`
      );

      if (pendingInBatch >= BATCH_SIZE) {
        await batch.commit();
        console.log(`  [batch committed: ${pendingInBatch} writes]`);
        batch = db.batch();
        pendingInBatch = 0;
      }
    }
  }

  if (!args.dryRun && pendingInBatch > 0) {
    await batch.commit();
    console.log(`  [final batch committed: ${pendingInBatch} writes]`);
  }

  // ── Summary ───────────────────────────────────────────────────────────
  console.log(
    `\n${prefix(args.dryRun)}Summary:\n` +
      `  Total payouts scanned:                 ${stats.scanned}\n` +
      `  Skipped (already had dealerCode):      ${stats.skipped}\n` +
      `  ${args.dryRun ? 'Would update' : 'Updated      '}:                          ${
        args.dryRun ? stats.wouldUpdate : stats.updated
      }\n` +
      `  ORPHAN (missing job ref):              ${stats.orphans}\n` +
      `  MALFORMED (job has no dealerCode):     ${stats.malformed}\n`
  );

  if (args.dryRun) {
    console.log('Dry run complete. To apply, re-run with --commit.');
  } else {
    console.log('Backfill complete.');
  }
}

// ── Entry point ────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  initializeAdmin(args.keyPath);
  try {
    await backfill(args);
  } catch (err) {
    console.error(`\nFatal: ${err && err.stack ? err.stack : err}`);
    process.exit(1);
  }
  process.exit(0);
}

main();
