/**
 * Dealer-tools item 7 — storage.rules for sales_jobs/** and sales/**.
 *
 * ⚠️ NOT run by `npm test`. Needs the Firestore AND Storage emulators:
 *   firebase --config <cfg declaring firestore+storage> emulators:exec \
 *     --only firestore,storage --project demo-dealer-tools "npx jest ..."
 *
 * PROJECT_ID MUST equal the CLI --project: the Storage emulator resolves the
 * rules' firestore.exists()/get() against the CLI project, not the test
 * env's (a mismatch silently turns every cross-service lookup false).
 * Object paths are unique per test because clearStorage() does not reliably
 * remove objects in this emulator.
 */

import { initializeTestEnvironment, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { doc, setDoc } from "firebase/firestore";
import {
  FirebaseStorage,
  deleteObject,
  getDownloadURL,
  ref,
  uploadBytes,
} from "firebase/storage";

import { D1, D2, ctxFor, draftJobPayload } from "./dealerToolsFixtures";

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-dealer-tools";
const HOOK_TIMEOUT_MS = 120_000;

let env: RulesTestEnvironment;
let seq = 0;
const uniq = () => `${Date.now()}_${++seq}`;
const st = (persona: string) => ctxFor(env, persona).storage() as unknown as FirebaseStorage;

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46]);

/** "ALLOW" | "DENY" — covers storage/unauthorized AND storage/unauthenticated. */
async function outcome(fn: () => Promise<unknown>): Promise<string> {
  try {
    await fn();
    return "ALLOW";
  } catch (e) {
    const code = (e as { code?: string }).code ?? "";
    if (code === "storage/unauthorized" || code === "storage/unauthenticated") return "DENY";
    throw e;
  }
}
const put = (persona: string, path: string, bytes: Uint8Array, contentType: string) =>
  outcome(() => uploadBytes(ref(st(persona), path), bytes, { contentType }));
const url = (persona: string, path: string) => outcome(() => getDownloadURL(ref(st(persona), path)));

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host: "127.0.0.1", port: 8080 },
    storage: { rules: readFileSync("../storage.rules", "utf8"), host: "127.0.0.1", port: 9199 },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "sales_jobs/job01"), draftJobPayload("job01", D1, "staff_sales_FIXTURE01"));
    await setDoc(doc(db, "sales_jobs/job02"), draftJobPayload("job02", D2, "staff_sales_FIXTURE02"));
  });
}, HOOK_TIMEOUT_MS);
afterAll(async () => env?.cleanup());

