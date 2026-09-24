/**
 * Pure-logic tests for the users/{uid} onCreate identity gates:
 *   • healUserProfile.planHeal — what to merge, or why not
 *   • assignReferralCode.referralCodeGate — assign, or why not
 *   • authIdentity — staff / anonymous discrimination
 *
 * Runs against the tsc output in lib/ (run `npm run build` first). No
 * emulator, no firebase-admin IO: firebase-admin is required only for the
 * Timestamp value class. The emulator counterpart drives the real
 * transaction + Auth lookup: test/emulator/healUserProfile.emulator.test.ts.
 */

const admin = require("firebase-admin");
const { Timestamp } = admin.firestore;

const {
  planHeal,
  displayNameFor,
  authCreationTimestamp,
  isSetField,
  HEALED_FIELDS,
} = require("../../lib/healUserProfile");
const { referralCodeGate } = require("../../lib/assignReferralCode");
const { isStaffUid, isAnonymousAuthUser } = require("../../lib/authIdentity");

const NOW = Timestamp.fromMillis(1_800_000_000_000);
const CREATED = "Tue, 23 Sep 2026 16:55:20 GMT"; // Auth's RFC 2822 format
const EMAIL = "jane.roof@example.test";

const emailUser = (over = {}) => ({
  uid: "u1",
  email: EMAIL,
  displayName: "Jane Roof",
  providerData: [{ providerId: "password" }],
  metadata: { creationTime: CREATED },
  ...over,
});
const anonUser = (over = {}) => ({
  uid: "u-anon",
  providerData: [],
  metadata: { creationTime: CREATED },
  ...over,
});
const STUB = { fcmToken: "t", fcmTokenUpdatedAt: NOW };

describe("authIdentity", () => {
  test("isStaffUid: prefix only", () => {
    expect(isStaffUid("staff_installer_TESTPIN")).toBe(true);
    expect(isStaffUid("staff_owner_TESTPIN")).toBe(true);
    expect(isStaffUid("Staff_installer_TESTPIN")).toBe(false);
    expect(isStaffUid("u_staff_x")).toBe(false);
    expect(isStaffUid("")).toBe(false);
  });

  test("isAnonymousAuthUser: no email AND no provider", () => {
    expect(isAnonymousAuthUser(anonUser())).toBe(true);
    expect(isAnonymousAuthUser({ uid: "x" })).toBe(true); // providerData undefined
    expect(isAnonymousAuthUser(emailUser())).toBe(false);
    // email present but no providers (custom token with an email) → not anonymous
    expect(isAnonymousAuthUser({ uid: "x", email: EMAIL, providerData: [] })).toBe(false);
    // provider present but no email (phone) → not anonymous
    expect(
      isAnonymousAuthUser({ uid: "x", providerData: [{ providerId: "phone" }] })
    ).toBe(false);
  });
});

describe("healUserProfile helpers", () => {
  test("isSetField: null/undefined/blank strings are unset", () => {
    expect(isSetField(undefined)).toBe(false);
    expect(isSetField(null)).toBe(false);
    expect(isSetField("")).toBe(false);
    expect(isSetField("   ")).toBe(false);
    expect(isSetField("x")).toBe(true);
    expect(isSetField(0)).toBe(true);
    expect(isSetField(false)).toBe(true);
    expect(isSetField(NOW)).toBe(true);
  });

  test("displayNameFor: Auth displayName, else email local part, else 'User'", () => {
    expect(displayNameFor(emailUser())).toBe("Jane Roof");
    expect(displayNameFor(emailUser({ displayName: "  " }))).toBe("jane.roof");
    expect(displayNameFor(emailUser({ displayName: null }))).toBe("jane.roof");
    expect(displayNameFor({ uid: "x", email: "@nolocal.example" })).toBe("User");
    expect(displayNameFor({ uid: "x" })).toBe("User");
  });

  test("authCreationTimestamp: parses Auth's RFC 2822 creationTime", () => {
    const ts = authCreationTimestamp(emailUser(), NOW);
    expect(ts.toMillis()).toBe(Date.parse(CREATED));
    expect(ts.toMillis()).toBe(Date.UTC(2026, 8, 23, 16, 55, 20));
  });

  test("authCreationTimestamp: falls back to now when missing/garbage", () => {
    expect(authCreationTimestamp(emailUser({ metadata: {} }), NOW)).toBe(NOW);
    expect(authCreationTimestamp(emailUser({ metadata: undefined }), NOW)).toBe(NOW);
    expect(
      authCreationTimestamp(emailUser({ metadata: { creationTime: "not a date" } }), NOW)
    ).toBe(NOW);
  });
});

