/**
 * sendInstallReminders — Scheduled Firebase Cloud Function
 *
 * Fires daily at 18:00 America/Chicago (6pm Central). Catches customers
 * before evening to send them a reminder for the next day's Day 1
 * pre-wire visit or Day 2 install visit.
 *
 * Two passes per run:
 *   • Pass 1 — Day 1 reminders for sales_jobs where status ==
 *     'prewireScheduled' and day1Date falls within the next Central
 *     calendar day.
 *   • Pass 2 — Day 2 reminders for sales_jobs where status ==
 *     'installScheduled' and day2Date falls within the next Central
 *     calendar day.
 *
 * Per-job errors NEVER stop the loop. A bad phone number, a Twilio
 * outage, or a Firestore read failure for one job is logged with the
 * job id and the loop continues.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:sendInstallReminders
 *
 * Required Firestore composite indexes (NOT auto-created):
 *   • sales_jobs: status ASC + day1Date ASC
 *   • sales_jobs: status ASC + day2Date ASC
 * Add to firestore.indexes.json before first deploy or the first run
 * will fail with FAILED_PRECONDITION.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

import {
  sendSms,
  formatPhone,
  loadDealerMessagingConfig,
  resolveSignOff,
} from "./messaging-helpers";

// admin.initializeApp() is called in index.js — do not call again here.

// ── Status enum mirror (matches lib/features/sales/models/sales_models.dart) ─
const STATUS_PREWIRE_SCHEDULED = "prewireScheduled";
const STATUS_INSTALL_SCHEDULED = "installScheduled";

// ── Helpers ─────────────────────────────────────────────────────────────────

interface ProspectInfo {
  firstName: string;
  phone: string;
}

function readProspect(jobData: admin.firestore.DocumentData): ProspectInfo {
  const p = (jobData.prospect ?? {}) as Record<string, unknown>;
  return {
    firstName: ((p.firstName as string) ?? "").trim(),
    phone: ((p.phone as string) ?? "").trim(),
  };
}

/**
 * Best-effort tech name resolution. SalesJob.day1TechUid is currently a
 * 4-digit installer PIN per the codebase TODOs in
 * sales_job_service.dart, not a Firebase Auth UID. Short numeric
 * strings are PINs → fall back to the generic "our technician".
 *
 * Mirrors the same helper in onSalesJobStatusChanged.ts so the
 * day-before reminder reads the same way as the day-of confirmation.
 */
function resolveTechName(uid: string | undefined | null): string {
  if (!uid || uid.trim().length === 0) return "our technician";
  if (/^\d{1,8}$/.test(uid)) return "our technician";
  return uid;
}

/**
 * Compute the "tomorrow" window in America/Chicago time and return it
 * as a pair of UTC Dates suitable for Firestore Timestamp.fromDate().
 *
 * The function fires at 18:00 Central, so "tomorrow" always means the
 * next Central calendar day — start at 00:00 Central, end at 24:00
 * Central. We use Intl.DateTimeFormat with the IANA "America/Chicago"
 * zone to get the current Central calendar date, increment by one day,
 * then format that target day's midnight in Central as a string and
 * parse it back through the same formatter to discover the correct UTC
 * offset (which handles DST transitions automatically).
 *
 * Returns a window covering [start, end) — start inclusive, end
 * exclusive. Pass `end` to Firestore as the upper bound with `<` for
 * the exclusive semantics.
 */
