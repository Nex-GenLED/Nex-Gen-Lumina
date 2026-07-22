/**
 * D3-S2 — cross-dealer isolation, per claim tier.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * THE DEFECT THIS CLOSES
 *
 * hasMediaAccess() resolved `user_role in ['media','dealer','admin']` and was
 * OR'd into ~16 rules — including every isDealerMember() and sales_jobs'
 * isJobStakeholder(). So EVERY dealer satisfied EVERY other dealer's
 * membership test: dealer A could read, and in most cases WRITE, dealer B's
 * customers, pipeline, pricing, stock, and ship-to address. The paths were
 * partitioned; the guard was not.
 *
 * D3-S2 swapped all 16 sites individually (search "D3-S2 SITE" in
 * firestore.rules) and deleted hasMediaAccess() outright so it cannot be
 * reached for again.
 *
 * TIERS UNDER TEST
 *   • dealer-scoped  — a dealer's own staff (user-doc dealer_code, or a
 *                      hasStaffClaim(dealerCode) PIN session)
 *   • corporate      — isMediaOrAdmin(): media/admin user_role, NOT dealer
 *   • admin/owner    — hasAdminOrOwnerClaim(): mintStaffToken admin/owner
 *
 * The load-bearing assertion in every group is the same: DEALER A IS DENIED
 * DEALER B'S DATA.
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test-isolation";

const A = "55"; // dealer A
const B = "56"; // dealer B

const DEALER_A_UID = "dealer-a-uid";
const DEALER_B_UID = "dealer-b-uid";
const MEDIA_UID = "media-uid";
const CUSTOMER_A_UID = "customer-of-a-uid";

let env: RulesTestEnvironment;

// Explicit hook timeouts — jest's default is 5s, which is NOT enough here:
//   • beforeAll compiles + loads the full ruleset (~1750 lines) into a
//     possibly-cold emulator.
//   • beforeEach seeds ~25 docs across 8 collections.
// Both routinely exceed 5s under full-suite load. This is the same failure
// mode that makes setAccountProfile.emulator.test.ts flaky (its
// beforeEach(wipe) does full collection scans + recursiveDelete inside the
// same 5s default) — worth fixing there too, separately.
const HOOK_TIMEOUT_MS = 60_000;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync("../firestore.rules", "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
}, HOOK_TIMEOUT_MS);

afterAll(async () => {
  // Guard: if beforeAll timed out, env is undefined and an unguarded
  // env.cleanup() masks the real error with a TypeError.
  if (env) await env.cleanup();
}, HOOK_TIMEOUT_MS);

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Two dealer-role accounts, each affiliated with their own dealer.
    await setDoc(doc(db, `users/${DEALER_A_UID}`), {
      user_role: "dealer",
      dealer_code: A,
      display_name: "Dealer A Owner",
      email: "a@example.com",
    });
    await setDoc(doc(db, `users/${DEALER_B_UID}`), {
      user_role: "dealer",
      dealer_code: B,
      display_name: "Dealer B Owner",
      email: "b@example.com",
    });
    // Corporate content role.
    await setDoc(doc(db, `users/${MEDIA_UID}`), {
      user_role: "media",
      display_name: "Media User",
      email: "m@example.com",
    });
    // A customer belonging to dealer A.
    await setDoc(doc(db, `users/${CUSTOMER_A_UID}`), {
      user_role: "residential",
      dealer_code: A,
      display_name: "Customer of A",
      email: "c@example.com",
      id: CUSTOMER_A_UID,
      owner_id: CUSTOMER_A_UID,
    });

    // Dealer docs
    await setDoc(doc(db, `dealers/${A}`), { dealerCode: A, name: "Dealer A" });
    await setDoc(doc(db, `dealers/${B}`), { dealerCode: B, name: "Dealer B" });

    // Per-dealer subcollections
    for (const code of [A, B]) {
      await setDoc(doc(db, `dealers/${code}/pricing/current`), {
        pricePerLinearFoot: 18,
      });
      await setDoc(doc(db, `dealers/${code}/config/messaging`), { tpl: "hi" });
      await setDoc(doc(db, `dealers/${code}/inventory/mat1`), {
        quantityOnHand: 10,
      });
      await setDoc(doc(db, `dealers/${code}/sku_inventory/NGL-1`), {
        in_warehouse: 5,
      });
      await setDoc(doc(db, `dealers/${code}/shipping_address/primary`), {
        line1: "1 Main St",
      });
      await setDoc(doc(db, `dealers/${code}/materialCatalog/mat1`), {
        unitCostCents: 100,
      });
    }

    // Jobs, install records, payouts — one per dealer
    for (const code of [A, B]) {
      await setDoc(doc(db, `sales_jobs/job-${code}`), {
        dealerCode: code,
        customerName: `Prospect of ${code}`,
        totalPriceUsd: 5000,
      });
      await setDoc(doc(db, `installation_records/rec-${code}`), {
        dealer_code: code,
        installer_code: "01",
      });
      await setDoc(doc(db, `referral_payouts/pay-${code}`), {
        dealerCode: code,
        referrerUid: "someone",
        status: "pending",
      });
    }
  });
}, HOOK_TIMEOUT_MS);

// ── Contexts ────────────────────────────────────────────────────────────────
/** A dealer-role ACCOUNT (user_role:'dealer'), no PIN session. */
const dealerAcct = (uid: string) => env.authenticatedContext(uid).firestore();
/** A PIN session scoped to one dealer (mintStaffToken installer branch). */
const staff = (dealerCode: string) =>
  env
    .authenticatedContext(`staff_installer_${dealerCode}01`, {
      role: "installer",
      dealerCode,
    })
    .firestore();
