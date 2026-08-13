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


// ─── #71 pure decision helpers (exported for unit verification) ────────────

export type InitiatorVerdict =
  | { ok: true }
  | { ok: false; reason: string; message: string };

/**
 * PURE. May THIS initiator start a session in this category?
 *
 * CONSENT > PAUSE. Pause is a mood; consent is a contract. This function knows
 * only about the contract — `participationStatus` is deliberately not an input,
 * because the initiator is exempt from it and passing it here would invite a
 * future edit to blend the two back together.
 *
 * Three distinct refusals, because the remedies differ: never answered, said no
 * to the category, said skip-this-one.
 */
export function initiatorConsentVerdict(args: {
  consentExists: boolean;
  categoryOptIns: Record<string, unknown> | undefined | null;
  skipNextEventIds: unknown;
  category: string;
  eventId: string;
}): InitiatorVerdict {
  if (!args.consentExists) {
    return {
      ok: false,
      reason: "consent_missing",
      message:
        `You have no sync consent recorded for "${args.category}", so this ` +
        "session was not started.",
    };
  }
  if (!(args.categoryOptIns || {})[args.category]) {
    return {
      ok: false,
      reason: "consent_blocked",
      message:
        `Your sync consent for "${args.category}" is off, so this session was ` +
        "not started. Turn it on to sync this category.",
    };
  }
  const skip = Array.isArray(args.skipNextEventIds) ? args.skipNextEventIds : [];
  if (skip.includes(args.eventId)) {
    return {
      ok: false,
      reason: "skip_next_active",
      message: "You chose to skip this event, so this session was not started.",
    };
  }
  return { ok: true };
}

/**
 * PURE. Is this member dropped for participationStatus?
 *
 * #71: the initiator never is. Identity-keyed, mirroring #69's fix in
 * applySyncPattern — NOT a relaxed predicate, so every other member's pause
 * semantics are byte-identical to before.
 */
export function memberSkippedForSession(
  isInitiator: boolean,
  participationStatus: unknown
): boolean {
  if (isInitiator) return false;
  return participationStatus === "paused" || participationStatus === "optedOut";
}

/**
 * PURE. Host selection, unchanged in rule and now reachable by a paused
 * initiator: they are in `participants`, so the existing preference order can
 * pick them.
 */
export function chooseHost(
  participants: string[],
  creatorUid: unknown,
  initiatorUid: string
): string {
  if (typeof creatorUid === "string" && participants.includes(creatorUid)) {
    return creatorUid;
  }
  if (participants.includes(initiatorUid)) return initiatorUid;
  return participants[0];
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

    // ── #71 — CONSENT > PAUSE, and the initiator is exempt from pause only ──
    //
    // Tyler's decision, 2026-08-13: *"the initiator exemption extends to
    // participationStatus (pause) in initiateSyncSession, but NEVER overrides
    // syncConsent. Pause is a mood; consent is a contract. A paused initiator
    // joins and can host their own session; an explicitly opted-out initiator
    // gets a LEGIBLE refusal telling them their consent setting blocks it —
    // never a silent re-opt-in, never a silent drop."*
    //
    // The initiator's consent is resolved BEFORE the member loop so the refusal
    // can be returned instead of a session. Inside the loop they would merely be
    // skipped, and the caller would receive "no eligible participants" — the
    // silent drop the decision forbids.
    const initiatorConsentDoc = await db
      .collection("neighborhoods").doc(groupId)
      .collection("members").doc(initiatorUid)
      .collection("settings").doc("syncConsent")
      .get();

    const refuse = (reason: string, message: string) => {
      console.warn(
        `initiateSyncSession: REFUSED for ${initiatorUid} in ${groupId} ` +
          `category=${category} event=${eventId} — ${reason}`
      );
      res.status(200).json({ success: false, reason, category, message });
    };

    const ic = initiatorConsentDoc.data() || {};
    const verdict = initiatorConsentVerdict({
      consentExists: initiatorConsentDoc.exists,
      categoryOptIns: ic.categoryOptIns as Record<string, unknown> | undefined,
      skipNextEventIds: ic.skipNextEventIds,
      category,
      eventId,
    });
    if (!verdict.ok) {
      refuse(verdict.reason, verdict.message);
      return;
    }

    for (const memberDoc of membersSnap.docs) {
      const memberData = memberDoc.data();
      const uid = memberDoc.id;
      const isInitiator = uid === initiatorUid;

      // Check consent — applies to EVERYONE, initiator included. The initiator
      // already passed it above; re-running it here keeps one code path rather
      // than a special case that could drift.
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

      // Participation status check. #71: the initiator is exempt — identity
      // keyed, exactly as #69's fix in applySyncPattern, NOT a relaxed
      // predicate. Every other member's pause semantics are untouched.
      if (memberSkippedForSession(isInitiator, memberData.participationStatus)) {
        console.warn(
          `initiateSyncSession: skipped ${uid} in ${groupId} — ` +
            `participationStatus=${String(memberData.participationStatus)} ` +
            "(not the initiator)"
        );
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
    const hostUid = chooseHost(participants, groupData.creatorUid, initiatorUid);

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

      // #74 — arrayRemove takes the ELEMENT, not an array containing it.
      // `arrayRemove([eventId])` asks Firestore to remove the nested array
      // `[eventId]` from `skipNextEventIds`, which it rejects outright:
      // "Element at index 0 is not a valid array element. Nested arrays are not
      // supported." The #84 family, one call site further on.
      //
      // Latent until 2026-08-13: this loop runs once per participant, and with
      // no participants the batch was empty and never validated. #71 put the
      // paused initiator INTO participants, which is what first reached it —
      // and it throws AFTER `sessionRef.set()`, so the session goes live and
      // the caller still gets a 500.
      batch.update(consentRef, {
        skipNextEventIds: admin.firestore.FieldValue.arrayRemove(eventId),
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
