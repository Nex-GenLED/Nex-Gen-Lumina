/**
 * P1-44 — Firestore security-rules tests for config/sync_fanout (the
 * Neighborhood Sync fanout feature flag).
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator (JDK 21+). See
 * test/emulator/README.md. Driven via:
 *   JAVA_HOME=<JDK21+> firebase emulators:exec --only firestore "npm run test:emulator"
 *
 * The deployed rule (firestore.rules → match /config/sync_fanout):
 *   allow read:            if request.auth != null;
 *   allow create:          if request.auth != null &&
 *                             request.resource.data.enabled == false;
 *   allow update, delete:  if false;
 *
 * Why these tests exist: the flag gates crew fanout. Bootstrap must be able to
 * provision the doc with the SAFE DEFAULT (enabled:false), but a client must NOT
 * be able to provision it already-on (create enabled:true) or flip it on later
 * (update) — the enabled=true flip is console-only. A create-enabled:true that
 * ALLOWED would be a real hole (someone provisions the flag on), so that DENY is
 * the load-bearing assertion. The enabled:false-ALLOW test sits right beside it
 * to prove create is generally permitted — so the enabled:true DENY is the CEL
 * guard firing, not create being blanket-denied.
 *
 * Asserts:
 *   • authed create {enabled:false}  — ALLOWED (bootstrap, safe default)
 *   • authed create {enabled:true}   — DENIED  (can't provision the flag on)
 *   • authed update existing doc      — DENIED  (flip is console-only)
 *   • authed read                     — ALLOWED (client StreamProvider)
 *   • unauthenticated read            — DENIED
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { setDoc, updateDoc, getDoc, doc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test";
const USER = "user-uid";
const FLAG_PATH = "config/sync_fanout";

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

describe("config/sync_fanout — P1-44 create-rule (flag can't be provisioned on)", () => {
  test("authed user CAN create the flag with the safe default {enabled:false}", async () => {
    const db = env.authenticatedContext(USER).firestore();
    await assertSucceeds(setDoc(doc(db, FLAG_PATH), { enabled: false }));
  });

  test("authed user CANNOT create the flag with {enabled:true} "
      + "(no provisioning it already-on — the console-only flip guard)", async () => {
    const db = env.authenticatedContext(USER).firestore();
    // Contrast with the enabled:false ALLOW above: create is permitted in
    // general, so this failure is the `request.resource.data.enabled == false`
    // CEL guard denying — not create being blanket-denied.
    await assertFails(setDoc(doc(db, FLAG_PATH), { enabled: true }));
  });

  test("authed user CANNOT update an existing flag doc (flip is console-only)", async () => {
    // Seed the doc as an admin (bootstrap already happened) so the attempted
    // write is a genuine UPDATE against an EXISTING doc — proving the CEL denies
    // the update, not that the doc is merely absent.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), FLAG_PATH), { enabled: false });
    });
    const db = env.authenticatedContext(USER).firestore();
    await assertFails(updateDoc(doc(db, FLAG_PATH), { enabled: true }));
  });

  test("authed user CAN read the flag (client StreamProvider path)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), FLAG_PATH), { enabled: false });
    });
    const db = env.authenticatedContext(USER).firestore();
    await assertSucceeds(getDoc(doc(db, FLAG_PATH)));
  });

  test("unauthenticated CANNOT read the flag", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), FLAG_PATH), { enabled: false });
    });
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, FLAG_PATH)));
  });
});
