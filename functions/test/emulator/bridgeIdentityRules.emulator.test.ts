/**
 * Firestore security-rules tests for per-bridge identities (bridge firmware
 * 1.3.0, esp32-bridge/src/main.cpp "#5 per-bridge credential").
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * Phase R1 of the migration is ADDITIVE. What this file pins:
 *   • everything the legacy shared bridge account could do, it still can —
 *     no un-reflashed bridge loses access when these rules deploy;
 *   • a per-bridge account (uid bridge_<deviceId>, Admin-created) reaches a
 *     user's queue only when that user's bridge_email names it, writes ONLY
 *     its own registry doc, and can read the OTA manifest;
 *   • an account that merely copies a per-bridge EMAIL (client sign-up with a
 *     random uid) gets no registry or manifest access;
 *   • the user-side pairing request is unchanged.
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test";

const SHARED_EMAIL = "bridge@nex-genled.com";
const DEV_A = "A1B2C3D4E5F6";
const DEV_B = "0A0B0C0D0E0F";
const DEV_NEW = "AABBCCDDEEFF";
const DEV_UNPAIRED = "112233445566";
const emailFor = (dev: string) => `bridge-${dev.toLowerCase()}@bridges.nex-genled.com`;

const U_LEGACY = "user-on-shared-bridge";  // bridge_email = shared account
const U_PER = "user-on-per-bridge";        // bridge_email = DEV_A's own account
const OTHER = "some-signed-in-user";

const RULES = readFileSync("../firestore.rules", "utf8");
// The registry's temporary block list (isNotBlockedDeletedUid). Read from the
// rules rather than repeated here, so no account id is copied into a test.
const BLOCKED_UID = (/isNotBlockedDeletedUid\(\)[\s\S]*?in \[\s*'([^']+)'/.exec(RULES) || [])[1];

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: RULES,
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
    await setDoc(doc(db, `users/${U_LEGACY}`), { bridge_email: SHARED_EMAIL });
    await setDoc(doc(db, `users/${U_LEGACY}/commands/c1`), { status: "pending", controllerIp: "" });
    await setDoc(doc(db, `users/${U_LEGACY}/bridge_status/current`), { uptime: 1 });
    await setDoc(doc(db, `users/${U_PER}`), { bridge_email: emailFor(DEV_A) });
    await setDoc(doc(db, `users/${U_PER}/commands/c1`), { status: "pending", controllerIp: "" });
    await setDoc(doc(db, `users/${U_PER}/bridge_status/current`), { uptime: 1 });
    await setDoc(doc(db, `users/${OTHER}`), { email: "other@example.com" });
    await setDoc(doc(db, `bridge_registry/${DEV_A}`), { status: "paired", pairedUid: U_PER, pendingUid: "" });
    await setDoc(doc(db, `bridge_registry/${DEV_B}`), { status: "paired", pairedUid: U_LEGACY, pendingUid: "" });
    await setDoc(doc(db, `bridge_registry/${DEV_UNPAIRED}`), { status: "unpaired", pairedUid: "", pendingUid: "" });
    await setDoc(doc(db, "bridge_firmware/stable"), { version: "1.3.1", enabled: true });
  });
});

// ── Actors ──────────────────────────────────────────────────────────────────

const asShared = () =>
  env.authenticatedContext("legacy-shared-bridge-uid", { email: SHARED_EMAIL }).firestore();
const asPerBridge = (dev: string) =>
  env.authenticatedContext(`bridge_${dev}`, { email: emailFor(dev) }).firestore();
/** A client-created account that copied DEV_A's per-bridge email. */
const asEmailSquatter = () =>
  env.authenticatedContext("Zq9randomClientUid0000000001", { email: emailFor(DEV_A) }).firestore();
const asOther = () =>
  env.authenticatedContext(OTHER, { email: "other@example.com" }).firestore();
const asOwner = (uid: string) =>
  env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();

// ── Legacy shared account: unchanged ───────────────────────────────────────

describe("legacy shared bridge account (firmware <= 1.2) keeps every path", () => {
  test("reads and completes commands of a user that delegates to it", async () => {
    await assertSucceeds(getDoc(doc(asShared(), `users/${U_LEGACY}/commands/c1`)));
    await assertSucceeds(updateDoc(doc(asShared(), `users/${U_LEGACY}/commands/c1`), { status: "completed" }));
  });
  test("writes that user's heartbeat", async () => {
    await assertSucceeds(setDoc(doc(asShared(), `users/${U_LEGACY}/bridge_status/current`), { uptime: 2 }, { merge: true }));
  });
  test("creates and updates registry docs (any device, as before)", async () => {
    await assertSucceeds(updateDoc(doc(asShared(), `bridge_registry/${DEV_B}`), { lastSeen: "t" }));
    await assertSucceeds(setDoc(doc(asShared(), `bridge_registry/${DEV_NEW}`), { status: "unpaired", pairedUid: "", pendingUid: "" }));
  });
  test("reads the OTA manifest", async () => {
    await assertSucceeds(getDoc(doc(asShared(), "bridge_firmware/stable")));
  });
  test("is refused by a user that delegates to a per-bridge account", async () => {
    await assertFails(getDoc(doc(asShared(), `users/${U_PER}/commands/c1`)));
  });
});

