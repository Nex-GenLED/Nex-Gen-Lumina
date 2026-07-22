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
/**
 * Send a single SMS via Twilio. Throws on validation failure or on a
 * Twilio API error — callers in the messaging pipeline are expected to
 * catch and log so a failed message never fails its parent trigger.
 */
export declare function sendSms(to: string, body: string): Promise<void>;
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
export declare function sendEmail(params: SendEmailParams): Promise<void>;
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
/**
 * Load the dealer's messaging config from
 * `dealers/{dealerCode}/config/messaging`. Returns defaults on any
 * read failure or when the document doesn't exist. Logs warnings —
 * never throws.
 */
export declare function loadDealerMessagingConfig(dealerCode: string): Promise<DealerMessagingConfig>;
/**
 * Resolve the SMS sign-off the same way the Flutter model's
 * `effectiveSmsSignOff` getter does — `customSmsSignOff` when set and
 * non-empty, otherwise `senderName`.
 */
export declare function resolveSignOff(config: DealerMessagingConfig): string;
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
export declare function formatPhone(phone: string): string | null;
