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

import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface ApplyPatternRequest {
  payload: Record<string, unknown>;
  initiatorUid: string;
  groupId?: string;
  sessionId?: string;
  source?: string;
  controllerIds?: string[];
  // Slice 1: ONLY the foreground ad-hoc "start" caller sets this true. The
  // background self-apply callers (sync_event_background_worker,
  // game_day_autopilot) pass a groupId but NOT fanout, so they keep the
  // self-only path even when the flag is on — preserving the distributed
  // self-apply model and the scheduled path's own syncConsent check
  // (initiateSyncSession). Without this, flipping the flag would make every
  // background self-apply fan out to the whole crew.
  fanout?: boolean;
}

export const applySyncPattern = onRequest(
  { maxInstances: 10, cors: false },
  async (req, res) => {
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
    let decoded: admin.auth.DecodedIdToken;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      console.warn("applySyncPattern: token verification failed", err);
      res.status(401).json({ error: "Invalid or expired ID token" });
      return;
    }

    // ── Body parsing (accept both `{data: ...}` and flat) ─────────────
    const rawBody = (req.body ?? {}) as Record<string, unknown>;
    const envelope: ApplyPatternRequest = (rawBody.data !== undefined
      ? (rawBody.data as ApplyPatternRequest)
      : (rawBody as unknown as ApplyPatternRequest));

    const {
      payload,
      initiatorUid,
      groupId,
      sessionId,
      source,
      controllerIds,
      fanout,
    } = envelope;

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
        // Anti-strobe rate limit (Commit 2). Reserve a slot TRANSACTIONALLY so
        // the function's concurrent instances serialize on the state doc — a
        // per-instance in-memory counter would not. On reject nothing is
        // written (no member docs); the app suppresses its broadcast too.
        const reservation = await reserveFanoutSlot(
          db,
          groupId,
          initiatorUid,
          Date.now()
        );
        if (!reservation.allowed) {
          res.status(200).json({
            ok: false,
            reason: "rate_limited",
            retryAfterMs: reservation.retryAfterMs,
          });
          return;
        }
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
    const webhookUrl = (userDoc.data()?.webhookUrl as string | undefined) || "";

    // ── Resolve target controllers ────────────────────────────────────
    const controllersRef = db
      .collection("users")
      .doc(initiatorUid)
      .collection("controllers");

    const targets: { id: string; ip: string }[] = [];

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

    res.status(200).json({ ok: true, commandCount: targets.length });
  }
);

// ─── Slice 1 fanout helpers ──────────────────────────────────────────────

/**
 * PURE. A crew member in these states is NOT commanded by an ad-hoc fanout
 * (explicit pause / opt-out). NOTE: `isParticipating` is deliberately NOT
 * checked here — it is a runtime apply-state that is false on every resting
 * member, so gating START on it would skip the entire crew and the fanout
 * would no-op. (isParticipating is a STOP-path gate, a later slice.)
 * Exported for unit verification.
 */
export function isMemberSkipped(participationStatus: unknown): boolean {
  return participationStatus === "paused" || participationStatus === "optedOut";
}

/**
 * PURE. The exact command-doc body the autonomous bridge already executes —
 * byte-compatible with the self-only path above and the app's
 * CloudRelayRepository writer. The server `createdAt` timestamp is added by the
 * caller (it can't be a pure value). Exported for unit verification.
 */
