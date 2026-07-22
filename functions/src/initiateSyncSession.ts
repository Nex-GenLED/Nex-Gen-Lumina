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
 * Transport: onRequest (raw HTTPS) with manual ID-token verification.
 *
 * Request body — accepts BOTH `{data: {...}}` (legacy callable-shape) and
 * flat shapes. Returns a flat 200 body — no callable-protocol `{result:}`
 * wrapping.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:initiateSyncSession
 */

import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface InitiateRequest {
  groupId: string;
  eventId: string;
  gameId?: string;
  initiatorUid: string;
}

export const initiateSyncSession = onRequest(
  { maxInstances: 10, cors: false },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed; use POST." });
      return;
    }

    // ── Manual auth verification ──────────────────────────────────────
    const authHeader = req.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({
        error: "Missing or malformed Authorization header (expected Bearer).",
      });
      return;
    }
    const idToken = authHeader.substring("Bearer ".length).trim();
    let decoded: admin.auth.DecodedIdToken;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      console.warn("initiateSyncSession: token verification failed", err);
      res.status(401).json({ error: "Invalid or expired ID token" });
      return;
    }

    // ── Body parsing (accept both shapes) ─────────────────────────────
    const rawBody = (req.body ?? {}) as Record<string, unknown>;
    const envelope: InitiateRequest = (rawBody.data !== undefined
      ? (rawBody.data as InitiateRequest)
      : (rawBody as unknown as InitiateRequest));

    const { groupId, eventId, gameId, initiatorUid } = envelope;

    if (!groupId || !eventId || !initiatorUid) {
      res.status(400).json({
        error: "Missing required fields: groupId, eventId, initiatorUid.",
      });
      return;
    }

    if (decoded.uid !== initiatorUid) {
      res
        .status(403)
        .json({ error: "Token UID does not match initiatorUid" });
      return;
    }

    const db = admin.firestore();

    // ── Validate group exists ─────────────────────────────────────────
    const groupDoc = await db.collection("neighborhoods").doc(groupId).get();
    if (!groupDoc.exists) {
      res.status(404).json({ error: "Neighborhood group not found." });
      return;
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
      res.status(404).json({ error: "Sync event not found." });
      return;
    }
    const eventData = eventDoc.data()!;
    if (!eventData.isEnabled) {
      res.status(200).json({ success: false, message: "Event is disabled." });
      return;
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
      res.status(200).json({
        success: false,
        sessionId: activeSessions.docs[0].id,
        message: "Active session already exists.",
      });
      return;
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
      res
        .status(200)
        .json({ success: false, message: "No eligible participants." });
      return;
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

    res.status(200).json({
      success: true,
      sessionId: sessionRef.id,
      participantCount: participants.length,
      hostUid,
    });
  }
);
