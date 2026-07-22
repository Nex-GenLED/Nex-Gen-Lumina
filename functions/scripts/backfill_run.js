#!/usr/bin/env node
//
// backfill_run.js — the REAL backfill (WRITES to Firestore). Idempotent.
//
// LOCAL usage (your machine, Application Default Credentials):
//   gcloud auth application-default login          # once
//   cd functions && npm run build && node scripts/backfill_run.js
//
// It calls the SAME exported planFleetBackfill the deployed callable uses, WITH
// the SAME exported makeBackfillWriter callback — so the writes here are
// byte-for-byte the deployed function's writes (no reimplementation). Each
// user's schedules are upserted to /users/{uid}/schedules/{sanitizedId}
// (sortKey = array index, wledPayload verbatim), then schedulesMigratedAt is
// stamped per user. Re-running is a no-op (existing sortKeys preserved).

const admin = require("firebase-admin");
const {
  planFleetBackfill,
  makeBackfillWriter,
} = require("../lib/backfillSchedulesSubcollection");

const PROJECT_ID = "icrt6menwsv2d8all8oijs021b06s5";

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  // WRITER callback supplied → this run writes.
  const r = await planFleetBackfill(
    db,
    { singleUid: null, pageSize: 200 },
    makeBackfillWriter(db),
  );

  console.log("======== backfillSchedulesSubcollection — REAL RUN ========");
  console.log(`users processed:                 ${r.usersProcessed}`);
  console.log(`users with a schedules array:    ${r.usersWithSchedules}`);
  console.log(`schedule docs CREATED (upserts): ${r.totalUpserts}`);
  console.log(`  (new docs planned:             ${r.totalNewDocs})`);
  console.log(
    `schedulesMigratedAt stamped:     ${r.usersWithSchedules}  (one per user with schedules)`,
  );
  console.log("DONE — real backfill complete");
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("backfill failed:", e && e.message ? e.message : e);
    process.exit(1);
  });
