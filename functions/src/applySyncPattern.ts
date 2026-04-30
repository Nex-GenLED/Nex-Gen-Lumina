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
 * Request data envelope:
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
 * Returns: { ok: true, commandCount: N }
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:applySyncPattern
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface ApplyPatternRequest {
  payload: Record<string, unknown>;
  initiatorUid: string;
  groupId?: string;
  sessionId?: string;
  source?: string;
  controllerIds?: string[];
}

export const applySyncPattern = onCall(
  { maxInstances: 10 },
  async (request) => {
    const {
      payload,
      initiatorUid,
      groupId,
      sessionId,
      source,
      controllerIds,
    } = request.data as ApplyPatternRequest;

    if (!initiatorUid) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required field: initiatorUid."
      );
    }
    if (!payload || typeof payload !== "object") {
      throw new HttpsError(
        "invalid-argument",
        "Missing or invalid field: payload (expected JSON object)."
      );
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
        throw new HttpsError(
          "permission-denied",
          "Initiator is not a member of the named sync group."
        );
      }
    }

    // ── Resolve host's webhook URL (for Webhook Mode users) ───────────
    const userDoc = await db.collection("users").doc(initiatorUid).get();
    const webhookUrl = (userDoc.data()?.webhookUrl as string | undefined) || "";

    // ── Resolve target controllers ────────────────────────────────────
    const controllersRef = db
      .collection("users")
      .doc(initiatorUid)
      .collection("controllers");

    let targets: { id: string; ip: string }[] = [];

    if (controllerIds && controllerIds.length > 0) {
      const docs = await Promise.all(
        controllerIds.map((id) => controllersRef.doc(id).get())
      );
      for (const doc of docs) {
        if (!doc.exists) continue;
        const ip = doc.data()?.ip as string | undefined;
        if (ip && ip.length > 0) {
          targets.push({ id: doc.id, ip });
        }
      }
    } else {
      const snap = await controllersRef.get();
      for (const doc of snap.docs) {
        const ip = doc.data().ip as string | undefined;
        if (ip && ip.length > 0) {
          targets.push({ id: doc.id, ip });
        }
      }
    }

    if (targets.length === 0) {
      console.warn(
        `applySyncPattern: no target controllers for ${initiatorUid}`
      );
      return { ok: true, commandCount: 0 };
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

    const writes = targets.map((t) =>
      commandsRef.add({
        type: "applyJson",
        payload: payloadString,
        controllerId: t.id,
        controllerIp: t.ip,
        webhookUrl: webhookUrl || null,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        source: source || "sync_fanout",
        sessionId: sessionId || "",
      })
    );

    await Promise.all(writes);

    console.log(
      `applySyncPattern: enqueued ${targets.length} commands for ` +
        `${initiatorUid} (source=${source || "sync_fanout"}, ` +
        `groupId=${groupId || "-"}, sessionId=${sessionId || "-"})`
    );

    return { ok: true, commandCount: targets.length };
  }
);