function tomorrowWindowCentral(): { start: Date; end: Date } {
  // Get current Central calendar date (en-CA gives us YYYY-MM-DD).
  const now = new Date();
  const dateFmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Chicago",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const todayCentral = dateFmt.format(now); // e.g. "2026-04-08"
  const [y, m, d] = todayCentral.split("-").map(Number);

  // Build "tomorrow midnight Central" by adding one calendar day in UTC
  // and then walking the offset back. We do this by computing the
  // millisecond offset between Central and UTC at the target instant.
  const tomorrowUtcMidnight = new Date(Date.UTC(y, m - 1, d + 1, 0, 0, 0, 0));

  // tomorrowUtcMidnight currently represents 00:00 UTC for the calendar
  // day after today-in-Central. We need to shift it to 00:00 Central
  // for that same calendar day. The shift is the Central offset at
  // that instant — derived by formatting tomorrowUtcMidnight in Central
  // and reading back the hour difference from UTC.
  const offsetMinutes = centralOffsetMinutes(tomorrowUtcMidnight);
  // Central is UTC-5 or UTC-6, so offsetMinutes is -300 or -360.
  // To convert "00:00 UTC" → "00:00 Central", we shift forward by the
  // absolute offset, i.e. add (-offsetMinutes) minutes.
  const startMs = tomorrowUtcMidnight.getTime() - offsetMinutes * 60 * 1000;
  const start = new Date(startMs);

  // End is start + 24 hours. This is correct on non-DST-transition days.
  // On the spring-forward day (March, lose an hour) the window is 23h
  // wide; on the fall-back day (November, gain an hour) it's 25h wide.
  // For our purposes — flagging "tomorrow's appointments" — using a
  // calendar-day-based end is more correct than a fixed 24h delta, so
  // we recompute end the same way.
  const dayAfterTomorrowUtcMidnight = new Date(
    Date.UTC(y, m - 1, d + 2, 0, 0, 0, 0),
  );
  const endOffsetMinutes = centralOffsetMinutes(dayAfterTomorrowUtcMidnight);
  const endMs =
    dayAfterTomorrowUtcMidnight.getTime() - endOffsetMinutes * 60 * 1000;
  const end = new Date(endMs);

  return { start, end };
}

/**
 * Returns the offset (in minutes) from UTC for the America/Chicago
 * timezone at the given instant. CST = -360, CDT = -300. Uses
 * Intl.DateTimeFormat with timeZoneName: "shortOffset" to read the
 * GMT-N value at the given moment, then parses it.
 */
function centralOffsetMinutes(at: Date): number {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Chicago",
    timeZoneName: "shortOffset",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const parts = fmt.formatToParts(at);
  const tzPart = parts.find((p) => p.type === "timeZoneName");
  if (!tzPart) return -360; // Conservative CST default.

  // tzPart.value is like "GMT-5" or "GMT-6"
  const match = /GMT([+-])(\d{1,2})(?::(\d{2}))?/.exec(tzPart.value);
  if (!match) return -360;

  const sign = match[1] === "-" ? -1 : 1;
  const hours = parseInt(match[2], 10);
  const minutes = match[3] ? parseInt(match[3], 10) : 0;
  return sign * (hours * 60 + minutes);
}

/**
 * Try to send an SMS for a single job. Returns 'sent', 'skipped' (no
 * phone or formatting failure), or 'error' (Twilio rejected). Errors
 * are caught internally — never thrown.
 */
async function trySendReminder(params: {
  jobId: string;
  phone: string;
  body: string;
  pass: "Day1" | "Day2";
}): Promise<"sent" | "skipped" | "error"> {
  const { jobId, phone, body, pass } = params;

  if (!phone) {
    logger.warn(
      `sendInstallReminders: ${pass} job ${jobId} — no prospect.phone, skipping`,
    );
    return "skipped";
  }

  const e164 = formatPhone(phone);
  if (!e164) {
    logger.warn(
      `sendInstallReminders: ${pass} job ${jobId} — phone "${phone}" failed E.164 normalization, skipping`,
    );
    return "skipped";
  }

  try {
    await sendSms(e164, body);
    return "sent";
  } catch (err) {
    logger.error(
      `sendInstallReminders: ${pass} job ${jobId} — SMS send failed: ${(err as Error).message}`,
    );
    return "error";
  }
}

// ── Cloud Function ──────────────────────────────────────────────────────────

