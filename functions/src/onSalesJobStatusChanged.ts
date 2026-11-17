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
 * 2026-11-17: every message is sent at most once per job (a claimed
 * `messagingSent.<key>` marker, see claimSend), and the three
 * status-update SMS honour the dealer's `sendStatusSms` toggle.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:onSalesJobStatusChanged
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

import {
  sendSms,
  sendEmail,
  formatPhone,
  loadDealerMessagingConfig,
  resolveSignOff,
  DealerMessagingConfig,
} from "./messaging-helpers";

// admin.initializeApp() is called in index.js — do not call again here.

// ── App store placeholders ──────────────────────────────────────────────────
// TODO: replace with real store URLs once the apps are listed.
const APP_STORE_URL =
  "https://apps.apple.com/app/lumina/id[PLACEHOLDER_APP_ID]";
const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=[PLACEHOLDER_PACKAGE_ID]";

// ── Status enum mirror (matches lib/features/sales/models/sales_models.dart) ─
const STATUS_ESTIMATE_SIGNED = "estimateSigned";
const STATUS_PREWIRE_SCHEDULED = "prewireScheduled";
const STATUS_INSTALL_SCHEDULED = "installScheduled";
const STATUS_INSTALL_COMPLETE = "installComplete";

// ── Helpers ─────────────────────────────────────────────────────────────────

interface ProspectInfo {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
}

function readProspect(jobData: admin.firestore.DocumentData): ProspectInfo {
  const p = (jobData.prospect ?? {}) as Record<string, unknown>;
  return {
    firstName: ((p.firstName as string) ?? "").trim(),
    lastName: ((p.lastName as string) ?? "").trim(),
    email: ((p.email as string) ?? "").trim(),
    phone: ((p.phone as string) ?? "").trim(),
  };
}

function readableDate(ts: unknown): string {
  if (!ts) return "TBD";
  try {
    const date = (ts as admin.firestore.Timestamp).toDate();
    return date.toLocaleDateString("en-US", {
      weekday: "long",
      month: "long",
      day: "numeric",
    });
  } catch {
    return "TBD";
  }
}

/**
 * Look up a friendly dealer display name from /dealers/{dealerCode}.
 * Falls back to the dealer code if the doc doesn't exist or has no
 * businessName field.
 */
