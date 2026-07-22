/**
 * redeemReferralCode — Firebase Cloud Function
 *
 * Callable function invoked when a new prospect redeems a referral code.
 * Looks up the referrer via /referral_codes/{code}, then creates a tracking
 * doc under /users/{referrerUid}/referrals with the full pipeline schema.
 *
 * Security: authenticated — the caller must be a Firebase Auth user.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:redeemReferralCode
 */
export declare const redeemReferralCode: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    referralId: string;
}>, unknown>;
