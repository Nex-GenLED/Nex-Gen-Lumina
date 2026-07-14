/**
 * C3 — the promote-to-dealer write, verified against the LIVE D0 rules.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * WHY THIS TEST EXISTS
 *
 * `user_role` previously had NO writer anywhere in the app — UserRole.dealer
 * was parsed and displayed but never assigned, so creating a dealer account
 * meant hand-editing Firestore. C3 adds
 * CorporateAdminService.promoteUserToDealer as the in-app path.
 *
 * That write sets BOTH fields the D0 hotfix guards on /users update:
 *   • user_role  → 'dealer' (a PRIVILEGED role, D0 elevatesRole())
 *   • dealer_code → possibly a reassignment (D0 reassignsDealerCode())
 *
 * D0 denies both unless hasAdminOrOwnerClaim(). So the ONLY thing making C3
 * work is that it runs under a mintStaffToken admin/owner session. These
 * tests pin that: the same write is DENIED from every non-admin caller and
 * ALLOWED from an admin/owner claim.
 *
 * D3 PAIRING: the retrofit narrows the broad `|| request.auth != null` grants
 * toward hasStaffClaim()/hasAdminOrOwnerClaim(). An admin-claim caller is
 * exactly what survives that narrowing, so these assertions must keep passing
 * verbatim after D3. If they start failing, D3 broke dealer provisioning.
 *
 * Mirrors CorporateAdminService.promoteUserToDealer /
 * demoteDealerUser (corporate_admin_providers.dart). Keep the payloads in
 * sync with those methods.
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { doc, setDoc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test-promote";

const TARGET = "target-user-uid";
const DEALER = "56";

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

async function seedTarget(extra: Record<string, unknown> = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${TARGET}`), {
      id: TARGET,
      owner_id: TARGET,
      email: "newdealer@example.com",
      display_name: "New Dealer",
      user_role: "residential",
      ...extra,
    });
  });
}

/** EXACTLY promoteUserToDealer's payload. */
const promotePayload = {
  user_role: "dealer",
  dealer_code: DEALER,
  updated_at: new Date(),
};

/** EXACTLY demoteDealerUser's payload. */
const demotePayload = {
  user_role: "residential",
  updated_at: new Date(),
};

const adminClaim = () =>
  env.authenticatedContext("staff_admin_5501", { role: "admin" }).firestore();
const ownerClaim = () =>
  env.authenticatedContext("staff_owner_9999", { role: "owner" }).firestore();
const installerClaim = () =>
  env
    .authenticatedContext("staff_installer_5501", {
      role: "installer",
      dealerCode: "55",
    })
    .firestore();
const anonWizard = () =>
  env
    .authenticatedContext("anon-wizard-uid", { provider_id: "anonymous" })
    .firestore();
const selfServe = () => env.authenticatedContext(TARGET).firestore();

describe("C3 — promoteUserToDealer requires an admin/owner claim", () => {
  test("admin claim CAN promote a residential user to dealer", async () => {
    await seedTarget();
    await assertSucceeds(
      setDoc(doc(adminClaim(), `users/${TARGET}`), promotePayload, {
        merge: true,
      }),
    );
  });

  test("owner claim CAN promote", async () => {
    await seedTarget();
    await assertSucceeds(
      setDoc(doc(ownerClaim(), `users/${TARGET}`), promotePayload, {
        merge: true,
      }),
    );
  });

  test("an INSTALLER claim CANNOT promote (D0 elevatesRole)", async () => {
    await seedTarget();
    await assertFails(
      setDoc(doc(installerClaim(), `users/${TARGET}`), promotePayload, {
        merge: true,
      }),
    );
  });

  test("the anonymous wizard session CANNOT promote", async () => {
    await seedTarget();
    await assertFails(
      setDoc(doc(anonWizard(), `users/${TARGET}`), promotePayload, {
        merge: true,
      }),
    );
  });

  test("the user CANNOT promote THEMSELVES (the D0 vuln, still closed)", async () => {
    await seedTarget();
    await assertFails(
      setDoc(doc(selfServe(), `users/${TARGET}`), promotePayload, {
        merge: true,
      }),
    );
  });
});

describe("C3 — re-association (dealer_code reassignment)", () => {
  test("admin CAN re-associate an existing dealer to another code", async () => {
    await seedTarget({ user_role: "dealer", dealer_code: "55" });
    await assertSucceeds(
      setDoc(
        doc(adminClaim(), `users/${TARGET}`),
        { user_role: "dealer", dealer_code: "57", updated_at: new Date() },
        { merge: true },
      ),
    );
  });

  test("a non-admin CANNOT re-associate (D0 reassignsDealerCode)", async () => {
    await seedTarget({ user_role: "dealer", dealer_code: "55" });
    await assertFails(
      setDoc(
        doc(installerClaim(), `users/${TARGET}`),
        { dealer_code: "57", updated_at: new Date() },
        { merge: true },
      ),
    );
  });
});

describe("C3 — demoteDealerUser", () => {
  test("admin CAN revoke the dealer role", async () => {
    await seedTarget({ user_role: "dealer", dealer_code: DEALER });
    await assertSucceeds(
      setDoc(doc(adminClaim(), `users/${TARGET}`), demotePayload, {
        merge: true,
      }),
    );
  });

  test("demotion keeps dealer_code (association survives)", async () => {
    await seedTarget({ user_role: "dealer", dealer_code: DEALER });
    await assertSucceeds(
      setDoc(doc(adminClaim(), `users/${TARGET}`), demotePayload, {
        merge: true,
      }),
    );
    await env.withSecurityRulesDisabled(async (ctx) => {
      const snap = await ctx.firestore().doc(`users/${TARGET}`).get();
      expect(snap.get("dealer_code")).toBe(DEALER);
      expect(snap.get("user_role")).toBe("residential");
    });
  });

  test("a demotion to a NON-privileged role is not an elevation — allowed for self", async () => {
    // Guards against over-tightening: D0 denies ELEVATION, not downgrade. A
    // user writing user_role:'residential' onto their own already-residential
    // doc must keep working (UserModel.toJson re-emits user_role every save).
    await seedTarget();
    await assertSucceeds(
      setDoc(
        doc(selfServe(), `users/${TARGET}`),
        { user_role: "residential", display_name: "Renamed" },
        { merge: true },
      ),
    );
  });
});