describe("planHeal", () => {
  test("stub + email user → heal with exactly the seven required keys", () => {
    const plan = planHeal("u1", STUB, emailUser(), NOW);
    expect(plan.action).toBe("heal");
    expect(Object.keys(plan.fields).sort()).toEqual([...HEALED_FIELDS].sort());
    expect(plan.fields).toMatchObject({
      id: "u1",
      owner_id: "u1",
      email: EMAIL,
      display_name: "Jane Roof",
      installation_role: "unlinked",
      updated_at: NOW,
    });
    expect(plan.fields.created_at.toMillis()).toBe(Date.parse(CREATED));
  });

  test("uid comes from the document path, not the Auth record", () => {
    const plan = planHeal("path-uid", STUB, emailUser({ uid: "other" }), NOW);
    expect(plan.fields.id).toBe("path-uid");
    expect(plan.fields.owner_id).toBe("path-uid");
  });

  test("never overwrites: only absent keys are in the plan", () => {
    const existing = {
      ...STUB,
      display_name: "Kept",
      created_at: Timestamp.fromMillis(1),
      installation_role: "subUser",
    };
    const plan = planHeal("u1", existing, emailUser(), NOW);
    expect(plan.action).toBe("heal");
    expect(Object.keys(plan.fields).sort()).toEqual(
      ["email", "id", "owner_id", "updated_at"].sort()
    );
  });

  test("empty-string owner_id counts as unset (matches rules isProvisionedUser)", () => {
    const plan = planHeal("u1", { ...STUB, owner_id: "" }, emailUser(), NOW);
    expect(plan.action).toBe("heal");
    expect(plan.fields.owner_id).toBe("u1");
  });

  test("already provisioned (owner_id set) → skip, regardless of Auth", () => {
    expect(planHeal("u1", { owner_id: "u1" }, emailUser(), NOW)).toEqual({
      action: "skip",
      reason: "already_provisioned",
    });
    expect(planHeal("u1", { owner_id: "u1" }, null, NOW)).toEqual({
      action: "skip",
      reason: "already_provisioned",
    });
  });

  test("staff_* uid → skip before anything else", () => {
    expect(planHeal("staff_installer_TESTPIN", STUB, emailUser(), NOW)).toEqual({
      action: "skip",
      reason: "staff_uid",
    });
    expect(planHeal("staff_installer_TESTPIN", null, null, NOW)).toEqual({
      action: "skip",
      reason: "staff_uid",
    });
  });

  test("deleted doc → skip (never re-created)", () => {
    expect(planHeal("u1", null, emailUser(), NOW)).toEqual({
      action: "skip",
      reason: "doc_missing",
    });
  });

  test("no Auth record → skip", () => {
    expect(planHeal("u1", STUB, null, NOW)).toEqual({
      action: "skip",
      reason: "auth_missing",
    });
  });

  test("anonymous Auth user → skip", () => {
    expect(planHeal("u1", STUB, anonUser(), NOW)).toEqual({
      action: "skip",
      reason: "anonymous",
    });
  });

  test("provider but no email (phone) → skip: no_email", () => {
    const phone = { uid: "u1", providerData: [{ providerId: "phone" }] };
    expect(planHeal("u1", STUB, phone, NOW)).toEqual({
      action: "skip",
      reason: "no_email",
    });
  });
});

describe("referralCodeGate", () => {
  test("email user → assign", () => {
    expect(referralCodeGate("u1", emailUser())).toEqual({ assign: true });
  });
  test("staff_* uid → skip even with an Auth record", () => {
    expect(referralCodeGate("staff_installer_TESTPIN", emailUser())).toEqual({
      assign: false,
      reason: "staff_uid",
    });
  });
  test("no Auth record → skip", () => {
    expect(referralCodeGate("u1", null)).toEqual({
      assign: false,
      reason: "auth_missing",
    });
  });
  test("anonymous → skip", () => {
    expect(referralCodeGate("u1", anonUser())).toEqual({
      assign: false,
      reason: "anonymous",
    });
  });
  test("a stub document does not matter — the gate never reads the doc", () => {
    // The gate takes no document argument at all; an email user whose first
    // document is the FCM stub still gets a code (the healer repairs the doc).
    expect(referralCodeGate("u1", emailUser({ displayName: null })).assign).toBe(true);
  });
});
