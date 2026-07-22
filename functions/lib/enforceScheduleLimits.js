"use strict";
/**
 * enforceScheduleLimits — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 19:00 UTC. Scans every user document and trims the
 * `schedules` array to a maximum of MAX_SCHEDULES entries, keeping the most
 * recently appended items.
 *
 * Server-side defense-in-depth for the same cap enforced at write-time by
 * SchedulesNotifier.addAll on the client
 * (lib/features/schedule/schedule_providers.dart:461). Catches users on older
 * app builds that don't enforce the cap, and any drift the client-side dedup
 * doesn't catch.
 *
 * TWO correctness properties this file guarantees:
 *
 *   1. TRANSACTIONAL. The array read-trim-write runs inside a per-user
 *      runTransaction. This is the LAST blind whole-array overwrite in the
 *      system — a third writer the client-side per-uid lock cannot see (it
 *      runs in this Cloud Functions process). Wrapping it in a transaction
 *      means a concurrent client remove/update can't be silently clobbered:
 *      the trim re-reads inside the txn and Firestore retries on conflict.
 *
 *   2. MIGRATION-AWARE. If (and only if) trimming occurred, the identical trim
 *      is applied to the /users/{uid}/schedules subcollection via batched
 *      deletes of the removed ids (translated through the same scheduleSubDocId
 *      contract the client uses). This keeps both shapes convergent during the
 *      array→subcollection dual-write window. Users with no subcollection docs
 *      yet just no-op the deletes.
 *
 * Idempotent (a second run finds length <= cap and does nothing); users
 * without a `schedules` array field are skipped.
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
const scheduleMigrationShared_1 = require("./scheduleMigrationShared");
// admin.initializeApp() is called in index.js — do not call again here.
// Firestore batch limit is 500; keep headroom.
const DELETE_BATCH_SIZE = 450;
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
        `cap=${scheduleMigrationShared_1.MAX_SCHEDULES}`);
    let trimmedCount = 0;
    let totalRemoved = 0;
    let subDocsDeleted = 0;
    const errors = [];
    for (const userDoc of usersSnap.docs) {
        // Cheap pre-filter to avoid a transaction for the overwhelming majority
        // of users who are within the cap. The transaction re-reads and
        // re-checks authoritatively, so this is just an optimization.
        const preSchedules = userDoc.data().schedules;
        if (!Array.isArray(preSchedules))
            continue;
        if (preSchedules.length <= scheduleMigrationShared_1.MAX_SCHEDULES)
            continue;
        const userRef = userDoc.ref;
        try {
            // ── 1. Transactional array trim ─────────────────────────────
            const removedIds = await db.runTransaction(async (txn) => {
                const snap = await txn.get(userRef);
                const schedules = snap.get("schedules");
                const plan = (0, scheduleMigrationShared_1.planScheduleTrim)(schedules, scheduleMigrationShared_1.MAX_SCHEDULES);
                if (!plan.trimmed)
                    return [];
                txn.update(userRef, { schedules: plan.kept });
                return plan.removedIds;
            });
            if (removedIds.length === 0)
                continue; // raced away; nothing to do
            trimmedCount++;
            totalRemoved += removedIds.length;
            console.log(`[enforceScheduleLimits] ${userDoc.id}: trimmed ${removedIds.length} ` +
                `entr${removedIds.length === 1 ? "y" : "ies"}`);
            // ── 2. Mirror the trim to the subcollection ─────────────────
            const schedulesCol = userRef.collection("schedules");
            for (let i = 0; i < removedIds.length; i += DELETE_BATCH_SIZE) {
                const batch = db.batch();
                for (const rawId of removedIds.slice(i, i + DELETE_BATCH_SIZE)) {
                    batch.delete(schedulesCol.doc((0, scheduleMigrationShared_1.scheduleSubDocId)(rawId)));
                }
                await batch.commit();
                subDocsDeleted += Math.min(DELETE_BATCH_SIZE, removedIds.length - i);
            }
        }
        catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(`[enforceScheduleLimits] FAILED ${userDoc.id}: ${msg}`);
            errors.push({ userId: userDoc.id, error: msg });
        }
    }
    console.log(`[enforceScheduleLimits] done — usersTrimmed=${trimmedCount}, ` +
        `totalEntriesRemoved=${totalRemoved}, ` +
        `subDocsDeleted=${subDocsDeleted}, errors=${errors.length}`);
    if (errors.length > 0) {
        console.error(`[enforceScheduleLimits] errors:`, JSON.stringify(errors));
    }
});
//# sourceMappingURL=enforceScheduleLimits.js.map