async function lookupDealerName(dealerCode: string): Promise<string> {
  if (!dealerCode) return "Nex-Gen LED";
  try {
    const doc = await admin
      .firestore()
      .collection("dealers")
      .doc(dealerCode)
      .get();
    if (!doc.exists) return dealerCode;
    const data = doc.data() ?? {};
    const businessName = data.businessName as string | undefined;
    return businessName && businessName.trim().length > 0
      ? businessName
      : dealerCode;
  } catch (err) {
    logger.warn(
      `onSalesJobStatusChanged: dealer lookup failed for ${dealerCode}: ${(err as Error).message}`,
    );
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
function resolveTechName(uid: string | undefined | null): string {
  if (!uid || uid.trim().length === 0) return "our technician";
  // Short numeric strings are PINs, not real names — fall back.
  if (/^\d{1,8}$/.test(uid)) return "our technician";
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
async function trySendSms(
  prospect: ProspectInfo,
  body: string,
  context: string,
): Promise<void> {
  if (!prospect.phone) {
    logger.warn(
      `onSalesJobStatusChanged: ${context} — prospect has no phone, skipping SMS`,
    );
    return;
  }
  const e164 = formatPhone(prospect.phone);
  if (!e164) {
    logger.warn(
      `onSalesJobStatusChanged: ${context} — could not format phone "${prospect.phone}" to E.164, skipping SMS`,
    );
    return;
  }
  try {
    await sendSms(e164, body);
  } catch (err) {
    logger.error(
      `onSalesJobStatusChanged: ${context} — SMS send failed: ${(err as Error).message}`,
    );
    // Swallow — never throw out of the trigger.
  }
}

/**
 * Same shape as trySendSms but for email. Logs and swallows on missing
 * email address or Resend API error.
 */
async function trySendEmail(
  prospect: ProspectInfo,
  subject: string,
  htmlBody: string,
  textBody: string,
  context: string,
): Promise<void> {
  if (!prospect.email) {
    logger.warn(
      `onSalesJobStatusChanged: ${context} — prospect has no email, skipping email`,
    );
    return;
  }
  try {
    await sendEmail({
      to: prospect.email,
      subject,
      htmlBody,
      textBody,
    });
  } catch (err) {
    logger.error(
      `onSalesJobStatusChanged: ${context} — email send failed: ${(err as Error).message}`,
    );
    // Swallow — never throw out of the trigger.
  }
}

// ── Email body builders ─────────────────────────────────────────────────────
//
// Two long-form emails sent by this trigger: estimateSigned (welcome /
// onboarding) and installComplete (download + activate). HTML versions
// are simple inline-styled blocks. Plain-text versions mirror the HTML
// for clients that don't render HTML and for the deliverability score.

function buildEstimateSignedEmail(
  prospect: ProspectInfo,
  dealerName: string,
): { subject: string; html: string; text: string } {
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

function buildInstallCompleteEmail(
  prospect: ProspectInfo,
  dealerName: string,
): { subject: string; html: string; text: string } {
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

// ── Sent markers (2026-11-17) ───────────────────────────────────────────────
//
// Each customer message is sent AT MOST ONCE per job. Before this, a status
// that bounced A→B→A→B re-sent B's message, and Firestore's at-least-once
// trigger delivery could double-send on a retry.
//
// The marker lives on the job at `messagingSent.<key>` (a server timestamp)
// and is CLAIMED in a transaction BEFORE the send, so a retry or a concurrent
// invocation finds it and stops. If the claim itself fails, the message is
// skipped (fail closed: a missed message beats a duplicate). The marker write
// re-fires this trigger, which returns early because neither status nor
// day1CompletedAt changed. A message whose dealer toggle is off is not
// marked, so turning the toggle back on lets a LATER transition send.
//
// Clients write the job with set(merge:true) of SalesJob.toJson(), which
// has no messagingSent key, so client saves never clear a marker.

export type MessageKey =
  | "day1CompletedSms"
  | "estimateSignedEmail"
  | "prewireScheduledSms"
  | "installScheduledSms"
  | "installCompleteEmail";

async function claimSend(jobId: string, key: MessageKey): Promise<boolean> {
  const db = admin.firestore();
  const ref = db.collection("sales_jobs").doc(jobId);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      if (snap.get(new admin.firestore.FieldPath("messagingSent", key)) != null) {
        logger.info(
          `onSalesJobStatusChanged: job ${jobId} ${key} already sent — skipping`,
        );
        return false;
      }
      tx.update(
        ref,
        new admin.firestore.FieldPath("messagingSent", key),
        admin.firestore.FieldValue.serverTimestamp(),
      );
      return true;
    });
  } catch (err) {
    logger.error(
      `onSalesJobStatusChanged: job ${jobId} could not claim ${key} — not sending: ${(err as Error).message}`,
    );
    return false;
  }
}

// ── Handler (exported for the emulator suite) ───────────────────────────────

export async function processSalesJobUpdate(
  jobId: string,
  before: admin.firestore.DocumentData,
  after: admin.firestore.DocumentData,
): Promise<void> {
    const beforeStatus = before.status as string | undefined;
    const afterStatus = after.status as string | undefined;

    // ── Day 1 completion detection (independent of status change) ─────────
    //
    // markDay1Complete in sales_job_service.dart writes BOTH status:
    // prewireComplete AND day1CompletedAt: now in the same atomic update.
    // We detect day1CompletedAt becoming non-null specifically rather
    // than the prewireComplete status, because the spec wants this
    // message tied to the completion event, not the queue transition.
    const day1CompletedBefore = before.day1CompletedAt;
    const day1CompletedAfter = after.day1CompletedAt;
    const day1JustCompleted =
      day1CompletedBefore == null && day1CompletedAfter != null;

    // Nothing this trigger reacts to changed (this includes our own
    // messagingSent marker writes) → return before any read.
    if (!day1JustCompleted && beforeStatus === afterStatus) {
      return;
    }

    const prospect = readProspect(after);
    const firstName = prospect.firstName || "there";

    // ── Load dealer messaging config (toggles + sign-off) ─────────────────
    //
    // loadDealerMessagingConfig returns defaults on missing/invalid
    // configs and never throws.
    const dealerCode = (after.dealerCode as string) ?? "";
    const config: DealerMessagingConfig =
      await loadDealerMessagingConfig(dealerCode);
    const signOff = resolveSignOff(config);

    // SMS toggle (sendStatusSms) covers the three status-update SMS. The
    // two emails keep their own toggles; the day-before reminders live in
    // sendInstallReminders.
    const smsSkipped = (what: string) =>
      logger.info(
        `onSalesJobStatusChanged: job ${jobId} ${what} SMS skipped — dealer ${dealerCode} has sendStatusSms=false`,
      );

    if (day1JustCompleted) {
      if (!config.sendStatusSms) {
        smsSkipped("day1 completed");
      } else if (await claimSend(jobId, "day1CompletedSms")) {
        const body =
          `Great news, ${firstName}! Wiring prep is complete at your home. ` +
          "Your light installation day is coming soon — we'll text you the " +
          `night before. — ${signOff}`;
        await trySendSms(
          prospect,
          body,
          `job ${jobId} day1 completed`,
        );
      }
    }

    // ── Status transitions ───────────────────────────────────────────────

    if (beforeStatus === afterStatus) {
      return;
    }

    logger.info(
      `onSalesJobStatusChanged: job ${jobId} ${beforeStatus} → ${afterStatus}`,
    );

    switch (afterStatus) {
      case STATUS_ESTIMATE_SIGNED: {
        // Email — welcome / onboarding. Toggle-controlled.
        if (!config.sendEstimateSignedEmail) {
          logger.info(
            `onSalesJobStatusChanged: job ${jobId} estimateSigned email skipped — dealer ${dealerCode} has sendEstimateSignedEmail=false`,
          );
          break;
        }
        if (!(await claimSend(jobId, "estimateSignedEmail"))) break;
        const dealerName = await lookupDealerName(dealerCode);
        const { subject, html, text } = buildEstimateSignedEmail(
          prospect,
          dealerName,
        );
        await trySendEmail(
          prospect,
          subject,
          html,
          text,
          `job ${jobId} estimateSigned`,
        );
        break;
      }

      case STATUS_PREWIRE_SCHEDULED: {
        // SMS — day 1 scheduling confirmation. sendStatusSms-controlled.
        if (!config.sendStatusSms) {
          smsSkipped("prewireScheduled");
          break;
        }
        if (!(await claimSend(jobId, "prewireScheduledSms"))) break;
        const day1 = readableDate(after.day1Date);
        const techName = resolveTechName(after.day1TechUid as string | null);
        const body =
          `Hi ${firstName}, your Nex-Gen LED prep day is confirmed for ` +
          `${day1}. ${techName} will handle the wiring — no lights go up ` +
          `this day, that's Day 2. Questions? Reply here. — ${signOff}`;
        await trySendSms(
          prospect,
          body,
          `job ${jobId} prewireScheduled`,
        );
        break;
      }

      case STATUS_INSTALL_SCHEDULED: {
        // SMS — day 2 scheduling confirmation. sendStatusSms-controlled.
        if (!config.sendStatusSms) {
          smsSkipped("installScheduled");
          break;
        }
        if (!(await claimSend(jobId, "installScheduledSms"))) break;
        const day2 = readableDate(after.day2Date);
        const body =
          `Hi ${firstName}, your Nex-Gen LED light installation is ` +
          `confirmed for ${day2}. Our install team will have your lights ` +
          `up and running. Get excited! — ${signOff}`;
        await trySendSms(
          prospect,
          body,
          `job ${jobId} installScheduled`,
        );
        break;
      }

      case STATUS_INSTALL_COMPLETE: {
        // Email — system is live + download Lumina. Toggle-controlled.
        if (!config.sendInstallCompleteEmail) {
          logger.info(
            `onSalesJobStatusChanged: job ${jobId} installComplete email skipped — dealer ${dealerCode} has sendInstallCompleteEmail=false`,
          );
          break;
        }
        if (!(await claimSend(jobId, "installCompleteEmail"))) break;
        const dealerName = await lookupDealerName(dealerCode);
        const { subject, html, text } = buildInstallCompleteEmail(
          prospect,
          dealerName,
        );
        await trySendEmail(
          prospect,
          subject,
          html,
          text,
          `job ${jobId} installComplete`,
        );
        break;
      }

      default:
        // No customer-facing message for other transitions.
        break;
    }
}

// ── Cloud Function ──────────────────────────────────────────────────────────

export const onSalesJobStatusChanged = onDocumentUpdated(
  {
    document: "sales_jobs/{jobId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) {
      logger.warn(
        "onSalesJobStatusChanged: missing before/after snapshot, ignoring",
      );
      return;
    }
    await processSalesJobUpdate(event.params.jobId, before, after);
  },
);
