"use strict";
/**
 * assignReferralCode — Firebase Cloud Function
 *
 * Firestore onCreate trigger for /users/{uid}.
 * Generates a unique 8-char referral code (LUM-XXXX) and writes it to:
 *   - /users/{uid}/referralCode   (user's own doc)
 *   - /referral_codes/{code}      (reverse-lookup for redemption)
 *
 * Collision-safe: retries up to 5 times if the generated code already exists.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:assignReferralCode
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
exports.assignReferralCode = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
// admin.initializeApp() is called in index.js — do not call again here.
const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const CODE_LEN = 4;
const MAX_ATTEMPTS = 5;
function generateCode() {
    let result = "";
    for (let i = 0; i < CODE_LEN; i++) {
        result += CHARS.charAt(Math.floor(Math.random() * CHARS.length));
    }
    return `LUM-${result}`;
}
exports.assignReferralCode = (0, firestore_1.onDocumentCreated)({ document: "users/{uid}", region: "us-central1" }, async (event) => {
    const uid = event.params.uid;
    const db = admin.firestore();
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
        const code = generateCode();
        const codeRef = db.collection("referral_codes").doc(code);
        try {
            await db.runTransaction(async (tx) => {
                const existing = await tx.get(codeRef);
                if (existing.exists) {
                    throw new Error("collision");
                }
                tx.set(codeRef, { uid });
                tx.update(db.collection("users").doc(uid), { referralCode: code });
            });
            console.log(`Assigned referral code ${code} to user ${uid}`);
            return;
        }
        catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            if (msg === "collision") {
                console.warn(`Referral code collision on attempt ${attempt + 1}, retrying...`);
                continue;
            }
            console.error(`Failed to assign referral code to ${uid}:`, err);
            throw err;
        }
    }
    console.error(`Exhausted ${MAX_ATTEMPTS} attempts assigning referral code to ${uid}`);
});
//# sourceMappingURL=assignReferralCode.js.map