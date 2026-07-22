#!/usr/bin/env node
//
// census_dealer_code_formats.js — C1 EVIDENCE CENSUS. READ-ONLY.
//
// WHY: two rival dealer-code formats exist in the codebase and only one can be
// canonical.
//
//   Format A — 2-DIGIT  ('55')                 admin_providers.dart:244 getNextDealerCode()
//   Format B — PREFIXED ('NXG-DEALER-TX-001')  corporate_admin_providers.dart:220 generateDealerCode()
//
// The PIN system is hard-wired to Format A: InstallerInfo composes
// `fullPin = '$dealerCode$installerCode'` (installer_providers.dart:82), the
// client rejects any PIN whose length != 4 (installer_providers.dart:168), and
// the server enforces PIN_REGEX = /^\d{4,6}$/ (staffAuth.ts:112). A Format-B
// dealer therefore cannot have a working installer.
//
// This script answers the only question code inspection cannot: WHICH FORMAT
// DOES THE LIVE DATA ACTUALLY HOLD? That decides whether fixing the creator is
// migration-free (majority already Format A) or a migration (majority Format B).
//
// SAFETY
//   • READ-ONLY BY CONSTRUCTION. There is no --confirm flag and no write path.
//     The only Firestore calls are .get(). Nothing here can mutate data.
//   • Reports counts + a per-doc table; never mutates, never deletes.
//   • Also cross-checks the blast radius of a hypothetical rename: how many
//     /installers, /users, and /sales_jobs docs reference each dealer code, and
//     which per-dealer subcollections exist (their doc id IS the dealer code).
//
// Usage:
//   cd functions && node scripts/census_dealer_code_formats.js
//   cd functions && node scripts/census_dealer_code_formats.js --json

const admin = require("firebase-admin");

const PROJECT_ID = "icrt6menwsv2d8all8oijs021b06s5";
const AS_JSON = process.argv.includes("--json");

// Format A: exactly 2 digits, 00-99. What the PIN system requires.
const FORMAT_A = /^\d{2}$/;
// Format B: what generateDealerCode() currently mints.
const FORMAT_B = /^NXG-DEALER-[A-Z]{2,}-\d{3}$/;

function classify(code) {
  if (code === undefined || code === null || code === "") return "EMPTY";
  if (FORMAT_A.test(code)) return "A_2DIGIT";
  if (FORMAT_B.test(code)) return "B_PREFIXED";
  return "OTHER";
}

