"use strict";
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
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.initiateSyncSession = void 0;
exports.initiatorConsentVerdict = initiatorConsentVerdict;
exports.memberSkippedForSession = memberSkippedForSession;
exports.chooseHost = chooseHost;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
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
function initiatorConsentVerdict(args) {
    if (!args.consentExists) {
        return {
            ok: false,
            reason: "consent_missing",
            message: `You have no sync consent recorded for "${args.category}", so this ` +
                "session was not started.",
        };
    }
    if (!(args.categoryOptIns || {})[args.category]) {
        return {
            ok: false,
            reason: "consent_blocked",
            message: `Your sync consent for "${args.category}" is off, so this session was ` +
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
function memberSkippedForSession(isInitiator, participationStatus) {
    if (isInitiator)
        return false;
    return participationStatus === "paused" || participationStatus === "optedOut";
}
/**
 * PURE. Host selection, unchanged in rule and now reachable by a paused
 * initiator: they are in `participants`, so the existing preference order can
 * pick them.
 */
function chooseHost(participants, creatorUid, initiatorUid) {
    if (typeof creatorUid === "string" && participants.includes(creatorUid)) {
        return creatorUid;
    }
    if (participants.includes(initiatorUid))
        return initiatorUid;
    return participants[0];
}
exports.initiateSyncSession = (0, https_1.onRequest)({ maxInstances: 10, cors: false }, async (req, res) => {
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
    let decoded;
    try {
        decoded = await admin.auth().verifyIdToken(idToken);
    }
    catch (err) {
        console.warn("initiateSyncSession: token verification failed", err);
        res.status(401).json({ error: "Invalid or expired ID token" });
        return;
    }
    // ── Body parsing (accept both shapes) ─────────────────────────────
    const rawBody = (req.body ?? {});
    const envelope = (rawBody.data !== undefined
        ? rawBody.data
        : rawBody);
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
    const groupData = groupDoc.data();
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
    const eventData = eventDoc.data();
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
    const participants = [];
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
    const refuse = (reason, message) => {
        console.warn(`initiateSyncSession: REFUSED for ${initiatorUid} in ${groupId} ` +
            `category=${category} event=${eventId} — ${reason}`);
        res.status(200).json({ success: false, reason, category, message });
    };
    const ic = initiatorConsentDoc.data() || {};
    const verdict = initiatorConsentVerdict({
        consentExists: initiatorConsentDoc.exists,
        categoryOptIns: ic.categoryOptIns,
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
        if (!consentDoc.exists)
            continue;
        const consent = consentDoc.data();
        // Category opt-in check
        const optIns = consent.categoryOptIns || {};
        if (!optIns[category])
            continue;
        // Skip-next check
        const skipIds = consent.skipNextEventIds || [];
        if (skipIds.includes(eventId))
            continue;
        // Participation status check. #71: the initiator is exempt — identity
        // keyed, exactly as #69's fix in applySyncPattern, NOT a relaxed
        // predicate. Every other member's pause semantics are untouched.
        if (memberSkippedForSession(isInitiator, memberData.participationStatus)) {
            console.warn(`initiateSyncSession: skipped ${uid} in ${groupId} — ` +
                `participationStatus=${String(memberData.participationStatus)} ` +
                "(not the initiator)");
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
        batch.update(consentRef, {
            skipNextEventIds: admin.firestore.FieldValue.arrayRemove([eventId]),
        });
    }
    await batch.commit();
    // ── Send FCM notifications ────────────────────────────────────────
    const tokens = [];
    for (const uid of participants) {
        if (uid === initiatorUid)
            continue; // Skip the initiator
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
                        priority: "high",
                    },
                    priority: "high",
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
        }
        catch (err) {
            console.warn("FCM notification failed:", err);
        }
    }
    console.log(`Session ${sessionRef.id} created for event ${eventId} ` +
        `with ${participants.length} participants`);
    res.status(200).json({
        success: true,
        sessionId: sessionRef.id,
        participantCount: participants.length,
        hostUid,
    });
});
//# sourceMappingURL=initiateSyncSession.js.map