// ── Per-bridge account ─────────────────────────────────────────────────────

describe("per-bridge account bridge_<deviceId>", () => {
  test("reads, completes and heartbeats for the user whose bridge_email names it", async () => {
    await assertSucceeds(getDoc(doc(asPerBridge(DEV_A), `users/${U_PER}/commands/c1`)));
    await assertSucceeds(updateDoc(doc(asPerBridge(DEV_A), `users/${U_PER}/commands/c1`), { status: "completed" }));
    await assertSucceeds(setDoc(doc(asPerBridge(DEV_A), `users/${U_PER}/bridge_status/current`), { uptime: 2 }, { merge: true }));
  });
  test("is refused by any other user's queue", async () => {
    await assertFails(getDoc(doc(asPerBridge(DEV_A), `users/${U_LEGACY}/commands/c1`)));
    await assertFails(updateDoc(doc(asPerBridge(DEV_B), `users/${U_PER}/commands/c1`), { status: "completed" }));
  });
  test("updates its own registry doc and creates it when missing", async () => {
    await assertSucceeds(updateDoc(doc(asPerBridge(DEV_A), `bridge_registry/${DEV_A}`), { lastSeen: "t" }));
    await assertSucceeds(setDoc(doc(asPerBridge(DEV_NEW), `bridge_registry/${DEV_NEW}`), { status: "unpaired", pairedUid: "", pendingUid: "" }));
  });
  test("cannot touch another bridge's registry doc", async () => {
    await assertFails(updateDoc(doc(asPerBridge(DEV_A), `bridge_registry/${DEV_B}`), { pairedUid: U_PER }));
    await assertFails(setDoc(doc(asPerBridge(DEV_A), `bridge_registry/${DEV_NEW}`), { status: "unpaired" }));
  });
  test("still cannot write a blocked pairedUid onto its own doc", async () => {
    expect(BLOCKED_UID).toBeTruthy();
    await assertFails(updateDoc(doc(asPerBridge(DEV_A), `bridge_registry/${DEV_A}`), { pairedUid: BLOCKED_UID }));
  });
  test("reads the OTA manifest but cannot write it", async () => {
    await assertSucceeds(getDoc(doc(asPerBridge(DEV_A), "bridge_firmware/stable")));
    await assertFails(setDoc(doc(asPerBridge(DEV_A), "bridge_firmware/stable"), { version: "9.9.9" }));
  });
  test("cannot delete a registry doc", async () => {
    await assertFails(deleteDoc(doc(asPerBridge(DEV_A), `bridge_registry/${DEV_A}`)));
  });
});

// ── Look-alikes and ordinary users ─────────────────────────────────────────

describe("accounts that are not bridges", () => {
  test("a client account with a copied per-bridge email gets no registry or manifest access", async () => {
    await assertFails(updateDoc(doc(asEmailSquatter(), `bridge_registry/${DEV_A}`), { lastSeen: "t" }));
    await assertFails(getDoc(doc(asEmailSquatter(), "bridge_firmware/stable")));
  });
  test("an ordinary user cannot read or write the OTA manifest", async () => {
    await assertFails(getDoc(doc(asOther(), "bridge_firmware/stable")));
    await assertFails(setDoc(doc(asOther(), "bridge_firmware/stable"), { version: "9.9.9" }));
  });
  test("an unauthenticated caller cannot read the OTA manifest", async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "bridge_firmware/stable")));
  });
  test("pairing request on an UNPAIRED bridge still works; on a paired one still fails", async () => {
    await assertSucceeds(updateDoc(doc(asOther(), `bridge_registry/${DEV_UNPAIRED}`), { status: "pairing", pendingUid: OTHER }));
    await assertFails(updateDoc(doc(asOther(), `bridge_registry/${DEV_A}`), { status: "pairing", pendingUid: OTHER }));
  });
  test("an owner still reads their own commands", async () => {
    await assertSucceeds(getDoc(doc(asOwner(U_PER), `users/${U_PER}/commands/c1`)));
  });
});

// Phase R3 (end of migration) closes the one gap R1 deliberately leaves
// unchanged from today: isBridgeForUser compares emails only, so an account
// that copies a per-bridge email reaches that user's queue. R3 adds the uid
// anchor to isBridgeForUser once no bridge authenticates with the shared
// account. Pinned there, not here, so R1 stays strictly additive.
test.todo("R3: a client account with a copied per-bridge email is refused by the user's queue");
