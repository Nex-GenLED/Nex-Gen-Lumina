/**
 * onReferralStatusChanged — Firebase Cloud Function
 *
 * Firestore onUpdate trigger for /users/{referrerUid}/referrals/{referralId}.
 * Sends a push notification to the referring user when a referral's status
 * advances through the pipeline.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:onReferralStatusChanged
 */
export declare const onReferralStatusChanged: import("firebase-functions/core").CloudFunction<import("firebase-functions/v2/firestore").FirestoreEvent<import("firebase-functions/v2/firestore").Change<import("firebase-functions/v2/firestore").QueryDocumentSnapshot> | undefined, {
    referrerUid: string;
    referralId: string;
}>>;
