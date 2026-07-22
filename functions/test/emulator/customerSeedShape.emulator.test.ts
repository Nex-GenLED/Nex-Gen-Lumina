/**
 * C2 — createCustomerAccount's seeded user-doc SHAPE contract.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * SCOPE — this asserts the FIELD-SHAPE CONTRACT, not the callable itself.
 * Invoking createCustomerAccount end-to-end needs the Auth emulator
 * (createUser / generatePasswordResetLink), and firebase.json configures only
 * the Firestore emulator. What actually broke was never the control flow — it
 * was the shape of the document the function writes. So these tests seed the
 * OLD (camelCase) and NEW (snake_case) shapes and prove, through the real
 * deployed rules, that the new one is reachable and the old one is not.
 *
 * The bug (pre-C2): the seed wrote camelCase (`displayName`, `dealerCode`,
 * `createdAt`) while the entire rest of the system reads snake_case
 * `dealer_code`. Consequences:
 *
 *   1. firestore.rules:158-162 gates installer/salesperson reads on
 *      resource.data.get('dealer_code','') == token.dealerCode → a camelCase
 *      doc never matches → the customer is INVISIBLE to every PIN session.
 *   2. installer_setup_wizard.dart:751-757 looks the customer up with
 *      .where('dealer_code', ==, code) and treats an empty result as a HARD
 *      error (:759-772) → a wrap-up-created customer could not be picked up
 *      by the installer wizard. The two halves of the install flow did not
 *      compose.
 *
 * Asserts:
 *   • an installer PIN session CAN read a snake_case-seeded customer
 *   • a salesperson PIN session CAN read it
 *   • the SAME session CANNOT read the old camelCase doc (proves the bug)
 *   • the wizard's exact dealer_code query returns the snake_case customer
 *     and does NOT return the camelCase one (proves "survives the wizard")
 *   • a foreign dealer's PIN session cannot read either (scoping intact)
 *   • the seeded doc carries every field UserModel.fromJson casts non-null
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { doc, getDoc, getDocs, collection, query, where } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test-customerseed";

const DEALER = "55";
const OTHER_DEALER = "56";

const NEW_UID = "customer-snake-uid";
const OLD_UID = "customer-camel-uid";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync("../firestore.rules", "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

/**
 * EXACTLY the shape createCustomerAccount seeds after C2
 * (createCustomerAccount.ts, "Seed the user document").
 * Keep in sync with that block.
 */
const snakeSeed = {
  id: NEW_UID,
  owner_id: NEW_UID,
  email: "jane@example.com",
  display_name: "Jane Customer",
  dealer_code: DEALER,
  installation_role: "primary",
  job_id: "job-abc",
  created_at: new Date(),
  updated_at: new Date(),
};

/** The pre-C2 camelCase shape — the regression we must never ship again. */
const camelSeed = {
  displayName: "John Camel",
  email: "john@example.com",
  dealerCode: DEALER,
  jobId: "job-def",
  installation_role: "primary",
  createdAt: new Date(),
};

async function seed(uid: string, data: Record<string, unknown>) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`users/${uid}`).set(data);
  });
}

/** A staff PIN session: mintStaffToken's installer/salesperson branch. */
const staff = (role: "installer" | "salesperson", dealerCode: string) =>
  env
    .authenticatedContext(`staff_${role}_${dealerCode}01`, {
      role,
      dealerCode,
    })
    .firestore();

describe("C2 — a wrap-up-created customer is visible to PIN sessions", () => {
  test("installer PIN session CAN read the snake_case customer", async () => {
    await seed(NEW_UID, snakeSeed);
    const db = staff("installer", DEALER);
    await assertSucceeds(getDoc(doc(db, `users/${NEW_UID}`)));
  });

  test("salesperson PIN session CAN read the snake_case customer", async () => {
    await seed(NEW_UID, snakeSeed);
    const db = staff("salesperson", DEALER);
    await assertSucceeds(getDoc(doc(db, `users/${NEW_UID}`)));
  });

  test("the OLD camelCase doc is INVISIBLE to the same session (the bug)", async () => {
    await seed(OLD_UID, camelSeed);
    const db = staff("installer", DEALER);
    // resource.data.get('dealer_code','') is '' on a camelCase doc, so the
    // rule's staff branch cannot match — firestore.rules:158-162.
    await assertFails(getDoc(doc(db, `users/${OLD_UID}`)));
  });

  test("a FOREIGN dealer's PIN session cannot read the customer (scoping intact)", async () => {
    await seed(NEW_UID, snakeSeed);
    const db = staff("installer", OTHER_DEALER);
    await assertFails(getDoc(doc(db, `users/${NEW_UID}`)));
  });
});

describe("C2 — the customer survives the installer wizard's lookup", () => {
  test("the wizard's exact dealer_code query FINDS the snake_case customer", async () => {
    await seed(NEW_UID, snakeSeed);
    const db = staff("installer", DEALER);

    // Mirrors installer_setup_wizard.dart:751-757. An empty result is a HARD
    // error there (:759-772) — "No existing customer matches this email under
    // your dealer code" — so this query returning the doc is exactly what
    // "survives the wizard" means.
    const q = query(
      collection(db, "users"),
      where("dealer_code", "==", DEALER),
    );
    const snap = await assertSucceeds(getDocs(q));
    expect(snap.docs.map((d) => d.id)).toContain(NEW_UID);
  });

  test("the same query does NOT return a camelCase customer (pre-C2 hard-fail)", async () => {
    await seed(OLD_UID, camelSeed);
    const db = staff("installer", DEALER);

    const q = query(
      collection(db, "users"),
      where("dealer_code", "==", DEALER),
    );
    const snap = await assertSucceeds(getDocs(q));
    expect(snap.docs.map((d) => d.id)).not.toContain(OLD_UID);
    expect(snap.empty).toBe(true);
  });

  test("both shapes present: the query returns ONLY the snake_case one", async () => {
    await seed(NEW_UID, snakeSeed);
    await seed(OLD_UID, camelSeed);
    const db = staff("installer", DEALER);

    const q = query(
      collection(db, "users"),
      where("dealer_code", "==", DEALER),
    );
    const snap = await assertSucceeds(getDocs(q));
    expect(snap.docs.map((d) => d.id)).toEqual([NEW_UID]);
  });
});

describe("C2 — the seed satisfies UserModel.fromJson", () => {
  test("carries every field fromJson casts non-null", () => {
    // user_model.dart:404-410 does unguarded casts:
    //   json['id'] as String, json['email'] as String,
    //   json['display_name'] as String, json['owner_id'] as String,
    //   (json['created_at'] as Timestamp), (json['updated_at'] as Timestamp)
    // A missing key throws "Null is not a subtype of String", which
    // customer_lookup_service.dart:28 swallows into a silent null.
    for (const k of [
      "id",
      "email",
      "display_name",
      "owner_id",
      "created_at",
      "updated_at",
    ]) {
      expect(Object.keys(snakeSeed)).toContain(k);
    }
  });

  test("the old camelCase shape supplied NONE of them (why fromJson threw)", () => {
    for (const k of ["id", "display_name", "owner_id", "created_at", "updated_at"]) {
      expect(Object.keys(camelSeed)).not.toContain(k);
    }
  });
});
