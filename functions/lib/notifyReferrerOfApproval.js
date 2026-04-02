"use strict";
/**
 * notifyReferrerOfApproval — Firebase Cloud Function
 *
 * Callable function that sends an FCM push notification to a referrer
 * when their referral reward payout has been approved by a dealer/admin.
 *
 * Security: authenticated (caller must be a Firebase Auth user).
 * FCM tokens are looked up server-side — never sent from the client.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:notifyReferrerOfApproval
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
exports.notifyReferrerOfApproval = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
exports.notifyReferrerOfApproval = (0, https_1.onCall)({ maxInstances: 10 }, async (request) => {
    // ── Auth check ─────────────────────────────────────────────────
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be authenticated to send reward notifications.");
    }
    const { payoutId } = request.data;
    if (!payoutId || typeof payoutId !== "string") {
        throw new https_1.HttpsError("invalid-argument", "payoutId is required and must be a string.");
    }
    const db = admin.firestore();
    // 1. Read payout doc
    const payoutDoc = await db.collection("referral_payouts").doc(payoutId).get();
    if (!payoutDoc.exists) {
        throw new https_1.HttpsError("not-found", `Payout ${payoutId} not found.`);
    }
    const payout = payoutDoc.data();
    // 2. Read referrer FCM token
    const userDoc = await db
        .collection("users")
        .doc(payout.referrerUid)
        .get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) {
        firebase_functions_1.logger.info(`notifyReferrerOfApproval: No FCM token for user ${payout.referrerUid}`);
        return { success: false, reason: "no_fcm_token" };
    }
    // 3. Build notification based on reward type
    const isGc = payout.rewardType === "visaGiftCard";
    const amount = `$${payout.rewardAmountUsd}`;
    const title = "Your referral reward is approved";
    const body = isGc
        ? `A ${amount} Visa gift card is on the way for referring ${payout.prospectName}`
        : `${amount} in Nex-Gen credit has been added to your account for referring ${payout.prospectName}`;
    // 4. Send FCM notification
    try {
        await admin.messaging().send({
            token: fcmToken,
            notification: { title, body },
            data: {
                payoutId,
                type: "rewardApproved",
                rewardType: payout.rewardType,
                rewardAmount: String(payout.rewardAmountUsd),
            },
        });
        firebase_functions_1.logger.info(`Reward approval notification sent to ${payout.referrerUid} for payout ${payoutId}`);
    }
    catch (err) {
        firebase_functions_1.logger.error(`notifyReferrerOfApproval: FCM send failed for ${payout.referrerUid}: ${err}`);
    }
    return { success: true };
});
//# sourceMappingURL=notifyReferrerOfApproval.js.map