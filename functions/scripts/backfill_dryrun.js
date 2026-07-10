#!/usr/bin/env node
//
// backfill_dryrun.js — WRITE-NOTHING dry run of backfillSchedulesSubcollection.
//
// LOCAL usage (your machine, using Application Default Credentials):
//   gcloud auth application-default login          # once
//   cd functions && node scripts/backfill_dryrun.js
//   (if functions/lib is absent/stale, run `npm run build` first — this script
//    imports the COMPILED shared planner from ../lib.)
//
// It calls the SAME exported planFleetBackfill that the deployed
// backfillSchedulesSubcollection callable uses (required below) — it does NOT
// reimplement any planning logic, so the numbers it previews match a real run
// exactly. planFleetBackfill writes nothing on its own, and this script passes
// NO writer callback, so there is NO .set()/.update()/.commit() anywhere in
// this script's path: a Firestore write is structurally impossible here.

const admin = require("firebase-admin");
const { planFleetBackfill } = require("../lib/backfillSchedulesSubcollection");

const PROJECT_ID = "icrt6menwsv2d8all8oijs021b06s5";
const SAMPLE_USERS = 3;

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  // No writer callback → read-only; dryRun by construction.
  const r = await planFleetBackfill(db, { singleUid: null, pageSize: 200 });

  // planFleetBackfill only pushes a perUser entry for users WITH a schedules[].
  const users = r.perUser;

  console.log("======== backfillSchedulesSubcollection — DRY RUN (batch mode) ========");
  console.log(`users scanned:                        ${r.usersProcessed}`);
  console.log(`users WITH a schedules array:         ${r.usersWithSchedules}`);
  console.log(`schedule docs that WOULD be created:  ${r.totalNewDocs}`);

  // sortKey spot-check — first N users, schedule id (array order) -> sortKey.
  console.log(
    `\n--- sortKey spot-check (first ${SAMPLE_USERS} users) — id (array order) -> assigned sortKey (expect 0,1,2,...) ---`,
  );
  if (users.length === 0) console.log("    (no users with schedules)");
  for (const u of users.slice(0, SAMPLE_USERS)) {
    console.log(
      `  user ${u.uid}  (array=${u.arrayCount} new=${u.newCount} existing=${u.existingCount} migratedAlready=${u.migratedAlready})`,
    );
    for (const a of u.sortKeyAssignments) {
      console.log(`      ${a.docId} -> ${a.sortKey}`);
    }
    if (u.arrayCount > u.sortKeyAssignments.length) {
      console.log(
        `      … (+${u.arrayCount - u.sortKeyAssignments.length} more; sample capped)`,
      );
    }
  }

  // Malformed / skipped items, WITH the reason the planner flagged each one.
  const totalSkipped = users.reduce((n, u) => n + u.skippedMalformed, 0);
  console.log(`\n--- malformed / skipped items: ${totalSkipped} total ---`);
  if (totalSkipped === 0) console.log("    none");
  for (const u of users) {
    for (const d of u.skippedDetails) {
      console.log(`    user ${u.uid}  array[${d.index}]: ${d.reason}`);
    }
  }

  // Prior-run indicator: any user already carrying schedulesMigratedAt.
  console.log(
    `\n--- users already carrying schedulesMigratedAt (prior-run indicator): ${r.usersAlreadyMigrated} ---`,
  );
  const already = users.filter((u) => u.migratedAlready).map((u) => u.uid);
  if (already.length === 0) console.log("    none (expected on a first run)");
  else already.forEach((uid) => console.log(`    ${uid}`));

  console.log("\nDRY RUN — 0 writes");
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("dry-run failed:", e && e.message ? e.message : e);
    process.exit(1);
  });
