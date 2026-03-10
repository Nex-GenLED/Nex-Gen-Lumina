/**
 * initiateSyncSession — Firebase Cloud Function
 *
 * Called by the background service (or foreground app) to create a sync
 * session server-side. This function:
 *   1. Validates the event exists and is enabled
 *   2. Resolves participants from group members with consent checks
 *   3. Determines host (prefers group creator, falls back to initiator)
 *   4. Creates the session document in Firestore
 *   5. Sends FCM notifications to participants
 *   6. Returns the session ID
 *
 * This runs server-side because the background isolate cannot use Riverpod
 * or Firestore listeners — it only has SharedPreferences and HTTP.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:initiateSyncSession
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface InitiateRequest {
  groupId: string;
  eventId: string;
  gameId?: string;
  initiatorUid: string;
}

export const initiateSyncSession = onCall(
  { maxInstances: 10 },
  async (request) => {
    // Auth is optional for background service calls (uses initiatorUid)
    const { groupId, eventId, gameId, initiatorUid } =
      request.data as InitiateRequest;

    if (!groupId || !eventId || !initiatorUid) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required fields: groupId, eventId, initiatorUid."
      );
    }

    const db = admin.firestore();

    // ── Validate group exists ─────────────────────────────────────────
    const groupDoc = await db.collection("neighborhoods").doc(groupId).get();
    if (!groupDoc.exists) {
      throw new HttpsError("not-found", "Neighborhood group not found.");
    }
    const groupData = groupDoc.data()!;

    // ── Validate event exists and is enabled ──────────────────────────
    const eventDoc = await db
      .collection("neighborhoods")
      .doc(groupId)
      .collection("syncEvents")
      .doc(eventId)
      .get();

    if (!eventDoc.exists) {
      throw new HttpsError("not-found", "Sync event not found.");
    }
    const eventData = eventDoc.data()!;
    if (!eventData.isEnabled) {
      return { success: false, message: "Event is disabled." };
    }

    // ── Check for existing active session ─────────────────────────────
    const activeSessions = await db
      .collection("neighborhoods")
      .doc(groupId)
      .collection("syncSessions")
      .where("status", "in", ["active", "waitingForGameStart"])
      .limit(1)
      .get();

    if (!activeSessions.empty) {
      return {
        success: false,
        sessionId: activeSessions.docs[0].id,
        message: "Active session already exists.",
      };
    }

    // ── Resolve participants ──────────────────────────────────────────
    const membersSnap = await db
      .collection("neighborhoods")
      .doc(groupId)
      .collection("members")
      .get();

    const category = eventData.category || "gameDay";
    const participants: string[] = [];

    for (const memberDoc of membersSnap.docs) {
      const memberData = memberDoc.data();
      const uid = memberDoc.id;

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
      const consent = consentDoc.data()!;

      // Category opt-in check
      const optIns = consent.categoryOptIns || {};
      if (!optIns[category]) continue;

      // Skip-next check
      const skipIds: string[] = consent.skipNextEventIds || [];
      if (skipIds.includes(eventId)) continue;

      // Participation status check
      if (memberData.participationStatus === "paused" ||
          memberData.participationStatus === "optedOut") {
        continue;
      }

      participants.push(uid);
    }

    if (participants.length === 0) {
      return { success: false, message: "No eligible participants." };
    }

    // ── Determine host ────────────────────────────────────────────────
    const creatorUid = groupData.creatorUid;
    const hostUid = participants.includes(creatorUid)
      ? creatorUid
      : participants.includes(initiatorUid)
        ? initiatorUid
        : participants[0];

    // ── Create session ────────────────────────────────────────────────
    const sessionRef = db
      .collection("neighborhoods")
      .doc(groupId)
      .collection("syncSessions")
      .doc();

    const session = {
      syncEventId: eventId,
      groupId,
      status: "active",
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      hostUid,
      activeParticipantUids: participants,
      declinedUids: [],
      gameId: gameId || null,
      isCelebrating: false,
      celebrationStartedAt: null,
      endedAt: null,
    };

    await sessionRef.set(session);

    // ── Clear skip-next flags ─────────────────────────────────────────
    const batch = db.batch();
    for (const uid of participants) {
      const consentRef = db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("members")
        .doc(uid)
        .collection("settings")
        .doc("syncConsent");

      batch.update(consentRef, {
        skipNextEventIds: admin.firestore.FieldValue.arrayRemove([eventId]),
      });
    }
    await batch.commit();

    // ── Send FCM notifications ────────────────────────────────────────
    const tokens: string[] = [];
    for (const uid of participants) {
      if (uid === initiatorUid) continue; // Skip the initiator
      const memberDoc = await db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("members")
        .doc(uid)
        .get();
      const token = memberDoc.data()?.fcmToken;
      if (token && typeof token === "string") {
        tokens.push(token);
      }
    }

    if (tokens.length > 0) {
      try {
        await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: "Neighborhood Sync",
            body: `${eventData.name} sync started — your lights are joining!`,
          },
          data: {
            type: "sessionStarted",
            groupId,
            eventName: eventData.name,
            sessionId: sessionRef.id,
          },
          android: {
            notification: {
              channelId: "neighborhood_sync",
              priority: "high" as const,
            },
            priority: "high" as const,
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: "Neighborhood Sync",
                  body: `${eventData.name} sync started — your lights are joining!`,
                },
                sound: "default",
                badge: 1,
              },
            },
          },
        });
      } catch (err) {
        console.warn("FCM notification failed:", err);
      }
    }

    console.log(
      `Session ${sessionRef.id} created for event ${eventId} ` +
        `with ${participants.length} participants`
    );

    return {
      success: true,
      sessionId: sessionRef.id,
      participantCount: participants.length,
      hostUid,
    };
  }
);