/** Corporate content role — isMediaOrAdmin() includes media. */
const media = () => env.authenticatedContext(MEDIA_UID).firestore();
const adminClaim = () =>
  env.authenticatedContext("staff_admin_5501", { role: "admin" }).firestore();
const ownerClaim = () =>
  env.authenticatedContext("staff_owner_9999", { role: "owner" }).firestore();

// ════════════════════════════════════════════════════════════════════════════
// THE HEADLINE: dealer A must never reach dealer B
// ════════════════════════════════════════════════════════════════════════════
describe("cross-dealer isolation — dealer A denied dealer B (the ~16-site defect)", () => {
  test("dealers doc: A cannot read B's", async () => {
    await assertFails(getDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${B}`)));
  });

  test("installation_records: A cannot read B's install activity", async () => {
    await assertFails(
      getDoc(doc(dealerAcct(DEALER_A_UID), `installation_records/rec-${B}`)),
    );
  });

  test("materialCatalog: A cannot read B's cost basis", async () => {
    await assertFails(
      getDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${B}/materialCatalog/mat1`)),
    );
  });

  test("pricing: A cannot READ B's pricing", async () => {
    await assertFails(
      getDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${B}/pricing/current`)),
    );
  });

  test("pricing: A cannot WRITE B's pricing", async () => {
    await assertFails(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${B}/pricing/current`), {
        pricePerLinearFoot: 1,
      }),
    );
  });

  test("sales_jobs: A cannot read B's pipeline", async () => {
    await assertFails(
      getDoc(doc(dealerAcct(DEALER_A_UID), `sales_jobs/job-${B}`)),
    );
  });

  test("sales_jobs: A cannot UPDATE B's job (the widest old leak)", async () => {
    await assertFails(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `sales_jobs/job-${B}`), {
        totalPriceUsd: 1,
      }),
    );
  });

  test("inventory: A cannot read or write B's stock", async () => {
    await assertFails(
      getDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${B}/inventory/mat1`)),
    );
    await assertFails(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${B}/inventory/mat1`), {
        quantityOnHand: 0,
      }),
    );
  });

  test("sku_inventory: A cannot write B's warehouse", async () => {
    await assertFails(
      updateDoc(
        doc(dealerAcct(DEALER_A_UID), `dealers/${B}/sku_inventory/NGL-1`),
        { in_warehouse: 0 },
      ),
    );
  });

  test("shipping_address: A cannot REDIRECT B's shipments", async () => {
    await assertFails(
      updateDoc(
        doc(dealerAcct(DEALER_A_UID), `dealers/${B}/shipping_address/primary`),
        { line1: "attacker st" },
      ),
    );
  });

  test("config: A cannot rewrite B's customer messaging templates", async () => {
    await assertFails(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${B}/config/messaging`), {
        tpl: "spam",
      }),
    );
  });

  test("referral_payouts: A cannot rewrite B's payouts", async () => {
    await assertFails(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `referral_payouts/pay-${B}`), {
        status: "approved",
      }),
    );
  });

  test("users: A cannot read B's customer (canReadUserData fan-out)", async () => {
    // Site 1 — the 10-consumer helper. A dealer could read EVERY customer.
    const customerOfB = "customer-of-b-uid";
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${customerOfB}`), {
        user_role: "residential",
        dealer_code: B,
        display_name: "Customer of B",
        email: "cb@example.com",
      });
    });
    await assertFails(
      getDoc(doc(dealerAcct(DEALER_A_UID), `users/${customerOfB}`)),
    );
  });
});