export function buildFanoutCommandDoc(args: {
  payloadString: string;
  controllerId: string;
  controllerIp: string;
  webhookUrl: string | null;
  source: string;
  initiatorUid: string;
  sessionId: string;
}): Record<string, unknown> {
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
async function readSyncFanoutEnabled(
  db: admin.firestore.Firestore
): Promise<boolean> {
  try {
    const doc = await db.collection("config").doc("sync_fanout").get();
    return doc.exists && doc.data()?.enabled === true;
  } catch (err) {
    console.warn(
      "applySyncPattern: fanout flag read failed; defaulting OFF",
      err
    );
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
async function resolveMemberTargets(
  db: admin.firestore.Firestore,
  memberUid: string,
  memberData: admin.firestore.DocumentData
): Promise<{ id: string; ip: string }[]> {
  const denormIds = Array.isArray(memberData.controllerId)
    ? (memberData.controllerId as unknown[]).filter(
        (x) => typeof x === "string" && (x as string).length > 0
      )
    : [];
  if (denormIds.length > 0) {
    return (denormIds as string[]).map((id) => ({ id, ip: "" }));
  }

  try {
    const snap = await db
      .collection("users")
      .doc(memberUid)
      .collection("controllers")
      .get();
    const out: { id: string; ip: string }[] = [];
    snap.forEach((d) =>
      out.push({ id: d.id, ip: (d.data().ip as string) || "" })
    );
    if (out.length > 0) return out;
  } catch (err) {
    console.warn(
      `applySyncPattern: controller read failed for ${memberUid}`,
      err
    );
  }

  const legacyIp = (memberData.controllerIp as string) || "";
  if (legacyIp.length > 0) return [{ id: "", ip: legacyIp }];
  return [{ id: "", ip: "" }];
}

/**
 * SYNC-1 server-side mutual-membership verification. A fanout may only target a
 * uid that is a VERIFIED member of the crew — present in the group's
 * `memberUids[]` (which the self-join flow maintains for both the group doc and
 * the member subcollection). A member SUBCOLLECTION doc that is NOT backed by
 * memberUids membership is not a mutual/self-consented member (e.g. an orphaned
 * or out-of-band doc) and must NOT receive a fanout write to its command queue.
 * Pure + exported for unit verification (mirrors evaluateRateLimit).
 */
export function verifyFanoutTarget(
  targetUid: string,
  groupMemberUids: string[]
): { ok: boolean; reason?: string } {
  if (!targetUid || targetUid.length === 0) {
    return { ok: false, reason: "empty_uid" };
  }
  if (!groupMemberUids.includes(targetUid)) {
    return { ok: false, reason: "not_in_group_member_uids" };
  }
  return { ok: true };
}

/**
 * Fan an ad-hoc sync out to every consenting crew member's own command queue.
 * Membership is read LIVE here (never a cached/passed-in list) so a member who
 * just left is already gone. Per-member work is isolated with allSettled — one
 * member's read/write failure must not abort the crew.
 *
 * SYNC-1: each target is verified against the group's memberUids[] via
 * [verifyFanoutTarget] BEFORE any write — a member-subcollection doc alone (e.g.
 * a one-sided/out-of-band insert) is skipped, never fanned out to. Exported for
 * unit verification.
 */
export async function fanoutToCrew(
  db: admin.firestore.Firestore,
  args: {
    groupId: string;
    initiatorUid: string;
    payloadString: string;
    sessionId: string;
    source: string;
  }
): Promise<{ memberCount: number; commandCount: number; skipped: number }> {
  // SYNC-1: the crew's verified roster. A member SUBCOLLECTION doc is only
  // fanned out to if its uid is ALSO in the group's memberUids[] (mutual /
  // self-consented membership). Read once; the members subcollection iteration
  // is cross-checked against it below.
  const groupSnap = await db
    .collection("neighborhoods")
    .doc(args.groupId)
    .get();
  const groupMemberUids: string[] = Array.isArray(groupSnap.data()?.memberUids)
    ? (groupSnap.data()!.memberUids as unknown[]).filter(
        (x): x is string => typeof x === "string"
      )
    : [];

  const membersSnap = await db
    .collection("neighborhoods")
    .doc(args.groupId)
    .collection("members")
    .get();

  let memberCount = 0;
  let skipped = 0;
  const tasks: Promise<number>[] = [];

  membersSnap.forEach((memberDoc) => {
    const data = memberDoc.data();
    if (isMemberSkipped(data.participationStatus)) {
      skipped++;
      return;
    }
    const memberUid = memberDoc.id;
    // SYNC-1: reject any target not mutually verified in memberUids[]. Closes
    // the self-fanout hole — a one-sided/out-of-band member doc never receives a
    // write to its command queue. Structured + logged.
    const verdict = verifyFanoutTarget(memberUid, groupMemberUids);
    if (!verdict.ok) {
      skipped++;
      console.warn(
        `applySyncPattern FANOUT: skipped unverified target ${memberUid} ` +
          `in ${args.groupId} — ${verdict.reason}`
      );
      return;
    }
    memberCount++;
    tasks.push(
      (async () => {
        const targets = await resolveMemberTargets(db, memberUid, data);
        // Webhook-Mode members need their forward URL; bridge-mode members get
        // null. One get per member — acceptable at crew scale.
        let webhookUrl: string | null = null;
        try {
          const u = await db.collection("users").doc(memberUid).get();
          webhookUrl = (u.data()?.webhookUrl as string | undefined) || null;
        } catch (_) {
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
      })()
    );
  });

  const results = await Promise.allSettled(tasks);
  let commandCount = 0;
  for (const r of results) {
    if (r.status === "fulfilled") {
      commandCount += r.value;
    } else {
      console.warn("applySyncPattern: member fanout failed", r.reason);
    }
  }

  console.log(
    `applySyncPattern FANOUT: group=${args.groupId} members=${memberCount} ` +
      `commands=${commandCount} skipped=${skipped}`
  );
  return { memberCount, commandCount, skipped };
}

// ─── Slice 1 Commit 2: anti-strobe rate limit ────────────────────────────

/** Per-group ceiling: max ad-hoc fanouts committed in any rolling 60s. */
export const GROUP_CEILING_PER_MIN = 5;
/** Per-initiator cooldown: minimum ms between one initiator's fanouts. */
export const INITIATOR_COOLDOWN_MS = 18000;
/** Rolling window for the per-group ceiling. */
export const RATE_WINDOW_MS = 60000;

interface RateState {
  windowStarts?: number[];
  lastByInitiator?: Record<string, number>;
}

/**
 * PURE decision + next-state for the rate limiter. Given the current state and
 * `nowMs`, decides whether this initiator's fanout is allowed and returns the
 * state to persist on accept. Exported for unit verification. NOTE: the
 * `windowStarts`/`lastByInitiator` in the returned value are the trimmed/updated
 * values the caller writes ONLY when `allowed` — on reject nothing is written.
 *
 * Checks (reject on either):
 *   • per-initiator cooldown — now - lastByInitiator[uid] < INITIATOR_COOLDOWN_MS
 *   • per-group ceiling      — live windowStarts (last 60s) length >= ceiling
 * retryAfterMs = ms until the failing constraint next permits a fanout.
 */
export function evaluateRateLimit(
  state: RateState,
  initiatorUid: string,
  nowMs: number
): {
  allowed: boolean;
  retryAfterMs: number;
  windowStarts: number[];
  lastByInitiator: Record<string, number>;
} {
  const cutoff = nowMs - RATE_WINDOW_MS;
  const trimmed = (state.windowStarts ?? []).filter((t) => t > cutoff);
  const last = state.lastByInitiator ?? {};

  // Per-initiator cooldown.
  const lastAt = last[initiatorUid] ?? 0;
  const sinceLast = nowMs - lastAt;
  if (sinceLast < INITIATOR_COOLDOWN_MS) {
    return {
      allowed: false,
      retryAfterMs: INITIATOR_COOLDOWN_MS - sinceLast,
      windowStarts: trimmed,
      lastByInitiator: last,
    };
  }

  // Per-group ceiling.
  if (trimmed.length >= GROUP_CEILING_PER_MIN) {
    const earliest = Math.min(...trimmed);
    const retryAfterMs = Math.max(0, earliest + RATE_WINDOW_MS - nowMs);
    return { allowed: false, retryAfterMs, windowStarts: trimmed, lastByInitiator: last };
  }

  // Accept — reserve a slot. Prune lastByInitiator to initiators active within
  // the cooldown window so the map can't grow unbounded (stale entries can't
  // cause a rejection anyway).
  const prunedLast: Record<string, number> = {};
  for (const [uid, t] of Object.entries(last)) {
    if (t > nowMs - INITIATOR_COOLDOWN_MS) prunedLast[uid] = t;
  }
  prunedLast[initiatorUid] = nowMs;

  return {
    allowed: true,
    retryAfterMs: 0,
    windowStarts: [...trimmed, nowMs],
    lastByInitiator: prunedLast,
  };
}

/**
 * TRANSACTIONAL check-and-reserve against
 * neighborhoods/{groupId}/rate_limits/state. Runs inside db.runTransaction so
 * the function's concurrent instances serialize on this single doc — two calls
 * that would both pass a naive check can't both commit; Firestore aborts and
 * retries one against the other's committed state. Single-doc read+write → no
 * composite index. Admin-SDK only (new subcollection has no client rule →
 * default-deny for clients).
 */
async function reserveFanoutSlot(
  db: admin.firestore.Firestore,
  groupId: string,
  initiatorUid: string,
  nowMs: number
): Promise<{ allowed: boolean; retryAfterMs: number }> {
  const ref = db
    .collection("neighborhoods")
    .doc(groupId)
    .collection("rate_limits")
    .doc("state");
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const state: RateState = snap.exists ? (snap.data() as RateState) : {};
    const decision = evaluateRateLimit(state, initiatorUid, nowMs);
    if (!decision.allowed) {
      return { allowed: false, retryAfterMs: decision.retryAfterMs };
    }
    tx.set(
      ref,
      {
        windowStarts: decision.windowStarts,
        lastByInitiator: decision.lastByInitiator,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { allowed: true, retryAfterMs: 0 };
  });
}
