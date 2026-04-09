"use strict";
/**
 * onSalesJobStatusChanged — Firestore trigger
 *
 * Fires whenever a sales_jobs document is updated. Detects status
 * transitions and the day1 completion event, and dispatches the
 * appropriate customer-facing SMS or email via the messaging-helpers
 * module.
 *
 * Critical contract: this trigger MUST NOT throw on messaging
 * failures. A bad customer phone number, a Twilio outage, or a Resend
 * 5xx must never fail the Firestore trigger itself — that would loop
 * the trigger and corrupt the job document's update history. Every
 * outbound message call is wrapped in a per-channel try/catch that
 * logs and continues.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:onSalesJobStatusChanged
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
exports.onSalesJobStatusChanged = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
const messaging_helpers_1 = require("./messaging-helpers");
// admin.initializeApp() is called in index.js — do not call again here.
// ── App store placeholders ──────────────────────────────────────────────────
// TODO: replace with real store URLs once the apps are listed.
const APP_STORE_URL = "https://apps.apple.com/app/lumina/id[PLACEHOLDER_APP_ID]";
const PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=[PLACEHOLDER_PACKAGE_ID]";
// ── Status enum mirror (matches lib/features/sales/models/sales_models.dart) ─
const STATUS_ESTIMATE_SIGNED = "estimateSigned";
const STATUS_PREWIRE_SCHEDULED = "prewireScheduled";
const STATUS_INSTALL_SCHEDULED = "installScheduled";
const STATUS_INSTALL_COMPLETE = "installComplete";
function readProspect(jobData) {
    const p = (jobData.prospect ?? {});
    return {
        firstName: (p.firstName ?? "").trim(),
        lastName: (p.lastName ?? "").trim(),
        email: (p.email ?? "").trim(),
        phone: (p.phone ?? "").trim(),
    };
}
function readableDate(ts) {
    if (!ts)
        return "TBD";
    try {
        const date = ts.toDate();
        return date.toLocaleDateString("en-US", {
            weekday: "long",
            month: "long",
            day: "numeric",
        });
    }
    catch {
        return "TBD";
    }
}
/**
 * Look up a friendly dealer display name from /dealers/{dealerCode}.
 * Falls back to the dealer code if the doc doesn't exist or has no
 * businessName field.
 */
async function lookupDealerName(dealerCode) {
    if (!dealerCode)
        return "Nex-Gen LED";
    try {
        const doc = await admin
            .firestore()
            .collection("dealers")
            .doc(dealerCode)
            .get();
        if (!doc.exists)
            return dealerCode;
        const data = doc.data() ?? {};
        const businessName = data.businessName;
        return businessName && businessName.trim().length > 0
            ? businessName
            : dealerCode;
    }
    catch (err) {
        firebase_functions_1.logger.warn(`onSalesJobStatusChanged: dealer lookup failed for ${dealerCode}: ${err.message}`);
        return dealerCode;
    }
}
/**
 * Best-effort tech name resolution. SalesJob.day1TechUid is currently a
 * 4-digit installer PIN per the codebase TODOs in
 * sales_job_service.dart, not a Firebase Auth UID. If the value is a
 * short numeric string we know it's a PIN and fall back to the generic
 * "our technician".
 */
function resolveTechName(uid) {
    if (!uid || uid.trim().length === 0)
        return "our technician";
    // Short numeric strings are PINs, not real names — fall back.
    if (/^\d{1,8}$/.test(uid))
        return "our technician";
    return uid;
}
/**
 * Try to send an SMS to the prospect. Logs and swallows on:
 *   • missing phone
 *   • phone failing E.164 normalization
 *   • Twilio API error
 *
 * Returns true if a send was attempted, false if skipped due to
 * missing/invalid phone. Errors are caught internally — never thrown.
 */
