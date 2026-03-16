"use strict";
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
exports.triggerSyncFailover = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
exports.triggerSyncFailover = (0, https_1.onCall)({ maxInstances: 10 }, async (request) => {
    const { groupId, eventId, failedHostUid, gameId } = request.data;
    if (!groupId || !eventId || !failedHostUid) {
        throw new https_1.HttpsError("invalid-argument", "Missing required fields: groupId, eventId, failedHostUid.");
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
        throw new https_1.HttpsError("not-found", "Group not found.");
    }
    const memberUids = groupDoc.data()?.memberUids ?? [];
    let backupHostUid = null;
    let backupToken = null;
    // Find an eligible member who isn't the failed host
    for (const uid of memberUids) {
        if (uid === failedHostUid)
            continue;
        const memberDoc = await db
            .collection("neighborhoods")
            .doc(groupId)
            .collection("members")
            .doc(uid)
            .get();
        if (!memberDoc.exists)
            continue;
        const data = memberDoc.data();
        // Check consent
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
        console.log(`Failover: silent push sent to backup host ${backupHostUid} ` +
            `for event ${eventId} in group ${groupId}`);
        return {
            success: true,
            backupHostUid,
            message: "Silent push sent to backup host.",
        };
    }
    catch (err) {
        console.error("Failover FCM send failed:", err);
        throw new https_1.HttpsError("internal", "Failed to send failover push.");
    }
});
//# sourceMappingURL=triggerSyncFailover.js.map