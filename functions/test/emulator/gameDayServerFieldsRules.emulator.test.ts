/**
 * B5 (2026-10-02) — /users/{uid}: `gameday_server` and `gameday_gate_blocking`
 * are server-owned. Firestore security-rules tests.
 *
 * ⚠️ NOT run by `npm test`. Requires @firebase/rules-unit-testing + the
 * Firestore emulator. See test/emulator/README.md.
 *
 * Threat: the planner publishes `gameday_server.served:true` when the SERVER
 * fires an account's Game Day, and the app stands down on it (plan step C). A
 * client able to write the field could forge served:true and silence its own
 * app while nothing fires. The /users update rule carries a broad
 * `|| request.auth != null` disjunct (the installer wizard writes customer docs
 * anonymously), so the guard is ANDed at the top level like the D0 guards.
 *
 * Asserts:
 *   • owner / anonymous / another uid / an admin-claim caller CANNOT add or
 *     change either field, by update(), set(merge), a dotted path, or create
 *   • REMOVAL is allowed (absent = "not served", the safe direction), including
 *     the full-document set() the profile-create path performs
 *   • every ordinary field each identity could write before is still writable,
 *     on a doc that carries both server fields
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { deleteField, doc, setDoc, updateDoc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test-gameday-server";
const OWNER = "owner-uid";
const OTHER = "other-uid";
const ANON = "anon-wizard-uid";
const ADMIN = "admin-claim-uid";

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

const SERVER_STATE = {
  gameday_server: {
    served: false,
    teams: [],
    preflight: { ok: false, reasons: ["preflight_bridge_stale"], info: [], mode: "enforce" },
    next_fire: null,
  },
  gameday_gate_blocking: ["gated_no_facts"],
};

/** A realistic customer profile, carrying both server-owned fields. */
async function seed(): Promise<void> {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${OWNER}`), {
      id: OWNER,
      owner_id: OWNER,
      email: "owner@example.com",
      display_name: "Test Owner",
      user_role: "residential",
      dealer_code: "99",
      ...SERVER_STATE,
    });
  });
}
beforeEach(seed);

const owner = () => env.authenticatedContext(OWNER, { email: "owner@example.com" }).firestore();
const other = () => env.authenticatedContext(OTHER, { email: "other@example.com" }).firestore();
const anon = () =>
  env.authenticatedContext(ANON, { firebase: { sign_in_provider: "anonymous" } }).firestore();
const admin = () => env.authenticatedContext(ADMIN, { admin: true, role: "admin" }).firestore();
const IDENTITIES: Array<[string, () => ReturnType<typeof owner>]> = [
  ["owner", owner],
  ["anonymous (installer wizard shape)", anon],
  ["another signed-in uid", other],
  ["an admin-claim caller", admin],
];
const ownerDoc = (db: ReturnType<typeof owner>) => doc(db, `users/${OWNER}`);

describe("no client may ADD or CHANGE a server-owned field", () => {
  for (const [name, db] of IDENTITIES) {
    test(`${name}: forging gameday_server.served:true by update() is DENIED`, async () => {
      await assertFails(
        updateDoc(ownerDoc(db()), { gameday_server: { ...SERVER_STATE.gameday_server, served: true } })
      );
    });
    test(`${name}: a dotted-path write into gameday_server is DENIED`, async () => {
      await assertFails(updateDoc(ownerDoc(db()), { "gameday_server.served": true }));
    });
    test(`${name}: clearing the gate verdict (changing gameday_gate_blocking) is DENIED`, async () => {
      await assertFails(updateDoc(ownerDoc(db()), { gameday_gate_blocking: [] }));
    });
    test(`${name}: set(merge) carrying a changed server field is DENIED`, async () => {
      await assertFails(
        setDoc(ownerDoc(db()), { display_name: "x", gameday_server: { served: true } }, { merge: true })
      );
    });
  }

  test("ADDING the field to a doc that lacks it is DENIED", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${OWNER}`), {
        id: OWNER, owner_id: OWNER, email: "owner@example.com",
      });
    });
    await assertFails(updateDoc(ownerDoc(owner()), { gameday_server: { served: true } }));
    await assertFails(updateDoc(ownerDoc(owner()), { gameday_gate_blocking: [] }));
  });

  test("CREATING a profile that carries either field is DENIED; without them it is allowed", async () => {
    const fresh = (db: ReturnType<typeof owner>) => doc(db, "users/new-uid");
    const ctx = env.authenticatedContext("new-uid", { email: "new@example.com" }).firestore();
    const base = { id: "new-uid", owner_id: "new-uid", email: "new@example.com" };
    await assertFails(setDoc(fresh(ctx), { ...base, gameday_server: { served: true } }));
    await assertFails(setDoc(fresh(ctx), { ...base, gameday_gate_blocking: [] }));
    await assertSucceeds(setDoc(fresh(ctx), base));
  });
});

describe("REMOVAL is allowed — absent reads as not served", () => {
  test("deleteField() on either field", async () => {
    await assertSucceeds(updateDoc(ownerDoc(owner()), { gameday_server: deleteField() }));
    await assertSucceeds(updateDoc(ownerDoc(owner()), { gameday_gate_blocking: deleteField() }));
  });

  test("a full-document set() without the fields (user_service.createUser's shape)", async () => {
    await assertSucceeds(
      setDoc(ownerDoc(owner()), {
        id: OWNER, owner_id: OWNER, email: "owner@example.com", display_name: "Test Owner",
        user_role: "residential", dealer_code: "99",
      })
    );
  });

  test("re-sending the SAME value is not a change, and is allowed", async () => {
    await assertSucceeds(setDoc(ownerDoc(owner()), { ...SERVER_STATE, display_name: "y" }, { merge: true }));
  });
});

describe("every ordinary write is unchanged on a doc carrying both server fields", () => {
  // Fields the app writes to its own users/{uid} doc (UserModel.toJson,
  // team registration, edit profile, referral, connectivity).
  const ORDINARY: Record<string, unknown> = {
    display_name: "New Name",
    phone_number: "555-0100",
    sports_teams: ["Team A"],
    sports_team_priority: ["Team A"],
    game_day_team_priority: ["nfl_a"],
    latitude: 39.0,
    longitude: -95.0,
    time_zone: "America/Chicago",
    autopilot_enabled: true,
    referralCode: "ABC123",
    home_ssid_hash: "hash",
    updated_at: new Date(0),
  };

  for (const [field, value] of Object.entries(ORDINARY)) {
    test(`owner update(${field})`, async () => {
      await assertSucceeds(updateDoc(ownerDoc(owner()), { [field]: value }));
    });
  }

  test("owner set(merge) of several profile fields at once", async () => {
    await assertSucceeds(setDoc(ownerDoc(owner()), ORDINARY, { merge: true }));
  });

  test("the anonymous installer wizard's real field set (user_role + dealer_code)", async () => {
    await assertSucceeds(
      setDoc(ownerDoc(anon()), { user_role: "residential", dealer_code: "99", display_name: "W" }, { merge: true })
    );
  });

  test("another signed-in uid keeps the broad grant for ordinary fields (pre-existing behaviour)", async () => {
    await assertSucceeds(updateDoc(ownerDoc(other()), { display_name: "Broad Grant" }));
  });

  test("the D0 guards still bite (elevation to admin is still denied)", async () => {
    await assertFails(updateDoc(ownerDoc(owner()), { user_role: "admin" }));
  });
});