// Per-dealer subcollections whose PARENT doc id is the dealer code. A rename
// means recreating each of these under a new parent — the real migration cost.
const DEALER_SUBS = [
  "pricing",
  "config",
  "inventory",
  "sku_inventory",
  "materialCatalog",
  "inventoryLedger",
  "shipping_address",
];

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  const out = {
    project: PROJECT_ID,
    generatedAt: new Date().toISOString(),
    dealers: [],
    tally: { A_2DIGIT: 0, B_PREFIXED: 0, OTHER: 0, EMPTY: 0 },
    docIdMismatch: [],
    referencing: {},
    verdict: null,
  };

  // ── /dealers ──────────────────────────────────────────────────────────────
  const dealersSnap = await db.collection("dealers").get();

  for (const doc of dealersSnap.docs) {
    const data = doc.data();
    const field = data.dealerCode;
    const kind = classify(field);
    out.tally[kind]++;

    // createDealer() uses the code as BOTH the doc id and the dealerCode field
    // (corporate_admin_providers.dart:242). addDealer() uses .add() (auto id),
    // so a mismatch here tells us which creator produced the doc.
    if (doc.id !== field) {
      out.docIdMismatch.push({ docId: doc.id, dealerCodeField: field ?? null });
    }

    const rec = {
      docId: doc.id,
      dealerCode: field ?? null,
      format: kind,
      name: data.name ?? data.businessName ?? null,
      isActive: data.isActive ?? null,
      registeredAt: data.registeredAt?.toDate?.()?.toISOString?.() ?? null,
      subcollections: {},
    };

    for (const sub of DEALER_SUBS) {
      const s = await doc.ref.collection(sub).limit(5).get();
      if (!s.empty) rec.subcollections[sub] = s.size;
    }

    out.dealers.push(rec);
  }

  // ── Blast radius: who REFERENCES each dealer code ─────────────────────────
  const codes = [
    ...new Set(
      out.dealers.map((d) => d.dealerCode).filter((c) => c !== null && c !== ""),
    ),
  ];

  for (const code of codes) {
    const [installers, usersByDealer, jobs] = await Promise.all([
      db.collection("installers").where("dealerCode", "==", code).get(),
      db.collection("users").where("dealer_code", "==", code).get(),
      db.collection("sales_jobs").where("dealerCode", "==", code).get(),
    ]);
    out.referencing[code] = {
      installers: installers.size,
      users_dealer_code: usersByDealer.size,
      sales_jobs: jobs.size,
    };
  }

  // Orphan sweep: references to codes that have no /dealers doc.
  const allInstallers = await db.collection("installers").get();
  const installerCodes = new Set(
    allInstallers.docs.map((d) => d.data().dealerCode).filter(Boolean),
  );
  out.orphanInstallerDealerCodes = [...installerCodes].filter(
    (c) => !codes.includes(c),
  );
  out.installerTotal = allInstallers.size;
  // An installer doc with no `role` cannot authenticate (staffAuth.ts:357).
  out.installersMissingRole = allInstallers.docs.filter(
    (d) => d.data().role === undefined,
  ).length;

  // ── Verdict ───────────────────────────────────────────────────────────────
  const a = out.tally.A_2DIGIT;
  const b = out.tally.B_PREFIXED;
  if (a > 0 && b === 0) out.verdict = "UNANIMOUS_A — 2-digit is canonical; fixing the creator is MIGRATION-FREE";
  else if (b > 0 && a === 0) out.verdict = "UNANIMOUS_B — live data is prefixed; adopting 2-digit REQUIRES A MIGRATION";
  else if (a > 0 && b > 0) out.verdict = `SPLIT — ${a} 2-digit vs ${b} prefixed; MIGRATION DECISION REQUIRED (escalate)`;
  else out.verdict = "NO_DEALERS — greenfield; pick the format the consumers require (2-digit)";

  if (AS_JSON) {
    console.log(JSON.stringify(out, null, 2));
    return;
  }

  console.log("\n════════ DEALER CODE FORMAT CENSUS (READ-ONLY) ════════");
  console.log(`project: ${out.project}`);
  console.log(`when   : ${out.generatedAt}\n`);
  console.log(`/dealers docs: ${dealersSnap.size}`);
  console.log(`  A_2DIGIT   (e.g. '55')                : ${out.tally.A_2DIGIT}`);
  console.log(`  B_PREFIXED (e.g. 'NXG-DEALER-TX-001') : ${out.tally.B_PREFIXED}`);
  console.log(`  OTHER                                 : ${out.tally.OTHER}`);
  console.log(`  EMPTY / missing dealerCode            : ${out.tally.EMPTY}\n`);

  if (out.dealers.length) {
    console.log("── per-dealer ──");
    for (const d of out.dealers) {
      const subs = Object.keys(d.subcollections).length
        ? Object.entries(d.subcollections).map(([k, v]) => `${k}:${v}`).join(" ")
        : "(none)";
      const refs = out.referencing[d.dealerCode];
      const refStr = refs
        ? `installers:${refs.installers} users:${refs.users_dealer_code} jobs:${refs.sales_jobs}`
        : "(n/a)";
      console.log(
        `  docId=${d.docId} | dealerCode=${d.dealerCode} | ${d.format} | active=${d.isActive} | ${d.name ?? ""}`,
      );
      console.log(`      refs: ${refStr}`);
      console.log(`      subs: ${subs}`);
    }
    console.log("");
  }

  if (out.docIdMismatch.length) {
    console.log("── docId != dealerCode (creator fingerprint) ──");
    for (const m of out.docIdMismatch) {
      console.log(`  docId=${m.docId} field=${m.dealerCodeField}`);
    }
    console.log("");
  }

  console.log("── installers ──");
  console.log(`  total                    : ${out.installerTotal}`);
  console.log(`  missing 'role' (cannot auth, staffAuth.ts:357): ${out.installersMissingRole}`);
  if (out.orphanInstallerDealerCodes.length) {
    console.log(`  orphan dealerCodes (no /dealers doc): ${out.orphanInstallerDealerCodes.join(", ")}`);
  }

  console.log(`\n>>> VERDICT: ${out.verdict}\n`);
}

main().catch((e) => {
  console.error("census failed:", e.message);
  process.exit(1);
});
