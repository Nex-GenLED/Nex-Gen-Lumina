/**
 * Dealer-tools item 10 — notifyDay2Team dealer scope, against the Firestore
 * emulator.
 *
 * ⚠️ NOT run by `npm test`. Needs FIRESTORE_EMULATOR_HOST (refuses to load
 * otherwise). FCM is never reached: runNotifyDay2Team() takes the multicast
 * sender as a dependency and every test passes a jest fake.
 */

import * as admin from "firebase-admin";
import { CallableRequest } from "firebase-functions/v2/https";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("notifyDay2Team.emulator.test needs the Firestore emulator.");
}
const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-dealer-tools";
if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

import { runNotifyDay2Team } from "../../src/notifyDay2Team";

type Claims = Record<string, unknown>;
const req = (jobId: string, who?: { uid: string; token?: Claims }) =>
  ({
    data: { jobId },
    auth: who ? { uid: who.uid, token: (who.token ?? {}) as never } : undefined,
  }) as unknown as Pick<CallableRequest, "auth" | "data">;

const staff = (role: string, dealerCode?: string) => ({
  uid: `staff_${role}_FIXTURE${dealerCode ?? ""}`,
  token: dealerCode ? { role, dealerCode } : { role },
});

function fakeFcm() {
  return jest.fn(async (m: admin.messaging.MulticastMessage) => ({
    successCount: m.tokens.length,
    failureCount: 0,
    responses: m.tokens.map(() => ({ success: true })),
  })) as unknown as jest.Mock;
}

async function codeOf(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "ok";
  } catch (e) {
    return (e as { code?: string }).code ?? String(e);
  }
}

beforeEach(async () => {
  for (const c of ["sales_jobs", "installers", "users"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => db.recursiveDelete(d.ref)));
  }
  await db.doc("sales_jobs/job01").set({
    id: "job01",
    dealerCode: "01",
    prospect: { firstName: "Pat", lastName: "Example", address: "1 Example St" },
  });
  await db.doc("installers/i01").set({ dealerCode: "01", isActive: true, linkedUid: "tech01" });
  await db.doc("installers/i02").set({ dealerCode: "02", isActive: true, linkedUid: "tech02" });
  await db.doc("users/tech01").set({ fcmToken: "fixture-token-dealer-01" });
  await db.doc("users/tech02").set({ fcmToken: "fixture-token-dealer-02" });
}, 60_000);

afterAll(async () => {
  await Promise.all(admin.apps.map((a) => a?.delete()));
});

describe("notifyDay2Team — the caller's staff dealerCode must be the job's", () => {
  test.each([
    ["unauthenticated", undefined, "unauthenticated"],
    ["a signed-in customer (no claim)", { uid: "cust_a_uid", token: {} }, "permission-denied"],
    ["an anonymous sign-in", { uid: "anon", token: { firebase: { sign_in_provider: "anonymous" } } }, "permission-denied"],
    ["another dealer's salesperson", staff("salesperson", "02"), "permission-denied"],
    ["another dealer's installer", staff("installer", "02"), "permission-denied"],
    ["another dealer's admin claim", staff("admin", "02"), "permission-denied"],
    ["the master admin claim (dealer 55)", staff("admin", "55"), "permission-denied"],
  ])("%s: refused, nothing sent, job untouched", async (_l, who, code) => {
    const send = fakeFcm();
    expect(await codeOf(runNotifyDay2Team(req("job01", who), { sendEachForMulticast: send }))).toBe(code);
    expect(send).not.toHaveBeenCalled();
    expect((await db.doc("sales_jobs/job01").get()).get("day2Notified")).toBeUndefined();
  });

  test.each([
    ["the job's salesperson", staff("salesperson", "01")],
    ["the job's installer", staff("installer", "01")],
    ["the job's dealer admin claim", staff("admin", "01")],
    ["the owner claim (no dealerCode by design)", staff("owner")],
  ])("%s: notifies ONLY the job's dealer's installers and marks the job", async (_l, who) => {
    const send = fakeFcm();
    const res = await runNotifyDay2Team(req("job01", who), { sendEachForMulticast: send });
    expect(res).toEqual({ success: true, notifiedCount: 1 });
    expect(send).toHaveBeenCalledTimes(1);
    expect((send.mock.calls[0][0] as admin.messaging.MulticastMessage).tokens).toEqual(["fixture-token-dealer-01"]);
    expect((await db.doc("sales_jobs/job01").get()).get("day2Notified")).toBe(true);
  });

  test("an unknown job: not-found for an authorised role", async () => {
    expect(await codeOf(runNotifyDay2Team(req("nojob", staff("installer", "01")), { sendEachForMulticast: fakeFcm() })))
      .toBe("not-found");
  });
});
