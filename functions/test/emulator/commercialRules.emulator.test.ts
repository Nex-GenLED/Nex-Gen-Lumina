/**
 * Firestore security-rules tests for the commercial collections.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * Covers the 2026-07-14 commercial audit's rules findings:
 *   • commercial_locations — the `|| request.auth != null` that swallowed
 *     isOwner and let ANY signed-in user write ANY user's locations.
 *   • brand_profile — the same fallback on read + every write branch.
 *   • commercial_organizations / campaigns — NO rule block at all, so both
 *     were default-denied and every corporate push failed silently, 100%.
 *
 * The shape asserted on all of them: owner ALLOWED, dealer-scoped staff
 * ALLOWED, random authenticated DENIED. The last case is the regression that
 * matters — it fails against the old rules.
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { setDoc, doc, getDoc, deleteDoc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test";

const OWNER = "owner-uid";
const RANDOM = "random-uid";
const STAFF = "staff-uid";
const ORG_OWNER = "org-owner-uid";
const ORG_MEMBER = "org-member-uid";
const DEALER = "D42";
const OTHER_DEALER = "D99";
const ORG_ID = "org-1";

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

beforeEach(async () => {
  await env.clearFirestore();
  // Every commercial subcollection rule scopes staff via the parent user
  // doc's dealer_code (dealerCodeOf), so the parent must exist.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${OWNER}`), {
      email: "steve@bluelinebar.example",
      dealer_code: DEALER,
      profile_type: "commercial",
    });
    await setDoc(doc(db, `users/${RANDOM}`), { email: "nosy@example.com" });
  });
});

// ── Contexts ────────────────────────────────────────────────────────────────

const asOwner = () => env.authenticatedContext(OWNER).firestore();
const asRandom = () => env.authenticatedContext(RANDOM).firestore();
/** Staff session as minted by mintStaffToken: role + dealerCode claims. */
const asStaff = (dealerCode = DEALER) =>
  env
    .authenticatedContext(STAFF, { role: "installer", dealerCode })
    .firestore();
const asAdminClaim = () =>
  env.authenticatedContext("admin-uid", { role: "admin" }).firestore();
const asUnauth = () => env.unauthenticatedContext().firestore();

const LOC = `users/${OWNER}/commercial_locations/primary`;
const BRAND = `users/${OWNER}/brand_profile/brand`;
const HOURS = `users/${OWNER}/commercial_hours/primary`;

const seed = async (path: string, data: Record<string, unknown>) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });

// ── commercial_locations ────────────────────────────────────────────────────

describe("/users/{uid}/commercial_locations/{id}", () => {
  const sample = { location_id: "primary", active: true };

  test("owner: read + write ALLOWED", async () => {
    await assertSucceeds(setDoc(doc(asOwner(), LOC), sample));
    await assertSucceeds(getDoc(doc(asOwner(), LOC)));
  });

  test("dealer-scoped staff: read + write ALLOWED", async () => {
    await assertSucceeds(setDoc(doc(asStaff(), LOC), sample));
    await assertSucceeds(getDoc(doc(asStaff(), LOC)));
  });

  test("admin claim: read + write ALLOWED", async () => {
    await assertSucceeds(setDoc(doc(asAdminClaim(), LOC), sample));
    await assertSucceeds(getDoc(doc(asAdminClaim(), LOC)));
  });

  test("random authenticated: create DENIED", async () => {
    // THE regression: the old rule was `allow create: if request.auth != null`.
    await assertFails(setDoc(doc(asRandom(), LOC), sample));
  });

  test("random authenticated: read/update/delete DENIED", async () => {
    await seed(LOC, sample);
    await assertFails(getDoc(doc(asRandom(), LOC)));
    await assertFails(setDoc(doc(asRandom(), LOC), { active: false }));
    await assertFails(deleteDoc(doc(asRandom(), LOC)));
  });

  test("staff from ANOTHER dealer: DENIED", async () => {
    await seed(LOC, sample);
    await assertFails(setDoc(doc(asStaff(OTHER_DEALER), LOC), sample));
    await assertFails(getDoc(doc(asStaff(OTHER_DEALER), LOC)));
  });

  test("unauthenticated: DENIED", async () => {
    await seed(LOC, sample);
    await assertFails(getDoc(doc(asUnauth(), LOC)));
    await assertFails(setDoc(doc(asUnauth(), LOC), sample));
  });
});

// ── brand_profile ───────────────────────────────────────────────────────────

describe("/users/{uid}/brand_profile/{id}", () => {
  const sample = { company_name: "The Blue Line Bar" };

  test("owner: read + write ALLOWED", async () => {
    await assertSucceeds(setDoc(doc(asOwner(), BRAND), sample));
    await assertSucceeds(getDoc(doc(asOwner(), BRAND)));
  });

  test("dealer-scoped staff: read + write ALLOWED (installer pre-seed)", async () => {
    await assertSucceeds(setDoc(doc(asStaff(), BRAND), sample));
    await assertSucceeds(getDoc(doc(asStaff(), BRAND)));
  });

  test("random authenticated: read DENIED", async () => {
    // The old rule read `canReadUserData(userId) || request.auth != null`,
    // so every signed-in user could read every business's brand profile.
    await seed(BRAND, sample);
    await assertFails(getDoc(doc(asRandom(), BRAND)));
  });

  test("random authenticated: create/update/delete DENIED", async () => {
    await assertFails(setDoc(doc(asRandom(), BRAND), sample));
    await seed(BRAND, sample);
    await assertFails(setDoc(doc(asRandom(), BRAND), { company_name: "X" }));
    await assertFails(deleteDoc(doc(asRandom(), BRAND)));
  });

  test("staff from ANOTHER dealer: DENIED", async () => {
    await assertFails(setDoc(doc(asStaff(OTHER_DEALER), BRAND), sample));
  });

  test("unauthenticated: DENIED", async () => {
    await seed(BRAND, sample);
    await assertFails(getDoc(doc(asUnauth(), BRAND)));
  });
});

