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

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

interface RedeemRequest {
  code: string;
  prospectName?: string;
}

export const redeemReferralCode = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to redeem a referral code.");
    }

    const { code, prospectName } = request.data as RedeemRequest;
    if (!code || typeof code !== "string") {
      throw new HttpsError("invalid-argument", "A referral code is required.");
    }

    const db = admin.firestore();
    const codeDoc = await db.collection("referral_codes").doc(code.toUpperCase()).get();

    if (!codeDoc.exists) {
      throw new HttpsError("not-found", "Invalid referral code.");
    }

    const referrerUid = codeDoc.data()?.uid as string;
    if (referrerUid === request.auth.uid) {
      throw new HttpsError("invalid-argument", "You cannot redeem your own referral code.");
    }

    const referralRef = db
      .collection("users")
      .doc(referrerUid)
      .collection("referrals")
      .doc();

    await referralRef.set({
      name: prospectName || "Friend",
      status: "lead",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      status_updated_at: admin.firestore.FieldValue.serverTimestamp(),
      prospect_uid: request.auth.uid,
      job_id: null,
      referral_code: code.toUpperCase(),
    });

    return { success: true, referralId: referralRef.id };
  }
);
