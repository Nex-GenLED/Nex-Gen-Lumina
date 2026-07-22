/**
 * Integration tests for setAccountProfile against the Firestore emulator.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * firebase-admin pointed at a running Firestore emulator
 * (FIRESTORE_EMULATOR_HOST). See test/emulator/README.md.
 *
 * Drives the exported runSetAccountProfile() rather than the onCall wrapper,
 * so the real auth gate, validation and batch all execute with a synthetic
 * CallableRequest.
 *
 * Asserts:
 *   • auth: owner allowed, dealer-scoped staff allowed, admin/owner claim
 *     allowed, cross-dealer staff DENIED, random authed DENIED, anon DENIED.
 *   • the installations reconciliation both legacy batches skipped.
 *   • idempotency (rerun converges) and reversibility (non-destructive).
 *   • real coords are used, never the wizard's hardcoded 0.0.
 *   • businessHours validation incl. the cross-midnight bar case.
 *   • sports_team_priority -> commercial_teams mapping.
 */

import * as admin from "firebase-admin";
import { CallableRequest } from "firebase-functions/v2/https";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "lumina-fn-test" });
}
const db = admin.firestore();

import {
  runSetAccountProfile,
  validateBusinessHours,
  mapTeams,
  sportFromSlug,
  titleCaseSlugSuffix,
  MAX_SUB_USERS_COMMERCIAL,
  MAX_SUB_USERS_RESIDENTIAL,
} from "../../src/setAccountProfile";

// ── Helpers ─────────────────────────────────────────────────────────────────

const UID = "uid-blue-line";
const INSTALL_ID = "install-blue-line";
const DEALER = "D42";

/** Synthetic CallableRequest — only auth + data are read by the function. */
function req(
  data: Record<string, unknown>,
  auth?: { uid: string; token?: Record<string, unknown> }
): CallableRequest {
  return {
    data,
    auth: auth
      ? { uid: auth.uid, token: (auth.token ?? {}) as never }
      : undefined,
    rawRequest: {} as never,
    acceptsStreaming: false,
  } as unknown as CallableRequest;
}

const asOwner = (data: Record<string, unknown>) => req(data, { uid: UID });
const asStaff = (data: Record<string, unknown>, dealerCode = DEALER) =>
  req(data, {
    uid: "uid-installer",
    token: { role: "installer", dealerCode },
  });
const asAdmin = (data: Record<string, unknown>) =>
  req(data, { uid: "uid-admin", token: { role: "admin" } });
const asRandom = (data: Record<string, unknown>) =>
  req(data, { uid: "uid-random" });

async function seedUser(extra: Record<string, unknown> = {}) {
  await db.doc(`users/${UID}`).set({
    email: "steve@bluelinebar.example",
    profile_type: "residential",
    dealer_code: DEALER,
    installation_id: INSTALL_ID,
    ...extra,
  });
  await db.doc(`installations/${INSTALL_ID}`).set({
    site_mode: "residential",
    max_sub_users: MAX_SUB_USERS_RESIDENTIAL,
  });
}

const userDoc = async () => (await db.doc(`users/${UID}`).get()).data() ?? {};
const installDoc = async () =>
  (await db.doc(`installations/${INSTALL_ID}`).get()).data() ?? {};
const locationDoc = async () =>
  (await db.doc(`users/${UID}/commercial_locations/primary`).get()).data();
const hoursDoc = async () =>
  (await db.doc(`users/${UID}/commercial_hours/primary`).get()).data();

async function wipe() {
  for (const path of ["users", "installations"]) {
    const snap = await db.collection(path).get();
    await Promise.all(snap.docs.map((d) => db.recursiveDelete(d.ref)));
  }
}

beforeEach(wipe);
afterAll(wipe);

// ── Pure helpers (no emulator needed, but colocated with their consumer) ─────

describe("businessHours validation", () => {
  test("accepts the cross-midnight bar case (16:00 -> 02:00)", () => {
    const h = validateBusinessHours({
      fri: { open: "16:00", close: "02:00" },
      sun: { closed: true },
    });
    expect(h.fri).toEqual({ closed: false, open: "16:00", close: "02:00" });
    // closed days drop open/close entirely
    expect(h.sun).toEqual({ closed: true });
  });

  test("rejects non-HH:MM, 12-hour, and out-of-range times", () => {
    for (const bad of ["4pm", "24:00", "16:60", "1:00", ""]) {
      expect(() =>
        validateBusinessHours({ mon: { open: bad, close: "02:00" } })
      ).toThrow(/HH:MM/);
    }
  });

  test("rejects unknown day keys", () => {
    expect(() => validateBusinessHours({ funday: { closed: true } })).toThrow(
      /unknown day/
    );
  });

  test("rejects non-object input", () => {
    expect(() => validateBusinessHours([])).toThrow(/must be an object/);
    expect(() => validateBusinessHours("mon")).toThrow(/must be an object/);
  });
});

