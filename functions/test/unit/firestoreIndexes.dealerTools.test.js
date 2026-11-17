/**
 * Dealer-tools item 8 (2026-11-17): firestore.indexes.json carries the
 * indexes whose client queries are correct, and NOT the installations ones.
 *
 * The emulator does not enforce composite indexes, so this pins the file
 * contract instead. Each composite below matches a client query verbatim:
 *   installers (dealerCode ASC, installerCode DESC)
 *     admin_providers.dart getNextInstallerCode
 *   referral_payouts (status ASC, createdAt DESC)
 *     payout_providers.dart pendingPayoutsProvider
 *   referral_payouts (referrerUid ASC, createdAt DESC)
 *     payout_providers.dart myPayoutsProvider
 *   materialCatalog.isActive COLLECTION_GROUP
 *     corporate_inventory_providers.dart allMaterialCatalogProvider
 * customer_lookup_service.dart's installations queries use camelCase
 * dealerCode / installerCode / installedAt; live installation docs are
 * snake_case, so those queries are wrong and get no index until the client
 * is fixed.
 */

const path = require("path");
const fs = require("fs");

const file = path.join(__dirname, "..", "..", "..", "firestore.indexes.json");
const json = JSON.parse(fs.readFileSync(file, "utf8"));

const sig = (i) =>
  `${i.collectionGroup}|${i.queryScope}|` +
  i.fields.map((f) => `${f.fieldPath}:${f.order || f.arrayConfig}`).join(",");

describe("firestore.indexes.json — dealer-tools item 8", () => {
  const sigs = json.indexes.map(sig);

  test.each([
    "installers|COLLECTION|dealerCode:ASCENDING,installerCode:DESCENDING",
    "referral_payouts|COLLECTION|status:ASCENDING,createdAt:DESCENDING",
    "referral_payouts|COLLECTION|referrerUid:ASCENDING,createdAt:DESCENDING",
  ])("has composite %s", (s) => {
    expect(sigs).toContain(s);
  });

  test("keeps the 21 indexes that are live today and has no duplicates", () => {
    expect(json.indexes).toHaveLength(24);
    expect(new Set(sigs).size).toBe(sigs.length);
  });

  test("adds no installations index (those client queries use the wrong field names)", () => {
    expect(json.indexes.filter((i) => i.collectionGroup === "installations")).toEqual([]);
  });

  test("materialCatalog.isActive gets a collection-group index and keeps its collection defaults", () => {
    const o = (json.fieldOverrides || []).filter(
      (f) => f.collectionGroup === "materialCatalog" && f.fieldPath === "isActive",
    );
    expect(o).toHaveLength(1);
    const ix = o[0].indexes.map((i) => `${i.queryScope}:${i.order || i.arrayConfig}`).sort();
    expect(ix).toEqual(
      [
        "COLLECTION:ASCENDING",
        "COLLECTION:DESCENDING",
        "COLLECTION:CONTAINS",
        "COLLECTION_GROUP:ASCENDING",
      ].sort(),
    );
  });
});
