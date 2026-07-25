/**
 * SYNC-1 — Firestore security-rules tests for neighborhoods/{g}/members/{uid}.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * Closes the self-fanout authorization hole: a member doc may only be CREATED
 * by that user themselves (self-join). The group creator can UPDATE/DELETE
 * existing member docs (reorder/moderation) but can NOT CREATE one for someone
 * else — that one-sided insert was what let a crew fanout target a
 * non-consenting stranger's controller.
 *
 * Asserts:
 *   • a user can CREATE their OWN member doc (self-join) — ALLOWED
 *   • the group creator CREATING a member doc for a DIFFERENT uid — DENIED
 *     (the fix; against the old rule this was ALLOWED)
 *   • the group creator UPDATING an EXISTING member doc — ALLOWED (moderation)
 *   • unauthenticated create — DENIED
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { setDoc, updateDoc, doc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test";
const CREATOR = "creator-uid";
const MEMBER = "member-uid";
const VICTIM = "victim-uid";
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
  // Seed the group: CREATOR owns it, memberUids starts with the creator.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `neighborhoods/${GROUP}`), {
      creatorUid: CREATOR,
      memberUids: [CREATOR],
      name: "Test Crew",
    });
  });
});

const memberPath = (uid: string) => `neighborhoods/${GROUP}/members/${uid}`;
const memberDoc = { displayName: "x", ledCount: 100, positionIndex: 0 };

describe("neighborhoods/{g}/members/{uid} — SYNC-1 create authorization", () => {
  test("a user can CREATE their OWN member doc (self-join)", async () => {
    const db = env.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(setDoc(doc(db, memberPath(MEMBER)), memberDoc));
  });

  test("the group CREATOR CANNOT create a member doc for a DIFFERENT uid "
      + "(closes the one-sided self-fanout insert)", async () => {
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertFails(setDoc(doc(db, memberPath(VICTIM)), memberDoc));
  });

  test("the group creator CAN UPDATE an EXISTING member doc (moderation)", async () => {
    // Seed the member's own doc first (admin bypass = self-join happened).
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), memberPath(MEMBER)), memberDoc);
    });
    const db = env.authenticatedContext(CREATOR).firestore();
    await assertSucceeds(
      updateDoc(doc(db, memberPath(MEMBER)), { positionIndex: 3 })
    );
  });

  test("unauthenticated CANNOT create a member doc", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anon, memberPath(MEMBER)), memberDoc));
  });
});
