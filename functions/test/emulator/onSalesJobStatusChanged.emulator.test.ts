/**
 * Dealer-tools item 10 — onSalesJobStatusChanged sent markers and the dealer
 * SMS toggle, against the Firestore emulator.
 *
 * ⚠️ NOT run by `npm test`. Needs FIRESTORE_EMULATOR_HOST (refuses to load
 * otherwise).
 *
 * NOTHING LEAVES THE MACHINE: sendSms / sendEmail are jest mocks, the
 * `twilio` and `resend` modules are tripwire constructors that throw, and no
 * Twilio/Resend credential exists in the environment.
 *
 * Drives processSalesJobUpdate(jobId, before, after) — the trigger body —
 * against a real job document so the transactional marker claim runs.
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
    sendSms: jest.fn(async () => undefined),
  };
});

import * as admin from "firebase-admin";

for (const k of ["RESEND_API_KEY", "TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM_NUMBER"]) {
  delete process.env[k];
}
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("onSalesJobStatusChanged.emulator.test needs the Firestore emulator.");
}
const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-dealer-tools";
if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

import { processSalesJobUpdate } from "../../src/onSalesJobStatusChanged";
import * as messaging from "../../src/messaging-helpers";

const sendSms = messaging.sendSms as unknown as jest.Mock;
const sendEmail = messaging.sendEmail as unknown as jest.Mock;

const JOB = "jobMsg";
const base = {
  id: JOB,
  dealerCode: "01",
  prospect: { firstName: "Pat", lastName: "Example", email: "pat@example.com", phone: "(555) 010-0000" },
};
const at = (status: string, extra: Record<string, unknown> = {}) => ({ ...base, status, ...extra });

/** Simulate one trigger delivery for a before→after write. */
async function deliver(before: Record<string, unknown>, after: Record<string, unknown>) {
  await processSalesJobUpdate(JOB, before, after);
}
const markers = async () => ((await db.doc(`sales_jobs/${JOB}`).get()).get("messagingSent") ?? {}) as Record<string, unknown>;

beforeEach(async () => {
  sendSms.mockClear();
  sendEmail.mockClear();
  for (const c of ["sales_jobs", "dealers"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => db.recursiveDelete(d.ref)));
  }
  await db.doc(`sales_jobs/${JOB}`).set(at("draft"));
}, 60_000);

afterAll(async () => {
  await Promise.all(admin.apps.map((a) => a?.delete()));
});

describe("sent markers — each message at most once per job", () => {
  test("estimateSigned: the email goes once; a redelivery of the same event sends nothing", async () => {
    await deliver(at("estimateSent"), at("estimateSigned"));
    await deliver(at("estimateSent"), at("estimateSigned"));
    expect(sendEmail).toHaveBeenCalledTimes(1);
    expect(Object.keys(await markers())).toEqual(["estimateSignedEmail"]);
  });
  test("A→B→A→B on prewireScheduled sends the SMS once", async () => {
    await deliver(at("estimateSigned"), at("prewireScheduled"));
    await deliver(at("prewireScheduled"), at("estimateSigned"));
    await deliver(at("estimateSigned"), at("prewireScheduled"));
    expect(sendSms).toHaveBeenCalledTimes(1);
  });
  test("installScheduled SMS and installComplete email each go once", async () => {
    await deliver(at("prewireComplete"), at("installScheduled"));
    await deliver(at("prewireComplete"), at("installScheduled"));
    await deliver(at("installScheduled"), at("installComplete"));
    await deliver(at("installScheduled"), at("installComplete"));
    expect(sendSms).toHaveBeenCalledTimes(1);
    expect(sendEmail).toHaveBeenCalledTimes(1);
    expect(Object.keys(await markers()).sort()).toEqual(["installCompleteEmail", "installScheduledSms"]);
  });
  test("day1 completion SMS goes once", async () => {
    const t = admin.firestore.Timestamp.now();
    await deliver(at("prewireScheduled"), at("prewireComplete", { day1CompletedAt: t }));
    await deliver(at("prewireScheduled"), at("prewireComplete", { day1CompletedAt: t }));
    expect(sendSms).toHaveBeenCalledTimes(1);
    expect(Object.keys(await markers())).toEqual(["day1CompletedSms"]);
  });
  test("the marker write itself (no status / day1 change) sends nothing", async () => {
    await deliver(at("installScheduled"), at("installScheduled", { messagingSent: { x: 1 } }));
    expect(sendSms).not.toHaveBeenCalled();
    expect(sendEmail).not.toHaveBeenCalled();
  });
});

describe("dealer SMS toggle — dealers/{code}/config/messaging.sendStatusSms", () => {
  beforeEach(async () => {
    await db.doc("dealers/01/config/messaging").set({ dealerCode: "01", sendStatusSms: false });
  });
  test("off: no status SMS of any kind, and no marker (a later transition can still send)", async () => {
    const t = admin.firestore.Timestamp.now();
    await deliver(at("estimateSigned"), at("prewireScheduled"));
    await deliver(at("prewireComplete"), at("installScheduled"));
    await deliver(at("prewireScheduled"), at("prewireComplete", { day1CompletedAt: t }));
    expect(sendSms).not.toHaveBeenCalled();
    expect(await markers()).toEqual({});
  });
  test("off: the emails are unaffected (they keep their own toggles)", async () => {
    await deliver(at("estimateSent"), at("estimateSigned"));
    expect(sendEmail).toHaveBeenCalledTimes(1);
  });
  test("absent: defaults to ON, so a dealer with no config doc behaves as before", async () => {
    await db.doc("dealers/01/config/messaging").delete();
    await deliver(at("estimateSigned"), at("prewireScheduled"));
    expect(sendSms).toHaveBeenCalledTimes(1);
  });
});

describe("customer email content", () => {
  test("the install-complete and estimate-signed emails carry no placeholder or store link", async () => {
    await deliver(at("estimateSent"), at("estimateSigned"));
    await deliver(at("installScheduled"), at("installComplete"));
    expect(sendEmail).toHaveBeenCalledTimes(2);
    for (const [msg] of sendEmail.mock.calls as [{ htmlBody: string; textBody: string }][]) {
      for (const body of [msg.htmlBody, msg.textBody]) {
        expect(body).not.toMatch(/PLACEHOLDER/);
        expect(body).not.toMatch(/apps\.apple\.com|play\.google\.com/);
      }
    }
  });
});

describe("existing email toggles still apply and leave no marker", () => {
  test("sendEstimateSignedEmail=false: no email, no marker", async () => {
    await db.doc("dealers/01/config/messaging").set({ sendEstimateSignedEmail: false });
    await deliver(at("estimateSent"), at("estimateSigned"));
    expect(sendEmail).not.toHaveBeenCalled();
    expect(await markers()).toEqual({});
  });
});