describe("team mapping", () => {
  test("longest sport prefix wins (ncaamb_ is not swallowed by ncaa_)", () => {
    expect(sportFromSlug("ncaamb_jayhawks")).toBe("ncaaMB");
    expect(sportFromSlug("ncaa_jayhawks")).toBe("ncaaFB");
    expect(sportFromSlug("cl_madrid")).toBe("championsLeague");
    expect(sportFromSlug("unknown_thing")).toBeNull();
  });

  test("ranks by list order and honours client-supplied real names", () => {
    const teams = mapTeams(
      ["mlb_royals", "nfl_chiefs"],
      { mlb_royals: "Kansas City Royals", nfl_chiefs: "Kansas City Chiefs" }
    );
    expect(teams).toEqual([
      {
        team_slug: "mlb_royals",
        team_name: "Kansas City Royals",
        sport: "mlb",
        priority_rank: 1,
        alert_intensity: "full",
        enable_game_day_mode: true,
      },
      expect.objectContaining({ team_slug: "nfl_chiefs", priority_rank: 2 }),
    ]);
  });

  test("falls back to a title-cased suffix when no name is supplied", () => {
    expect(titleCaseSlugSuffix("nfl_bills")).toBe("Bills");
    expect(mapTeams(["nfl_bills"])[0].team_name).toBe("Bills");
  });

  test("SKIPS unknown-sport slugs rather than writing a bogus sport", () => {
    // A wrong sport silently mis-drives game-day automation; absence is safer.
    expect(mapTeams(["nfl_chiefs", "quidditch_owls"])).toHaveLength(1);
  });

  test("never emits a null team_name or sport (CommercialTeam.fromJson hard-casts both)", () => {
    for (const t of mapTeams(["nfl_chiefs", "mlb_royals"])) {
      expect(typeof t.team_name).toBe("string");
      expect(typeof t.sport).toBe("string");
      expect(t.team_name).not.toBe("");
    }
  });
});

// ── Auth gate ───────────────────────────────────────────────────────────────

describe("auth gate", () => {
  beforeEach(seedUser);

  test("owner allowed", async () => {
    const r = await runSetAccountProfile(
      asOwner({ uid: UID, direction: "commercial" })
    );
    expect(r.direction).toBe("commercial");
  });

  test("dealer-scoped staff allowed", async () => {
    const r = await runSetAccountProfile(
      asStaff({ uid: UID, direction: "commercial" })
    );
    expect(r.direction).toBe("commercial");
  });

  test("admin claim allowed", async () => {
    const r = await runSetAccountProfile(
      asAdmin({ uid: UID, direction: "commercial" })
    );
    expect(r.direction).toBe("commercial");
  });

  test("staff from ANOTHER dealer DENIED", async () => {
    await expect(
      runSetAccountProfile(asStaff({ uid: UID, direction: "commercial" }, "D99"))
    ).rejects.toThrow(/Not authorized/);
    expect((await userDoc()).profile_type).toBe("residential");
  });

  test("random authenticated user DENIED (the banned `auth != null` class)", async () => {
    await expect(
      runSetAccountProfile(asRandom({ uid: UID, direction: "commercial" }))
    ).rejects.toThrow(/Not authorized/);
    expect((await userDoc()).profile_type).toBe("residential");
  });

  test("unauthenticated DENIED", async () => {
    await expect(
      runSetAccountProfile(req({ uid: UID, direction: "commercial" }))
    ).rejects.toThrow(/Sign-in required/);
  });

  test("staff with a matching dealerCode but a non-staff role DENIED", async () => {
    await expect(
      runSetAccountProfile(
        req(
          { uid: UID, direction: "commercial" },
          { uid: "x", token: { role: "customer", dealerCode: DEALER } }
        )
      )
    ).rejects.toThrow(/Not authorized/);
  });

  test("empty dealerCode claim cannot match an empty customer dealer_code", async () => {
    // Guards against '' == '' silently authorizing every unscoped session.
    await db.doc(`users/${UID}`).set({ dealer_code: "" }, { merge: true });
    await expect(
      runSetAccountProfile(
        req(
          { uid: UID, direction: "commercial" },
          { uid: "x", token: { role: "installer", dealerCode: "" } }
        )
      )
    ).rejects.toThrow(/Not authorized/);
  });
});

