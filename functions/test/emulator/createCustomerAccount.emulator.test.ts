/**
 * Dealer-tools item 9 — createCustomerAccount auth gate, store links and
 * email gating, against the Firestore AND Auth emulators.
 *
 * ⚠️ NOT run by `npm test`. Needs a firebase.json declaring firestore + auth
 * emulators (see README.md) and FIREBASE_AUTH_EMULATOR_HOST set; this file
 * refuses to load otherwise, so it can never create a real Auth user.
 *
 * NOTHING LEAVES THE MACHINE: sendEmail / sendSms are replaced with jest
 * mocks, and the `resend` and `twilio` modules are replaced with
 * constructors that throw, as a tripwire in case anything reaches them.
 * RESEND_API_KEY is unset except inside the one test that sets a dummy
 * value to prove the "key present" branch calls the (mocked) sender.
 *
 * Drives runCreateCustomerAccount() with a synthetic CallableRequest, so the
 * real gate, Auth calls and user-doc seed all execute.
 */

jest.mock("resend", () => ({
  Resend: jest.fn(() => {
    throw new Error("tripwire: Resend must never be constructed in tests");
  }),
}));
jest.mock("twilio", () => ({
  Twilio: jest.fn(() => {
    throw new Error("tripwire: Twilio must never be constructed in tests");
  }),
}));
jest.mock("../../src/messaging-helpers", () => {
  const actual = jest.requireActual("../../src/messaging-helpers");
  return {
    ...actual,
    sendEmail: jest.fn(async () => undefined),
    sendSms: jest.fn(async () => {
      throw new Error("tripwire: sendSms must not be called here");
    }),
  };
});

import * as admin from "firebase-admin";
import { CallableRequest } from "firebase-functions/v2/https";

for (const k of ["RESEND_API_KEY", "RESEND_FROM_EMAIL", "RESEND_FROM_NAME",
  "TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM_NUMBER"]) {
  delete process.env[k];
}
if (!process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    "createCustomerAccount.emulator.test needs the Auth AND Firestore emulators " +
      "(FIREBASE_AUTH_EMULATOR_HOST / FIRESTORE_EMULATOR_HOST unset).",
  );
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-dealer-tools";
if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const auth = admin.auth();

import { runCreateCustomerAccount } from "../../src/createCustomerAccount";
import * as messaging from "../../src/messaging-helpers";

const sendEmail = messaging.sendEmail as unknown as jest.Mock;
const HOOK_TIMEOUT_MS = 60_000;

type Claims = Record<string, unknown>;
const req = (data: Record<string, unknown>, who?: { uid: string; token?: Claims }) =>
  ({
    data,
    auth: who ? { uid: who.uid, token: (who.token ?? {}) as never } : undefined,
  }) as unknown as Pick<CallableRequest, "auth" | "data">;

const INST01 = { uid: "staff_installer_FIXTURE01", token: { role: "installer", dealerCode: "01" } };
const INST02 = { uid: "staff_installer_FIXTURE02", token: { role: "installer", dealerCode: "02" } };
const SALES01 = { uid: "staff_sales_FIXTURE01", token: { role: "salesperson", dealerCode: "01" } };
const ADMIN01 = { uid: "staff_admin_FIXTURE01", token: { role: "admin", dealerCode: "01" } };
const ADMIN02 = { uid: "staff_admin_FIXTURE02", token: { role: "admin", dealerCode: "02" } };
const OWNER = { uid: "staff_owner_FIXTURE", token: { role: "owner" } };
const CUSTOMER = { uid: "cust_a_uid", token: {} };

const input = (email: string, dealerCode = "01", jobId = "job01") => ({
  email,
  displayName: "Pat Example",
  jobId,
  dealerCode,
});

async function codeOf(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "ok";
  } catch (e) {
    return (e as { code?: string }).code ?? String(e);
  }
}

async function authUserExists(email: string): Promise<boolean> {
  try {
    await auth.getUserByEmail(email);
    return true;
  } catch {
    return false;
  }
}

async function wipe() {
  const page = await auth.listUsers(1000);
  if (page.users.length) await auth.deleteUsers(page.users.map((u) => u.uid));
  for (const c of ["users", "sales_jobs", "dealers"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => db.recursiveDelete(d.ref)));
  }
}

beforeEach(async () => {
  sendEmail.mockClear();
  delete process.env.RESEND_API_KEY;
  await wipe();
  await db.doc("sales_jobs/job01").set({ id: "job01", dealerCode: "01", status: "installComplete" });
  await db.doc("dealers/01").set({ dealerCode: "01", name: "Dealer One", isActive: true });
}, HOOK_TIMEOUT_MS);

afterAll(async () => {
  await wipe();
  await Promise.all(admin.apps.map((a) => a?.delete()));
});

