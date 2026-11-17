#!/usr/bin/env node
/**
 * READ-ONLY export of production `product_catalog` for seeding staging.
 *
 *   node scripts/staging/export_prod_catalog.js
 *
 * Issues GET requests only (listCollection), against production, with the
 * operator's own gcloud credential. Writes the raw REST documents (typed
 * fields, verbatim) to scripts/staging/.local/product_catalog.export.json,
 * which is gitignored: the catalog carries `unit_price`, the dealer buy
 * price, and this repository may be public. Prints counts only, never values.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { PRODUCTION_PROJECT, listCollection } = require("./_firestore_rest");

const OUT_DIR = path.join(__dirname, ".local");
const OUT = path.join(OUT_DIR, "product_catalog.export.json");

(async () => {
  const docs = await listCollection(PRODUCTION_PROJECT, "product_catalog");
  const documents = docs.map((d) => ({
    id: d.name.split("/").pop(),
    fields: d.fields || {},
    createTime: d.createTime,
    updateTime: d.updateTime,
  }));
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(
    OUT,
    JSON.stringify(
      { exportedAt: new Date().toISOString(), source: "production product_catalog", count: documents.length, documents },
      null,
      2,
    ),
  );
  console.log(`exported ${documents.length} product_catalog docs -> ${OUT}`);
  if (documents.length !== 61) {
    console.log(`note: the 2026-11-17 audit counted 61; this export has ${documents.length}.`);
  }
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