// ── Validation ──────────────────────────────────────────────────────────────

describe("input validation", () => {
  beforeEach(seedUser);

  test("rejects a missing/blank uid", async () => {
    await expect(
      runSetAccountProfile(asOwner({ direction: "commercial" }))
    ).rejects.toThrow(/uid is required/);
  });

  test("rejects an unknown direction", async () => {
    await expect(
      runSetAccountProfile(asOwner({ uid: UID, direction: "sideways" }))
    ).rejects.toThrow(/direction must be/);
  });

  test("rejects an unknown user", async () => {
    await expect(
      runSetAccountProfile(
        req({ uid: "ghost", direction: "commercial" }, { uid: "ghost" })
      )
    ).rejects.toThrow(/not found/);
  });

  test("a bad businessHours payload writes NOTHING (validated pre-batch)", async () => {
    await expect(
      runSetAccountProfile(
        asOwner({
          uid: UID,
          direction: "commercial",
          businessHours: { mon: { open: "nope", close: "02:00" } },
        })
      )
    ).rejects.toThrow(/HH:MM/);
    expect((await userDoc()).profile_type).toBe("residential");
    expect(await locationDoc()).toBeUndefined();
  });
});

// ── Activation ──────────────────────────────────────────────────────────────

describe("convert to commercial", () => {
  test("writes the FULL activation set incl. the installations reconciliation", async () => {
    await seedUser({ sports_team_priority: ["mlb_royals", "nfl_chiefs"] });

    const r = await runSetAccountProfile(
      asOwner({
        uid: UID,
        direction: "commercial",
        commercialProfile: { business_name: "The Blue Line Bar" },
        location: { locationName: "The Blue Line Bar", address: "1 Main St" },
        businessHours: { fri: { open: "16:00", close: "02:00" } },
        teamNames: { mlb_royals: "Kansas City Royals" },
      })
    );

    const u = await userDoc();
    expect(u.profile_type).toBe("commercial");
    expect(u.commercial_mode_enabled).toBe(true);
    expect(u.commercial_mode_override).toBe(true);
    expect(u.commercial_profile).toMatchObject({
      business_name: "The Blue Line Bar",
    });
    // Stamped server-side: callers cannot send a serverTimestamp sentinel
    // through a callable payload.
    expect(u.commercial_profile.updated_at).toBeDefined();

    // The step BOTH legacy batches skipped — residential invite limits used to
    // survive conversion forever (invitation_service.dart:38-50).
    const i = await installDoc();
    expect(i.site_mode).toBe("commercial");
    expect(i.max_sub_users).toBe(MAX_SUB_USERS_COMMERCIAL);
    expect(r.installationUpdated).toBe(true);

    const loc = await locationDoc();
    expect(loc).toMatchObject({
      location_id: "primary",
      location_name: "The Blue Line Bar",
      address: "1 Main St",
      active: true,
    });
    expect(loc!.managers).toEqual([
      expect.objectContaining({ user_id: UID, role: "corporateAdmin" }),
    ]);

    expect((await hoursDoc())!.days).toEqual({
      fri: { closed: false, open: "16:00", close: "02:00" },
    });

    expect(r.teamsMapped).toBe(2);
    expect(u.commercial_teams[0]).toMatchObject({
      team_slug: "mlb_royals",
      team_name: "Kansas City Royals",
      priority_rank: 1,
    });
  });

  test("uses the user doc's REAL coords, never the wizard's hardcoded 0.0", async () => {
    await seedUser({ latitude: 39.0997, longitude: -94.5786 });
    await runSetAccountProfile(asOwner({ uid: UID, direction: "commercial" }));
    const loc = await locationDoc();
    expect(loc!.lat).toBeCloseTo(39.0997);
    expect(loc!.lng).toBeCloseTo(-94.5786);
  });

  test("explicit location coords beat the user doc's", async () => {
    await seedUser({ latitude: 1, longitude: 2 });
    await runSetAccountProfile(
      asOwner({ uid: UID, direction: "commercial", location: { lat: 10, lng: 20 } })
    );
    const loc = await locationDoc();
    expect(loc!.lat).toBe(10);
    expect(loc!.lng).toBe(20);
  });

  test("coords absent everywhere => null, NOT a fake 0.0 on the equator", async () => {
    await seedUser();
    await runSetAccountProfile(asOwner({ uid: UID, direction: "commercial" }));
    const loc = await locationDoc();
    expect(loc!.lat).toBeNull();
    expect(loc!.lng).toBeNull();
  });

  test("missing installation_id is non-fatal; flags still apply", async () => {
    await db.doc(`users/${UID}`).set({ profile_type: "residential" });
    const r = await runSetAccountProfile(asOwner({ uid: UID, direction: "commercial" }));
    expect(r.installationUpdated).toBe(false);
    expect((await userDoc()).profile_type).toBe("commercial");
  });

  test("existing commercial_teams are NOT overwritten by the residential list", async () => {
    await seedUser({
      sports_team_priority: ["nfl_chiefs"],
      commercial_teams: [{ team_slug: "curated", team_name: "C", sport: "nfl" }],
    });
    const r = await runSetAccountProfile(asOwner({ uid: UID, direction: "commercial" }));
    expect(r.teamsMapped).toBe(0);
    expect((await userDoc()).commercial_teams).toEqual([
      { team_slug: "curated", team_name: "C", sport: "nfl" },
    ]);
  });
});

