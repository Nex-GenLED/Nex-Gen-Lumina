/**
 * triggerSyncFailover — Firebase Cloud Function
 *
 * Sends a silent push notification to the backup host when the primary host
 * fails to initiate a sync session within the 2-minute grace window.
 *
 * Called by a Firestore trigger (or scheduled check) when a session was
 * expected but not created within the grace window.
 *
 * Also provides a callable endpoint for explicit failover requests.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:triggerSyncFailover
 */
export declare const triggerSyncFailover: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    message: string;
    sessionId: string;
    backupHostUid?: undefined;
} | {
    success: boolean;
    message: string;
    sessionId?: undefined;
    backupHostUid?: undefined;
} | {
    success: boolean;
    backupHostUid: string;
    message: string;
    sessionId?: undefined;
}>, unknown>;
