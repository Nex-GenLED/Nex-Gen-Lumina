/**
 * F-3 — Firestore security-rules tests for the neighborhood read/join surface.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator:
 *   cd functions
 *   npx firebase emulators:exec --only firestore \
 *     "npx jest --config jest.emulator.config.js --runInBand"
 *
 * WHAT F-3 WAS
 * `/neighborhoods/{groupId}` was `allow read: if request.auth != null`, so any
 * authenticated — including anonymous — token could list every crew in the
 * fleet together with `streetName`, `latitude`, `longitude` and `inviteCode`.
 * The members subcollection was equally open and carries `displayName` and
 * `controllerIp`. Group `update` additionally accepted anyone who inserted
 * their own uid into `memberUids`, with the comment "enforced app-side" — so a
 * stranger could join any crew with no credential, satisfy isGroupMemberLookup()
 * and unlock its commands/schedules/syncEvents. That last one also went around
 * SYNC-1, since a self-joined attacker is in `memberUids[]` legitimately.
 *
 * WHAT IS ASSERTED HERE
 *   • group read: member ✓ / creator ✓ / non-member ✗ / anonymous ✗
 *   • group update: existing member ✓ / creator ✓ / SELF-INSERTION ✗   ← the fix
 *   • members roster read: crew member ✓ / non-member ✗
 *   • public projection: readable by anyone authed, but the SHAPE guard rejects
 *     any doc carrying inviteCode / street / precise coords, and only the
 *     parent group's creator may write it
 *
 * The credential half of joining (bad code refused, good code accepted) is not
 * expressible here — it lives in the joinNeighborhood callable, which runs with
 * the admin SDK and bypasses rules by design. It is covered in
 * test/unit/joinNeighborhood.test.js (`decideJoin`).
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { setDoc, updateDoc, getDoc, doc, getDocs, collection } from "firebase/firestore";

const PROJECT_ID = "lumina-f3-rules-test";
const CREATOR = "creator-uid";
const MEMBER = "member-uid";
const STRANGER = "stranger-uid";
const GROUP = "g1";

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
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // A private crew carrying exactly the fields F-3 was leaking.
    await setDoc(doc(db, `neighborhoods/${GROUP}`), {
      creatorUid: CREATOR,
      memberUids: [CREATOR, MEMBER],
      name: "Test Crew",
      inviteCode: "AB2C3D",
      streetName: "1200 Maple Street",
      city: "Kansas City",
      latitude: 39.0997,
      longitude: -94.5786,
      isPublic: false,
    });
    // Member docs are the canonical membership signal used by isGroupMemberLookup().
    await setDoc(doc(db, `neighborhoods/${GROUP}/members/${CREATOR}`), {
      displayName: "Creator Home",
      controllerIp: "192.168.1.150",
    });
    await setDoc(doc(db, `neighborhoods/${GROUP}/members/${MEMBER}`), {
      displayName: "Member Home",
      controllerIp: "192.168.1.151",
    });
  });
});

const groupRef = (db: any) => doc(db, `neighborhoods/${GROUP}`);

describe("F-3 — /neighborhoods/{groupId} read is membership-scoped", () => {
  test("a MEMBER can read the group", async () => {
    const db = env.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(getDoc(groupRef(db)));
  });

  test("the CREATOR can read the group", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertSucceeds(getDoc(groupRef(db)));
  });

  // THE FIX. Before F-3 this succeeded and returned street + coords + inviteCode.
  test("a NON-MEMBER cannot read the group (street, coords, inviteCode)", async () => {
    const db = env.authenticatedContext(STRANGER).firestore();
    await assertFails(getDoc(groupRef(db)));
  });

  test("an ANONYMOUS token cannot read the group", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(groupRef(anon)));
  });

  test("a non-member cannot LIST the neighborhoods collection", async () => {
    const db = env.authenticatedContext(STRANGER).firestore();
    await assertFails(getDocs(collection(db, "neighborhoods")));
  });
});

describe("F-3 — self-insertion into memberUids is refused", () => {
  // THE OTHER HALF OF THE FIX. This is the "enforced app-side" clause: a
  // stranger appending their own uid to a crew they have no code for.
  test("a STRANGER cannot add themselves to memberUids", async () => {
    const db = env.authenticatedContext(STRANGER).firestore();
    await assertFails(
      updateDoc(groupRef(db), { memberUids: [CREATOR, MEMBER, STRANGER] })
    );
  });

  test("an EXISTING member can still update the group", async () => {
    const db = env.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(updateDoc(groupRef(db), { isActive: true }));
  });

  test("the creator can still update the group", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertSucceeds(updateDoc(groupRef(db), { name: "Renamed" }));
  });

  // Leaving must survive: a member removing themselves is evaluated against the
  // PRE-update doc, where they are still a member.
  test("a member can remove themselves (leave)", async () => {
    const db = env.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(updateDoc(groupRef(db), { memberUids: [CREATOR] }));
  });
});

describe("F-3 — members roster read is crew-only", () => {
  test("a crew member can read the roster", async () => {
    const db = env.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(
      getDocs(collection(db, `neighborhoods/${GROUP}/members`))
    );
  });

  // Carried displayName + controllerIp for every household in the fleet.
  test("a non-member cannot read the roster", async () => {
    const db = env.authenticatedContext(STRANGER).firestore();
    await assertFails(
      getDocs(collection(db, `neighborhoods/${GROUP}/members`))
    );
  });
});

describe("F-3 — /neighborhood_public projection", () => {
  const projPath = `neighborhood_public/${GROUP}`;
  const safeProjection = {
    groupId: GROUP,
    name: "Test Crew",
    description: "A test crew",
    memberCount: 2,
    isPublic: true,
    latCoarse: 39.1,
    lonCoarse: -94.58,
  };

  test("the parent group's creator can publish a safe projection", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertSucceeds(setDoc(doc(db, projPath), safeProjection));
  });

  test("ANY authenticated user can read the projection (discovery)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), projPath), safeProjection);
    });
    const db = env.authenticatedContext(STRANGER).firestore();
    await assertSucceeds(getDoc(doc(db, projPath)));
  });

  test("an anonymous token cannot read the projection", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), projPath), safeProjection);
    });
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, projPath)));
  });

  // The shape guard is the reason the cross-tenant read is acceptable. A writer
  // bug that copies the whole group doc into the projection must FAIL, not leak.
  test("a projection carrying inviteCode is REFUSED", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertFails(
      setDoc(doc(db, projPath), { ...safeProjection, inviteCode: "AB2C3D" })
    );
  });

  test("a projection carrying precise coordinates is REFUSED", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertFails(
      setDoc(doc(db, projPath), {
        ...safeProjection,
        latitude: 39.0997,
        longitude: -94.5786,
      })
    );
  });

  test("a projection carrying streetName is REFUSED", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertFails(
      setDoc(doc(db, projPath), { ...safeProjection, streetName: "1200 Maple Street" })
    );
  });

  test("a projection carrying memberUids is REFUSED", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertFails(
      setDoc(doc(db, projPath), { ...safeProjection, memberUids: [CREATOR] })
    );
  });

  test("a NON-creator cannot publish a projection for someone's group", async () => {
    const db = env.authenticatedContext(STRANGER).firestore();
    await assertFails(setDoc(doc(db, projPath), safeProjection));
  });

  test("a projection with isPublic false is REFUSED (private stays unlisted)", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertFails(
      setDoc(doc(db, projPath), { ...safeProjection, isPublic: false })
    );
  });

  test("the creator can delete the projection (going private again)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), projPath), safeProjection);
    });
    const db = env.authenticatedContext(CREATOR).firestore();
    const { deleteDoc } = await import("firebase/firestore");
    await assertSucceeds(deleteDoc(doc(db, projPath)));
  });
});