describe("createCustomerAccount — who may call it", () => {
  test("unauthenticated: refused, no Auth user created", async () => {
    expect(await codeOf(runCreateCustomerAccount(req(input("a@example.com"))))).toBe("unauthenticated");
    expect(await authUserExists("a@example.com")).toBe(false);
  });
  test("a signed-in customer (no staff claim): refused", async () => {
    expect(await codeOf(runCreateCustomerAccount(req(input("b@example.com"), CUSTOMER)))).toBe("permission-denied");
    expect(await authUserExists("b@example.com")).toBe(false);
  });
  test("a salesperson claim of the job's dealer: refused (installer, admin or owner only)", async () => {
    expect(await codeOf(runCreateCustomerAccount(req(input("c@example.com"), SALES01)))).toBe("permission-denied");
  });
  test("an installer of ANOTHER dealer: refused, no Auth user created", async () => {
    expect(await codeOf(runCreateCustomerAccount(req(input("d@example.com"), INST02)))).toBe("permission-denied");
    expect(await authUserExists("d@example.com")).toBe(false);
  });
  test("an admin claim of another dealer: refused", async () => {
    expect(await codeOf(runCreateCustomerAccount(req(input("e@example.com"), ADMIN02)))).toBe("permission-denied");
  });
  test("the job's installer asking to stamp a DIFFERENT dealer code: refused", async () => {
    expect(await codeOf(runCreateCustomerAccount(req(input("f@example.com", "02"), INST01)))).toBe("permission-denied");
    expect(await authUserExists("f@example.com")).toBe(false);
  });
  test("a job that does not exist: not-found", async () => {
    expect(await codeOf(runCreateCustomerAccount(req(input("g@example.com", "01", "nojob"), INST01)))).toBe("not-found");
  });

  test.each([
    ["the job's installer", INST01],
    ["an admin claim of the job's dealer", ADMIN01],
    ["the owner claim (no dealerCode by design)", OWNER],
  ])("%s: creates the account and seeds the profile", async (_label, who) => {
    const email = `ok_${who.uid}@example.com`.toLowerCase();
    const res = await runCreateCustomerAccount(req(input(email), who));
    const user = await auth.getUserByEmail(email);
    expect(res.uid).toBe(user.uid);
    const profile = (await db.doc(`users/${user.uid}`).get()).data() ?? {};
    expect(profile.dealer_code).toBe("01");
    expect(profile.installation_role).toBe("primary");
    expect(profile.owner_id).toBe(user.uid);
  });
});

describe("createCustomerAccount — email", () => {
  test("no RESEND_API_KEY: no send is attempted and tempPasswordSent is false", async () => {
    const res = await runCreateCustomerAccount(req(input("nokey@example.com"), INST01));
    expect(res.tempPasswordSent).toBe(false);
    expect(sendEmail).not.toHaveBeenCalled();
  });
  test("RESEND_API_KEY present: the (mocked) sender gets one email with no store links", async () => {
    process.env.RESEND_API_KEY = "dummy-value-for-test-only";
    const res = await runCreateCustomerAccount(req(input("withkey@example.com"), INST01));
    expect(res.tempPasswordSent).toBe(true);
    expect(sendEmail).toHaveBeenCalledTimes(1);
    const sent = sendEmail.mock.calls[0][0] as { to: string; htmlBody: string; textBody: string };
    expect(sent.to).toBe("withkey@example.com");
    for (const body of [sent.htmlBody, sent.textBody]) {
      expect(body).not.toMatch(/PLACEHOLDER/);
      expect(body).not.toMatch(/apps\.apple\.com|play\.google\.com/);
      expect(body).toMatch(/sign in to the Lumina app/);
    }
  });
});

describe("createCustomerAccount — existing accounts", () => {
  test("an existing account of ANOTHER dealer is refused and left as it was", async () => {
    const u = await auth.createUser({ email: "taken@example.com" });
    await db.doc(`users/${u.uid}`).set({ id: u.uid, owner_id: u.uid, dealer_code: "02" });
    expect(await codeOf(runCreateCustomerAccount(req(input("taken@example.com"), INST01)))).toBe("permission-denied");
    expect((await db.doc(`users/${u.uid}`).get()).get("dealer_code")).toBe("02");
  });
  test("an existing account with no dealer yet is reused and seeded, no email", async () => {
    const u = await auth.createUser({ email: "free@example.com" });
    process.env.RESEND_API_KEY = "dummy-value-for-test-only";
    const res = await runCreateCustomerAccount(req(input("free@example.com"), INST01));
    expect(res).toEqual({ uid: u.uid, tempPasswordSent: false });
    expect((await db.doc(`users/${u.uid}`).get()).get("dealer_code")).toBe("01");
    expect(sendEmail).not.toHaveBeenCalled();
  });
});
