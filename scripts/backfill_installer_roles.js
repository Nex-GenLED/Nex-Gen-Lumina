#!/usr/bin/env node
//
// backfill_installer_roles.js — stamp `role` onto legacy /installers docs.
//
// ⚠️⚠️ DO NOT RUN THIS YET. IT IS HALF OF A PAIRED CHANGE. ⚠️⚠️
//
// ── WHY IT IS GATED ───────────────────────────────────────────────────────
//
// mintStaffToken rejects any installers doc whose `role` !== roleForMode(mode):
//
//     const docRole = data.role as string | undefined;
//     if (docRole !== roleForMode(mode)) return null;   // staffAuth.ts:356-357
//
// A missing `role` is a mismatch. So every installer created by the admin UI
// (InstallerInfo.toMap() never emitted `role` before C4) is permanently unable
// to authenticate. That is a real bug — it is why a second dealer cannot be
// onboarded today, and why the only working staff auth is the four master PINs
// (all hardwired to MASTER_DEALER_CODE '55').
//
// BUT that same bug is currently the ONLY thing preventing a full staff-auth
// compromise:
//
//     /installers/{installerId}
//       allow read: if request.auth != null;      // firestore.rules ~:817
//
// Any authenticated session — including an anonymous one — can list every
// installer doc in the fleet. Those docs store `fullPin` in CLEARTEXT
// (installer_providers.dart, InstallerInfo.toMap → 'fullPin'). So an attacker
// can already read every staff PIN in the system. Today those PINs fail at
// staffAuth.ts:357 for lack of a `role`.
//
// >>> RUNNING THIS BACKFILL REMOVES THAT ACCIDENTAL PROTECTION. <<<
// >>> It turns a readable list of PINs into a working set of staff logins. <<<
//
// ── THE PAIRING REQUIREMENT ───────────────────────────────────────────────
//
// This script may ONLY be run as part of the D3 retrofit deploy, in this
// order, as a single operation:
//
//   1. D3 tightens /installers read from `request.auth != null` to
//      hasAdminOrOwnerClaim()  (firestore.rules ~:817)
//   2. D3's rules are DEPLOYED and VERIFIED LIVE via the Rules API
//      (a `firebase deploy` reporting success is NOT proof — it will happily
//      ship the wrong file; check the live ruleset source)
//   3. ONLY THEN: node scripts/backfill_installer_roles.js --confirm
//
// Running it before step 2 opens the vector. Running the rules change without
// this backfill leaves dealer #2 unable to onboard. They ship together.
//
// Ideally D3 also stops storing fullPin in cleartext, which removes the
// dependency entirely. Until then, the ordering above is load-bearing.
//
// ── WHAT IT DOES ──────────────────────────────────────────────────────────
//
// Infers each doc's role and stamps it. Inference, in priority order:
//   1. an explicit, VALID existing `role`     → leave untouched (idempotent)
//   2. an explicit `role` that is unrecognized → SKIP + report (never guess
//      over a human's intent)
//   3. no role                                 → 'installer' (the default and
//      the least-privileged of the three)
//
// It deliberately does NOT infer 'admin' or 'salesperson' from doc-id or name
// heuristics. Promoting someone to admin is a privilege decision, not a
// migration decision — those must be set deliberately via the staff-management
// UI. Every doc this script touches becomes the LEAST-privileged role.
//
// SAFETY
//   • DRY RUN BY DEFAULT. Pass --confirm to write.
//   • Only the `role` field is written; every other field is untouched.
//   • Idempotent: a doc with a valid role is a no-op.
//   • Unrecognized roles are SKIPPED and reported — a skip is a
//     STOP-and-review, never a silent overwrite.
//   • Per-doc update (no transaction needed — single scalar field, no
//     read-modify-write race).
//
// Usage:
//   node scripts/backfill_installer_roles.js              # dry run (safe)
//   node scripts/backfill_installer_roles.js --confirm    # WRITE — gated, see above

const admin = require("firebase-admin");

const PROJECT_ID = "icrt6menwsv2d8all8oijs021b06s5";
const CONFIRM = process.argv.includes("--confirm");
const ACK = process.argv.includes("--i-have-deployed-d3-rules");

// Mirrors StaffRole (staffAuth.ts:148) minus 'owner', which is master-only
// (staffAuth.ts:212) and can never come from an installers doc.
const VALID_ROLES = ["salesperson", "installer", "admin"];
const DEFAULT_ROLE = "installer";

async function main() {
  if (CONFIRM && !ACK) {
    console.error(
      [
        "",
        "REFUSING TO WRITE.",
        "",
        "This backfill is the second half of a paired change. Running it before",
        "the D3 rules are LIVE turns the cleartext fullPin list at",
        "/installers (readable by any authenticated session via",
        "`allow read: if request.auth != null`) into a working set of staff",
        "logins. The missing `role` field is currently the only thing stopping",
        "that.",
        "",
        "Required order:",
        "  1. D3 tightens /installers read to hasAdminOrOwnerClaim()",
        "  2. Deploy AND verify live via the Rules API (deploy success is not",
        "     proof — confirm the live ruleset source actually contains it)",
        "  3. then re-run with:",
        "     node scripts/backfill_installer_roles.js --confirm --i-have-deployed-d3-rules",
        "",
      ].join("\n"),
    );
    process.exit(2);
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  const snap = await db.collection("installers").get();

  const plan = { stamp: [], alreadyValid: [], skipped: [] };

  for (const doc of snap.docs) {
    const data = doc.data();
    const raw = data.role;

    if (typeof raw === "string" && VALID_ROLES.includes(raw)) {
      plan.alreadyValid.push({ id: doc.id, role: raw });
      continue;
    }
    if (raw !== undefined && raw !== null && raw !== "") {
      plan.skipped.push({ id: doc.id, role: raw, why: "unrecognized role" });
      continue;
    }
    plan.stamp.push({
      id: doc.id,
      fullPin: data.fullPin ?? "(none)",
      dealerCode: data.dealerCode ?? "(none)",
      name: data.name ?? "(unnamed)",
      to: DEFAULT_ROLE,
    });
  }

  console.log("\n════════ INSTALLER ROLE BACKFILL ════════");
  console.log(`mode    : ${CONFIRM ? "WRITE (--confirm)" : "DRY RUN"}`);
  console.log(`project : ${PROJECT_ID}`);
  console.log(`docs    : ${snap.size}\n`);

  console.log(`already valid (no-op) : ${plan.alreadyValid.length}`);
  for (const d of plan.alreadyValid) console.log(`   ${d.id}  role=${d.role}`);

  console.log(`\nwould stamp -> '${DEFAULT_ROLE}' : ${plan.stamp.length}`);
  for (const d of plan.stamp) {
    console.log(
      `   ${d.id}  dealerCode=${d.dealerCode}  pin=${d.fullPin}  ${d.name}`,
    );
  }

  console.log(`\nSKIPPED (review by hand) : ${plan.skipped.length}`);
  for (const d of plan.skipped) {
    console.log(`   ${d.id}  role=${JSON.stringify(d.role)}  — ${d.why}`);
  }

  if (!CONFIRM) {
    console.log(
      "\nDRY RUN — nothing written. See the header before running with --confirm.\n",
    );
    return;
  }

  let written = 0;
  for (const d of plan.stamp) {
    await db.collection("installers").doc(d.id).update({ role: DEFAULT_ROLE });
    written++;
  }
  console.log(`\nWROTE role='${DEFAULT_ROLE}' to ${written} doc(s).\n`);
}

main().catch((e) => {
  console.error("backfill failed:", e.message);
  process.exit(1);
});
