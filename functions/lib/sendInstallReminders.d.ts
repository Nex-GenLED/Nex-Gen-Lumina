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
export declare const sendInstallReminders: import("firebase-functions/v2/scheduler").ScheduleFunction;
