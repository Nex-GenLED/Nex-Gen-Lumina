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

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

// admin.initializeApp() is called in index.js — do not call again here.

interface NotifyReferrerRequest {
  payoutId: string;
}

export const notifyReferrerOfApproval = onCall(
  { maxInstances: 10 },
  async (request) => {
    // ── Auth check ─────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Must be authenticated to send reward notifications."
      );
    }

    const { payoutId } = request.data as NotifyReferrerRequest;

    if (!payoutId || typeof payoutId !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "payoutId is required and must be a string."
      );
    }

    const db = admin.firestore();

    // 1. Read payout doc
    const payoutDoc = await db.collection("referral_payouts").doc(payoutId).get();
    if (!payoutDoc.exists) {
      throw new HttpsError("not-found", `Payout ${payoutId} not found.`);
    }
    const payout = payoutDoc.data()!;

    // 2. Read referrer FCM token
    const userDoc = await db
      .collection("users")
      .doc(payout.referrerUid)
      .get();
    const fcmToken = userDoc.data()?.fcmToken as string | undefined;
    if (!fcmToken) {
      logger.info(
        `notifyReferrerOfApproval: No FCM token for user ${payout.referrerUid}`
      );
      return { success: false, reason: "no_fcm_token" };
    }

    // 3. Build notification based on reward type
    const isGc = payout.rewardType === "visaGiftCard";
    const amount = `$${payout.rewardAmountUsd}`;
    const title = "Your referral reward is approved";
    const body = isGc
      ? `A ${amount} Visa gift card is on the way for referring ${payout.prospectName}`
      : `${amount} in Nex-Gen credit has been added to your account for referring ${payout.prospectName}`;

    // 4. Send FCM notification
    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        data: {
          payoutId,
          type: "rewardApproved",
          rewardType: payout.rewardType,
          rewardAmount: String(payout.rewardAmountUsd),
        },
      });

      logger.info(
        `Reward approval notification sent to ${payout.referrerUid} for payout ${payoutId}`
      );
    } catch (err) {
      logger.error(
        `notifyReferrerOfApproval: FCM send failed for ${payout.referrerUid}: ${err}`
      );
    }

    return { success: true };
  }
);
