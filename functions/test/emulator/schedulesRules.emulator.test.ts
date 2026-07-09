/**
 * Firestore security-rules tests for the schedules subcollection + flag doc.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * Asserts:
 *   • owner can read AND write /users/{uid}/schedules/{id}
 *   • a DIFFERENT authenticated uid is DENIED read and write (proves the parent
 *     user-doc `|| request.auth != null` grant was NOT inherited)
 *   • unauthenticated is DENIED
 *   • config/schedules_subcollection is readable by any authenticated user
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { setDoc, doc, getDoc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test";
const OWNER = "owner-uid";
const OTHER = "other-uid";

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

const schedulePath = (uid: string) => `users/${uid}/schedules/sched-1`;
const sample = { id: "sched-1", timeLabel: "7:00 PM", enabled: true };

describe("/users/{uid}/schedules/{id}", () => {
  test("owner can write then read their own schedule", async () => {
    const db = env.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(doc(db, schedulePath(OWNER)), sample));
    await assertSucceeds(getDoc(doc(db, schedulePath(OWNER))));
  });

  test("a different authenticated uid is DENIED (no inherited broad grant)", async () => {
    // Seed as owner (admin context bypasses rules).
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), schedulePath(OWNER)), sample);
    });
    const otherDb = env.authenticatedContext(OTHER).firestore();
    await assertFails(getDoc(doc(otherDb, schedulePath(OWNER))));
    await assertFails(setDoc(doc(otherDb, schedulePath(OWNER)), sample));
  });

  test("unauthenticated is DENIED", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, schedulePath(OWNER))));
    await assertFails(setDoc(doc(anon, schedulePath(OWNER)), sample));
  });
});

describe("config/schedules_subcollection flag doc", () => {
  test("readable by any authenticated user", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "config/schedules_subcollection"), {
        enabled: false,
      });
    });
    const db = env.authenticatedContext(OTHER).firestore();
    await assertSucceeds(getDoc(doc(db, "config/schedules_subcollection")));
  });

  test("unauthenticated read denied", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "config/schedules_subcollection")));
  });
});
