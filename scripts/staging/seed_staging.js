#!/usr/bin/env node
/**
 * Seed the STAGING project for the estimate and dealer tools.
 *
 *   node scripts/staging/seed_staging.js --project nex-gen-lumina-22751          # plan only
 *   node scripts/staging/seed_staging.js --project nex-gen-lumina-22751 --yes    # write
 *   ... --rotate-pins   generate new test PINs instead of reusing .local/test_pins.json
 *
 * HARD-GUARDED: every write goes to the constant STAGING_PROJECT. --project is
 * a confirmation that must equal it; any other value (production above all)
 * refuses before anything is read or written. Writes go through the
 * operator's own gcloud credential (Firestore REST :commit), which is not
 * subject to security rules.
 *
 * Seeds (each document is fully replaced):
 *   product_catalog/{sku}            from .local/product_catalog.export.json
 *                                    (run export_prod_catalog.js first; 61 SKUs)
 *   dealers/01, dealers/02           keyed by code (the shape createDealer writes)
 *   app_config/pricing_defaults      placeholder = DealerPricing.defaults()
 *   installers/staging_<dd>_<role>   dealer 01: admin, installer, salesperson;
 *                                    dealer 02: installer, salesperson
 *   app_config/master_sales_pin, master_installer, master_admin,
 *   master_corporate_pin             sha256 of NEW random test PINs
 *
 * PINs: freshly random (crypto.randomInt), never derived from or copied from
 * production. Per-installer PINs follow the app's `fullPin = dealerCode +
 * installerCode` shape with a random 2-digit installer code. The master sales
 * PIN starts with 01 because mintStaffToken derives the sales master's dealer
 * from the PIN's first two digits. All PINs are distinct. They are written
 * ONLY to .local/test_pins.json (gitignored) and reused on later runs unless
 * --rotate-pins. This script never prints a PIN, a hash or a price.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { createHash, randomInt } = require("crypto");
const {
  PRODUCTION_PROJECT,
  STAGING_PROJECT,
  encodeFields,
  commitWrites,
} = require("./_firestore_rest");

const LOCAL = path.join(__dirname, ".local");
const CATALOG = path.join(LOCAL, "product_catalog.export.json");
const PINS = path.join(LOCAL, "test_pins.json");

// ── args + guard ────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const projectArg = (() => {
  const i = args.indexOf("--project");
  if (i >= 0) return args[i + 1] || "";
  const eq = args.find((a) => a.startsWith("--project="));
  return eq ? eq.slice("--project=".length) : "";
})();

function refuse(msg) {
  console.error(`REFUSED: ${msg}`);
  process.exit(1);
}
if (projectArg === PRODUCTION_PROJECT) refuse("that is the PRODUCTION project. This script only seeds staging.");
if (projectArg !== STAGING_PROJECT) {
  refuse(`--project must be exactly ${STAGING_PROJECT} (got '${projectArg || "(none)"}').`);
}
const WRITE = flag("--yes");
const ROTATE = flag("--rotate-pins");

// ── PINs ────────────────────────────────────────────────────────────────────

const INSTALLER_SLOTS = [
  { dealerCode: "01", role: "admin", name: "Staging Dealer 01 Admin" },
  { dealerCode: "01", role: "installer", name: "Staging Dealer 01 Installer" },
  { dealerCode: "01", role: "salesperson", name: "Staging Dealer 01 Sales" },
  { dealerCode: "02", role: "installer", name: "Staging Dealer 02 Installer" },
  { dealerCode: "02", role: "salesperson", name: "Staging Dealer 02 Sales" },
];
const MASTER_SLOTS = [
  { docId: "master_sales_pin", role: "salesperson", displayName: "Staging master sales", prefix: "01" },
  { docId: "master_installer", role: "installer", displayName: "Staging master installer" },
  { docId: "master_admin", role: "admin", displayName: "Staging master admin" },
  { docId: "master_corporate_pin", role: "owner", displayName: "Staging owner" },
];

function generatePins() {
  const used = new Set();
  const take = (make) => {
    for (let i = 0; i < 1000; i++) {
      const p = make();
      if (!used.has(p)) {
        used.add(p);
        return p;
      }
    }
    throw new Error("could not allocate a distinct PIN");
  };
  const two = () => String(randomInt(10, 100));
  const installers = INSTALLER_SLOTS.map((s) => {
    const pin = take(() => s.dealerCode + two());
    return {
      docId: `staging_${s.dealerCode}_${s.role}`,
      role: s.role,
      dealerCode: s.dealerCode,
      installerCode: pin.slice(2),
      name: s.name,
      pin,
    };
  });
  const masters = MASTER_SLOTS.map((m) => ({
    docId: m.docId,
    role: m.role,
    displayName: m.displayName,
    pin: take(() => (m.prefix ? m.prefix + two() : String(randomInt(1000, 10000)))),
  }));
  return {
    project: STAGING_PROJECT,
    generatedAt: new Date().toISOString(),
    note: "STAGING test PINs. Local only; never commit. Not production PINs.",
    masters,
    installers,
  };
}

function loadOrCreatePins() {
  if (!ROTATE && fs.existsSync(PINS)) {
    const p = JSON.parse(fs.readFileSync(PINS, "utf8"));
    if (p.project !== STAGING_PROJECT) refuse(`${PINS} is for another project.`);
    return { pins: p, reused: true };
  }
  return { pins: generatePins(), reused: false };
}

const sha256 = (s) => createHash("sha256").update(s, "utf8").digest("hex");

// ── documents ───────────────────────────────────────────────────────────────

function buildWrites(pins, catalogDocs) {
  const now = new Date();
  const writes = [];

  for (const d of catalogDocs) {
    writes.push({ path: `product_catalog/${d.id}`, fields: d.fields });
  }

  for (const [code, territory] of [["01", "Staging A"], ["02", "Staging B"]]) {
    writes.push({
      path: `dealers/${code}`,
      fields: encodeFields({
        dealerCode: code,
        name: `Staging Dealer ${code}`,
        companyName: `Staging Dealer ${code}`,
        businessName: `Staging Dealer ${code}`,
        territory,
        email: `dealer${code}@example.com`,
        phone: "",
        isActive: true,
        registeredAt: now,
      }),
    });
  }

  writes.push({
    path: "app_config/pricing_defaults",
    fields: encodeFields({
      // DealerPricing.defaults() (sales_models.dart) — placeholder values.
      pricePerLinearFoot: 18,
      laborRatePerFoot: 4,
      flatLaborMinimum: 150,
      controllerRetailPrice: 285,
      powerBoardRetailPrice: 95,
      wasteFactor: 0.08,
      dealerCostPerLinearFoot: 0,
      dealerControllerCost: 0,
      dealerPowerBoardCost: 0,
      seededBy: "scripts/staging/seed_staging.js (placeholder)",
      updatedAt: now,
    }),
  });

  for (const i of pins.installers) {
    writes.push({
      path: `installers/${i.docId}`,
      fields: encodeFields({
        // InstallerInfo.toMap() shape; mintStaffToken matches fullPin + isActive + role.
        installerCode: i.installerCode,
        dealerCode: i.dealerCode,
        fullPin: i.pin,
        name: i.name,
        email: `${i.docId}@example.com`,
        phone: "",
        isActive: true,
        registeredAt: now,
        totalInstallations: 0,
        role: i.role,
      }),
    });
  }

  for (const m of pins.masters) {
    const hash = sha256(m.pin);
    if (hash.length !== 64) throw new Error("hash length check failed");
    writes.push({
      path: `app_config/${m.docId}`,
      fields: encodeFields({ displayName: m.displayName, role: m.role, pin_hash: hash, updatedAt: now }),
    });
  }

  return writes;
}

// ── main ────────────────────────────────────────────────────────────────────

(async () => {
  if (!fs.existsSync(CATALOG)) {
    refuse(`${CATALOG} not found. Run: node scripts/staging/export_prod_catalog.js`);
  }
  const catalog = JSON.parse(fs.readFileSync(CATALOG, "utf8"));
  const catalogDocs = catalog.documents || [];
  if (catalogDocs.length === 0) refuse("the catalog export is empty.");

  const { pins, reused } = loadOrCreatePins();
  const writes = buildWrites(pins, catalogDocs);

  const byCollection = {};
  for (const w of writes) {
    const c = w.path.split("/")[0];
    byCollection[c] = (byCollection[c] || 0) + 1;
  }
  console.log(`target:   ${STAGING_PROJECT}`);
  console.log(`catalog:  ${catalogDocs.length} docs from the export (${catalog.exportedAt || "unknown date"})`);
  console.log(`pins:     ${reused ? "reusing" : "NEW"} ${pins.masters.length} master + ${pins.installers.length} installer PINs (values only in ${PINS})`);
  console.log(`writes:   ${writes.length}`, byCollection);
  for (const w of writes.filter((x) => !x.path.startsWith("product_catalog/"))) console.log(`  ${w.path}`);

  if (!WRITE) {
    console.log("\nPlan only. Re-run with --yes to write.");
    return;
  }

  fs.mkdirSync(LOCAL, { recursive: true });
  if (!reused) fs.writeFileSync(PINS, JSON.stringify(pins, null, 2));
  await commitWrites(STAGING_PROJECT, writes);
  console.log(`\nwrote ${writes.length} documents to ${STAGING_PROJECT}.`);
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