async function trySendSms(prospect, body, context) {
    if (!prospect.phone) {
        firebase_functions_1.logger.warn(`onSalesJobStatusChanged: ${context} — prospect has no phone, skipping SMS`);
        return;
    }
    const e164 = (0, messaging_helpers_1.formatPhone)(prospect.phone);
    if (!e164) {
        firebase_functions_1.logger.warn(`onSalesJobStatusChanged: ${context} — could not format phone "${prospect.phone}" to E.164, skipping SMS`);
        return;
    }
    try {
        await (0, messaging_helpers_1.sendSms)(e164, body);
    }
    catch (err) {
        firebase_functions_1.logger.error(`onSalesJobStatusChanged: ${context} — SMS send failed: ${err.message}`);
        // Swallow — never throw out of the trigger.
    }
}
/**
 * Same shape as trySendSms but for email. Logs and swallows on missing
 * email address or Resend API error.
 */
async function trySendEmail(prospect, subject, htmlBody, textBody, context) {
    if (!prospect.email) {
        firebase_functions_1.logger.warn(`onSalesJobStatusChanged: ${context} — prospect has no email, skipping email`);
        return;
    }
    try {
        await (0, messaging_helpers_1.sendEmail)({
            to: prospect.email,
            subject,
            htmlBody,
            textBody,
        });
    }
    catch (err) {
        firebase_functions_1.logger.error(`onSalesJobStatusChanged: ${context} — email send failed: ${err.message}`);
        // Swallow — never throw out of the trigger.
    }
}
// ── Email body builders ─────────────────────────────────────────────────────
//
// Two long-form emails sent by this trigger: estimateSigned (welcome /
// onboarding) and installComplete (download + activate). HTML versions
// are simple inline-styled blocks. Plain-text versions mirror the HTML
// for clients that don't render HTML and for the deliverability score.
function buildEstimateSignedEmail(prospect, dealerName) {
    const firstName = prospect.firstName || "there";
    const subject = "You're booked with Nex-Gen LED! 🎉";
    const text = [
        `Hi ${firstName},`,
        "",
        "Your permanent LED lighting system is confirmed. Here's what happens next:",
        "",
        "Step 1 — Day 1: Our electrician visits to run all wiring. No lights go up on this day.",
        "",
        "Step 2 — Day 2: Our install team arrives and your lights go up.",
        "",
        "We'll send you a text reminder the night before each visit.",
        "",
        "Before we arrive, please make sure we'll have access to:",
        "  • your electrical panel",
        "  • your garage or utility area",
        "  • the exterior eaves of your home",
        "",
        `Questions or scheduling changes? Reach out to ${dealerName} anytime.`,
        "",
        "Welcome to the Nex-Gen LED family!",
    ].join("\n");
    const html = `
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background:#f6f9fc; margin:0; padding:24px; color:#1a1a1a;">
  <div style="max-width:560px; margin:0 auto; background:#ffffff; border-radius:12px; padding:32px; box-shadow:0 1px 3px rgba(0,0,0,0.06);">
    <h1 style="color:#00B7C2; font-size:24px; margin:0 0 16px 0;">You're booked! 🎉</h1>
    <p style="font-size:16px; line-height:1.5;">Hi ${firstName},</p>
    <p style="font-size:16px; line-height:1.5;">Your permanent LED lighting system is confirmed. Here's what happens next:</p>

    <div style="background:#f6f9fc; border-radius:8px; padding:16px; margin:20px 0;">
      <h3 style="margin:0 0 8px 0; color:#00B7C2; font-size:14px; letter-spacing:0.6px;">STEP 1 — DAY 1</h3>
      <p style="margin:0; font-size:14px; line-height:1.5;">Our electrician visits to run all wiring. <strong>No lights go up on this day.</strong></p>
    </div>

    <div style="background:#f6f9fc; border-radius:8px; padding:16px; margin:20px 0;">
      <h3 style="margin:0 0 8px 0; color:#00B7C2; font-size:14px; letter-spacing:0.6px;">STEP 2 — DAY 2</h3>
      <p style="margin:0; font-size:14px; line-height:1.5;">Our install team arrives and your lights go up.</p>
    </div>

    <p style="font-size:14px; line-height:1.5; color:#555;">We'll send you a text reminder the night before each visit.</p>

    <h3 style="font-size:14px; color:#1a1a1a; margin:24px 0 8px 0;">Before we arrive, please make sure we'll have access to:</h3>
    <ul style="font-size:14px; line-height:1.6; color:#555; padding-left:20px;">
      <li>your electrical panel</li>
      <li>your garage or utility area</li>
      <li>the exterior eaves of your home</li>
    </ul>

    <p style="font-size:14px; line-height:1.5; color:#555; margin-top:24px;">
      Questions or scheduling changes? Reach out to <strong>${dealerName}</strong> anytime.
    </p>

    <p style="font-size:16px; line-height:1.5; margin-top:24px;">
      Welcome to the Nex-Gen LED family!
    </p>
  </div>
</body>
</html>
  `.trim();
    return { subject, html, text };
}
function buildInstallCompleteEmail(prospect, dealerName) {
    const firstName = prospect.firstName || "there";
    const subject = "Your Nex-Gen LED system is live! 💡";
    const text = [
        `Hi ${firstName},`,
        "",
        "Your permanent LED lighting system is installed and ready.",
        "",
        "Download Lumina to control your lights:",
        `  • iPhone: ${APP_STORE_URL}`,
        `  • Android: ${PLAY_STORE_URL}`,
        "",
        `Your login was sent to ${prospect.email}. Check your inbox for your account setup email.`,
        "",
        "Welcome to the Nex-Gen LED family — we can't wait to see your home lit up.",
        "",
        `Questions? ${dealerName} is here for you.`,
    ].join("\n");
    const html = `
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background:#f6f9fc; margin:0; padding:24px; color:#1a1a1a;">
  <div style="max-width:560px; margin:0 auto; background:#ffffff; border-radius:12px; padding:32px; box-shadow:0 1px 3px rgba(0,0,0,0.06);">
    <h1 style="color:#00B7C2; font-size:24px; margin:0 0 16px 0;">Your system is live! 💡</h1>
    <p style="font-size:16px; line-height:1.5;">Hi ${firstName},</p>
    <p style="font-size:16px; line-height:1.5;">Your permanent LED lighting system is installed and ready.</p>

    <h3 style="font-size:14px; color:#1a1a1a; margin:24px 0 12px 0;">Download Lumina to control your lights</h3>
    <div style="margin:8px 0;">
      <a href="${APP_STORE_URL}" style="display:inline-block; background:#00B7C2; color:#ffffff; text-decoration:none; padding:12px 18px; border-radius:8px; font-size:14px; font-weight:600; margin-right:8px;">Download for iPhone</a>
      <a href="${PLAY_STORE_URL}" style="display:inline-block; background:#00B7C2; color:#ffffff; text-decoration:none; padding:12px 18px; border-radius:8px; font-size:14px; font-weight:600;">Download for Android</a>
    </div>

    <p style="font-size:14px; line-height:1.5; color:#555; margin-top:24px;">
      Your login was sent to <strong>${prospect.email}</strong>. Check your inbox for your account setup email.
    </p>

    <p style="font-size:16px; line-height:1.5; margin-top:24px;">
      Welcome to the Nex-Gen LED family — we can't wait to see your home lit up.
    </p>

    <p style="font-size:14px; line-height:1.5; color:#555;">
      Questions? <strong>${dealerName}</strong> is here for you.
    </p>
  </div>
</body>
</html>
  `.trim();
    return { subject, html, text };
}
// ── Cloud Function ──────────────────────────────────────────────────────────
exports.onSalesJobStatusChanged = (0, firestore_1.onDocumentUpdated)({
    document: "sales_jobs/{jobId}",
    region: "us-central1",
}, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) {
        firebase_functions_1.logger.warn("onSalesJobStatusChanged: missing before/after snapshot, ignoring");
        return;
    }
    const jobId = event.params.jobId;
    const beforeStatus = before.status;
    const afterStatus = after.status;
    const prospect = readProspect(after);
    const firstName = prospect.firstName || "there";
    // ── Load dealer messaging config (toggles + sign-off) ─────────────────
    //
    // Load once up front since both the day1-completed branch and the
    // status-transition branch need it. loadDealerMessagingConfig
    // returns defaults on missing/invalid configs and never throws.
    const dealerCode = after.dealerCode ?? "";
    const config = await (0, messaging_helpers_1.loadDealerMessagingConfig)(dealerCode);
    const signOff = (0, messaging_helpers_1.resolveSignOff)(config);
    // ── Day 1 completion detection (independent of status change) ─────────
    //
    // markDay1Complete in sales_job_service.dart writes BOTH status:
    // prewireComplete AND day1CompletedAt: now in the same atomic update.
    // We detect day1CompletedAt becoming non-null specifically rather
    // than the prewireComplete status, because the spec wants this
    // message tied to the completion event, not the queue transition.
    //
    // Not toggle-controlled — the spec only puts toggles on the two
    // emails and the two day-before reminders. This SMS always sends.
    const day1CompletedBefore = before.day1CompletedAt;
    const day1CompletedAfter = after.day1CompletedAt;
    const day1JustCompleted = day1CompletedBefore == null && day1CompletedAfter != null;
    if (day1JustCompleted) {
        const body = `Great news, ${firstName}! Wiring prep is complete at your home. ` +
            "Your light installation day is coming soon — we'll text you the " +
            `night before. — ${signOff}`;
        await trySendSms(prospect, body, `job ${jobId} day1 completed`);
    }
    // ── Status transitions ───────────────────────────────────────────────
    //
    // Status hasn't changed and there was no day1 completion event →
    // nothing to do. Return early.
    if (beforeStatus === afterStatus) {
        return;
    }
    firebase_functions_1.logger.info(`onSalesJobStatusChanged: job ${jobId} ${beforeStatus} → ${afterStatus}`);
    switch (afterStatus) {
        case STATUS_ESTIMATE_SIGNED: {
            // Email — welcome / onboarding. Toggle-controlled.
            if (!config.sendEstimateSignedEmail) {
                firebase_functions_1.logger.info(`onSalesJobStatusChanged: job ${jobId} estimateSigned email skipped — dealer ${dealerCode} has sendEstimateSignedEmail=false`);
                break;
            }
            const dealerName = await lookupDealerName(dealerCode);
            const { subject, html, text } = buildEstimateSignedEmail(prospect, dealerName);
            await trySendEmail(prospect, subject, html, text, `job ${jobId} estimateSigned`);
            break;
        }
        case STATUS_PREWIRE_SCHEDULED: {
            // SMS — day 1 scheduling confirmation. Always sends.
            const day1 = readableDate(after.day1Date);
            const techName = resolveTechName(after.day1TechUid);
            const body = `Hi ${firstName}, your Nex-Gen LED prep day is confirmed for ` +
                `${day1}. ${techName} will handle the wiring — no lights go up ` +
                `this day, that's Day 2. Questions? Reply here. — ${signOff}`;
            await trySendSms(prospect, body, `job ${jobId} prewireScheduled`);
            break;
        }
        case STATUS_INSTALL_SCHEDULED: {
            // SMS — day 2 scheduling confirmation. Always sends.
            const day2 = readableDate(after.day2Date);
            const body = `Hi ${firstName}, your Nex-Gen LED light installation is ` +
                `confirmed for ${day2}. Our install team will have your lights ` +
                `up and running. Get excited! — ${signOff}`;
            await trySendSms(prospect, body, `job ${jobId} installScheduled`);
            break;
        }
        case STATUS_INSTALL_COMPLETE: {
            // Email — system is live + download Lumina. Toggle-controlled.
            if (!config.sendInstallCompleteEmail) {
                firebase_functions_1.logger.info(`onSalesJobStatusChanged: job ${jobId} installComplete email skipped — dealer ${dealerCode} has sendInstallCompleteEmail=false`);
                break;
            }
            const dealerName = await lookupDealerName(dealerCode);
            const { subject, html, text } = buildInstallCompleteEmail(prospect, dealerName);
            await trySendEmail(prospect, subject, html, text, `job ${jobId} installComplete`);
            break;
        }
        default:
            // No customer-facing message for other transitions.
            break;
    }
});
//# sourceMappingURL=onSalesJobStatusChanged.js.map