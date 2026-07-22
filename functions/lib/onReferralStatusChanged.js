"use strict";
/**
 * onReferralStatusChanged — Firebase Cloud Function
 *
 * Firestore onUpdate trigger for /users/{referrerUid}/referrals/{referralId}.
 * Sends a push notification to the referring user when a referral's status
 * advances through the pipeline.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:onReferralStatusChanged
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
exports.onReferralStatusChanged = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
const logger = __importStar(require("firebase-functions/logger"));
// admin.initializeApp() is called in index.js — do not call again here.
const NOTIFICATION_MAP = {
    confirmed: {
        title: "Referral confirmed",
        body: (name) => `${name} signed their estimate — install is scheduled`,
    },
    installing: {
        title: "Install day is here",
        body: (name) => `${name}'s Nex-Gen system is being installed today`,
    },
    installed: {
        title: "Your neighbor is live",
        body: (name) => `A Nex-Gen account has been created for ${name}`,
    },
    paid: {
        title: "Your referral reward is ready",
        body: (name) => `Your reward for referring ${name} has been issued`,
    },
};
exports.onReferralStatusChanged = (0, firestore_1.onDocumentUpdated)({
    document: "users/{referrerUid}/referrals/{referralId}",
    region: "us-central1",
}, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const oldStatus = before.status;
    const newStatus = after.status;
    // Only fire when status actually changed
    if (!newStatus || oldStatus === newStatus)
        return;
    // Skip "lead" — handled separately by lead capture
    const notification = NOTIFICATION_MAP[newStatus];
    if (!notification)
        return;
    const referrerUid = event.params.referrerUid;
    const referralId = event.params.referralId;
    const name = after.name || "Your referral";
    // Read the referrer's FCM token
    const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(referrerUid)
        .get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) {
        logger.info(`No FCM token for referrer ${referrerUid} — skipping notification`);
        return;
    }
    try {
        await admin.messaging().send({
            token: fcmToken,
            notification: {
                title: notification.title,
                body: notification.body(name),
            },
            data: {
                referralId,
                newStatus,
                referrerUid,
            },
            android: {
                notification: {
                    channelId: "referral_updates",
                    priority: "high",
                    defaultSound: true,
                },
                priority: "high",
            },
            apns: {
                payload: {
                    aps: {
                        alert: {
                            title: notification.title,
                            body: notification.body(name),
                        },
                        sound: "default",
                        badge: 1,
                    },
                },
            },
        });
        logger.info(`Sent "${newStatus}" notification for referral ${referralId} to ${referrerUid}`);
    }
    catch (err) {
        logger.error(`Failed to send referral notification to ${referrerUid}:`, err);
    }
});
//# sourceMappingURL=onReferralStatusChanged.js.map