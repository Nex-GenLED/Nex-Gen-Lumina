/**
 * Firestore security-rules tests for the D0 privilege-field escalation guard
 * on /users/{userId} create + update.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * Threat being closed: /users create+update carry a broad
 * `|| request.auth != null` disjunct, which let ANY authenticated caller —
 * including an anonymous one — set `user_role: 'admin'` on their own doc and
 * thereby satisfy hasMediaAccess()/isUserRoleAdmin() (global cross-dealer read
 * of every customer + write on corporate catalogs). It also let anyone rewrite
 * `dealer_code`, reassigning a customer between dealers.
 *
 * The broad grant is INTENTIONALLY still present for all other fields: the
 * installer wizard writes the customer doc under an ANONYMOUS session
 * (installer_setup_wizard.dart:731 signInAnonymously → :937 set(merge:true)),
 * so it has no staff claim. Re-minting the staff token there is the P1
 * structural fix; this hotfix only constrains the two privilege fields.
 *
 * Asserts:
 *   • anonymous CAN still create/update a customer doc without role fields
 *   • anonymous CAN still write the wizard's REAL field set
 *     (user_role:'residential' + dealer_code) — the install flow must not break
 *   • anonymous / dealer / random-auth CANNOT set user_role:'admin' (or
 *     'dealer' / 'media') on their own or anyone else's doc, on create OR update
 *   • an admin-claim caller CAN
 *   • dealer_code: set-when-absent allowed; REASSIGNMENT denied without a claim
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { setDoc, updateDoc, doc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test-privfields";

const VICTIM = "victim-uid";
const ATTACKER = "attacker-uid";
const DEALER_A = "dealer-a-uid";
const ANON_WIZARD = "anon-wizard-uid";

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

const userDoc = (uid: string) => `users/${uid}`;

/** Minimal profile-only payload — no privilege fields at all. */
const profileOnly = {
  display_name: "Jane Customer",
  email: "jane@example.com",
  phone_number: "555-0100",
};

/**
 * The installer wizard's REAL field shape. UserModel.toJson() ALWAYS emits
 * user_role (user_model.dart:569) and emits dealer_code when non-null (:595);
 * the wizard sets both (installer_setup_wizard.dart:912). This payload is the
 * regression guard: if the D0 guard ever rejects this, every install breaks.
 */
const wizardWrite = {
  display_name: "Jane Customer",
  email: "jane@example.com",
  owner_id: VICTIM,
  id: VICTIM,
  user_role: "residential",
  dealer_code: "55",
  installation_role: "primary",
  must_reset_password: true,
  welcome_completed: false,
};

/** Seed a doc bypassing rules. */
async function seed(uid: string, data: Record<string, unknown>) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), userDoc(uid)), data);
  });
}

// ── Contexts ────────────────────────────────────────────────────────────────
//
// IMPORTANT — "anonymous" here means Firebase ANONYMOUS AUTH
// (FirebaseAuth.signInAnonymously(), which is what the installer wizard calls
// at installer_setup_wizard.dart:731). That produces a REAL authenticated
// session with a uid, so `request.auth != null` is TRUE and the broad grant
// applies. It is NOT the same as env.unauthenticatedContext(), which models a
// signed-OUT caller (request.auth == null) and has always been denied by the
// `|| request.auth != null` disjunct. Both are covered below, separately.
const anonAuth = () =>
  env
    .authenticatedContext(ANON_WIZARD, { provider_id: "anonymous" })
    .firestore();
const signedOut = () => env.unauthenticatedContext().firestore();
const authed = (uid: string) => env.authenticatedContext(uid).firestore();

/** A staff session with the admin claim (mintStaffToken mode:'admin'). */
const adminClaim = () =>
  env.authenticatedContext("staff_admin_5501", { role: "admin" }).firestore();

/** A staff session with the owner claim (mode:'owner'; no dealerCode claim). */
const ownerClaim = () =>
  env.authenticatedContext("staff_owner_9999", { role: "owner" }).firestore();