// ── commercial_hours (new) ──────────────────────────────────────────────────

describe("/users/{uid}/commercial_hours/{id}", () => {
  const sample = { location_id: "primary", days: { fri: { open: "16:00" } } };

  test("owner: read + write ALLOWED", async () => {
    await assertSucceeds(setDoc(doc(asOwner(), HOURS), sample));
    await assertSucceeds(getDoc(doc(asOwner(), HOURS)));
  });

  test("random authenticated: DENIED", async () => {
    await seed(HOURS, sample);
    await assertFails(getDoc(doc(asRandom(), HOURS)));
    await assertFails(setDoc(doc(asRandom(), HOURS), sample));
  });

  test("staff: read DENIED (hours are private operating data, owner-scoped)", async () => {
    await seed(HOURS, sample);
    await assertFails(getDoc(doc(asStaff(), HOURS)));
  });
});

// ── commercial_organizations ────────────────────────────────────────────────

describe("/commercial_organizations/{orgId}", () => {
  const ORG = `commercial_organizations/${ORG_ID}`;
  const sample = { org_id: ORG_ID, owner_id: ORG_OWNER, name: "BLB Group" };

  beforeEach(async () => {
    await seed(ORG, sample);
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${ORG_MEMBER}`), {
        organization_id: ORG_ID,
      });
      await setDoc(doc(ctx.firestore(), `users/${ORG_OWNER}`), {
        email: "owner@blb.example",
      });
    });
  });

  test("org owner: read ALLOWED (was default-denied — no rule block existed)", async () => {
    const db = env.authenticatedContext(ORG_OWNER).firestore();
    await assertSucceeds(getDoc(doc(db, ORG)));
  });

  test("org member: read ALLOWED", async () => {
    // commercialOrgProvider's real access pattern: the caller's user doc
    // names the org. This read threw permission-denied before, which the
    // provider's `catch (_) => null` hid.
    const db = env.authenticatedContext(ORG_MEMBER).firestore();
    await assertSucceeds(getDoc(doc(db, ORG)));
  });

  test("admin claim: read ALLOWED", async () => {
    await assertSucceeds(getDoc(doc(asAdminClaim(), ORG)));
  });

  test("random authenticated: read DENIED", async () => {
    await assertFails(getDoc(doc(asRandom(), ORG)));
  });

  test("writes DENIED for owner + member; admin/owner claim only", async () => {
    // Nothing in the app creates an org; a client write path would be
    // speculative surface area.
    const ownerDb = env.authenticatedContext(ORG_OWNER).firestore();
    await assertFails(setDoc(doc(ownerDb, ORG), { name: "Renamed" }));
    await assertSucceeds(setDoc(doc(asAdminClaim(), ORG), { name: "Renamed" }));
  });

  test("unauthenticated: DENIED", async () => {
    await assertFails(getDoc(doc(asUnauth(), ORG)));
  });
});

// ── campaigns ───────────────────────────────────────────────────────────────

describe("/campaigns/{campaignId}", () => {
  const CAMP = "campaigns/camp-1";
  const sample = {
    campaign_id: "camp-1",
    campaign_name: "Playoff Push",
    created_by: OWNER,
    location_ids: ["primary"],
  };

  test("creator: create + read ALLOWED (every push was denied before)", async () => {
    await assertSucceeds(setDoc(doc(asOwner(), CAMP), sample));
    await assertSucceeds(getDoc(doc(asOwner(), CAMP)));
  });

  test("create with someone ELSE's created_by is DENIED", async () => {
    // Stops a caller minting a campaign that reads as another user's.
    await assertFails(
      setDoc(doc(asRandom(), CAMP), { ...sample, created_by: OWNER })
    );
  });

  test("random authenticated: read/update/delete DENIED", async () => {
    await seed(CAMP, sample);
    await assertFails(getDoc(doc(asRandom(), CAMP)));
    await assertFails(setDoc(doc(asRandom(), CAMP), { campaign_name: "X" }));
    await assertFails(deleteDoc(doc(asRandom(), CAMP)));
  });

  test("admin claim: read + write ALLOWED", async () => {
    await seed(CAMP, sample);
    await assertSucceeds(getDoc(doc(asAdminClaim(), CAMP)));
    await assertSucceeds(deleteDoc(doc(asAdminClaim(), CAMP)));
  });

  test("a legacy campaign with NO created_by is admin-only, not world-readable", async () => {
    // '' matches no uid, so the missing-field default fails safe.
    await seed("campaigns/legacy", { campaign_name: "Old" });
    await assertFails(getDoc(doc(asOwner(), "campaigns/legacy")));
    await assertFails(getDoc(doc(asRandom(), "campaigns/legacy")));
    await assertSucceeds(getDoc(doc(asAdminClaim(), "campaigns/legacy")));
  });

  test("unauthenticated: DENIED", async () => {
    await seed(CAMP, sample);
    await assertFails(getDoc(doc(asUnauth(), CAMP)));
  });
});
