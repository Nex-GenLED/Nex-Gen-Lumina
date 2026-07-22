/**
 * enforceScheduleLimits — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 19:00 UTC. Scans every user document and trims the
 * `schedules` array to a maximum of MAX_SCHEDULES entries, keeping the most
 * recently appended items.
 *
 * Server-side defense-in-depth for the same cap enforced at write-time by
 * SchedulesNotifier.addAll on the client
 * (lib/features/schedule/schedule_providers.dart:461). Catches users on older
 * app builds that don't enforce the cap, and any drift the client-side dedup
 * doesn't catch.
 *
 * TWO correctness properties this file guarantees:
 *
 *   1. TRANSACTIONAL. The array read-trim-write runs inside a per-user
 *      runTransaction. This is the LAST blind whole-array overwrite in the
 *      system — a third writer the client-side per-uid lock cannot see (it
 *      runs in this Cloud Functions process). Wrapping it in a transaction
 *      means a concurrent client remove/update can't be silently clobbered:
 *      the trim re-reads inside the txn and Firestore retries on conflict.
 *
 *   2. MIGRATION-AWARE. If (and only if) trimming occurred, the identical trim
 *      is applied to the /users/{uid}/schedules subcollection via batched
 *      deletes of the removed ids (translated through the same scheduleSubDocId
 *      contract the client uses). This keeps both shapes convergent during the
 *      array→subcollection dual-write window. Users with no subcollection docs
 *      yet just no-op the deletes.
 *
 * Idempotent (a second run finds length <= cap and does nothing); users
 * without a `schedules` array field are skipped.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:enforceScheduleLimits
 */
export declare const enforceScheduleLimits: import("firebase-functions/v2/scheduler").ScheduleFunction;
