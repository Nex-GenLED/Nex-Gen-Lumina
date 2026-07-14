#!/usr/bin/env node
//
// repair_array_sortkeys.js — RAMP-BLOCKER REPAIR.
//
// The array→subcollection backfill stamped `sortKey` onto the SUBCOLLECTION docs
// only. The matching legacy `schedules` ARRAY items still lack the field, so they
// deserialize to sortKey 0 (ScheduleItem.fromJson: `?? 0`). Consequence:
// SchedulesNotifier._assignSortKeys computes nextKey = max(0,0,..)+1 = 1 for an
// array-path add and mirrors sortKey=1 into a subcollection that ALREADY holds a
// backfilled sortKey=1 → collision → orderBy('sortKey') tie → the subcollection's
// read order diverges from the array's insertion order on any later flip.
// `schedulesMigratedAt` makes the lazy migrator skip these users permanently, so
// nothing self-heals this.
//
// FIX: make the array agree with the subcollection — stamp each array item with
// the SAME sortKey its matching subcollection doc already carries. The
// subcollection is the future source of truth, so it is never renumbered.
//
// SAFETY
//   • DRY RUN BY DEFAULT. Pass --confirm to write.
//   • Transactional per user: the array is a single field, so it must be
//     read-modify-written atomically or a concurrent client write is clobbered
//     (the known non-transactional array race).
//   • Only the `sortKey` field is touched; every other field on every item is
//     passed through byte-for-byte.
//   • Any item that cannot be matched 1:1 is SKIPPED and the whole user is left
//     untouched — a skip is a STOP-and-review, never a silent partial write.
//   • Idempotent: a user whose array sortKeys already equal the sub's is a no-op.
//
// Usage:
//   cd functions && node scripts/repair_array_sortkeys.js            # dry run
//   cd functions && node scripts/repair_array_sortkeys.js --confirm  # write

const admin = require("firebase-admin");

const PROJECT_ID = "icrt6menwsv2d8all8oijs021b06s5";
const CONFIRM = process.argv.includes("--confirm");
const MIGRATED_MARKER = "schedulesMigratedAt";

