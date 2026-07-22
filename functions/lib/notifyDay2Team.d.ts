/**
 * notifyDay2Team — Firebase Cloud Function
 *
 * Callable function that sends FCM push notifications to the install
 * team when a pre-wire is marked complete. Notifies all active
 * installers under the same dealer code as the sales job.
 *
 * Security: authenticated (caller must be a Firebase Auth user).
 * FCM tokens are looked up server-side — never sent from the client.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:notifyDay2Team
 */
export declare const notifyDay2Team: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    notifiedCount: number;
}>, unknown>;
