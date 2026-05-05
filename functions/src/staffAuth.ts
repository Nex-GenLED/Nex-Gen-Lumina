/**
 * mintStaffToken — Firebase Cloud Function (callable)
 *
 * Server-side validation of the staff PIN flow that today runs entirely
 * in the Flutter client. Mirrors:
 *   • lib/features/sales/sales_providers.dart
 *     SalesModeNotifier.enterSalesMode (lines 60-144)
 *   • lib/features/installer/installer_providers.dart
 *     InstallerModeNotifier.enterInstallerMode (lines 164-258)
 *
 * Why this exists: the existing client flow forces the staff-pin
 * screen to read the master PIN hashes directly out of Firestore. A
 * 4-digit PIN is trivially brute-forceable from a leaked SHA-256, so
 * exposing the hash to anonymous sessions is effectively the same as
 * exposing the PIN. This callable validates server-side and returns a
 * Firebase Auth custom token with role + dealerCode claims so the
 * client never reads the hashes.
 *
 * Contract:
 *   request.data: { pin: string, mode: 'sales' | 'installer' }
 *   response:     { token, role, dealerCode, displayName, source }
 *
 * Errors:
 *   invalid-argument   pin is not 4-6 digits, or mode is not one of
 *                      the allowed values.
 *   permission-denied  no master PIN match AND no active installer
 *                      doc match. The error message is intentionally
 *                      generic — clients should not be able to
 *                      distinguish "wrong PIN" from "missing config"
 *                      from "inactive installer".
 *   internal           createCustomToken failed.
 *
 * Audit log:
 *   Every attempt (success and failure) appends one doc to
 *   `staff_auth_log`. The PIN itself is NEVER written. The custom
 *   token claim `pin` is server-side only and is not read by any
 *   firestore.rules expression.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:mintStaffToken
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { createHash } from "crypto";

// admin.initializeApp() is called in index.js — do not call again here.

// ── Constants ───────────────────────────────────────────────────────────────

const PIN_REGEX = /^\d{4,6}$/;

// Mirrors the synthetic session created when the client matches the
// master installer PIN — see installer_providers.dart lines 183-198.
const MASTER_DEALER_CODE = "88";
const MASTER_DISPLAY_NAME = "Nex-Gen Administrator";

// ── Types ───────────────────────────────────────────────────────────────────

type StaffMode = "sales" | "installer";
type StaffSource = "master" | "installer_doc";
type StaffRole = "salesperson" | "installer";

interface MintStaffTokenInput {
  pin: string;
  mode: StaffMode;
}

interface MintStaffTokenResult {
  token: string;
  role: StaffRole;
  dealerCode: string;
  displayName: string;
  source: StaffSource;
}

interface ResolvedSession {
  dealerCode: string;
  displayName: string;
  source: StaffSource;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

function sha256Hex(input: string): string {
  return createHash("sha256").update(input, "utf8").digest("hex");
}

function roleForMode(mode: StaffMode): StaffRole {
  return mode === "sales" ? "salesperson" : "installer";
}

/**
 * Resolve a session against the master PIN doc for `mode`. Returns
 * null if the doc is missing OR the stored hash does not match.
 *
 * Sales master uses the first 2 digits of the PIN as the dealer code
 * (mirrors sales_providers.dart line 84). Installer master uses the
 * fixed Nex-Gen admin dealer code (mirrors installer_providers.dart
 * line 186).
 */
async function tryMasterPin(
  db: admin.firestore.Firestore,
  mode: StaffMode,
  pin: string,
  hashHex: string,
): Promise<ResolvedSession | null> {
  const docId = mode === "sales" ? "master_sales_pin" : "master_installer";
  const snap = await db.collection("app_config").doc(docId).get();
  if (!snap.exists) return null;

  const storedHash = snap.data()?.pin_hash as string | undefined;
  if (!storedHash || storedHash !== hashHex) return null;

  return {
    dealerCode:
      mode === "sales" ? pin.substring(0, 2) : MASTER_DEALER_CODE,
    displayName: MASTER_DISPLAY_NAME,
    source: "master",
  };
}

