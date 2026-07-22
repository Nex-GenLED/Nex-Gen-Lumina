/**
 * messaging-helpers — Shared SMS + email helpers for the Nex-Gen LED
 * customer messaging pipeline.
 *
 * NOT a Cloud Function. Pure support module imported by:
 *   - onSalesJobStatusChanged.ts
 *   - createCustomerAccount.ts
 *
 * Reads credentials via the same defineString() params declared in
 * functions/index.js. Calling defineString() with the same key in two
 * places does NOT double-register — both calls resolve to the same
 * runtime parameter.
 *
 * No exported Cloud Function here, so this file is NOT wired into
 * index.js with a require/exports pair.
 */

import { defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { Twilio } from "twilio";
import { Resend } from "resend";

// admin.initializeApp() is called in index.js — do not call again here.

// ── Param declarations ──────────────────────────────────────────────────────
//
// Same names as the defineString block in index.js — duplicate calls are
// safe and resolve to the same parameter instance.

const twilioAccountSid = defineString("TWILIO_ACCOUNT_SID");
const twilioAuthToken = defineString("TWILIO_AUTH_TOKEN");
const twilioFromNumber = defineString("TWILIO_FROM_NUMBER");

const resendApiKey = defineString("RESEND_API_KEY");
const resendFromEmail = defineString("RESEND_FROM_EMAIL");
const resendFromName = defineString("RESEND_FROM_NAME");

// ── E.164 validation ────────────────────────────────────────────────────────

/**
 * Loose E.164 check: starts with `+`, then 7–15 digits. Twilio rejects
 * anything outside this range, so we fail fast before the network call.
 */
const E164_RE = /^\+[1-9]\d{6,14}$/;

// ── sendSms ─────────────────────────────────────────────────────────────────

/**
 * Send a single SMS via Twilio. Throws on validation failure or on a
 * Twilio API error — callers in the messaging pipeline are expected to
 * catch and log so a failed message never fails its parent trigger.
 */
export async function sendSms(to: string, body: string): Promise<void> {
  if (!to || to.trim().length === 0) {
    throw new Error("sendSms: 'to' is required");
  }
  if (!E164_RE.test(to)) {
    throw new Error(
      `sendSms: 'to' must be E.164 format (e.g. +18165551234), got: ${to}`,
    );
  }
  if (!body || body.trim().length === 0) {
    throw new Error("sendSms: 'body' is required");
  }

  const sid = twilioAccountSid.value();
  const token = twilioAuthToken.value();
  const from = twilioFromNumber.value();

  if (!sid || !token || !from) {
    throw new Error(
      "sendSms: Twilio credentials not configured " +
        "(check TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM_NUMBER in .env)",
    );
  }

  const client = new Twilio(sid, token);

  try {
    const message = await client.messages.create({
      to,
      from,
      body,
    });
    logger.info(
      `sendSms: ok (sid=${message.sid}, to=${to}, len=${body.length})`,
    );
  } catch (err) {
    logger.error(`sendSms: failed (to=${to}): ${(err as Error).message}`);
    throw err;
  }
}

// ── sendEmail ───────────────────────────────────────────────────────────────

export interface SendEmailParams {
  to: string;
  subject: string;
  htmlBody: string;
  textBody: string;
}

/**
 * Send a transactional email via Resend. Throws on validation failure
 * or on a Resend API error — callers are expected to catch and log so
 * a failed message never fails its parent trigger.
 */
export async function sendEmail(params: SendEmailParams): Promise<void> {
  const { to, subject, htmlBody, textBody } = params;

  if (!to || to.trim().length === 0) {
    throw new Error("sendEmail: 'to' is required");
  }
  if (!subject || subject.trim().length === 0) {
    throw new Error("sendEmail: 'subject' is required");
  }
  if (!htmlBody || htmlBody.trim().length === 0) {
    throw new Error("sendEmail: 'htmlBody' is required");
  }
  if (!textBody || textBody.trim().length === 0) {
    throw new Error("sendEmail: 'textBody' is required");
  }

  const apiKey = resendApiKey.value();
  const fromEmail = resendFromEmail.value();
  const fromName = resendFromName.value();

  if (!apiKey || !fromEmail || !fromName) {
    throw new Error(
      "sendEmail: Resend credentials not configured " +
        "(check RESEND_API_KEY / RESEND_FROM_EMAIL / RESEND_FROM_NAME in .env)",
    );
  }

  const resend = new Resend(apiKey);
  const from = `${fromName} <${fromEmail}>`;

  try {
    const result = await resend.emails.send({
      from,
      to: [to],
      subject,
      html: htmlBody,
      text: textBody,
    });

    if (result.error) {
      logger.error(
        `sendEmail: Resend returned error (to=${to}): ${result.error.message}`,
      );
      throw new Error(`Resend error: ${result.error.message}`);
    }

    logger.info(
      `sendEmail: ok (id=${result.data?.id ?? "unknown"}, to=${to})`,
    );
  } catch (err) {
    logger.error(`sendEmail: failed (to=${to}): ${(err as Error).message}`);
    throw err;
  }
}

// ── loadDealerMessagingConfig ───────────────────────────────────────────────

/**
 * Subset of the dealer's messaging config that the Cloud Functions
 * actually need at message-send time. Mirrors a subset of the Flutter
 * `DealerMessagingConfig` model in
 * `lib/features/sales/models/dealer_messaging_config.dart` —
 * intentionally not the full model because the functions don't need
 * `replyPhone`, `supportEmail`, `smsOptInDefault`, or `updatedAt`.
 *
 * If the underlying Firestore document doesn't exist (or fails to
 * read), defaults are returned with all toggles enabled and
 * `senderName: 'Nex-Gen LED'`. The functions never error out on a
 * missing config — that would silently disable messaging for any
 * freshly-provisioned dealer that hasn't visited the config screen
 * yet, which would be a worse failure mode than just sending with
 * defaults.
 */
export interface DealerMessagingConfig {
  senderName: string;
  customSmsSignOff: string | null;
  sendDay1Reminder: boolean;
  sendDay2Reminder: boolean;
  sendEstimateSignedEmail: boolean;
  sendInstallCompleteEmail: boolean;
}

/** Defaults applied when the dealer has no config doc. */
const DEFAULT_DEALER_CONFIG: DealerMessagingConfig = {
  senderName: "Nex-Gen LED",
  customSmsSignOff: null,
  sendDay1Reminder: true,
  sendDay2Reminder: true,
  sendEstimateSignedEmail: true,
  sendInstallCompleteEmail: true,
};

/**
 * Load the dealer's messaging config from
 * `dealers/{dealerCode}/config/messaging`. Returns defaults on any
 * read failure or when the document doesn't exist. Logs warnings —
 * never throws.
 */
export async function loadDealerMessagingConfig(
  dealerCode: string,
): Promise<DealerMessagingConfig> {
  if (!dealerCode || dealerCode.trim().length === 0) {
    logger.warn(
      "loadDealerMessagingConfig: empty dealerCode, returning defaults",
    );
    return DEFAULT_DEALER_CONFIG;
  }

  try {
    const snap = await admin
      .firestore()
      .collection("dealers")
      .doc(dealerCode)
      .collection("config")
      .doc("messaging")
      .get();

    if (!snap.exists) {
      return DEFAULT_DEALER_CONFIG;
    }

    const data = snap.data();
    if (!data) {
      return DEFAULT_DEALER_CONFIG;
    }

    // Field names match the Flutter model's toJson/fromJson camelCase
    // convention. Each field falls back to the default if missing or
    // wrong type — bad config never blocks messaging.
    const customSmsSignOffRaw = data.customSmsSignOff as string | undefined;
    const customSmsSignOff =
      customSmsSignOffRaw != null && customSmsSignOffRaw.trim().length > 0
        ? customSmsSignOffRaw.trim()
        : null;

    return {
      senderName:
        (data.senderName as string | undefined)?.trim() ||
        DEFAULT_DEALER_CONFIG.senderName,
      customSmsSignOff,
      sendDay1Reminder:
        (data.sendDay1Reminder as boolean | undefined) ??
        DEFAULT_DEALER_CONFIG.sendDay1Reminder,
      sendDay2Reminder:
        (data.sendDay2Reminder as boolean | undefined) ??
        DEFAULT_DEALER_CONFIG.sendDay2Reminder,
      sendEstimateSignedEmail:
        (data.sendEstimateSignedEmail as boolean | undefined) ??
        DEFAULT_DEALER_CONFIG.sendEstimateSignedEmail,
      sendInstallCompleteEmail:
        (data.sendInstallCompleteEmail as boolean | undefined) ??
        DEFAULT_DEALER_CONFIG.sendInstallCompleteEmail,
    };
  } catch (err) {
    logger.warn(
      `loadDealerMessagingConfig: read failed for ${dealerCode} (${(err as Error).message}), returning defaults`,
    );
    return DEFAULT_DEALER_CONFIG;
  }
}

/**
 * Resolve the SMS sign-off the same way the Flutter model's
 * `effectiveSmsSignOff` getter does — `customSmsSignOff` when set and
 * non-empty, otherwise `senderName`.
 */
export function resolveSignOff(config: DealerMessagingConfig): string {
  if (config.customSmsSignOff && config.customSmsSignOff.trim().length > 0) {
    return config.customSmsSignOff.trim();
  }
  return config.senderName;
}

// ── formatPhone ─────────────────────────────────────────────────────────────

/**
 * Sanitize a US phone number into E.164 format. Strips all non-digit
 * characters, prepends the `+1` country code if not already present,
 * and returns null if the resulting number isn't 11 digits total.
 *
 * Examples:
 *   "(816) 555-1234"     → "+18165551234"
 *   "816.555.1234"       → "+18165551234"
 *   "1-816-555-1234"     → "+18165551234"
 *   "+18165551234"       → "+18165551234"
 *   "555-1234"           → null  (only 7 digits)
 *   "+44 20 7946 0958"   → null  (UK number, not 11 digits with country)
 *   ""                   → null
 */
export function formatPhone(phone: string): string | null {
  if (!phone) return null;

  // Strip everything that isn't a digit.
  const digits = phone.replace(/\D/g, "");

  // Already includes country code → must be exactly 11 digits starting with 1
  // (US/Canada). Numbers from other countries return null.
  if (digits.length === 11) {
    if (!digits.startsWith("1")) return null;
    return `+${digits}`;
  }

  // 10-digit number → prepend US country code.
  if (digits.length === 10) {
    return `+1${digits}`;
  }

  return null;
}
