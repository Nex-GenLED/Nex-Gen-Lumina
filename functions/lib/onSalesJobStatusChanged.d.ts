/**
 * onSalesJobStatusChanged — Firestore trigger
 *
 * Fires whenever a sales_jobs document is updated. Detects status
 * transitions and the day1 completion event, and dispatches the
 * appropriate customer-facing SMS or email via the messaging-helpers
 * module.
 *
 * Critical contract: this trigger MUST NOT throw on messaging
 * failures. A bad customer phone number, a Twilio outage, or a Resend
 * 5xx must never fail the Firestore trigger itself — that would loop
 * the trigger and corrupt the job document's update history. Every
 * outbound message call is wrapped in a per-channel try/catch that
 * logs and continues.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:onSalesJobStatusChanged
 */
export declare const onSalesJobStatusChanged: import("firebase-functions").CloudFunction<import("firebase-functions/v2/firestore").FirestoreEvent<import("firebase-functions").Change<import("firebase-functions/v2/firestore").QueryDocumentSnapshot> | undefined, {
    jobId: string;
}>>;
