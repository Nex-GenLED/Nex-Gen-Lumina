/**
 * initiateSyncSession — Firebase Cloud Function
 *
 * Called by the background service (or foreground app) to create a sync
 * session server-side. This function:
 *   1. Validates the event exists and is enabled
 *   2. Resolves participants from group members with consent checks
 *   3. Determines host (prefers group creator, falls back to initiator)
 *   4. Creates the session document in Firestore
 *   5. Sends FCM notifications to participants
 *   6. Returns the session ID
 *
 * This runs server-side because the background isolate cannot use Riverpod
 * or Firestore listeners — it only has SharedPreferences and HTTP.
 *
 * Transport: onRequest (raw HTTPS) with manual ID-token verification.
 *
 * Request body — accepts BOTH `{data: {...}}` (legacy callable-shape) and
 * flat shapes. Returns a flat 200 body — no callable-protocol `{result:}`
 * wrapping.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:initiateSyncSession
 */
export declare const initiateSyncSession: import("firebase-functions/v2/https").HttpsFunction;