/** A dealer-role user (user_role:'dealer' on their doc, NO admin claim). */
async function dealerCtx() {
  await seed(DEALER_A, { user_role: "dealer", display_name: "Dealer A" });
  return authed(DEALER_A);
}

// ── 1. The broad grant must SURVIVE for non-privilege writes ────────────────
describe("anonymous customer-doc writes still work (wizard must not break)", () => {
  test("anonymous CAN create a customer doc with no role fields", async () => {
    await assertSucceeds(setDoc(doc(anonAuth(), userDoc(VICTIM)), profileOnly));
  });

  test("anonymous CAN update a customer doc with no role fields", async () => {
    await seed(VICTIM, profileOnly);
    await assertSucceeds(
      updateDoc(doc(anonAuth(), userDoc(VICTIM)), { phone_number: "555-0199" }),
    );
  });

  test("anonymous CAN write the wizard's REAL field set (user_role:'residential' + dealer_code)", async () => {
    await assertSucceeds(setDoc(doc(anonAuth(), userDoc(VICTIM)), wizardWrite));
  });

  test("anonymous CAN stamp dealer_code onto a self-registered customer (set-when-absent merge)", async () => {
    await seed(VICTIM, { user_role: "residential", display_name: "Self Reg" });
    await assertSucceeds(
      updateDoc(doc(anonAuth(), userDoc(VICTIM)), { dealer_code: "55" }),
    );
  });

  test("anonymous CAN re-run the wizard for the SAME dealer (dealer_code unchanged)", async () => {
    await seed(VICTIM, { user_role: "residential", dealer_code: "55" });
    await assertSucceeds(setDoc(doc(anonAuth(), userDoc(VICTIM)), wizardWrite));
  });

  test("an existing privileged user can still save their own profile (role UNCHANGED)", async () => {
    await seed(DEALER_A, { user_role: "dealer", display_name: "Dealer A" });
    await assertSucceeds(
      updateDoc(doc(authed(DEALER_A), userDoc(DEALER_A)), {
        user_role: "dealer",
        phone_number: "555-0123",
      }),
    );
  });
});

// ── 1b. Signed-OUT (no auth at all) — unchanged pre-existing behavior ───────
// Distinct from anonymous auth above. request.auth == null fails the broad
// `|| request.auth != null` disjunct outright, so these were already denied
// before D0. Asserted here so the distinction stays explicit and a future
// change to the disjunct can't silently open it.
describe("signed-out callers are denied (pre-existing, not a D0 behavior)", () => {
  test("signed-out CANNOT create a customer doc", async () => {
    await assertFails(setDoc(doc(signedOut(), userDoc(VICTIM)), profileOnly));
  });

  test("signed-out CANNOT update a customer doc", async () => {
    await seed(VICTIM, profileOnly);
    await assertFails(
      updateDoc(doc(signedOut(), userDoc(VICTIM)), { phone_number: "555-0199" }),
    );
  });

  test("signed-out CANNOT set user_role:'admin'", async () => {
    await assertFails(
      setDoc(doc(signedOut(), userDoc(ATTACKER)), {
        ...profileOnly,
        user_role: "admin",
      }),
    );
  });
});

