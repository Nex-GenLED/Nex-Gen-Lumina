"use strict";
/**
 * enforceScheduleLimits — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 19:00 UTC. Scans every user document and trims the
 * `schedules` array to a maximum of MAX_SCHEDULES entries, keeping the most
 * recently appended items.
 *
 * Server-side defense-in-depth for the same cap enforced at write-time by
 * SchedulesNotifier.addAll on the client. Catches users on older app builds
 * that don't enforce the cap, and any drift that the client-side dedup
 * doesn't catch.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:enforceScheduleLimits
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
exports.enforceScheduleLimits = void 0;
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = __importStar(require("firebase-admin"));
// admin.initializeApp() is called in index.js — do not call again here.
const MAX_SCHEDULES = 50;
exports.enforceScheduleLimits = (0, scheduler_1.onSchedule)({
    schedule: "every sunday 19:00",
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "256MiB",
}, async () => {
    const db = admin.firestore();
    const usersSnap = await db.collection("users").get();
    console.log(`[enforceScheduleLimits] scanning ${usersSnap.size} users, ` +
        `cap=${MAX_SCHEDULES}`);
    let trimmedCount = 0;
    let totalRemoved = 0;
    const errors = [];
    for (const userDoc of usersSnap.docs) {
        const data = userDoc.data();
        const schedules = data.schedules;
        if (!Array.isArray(schedules))
            continue;
        if (schedules.length <= MAX_SCHEDULES)
            continue;
        const trimmed = schedules.slice(-MAX_SCHEDULES);
        const removed = schedules.length - trimmed.length;
        try {
            await userDoc.ref.update({ schedules: trimmed });
            console.log(`[enforceScheduleLimits] ${userDoc.id}: ` +
                `${schedules.length} → ${trimmed.length} (removed ${removed})`);
            trimmedCount++;
            totalRemoved += removed;
        }
        catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(`[enforceScheduleLimits] FAILED ${userDoc.id}: ${msg}`);
            errors.push({ userId: userDoc.id, error: msg });
        }
    }
    console.log(`[enforceScheduleLimits] done — usersTrimmed=${trimmedCount}, ` +
        `totalEntriesRemoved=${totalRemoved}, errors=${errors.length}`);
    if (errors.length > 0) {
        console.error(`[enforceScheduleLimits] errors:`, JSON.stringify(errors));
    }
});
//# sourceMappingURL=enforceScheduleLimits.js.map