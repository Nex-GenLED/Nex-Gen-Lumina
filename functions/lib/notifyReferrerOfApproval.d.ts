/**
 * notifyReferrerOfApproval — Firebase Cloud Function
 *
 * Callable function that sends an FCM push notification to a referrer
 * when their referral reward payout has been approved by a dealer/admin.
 *
 * Security: authenticated (caller must be a Firebase Auth user).
 * FCM tokens are looked up server-side — never sent from the client.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:notifyReferrerOfApproval
 */
export declare const notifyReferrerOfApproval: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    reason: string;
} | {
    success: boolean;
    reason?: undefined;
}>, unknown>;
