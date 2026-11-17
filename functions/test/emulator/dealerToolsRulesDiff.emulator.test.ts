/**
 * Differential allow-matrix for the dealer-tools rules change.
 *
 * ⚠️ NOT run by `npm test`. Needs the Firestore emulator — see README.md.
 *
 * Runs the SAME request matrix (17 personas × 61 requests) against two
 * rulesets loaded into two emulator projects:
 *   OLD = `git show ${BASELINE_REF}:firestore.rules` (0a364ce0, which is
 *         byte-identical to the ruleset live in production since 2026-10-05)
 *   NEW = ../firestore.rules (the working tree)
 * Both projects are reseeded with identical fixtures before each persona.
 *
 * It then asserts the set of behavioural deltas EQUALS `EXPECTED_DELTAS`
 * exactly — an unintended widening OR narrowing anywhere in the matrix fails
 * the run, as does an intended delta that did not happen.
 *
 * DIFF_EXPECT=none asserts there are NO deltas (used once, before any rules
 * edit, to prove the harness itself is neutral). DIFF_OUT=<path> writes both
 * matrices and the delta list as JSON for the report.
 */

import {
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { execFileSync } from "child_process";
import { readFileSync, writeFileSync } from "fs";
import {
  Firestore,
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

import { D1, D2, PERSONA_KEYS, ctxFor, draftJobPayload, reseed } from "./dealerToolsFixtures";

const BASELINE_REF = process.env.DEALER_TOOLS_BASELINE_REF ?? "0a364ce0";
const OLD_PROJECT = "lumina-dt-diff-old";
const NEW_PROJECT = "lumina-dt-diff-new";
const HOOK_TIMEOUT_MS = 120_000;
const MATRIX_TIMEOUT_MS = 600_000;

type Outcome = "ALLOW" | "DENY" | string;

type Op = { id: string; run: (db: Firestore, p: string) => Promise<unknown> };

const day = (iso: string) => Timestamp.fromDate(new Date(iso));

/**
 * Order matters: reads, then creates (fresh ids per persona), then updates
 * that do not change any field a later predicate reads, then deletes.
 */
const OPS: Op[] = [
  // ── reads ────────────────────────────────────────────────────────────────
  { id: "get users/custA", run: (db) => getDoc(doc(db, "users/cust_a_uid")) },
  {
    id: "list users dealer_code==01",
    run: (db) => getDocs(query(collection(db, "users"), where("dealer_code", "==", D1))),
  },
  { id: "get custA/controllers/c1", run: (db) => getDoc(doc(db, "users/cust_a_uid/controllers/c1")) },
  { id: "get custA/schedules/s1", run: (db) => getDoc(doc(db, "users/cust_a_uid/schedules/s1")) },
  { id: "get installations/inst_a", run: (db) => getDoc(doc(db, "installations/inst_a")) },
  { id: "get installers/i01", run: (db) => getDoc(doc(db, "installers/i01")) },
  { id: "get dealers/01", run: (db) => getDoc(doc(db, "dealers/01")) },
  { id: "get sales_jobs/job01", run: (db) => getDoc(doc(db, "sales_jobs/job01")) },
  { id: "get sales_jobs/job02", run: (db) => getDoc(doc(db, "sales_jobs/job02")) },
  {
    id: "list sales_jobs dealerCode==01",
    run: (db) => getDocs(query(collection(db, "sales_jobs"), where("dealerCode", "==", D1))),
  },
  {
    // generateJobNumber() (sales_providers.dart:272-288): UNSCOPED count.
    id: "count sales_jobs createdAt today (unscoped)",
    run: (db) =>
      getCountFromServer(
        query(
          collection(db, "sales_jobs"),
          where("createdAt", ">=", day("2026-11-17T00:00:00Z")),
          where("createdAt", "<", day("2026-11-18T00:00:00Z")),
        ),
      ),
  },
  { id: "get job01/materialList/current", run: (db) => getDoc(doc(db, "sales_jobs/job01/materialList/current")) },
  { id: "get job01/materialLedger/l1", run: (db) => getDoc(doc(db, "sales_jobs/job01/materialLedger/l1")) },
  { id: "get dealers/01/pricing/current", run: (db) => getDoc(doc(db, "dealers/01/pricing/current")) },
  { id: "get dealers/01/config/messaging", run: (db) => getDoc(doc(db, "dealers/01/config/messaging")) },
  { id: "get dealers/01/shipping_address/primary", run: (db) => getDoc(doc(db, "dealers/01/shipping_address/primary")) },
  { id: "get dealers/01/inventoryLedger/e1", run: (db) => getDoc(doc(db, "dealers/01/inventoryLedger/e1")) },
  { id: "get dealers/01/inventory/i1", run: (db) => getDoc(doc(db, "dealers/01/inventory/i1")) },
  { id: "get dealers/01/materialCatalog/m1", run: (db) => getDoc(doc(db, "dealers/01/materialCatalog/m1")) },
  { id: "get referral_payouts/pay01", run: (db) => getDoc(doc(db, "referral_payouts/pay01")) },
  {
    id: "list referral_payouts dealerCode==01",
    run: (db) => getDocs(query(collection(db, "referral_payouts"), where("dealerCode", "==", D1))),
  },
  { id: "get dealer_orders/ord01", run: (db) => getDoc(doc(db, "dealer_orders/ord01")) },
  { id: "get app_config/pricing_defaults", run: (db) => getDoc(doc(db, "app_config/pricing_defaults")) },
  { id: "get app_config/master_sales_pin", run: (db) => getDoc(doc(db, "app_config/master_sales_pin")) },
  { id: "get product_catalog/sku1", run: (db) => getDoc(doc(db, "product_catalog/sku1")) },

  // ── creates (fresh ids) ──────────────────────────────────────────────────
  { id: "create custA/controllers/new", run: (db, p) => setDoc(doc(db, `users/cust_a_uid/controllers/new_${p}`), { name: "x" }) },
  { id: "create custA/schedules/new", run: (db, p) => setDoc(doc(db, `users/cust_a_uid/schedules/new_${p}`), { label: "x" }) },
  {
    id: "create sales_jobs dealerCode 01 (client payload)",
    run: (db, p) =>
      setDoc(doc(db, `sales_jobs/new01_${p}`), draftJobPayload(`new01_${p}`, D1, `uid_${p}`), { merge: true }),
  },
  {
    id: "create sales_jobs dealerCode 02 (client payload)",
    run: (db, p) =>
      setDoc(doc(db, `sales_jobs/new02_${p}`), draftJobPayload(`new02_${p}`, D2, `uid_${p}`), { merge: true }),
  },
  {
    // prospect_info_screen falls back to dealerCode '' when no sales session.
    id: "create sales_jobs dealerCode '' (client payload)",
    run: (db, p) =>
      setDoc(doc(db, `sales_jobs/newEmpty_${p}`), draftJobPayload(`newEmpty_${p}`, "", `uid_${p}`), { merge: true }),
  },
  {
    id: "create job01/materialList/new",
    run: (db, p) => setDoc(doc(db, `sales_jobs/job01/materialList/new_${p}`), { lines: [] }),
  },
  {
    id: "create job01/materialLedger/new",
    run: (db, p) => setDoc(doc(db, `sales_jobs/job01/materialLedger/new_${p}`), { type: "checkout", quantity: 1 }),
  },
  {
    id: "create job02/materialLedger/new",
    run: (db, p) => setDoc(doc(db, `sales_jobs/job02/materialLedger/new_${p}`), { type: "checkout", quantity: 1 }),
  },
  {
    id: "create dealers/01/inventoryLedger/new",
    run: (db, p) => setDoc(doc(db, `dealers/01/inventoryLedger/new_${p}`), { type: "usage_final", quantity: 1 }),
  },
  {
    id: "create dealers/02/inventoryLedger/new",
    run: (db, p) => setDoc(doc(db, `dealers/02/inventoryLedger/new_${p}`), { type: "usage_final", quantity: 1 }),
  },
  {
    id: "create installers dealer 01 role installer",
    run: (db, p) => setDoc(doc(db, `installers/new01_${p}`), { dealerCode: D1, role: "installer", isActive: true }),
  },
  {
    id: "create installers dealer 02 role installer",
    run: (db, p) => setDoc(doc(db, `installers/new02_${p}`), { dealerCode: D2, role: "installer", isActive: true }),
  },
  {
    id: "create installers dealer 01 role admin",
    run: (db, p) => setDoc(doc(db, `installers/new01a_${p}`), { dealerCode: D1, role: "admin", isActive: true }),
  },
  {
    id: "create dealer_orders dealer_code 01",
    run: (db, p) => setDoc(doc(db, `dealer_orders/new01_${p}`), { dealer_code: D1, status: "draft", line_items: [] }),
  },
  {
    id: "create dealer_orders dealer_code 02",
    run: (db, p) => setDoc(doc(db, `dealer_orders/new02_${p}`), { dealer_code: D2, status: "draft", line_items: [] }),
  },
  {
    id: "create referral_payouts dealerCode 01",
    run: (db, p) => setDoc(doc(db, `referral_payouts/new_${p}`), { dealerCode: D1, referrerUid: "cust_b_uid", status: "pending" }),
  },
  {
    id: "create email_notifications",
    run: (db, p) => setDoc(doc(db, `email_notifications/new_${p}`), { type: "x" }),
  },

  // ── updates (no field a predicate reads is changed) ─────────────────────
  { id: "update users/custA display_name", run: (db, p) => setDoc(doc(db, "users/cust_a_uid"), { display_name: `n_${p}` }, { merge: true }) },
  { id: "update installations/inst_a", run: (db, p) => updateDoc(doc(db, "installations/inst_a"), { notes: `n_${p}` }) },
  { id: "update sales_jobs/job01", run: (db, p) => updateDoc(doc(db, "sales_jobs/job01"), { day1Notes: `n_${p}` }) },
  { id: "update sales_jobs/job02", run: (db, p) => updateDoc(doc(db, "sales_jobs/job02"), { day1Notes: `n_${p}` }) },
  { id: "set job01/materialList/current", run: (db, p) => setDoc(doc(db, "sales_jobs/job01/materialList/current"), { jobNumber: "NXG-1", dealerCode: D1, lines: [], notes: p }) },
  { id: "set dealers/01/pricing/current", run: (db) => setDoc(doc(db, "dealers/01/pricing/current"), { pricePerLinearFoot: 1 }) },
  { id: "set dealers/02/pricing/current", run: (db) => setDoc(doc(db, "dealers/02/pricing/current"), { pricePerLinearFoot: 1 }) },
  { id: "set dealers/01/config/messaging", run: (db) => setDoc(doc(db, "dealers/01/config/messaging"), { dealerCode: D1, senderName: "x" }, { merge: true }) },
  { id: "set dealers/01/shipping_address/primary", run: (db) => setDoc(doc(db, "dealers/01/shipping_address/primary"), { line1: "elsewhere" }) },
  { id: "set dealers/01/inventory/i1", run: (db) => setDoc(doc(db, "dealers/01/inventory/i1"), { quantityOnHand: 9 }) },
  { id: "set app_config/pricing_defaults", run: (db) => setDoc(doc(db, "app_config/pricing_defaults"), { pricePerLinearFoot: 1 }) },
  { id: "update installers/i01 name", run: (db, p) => updateDoc(doc(db, "installers/i01"), { name: `n_${p}` }) },
  { id: "update installers/i02 name", run: (db, p) => updateDoc(doc(db, "installers/i02"), { name: `n_${p}` }) },
  { id: "update dealer_orders/ord01 notes", run: (db, p) => updateDoc(doc(db, "dealer_orders/ord01"), { notes: `n_${p}` }) },
  { id: "update referral_payouts/pay01 notes", run: (db, p) => updateDoc(doc(db, "referral_payouts/pay01"), { notes: `n_${p}` }) },

  // ── deletes ──────────────────────────────────────────────────────────────
  { id: "delete installers/i01", run: (db) => deleteDoc(doc(db, "installers/i01")) },
  { id: "delete installers/i02", run: (db) => deleteDoc(doc(db, "installers/i02")) },
  { id: "delete dealer_orders/ord01 (draft)", run: (db) => deleteDoc(doc(db, "dealer_orders/ord01")) },
  { id: "delete dealer_orders/ord02 (draft)", run: (db) => deleteDoc(doc(db, "dealer_orders/ord02")) },
];

/**
 * Every intended behavioural delta, as "persona | request : OLD -> NEW".
 * Grouped by the change that causes it.
 */
const CUSTOMERS_OF_01 = ["custA", "custB"];
const SELF_STAMPED = ["custIdc"];
const ALL_CUSTOMERS = ["custA", "custB", "custSelf", "custIdc"];
const ADMIN_CLAIMS = ["admin01", "admin55"];
const d = (personas: string[], op: string, from: Outcome, to: Outcome) =>
  personas.map((p) => `${p} | ${op} : ${from} -> ${to}`);

const EXPECTED_BY_ITEM: Record<string, string[]> = {
  "1": [
    // Item 1 / R1: customers stamped with dealer_code 01 (and a self-stamped
    // installer_dealer_code) lose sales_jobs.
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "get sales_jobs/job01", "ALLOW", "DENY"),
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "list sales_jobs dealerCode==01", "ALLOW", "DENY"),
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "update sales_jobs/job01", "ALLOW", "DENY"),
    // Item 1 / R2: same customers lose dealer_orders (read, create, update,
    // delete-draft).
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "get dealer_orders/ord01", "ALLOW", "DENY"),
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "create dealer_orders dealer_code 01", "ALLOW", "DENY"),
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "update dealer_orders/ord01 notes", "ALLOW", "DENY"),
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "delete dealer_orders/ord01 (draft)", "ALLOW", "DENY"),
  ],
  "2": [
    // Item 2: inventoryLedger create opens to the dealer's own sales/installer
    // PIN sessions.
    ...d(["sales01", "inst01"], "create dealers/01/inventoryLedger/new", "DENY", "ALLOW"),
    ...d(["sales02", "inst02"], "create dealers/02/inventoryLedger/new", "DENY", "ALLOW"),
    // Item 2: pricing/config writes move from dealer ACCOUNT to admin-role
    // claims + owner. (Admin claims are cross-dealer by the existing
    // hasAdminClaim() design, so admin01 also reaches dealer 02's pricing.)
    ...d(["dealerAcct01"], "set dealers/01/pricing/current", "ALLOW", "DENY"),
    ...d([...ADMIN_CLAIMS, "owner"], "set dealers/01/pricing/current", "DENY", "ALLOW"),
    ...d([...ADMIN_CLAIMS, "owner"], "set dealers/02/pricing/current", "DENY", "ALLOW"),
    ...d(["dealerAcct01"], "set dealers/01/config/messaging", "ALLOW", "DENY"),
    ...d([...ADMIN_CLAIMS, "owner"], "set dealers/01/config/messaging", "DENY", "ALLOW"),
    // Item 2: shipping_address write was open to sales/installer PINs (the
    // audit table missed that isDealerMember() includes hasStaffClaim) — now
    // admin-role claims + owner only.
    ...d(["dealerAcct01", "sales01", "inst01"], "set dealers/01/shipping_address/primary", "ALLOW", "DENY"),
  ],
  "3": [
    // Item 3 / R3: dealer_code / installer_dealer_code customers lose
    // referral_payouts read. custB keeps get via the referrerUid arm (it is
    // the referrer) but loses the dealer-wide list.
    ...d(["custA", ...SELF_STAMPED], "get referral_payouts/pay01", "ALLOW", "DENY"),
    ...d([...CUSTOMERS_OF_01, ...SELF_STAMPED], "list referral_payouts dealerCode==01", "ALLOW", "DENY"),
    // Item 3 / R4: a dealer ACCOUNT is scoped to its own dealer on /installers,
    // and cannot create an admin-role installer (which would mint a
    // cross-dealer admin claim). Corporate user_role admin keeps global reach.
    ...d(["dealerAcct01"], "create installers dealer 02 role installer", "ALLOW", "DENY"),
    ...d(["dealerAcct01"], "create installers dealer 01 role admin", "ALLOW", "DENY"),
    ...d(["dealerAcct01"], "update installers/i02 name", "ALLOW", "DENY"),
    ...d(["dealerAcct01"], "delete installers/i02", "ALLOW", "DENY"),
    // Item 3 / R5: pricing_defaults read narrows to staff + admin/owner claims;
    // write opens to admin claims (corporate Admin tab).
    ...d(["anonSession", ...ALL_CUSTOMERS, "dealerAcct01", "corpAdminAcct", "mediaAcct"], "get app_config/pricing_defaults", "ALLOW", "DENY"),
    ...d(ADMIN_CLAIMS, "set app_config/pricing_defaults", "DENY", "ALLOW"),
  ],
  "4": [
    // Item 4: materialList / materialLedger narrow from any-signed-in to the
    // job's stakeholders + corporate.
    ...d(["anonSession", ...ALL_CUSTOMERS, "sales02", "inst02"], "get job01/materialList/current", "ALLOW", "DENY"),
    ...d(["anonSession", ...ALL_CUSTOMERS, "sales02", "inst02"], "get job01/materialLedger/l1", "ALLOW", "DENY"),
    ...d(["anonSession", ...ALL_CUSTOMERS, "sales02", "inst02"], "create job01/materialList/new", "ALLOW", "DENY"),
    ...d(["anonSession", ...ALL_CUSTOMERS, "sales02", "inst02"], "create job01/materialLedger/new", "ALLOW", "DENY"),
    ...d(["anonSession", ...ALL_CUSTOMERS, "sales02", "inst02"], "set job01/materialList/current", "ALLOW", "DENY"),
    ...d(["anonSession", ...ALL_CUSTOMERS, "sales01", "inst01", "dealerAcct01"], "create job02/materialLedger/new", "ALLOW", "DENY"),
  ],
  "5": [
    // Item 5: sales_jobs create requires a staff claim for the new doc's
    // dealerCode, or an admin/owner claim.
    ...d(["anonSession", ...ALL_CUSTOMERS, "dealerAcct01", "corpAdminAcct", "mediaAcct", "sales02", "inst02"],
      "create sales_jobs dealerCode 01 (client payload)", "ALLOW", "DENY"),
    ...d(["anonSession", ...ALL_CUSTOMERS, "dealerAcct01", "corpAdminAcct", "mediaAcct", "sales01", "inst01"],
      "create sales_jobs dealerCode 02 (client payload)", "ALLOW", "DENY"),
    ...d(["anonSession", ...ALL_CUSTOMERS, "dealerAcct01", "corpAdminAcct", "mediaAcct", "sales01", "sales02", "inst01", "inst02"],
      "create sales_jobs dealerCode '' (client payload)", "ALLOW", "DENY"),
  ],
};

