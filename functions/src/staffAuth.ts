/**
 * mintStaffToken — Firebase Cloud Function (callable)
 *
 * Server-side validation of the staff PIN flow that today runs entirely
 * in the Flutter client. Mirrors:
 *   • lib/features/sales/sales_providers.dart
 *     SalesModeNotifier.enterSalesMode (lines 60-144)
 *   • lib/features/installer/installer_providers.dart
 *     InstallerModeNotifier.enterInstallerMode (lines 164-258)
 *   • lib/features/installer/admin/admin_providers.dart
 *     validateAdminPin (lines 60-115; will be migrated to call this
 *     callable in Prompt 8-iii)
 *   • lib/features/corporate/providers/corporate_providers.dart
 *     CorporateModeNotifier.authenticate — to be migrated as 'owner' mode
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
 *   request.data: { pin: string, mode: 'sales' | 'installer' | 'admin' | 'owner' }
 *   response:     { token, role, dealerCode, displayName, source }
 *
 *   `dealerCode` in the response is an empty string for owner mode
 *   (cross-dealer god mode); for other modes it's the dealer this
 *   session is scoped to. The custom token's `dealerCode` claim is
 *   only minted for non-owner modes — owner sessions have no
 *   dealerCode claim at all so rule helpers cleanly distinguish
 *   "scoped staff" from "unscoped owner."
 *
 * Mode → master doc → role mapping:
 *   sales      → app_config/master_sales_pin     → role: 'salesperson'
 *   installer  → app_config/master_installer     → role: 'installer'
 *   admin      → app_config/master_admin         → role: 'admin'
 *   owner      → app_config/master_corporate_pin → role: 'owner'
 *                (no installers fallback, no dealer.isActive check)
 *
 * Strict mode-role enforcement on the per-installer fallback:
 *   When the master PIN doesn't match, sales/installer/admin modes
 *   look up the PIN in the `installers` collection. The matched doc's
 *   `role` field MUST equal the role corresponding to the requested
 *   mode. A salesperson PIN cannot accidentally authenticate under
 *   installer mode (or vice versa) just because it's a 4-digit number
 *   that exists in the collection. Missing role field is treated as
 *   a mismatch (PIN miss).
 *
 *   Owner mode skips the installers fallback entirely — corporate
 *   credentials are master-only by design.
 *
 * Errors:
 *   invalid-argument    pin is not 4-6 digits, or mode is not one of
 *                       the allowed values.
 *   resource-exhausted  rate limit exceeded for the caller's IP
 *                       (10 attempts per 60 seconds).
 *   permission-denied   no master PIN match AND no active installer
 *                       doc match — OR matched installer's role
 *                       doesn't match the requested mode — OR matched
 *                       installer's dealer is inactive. The error
 *                       message is intentionally generic — clients
 *                       should not be able to distinguish between
 *                       these failure modes.
 *   internal            createCustomToken failed (e.g. IAM
 *                       Service Account Token Creator role missing
 *                       on the Cloud Functions runtime SA).
 *
 * Audit log:
 *   Every attempt (success and failure) appends one doc to
 *   `staff_auth_log`. The PIN itself is NEVER written. The custom
 *   token claim `pin` is server-side only and is not read by any
 *   firestore.rules expression.
 *
 *   `source` field on audit-log entries:
 *     'master'           success via master PIN doc
 *     'installer_doc'    success via per-installer fallback
 *     null               PIN miss (no branch matched, OR role mismatch
 *                        on installers fallback)
 *     'dealer_inactive'  per-installer match but dealer.isActive false
 *     'mint_failed'      createCustomToken threw (e.g. IAM denial)
 *     'rate_limited'     IP exceeded the 10/60s window
 *
 * Rate limit:
 *   Tracked per-IP in `staff_auth_rate_limit/{ipAddress}`. Window is
 *   10 attempts per 60 seconds. Failed and successful attempts both
 *   count. On Firestore transaction failure the check fails OPEN
 *   (allows the request, logs the failure) so a Firestore blip never
 *   locks all staff out — security trade-off chosen for MVP.
 *
 *   FOLLOW-UP: configure Firestore TTL policy on
 *   `staff_auth_rate_limit` to expire docs at `windowStart + 1h`
 *   so attacker counter docs don't accumulate. Console-only step;
 *   not deployable from this file.
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

// Dealer code minted for master-PIN auth that doesn't have a per-PIN
// derived dealer (i.e. installer + admin masters). Was '88' as a
// sentinel before 2026-05-05; corrected to '55' (Tyler's HQ /
// Nex-Gen first dealer) so dealer.isActive checks resolve against a
// real dealer doc rather than a fictitious one.
const MASTER_DEALER_CODE = "55";
const MASTER_DISPLAY_NAME = "Nex-Gen Administrator";

// Per-IP rate limit. The 10/60s window is loose enough that a real
// salesperson fat-fingering a PIN doesn't get blocked but tight enough
// that brute-forcing a 4-digit PIN (10,000 candidates) takes >10
// minutes per IP rather than seconds.
const RATE_LIMIT_MAX_ATTEMPTS = 10;
const RATE_LIMIT_WINDOW_MS = 60_000;

// ── Types ───────────────────────────────────────────────────────────────────

type StaffMode = "sales" | "installer" | "admin" | "owner";

// Source values returned to the client on success. The client treats
// these as opaque and stores them in the staff session for display /
// debugging only.
type StaffSource = "master" | "installer_doc";

// Superset of StaffSource that includes audit-only values. These extra
// values are never returned to the client — they only appear in
// staff_auth_log entries to disambiguate failure modes during
// forensics.
type AuditSource =
  | StaffSource
  | "rate_limited"
  | "mint_failed"
  | "dealer_inactive";

type StaffRole = "salesperson" | "installer" | "admin" | "owner";

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
  switch (mode) {
    case "sales":
      return "salesperson";
    case "installer":
      return "installer";
    case "admin":
      return "admin";
    case "owner":
      return "owner";
  }
}

/**
 * Mode → master PIN doc id + the dealerCode that a successful match on
 * THAT master doc should mint. Returns null for unknown modes (defense
 * in depth — the caller already validated mode, but switch fall-through
 * is the kind of bug that bites later).
 *
 *   sales:     dealerCode derived from PIN's first 2 digits
 *              (mirrors sales_providers.dart line 84)
 *   installer: dealerCode = MASTER_DEALER_CODE ('55')
 *   admin:     dealerCode = MASTER_DEALER_CODE ('55')
 *   owner:     dealerCode = '' (no dealer scope — cross-dealer god mode)
 */
