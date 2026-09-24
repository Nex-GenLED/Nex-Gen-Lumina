/**
 * Integration tests for healUserProfile and the assignReferralCode gate,
 * against the Firestore AND Auth emulators.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * firebase-admin pointed at BOTH emulators (FIRESTORE_EMULATOR_HOST and
 * FIREBASE_AUTH_EMULATOR_HOST). The repo's firebase.json declares only the
 * Firestore emulator, so run with a config that also declares auth
 * (port 9099) — see test/emulator/README.md.
 *
 * Drives the exported runHealUserProfile() / runAssignReferralCode() rather
 * than the onDocumentCreated wrappers, so the real Auth lookup, transaction
 * and merge execute against the emulators.
 *
 * Asserts (residential-path-audit-2026-09-23 §9.2.1 / §9.2.2):
 *   • a stub created for an email user is healed with exactly the seven
 *     required keys, created_at = Auth creation time, stub keys preserved;
 *   • display_name falls back to the email's local part;
 *   • a full profile is untouched (byte-identical before/after);
 *   • a partially-filled doc gets only its absent keys (never overwrite);
 *   • anonymous Auth users are skipped, the stub is left as-is;
 *   • staff_* uids are skipped WITHOUT an Auth lookup;
 *   • a uid with no Auth record is skipped;
 *   • the healer is idempotent;
 *   • a stub and a racing client skeleton write converge to the same
 *     document in either landing order;
 *   • assignReferralCode assigns for an email user, and skips anonymous and
 *     staff_* uids (no code, no referral_codes doc).
 */

import * as admin from "firebase-admin";

if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error(
    "healUserProfile.emulator.test.ts needs the Auth emulator " +
      "(FIREBASE_AUTH_EMULATOR_HOST is unset). See test/emulator/README.md."
  );
}
if (!admin.apps.length) {
  admin.initializeApp({ projectId: "lumina-fn-test" });
}
const db = admin.firestore();
const auth = admin.auth();
const { FieldValue, Timestamp } = admin.firestore;

import {
  HEALED_FIELDS,
  runHealUserProfile,
} from "../../src/healUserProfile";
import { runAssignReferralCode } from "../../src/assignReferralCode";

// ── Helpers ─────────────────────────────────────────────────────────────────

// RFC 2606 reserved domain — never a real mailbox.
const EMAIL = "jane.roof@example.test";

/** The FCM token store's write (sync_notification_service.dart:359-362). */
const STUB = () => ({
  fcmToken: "fcm-token-abc",
  fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
});

/** The router's lazy skeleton (route_guards.dart:28-41), as a merge. */
function clientSkeleton(uid: string, email: string, displayName?: string) {
  return {
    id: uid,
    email,
    display_name: displayName ?? email.split("@")[0],
    owner_id: uid,
    created_at: FieldValue.serverTimestamp(),
    updated_at: FieldValue.serverTimestamp(),
    installation_role: "unlinked",
    welcome_completed: false,
  };
}

async function wipeUsersAndCodes() {
  for (const col of ["users", "referral_codes"]) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  const page = await auth.listUsers(1000);
  if (page.users.length) {
    await auth.deleteUsers(page.users.map((u) => u.uid));
  }
}

async function read(uid: string): Promise<Record<string, unknown> | null> {
  const snap = await db.doc(`users/${uid}`).get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : null;
}

/** Strips timestamp-valued keys so two docs can be compared for convergence. */
function withoutTimestamps(doc: Record<string, unknown>) {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(doc)) {
    if (!(v instanceof Timestamp)) out[k] = v;
  }
  return out;
}

beforeEach(wipeUsersAndCodes);
afterAll(wipeUsersAndCodes);

// ── healUserProfile ─────────────────────────────────────────────────────────

