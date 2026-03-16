/**
 * endSyncSession — Firebase Cloud Function
 *
 * Called by the background service to end an active sync session.
 * Handles the 30-second dissolution warning, marks session as completed,
 * and sends FCM notifications to all participants.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:endSyncSession
 */
export declare const endSyncSession: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    message: string;
    sessionId?: undefined;
    participantCount?: undefined;
} | {
    success: boolean;
    sessionId: string;
    participantCount: number;
    message?: undefined;
}>, unknown>;
