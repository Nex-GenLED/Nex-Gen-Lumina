/**
 * sendSyncNotification — Firebase Cloud Function
 *
 * Callable function that sends FCM push notifications to neighborhood sync
 * participants. Called by the host device's SyncNotificationService.
 *
 * Security: authenticated (caller must be a Firebase Auth user).
 * Tokens are looked up server-side — never sent from the client.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:sendSyncNotification
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

interface SendSyncNotificationRequest {
  groupId: string;
  participantUids: string[];
  title: string;
  body: string;
  type: string;
  data?: Record<string, string>;
}

export const sendSyncNotification = onCall(
  { maxInstances: 20 },
  async (request) => {
    // ── Auth check ─────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Must be authenticated to send sync notifications."
      );
    }

    const callerUid = request.auth.uid;
    const {
      groupId,
      participantUids,
      title,
      body,
      type,
      data,
    } = request.data as SendSyncNotificationRequest;

    // ── Validate inputs ────────────────────────────────────────────
    if (!groupId || !participantUids || !title || !body) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required fields: groupId, participantUids, title, body."
      );
    }

    if (participantUids.length > 100) {
      throw new HttpsError(
        "invalid-argument",
        "Cannot notify more than 100 participants at once."
      );
    }

    // ── Verify caller is a member of the group ─────────────────────
    const groupDoc = await admin
      .firestore()
      .collection("neighborhoods")
      .doc(groupId)
      .get();

    if (!groupDoc.exists) {
      throw new HttpsError("not-found", "Neighborhood group not found.");
    }

    const groupData = groupDoc.data();
    const memberUids: string[] = groupData?.memberUids ?? [];
    if (!memberUids.includes(callerUid)) {
      throw new HttpsError(
        "permission-denied",
        "You are not a member of this group."
      );
    }

    // ── Collect FCM tokens for participants ─────────────────────────
    const tokens: string[] = [];
    const staleTokenUids: string[] = [];

    for (const uid of participantUids) {
      // Skip sending to the caller themselves (they already know)
      if (uid === callerUid) continue;

      try {
        // Look up token from the member's profile in the group
        const memberDoc = await admin
          .firestore()
          .collection("neighborhoods")
          .doc(groupId)
          .collection("members")
          .doc(uid)
          .get();

        const fcmToken = memberDoc.data()?.fcmToken;
        if (fcmToken && typeof fcmToken === "string") {
          tokens.push(fcmToken);
        } else {
          staleTokenUids.push(uid);
        }
      } catch (err) {
        console.warn(`Failed to get token for ${uid}:`, err);
        staleTokenUids.push(uid);
      }
    }

    if (tokens.length === 0) {
      return {
        success: true,
        sent: 0,
        staleTokens: staleTokenUids.length,
        message: "No valid tokens found.",
      };
    }

    // ── Send via FCM ───────────────────────────────────────────────
    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title,
        body,
      },
      data: {
        type: type ?? "sessionStarted",
        groupId,
        ...(data ?? {}),
      },
      android: {
        notification: {
          channelId: "neighborhood_sync",
          priority: "high" as const,
          defaultSound: true,
        },
        priority: "high" as const,
      },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);

      // Handle stale/invalid tokens
      const failedTokens: string[] = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            failedTokens.push(tokens[idx]);
          }
          console.warn(
            `FCM send failed for token ${idx}:`,
            resp.error?.message
          );
        }
      });

      // Clean up stale tokens from Firestore
      if (failedTokens.length > 0) {
        console.log(
          `Cleaning ${failedTokens.length} stale tokens from group ${groupId}`
        );
        const batch = admin.firestore().batch();
        for (const uid of participantUids) {
          const memberDoc = await admin
            .firestore()
            .collection("neighborhoods")
            .doc(groupId)
            .collection("members")
            .doc(uid)
            .get();
          const memberToken = memberDoc.data()?.fcmToken;
          if (memberToken && failedTokens.includes(memberToken)) {
            batch.update(memberDoc.ref, {
              fcmToken: admin.firestore.FieldValue.delete(),
            });
          }
        }
        await batch.commit();
      }

      return {
        success: true,
        sent: response.successCount,
        failed: response.failureCount,
        staleTokens: staleTokenUids.length + failedTokens.length,
      };
    } catch (err) {
      console.error("FCM multicast send failed:", err);
      throw new HttpsError(
        "internal",
        "Failed to send notifications."
      );
    }
  }
);
