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
exports.isMemberSkipped = isMemberSkipped;
exports.buildFanoutCommandDoc = buildFanoutCommandDoc;
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
    const { payload, initiatorUid, groupId, sessionId, source, controllerIds, fanout, } = envelope;
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
    // ── Slice 1: flag-gated ad-hoc fanout (default OFF) ───────────────
    // ONLY the foreground ad-hoc caller sets fanout:true. When that AND the
    // flag are on AND a groupId is present, fan the command out to EVERY
    // consenting crew member's own command queue (admin SDK) so only the
    // initiator needs the app open. Anything else (no fanout flag = background
    // self-apply callers, no groupId = Game Day personal mode, flag off) →
    // falls through to the unchanged self-only path below, byte-identical to
    // pre-Slice-1. The flag is read ONLY on the fanout-requested path so the
    // high-frequency background callers incur zero extra read. Membership was
    // already verified above.
    if (fanout === true && groupId && groupId.length > 0) {
        const fanoutEnabled = await readSyncFanoutEnabled(db);
        if (fanoutEnabled) {
            const fan = await fanoutToCrew(db, {
                groupId,
                initiatorUid,
                payloadString: JSON.stringify(payload),
                sessionId: sessionId || "",
                source: source || "sync_fanout",
            });
            res.status(200).json({ ok: true, ...fan });
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
// ─── Slice 1 fanout helpers ──────────────────────────────────────────────
/**
 * PURE. A crew member in these states is NOT commanded by an ad-hoc fanout
 * (explicit pause / opt-out). NOTE: `isParticipating` is deliberately NOT
 * checked here — it is a runtime apply-state that is false on every resting
 * member, so gating START on it would skip the entire crew and the fanout
 * would no-op. (isParticipating is a STOP-path gate, a later slice.)
 * Exported for unit verification.
 */
function isMemberSkipped(participationStatus) {
    return participationStatus === "paused" || participationStatus === "optedOut";
}
/**
 * PURE. The exact command-doc body the autonomous bridge already executes —
 * byte-compatible with the self-only path above and the app's
 * CloudRelayRepository writer. The server `createdAt` timestamp is added by the
 * caller (it can't be a pure value). Exported for unit verification.
 */
function buildFanoutCommandDoc(args) {
    return {
        type: "applyJson",
        payload: args.payloadString,
        controllerId: args.controllerId,
        controllerIp: args.controllerIp,
        webhookUrl: args.webhookUrl,
        status: "pending",
        source: args.source,
        initiatorUid: args.initiatorUid,
        sessionId: args.sessionId,
    };
}
/** Read the fanout feature flag (config/sync_fanout.enabled). Default false. */
async function readSyncFanoutEnabled(db) {
    try {
        const doc = await db.collection("config").doc("sync_fanout").get();
        return doc.exists && doc.data()?.enabled === true;
    }
    catch (err) {
        console.warn("applySyncPattern: fanout flag read failed; defaulting OFF", err);
        return false;
    }
}
/**
 * Resolve a member's controller targets.
 *   1. Denormalized member.controllerId[] (Slice 1) → write one target per id
 *      with controllerIp:"" so the bridge self-resolves its paired WLED IP. No
 *      cross-collection read — this is the denormalization win for the common
 *      bridge-mode install.
 *   2. Else LAZY-read users/{uid}/controllers live → {id, ip} (covers existing
 *      members with no controllerId[] yet, and Webhook-Mode members that need a
 *      real IP).
 *   3. Else the legacy single controllerIp on the member doc.
 *   4. Else a single {id:"", ip:""} — the bridge self-resolves from "".
 */
async function resolveMemberTargets(db, memberUid, memberData) {
    const denormIds = Array.isArray(memberData.controllerId)
        ? memberData.controllerId.filter((x) => typeof x === "string" && x.length > 0)
        : [];
    if (denormIds.length > 0) {
        return denormIds.map((id) => ({ id, ip: "" }));
    }
    try {
        const snap = await db
            .collection("users")
            .doc(memberUid)
            .collection("controllers")
            .get();
        const out = [];
        snap.forEach((d) => out.push({ id: d.id, ip: d.data().ip || "" }));
        if (out.length > 0)
            return out;
    }
    catch (err) {
        console.warn(`applySyncPattern: controller read failed for ${memberUid}`, err);
    }
    const legacyIp = memberData.controllerIp || "";
    if (legacyIp.length > 0)
        return [{ id: "", ip: legacyIp }];
    return [{ id: "", ip: "" }];
}
/**
 * Fan an ad-hoc sync out to every consenting crew member's own command queue.
 * Membership is read LIVE here (never a cached/passed-in list) so a member who
 * just left is already gone. Per-member work is isolated with allSettled — one
 * member's read/write failure must not abort the crew.
 */
async function fanoutToCrew(db, args) {
    const membersSnap = await db
        .collection("neighborhoods")
        .doc(args.groupId)
        .collection("members")
        .get();
    let memberCount = 0;
    let skipped = 0;
    const tasks = [];
    membersSnap.forEach((memberDoc) => {
        const data = memberDoc.data();
        if (isMemberSkipped(data.participationStatus)) {
            skipped++;
            return;
        }
        memberCount++;
        const memberUid = memberDoc.id;
        tasks.push((async () => {
            const targets = await resolveMemberTargets(db, memberUid, data);
            // Webhook-Mode members need their forward URL; bridge-mode members get
            // null. One get per member — acceptable at crew scale.
            let webhookUrl = null;
            try {
                const u = await db.collection("users").doc(memberUid).get();
                webhookUrl = u.data()?.webhookUrl || null;
            }
            catch (_) {
                /* ignore — null webhook = bridge mode */
            }
            const commandsRef = db
                .collection("users")
                .doc(memberUid)
                .collection("commands");
            let written = 0;
            for (const t of targets) {
                await commandsRef.add({
                    ...buildFanoutCommandDoc({
                        payloadString: args.payloadString,
                        controllerId: t.id,
                        controllerIp: t.ip,
                        webhookUrl,
                        source: args.source,
                        initiatorUid: args.initiatorUid,
                        sessionId: args.sessionId,
                    }),
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                written++;
            }
            return written;
        })());
    });
    const results = await Promise.allSettled(tasks);
    let commandCount = 0;
    for (const r of results) {
        if (r.status === "fulfilled") {
            commandCount += r.value;
        }
        else {
            console.warn("applySyncPattern: member fanout failed", r.reason);
        }
    }
    console.log(`applySyncPattern FANOUT: group=${args.groupId} members=${memberCount} ` +
        `commands=${commandCount} skipped=${skipped}`);
    return { memberCount, commandCount, skipped };
}
//# sourceMappingURL=applySyncPattern.js.map