function masterConfigForMode(
  mode: StaffMode,
  pin: string,
): { docId: string; dealerCode: string } {
  switch (mode) {
    case "sales":
      return { docId: "master_sales_pin", dealerCode: pin.substring(0, 2) };
    case "installer":
      return { docId: "master_installer", dealerCode: MASTER_DEALER_CODE };
    case "admin":
      return { docId: "master_admin", dealerCode: MASTER_DEALER_CODE };
    case "owner":
      return { docId: "master_corporate_pin", dealerCode: "" };
  }
}

/**
 * IP-based rate limit. Returns true if the caller has exceeded the
 * window and should be rejected. Atomic via Firestore transaction so
 * concurrent requests from the same IP can't both slip through at
 * count == limit-1.
 *
 * Counter doc shape: `staff_auth_rate_limit/{ip}` with fields
 *   { count: number, windowStart: Timestamp }
 *
 * Window logic: if `now > windowStart + window`, reset counter to 1
 * with a new windowStart. Otherwise increment until count hits the
 * cap, then reject without further increment (so the doc doesn't
 * grow unbounded mid-window).
 *
 * Fail-open on transaction errors: if the read-modify-write throws
 * (network blip, contention), allow the request and log. A Firestore
 * outage shouldn't lock every salesperson out of staff mode.
 */
async function checkRateLimit(
  db: admin.firestore.Firestore,
  ip: string,
): Promise<boolean> {
  try {
    const docRef = db.collection("staff_auth_rate_limit").doc(ip);
    const now = Date.now();

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(docRef);
      const data = snap.data();

      if (!snap.exists || !data) {
        tx.set(docRef, {
          count: 1,
          windowStart: admin.firestore.Timestamp.fromMillis(now),
        });
        return false;
      }

      const windowStart =
        (data.windowStart as admin.firestore.Timestamp | undefined)?.toMillis() ??
        0;
      const count = (data.count as number | undefined) ?? 0;

      if (now > windowStart + RATE_LIMIT_WINDOW_MS) {
        // Window expired — reset.
        tx.set(docRef, {
          count: 1,
          windowStart: admin.firestore.Timestamp.fromMillis(now),
        });
        return false;
      }

      if (count >= RATE_LIMIT_MAX_ATTEMPTS) {
        // Hit cap; don't increment further, just reject.
        return true;
      }

      tx.update(docRef, {
        count: admin.firestore.FieldValue.increment(1),
      });
      return false;
    });
  } catch (err) {
    logger.error(
      `mintStaffToken: rate limit check failed (failing open): ${(err as Error).message}`,
    );
    return false;
  }
}