describe("healUserProfile", () => {
  test("stub for an email user is healed with the seven required keys", async () => {
    const uid = "u-email-1";
    await auth.createUser({ uid, email: EMAIL, displayName: "Jane Roof" });
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });

    const plan = await runHealUserProfile(uid);
    expect(plan.action).toBe("heal");
    if (plan.action !== "heal") return;
    expect(Object.keys(plan.fields).sort()).toEqual([...HEALED_FIELDS].sort());

    const doc = (await read(uid))!;
    expect(doc.id).toBe(uid);
    expect(doc.owner_id).toBe(uid);
    expect(doc.email).toBe(EMAIL);
    expect(doc.display_name).toBe("Jane Roof");
    expect(doc.installation_role).toBe("unlinked");
    expect(doc.created_at).toBeInstanceOf(Timestamp);
    expect(doc.updated_at).toBeInstanceOf(Timestamp);

    // created_at is the Auth creation time, not "now".
    const rec = await auth.getUser(uid);
    expect((doc.created_at as admin.firestore.Timestamp).toMillis()).toBe(
      Date.parse(rec.metadata.creationTime)
    );

    // The stub's own keys survive.
    expect(doc.fcmToken).toBe("fcm-token-abc");
    expect(doc.fcmTokenUpdatedAt).toBeInstanceOf(Timestamp);
  });

  test("display_name falls back to the email local part", async () => {
    const uid = "u-email-2";
    await auth.createUser({ uid, email: EMAIL });
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });

    const plan = await runHealUserProfile(uid);
    expect(plan.action).toBe("heal");
    expect((await read(uid))!.display_name).toBe("jane.roof");
  });

  test("a full profile is untouched (skip: already_provisioned)", async () => {
    const uid = "u-full";
    await auth.createUser({ uid, email: EMAIL, displayName: "Auth Name" });
    const full = {
      id: uid,
      owner_id: uid,
      email: EMAIL,
      display_name: "Profile Name",
      created_at: Timestamp.fromMillis(1_700_000_000_000),
      updated_at: Timestamp.fromMillis(1_700_000_001_000),
      installation_role: "primary",
      installation_id: "inst-1",
      dealer_code: "55",
      welcome_completed: true,
    };
    await db.doc(`users/${uid}`).set(full);
    const before = await read(uid);

    const plan = await runHealUserProfile(uid);
    expect(plan).toEqual({ action: "skip", reason: "already_provisioned" });
    expect(await read(uid)).toEqual(before);
  });

  test("only absent keys are filled; set keys are never overwritten", async () => {
    const uid = "u-partial";
    await auth.createUser({ uid, email: EMAIL, displayName: "Auth Name" });
    const oldCreated = Timestamp.fromMillis(1_600_000_000_000);
    await db.doc(`users/${uid}`).set({
      ...STUB(),
      display_name: "Kept Name",
      created_at: oldCreated,
      installation_role: "subUser",
      // owner_id absent → still a stub by the rules' own test.
    });

    const plan = await runHealUserProfile(uid);
    expect(plan.action).toBe("heal");
    if (plan.action !== "heal") return;
    expect(Object.keys(plan.fields).sort()).toEqual(
      ["email", "id", "owner_id", "updated_at"].sort()
    );

    const doc = (await read(uid))!;
    expect(doc.display_name).toBe("Kept Name");
    expect((doc.created_at as admin.firestore.Timestamp).isEqual(oldCreated)).toBe(true);
    expect(doc.installation_role).toBe("subUser");
    expect(doc.owner_id).toBe(uid);
    expect(doc.id).toBe(uid);
    expect(doc.email).toBe(EMAIL);
  });

  test("anonymous Auth user is skipped and the stub is left as-is", async () => {
    const uid = "u-anon";
    await auth.createUser({ uid }); // no email, no provider → anonymous
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });
    const before = await read(uid);

    const plan = await runHealUserProfile(uid);
    expect(plan).toEqual({ action: "skip", reason: "anonymous" });
    expect(await read(uid)).toEqual(before);
    expect(Object.keys(before!).sort()).toEqual(["fcmToken", "fcmTokenUpdatedAt"]);
  });

  test("staff_* uid is skipped without an Auth lookup", async () => {
    const uid = "staff_installer_TESTPIN";
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });
    const before = await read(uid);

    const getAuthUser = jest.fn(async () => {
      throw new Error("Auth must not be consulted for a staff uid");
    });
    const plan = await runHealUserProfile(uid, { getAuthUser });
    expect(plan).toEqual({ action: "skip", reason: "staff_uid" });
    expect(getAuthUser).not.toHaveBeenCalled();
    expect(await read(uid)).toEqual(before);
  });

  test("uid with no Auth record is skipped", async () => {
    const uid = "u-ghost";
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });
    const before = await read(uid);

    const plan = await runHealUserProfile(uid);
    expect(plan).toEqual({ action: "skip", reason: "auth_missing" });
    expect(await read(uid)).toEqual(before);
  });

  test("deleted document is skipped, never re-created", async () => {
    const uid = "u-deleted";
    await auth.createUser({ uid, email: EMAIL });
    const plan = await runHealUserProfile(uid);
    expect(plan).toEqual({ action: "skip", reason: "doc_missing" });
    expect(await read(uid)).toBeNull();
  });

  test("idempotent: a second run skips and changes nothing", async () => {
    const uid = "u-twice";
    await auth.createUser({ uid, email: EMAIL });
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });

    expect((await runHealUserProfile(uid)).action).toBe("heal");
    const after1 = await read(uid);
    expect(await runHealUserProfile(uid)).toEqual({
      action: "skip",
      reason: "already_provisioned",
    });
    expect(await read(uid)).toEqual(after1);
  });

  test("stub + racing client skeleton converge in either landing order", async () => {
    // The same uid and email both times (Auth rejects a duplicate email, so
    // the two orders run one after the other with a wipe in between).
    const uid = "u-race";
    const seed = () => auth.createUser({ uid, email: EMAIL, displayName: "Jane Roof" });
    const stub = () => db.doc(`users/${uid}`).set(STUB(), { merge: true });
    const skeleton = () =>
      db.doc(`users/${uid}`).set(clientSkeleton(uid, EMAIL, "Jane Roof"), { merge: true });

    // Order A: FCM stub → client skeleton merge → healer (healer skips).
    await seed();
    await stub();
    await skeleton();
    expect(await runHealUserProfile(uid)).toEqual({
      action: "skip",
      reason: "already_provisioned",
    });
    const docA = (await read(uid))!;

    await wipeUsersAndCodes();

    // Order B: FCM stub → healer → client skeleton merge.
    await seed();
    await stub();
    expect((await runHealUserProfile(uid)).action).toBe("heal");
    await skeleton();
    const docB = (await read(uid))!;

    // Same key set, same value on every non-timestamp key.
    expect(Object.keys(docA).sort()).toEqual(Object.keys(docB).sort());
    expect(withoutTimestamps(docA)).toEqual(withoutTimestamps(docB));

    // Both carry every required key as a real value / Timestamp.
    for (const d of [docA, docB]) {
      for (const k of HEALED_FIELDS) expect(d[k]).toBeDefined();
      expect(d.created_at).toBeInstanceOf(Timestamp);
      expect(d.updated_at).toBeInstanceOf(Timestamp);
      expect(d.welcome_completed).toBe(false);
      expect(d.fcmToken).toBe("fcm-token-abc");
    }
  });
});

