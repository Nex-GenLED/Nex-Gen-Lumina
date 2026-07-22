/**
 * sendSyncNotification — Firebase Cloud Function
 *
 * Callable function that sends FCM push notifications to neighborhood sync
 * participants. Called by the host device's SyncNotificationService.
 *
 * Security: authenticated (caller must be a Firebase Auth user).
 * Tokens are looked up server-side — never sent from the client.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:sendSyncNotification
 */
export declare const sendSyncNotification: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    sent: number;
    staleTokens: number;
    message: string;
    failed?: undefined;
} | {
    success: boolean;
    sent: number;
    failed: number;
    staleTokens: number;
    message?: undefined;
}>, unknown>;
