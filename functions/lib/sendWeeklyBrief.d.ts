/**
 * sendWeeklyBrief — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 18:30 UTC. For each user with autopilot enabled and
 * weekly schedule preview enabled, reads upcoming autopilot_events, calls
 * Claude Haiku to generate a short push notification body, and sends an FCM
 * push with a deep-link to the autopilot schedule screen.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:sendWeeklyBrief
 */
export declare const sendWeeklyBrief: import("firebase-functions/v2/scheduler").ScheduleFunction;