const subDocId = (id) => (id.includes("/") ? id.replace(/\//g, "_") : id);

/**
 * Plan one user's repair. Pure: reads nothing, writes nothing.
 * Returns { action: 'noop'|'repair'|'skip', reasons: [], rows: [], newArray }
 */
function planUser(arr, subDocs) {
  const reasons = [];
  const bySubId = new Map(subDocs.map((d) => [d.id, d.data]));

  // Guard: duplicate ids in the array make a 1:1 match impossible.
  const seen = new Set();
  for (const item of arr) {
    if (typeof item?.id !== "string" || item.id.length === 0) {
      reasons.push(`array item with missing/non-string id: ${JSON.stringify(item?.id)}`);
      continue;
    }
    if (seen.has(item.id)) reasons.push(`duplicate array id: ${item.id}`);
    seen.add(item.id);
  }

  if (arr.length !== subDocs.length) {
    reasons.push(`count mismatch: array=${arr.length} sub=${subDocs.length}`);
  }

  const rows = [];
  const matchedSubIds = new Set();
  const newArray = [];

  for (let i = 0; i < arr.length; i++) {
    const item = arr[i];
    if (typeof item?.id !== "string" || item.id.length === 0) {
      newArray.push(item);
      continue;
    }
    const docId = subDocId(item.id);
    const sub = bySubId.get(docId);
    if (!sub) {
      reasons.push(`array[${i}] id=${item.id} has NO matching subcollection doc`);
      newArray.push(item);
      continue;
    }
    matchedSubIds.add(docId);
    const sk = sub.sortKey;
    if (!Number.isInteger(sk)) {
      reasons.push(`array[${i}] id=${item.id}: sub sortKey missing/non-int (${JSON.stringify(sk)})`);
      newArray.push(item);
      continue;
    }
    rows.push({ index: i, id: item.id, from: item.sortKey, to: sk });
    // Touch ONLY sortKey; everything else passes through untouched.
    newArray.push({ ...item, sortKey: sk });
  }

  for (const d of subDocs) {
    if (!matchedSubIds.has(d.id)) {
      reasons.push(`ORPHAN subcollection doc (no array item): ${d.id}`);
    }
  }

  if (reasons.length > 0) return { action: "skip", reasons, rows, newArray: null };

  const changed = rows.some((r) => r.from !== r.to);
  return {
    action: changed ? "repair" : "noop",
    reasons,
    rows,
    newArray: changed ? newArray : null,
  };
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  console.log("=".repeat(72));
  console.log(`repair_array_sortkeys — ${CONFIRM ? "*** CONFIRM (WRITING) ***" : "DRY RUN (writes nothing)"}`);
  console.log(`project: ${PROJECT_ID}`);
  console.log("=".repeat(72));

  const usersSnap = await db.collection("users").get();
  let considered = 0;
  let repaired = 0;
  let noop = 0;
  let skipped = 0;
  let itemsStamped = 0;

  for (const doc of usersSnap.docs) {
    const d = doc.data() || {};
    if (!d[MIGRATED_MARKER]) continue; // only users the backfill has touched
    const arr = Array.isArray(d.schedules) ? d.schedules : [];
    const subSnap = await doc.ref.collection("schedules").get();
    const subDocs = subSnap.docs.map((s) => ({ id: s.id, data: s.data() }));
    if (arr.length === 0 && subDocs.length === 0) continue;
    considered++;

    const plan = planUser(arr, subDocs);
    console.log(`\n--- ${doc.id} (${d.email || "?"}) array=${arr.length} sub=${subDocs.length} → ${plan.action.toUpperCase()}`);

    for (const r of plan.rows) {
      const mark = r.from === r.to ? "=" : "→";
      console.log(`    array[${r.index}]  ${r.id}  sortKey ${r.from === undefined ? "ABSENT" : r.from} ${mark} ${r.to}`);
    }

    if (plan.action === "skip") {
      skipped++;
      console.log("    !! SKIPPED — STOP AND REVIEW:");
      plan.reasons.forEach((x) => console.log(`       - ${x}`));
      continue;
    }
    if (plan.action === "noop") {
      noop++;
      console.log("    already in sync — no write");
      continue;
    }

    repaired++;
    itemsStamped += plan.rows.filter((r) => r.from !== r.to).length;

    if (!CONFIRM) continue;

    // Transactional RMW: re-read inside the txn and re-plan against the CURRENT
    // array so a concurrent client write is never clobbered.
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const freshArr = Array.isArray((fresh.data() || {}).schedules)
        ? fresh.data().schedules
        : [];
      const freshPlan = planUser(freshArr, subDocs);
      if (freshPlan.action !== "repair") {
        console.log(`    (txn) array changed under us → ${freshPlan.action}; leaving untouched`);
        return;
      }
      tx.update(doc.ref, { schedules: freshPlan.newArray });
    });
    console.log("    WROTE (transactional)");
  }

  console.log("\n" + "=".repeat(72));
  console.log(`users considered (have ${MIGRATED_MARKER}): ${considered}`);
  console.log(`  repair needed: ${repaired}   (items stamped: ${itemsStamped})`);
  console.log(`  already in sync (noop): ${noop}`);
  console.log(`  SKIPPED (review): ${skipped}`);
  console.log(CONFIRM ? "WRITES COMMITTED" : "DRY RUN — 0 writes. Re-run with --confirm to apply.");
  if (skipped > 0) {
    console.log("\n!! One or more users were SKIPPED. Review before ramping the rollout.");
    process.exitCode = 2;
  }
}

main()
  .then(() => process.exit(process.exitCode || 0))
  .catch((e) => {
    console.error("repair failed:", e && e.message ? e.message : e);
    process.exit(1);
  });