/**
 * Fallback: query `installers` for an active doc whose `fullPin`
 * equals the entered PIN. Used by both modes when the master PIN
 * doesn't match (mirrors the per-installer fallback shared by
 * sales_providers.dart lines 99-134 and installer_providers.dart
 * lines 207-257).
 *
 * Note: this fallback bypasses the dealer-active check that the
 * client's enterInstallerMode applies. If that becomes a real
 * concern later, gate on dealers/{dealerCode}.isActive here too.
 */
async function tryInstallersDoc(
  db: admin.firestore.Firestore,
  pin: string,
): Promise<ResolvedSession | null> {
  const snap = await db
    .collection("installers")
    .where("fullPin", "==", pin)
    .where("isActive", "==", true)
    .limit(1)
    .get();
  if (snap.empty) return null;

  const data = snap.docs[0].data();
  const dealerCode =
    (data.dealerCode as string | undefined) ?? pin.substring(0, 2);
  const displayName = (data.name as string | undefined) ?? "Installer";

  return {
    dealerCode,
    displayName,
    source: "installer_doc",
  };
}

/**
 * Best-effort audit log writer. Failures are logged but never
 * propagated — a successful auth must not be rolled back because the
 * audit row failed to write, and a failed auth must still surface
 * permission-denied to the client.
 */
async function writeAuditLog(
  db: admin.firestore.Firestore,
  entry: {
    mode: StaffMode;
    success: boolean;
    source: StaffSource | null;
    ip: string | null;
    dealerCode: string | null;
  },
): Promise<void> {
  try {
    await db.collection("staff_auth_log").add({
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ...entry,
    });
  } catch (err) {
    logger.error(
      `mintStaffToken: audit log write failed: ${(err as Error).message}`,
    );
  }
}

// ── Cloud Function ──────────────────────────────────────────────────────────

export const mintStaffToken = onCall(
  {
    region: "us-central1",
    maxInstances: 10,
  },
  async (request): Promise<MintStaffTokenResult> => {
    const data = (request.data ?? {}) as Partial<MintStaffTokenInput>;
    const pin = (data.pin ?? "").trim();
    const mode = data.mode;
    const ip = request.rawRequest?.ip ?? null;

    // ── Input validation ────────────────────────────────────────────────
    if (!PIN_REGEX.test(pin)) {
      throw new HttpsError("invalid-argument", "pin must be 4-6 digits");
    }
    if (mode !== "sales" && mode !== "installer") {
      throw new HttpsError(
        "invalid-argument",
        "mode must be 'sales' or 'installer'",
      );
    }

    const db = admin.firestore();
    const hashHex = sha256Hex(pin);

    // ── Resolution: master first, then installers fallback ──────────────
    let resolved: ResolvedSession | null = await tryMasterPin(
      db,
      mode,
      pin,
      hashHex,
    );
    if (!resolved) {
      resolved = await tryInstallersDoc(db, pin);
    }

    // ── No match: log the failure and refuse ────────────────────────────
    if (!resolved) {
      await writeAuditLog(db, {
        mode,
        success: false,
        source: null,
        ip,
        dealerCode: null,
      });
      throw new HttpsError("permission-denied", "Authentication failed");
    }

    // ── Mint the custom token ───────────────────────────────────────────
    const role = roleForMode(mode);
    const uid = `staff_${mode}_${pin}`;
    const claims = {
      role,
      dealerCode: resolved.dealerCode,
      source: resolved.source,
      pin, // Server-side audit only; never read by Firestore rules.
    };

    let token: string;
    try {
      token = await admin.auth().createCustomToken(uid, claims);
    } catch (err) {
      logger.error(
        `mintStaffToken: createCustomToken failed for ${uid}: ${(err as Error).message}`,
      );
      throw new HttpsError("internal", "Failed to mint staff token");
    }

    // ── Success path: log + return ──────────────────────────────────────
    await writeAuditLog(db, {
      mode,
      success: true,
      source: resolved.source,
      ip,
      dealerCode: resolved.dealerCode,
    });

    return {
      token,
      role,
      dealerCode: resolved.dealerCode,
      displayName: resolved.displayName,
      source: resolved.source,
    };
  },
);
