"use strict";
/**
 * endSyncSession — Firebase Cloud Function
 *
 * Called by the background service to end an active sync session.
 * Handles the 30-second dissolution warning, marks session as completed,
 * and sends FCM notifications to all participants.
 *
 * Transport: onRequest (raw HTTPS) with manual ID-token verification.
 *
 * Request body — accepts BOTH `{data: {...}}` (legacy callable-shape) and
 * flat shapes. Returns a flat 200 body — no `{result:}` wrapping.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:endSyncSession
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
exports.endSyncSession = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
exports.endSyncSession = (0, https_1.onRequest)({ maxInstances: 10, cors: false }, async (req, res) => {
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
        console.warn("endSyncSession: token verification failed", err);
        res.status(401).json({ error: "Invalid or expired ID token" });
        return;
    }
    // ── Body parsing (accept both shapes) ─────────────────────────────
    const rawBody = (req.body ?? {});
    const envelope = (rawBody.data !== undefined
        ? rawBody.data
        : rawBody);
    const { groupId, sessionId, initiatorUid } = envelope;
    if (!groupId || !sessionId || !initiatorUid) {
        res.status(400).json({
            error: "Missing required fields: groupId, sessionId, initiatorUid.",
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
    // ── Get session ──────────────────────────────────────────────────
    const sessionRef = db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("syncSessions")
        .doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
        res.status(404).json({ error: "Session not found." });
        return;
    }
    const sessionData = sessionDoc.data();
    if (sessionData.status === "completed" || sessionData.status === "cancelled") {
        res
            .status(200)
            .json({ success: true, message: "Session already ended." });
        return;
    }
    const participants = sessionData.activeParticipantUids || [];
    // ── Mark session as ending (30s warning) ─────────────────────────
    await sessionRef.update({
        status: "ending",
    });
    // Send "ending" notification to participants
    const endingTokens = await _collectTokens(db, groupId, participants, initiatorUid);
    if (endingTokens.length > 0) {
        try {
            await admin.messaging().sendEachForMulticast({
                tokens: endingTokens,
                notification: {
                    title: "Sync Ending",
                    body: "Sync session is wrapping up...",
                },
                data: {
                    type: "sessionEnding",
                    groupId,
                    sessionId,
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
                            alert: { title: "Sync Ending", body: "Sync session is wrapping up..." },
                            sound: "default",
                        },
                    },
                },
            });
        }
        catch (err) {
            console.warn("FCM ending notification failed:", err);
        }
    }
    // ── Wait 30 seconds, then complete ───────────────────────────────
    // Cloud Functions have a max execution time of 540s, 30s is fine.
    await new Promise((resolve) => setTimeout(resolve, 30000));
    // ── Complete session ─────────────────────────────────────────────
    await sessionRef.update({
        status: "completed",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Get event name for notification
    const eventDoc = await db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("syncEvents")
        .doc(sessionData.syncEventId)
        .get();
    const eventName = eventDoc.data()?.name || "Sync event";
    // Send "ended" notification
    const endedTokens = await _collectTokens(db, groupId, participants, initiatorUid);
    if (endedTokens.length > 0) {
        try {
            await admin.messaging().sendEachForMulticast({
                tokens: endedTokens,
                notification: {
                    title: "Sync Ended",
                    body: `${eventName} sync ended — your lights are back on your schedule.`,
                },
                data: {
                    type: "sessionEnded",
                    groupId,
                    sessionId,
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
                                title: "Sync Ended",
                                body: `${eventName} sync ended — your lights are back on your schedule.`,
                            },
                            sound: "default",
                        },
                    },
                },
            });
        }
        catch (err) {
            console.warn("FCM ended notification failed:", err);
        }
    }
    console.log(`Session ${sessionId} completed for group ${groupId}`);
    res.status(200).json({
        success: true,
        sessionId,
        participantCount: participants.length,
    });
});
// ── Helper ───────────────────────────────────────────────────────────────
async function _collectTokens(db, groupId, participants, excludeUid) {
    const tokens = [];
    for (const uid of participants) {
        if (uid === excludeUid)
            continue;
        try {
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
        catch (err) {
            // Skip this participant
        }
    }
    return tokens;
}
//# sourceMappingURL=endSyncSession.js.map