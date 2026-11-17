/**
 * Dealer-tools rules, items 1-6 (2026-11-17), as named allow/deny cases.
 *
 * ⚠️ NOT run by `npm test`. Needs the Firestore emulator — see README.md.
 * The exhaustive before/after matrix is dealerToolsRulesDiff.emulator.test.ts;
 * this file states each intended behaviour by name, including the customers
 * who LOSE access, so a regression reads as a sentence.
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { createHash } from "crypto";
import { readFileSync } from "fs";
import {
  Firestore,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

import { D1, D2, ctxFor, draftJobPayload, reseed } from "./dealerToolsFixtures";

const PROJECT_ID = "lumina-dt-rules";
const RULES = readFileSync("../firestore.rules", "utf8");
const HOOK_TIMEOUT_MS = 120_000;

let env: RulesTestEnvironment;
const as = (persona: string) => ctxFor(env, persona).firestore() as unknown as Firestore;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: RULES, host: "127.0.0.1", port: 8080 },
  });
}, HOOK_TIMEOUT_MS);
afterAll(async () => env?.cleanup());
beforeEach(async () => reseed(env), HOOK_TIMEOUT_MS);

// ── Item 1 — R1 sales_jobs / R2 dealer_orders ──────────────────────────────

describe("item 1 / R1: customers stamped with a dealer code lose sales_jobs", () => {
  test("a dealer-01 customer can no longer read a dealer-01 job", async () => {
    await assertFails(getDoc(doc(as("custA"), "sales_jobs/job01")));
  });
  test("a dealer-01 customer can no longer update a dealer-01 job", async () => {
    await assertFails(updateDoc(doc(as("custA"), "sales_jobs/job01"), { day1Notes: "x" }));
  });
  test("a dealer-01 customer can no longer list dealer-01 jobs", async () => {
    await assertFails(getDocs(query(collection(as("custB"), "sales_jobs"), where("dealerCode", "==", D1))));
  });
  test("a self-stamped installer_dealer_code no longer reads the dealer's jobs", async () => {
    await assertFails(getDoc(doc(as("custIdc"), "sales_jobs/job01")));
  });
  test("the customer still reads their own profile, controllers, schedules and installation", async () => {
    const db = as("custA");
    await assertSucceeds(getDoc(doc(db, "users/cust_a_uid")));
    await assertSucceeds(getDoc(doc(db, "users/cust_a_uid/controllers/c1")));
    await assertSucceeds(getDoc(doc(db, "users/cust_a_uid/schedules/s1")));
    await assertSucceeds(getDoc(doc(db, "installations/inst_a")));
  });
  test("the dealer's sales PIN still reads, lists and updates its job", async () => {
    const db = as("sales01");
    await assertSucceeds(getDoc(doc(db, "sales_jobs/job01")));
    await assertSucceeds(getDocs(query(collection(db, "sales_jobs"), where("dealerCode", "==", D1))));
    await assertSucceeds(updateDoc(doc(db, "sales_jobs/job01"), { day1Notes: "x" }));
  });
  test("the dealer's installer PIN still reads its job; another dealer's cannot", async () => {
    await assertSucceeds(getDoc(doc(as("inst01"), "sales_jobs/job01")));
    await assertFails(getDoc(doc(as("inst02"), "sales_jobs/job01")));
  });
  test("a user_role dealer account of the dealer still reads its job", async () => {
    await assertSucceeds(getDoc(doc(as("dealerAcct01"), "sales_jobs/job01")));
  });
  test("admin and owner claims still read any dealer's job", async () => {
    await assertSucceeds(getDoc(doc(as("admin01"), "sales_jobs/job02")));
    await assertSucceeds(getDoc(doc(as("owner"), "sales_jobs/job02")));
  });
});

describe("item 1 / R2: customers stamped with a dealer code lose dealer_orders", () => {
  test("a dealer-01 customer cannot read, update or delete a dealer-01 order", async () => {
    const db = as("custA");
    await assertFails(getDoc(doc(db, "dealer_orders/ord01")));
    await assertFails(updateDoc(doc(db, "dealer_orders/ord01"), { notes: "x" }));
    await assertFails(deleteDoc(doc(db, "dealer_orders/ord01")));
  });
  test("a dealer-01 customer cannot create a dealer-01 order", async () => {
    await assertFails(
      setDoc(doc(as("custB"), "dealer_orders/new"), { dealer_code: D1, status: "draft", line_items: [] }),
    );
  });
  test("the dealer's sales PIN still reads and creates its orders, not another dealer's", async () => {
    const db = as("sales01");
    await assertSucceeds(getDoc(doc(db, "dealer_orders/ord01")));
    await assertSucceeds(setDoc(doc(db, "dealer_orders/new01"), { dealer_code: D1, status: "draft", line_items: [] }));
    await assertFails(setDoc(doc(db, "dealer_orders/new02"), { dealer_code: D2, status: "draft", line_items: [] }));
  });
});

// ── Item 2 — dealer subcollection writes ───────────────────────────────────

describe("item 2: inventoryLedger create admits the dealer's own PIN sessions", () => {
  test("the dealer's sales and installer PINs can append to its ledger", async () => {
    await assertSucceeds(setDoc(doc(as("sales01"), "dealers/01/inventoryLedger/a"), { type: "checkout", quantity: 1 }));
    await assertSucceeds(setDoc(doc(as("inst01"), "dealers/01/inventoryLedger/b"), { type: "usage_final", quantity: 1 }));
  });
  test("another dealer's installer PIN and a customer cannot", async () => {
    await assertFails(setDoc(doc(as("inst02"), "dealers/01/inventoryLedger/c"), { type: "checkout", quantity: 1 }));
    await assertFails(setDoc(doc(as("custA"), "dealers/01/inventoryLedger/d"), { type: "checkout", quantity: 1 }));
  });
  test("the ledger stays append-only for every caller", async () => {
    await assertFails(updateDoc(doc(as("inst01"), "dealers/01/inventoryLedger/e1"), { quantity: 2 }));
    await assertFails(deleteDoc(doc(as("owner"), "dealers/01/inventoryLedger/e1")));
  });
});

describe("item 2: pricing, config and shipping_address writes are admin-role only", () => {
  const paths = [
    "dealers/01/pricing/current",
    "dealers/01/config/messaging",
    "dealers/01/shipping_address/primary",
  ];
  for (const path of paths) {
    test(`a sales or installer PIN cannot write ${path}`, async () => {
      await assertFails(setDoc(doc(as("sales01"), path), { changed: true }));
      await assertFails(setDoc(doc(as("inst01"), path), { changed: true }));
    });
    test(`the dealer's admin-role claim and the owner can write ${path}`, async () => {
      await assertSucceeds(setDoc(doc(as("admin01"), path), { changed: true }));
      await assertSucceeds(setDoc(doc(as("owner"), path), { changed: true }));
    });
    test(`a customer and a dealer ACCOUNT cannot write ${path}`, async () => {
      await assertFails(setDoc(doc(as("custA"), path), { changed: true }));
      await assertFails(setDoc(doc(as("dealerAcct01"), path), { changed: true }));
    });
    test(`the dealer's staff still read ${path}`, async () => {
      await assertSucceeds(getDoc(doc(as("sales01"), path)));
      await assertSucceeds(getDoc(doc(as("inst01"), path)));
    });
  }
  test("another dealer's sales PIN still cannot read dealer-01 pricing", async () => {
    await assertFails(getDoc(doc(as("sales02"), "dealers/01/pricing/current")));
  });
});

// ── Item 3 — R3 / R4 / R5 ──────────────────────────────────────────────────

describe("item 3 / R3: referral_payouts", () => {
  test("a dealer-01 customer can no longer read the dealer's payouts", async () => {
    await assertFails(getDoc(doc(as("custA"), "referral_payouts/pay01")));
    await assertFails(getDocs(query(collection(as("custA"), "referral_payouts"), where("dealerCode", "==", D1))));
  });
  test("the referrer still reads their own payout", async () => {
    await assertSucceeds(getDoc(doc(as("custB"), "referral_payouts/pay01")));
    await assertSucceeds(
      getDocs(query(collection(as("custB"), "referral_payouts"), where("referrerUid", "==", "cust_b_uid"))),
    );
  });
  test("the dealer's sales PIN still lists the dealer's payouts", async () => {
    await assertSucceeds(getDocs(query(collection(as("sales01"), "referral_payouts"), where("dealerCode", "==", D1))));
  });
});

describe("item 3 / R4: /installers dealer scope", () => {
  test("a dealer account may create an installer for its own dealer", async () => {
    await assertSucceeds(setDoc(doc(as("dealerAcct01"), "installers/n1"), { dealerCode: D1, role: "installer" }));
  });
  test("a dealer account may not create, update or delete another dealer's installer", async () => {
    const db = as("dealerAcct01");
    await assertFails(setDoc(doc(db, "installers/n2"), { dealerCode: D2, role: "installer" }));
    await assertFails(updateDoc(doc(db, "installers/i02"), { name: "x" }));
    await assertFails(deleteDoc(doc(db, "installers/i02")));
  });
  test("a dealer account may not move its installer to another dealer", async () => {
    await assertFails(updateDoc(doc(as("dealerAcct01"), "installers/i01"), { dealerCode: D2 }));
  });
  test("a dealer account may not create an admin-role installer", async () => {
    await assertFails(setDoc(doc(as("dealerAcct01"), "installers/n3"), { dealerCode: D1, role: "admin" }));
  });
  test("corporate (user_role admin, admin and owner claims) keep cross-dealer reach", async () => {
    await assertSucceeds(setDoc(doc(as("corpAdminAcct"), "installers/c1"), { dealerCode: D2, role: "installer" }));
    await assertSucceeds(setDoc(doc(as("admin01"), "installers/c2"), { dealerCode: D2, role: "installer" }));
    await assertSucceeds(setDoc(doc(as("owner"), "installers/c3"), { dealerCode: D2, role: "admin" }));
  });
  test("sales and installer PINs still cannot write /installers", async () => {
    await assertFails(setDoc(doc(as("inst01"), "installers/s1"), { dealerCode: D1, role: "installer" }));
    await assertFails(updateDoc(doc(as("inst01"), "installers/i01"), { totalInstallations: 1 }));
  });
});

describe("item 3 / R5: app_config/pricing_defaults", () => {
  test("customers, anonymous sessions and non-staff accounts can no longer read it", async () => {
    for (const p of ["custA", "custSelf", "anonSession", "dealerAcct01", "mediaAcct"]) {
      await assertFails(getDoc(doc(as(p), "app_config/pricing_defaults")));
    }
  });
  test("staff PIN sessions and admin/owner claims read it", async () => {
    for (const p of ["sales01", "inst02", "admin55", "owner"]) {
      await assertSucceeds(getDoc(doc(as(p), "app_config/pricing_defaults")));
    }
  });
  test("an admin claim can now save it (corporate Admin tab); a sales PIN cannot", async () => {
    await assertSucceeds(setDoc(doc(as("admin55"), "app_config/pricing_defaults"), { pricePerLinearFoot: 20 }));
    await assertFails(setDoc(doc(as("sales01"), "app_config/pricing_defaults"), { pricePerLinearFoot: 1 }));
  });
});

// ── Item 4 — materialList / materialLedger ─────────────────────────────────

describe("item 4: materialList and materialLedger follow their job", () => {
  test("a customer and an anonymous session lose both subcollections", async () => {
    for (const p of ["custA", "anonSession"]) {
      const db = as(p);
      await assertFails(getDoc(doc(db, "sales_jobs/job01/materialList/current")));
      await assertFails(setDoc(doc(db, "sales_jobs/job01/materialList/current"), { lines: [] }));
      await assertFails(getDoc(doc(db, "sales_jobs/job01/materialLedger/l1")));
      await assertFails(setDoc(doc(db, `sales_jobs/job01/materialLedger/${p}`), { quantity: 1 }));
    }
  });
  test("another dealer's installer PIN loses them", async () => {
    await assertFails(getDoc(doc(as("inst02"), "sales_jobs/job01/materialList/current")));
    await assertFails(setDoc(doc(as("inst02"), "sales_jobs/job01/materialLedger/x"), { quantity: 1 }));
  });
  test("the job's dealer's installer PIN keeps them (Day-2 final check-in)", async () => {
    const db = as("inst01");
    await assertSucceeds(getDoc(doc(db, "sales_jobs/job01/materialList/current")));
    await assertSucceeds(updateDoc(doc(db, "sales_jobs/job01/materialList/current"), { status: "complete" }));
    await assertSucceeds(setDoc(doc(db, "sales_jobs/job01/materialLedger/y"), { type: "usage_final", quantity: 1 }));
  });
  test("the ledger stays append-only", async () => {
    await assertFails(updateDoc(doc(as("inst01"), "sales_jobs/job01/materialLedger/l1"), { quantity: 9 }));
  });
  test("a subcollection under a job that does not exist is denied to staff", async () => {
    await assertFails(setDoc(doc(as("inst01"), "sales_jobs/nojob/materialLedger/z"), { quantity: 1 }));
  });
});

// ── Item 5 — sales_jobs create ─────────────────────────────────────────────

describe("item 5: sales_jobs create needs a staff claim for the new job's dealer", () => {
  // The client creates with set(merge:true) on a fresh id
  // (SalesJobService.updateJob from prospect_info_screen._saveAndContinue).
  const create = (persona: string, id: string, dealer: string) =>
    setDoc(doc(as(persona), `sales_jobs/${id}`), draftJobPayload(id, dealer, `uid_${persona}`), { merge: true });

  test("a sales PIN creates a job for its own dealer with the client's exact payload", async () => {
    await assertSucceeds(create("sales01", "s01", D1));
  });
  test("an installer PIN creates a job for its own dealer with the client's exact payload", async () => {
    await assertSucceeds(create("inst01", "i01", D1));
  });
  test("a sales PIN cannot create a job for another dealer", async () => {
    await assertFails(create("sales01", "s02", D2));
  });
  test("a sales PIN cannot create a job with no dealer (the no-session fallback)", async () => {
    await assertFails(create("sales01", "sEmpty", ""));
  });
  test("customers, anonymous sessions and dealer accounts cannot create jobs", async () => {
    for (const p of ["custA", "custSelf", "anonSession", "dealerAcct01", "mediaAcct"]) {
      await assertFails(create(p, `x_${p}`, D1));
    }
  });
  test("admin and owner claims can create a job for any dealer", async () => {
    await assertSucceeds(create("admin55", "a01", D1));
    await assertSucceeds(create("owner", "o02", D2));
  });
  test("pre-existing, NOT changed here: the client's unscoped job-number count is denied to staff", async () => {
    // generateJobNumber() (sales_providers.dart:272-288) counts today's jobs
    // with no dealerCode filter; the read rule cannot be proven for that
    // query under a staff claim. This blocks prospect save before the create
    // ever runs. Client fix: add where('dealerCode', ==, session.dealerCode).
    const { getCountFromServer, Timestamp } = await import("firebase/firestore");
    const q = (db: Firestore, scoped: boolean) =>
      query(
        collection(db, "sales_jobs"),
        ...(scoped ? [where("dealerCode", "==", D1)] : []),
        where("createdAt", ">=", Timestamp.fromDate(new Date("2026-11-17T00:00:00Z"))),
        where("createdAt", "<", Timestamp.fromDate(new Date("2026-11-18T00:00:00Z"))),
      );
    await assertFails(getCountFromServer(q(as("sales01"), false)));
    await assertSucceeds(getCountFromServer(q(as("sales01"), true)));
  });
});

// ── Item 6 — public-repo hygiene in rules comments ─────────────────────────

describe("item 6: rules comments carry no PIN-bearing ids or personal names", () => {
  test("no installer doc id embeds a 4-digit PIN", () => {
    expect(RULES).not.toMatch(/test_(admin|installer|sales)_\d{4}/);
  });
  test("no owner or supplier name appears in a comment", () => {
    // Compared by SHA-256 of each lower-cased word so this test does not
    // itself put the names back into the public repo. The two digests are
    // the owner's first name and the supplier name removed in item 6.
    const banned = new Set([
      "b258f8614815e4157b9eab23d55ac5d0ff77a97ef4a63800089141225d560eee",
      "555ed655e8b2b0ae06e280e6038e9b932238966ec88b4a7500ff7ef2f3655484",
    ]);
    const words = new Set(RULES.toLowerCase().match(/[a-z]+/g) ?? []);
    const hits = [...words].filter((w) => banned.has(createHash("sha256").update(w).digest("hex")));
    expect(hits).toEqual([]);
  });
});
