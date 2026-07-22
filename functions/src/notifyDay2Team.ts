/**
 * notifyDay2Team — Firebase Cloud Function
 *
 * Callable function that sends FCM push notifications to the install
 * team when a pre-wire is marked complete. Notifies all active
 * installers under the same dealer code as the sales job.
 *
 * Security: authenticated (caller must be a Firebase Auth user).
 * FCM tokens are looked up server-side — never sent from the client.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:notifyDay2Team
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

// admin.initializeApp() is called in index.js — do not call again here.

interface NotifyDay2TeamRequest {
  jobId: string;
}

export const notifyDay2Team = onCall(
  { maxInstances: 10 },
  async (request) => {
    // ── Auth check ─────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Must be authenticated to notify the install team."
      );
    }

    const { jobId } = request.data as NotifyDay2TeamRequest;

    if (!jobId || typeof jobId !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "jobId is required and must be a string."
      );
    }

    const db = admin.firestore();

    // 1. Read the job doc
    const jobDoc = await db.collection("sales_jobs").doc(jobId).get();
    if (!jobDoc.exists) {
      throw new HttpsError("not-found", `Sales job ${jobId} not found.`);
    }

    const jobData = jobDoc.data()!;
    const dealerCode = jobData.dealerCode as string;
    const customerName = jobData.prospect?.firstName
      ? `${jobData.prospect.firstName} ${jobData.prospect.lastName || ""}`.trim()
      : "Customer";
    const address = jobData.prospect?.address || "address on file";
    const day2Date = jobData.day2Date
      ? jobData.day2Date.toDate().toLocaleDateString("en-US", {
          month: "short",
          day: "numeric",
          year: "numeric",
        })
      : "TBD";

    // 2. Query active installers for this dealer
    const installerSnap = await db
      .collection("installers")
      .where("dealerCode", "==", dealerCode)
      .where("isActive", "==", true)
      .get();

    if (installerSnap.empty) {
      logger.info(`notifyDay2Team: No active installers for dealer ${dealerCode}`);
      return { success: true, notifiedCount: 0 };
    }

    // 3. Collect FCM tokens from installer user accounts
    const tokens: string[] = [];

    for (const installerDoc of installerSnap.docs) {
      const installerData = installerDoc.data();
      const linkedUid = installerData.linkedUid as string | undefined;
      if (!linkedUid) {
        logger.info(`notifyDay2Team: Installer ${installerDoc.id} has no linkedUid, skipping`);
        continue;
      }

      const userDoc = await db.collection("users").doc(linkedUid).get();
      if (!userDoc.exists) {
        logger.info(`notifyDay2Team: User ${linkedUid} not found, skipping`);
        continue;
      }

      const fcmToken = userDoc.data()?.fcmToken as string | undefined;
      if (fcmToken) {
        tokens.push(fcmToken);
      } else {
        logger.info(`notifyDay2Team: User ${linkedUid} has no FCM token, skipping`);
      }
    }

    if (tokens.length === 0) {
      logger.info(`notifyDay2Team: No FCM tokens found for dealer ${dealerCode}`);
      return { success: true, notifiedCount: 0 };
    }

    // 4. Send FCM notifications
    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: `Day 2 ready — ${customerName}`,
        body: `Pre-wire complete at ${address}. Install is a go for ${day2Date}.`,
      },
      data: {
        jobId,
        type: "day2Ready",
      },
      android: {
        priority: "high",
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    };

    let successCount = 0;
    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      successCount = response.successCount;
      logger.info(
        `notifyDay2Team: Sent ${successCount}/${tokens.length} notifications for job ${jobId}`
      );

      // Log individual failures
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          logger.warn(
            `notifyDay2Team: Failed to send to token ${idx}: ${resp.error?.message}`
          );
        }
      });
    } catch (err) {
      logger.error(`notifyDay2Team: FCM send failed: ${err}`);
    }

    // 5. Update job doc
    await db.collection("sales_jobs").doc(jobId).update({
      day2Notified: true,
      day2NotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, notifiedCount: successCount };
  }
);