// ── 2. Escalation must be DENIED ────────────────────────────────────────────
describe("user_role escalation is denied without an admin/owner claim", () => {
  test("anonymous CANNOT create a doc with user_role:'admin'", async () => {
    await assertFails(
      setDoc(doc(anonAuth(), userDoc(ATTACKER)), {
        ...profileOnly,
        user_role: "admin",
      }),
    );
  });

  test("anonymous CANNOT self-promote to admin on update", async () => {
    await seed(ATTACKER, { user_role: "residential", display_name: "A" });
    await assertFails(
      updateDoc(doc(anonAuth(), userDoc(ATTACKER)), { user_role: "admin" }),
    );
  });

  test("random authenticated user CANNOT self-promote to admin (the reported vuln)", async () => {
    await seed(ATTACKER, { user_role: "residential", display_name: "A" });
    await assertFails(
      updateDoc(doc(authed(ATTACKER), userDoc(ATTACKER)), {
        user_role: "admin",
      }),
    );
  });

  test("random authenticated user CANNOT promote SOMEONE ELSE to admin", async () => {
    await seed(VICTIM, { user_role: "residential", display_name: "V" });
    await assertFails(
      updateDoc(doc(authed(ATTACKER), userDoc(VICTIM)), { user_role: "admin" }),
    );
  });

  test("a dealer-role user CANNOT escalate to admin", async () => {
    const db = await dealerCtx();
    await assertFails(
      updateDoc(doc(db, userDoc(DEALER_A)), { user_role: "admin" }),
    );
  });

  test("anonymous CANNOT self-promote to 'dealer' (grants cross-dealer read via hasMediaAccess)", async () => {
    await seed(ATTACKER, { user_role: "residential" });
    await assertFails(
      updateDoc(doc(anonAuth(), userDoc(ATTACKER)), { user_role: "dealer" }),
    );
  });

  test("anonymous CANNOT self-promote to 'media' (also inside hasMediaAccess)", async () => {
    await seed(ATTACKER, { user_role: "residential" });
    await assertFails(
      updateDoc(doc(anonAuth(), userDoc(ATTACKER)), { user_role: "media" }),
    );
  });

  test("wizard-shaped write CANNOT smuggle user_role:'admin'", async () => {
    await assertFails(
      setDoc(doc(anonAuth(), userDoc(ATTACKER)), {
        ...wizardWrite,
        user_role: "admin",
      }),
    );
  });
});

// ── 3. Admin / owner claims CAN ─────────────────────────────────────────────
describe("admin/owner claim sessions can set privileged roles", () => {
  test("admin claim CAN create a doc with user_role:'dealer'", async () => {
    await assertSucceeds(
      setDoc(doc(adminClaim(), userDoc(DEALER_A)), {
        ...profileOnly,
        user_role: "dealer",
      }),
    );
  });

  test("admin claim CAN promote an existing user to admin", async () => {
    await seed(VICTIM, { user_role: "residential", display_name: "V" });
    await assertSucceeds(
      updateDoc(doc(adminClaim(), userDoc(VICTIM)), { user_role: "admin" }),
    );
  });

  test("owner claim CAN promote an existing user to dealer", async () => {
    await seed(VICTIM, { user_role: "residential", display_name: "V" });
    await assertSucceeds(
      updateDoc(doc(ownerClaim(), userDoc(VICTIM)), { user_role: "dealer" }),
    );
  });
});

// ── 4. dealer_code reassignment ─────────────────────────────────────────────
describe("dealer_code reassignment is denied without an admin/owner claim", () => {
  test("anonymous CANNOT move a customer from dealer 55 to dealer 56", async () => {
    await seed(VICTIM, { user_role: "residential", dealer_code: "55" });
    await assertFails(
      updateDoc(doc(anonAuth(), userDoc(VICTIM)), { dealer_code: "56" }),
    );
  });

  test("a dealer-role user CANNOT poach another dealer's customer", async () => {
    await seed(VICTIM, { user_role: "residential", dealer_code: "55" });
    const db = await dealerCtx();
    await assertFails(
      updateDoc(doc(db, userDoc(VICTIM)), { dealer_code: "56" }),
    );
  });

  test("admin claim CAN reassign dealer_code (support path)", async () => {
    await seed(VICTIM, { user_role: "residential", dealer_code: "55" });
    await assertSucceeds(
      updateDoc(doc(adminClaim(), userDoc(VICTIM)), { dealer_code: "56" }),
    );
  });

  test("a write that merely OMITS dealer_code is not a reassignment", async () => {
    await seed(VICTIM, { user_role: "residential", dealer_code: "55" });
    await assertSucceeds(
      updateDoc(doc(anonAuth(), userDoc(VICTIM)), { phone_number: "555-0177" }),
    );
  });
});
