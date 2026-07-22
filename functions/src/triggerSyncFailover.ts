/**
 * triggerSyncFailover — Firebase Cloud Function
 *
 * Sends a silent push notification to the backup host when the primary host
 * fails to initiate a sync session within the 2-minute grace window.
 *
 * Called by a Firestore trigger (or scheduled check) when a session was
 * expected but not created within the grace window.
 *
 * Also provides a callable endpoint for explicit failover requests.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:triggerSyncFailover
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface FailoverRequest {
  groupId: string;
  eventId: string;
  failedHostUid: string;
  gameId?: string;
}

export const triggerSyncFailover = onCall(
  { maxInstances: 10 },
  async (request) => {
    const { groupId, eventId, failedHostUid, gameId } =
      request.data as FailoverRequest;

    if (!groupId || !eventId || !failedHostUid) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required fields: groupId, eventId, failedHostUid."
      );
    }

    const db = admin.firestore();

    // ── Check session doesn't already exist ───────────────────────────
    const activeSessions = await db
      .collection("neighborhoods")
      .doc(groupId)
      .collection("syncSessions")
      .where("status", "in", ["active", "waitingForGameStart"])
      .limit(1)
      .get();

    if (!activeSessions.empty) {
      return {
        success: true,
        message: "Session already active — failover not needed.",
        sessionId: activeSessions.docs[0].id,
      };
    }

    // ── Find backup host ──────────────────────────────────────────────
    const groupDoc = await db.collection("neighborhoods").doc(groupId).get();
    if (!groupDoc.exists) {
      throw new HttpsError("not-found", "Group not found.");
    }

    const memberUids: string[] = groupDoc.data()?.memberUids ?? [];
    let backupHostUid: string | null = null;
    let backupToken: string | null = null;

    // Find an eligible member who isn't the failed host
    for (const uid of memberUids) {
      if (uid === failedHostUid) continue;

      const memberDoc = await db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("members")
        .doc(uid)
        .get();

      if (!memberDoc.exists) continue;
      const data = memberDoc.data()!;

      // Check consent
      const consentDoc = await db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("members")
        .doc(uid)
        .collection("settings")
        .doc("syncConsent")
        .get();

      if (!consentDoc.exists) continue;

      const token = data.fcmToken;
      if (token && typeof token === "string") {
        backupHostUid = uid;
        backupToken = token;
        break;
      }
    }

    if (!backupHostUid || !backupToken) {
      return {
        success: false,
        message: "No backup host available with valid FCM token.",
      };
    }

    // ── Send silent push to backup host ───────────────────────────────
    // Silent push = data-only message, no notification payload.
    // This wakes the app/background service on the backup device.
    try {
      await admin.messaging().send({
        token: backupToken,
        data: {
          type: "syncFailover",
          groupId,
          eventId,
          gameId: gameId || "",
          failedHostUid,
          action: "initiateSession",
        },
        android: {
          priority: "high",
          // No notification — data-only for silent wake
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "background",
          },
          payload: {
            aps: {
              "content-available": 1,
              // No alert, sound, or badge — silent push
            },
          },
        },
      });

      console.log(
        `Failover: silent push sent to backup host ${backupHostUid} ` +
          `for event ${eventId} in group ${groupId}`
      );

      return {
        success: true,
        backupHostUid,
        message: "Silent push sent to backup host.",
      };
    } catch (err) {
      console.error("Failover FCM send failed:", err);
      throw new HttpsError("internal", "Failed to send failover push.");
    }
  }
);
