// scripts/wipe_test_neighborhoods.js
//
// ONE-TIME cleanup for the neighborhood outage: ALL existing neighborhood
// groups are test data with no real users, so this wipes them entirely and
// clears the only server-side per-user pointer into them.
//
// WHAT IT DELETES
//   1. Every neighborhoods/{groupId} doc AND all its subcollections
//      (Firestore does NOT cascade-delete subcollections). recursiveDelete
//      handles the whole tree, including the NESTED members/{uid}/settings
//      subcollection. Subcollections observed in code:
//        members (+ members/{uid}/settings), commands, schedules, syncEvents,
//        syncSessions, game_day_autopilot, rate_limits.
//   2. Every users/{uid}/handoff/current doc — the server-side handoff pointer
//      (neighborhood_service.dart:292 / sync_handoff_manager.dart:746). Left
//      behind it would reference now-deleted groups.
//
// WHAT IT DOES **NOT** (and cannot) TOUCH — device-local only, cleared by the
// app-guard code changes, not by this admin script:
//   • activeNeighborhoodIdProvider — in-memory StateProvider (defaults null;
//     resets on restart; resolveAutoActiveGroupId now returns null for a
//     non-member/stale id so it never re-activates a wiped group).
//   • SharedPreferences: sync_handoff_state, _syncGroupId, previous_group_ids /
//     prev_group_name_* / prev_group_code_* (harmless "recent crews" hints;
//     rejoining a deleted group just fails).
//
// SAFETY: DRY-RUN by default (counts only, no writes). Pass --confirm to delete.
//
// Usage:
//   node scripts/wipe_test_neighborhoods.js \
//     --key=android/app/icrt6menwsv2d8all8oijs021b06s5-firebase-adminsdk-fbsvc-2e0cb54335.json
//   (dry run — reports what WOULD be deleted)
//
//   node scripts/wipe_test_neighborhoods.js --key=<path> --confirm
//   (actually deletes)

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';

function parseArgs(argv) {
  const args = { keyPath: null, confirm: false };
  for (const a of argv.slice(2)) {
    if (a.startsWith('--key=')) args.keyPath = a.slice('--key='.length);
    else if (a === '--confirm') args.confirm = true;
  }
  return args;
}

function initFirebase(keyPath) {
  if (keyPath) {
    const creds = require(path.resolve(keyPath));
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
      'No credentials. Pass --key=<path> or set GOOGLE_APPLICATION_CREDENTIALS.'
    );
    process.exit(1);
  }
}

async function main() {
  const args = parseArgs(process.argv);
  initFirebase(args.keyPath);
  const db = admin.firestore();

  const mode = args.confirm ? 'DELETE' : 'DRY-RUN (no writes)';
  console.log(`wipe_test_neighborhoods — mode: ${mode}`);

  // ── 1. Neighborhood groups + all subcollections ──────────────────────────
  const groupDocs = await db.collection('neighborhoods').listDocuments();
  console.log(`neighborhoods/: ${groupDocs.length} group(s)`);
  for (const g of groupDocs) {
    const subs = await g.listCollections();
    console.log(
      `  - ${g.id}  subcollections: [${subs.map((c) => c.id).join(', ')}]`
    );
  }

  // ── 2. Stale server-side handoff pointers ────────────────────────────────
  // collectionGroup catches every users/{uid}/handoff/* doc in one query.
  const handoffSnap = await db.collectionGroup('handoff').get();
  console.log(`users/*/handoff/*: ${handoffSnap.size} doc(s)`);

  if (!args.confirm) {
    console.log(
      '\nDRY-RUN complete. Re-run with --confirm to delete the above.'
    );
    return;
  }

  // recursiveDelete removes a doc and ALL descendant subcollections (incl.
  // the nested members/{uid}/settings). Passing the collection deletes every
  // group tree under it.
  console.log('\nDeleting neighborhoods/* recursively...');
  await db.recursiveDelete(db.collection('neighborhoods'));
  console.log('  neighborhoods/* deleted.');

  console.log('Deleting stale users/*/handoff/* pointers...');
  let deleted = 0;
  const batchSize = 400;
  let batch = db.batch();
  for (const doc of handoffSnap.docs) {
    batch.delete(doc.ref);
    deleted++;
    if (deleted % batchSize === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (deleted % batchSize !== 0) await batch.commit();
  console.log(`  ${deleted} handoff pointer(s) deleted.`);

  console.log('\nWipe complete.');
}

main().catch((e) => {
  console.error('wipe failed:', e);
  process.exit(1);
});
