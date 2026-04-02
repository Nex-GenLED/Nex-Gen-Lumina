"use strict";
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
exports.notifyDay2Team = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
exports.notifyDay2Team = (0, https_1.onCall)({ maxInstances: 10 }, async (request) => {
    // ── Auth check ─────────────────────────────────────────────────
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be authenticated to notify the install team.");
    }
    const { jobId } = request.data;
    if (!jobId || typeof jobId !== "string") {
        throw new https_1.HttpsError("invalid-argument", "jobId is required and must be a string.");
    }
    const db = admin.firestore();
    // 1. Read the job doc
    const jobDoc = await db.collection("sales_jobs").doc(jobId).get();
    if (!jobDoc.exists) {
        throw new https_1.HttpsError("not-found", `Sales job ${jobId} not found.`);
    }
    const jobData = jobDoc.data();
    const dealerCode = jobData.dealerCode;
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
        firebase_functions_1.logger.info(`notifyDay2Team: No active installers for dealer ${dealerCode}`);
        return { success: true, notifiedCount: 0 };
    }
    // 3. Collect FCM tokens from installer user accounts
    const tokens = [];
    for (const installerDoc of installerSnap.docs) {
        const installerData = installerDoc.data();
        const linkedUid = installerData.linkedUid;
        if (!linkedUid) {
            firebase_functions_1.logger.info(`notifyDay2Team: Installer ${installerDoc.id} has no linkedUid, skipping`);
            continue;
        }
        const userDoc = await db.collection("users").doc(linkedUid).get();
        if (!userDoc.exists) {
            firebase_functions_1.logger.info(`notifyDay2Team: User ${linkedUid} not found, skipping`);
            continue;
        }
        const fcmToken = userDoc.data()?.fcmToken;
        if (fcmToken) {
            tokens.push(fcmToken);
        }
        else {
            firebase_functions_1.logger.info(`notifyDay2Team: User ${linkedUid} has no FCM token, skipping`);
        }
    }
    if (tokens.length === 0) {
        firebase_functions_1.logger.info(`notifyDay2Team: No FCM tokens found for dealer ${dealerCode}`);
        return { success: true, notifiedCount: 0 };
    }
    // 4. Send FCM notifications
    const message = {
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
        firebase_functions_1.logger.info(`notifyDay2Team: Sent ${successCount}/${tokens.length} notifications for job ${jobId}`);
        // Log individual failures
        response.responses.forEach((resp, idx) => {
            if (!resp.success) {
                firebase_functions_1.logger.warn(`notifyDay2Team: Failed to send to token ${idx}: ${resp.error?.message}`);
            }
        });
    }
    catch (err) {
        firebase_functions_1.logger.error(`notifyDay2Team: FCM send failed: ${err}`);
    }
    // 5. Update job doc
    await db.collection("sales_jobs").doc(jobId).update({
        day2Notified: true,
        day2NotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, notifiedCount: successCount };
});
//# sourceMappingURL=notifyDay2Team.js.map