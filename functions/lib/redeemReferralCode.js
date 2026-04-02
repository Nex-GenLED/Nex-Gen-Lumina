"use strict";
/**
 * redeemReferralCode — Firebase Cloud Function
 *
 * Callable function invoked when a new prospect redeems a referral code.
 * Looks up the referrer via /referral_codes/{code}, then creates a tracking
 * doc under /users/{referrerUid}/referrals with the full pipeline schema.
 *
 * Security: authenticated — the caller must be a Firebase Auth user.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:redeemReferralCode
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
exports.redeemReferralCode = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
exports.redeemReferralCode = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign in to redeem a referral code.");
    }
    const { code, prospectName } = request.data;
    if (!code || typeof code !== "string") {
        throw new https_1.HttpsError("invalid-argument", "A referral code is required.");
    }
    const db = admin.firestore();
    const codeDoc = await db.collection("referral_codes").doc(code.toUpperCase()).get();
    if (!codeDoc.exists) {
        throw new https_1.HttpsError("not-found", "Invalid referral code.");
    }
    const referrerUid = codeDoc.data()?.uid;
    if (referrerUid === request.auth.uid) {
        throw new https_1.HttpsError("invalid-argument", "You cannot redeem your own referral code.");
    }
    const referralRef = db
        .collection("users")
        .doc(referrerUid)
        .collection("referrals")
        .doc();
    await referralRef.set({
        name: prospectName || "Friend",
        status: "lead",
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        status_updated_at: admin.firestore.FieldValue.serverTimestamp(),
        prospect_uid: request.auth.uid,
        job_id: null,
        referral_code: code.toUpperCase(),
    });
    return { success: true, referralId: referralRef.id };
});
//# sourceMappingURL=redeemReferralCode.js.map