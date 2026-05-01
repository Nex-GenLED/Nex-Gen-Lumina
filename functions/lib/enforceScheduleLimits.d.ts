/**
 * enforceScheduleLimits — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 19:00 UTC. Scans every user document and trims the
 * `schedules` array to a maximum of MAX_SCHEDULES entries, keeping the most
 * recently appended items.
 *
 * Server-side defense-in-depth for the same cap enforced at write-time by
 * SchedulesNotifier.addAll on the client. Catches users on older app builds
 * that don't enforce the cap, and any drift that the client-side dedup
 * doesn't catch.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:enforceScheduleLimits
 */
export declare const enforceScheduleLimits: import("firebase-functions/v2/scheduler").ScheduleFunction;