// DIFF_ITEMS=1,2 limits the expectation to those items (per-commit runs).
const ITEMS = (process.env.DIFF_ITEMS ?? Object.keys(EXPECTED_BY_ITEM).join(","))
  .split(",").map((x) => x.trim()).filter(Boolean);
const EXPECTED_DELTAS: string[] = ITEMS.flatMap((i) => EXPECTED_BY_ITEM[i] ?? []);

let oldEnv: RulesTestEnvironment;
let newEnv: RulesTestEnvironment;

function oldRules(): string {
  return execFileSync("git", ["-C", "..", "show", `${BASELINE_REF}:firestore.rules`], {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
}

beforeAll(async () => {
  oldEnv = await initializeTestEnvironment({
    projectId: OLD_PROJECT,
    firestore: { rules: oldRules(), host: "127.0.0.1", port: 8080 },
  });
  newEnv = await initializeTestEnvironment({
    projectId: NEW_PROJECT,
    firestore: { rules: readFileSync("../firestore.rules", "utf8"), host: "127.0.0.1", port: 8080 },
  });
}, HOOK_TIMEOUT_MS);

afterAll(async () => {
  await oldEnv?.cleanup();
  await newEnv?.cleanup();
});

async function outcome(fn: () => Promise<unknown>): Promise<Outcome> {
  try {
    await fn();
    return "ALLOW";
  } catch (e) {
    const code = (e as { code?: string }).code ?? "";
    if (code === "permission-denied") return "DENY";
    return `ERROR:${code || (e as Error).message}`;
  }
}

async function runMatrix(env: RulesTestEnvironment): Promise<Record<string, Outcome>> {
  const out: Record<string, Outcome> = {};
  for (const p of PERSONA_KEYS) {
    await reseed(env);
    const db = ctxFor(env, p).firestore() as unknown as Firestore;
    for (const op of OPS) {
      out[`${p} | ${op.id}`] = await outcome(() => op.run(db, p));
    }
  }
  return out;
}

test(
  `dealer-tools allow matrix: deltas vs ${BASELINE_REF} are exactly the intended set`,
  async () => {
    const before = await runMatrix(oldEnv);
    const after = await runMatrix(newEnv);

    const errors = Object.entries({ ...before, ...after }).filter(([, v]) => v.startsWith("ERROR"));
    const deltas = Object.keys(before)
      .filter((k) => before[k] !== after[k])
      .map((k) => `${k} : ${before[k]} -> ${after[k]}`)
      .sort();

    if (process.env.DIFF_OUT) {
      writeFileSync(
        process.env.DIFF_OUT,
        JSON.stringify(
          { baseline: BASELINE_REF, personas: PERSONA_KEYS, ops: OPS.map((o) => o.id), before, after, deltas },
          null,
          2,
        ),
      );
    }

    expect(errors).toEqual([]);
    const expected = process.env.DIFF_EXPECT === "none" ? [] : [...EXPECTED_DELTAS].sort();
    const unexpected = deltas.filter((x) => !expected.includes(x));
    const missing = expected.filter((x) => !deltas.includes(x));
    expect({ unexpected, missing }).toEqual({ unexpected: [], missing: [] });
  },
  MATRIX_TIMEOUT_MS,
);
