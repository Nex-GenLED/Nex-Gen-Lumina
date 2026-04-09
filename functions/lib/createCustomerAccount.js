"use strict";
/**
 * createCustomerAccount — Firebase Cloud Function (callable)
 *
 * Creates the customer-facing Firebase Auth user during the Day 2
 * wrap-up flow. Replaces the client-side stub the wrap-up screen has
 * been calling against — see day2_wrap_up_screen.dart Step 3 for the
 * caller, and the Prompt 7 build report for the contract.
 *
 * Idempotent: if a user already exists for the supplied email, returns
 * that user's uid with tempPasswordSent=false. The wrap-up screen
 * already handles this case.
 *
 * Side effects on success:
 *   • Creates the auth user (admin.auth().createUser)
 *   • Generates a password reset link (admin.auth().generatePasswordResetLink)
 *   • Sends a welcome email via Resend with the reset link + store links
 *   • Seeds /users/{uid} with displayName, email, dealerCode, jobId,
 *     installation_role: 'primary'
 *
 * NOTE: this function does NOT call SalesJobService.linkToInstall to
 * write the new uid back onto the SalesJob — that's the wrap-up
 * screen's job (it calls setLinkedUserId after this returns).
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:createCustomerAccount
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.createCustomerAccount = void 0;
const https_1 = require("firebase-functions/v2/https");
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
const messaging_helpers_1 = require("./messaging-helpers");
// admin.initializeApp() is called in index.js — do not call again here.
// ── Store URL placeholders (mirror of onSalesJobStatusChanged.ts) ───────────
// TODO: replace with real store URLs once the apps are listed.
const APP_STORE_URL = "https://apps.apple.com/app/lumina/id[PLACEHOLDER_APP_ID]";
const PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=[PLACEHOLDER_PACKAGE_ID]";
// ── Email regex ─────────────────────────────────────────────────────────────
// Loose check — full RFC 5322 is unnecessary; bad addresses get rejected
// by Firebase Auth on createUser anyway. We just want to fail fast on
// obviously broken input.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// ── Welcome email body builder ──────────────────────────────────────────────
function buildWelcomeEmail(params) {
    const { displayName, email, resetLink } = params;
    const firstName = displayName.split(" ")[0] || "there";
    const subject = "Set up your Nex-Gen LED Lumina account";
    const text = [
        `Hi ${firstName},`,
        "",
        "Welcome to Nex-Gen LED! Your Lumina account is ready and just needs a password.",
        "",
        "Set your password using this link:",
        resetLink,
        "",
        `(This link is tied to ${email}. If you didn't expect this email, you can safely ignore it.)`,
        "",
        "Once your password is set, download Lumina to control your lights:",
        `  • iPhone: ${APP_STORE_URL}`,
        `  • Android: ${PLAY_STORE_URL}`,
        "",
        "Welcome to the family!",
        "— Nex-Gen LED",
    ].join("\n");
    const html = `
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background:#f6f9fc; margin:0; padding:24px; color:#1a1a1a;">
  <div style="max-width:560px; margin:0 auto; background:#ffffff; border-radius:12px; padding:32px; box-shadow:0 1px 3px rgba(0,0,0,0.06);">
    <h1 style="color:#00B7C2; font-size:24px; margin:0 0 16px 0;">Welcome to Nex-Gen LED</h1>
    <p style="font-size:16px; line-height:1.5;">Hi ${firstName},</p>
    <p style="font-size:16px; line-height:1.5;">
      Your Lumina account is ready and just needs a password.
    </p>

    <div style="text-align:center; margin:28px 0;">
      <a href="${resetLink}" style="display:inline-block; background:#00B7C2; color:#ffffff; text-decoration:none; padding:14px 28px; border-radius:8px; font-size:16px; font-weight:600;">Set your password</a>
    </div>

    <p style="font-size:13px; line-height:1.5; color:#888;">
      This link is tied to <strong>${email}</strong>. If you didn't expect
      this email, you can safely ignore it.
    </p>

    <h3 style="font-size:14px; color:#1a1a1a; margin:32px 0 12px 0;">Once your password is set, download Lumina:</h3>
    <div style="margin:8px 0;">
      <a href="${APP_STORE_URL}" style="display:inline-block; background:#1a1a1a; color:#ffffff; text-decoration:none; padding:12px 18px; border-radius:8px; font-size:14px; font-weight:600; margin-right:8px;">iPhone</a>
      <a href="${PLAY_STORE_URL}" style="display:inline-block; background:#1a1a1a; color:#ffffff; text-decoration:none; padding:12px 18px; border-radius:8px; font-size:14px; font-weight:600;">Android</a>
    </div>

    <p style="font-size:16px; line-height:1.5; margin-top:32px;">
      Welcome to the family!<br>
      — Nex-Gen LED
    </p>
  </div>
</body>
</html>
  `.trim();
    return { subject, html, text };
}
// ── Cloud Function ──────────────────────────────────────────────────────────
exports.createCustomerAccount = (0, https_1.onCall)({
    region: "us-central1",
    maxInstances: 10,
}, async (request) => {
    // ── Input validation ──────────────────────────────────────────────────
    const data = (request.data ?? {});
    const email = (data.email ?? "").trim().toLowerCase();
    const displayName = (data.displayName ?? "").trim();
    const jobId = (data.jobId ?? "").trim();
    const dealerCode = (data.dealerCode ?? "").trim();
    if (!email) {
        throw new https_1.HttpsError("invalid-argument", "email is required");
    }
    if (!EMAIL_RE.test(email)) {
        throw new https_1.HttpsError("invalid-argument", `email is malformed: ${email}`);
    }
    if (!displayName) {
        throw new https_1.HttpsError("invalid-argument", "displayName is required");
    }
    if (!jobId) {
        throw new https_1.HttpsError("invalid-argument", "jobId is required");
    }
    if (!dealerCode) {
        throw new https_1.HttpsError("invalid-argument", "dealerCode is required");
    }
    const db = admin.firestore();
    const auth = admin.auth();
    // ── Confirm the job exists ────────────────────────────────────────────
    const jobDoc = await db.collection("sales_jobs").doc(jobId).get();
    if (!jobDoc.exists) {
        throw new https_1.HttpsError("not-found", `sales job ${jobId} not found`);
    }
    // ── Idempotency: existing user → return early ─────────────────────────
    let existingUser = null;
    try {
        existingUser = await auth.getUserByEmail(email);
    }
    catch (err) {
        const code = err.code;
        // 'auth/user-not-found' is the expected case for a brand new account.
        if (code !== "auth/user-not-found") {
            firebase_functions_1.logger.error(`createCustomerAccount: getUserByEmail failed for ${email}: ${err.message}`);
            throw new https_1.HttpsError("internal", "Failed to look up existing user");
        }
    }
    if (existingUser) {
        firebase_functions_1.logger.info(`createCustomerAccount: user already exists for ${email} (uid=${existingUser.uid}), returning idempotent response`);
        return {
            uid: existingUser.uid,
            tempPasswordSent: false,
        };
    }
    // ── Create the new auth user ──────────────────────────────────────────
    let createdUser;
    try {
        createdUser = await auth.createUser({
            email,
            displayName,
            emailVerified: false,
        });
        firebase_functions_1.logger.info(`createCustomerAccount: created auth user ${createdUser.uid} for ${email}`);
    }
    catch (err) {
        firebase_functions_1.logger.error(`createCustomerAccount: createUser failed for ${email}: ${err.message}`);
        throw new https_1.HttpsError("internal", "Failed to create auth user");
    }
    // ── Generate the password reset link ──────────────────────────────────
    let resetLink;
    try {
        resetLink = await auth.generatePasswordResetLink(email);
    }
    catch (err) {
        firebase_functions_1.logger.error(`createCustomerAccount: generatePasswordResetLink failed for ${email}: ${err.message}`);
        // Roll back the user we just created so the caller can retry
        // cleanly. If the rollback itself fails we still throw the
        // original error — the caller doesn't need to know about the
        // cleanup attempt.
        try {
            await auth.deleteUser(createdUser.uid);
        }
        catch (rollbackErr) {
            firebase_functions_1.logger.error(`createCustomerAccount: rollback deleteUser failed for ${createdUser.uid}: ${rollbackErr.message}`);
        }
        throw new https_1.HttpsError("internal", "Failed to generate password reset link");
    }
    // ── Send the welcome email via Resend ─────────────────────────────────
    //
    // Email failures are NOT a hard error — the auth user is already
    // created, the user doc is about to be seeded, and the wrap-up
    // screen will surface a snackbar to the installer either way. We
    // log loudly so the dealer can re-trigger manually if needed.
    let tempPasswordSent = false;
    try {
        const { subject, html, text } = buildWelcomeEmail({
            displayName,
            email,
            resetLink,
        });
        await (0, messaging_helpers_1.sendEmail)({
            to: email,
            subject,
            htmlBody: html,
            textBody: text,
        });
        tempPasswordSent = true;
    }
    catch (err) {
        firebase_functions_1.logger.error(`createCustomerAccount: welcome email failed for ${email}: ${err.message}`);
        // tempPasswordSent stays false — the response signals to the
        // wrap-up screen that the email didn't actually go out.
    }
    // ── Seed the user document ────────────────────────────────────────────
    //
    // Matches the snake_case `installation_role` field convention used
    // in installer_providers.dart. The 'primary' value tags this as
    // the customer-owned account (vs an installer's sub-user account).
    try {
        await db.collection("users").doc(createdUser.uid).set({
            displayName,
            email,
            dealerCode,
            jobId,
            installation_role: "primary",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    catch (err) {
        firebase_functions_1.logger.error(`createCustomerAccount: failed to seed users/${createdUser.uid}: ${err.message}`);
        // We don't roll back the auth user here — the user exists, the
        // welcome email may have already gone out, and the wrap-up
        // screen's setLinkedUserId call will still succeed. A missing
        // /users doc is recoverable on next sign-in.
    }
    return {
        uid: createdUser.uid,
        tempPasswordSent,
    };
});
//# sourceMappingURL=createCustomerAccount.js.map