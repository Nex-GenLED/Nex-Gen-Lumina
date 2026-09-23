"use strict";
/**
 * pollSyncFire — Firebase Cloud Function (callable)
 *
 * The read-back half of a Neighborhood Sync v1 fire. applySyncPattern writes
 * one command per member controller and a fire record at
 * neighborhoods/{groupId}/fires/{fireId}; the bridges then flip their command
 * docs pending → executing → completed/failed, and the sweeper flips a command
 * nobody picked up to expired. None of that is visible to the initiator: a
 * member cannot read another member's users/{uid}/commands, and the fires
 * subcollection has no client rule.
 *
 * This callable is polled by the initiator's app (every ~2 s while it waits,
 * up to the fire's expiry). It reads the open command docs with the admin SDK,
 * mirrors their status into the fire record, and returns a per-house view plus
 * a summary. A command still pending/executing past the fire's expiry is
 * reported `no_response` — the honest state, not "sent".
 *
 * WHY A POLL AND NOT A TRIGGER. An onDocumentUpdated trigger on
 * users/{uid}/commands would fire on every command write fleet-wide to observe
 * a handful of docs per fire; the project already rejected that shape for the
 * health collector (collectControllerHealth.ts:9-19). Polling costs only while
 * an initiator is actually waiting, and only for that fire's targets.
 *
 * Deployment (NOT deployed by the session that wrote this):
 *   cd functions && npm run build
 *   firebase deploy --only functions:pollSyncFire
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
exports.pollSyncFire = void 0;
exports.deriveTargetStatus = deriveTargetStatus;
exports.summarizeFireTargets = summarizeFireTargets;
exports.refreshFireStatus = refreshFireStatus;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
/** Statuses under which a target is still being waited on. */
const OPEN_STATUSES = new Set(["pending", "executing"]);
/**
 * PURE. The status a target is REPORTED with. A command still open past the
 * fire's expiry is `no_response` — the bridge never picked it up (or died
 * holding it). The command doc itself is left to the sweeper; this is the
 * fire's view, so the initiator is not kept waiting on a corpse.
 */
function deriveTargetStatus(stored, nowMs, expiresAtMs) {
    if (OPEN_STATUSES.has(stored) && nowMs > expiresAtMs)
        return "no_response";
    return stored;
}
/** PURE. Counts over derived statuses. */
function summarizeFireTargets(statuses) {
    const s = {
        total: statuses.length,
        commanded: 0,
        confirmed: 0,
        failed: 0,
        waiting: 0,
        noResponse: 0,
        noBridge: 0,
        noAddress: 0,
        skipped: 0,
        settled: true,
    };
    for (const st of statuses) {
        switch (st) {
            case "completed":
                s.commanded++;
                s.confirmed++;
                break;
            case "failed":
            case "timeout":
            case "superseded":
                s.commanded++;
                s.failed++;
                break;
            case "pending":
            case "executing":
                s.commanded++;
                s.waiting++;
                break;
            case "expired":
            case "no_response":
                s.commanded++;
                s.noResponse++;
                break;
            case "no_bridge":
                s.noBridge++;
                break;
            case "no_address":
                s.noAddress++;
                break;
            default:
                // skipped, plan_failed, anything unknown
                s.skipped++;
        }
    }
    s.settled = s.waiting === 0;
    return s;
}
/**
 * Read the fire, refresh every open target from its command doc, persist what
 * changed, and return the view. Exported so the emulator suite can drive it
 * without the callable wrapper.
 */
async function refreshFireStatus(db, groupId, fireId, nowMs) {
    const fireRef = db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("fires")
        .doc(fireId);
    const fireSnap = await fireRef.get();
    if (!fireSnap.exists) {
        throw new https_1.HttpsError("not-found", "No such sync fire.");
    }
    const fire = fireSnap.data() || {};
    const expiresAtRaw = fire.expiresAt;
    const expiresAtMs = expiresAtRaw && typeof expiresAtRaw.toMillis === "function"
        ? expiresAtRaw.toMillis()
        : fire.createdAtMs ?? nowMs;
    const createdAtMs = fire.createdAtMs ?? null;
    const stored = fire.targets || {};
    // Read back every target that is still open and has a command doc.
    const openKeys = Object.keys(stored).filter((k) => OPEN_STATUSES.has(stored[k].status) && !!stored[k].commandPath);
    const updates = {};
    if (openKeys.length > 0) {
        const refs = openKeys.map((k) => db.doc(stored[k].commandPath));
        let docs = [];
        try {
            docs = await db.getAll(...refs);
        }
        catch (err) {
            console.warn(`pollSyncFire: command read-back failed for fire ${fireId}`, err);
        }
        docs.forEach((d, i) => {
            const key = openKeys[i];
            if (!d.exists)
                return;
            const dd = d.data() || {};
            const status = typeof dd.status === "string" ? dd.status : "pending";
            const error = typeof dd.error === "string" ? dd.error : "";
            const completed = dd.completedAt;
            const completedAtMs = completed && typeof completed.toMillis === "function"
                ? completed.toMillis()
                : null;
            if (status !== stored[key].status) {
                stored[key] = { ...stored[key], status, error, completedAtMs };
                updates[`targets.${key}.status`] = status;
                updates[`targets.${key}.error`] = error;
                updates[`targets.${key}.completedAtMs`] = completedAtMs;
            }
        });
    }
    // Derive + persist no_response so the record settles even if nobody polls
    // again after this.
    const views = [];
    for (const key of Object.keys(stored)) {
        const t = stored[key];
        const derived = deriveTargetStatus(t.status, nowMs, expiresAtMs);
        if (derived !== t.status) {
            updates[`targets.${key}.status`] = derived;
            updates[`targets.${key}.error`] =
                "No response before expiry (bridge offline or unreachable at fire time).";
        }
        views.push({
            key,
            uid: t.uid,
            displayName: t.displayName || "",
            controllerId: t.controllerId || "",
            route: t.route || "none",
            status: derived,
            reason: t.reason || "",
            error: derived === t.status ? t.error || "" : String(updates[`targets.${key}.error`]),
            completedAtMs: t.completedAtMs ?? null,
        });
    }
    if (Object.keys(updates).length > 0) {
        try {
            await fireRef.update({
                ...updates,
                lastPolledAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        catch (err) {
            // The view is still correct; only the durable record lags.
            console.warn(`pollSyncFire: fire record update failed for ${fireId}`, err);
        }
    }
    return {
        fireId,
        groupId,
        createdAtMs,
        expiresAtMs,
        targets: views,
        summary: summarizeFireTargets(views.map((v) => v.status)),
    };
}
exports.pollSyncFire = (0, https_1.onCall)({ region: "us-central1", maxInstances: 10 }, async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new https_1.HttpsError("unauthenticated", "Sign-in required.");
    }
    const groupId = typeof request.data?.groupId === "string" ? request.data.groupId.trim() : "";
    const fireId = typeof request.data?.fireId === "string" ? request.data.fireId.trim() : "";
    if (!groupId || !fireId) {
        throw new https_1.HttpsError("invalid-argument", "groupId and fireId are required.");
    }
    const db = admin.firestore();
    // Any verified member of the crew may read a fire's outcome — the same
    // gate applySyncPattern applies to the initiator.
    const memberSnap = await db
        .collection("neighborhoods")
        .doc(groupId)
        .collection("members")
        .doc(callerUid)
        .get();
    if (!memberSnap.exists) {
        throw new https_1.HttpsError("permission-denied", "Not a member of this crew.");
    }
    return refreshFireStatus(db, groupId, fireId, Date.now());
});
//# sourceMappingURL=pollSyncFire.js.map