export const sendInstallReminders = onSchedule(
  {
    schedule: "every day 18:00",
    timeZone: "America/Chicago",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();

    const { start, end } = tomorrowWindowCentral();
    const startTs = admin.firestore.Timestamp.fromDate(start);
    const endTs = admin.firestore.Timestamp.fromDate(end);

    logger.info(
      `sendInstallReminders: starting — window ${start.toISOString()} → ${end.toISOString()}`,
    );

    let day1Sent = 0;
    let day1Skipped = 0;
    let day2Sent = 0;
    let day2Skipped = 0;

    // ── Pass 1 — Day 1 reminders ────────────────────────────────────────
    try {
      const day1Snap = await db
        .collection("sales_jobs")
        .where("status", "==", STATUS_PREWIRE_SCHEDULED)
        .where("day1Date", ">=", startTs)
        .where("day1Date", "<", endTs)
        .get();

      logger.info(
        `sendInstallReminders: Day 1 query matched ${day1Snap.size} jobs`,
      );

      for (const doc of day1Snap.docs) {
        const jobId = doc.id;
        try {
          const data = doc.data();
          const dealerCode = (data.dealerCode as string) ?? "";

          // Per-job dealer config: each job may belong to a different
          // dealer with different toggles + sign-off. Defaults on miss.
          const config = await loadDealerMessagingConfig(dealerCode);

          if (!config.sendDay1Reminder) {
            day1Skipped++;
            logger.info(
              `sendInstallReminders: Day 1 job ${jobId} skipped — dealer ${dealerCode} has sendDay1Reminder=false`,
            );
            continue;
          }

          const prospect = readProspect(data);
          const firstName = prospect.firstName || "there";
          const techName = resolveTechName(data.day1TechUid as string | null);
          const signOff = resolveSignOff(config);

          const body =
            `Hi ${firstName}! 👋 Just a reminder — tomorrow is your ` +
            `${signOff} prep day. ${techName} will be there at your home ` +
            "to run all wiring. Please make sure we have access to: your " +
            "electrical panel, garage or utility area, and exterior eaves. " +
            "No lights go up tomorrow — that's Day 2! See you then. " +
            `— ${signOff}`;

          const result = await trySendReminder({
            jobId,
            phone: prospect.phone,
            body,
            pass: "Day1",
          });

          if (result === "sent") {
            day1Sent++;
          } else {
            day1Skipped++;
          }
        } catch (jobErr) {
          // Per-job catch-all so an unexpected exception (e.g. malformed
          // job document) on one job never stops the loop.
          day1Skipped++;
          logger.error(
            `sendInstallReminders: Day 1 job ${jobId} — unexpected error: ${(jobErr as Error).message}`,
          );
        }
      }
    } catch (queryErr) {
      logger.error(
        `sendInstallReminders: Day 1 query failed: ${(queryErr as Error).message}`,
      );
      // Pass 2 should still run — fall through.
    }

    // ── Pass 2 — Day 2 reminders ────────────────────────────────────────
    try {
      const day2Snap = await db
        .collection("sales_jobs")
        .where("status", "==", STATUS_INSTALL_SCHEDULED)
        .where("day2Date", ">=", startTs)
        .where("day2Date", "<", endTs)
        .get();

      logger.info(
        `sendInstallReminders: Day 2 query matched ${day2Snap.size} jobs`,
      );

      for (const doc of day2Snap.docs) {
        const jobId = doc.id;
        try {
          const data = doc.data();
          const dealerCode = (data.dealerCode as string) ?? "";

          // Per-job dealer config: each job may belong to a different
          // dealer with different toggles + sign-off. Defaults on miss.
          const config = await loadDealerMessagingConfig(dealerCode);

          if (!config.sendDay2Reminder) {
            day2Skipped++;
            logger.info(
              `sendInstallReminders: Day 2 job ${jobId} skipped — dealer ${dealerCode} has sendDay2Reminder=false`,
            );
            continue;
          }

          const prospect = readProspect(data);
          const firstName = prospect.firstName || "there";
          const signOff = resolveSignOff(config);

          const body =
            `Hi ${firstName}! 🎉 Big day tomorrow — your ${signOff} ` +
            "lights go up! Our install team will be at your home to " +
            "complete the full installation. No electrical access needed " +
            "tomorrow — just the exterior of your home. Get ready to see " +
            `it light up! — ${signOff}`;

          const result = await trySendReminder({
            jobId,
            phone: prospect.phone,
            body,
            pass: "Day2",
          });

          if (result === "sent") {
            day2Sent++;
          } else {
            day2Skipped++;
          }
        } catch (jobErr) {
          day2Skipped++;
          logger.error(
            `sendInstallReminders: Day 2 job ${jobId} — unexpected error: ${(jobErr as Error).message}`,
          );
        }
      }
    } catch (queryErr) {
      logger.error(
        `sendInstallReminders: Day 2 query failed: ${(queryErr as Error).message}`,
      );
    }

    logger.info(
      `Reminder run complete — Day1: ${day1Sent} sent, ${day1Skipped} skipped. ` +
        `Day2: ${day2Sent} sent, ${day2Skipped} skipped.`,
    );
  },
);