// ── Idempotency ─────────────────────────────────────────────────────────────

describe("idempotency", () => {
  test("rerun converges and does NOT stomp seeded/edited fields", async () => {
    await seedUser();
    await runSetAccountProfile(
      asOwner({
        uid: UID,
        direction: "commercial",
        location: { locationName: "The Blue Line Bar" },
      })
    );

    // Simulate the customer editing their location after activation.
    await db
      .doc(`users/${UID}/commercial_locations/primary`)
      .set({ controller_id: "ctrl-1", org_id: "org-9" }, { merge: true });

    const r2 = await runSetAccountProfile(
      asOwner({
        uid: UID,
        direction: "commercial",
        location: { locationName: "The Blue Line Bar" },
      })
    );

    expect(r2.alreadyInDirection).toBe(true);
    const loc = await locationDoc();
    // First-write-only fields survive the rerun.
    expect(loc!.controller_id).toBe("ctrl-1");
    expect(loc!.org_id).toBe("org-9");
    expect(loc!.location_name).toBe("The Blue Line Bar");
    expect((await userDoc()).profile_type).toBe("commercial");
  });

  test("a rerun still REPAIRS a half-failed activation", async () => {
    // The old non-atomic batches could leave profile_type set with no
    // location doc. A rerun must heal that, not no-op on the flag alone.
    await seedUser({ profile_type: "commercial" });
    expect(await locationDoc()).toBeUndefined();

    const r = await runSetAccountProfile(asOwner({ uid: UID, direction: "commercial" }));

    expect(r.alreadyInDirection).toBe(true);
    expect(await locationDoc()).toBeDefined();
    expect((await installDoc()).max_sub_users).toBe(MAX_SUB_USERS_COMMERCIAL);
  });
});

// ── Reversibility ───────────────────────────────────────────────────────────

describe("revert to residential", () => {
  test("flips flags + sub-user limit and RETAINS commercial data as dormant", async () => {
    await seedUser({ sports_team_priority: ["nfl_chiefs"] });
    await runSetAccountProfile(
      asOwner({
        uid: UID,
        direction: "commercial",
        commercialProfile: { business_name: "The Blue Line Bar" },
        businessHours: { fri: { open: "16:00", close: "02:00" } },
      })
    );

    const r = await runSetAccountProfile(asOwner({ uid: UID, direction: "residential" }));
    expect(r.direction).toBe("residential");

    const u = await userDoc();
    expect(u.profile_type).toBe("residential");
    expect(u.commercial_mode_enabled).toBe(false);
    expect(u.commercial_mode_override).toBe(false);
    expect((await installDoc()).max_sub_users).toBe(MAX_SUB_USERS_RESIDENTIAL);
    expect((await installDoc()).site_mode).toBe("residential");

    // Non-destructive: a mis-fired revert must not cost the customer their
    // brand/hours/teams setup.
    expect(u.commercial_profile).toMatchObject({
      business_name: "The Blue Line Bar",
    });
    expect(u.commercial_teams).toHaveLength(1);
    expect(await locationDoc()).toBeDefined();
    expect(await hoursDoc()).toBeDefined();
    expect(r.locationWritten).toBe(false);
  });

  test("round-trips: commercial -> residential -> commercial", async () => {
    await seedUser();
    await runSetAccountProfile(asOwner({ uid: UID, direction: "commercial" }));
    await runSetAccountProfile(asOwner({ uid: UID, direction: "residential" }));
    const back = await runSetAccountProfile(
      asOwner({ uid: UID, direction: "commercial" })
    );

    expect(back.direction).toBe("commercial");
    expect((await userDoc()).commercial_mode_enabled).toBe(true);
    expect((await installDoc()).max_sub_users).toBe(MAX_SUB_USERS_COMMERCIAL);
  });
});
