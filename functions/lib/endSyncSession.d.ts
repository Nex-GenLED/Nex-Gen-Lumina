/**
 * endSyncSession — Firebase Cloud Function
 *
 * Called by the background service to end an active sync session.
 * Handles the 30-second dissolution warning, marks session as completed,
 * and sends FCM notifications to all participants.
 *
 * Transport: onRequest (raw HTTPS) with manual ID-token verification.
 *
 * Request body — accepts BOTH `{data: {...}}` (legacy callable-shape) and
 * flat shapes. Returns a flat 200 body — no `{result:}` wrapping.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:endSyncSession
 */
export declare const endSyncSession: import("firebase-functions/v2/https").HttpsFunction;
