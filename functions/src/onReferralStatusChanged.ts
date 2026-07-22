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

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// admin.initializeApp() is called in index.js — do not call again here.

const NOTIFICATION_MAP: Record<string, { title: string; body: (name: string) => string }> = {
  confirmed: {
    title: "Referral confirmed",
    body: (name) => `${name} signed their estimate — install is scheduled`,
  },
  installing: {
    title: "Install day is here",
    body: (name) => `${name}'s Nex-Gen system is being installed today`,
  },
  installed: {
    title: "Your neighbor is live",
    body: (name) => `A Nex-Gen account has been created for ${name}`,
  },
  paid: {
    title: "Your referral reward is ready",
    body: (name) => `Your reward for referring ${name} has been issued`,
  },
};

export const onReferralStatusChanged = onDocumentUpdated(
  {
    document: "users/{referrerUid}/referrals/{referralId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    const oldStatus = before.status as string | undefined;
    const newStatus = after.status as string | undefined;

    // Only fire when status actually changed
    if (!newStatus || oldStatus === newStatus) return;

    // Skip "lead" — handled separately by lead capture
    const notification = NOTIFICATION_MAP[newStatus];
    if (!notification) return;

    const referrerUid = event.params.referrerUid;
    const referralId = event.params.referralId;
    const name = (after.name as string) || "Your referral";

    // Read the referrer's FCM token
    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(referrerUid)
      .get();

    const fcmToken = userDoc.data()?.fcmToken as string | undefined;
    if (!fcmToken) {
      logger.info(
        `No FCM token for referrer ${referrerUid} — skipping notification`
      );
      return;
    }

    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: notification.title,
          body: notification.body(name),
        },
        data: {
          referralId,
          newStatus,
          referrerUid,
        },
        android: {
          notification: {
            channelId: "referral_updates",
            priority: "high",
            defaultSound: true,
          },
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: notification.title,
                body: notification.body(name),
              },
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.info(
        `Sent "${newStatus}" notification for referral ${referralId} to ${referrerUid}`
      );
    } catch (err) {
      logger.error(
        `Failed to send referral notification to ${referrerUid}:`,
        err
      );
    }
  }
);
