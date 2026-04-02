/**
 * assignReferralCode — Firebase Cloud Function
 *
 * Firestore onCreate trigger for /users/{uid}.
 * Generates a unique 8-char referral code (LUM-XXXX) and writes it to:
 *   - /users/{uid}/referralCode   (user's own doc)
 *   - /referral_codes/{code}      (reverse-lookup for redemption)
 *
 * Collision-safe: retries up to 5 times if the generated code already exists.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:assignReferralCode
 */
export declare const assignReferralCode: import("firebase-functions/core").CloudFunction<import("firebase-functions/v2/firestore").FirestoreEvent<import("firebase-functions/v2/firestore").QueryDocumentSnapshot | undefined, {
    uid: string;
}>>;
