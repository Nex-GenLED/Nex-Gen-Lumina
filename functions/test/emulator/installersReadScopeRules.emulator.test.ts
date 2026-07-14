/**
 * D3-HOTFIX — /installers read is admin/owner only.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * @firebase/rules-unit-testing + a running Firestore emulator. See
 * test/emulator/README.md.
 *
 * THE VECTOR THIS CLOSES (was live in production):
 *   • /installers docs store `fullPin` in CLEARTEXT.
 *   • `allow read: if request.auth != null` let ANY authenticated session —
 *     including anonymous — list every installer in the fleet.
 *   • mintStaffToken never reads request.auth (staffAuth.ts:424-440), so a
 *     PIN is a complete credential.
 *   => list /installers -> read the admin doc's cleartext PIN ->
 *      mintStaffToken({mode:'admin', pin}) -> admin-claim token -> global
 *      cross-dealer read.
 *
 * PIN LOGIN IS UNAFFECTED: mintStaffToken reads /installers via the ADMIN
 * SDK (`const db = admin.firestore()`, staffAuth.ts:453, passed into
 * tryInstallersDoc at :329-338), which bypasses security rules entirely.
 * These tests exercise the CLIENT surface only — that is the whole point:
 * the client never needed this read for auth.
 *
 * NOTE ON THE STAFF-CLAIM CASES BELOW: an installer/salesperson claim is
 * DENIED on purpose. hasStaffClaim would close the anonymous vector but not
 * the escalation one — the master installer PIN is a fleet-shared secret, so
 * any installer could read their dealer's ADMIN doc cleartext PIN and
 * escalate. While PINs are plaintext, admin/owner is the only defensible
 * scope. If a future commit hashes the PINs and relaxes this read, THESE
 * TESTS SHOULD BE UPDATED DELIBERATELY, not deleted quietly.
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
} from "firebase/firestore";

const PROJECT_ID = "lumina-rules-test-installerread";

const DEALER = "55";
const ADMIN_DOC = "test_admin_5520";
const INSTALLER_DOC = "test_installer_5510";

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
  // Mirrors the two docs that are live in production today.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `installers/${ADMIN_DOC}`), {
      dealerCode: DEALER,
      fullPin: "5520", // CLEARTEXT — the credential this rule now protects
      role: "admin",
      isActive: true,
      name: "Test Admin Jones",
    });
    await setDoc(doc(db, `installers/${INSTALLER_DOC}`), {
      dealerCode: DEALER,
      fullPin: "5510",
      role: "installer",
      isActive: true,
      name: "Test Installer Smith",
    });
  });
});

const signedOut = () => env.unauthenticatedContext().firestore();
const randomAuthed = () => env.authenticatedContext("random-user-uid").firestore();
const anonWizard = () =>
  env
    .authenticatedContext("anon-wizard-uid", { provider_id: "anonymous" })
    .firestore();
const staff = (role: "installer" | "salesperson", dealerCode: string) =>
  env
    .authenticatedContext(`staff_${role}_${dealerCode}01`, { role, dealerCode })
    .firestore();
const adminClaim = () =>
  env.authenticatedContext("staff_admin_5501", { role: "admin" }).firestore();
const ownerClaim = () =>
  env.authenticatedContext("staff_owner_9999", { role: "owner" }).firestore();

describe("D3 — the live vector is closed", () => {
  test("a random authenticated user CANNOT read an installer doc", async () => {
    await assertFails(getDoc(doc(randomAuthed(), `installers/${ADMIN_DOC}`)));
  });

  test("a random authenticated user CANNOT LIST /installers", async () => {
    // The actual attack: enumerate the collection, harvest cleartext PINs.
    await assertFails(getDocs(collection(randomAuthed(), "installers")));
  });

  test("the anonymous wizard session CANNOT read the admin doc's cleartext PIN", async () => {
    await assertFails(getDoc(doc(anonWizard(), `installers/${ADMIN_DOC}`)));
  });

  test("a signed-out caller CANNOT read (unchanged)", async () => {
    await assertFails(getDoc(doc(signedOut(), `installers/${ADMIN_DOC}`)));
  });

  test("the fullPin-targeted query the attacker would use is DENIED", async () => {
    const q = query(
      collection(randomAuthed(), "installers"),
      where("dealerCode", "==", DEALER),
    );
    await assertFails(getDocs(q));
  });
});

describe("D3 — admin/owner retain access", () => {
  test("admin claim CAN read an installer doc", async () => {
    await assertSucceeds(getDoc(doc(adminClaim(), `installers/${ADMIN_DOC}`)));
  });

  test("admin claim CAN list /installers (corporate + dealer-admin surfaces)", async () => {
    const snap = await assertSucceeds(
      getDocs(collection(adminClaim(), "installers")),
    );
    expect(snap.docs.map((d) => d.id).sort()).toEqual(
      [ADMIN_DOC, INSTALLER_DOC].sort(),
    );
  });

  test("admin claim CAN run the dealer-scoped roster query", async () => {
    // corporate_admin_providers.dart:181 (deactivation cascade) and
    // dealer_dashboard_providers.dart:155 under an admin session.
    const q = query(
      collection(adminClaim(), "installers"),
      where("dealerCode", "==", DEALER),
    );
    const snap = await assertSucceeds(getDocs(q));
    expect(snap.size).toBe(2);
  });

  test("owner claim CAN read", async () => {
    await assertSucceeds(getDoc(doc(ownerClaim(), `installers/${ADMIN_DOC}`)));
  });
});

describe("D3 — non-admin STAFF claims are denied (deliberate; see file header)", () => {
  test("an installer claim CANNOT read its own dealer's roster", async () => {
    // Deliberate: the master installer PIN is fleet-shared, so allowing this
    // would let any installer read the ADMIN doc's cleartext PIN and
    // escalate. Known UI cost: dealer_dashboard_screen.dart _OverviewTab
    // (:243) and _TeamTab (:838) break for installer sessions.
    await assertFails(
      getDoc(doc(staff("installer", DEALER), `installers/${ADMIN_DOC}`)),
    );
  });

  test("a salesperson claim CANNOT read the roster", async () => {
    await assertFails(
      getDocs(collection(staff("salesperson", DEALER), "installers")),
    );
  });

  test("an installer claim CANNOT read the admin doc's PIN (the escalation)", async () => {
    await assertFails(
      getDoc(doc(staff("installer", DEALER), `installers/${INSTALLER_DOC}`)),
    );
  });
});