/**
 * Resolve a session against the master PIN doc for `mode`. Returns
 * null if the doc is missing OR the stored hash does not match.
 *
 * Per-mode dealerCode mapping is centralized in masterConfigForMode().
 */
async function tryMasterPin(
  db: admin.firestore.Firestore,
  mode: StaffMode,
  pin: string,
  hashHex: string,
): Promise<ResolvedSession | null> {
  const config = masterConfigForMode(mode, pin);
  const snap = await db.collection("app_config").doc(config.docId).get();
  if (!snap.exists) return null;

  const storedHash = snap.data()?.pin_hash as string | undefined;
  if (!storedHash || storedHash !== hashHex) return null;

  return {
    dealerCode: config.dealerCode,
    displayName: MASTER_DISPLAY_NAME,
    source: "master",
  };
}

/**
 * Fallback: query `installers` for an active doc whose `fullPin`
 * equals the entered PIN. Used by sales/installer/admin modes when
 * the master PIN doesn't match. Owner mode skips this fallback —
 * corporate credentials are master-only.
 *
 * Strict mode-role enforcement: matched doc's `role` field MUST equal
 * the role corresponding to the requested mode. Mismatch (including
 * missing role field) returns null — treated as a PIN miss to avoid
 * leaking which branch was tried.
 *
 * NOTE: the dealer-active check is NOT done here — it's done in the
 * caller via isDealerActive() after we have a resolved session. That
 * keeps the per-installer query symmetric with the master path
 * (master never checks dealer.isActive — corporate credentials
 * shouldn't be gated by any dealer's status).
 */
async function tryInstallersDoc(
  db: admin.firestore.Firestore,
  pin: string,
  mode: StaffMode,
): Promise<ResolvedSession | null> {
  // Owner mode is master-only by design — no per-installer fallback.
  if (mode === "owner") return null;

  const snap = await db
    .collection("installers")
    .where("fullPin", "==", pin)
    .where("isActive", "==", true)
    .limit(1)
    .get();
  if (snap.empty) return null;

  const data = snap.docs[0].data();

  // Strict mode-role enforcement: the matched installer doc's role
  // must match the requested mode. Prevents a salesperson PIN from
  // authenticating under installer mode (or vice versa) just because
  // it's a 4-digit number that exists in the collection.
  //
  // Missing role field is a mismatch — the AdminService that creates
  // these docs will need to populate role explicitly going forward.
  // Existing docs (none in dev as of 2026-05-05; collection is empty)
  // would fail this check until role is backfilled.
  const docRole = data.role as string | undefined;
  if (docRole !== roleForMode(mode)) return null;

  const dealerCode =
    (data.dealerCode as string | undefined) ?? pin.substring(0, 2);
  const displayName = (data.name as string | undefined) ?? "Staff";

  return {
    dealerCode,
    displayName,
    source: "installer_doc",
  };
}

/**
 * Returns true iff a `dealers` doc exists with `dealerCode == X` and
 * `isActive == true`. Mirrors the client check at
 * installer_providers.dart:228-238 — uses a where-query rather than a
 * doc-id lookup because dealer docs may not be keyed by dealerCode.
 *
 * Only called in the per-installer fallback path. Master PIN paths
 * deliberately bypass this check, AND owner mode bypasses it entirely
 * (cross-dealer scope by design).
 */