// ════════════════════════════════════════════════════════════════════════════
// TIER: dealer-scoped — a dealer keeps its OWN data
// ════════════════════════════════════════════════════════════════════════════
describe("tier: dealer-scoped — own-dealer access preserved", () => {
  test("dealer account reads its OWN pricing", async () => {
    await assertSucceeds(
      getDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${A}/pricing/current`)),
    );
  });

  test("dealer account WRITES its OWN pricing", async () => {
    await assertSucceeds(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${A}/pricing/current`), {
        pricePerLinearFoot: 20,
      }),
    );
  });

  test("dealer account reads/writes its OWN inventory", async () => {
    await assertSucceeds(
      getDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${A}/inventory/mat1`)),
    );
    await assertSucceeds(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `dealers/${A}/inventory/mat1`), {
        quantityOnHand: 9,
      }),
    );
  });

  test("dealer account reads its OWN sales job", async () => {
    await assertSucceeds(
      getDoc(doc(dealerAcct(DEALER_A_UID), `sales_jobs/job-${A}`)),
    );
  });

  test("dealer account updates its OWN sales job", async () => {
    await assertSucceeds(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `sales_jobs/job-${A}`), {
        totalPriceUsd: 6000,
      }),
    );
  });

  test("dealer account rewrites its OWN payout", async () => {
    await assertSucceeds(
      updateDoc(doc(dealerAcct(DEALER_A_UID), `referral_payouts/pay-${A}`), {
        status: "approved",
      }),
    );
  });

  test("dealer account reads its OWN customer", async () => {
    // The /users staff/dealer branch — a dealer keeps its own customers.
    await assertSucceeds(
      getDoc(doc(dealerAcct(DEALER_A_UID), `users/${CUSTOMER_A_UID}`)),
    );
  });

  test("STAFF CLAIM reads its own dealer doc (site 2)", async () => {
    await assertSucceeds(getDoc(doc(staff(A), `dealers/${A}`)));
  });

  test("STAFF CLAIM denied ANOTHER dealer's doc", async () => {
    await assertFails(getDoc(doc(staff(A), `dealers/${B}`)));
  });

  test("STAFF CLAIM reads its own materialCatalog (site 12)", async () => {
    await assertSucceeds(
      getDoc(doc(staff(A), `dealers/${A}/materialCatalog/mat1`)),
    );
  });

  test("STAFF CLAIM denied another dealer's materialCatalog", async () => {
    await assertFails(
      getDoc(doc(staff(A), `dealers/${B}/materialCatalog/mat1`)),
    );
  });

  test("STAFF CLAIM reads its own installation_records (site 6)", async () => {
    await assertSucceeds(
      getDoc(doc(staff(A), `installation_records/rec-${A}`)),
    );
  });

  test("STAFF CLAIM denied another dealer's installation_records", async () => {
    await assertFails(getDoc(doc(staff(A), `installation_records/rec-${B}`)));
  });
});

// ════════════════════════════════════════════════════════════════════════════
// TIER: corporate (isMediaOrAdmin) — global read, no dealer
// ════════════════════════════════════════════════════════════════════════════
describe("tier: corporate — media/admin keep global read, dealers do not", () => {
  test("media reads ANY dealer's sales job", async () => {
    await assertSucceeds(getDoc(doc(media(), `sales_jobs/job-${A}`)));
    await assertSucceeds(getDoc(doc(media(), `sales_jobs/job-${B}`)));
  });

  test("media reads ANY customer (canReadUserData still admits media)", async () => {
    await assertSucceeds(getDoc(doc(media(), `users/${CUSTOMER_A_UID}`)));
  });

  test("media reads ANY installation_records", async () => {
    await assertSucceeds(getDoc(doc(media(), `installation_records/rec-${B}`)));
  });

  test("media CANNOT write a dealer's inventory (deliberate narrowing)", async () => {
    // isDealerMember() now excludes media entirely: a content role has no
    // business writing stock, and no client path does.
    await assertFails(
      updateDoc(doc(media(), `dealers/${A}/inventory/mat1`), {
        quantityOnHand: 0,
      }),
    );
  });
});

// ════════════════════════════════════════════════════════════════════════════
// TIER: admin / owner — corporate override intact
// ════════════════════════════════════════════════════════════════════════════
describe("tier: admin/owner — override intact across dealers", () => {
  test("admin claim reads both dealers' jobs", async () => {
    await assertSucceeds(getDoc(doc(adminClaim(), `sales_jobs/job-${A}`)));
    await assertSucceeds(getDoc(doc(adminClaim(), `sales_jobs/job-${B}`)));
  });

  test("admin claim reads both dealers' docs", async () => {
    await assertSucceeds(getDoc(doc(adminClaim(), `dealers/${A}`)));
    await assertSucceeds(getDoc(doc(adminClaim(), `dealers/${B}`)));
  });

  test("admin claim reads any dealer's pricing + materialCatalog", async () => {
    await assertSucceeds(
      getDoc(doc(adminClaim(), `dealers/${B}/pricing/current`)),
    );
    await assertSucceeds(
      getDoc(doc(adminClaim(), `dealers/${B}/materialCatalog/mat1`)),
    );
  });

  test("admin claim writes any dealer's inventory (support path)", async () => {
    await assertSucceeds(
      updateDoc(doc(adminClaim(), `dealers/${B}/inventory/mat1`), {
        quantityOnHand: 3,
      }),
    );
  });

  test("owner claim reads across dealers", async () => {
    await assertSucceeds(getDoc(doc(ownerClaim(), `dealers/${B}`)));
    await assertSucceeds(getDoc(doc(ownerClaim(), `sales_jobs/job-${B}`)));
  });

  test("admin claim reads any installation_records", async () => {
    await assertSucceeds(
      getDoc(doc(adminClaim(), `installation_records/rec-${B}`)),
    );
  });
});

// ════════════════════════════════════════════════════════════════════════════
// A plain customer must reach none of it
// ════════════════════════════════════════════════════════════════════════════
describe("plain customer is denied dealer surfaces", () => {
  // FINDING A (pre-existing, NOT caused by the hasMediaAccess sweep):
  // isDealerMember() accepted a bare `users.dealer_code == dealerCode`, and
  // the installer wizard stamps dealer_code onto every CUSTOMER's user doc
  // (installer_setup_wizard.dart:912). So every customer was a "member" of
  // their own dealer. pricing/inventory/config/shipping_address are
  // `allow write: if isDealerMember()` — meaning a CUSTOMER could rewrite
  // their dealer's prices. isDealerStaffAccount() now requires
  // user_role in ['dealer','admin'], so affiliation is no longer authority.
  test("customer cannot read a dealer doc / catalog / pricing / records", async () => {
    const c = dealerAcct(CUSTOMER_A_UID);
    await assertFails(getDoc(doc(c, `dealers/${A}`)));
    await assertFails(getDoc(doc(c, `dealers/${A}/materialCatalog/mat1`)));
    await assertFails(getDoc(doc(c, `dealers/${A}/pricing/current`)));
    await assertFails(getDoc(doc(c, `installation_records/rec-${A}`)));
  });

  test("customer of A cannot WRITE dealer A's pricing (the live hole)", async () => {
    await assertFails(
      updateDoc(
        doc(dealerAcct(CUSTOMER_A_UID), `dealers/${A}/pricing/current`),
        { pricePerLinearFoot: 1 },
      ),
    );
  });

  test("customer of A cannot WRITE dealer A's inventory / shipping / config", async () => {
    const c = dealerAcct(CUSTOMER_A_UID);
    await assertFails(
      updateDoc(doc(c, `dealers/${A}/inventory/mat1`), { quantityOnHand: 0 }),
    );
    await assertFails(
      updateDoc(doc(c, `dealers/${A}/shipping_address/primary`), {
        line1: "attacker st",
      }),
    );
    await assertFails(
      updateDoc(doc(c, `dealers/${A}/config/messaging`), { tpl: "spam" }),
    );
  });

  test("customer of A cannot create a payout against dealer A", async () => {
    await assertFails(
      setDoc(doc(dealerAcct(CUSTOMER_A_UID), "referral_payouts/forged"), {
        dealerCode: A,
        referrerUid: CUSTOMER_A_UID,
        status: "approved",
      }),
    );
  });

  test("customer still reads their OWN user doc", async () => {
    await assertSucceeds(
      getDoc(doc(dealerAcct(CUSTOMER_A_UID), `users/${CUSTOMER_A_UID}`)),
    );
  });
});