// ── assignReferralCode gate ─────────────────────────────────────────────────

describe("assignReferralCode gate (decided from Auth)", () => {
  test("email user gets a code and a reverse-lookup doc", async () => {
    const uid = "u-ref-email";
    await auth.createUser({ uid, email: EMAIL });
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });

    const res = await runAssignReferralCode(uid);
    expect(res.assigned).toMatch(/^LUM-[A-Z0-9]{4}$/);
    const code = res.assigned as string;
    expect((await read(uid))!.referralCode).toBe(code);
    const lookup = await db.doc(`referral_codes/${code}`).get();
    expect(lookup.exists).toBe(true);
    expect(lookup.get("uid")).toBe(uid);
  });

  test("anonymous user: no code, no referral_codes doc", async () => {
    const uid = "u-ref-anon";
    await auth.createUser({ uid });
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });

    const res = await runAssignReferralCode(uid);
    expect(res).toEqual({ assigned: null, reason: "anonymous" });
    expect((await read(uid))!.referralCode).toBeUndefined();
    expect((await db.collection("referral_codes").get()).size).toBe(0);
  });

  test("staff_* uid: no code, no Auth lookup", async () => {
    const uid = "staff_installer_TESTPIN";
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });

    const getAuthUser = jest.fn(async () => {
      throw new Error("Auth must not be consulted for a staff uid");
    });
    const res = await runAssignReferralCode(uid, { getAuthUser });
    expect(res).toEqual({ assigned: null, reason: "staff_uid" });
    expect(getAuthUser).not.toHaveBeenCalled();
    expect((await read(uid))!.referralCode).toBeUndefined();
    expect((await db.collection("referral_codes").get()).size).toBe(0);
  });

  test("uid with no Auth record: no code", async () => {
    const uid = "u-ref-ghost";
    await db.doc(`users/${uid}`).set(STUB(), { merge: true });
    const res = await runAssignReferralCode(uid);
    expect(res).toEqual({ assigned: null, reason: "auth_missing" });
    expect((await db.collection("referral_codes").get()).size).toBe(0);
  });
});
