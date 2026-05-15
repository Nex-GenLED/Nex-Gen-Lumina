"use strict";
/**
 * applySyncPattern — Firebase Cloud Function
 *
 * Server-side fanout of WLED payloads to a host's controllers via the
 * existing bridge command queue. Used by the Neighborhood Sync background
 * worker and the Game Day autopilot background worker — both run in an
 * isolate that has no Firebase SDK, so they delegate fanout to this
 * function via raw HTTPS.
 *
 * The function only enqueues RemoteCommand documents at
 * /users/{initiatorUid}/commands. The existing executeWledCommand trigger
 * (functions/index.js) handles routing:
 *   - ESP32 Bridge Mode (no webhookUrl): bridge polls the queue locally.
 *   - Webhook Mode (webhookUrl set):     trigger POSTs to the user's URL.
 *
 * Transport: onRequest (raw HTTPS) with manual ID-token verification.
 * Background isolates cannot use the Firebase Functions SDK, so they POST
 * directly to this URL with `Authorization: Bearer <idToken>`.
 *
 * Request body — accepts BOTH shapes for backward compatibility:
 *   - { data: { ...envelope } }  (legacy callable-shape; current clients)
 *   - { ...envelope }            (flat; new clients)
 *
 * Envelope:
 *   {
 *     payload:        Record<string, unknown>,  // WLED JSON
 *     initiatorUid:   string,                   // host UID — commands are
 *                                               // written under this user
 *     groupId?:       string,                   // when present, validates
 *                                               // initiator is a member
 *     sessionId?:     string,                   // tagged on each command
 *     source?:        string,                   // "sync_fanout" | "game_day"
 *     controllerIds?: string[]                  // restrict targets; default
 *                                               // is all of host's controllers
 *   }
 *
 * Returns (flat 200 body): { ok: true, commandCount: N }
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:applySyncPattern
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
exports.applySyncPattern = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
exports.applySyncPattern = (0, https_1.onRequest)({ maxInstances: 10, cors: false }, async (req, res) => {
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
        console.warn("applySyncPattern: token verification failed", err);
        res.status(401).json({ error: "Invalid or expired ID token" });
        return;
    }
    // ── Body parsing (accept both `{data: ...}` and flat) ─────────────
    const rawBody = (req.body ?? {});
    const envelope = (rawBody.data !== undefined
        ? rawBody.data
        : rawBody);
    const { payload, initiatorUid, groupId, sessionId, source, controllerIds, } = envelope;
    if (!initiatorUid) {
        res
            .status(400)
            .json({ error: "Missing required field: initiatorUid." });
        return;
    }
    if (!payload || typeof payload !== "object") {
        res.status(400).json({
            error: "Missing or invalid field: payload (expected JSON object).",
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
    // ── Group membership gate (only when groupId is provided) ─────────
    // Sync fanouts must originate from a member of the named group.
    // Game Day fanouts pass no groupId and target only the caller's own
    // controllers — that's safe because we never write to another user's
    // command queue.
    if (groupId && groupId.length > 0) {
        const memberDoc = await db
            .collection("neighborhoods")
            .doc(groupId)
            .collection("members")
            .doc(initiatorUid)
            .get();
        if (!memberDoc.exists) {
            res.status(403).json({
                error: "Initiator is not a member of the named sync group.",
            });
            return;
        }
    }
    // ── Resolve host's webhook URL (for Webhook Mode users) ───────────
    const userDoc = await db.collection("users").doc(initiatorUid).get();
    const webhookUrl = userDoc.data()?.webhookUrl || "";
    // ── Resolve target controllers ────────────────────────────────────
    const controllersRef = db
        .collection("users")
        .doc(initiatorUid)
        .collection("controllers");
    const targets = [];
    if (controllerIds && controllerIds.length > 0) {
        const docs = await Promise.all(controllerIds.map((id) => controllersRef.doc(id).get()));
        for (const doc of docs) {
            if (!doc.exists)
                continue;
            const ip = doc.data()?.ip;
            if (ip && ip.length > 0) {
                targets.push({ id: doc.id, ip });
            }
        }
    }
    else {
        const snap = await controllersRef.get();
        for (const doc of snap.docs) {
            const ip = doc.data().ip;
            if (ip && ip.length > 0) {
                targets.push({ id: doc.id, ip });
            }
        }
    }
    if (targets.length === 0) {
        console.warn(`applySyncPattern: no target controllers for ${initiatorUid}`);
        res.status(200).json({ ok: true, commandCount: 0 });
        return;
    }
    // ── Enqueue one RemoteCommand per controller ──────────────────────
    // payload stored as a JSON string (matches the Dart-side convention
    // documented in functions/index.js executeWledCommand handler — the
    // iOS Firestore SDK crashes on deeply-nested arrays).
    const payloadString = JSON.stringify(payload);
    const commandsRef = db
        .collection("users")
        .doc(initiatorUid)
        .collection("commands");
    const writes = targets.map((t) => commandsRef.add({
        type: "applyJson",
        payload: payloadString,
        controllerId: t.id,
        controllerIp: t.ip,
        webhookUrl: webhookUrl || null,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        source: source || "sync_fanout",
        sessionId: sessionId || "",
    }));
    await Promise.all(writes);
    console.log(`applySyncPattern: enqueued ${targets.length} commands for ` +
        `${initiatorUid} (source=${source || "sync_fanout"}, ` +
        `groupId=${groupId || "-"}, sessionId=${sessionId || "-"})`);
    res.status(200).json({ ok: true, commandCount: targets.length });
});
//# sourceMappingURL=applySyncPattern.js.map