describe("item 7: sales_jobs/** (signature + sales photos), create-only", () => {
  test("the job's sales PIN uploads the signature PNG and can fetch its download URL", async () => {
    const p = `sales_jobs/job01/signature_${uniq()}.png`;
    expect(await put("sales01", p, PNG, "image/png")).toBe("ALLOW");
    expect(await url("sales01", p)).toBe("ALLOW");
  });
  test("the job's installer PIN uploads a day-1 photo", async () => {
    expect(await put("inst01", `sales_jobs/job01/day1/mat1/${uniq()}.jpg`, JPEG, "image/jpeg")).toBe("ALLOW");
  });
  test("a sales PIN uploads a prospect photo under a draft job id that is not saved yet", async () => {
    const p = `sales_jobs/draft_${uniq()}/prospect/photo_1.jpg`;
    expect(await put("sales01", p, JPEG, "image/jpeg")).toBe("ALLOW");
    expect(await url("sales01", p)).toBe("ALLOW");
  });
  test("another dealer's sales and installer PINs can neither upload to nor read a job's objects", async () => {
    const p = `sales_jobs/job01/signature_${uniq()}.png`;
    expect(await put("sales01", p, PNG, "image/png")).toBe("ALLOW");
    expect(await put("sales02", `sales_jobs/job01/signature_${uniq()}.png`, PNG, "image/png")).toBe("DENY");
    expect(await put("inst02", `sales_jobs/job01/day1/m/${uniq()}.jpg`, JPEG, "image/jpeg")).toBe("DENY");
    expect(await url("sales02", p)).toBe("DENY");
    expect(await url("inst02", p)).toBe("DENY");
  });
  test("admin and owner claims upload and read for any dealer's job", async () => {
    const p = `sales_jobs/job02/zones/z1/photo_${uniq()}.jpg`;
    expect(await put("admin55", p, JPEG, "image/jpeg")).toBe("ALLOW");
    expect(await put("owner", `sales_jobs/job02/wizard/home_${uniq()}.jpg`, JPEG, "image/jpeg")).toBe("ALLOW");
    expect(await url("owner", p)).toBe("ALLOW");
  });
  test("customers, a dealer account, an anonymous sign-in and the unauthenticated get nothing", async () => {
    const p = `sales_jobs/job01/signature_${uniq()}.png`;
    expect(await put("sales01", p, PNG, "image/png")).toBe("ALLOW");
    for (const persona of ["custA", "custSelf", "dealerAcct01", "anonSession", "unauth"]) {
      expect(await put(persona, `sales_jobs/job01/signature_${uniq()}.png`, PNG, "image/png")).toBe("DENY");
      expect(await url(persona, p)).toBe("DENY");
    }
  });
  test("a non-image content type is refused", async () => {
    expect(await put("sales01", `sales_jobs/job01/estimate_${uniq()}.pdf`, PNG, "application/pdf")).toBe("DENY");
  });
  test("an object of 10 MB or more is refused; just under is accepted", async () => {
    const big = new Uint8Array(10 * 1024 * 1024);
    const ok = new Uint8Array(10 * 1024 * 1024 - 1);
    expect(await put("inst01", `sales_jobs/job01/day1/m/${uniq()}.jpg`, big, "image/jpeg")).toBe("DENY");
    expect(await put("inst01", `sales_jobs/job01/day1/m/${uniq()}.jpg`, ok, "image/jpeg")).toBe("ALLOW");
  }, 60_000);
  test("an existing object (e.g. the signature) cannot be overwritten or deleted", async () => {
    const p = `sales_jobs/job01/signature_${uniq()}.png`;
    expect(await put("sales01", p, PNG, "image/png")).toBe("ALLOW");
    expect(await put("sales01", p, PNG, "image/png")).toBe("DENY");
    expect(await put("owner", p, PNG, "image/png")).toBe("DENY");
    expect(await outcome(() => deleteObject(ref(st("owner"), p)))).toBe("DENY");
  });
});

describe("item 7: sales/** (Day-2 install-complete photos), create + overwrite", () => {
  test("the job's installer PIN uploads a channel photo and re-shoots it", async () => {
    const p = `sales/job01/install_complete/run_${uniq()}.jpg`;
    expect(await put("inst01", p, JPEG, "image/jpeg")).toBe("ALLOW");
    expect(await put("inst01", p, JPEG, "image/jpeg")).toBe("ALLOW");
    expect(await url("inst01", p)).toBe("ALLOW");
  });
  test("another dealer's installer and a customer cannot", async () => {
    expect(await put("inst02", `sales/job01/install_complete/run_${uniq()}.jpg`, JPEG, "image/jpeg")).toBe("DENY");
    expect(await put("custA", `sales/job01/install_complete/run_${uniq()}.jpg`, JPEG, "image/jpeg")).toBe("DENY");
  });
  test("nobody deletes from the client", async () => {
    const p = `sales/job01/install_complete/run_${uniq()}.jpg`;
    expect(await put("inst01", p, JPEG, "image/jpeg")).toBe("ALLOW");
    expect(await outcome(() => deleteObject(ref(st("inst01"), p)))).toBe("DENY");
  });
});

describe("item 7: users/** is unchanged", () => {
  test("a customer still uploads their own house photo; another account cannot", async () => {
    expect(await put("custA", "users/cust_a_uid/house_photo.jpg", JPEG, "image/jpeg")).toBe("ALLOW");
    expect(await put("custB", "users/cust_a_uid/house_photo.jpg", JPEG, "image/jpeg")).toBe("DENY");
    expect(await put("sales01", "users/cust_a_uid/house_photo.jpg", JPEG, "image/jpeg")).toBe("DENY");
  });
});
