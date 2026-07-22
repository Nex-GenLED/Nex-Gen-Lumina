#!/usr/bin/env node
/**
 * cleanup_orphaned_users.js
 *
 * One-time Firestore cleanup: remove /users/{uid} documents (and their
 * subcollections) for UIDs that no longer exist in Firebase Auth. This
 * happens when anonymous users are purged but their Firestore data is
 * left behind.
 *
 * -------------------------------------------------------------------
 * SETUP
 * -------------------------------------------------------------------
 * 1. Firebase Console → Project Settings → Service accounts →
 *    "Generate new private key". Save the downloaded JSON somewhere
 *    outside the repo (or at least outside source control — it grants
 *    admin access to Firestore and Auth).
 *
 * 2. From the project root (where firebase-admin is already installed
 *    via package.json), make the credentials available in one of two
 *    ways:
 *
 *      a. Environment variable (recommended):
 *         export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *
 *      b. CLI flag:
 *         --key=/path/to/service-account.json
 *
 * 3. DRY RUN (default — safe, no writes):
 *      node scripts/cleanup_orphaned_users.js
 *
 * 4. APPLY deletions (irreversible):
 *      node scripts/cleanup_orphaned_users.js --confirm
 *
 * Target project: icrt6menwsv2d8all8oijs021b06s5
 * -------------------------------------------------------------------
 */

'use strict';

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';

const USERS_PAGE_SIZE = 200;

function parseArgs(argv) {
  const args = { dryRun: true, keyPath: null };
  for (const a of argv.slice(2)) {
    if (a === '--confirm') {
      args.dryRun = false;
    } else if (a === '--dry-run') {
      args.dryRun = true;
    } else if (a.startsWith('--key=')) {
      args.keyPath = a.slice('--key='.length);
    } else if (a === '--help' || a === '-h') {
      console.log(
        'Usage: node scripts/cleanup_orphaned_users.js [--confirm] [--dry-run] [--key=<path>]\n' +
          '\n' +
          '  --confirm    Apply deletions. Without this, runs in dry-run mode.\n' +
          '  --dry-run    Explicit dry run (default).\n' +
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

function isProtected(data) {
  if (!data) return false;
  const email = data.email;
  if (typeof email === 'string' && email.trim().length > 0) return true;
  const role = data.role;
  if (typeof role === 'string' && role.trim().length > 0) return true;
  return false;
}

async function main() {
  const { dryRun, keyPath } = parseArgs(process.argv);

  if (keyPath) {
    const absPath = path.resolve(keyPath);
    const creds = require(absPath);
    admin.initializeApp({
      credential: admin.credential.cert(creds),
      projectId: PROJECT_ID,
    });
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
    });
  } else {
    console.error(
      'No credentials found. Set GOOGLE_APPLICATION_CREDENTIALS or pass --key=<path>.'
    );
    process.exit(1);
  }

  const firestore = admin.firestore();
  const auth = admin.auth();

  console.log(
    `${prefix(dryRun)}Starting orphaned-user cleanup for project ${PROJECT_ID}`
  );
  if (dryRun) {
    console.log(
      'Dry run: no writes will occur. Re-run with --confirm to apply.'
    );
  }

  const usersCol = firestore.collection('users');
  let cursor = null;
  let scanned = 0;
  let orphansDeleted = 0;
  let protectedSkipped = 0;
  let lookupErrors = 0;

  while (true) {
    let q = usersCol
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(USERS_PAGE_SIZE);
    if (cursor) q = q.startAfter(cursor);

    const page = await q.get();
    if (page.empty) break;

    for (const docSnap of page.docs) {
      scanned++;
      const uid = docSnap.id;
      const data = docSnap.data();

      let orphaned = false;
      try {
        await auth.getUser(uid);
      } catch (e) {
        if (e && e.code === 'auth/user-not-found') {
          orphaned = true;
        } else {
          lookupErrors++;
          console.error(
            `Auth lookup failed for ${uid} (${e?.code || e?.message}); leaving doc untouched.`
          );
          continue;
        }
      }

      if (!orphaned) continue;

      if (isProtected(data)) {
        console.log(`${prefix(dryRun)}Protected account skipped: ${uid}`);
        protectedSkipped++;
        continue;
      }

      console.log(`${prefix(dryRun)}Deleting orphaned user: ${uid}`);

      const userRef = usersCol.doc(uid);

      // Enumerate subcollections so we can log what's being (or would be)
      // removed. recursiveDelete walks everything regardless of name, but
      // we keep the per-subcollection log lines the spec defines.
      let subcollections = [];
      try {
        subcollections = await userRef.listCollections();
      } catch (e) {
        console.error(
          `Failed to list subcollections for ${uid}: ${e.message}`
        );
      }

      for (const colRef of subcollections) {
        try {
          const countSnap = await colRef.count().get();
          const n = countSnap.data().count;
          if (n > 0) {
            console.log(
              `${prefix(dryRun)}Deleted subcollection ${colRef.id} for ${uid} (${n} docs)`
            );
          }
        } catch (e) {
          console.error(
            `Failed to count subcollection ${colRef.id} for ${uid}: ${e.message}`
          );
        }
      }

      if (!dryRun) {
        try {
          // recursiveDelete sweeps every subcollection (known or not) and
          // removes the parent doc in one call.
          await firestore.recursiveDelete(userRef);
        } catch (e) {
          console.error(`Failed to delete user ${uid}: ${e.message}`);
          continue;
        }
      }
      orphansDeleted++;
    }

    if (page.size < USERS_PAGE_SIZE) break;
    cursor = page.docs[page.docs.length - 1];
  }

  console.log(
    `${prefix(dryRun)}Complete: ${orphansDeleted} orphaned users cleaned up ` +
      `(${scanned} scanned, ${protectedSkipped} protected, ${lookupErrors} lookup errors)`
  );
}

main().catch((e) => {
  console.error('Cleanup failed:', e);
  process.exit(1);
});