async function isDealerActive(
  db: admin.firestore.Firestore,
  dealerCode: string,
): Promise<boolean> {
  const snap = await db
    .collection("dealers")
    .where("dealerCode", "==", dealerCode)
    .where("isActive", "==", true)
    .limit(1)
    .get();
  return !snap.empty;
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
    source: AuditSource | null;
    ip: string | null;
    dealerCode: string | null;
    error?: string;
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

    // ── 1. Validate pin format ──────────────────────────────────────────
    if (!PIN_REGEX.test(pin)) {
      throw new HttpsError("invalid-argument", "pin must be 4-6 digits");
    }

    // ── 2. Validate mode ────────────────────────────────────────────────
    if (
      mode !== "sales" &&
      mode !== "installer" &&
      mode !== "admin" &&
      mode !== "owner"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "mode must be 'sales', 'installer', 'admin', or 'owner'",
      );
    }

    const db = admin.firestore();

    // ── 3. Rate limit by IP (or 'unknown' bucket if no IP available) ────
    //
    // Both successful and failed attempts count. A legitimate
    // salesperson typing 10 PINs in a minute is wrong regardless of
    // whether the PINs are right — and successful brute force is still
    // brute force.
    const rateLimitKey = ip ?? "unknown";
    if (await checkRateLimit(db, rateLimitKey)) {
      await writeAuditLog(db, {
        mode,
        success: false,
        source: "rate_limited",
        ip,
        dealerCode: null,
      });
      throw new HttpsError(
        "resource-exhausted",
        "Too many attempts. Try again in a minute.",
      );
    }

    // ── 4. Hash PIN ─────────────────────────────────────────────────────
    const hashHex = sha256Hex(pin);

    // ── 5-6. Resolution: master first, then installers fallback ─────────
    //
    // Owner mode skips the installers fallback (master-only by design).
    // tryInstallersDoc handles that internally — returns null for owner
    // without making the query — but the comment is here so the flow is
    // obvious.
    let resolved: ResolvedSession | null = await tryMasterPin(
      db,
      mode,
      pin,
      hashHex,
    );
    if (!resolved) {
      resolved = await tryInstallersDoc(db, pin, mode);
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

    // ── 7. Per-installer match: enforce dealer.isActive ─────────────────
    //
    // Master PIN matches bypass this check — corporate-level credentials
    // shouldn't be gated by any specific dealer's status. Per-installer
    // matches MUST verify the dealer is active to mirror the client
    // behavior at installer_providers.dart:228-238 and to prevent a
    // deactivated dealer's still-active installer from minting tokens.
    //
    // Owner mode never reaches this branch (no installers fallback) —
    // even if it did, owner is cross-dealer by design and shouldn't be
    // gated by any single dealer's active state.
    if (resolved.source === "installer_doc") {
      const dealerActive = await isDealerActive(db, resolved.dealerCode);
      if (!dealerActive) {
        await writeAuditLog(db, {
          mode,
          success: false,
          source: "dealer_inactive",
          ip,
          dealerCode: resolved.dealerCode,
        });
        // Same generic message as PIN miss — don't leak whether the
        // dealer is deactivated vs the PIN is wrong.
        throw new HttpsError("permission-denied", "Authentication failed");
      }
    }

    // ── 8. Mint the custom token (with audit-on-failure) ────────────────
    //
    // Owner mode mints WITHOUT a `dealerCode` claim — the absence of
    // the claim is how rule helpers distinguish "scoped staff session"
    // from "unscoped owner session". For all other modes the claim is
    // present and equals the resolved dealerCode.
    const role = roleForMode(mode);
    const uid = `staff_${mode}_${pin}`;
    const claims: {
      role: StaffRole;
      source: StaffSource;
      pin: string;
      dealerCode?: string;
    } = {
      role,
      source: resolved.source,
      pin, // Server-side audit only; never read by Firestore rules.
    };
    if (mode !== "owner") {
      claims.dealerCode = resolved.dealerCode;
    }

    let token: string;
    try {
      token = await admin.auth().createCustomToken(uid, claims);
    } catch (err) {
      // Most common cause: the Cloud Functions runtime SA lacks
      // `roles/iam.serviceAccountTokenCreator` (signBlob) permission.
      // Surfaced 2026-05-05 during initial smoke test — invisible in
      // staff_auth_log before this commit because mint failures fell
      // through neither the success-log nor the PIN-miss-log paths.
      const errCode =
        (err as { code?: string }).code ?? (err as Error).message ?? "unknown";
      logger.error(
        `mintStaffToken: createCustomToken failed for ${uid}: ${errCode}`,
      );
      await writeAuditLog(db, {
        mode,
        success: false,
        source: "mint_failed",
        ip,
        dealerCode: resolved.dealerCode || null,
        error: String(errCode).slice(0, 200),
      });
      throw new HttpsError("internal", "Failed to mint staff token");
    }

    // ── 9. Success path: log + return ───────────────────────────────────
    await writeAuditLog(db, {
      mode,
      success: true,
      source: resolved.source,
      ip,
      dealerCode: resolved.dealerCode || null,
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
