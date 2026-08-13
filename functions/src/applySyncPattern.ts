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
      const policy = await readSyncFanoutPolicy(db);
      const fanoutEnabled = fanoutsForGroup(policy, groupId);
      // LEGIBILITY (#68): a group held back by the allowlist must SAY so. A
      // scoped-out group falls through to the host-only path, which looks
      // identical to the flag being off — and "identical to off" with no reason
      // recorded is exactly how a scoped rollout becomes undiagnosable.
      if (policy.enabled && !fanoutEnabled) {
        console.log(
          `applySyncPattern: fanout SCOPED_OUT for group=${groupId} ` +
            `(allowlist has ${policy.allowlist?.length ?? 0} entr` +
            `${policy.allowlist?.length === 1 ? "y" : "ies"}); ` +
            "host-only path, no crew commands written"
        );
      }
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
 *
 * #70 — A TARGET WITH NO ADDRESS IS BORN FAILED. An empty `controllerIp` used
 * to be written as `status:"pending"`, so the bridge dutifully POSTed to an
 * empty host and reported `ERROR: HTTP -1`. The command is still written —
 * silence would be worse, and the doc is the evidence that a member was
 * *meant* to be commanded — but it is written `failed` with a legible
 * `no_address`, so it is never dispatched and never has to be diagnosed from a
 * transport error. Server-side twin of the harness guard in `0c5fd92`.
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
  // WEBHOOK MODE IS NOT ADDRESSLESS. executeWledCommand (functions/index.js:398)
  // routes on webhookUrl and never reads controllerIp, so a Webhook-Mode member
  // with no IP is perfectly deliverable. Judging on controllerIp alone would
  // have marked every one of them no_address — a fix that broke a working path
  // to repair a broken one.
  const hasIp =
    typeof args.controllerIp === "string" && args.controllerIp.trim().length > 0;
  const hasWebhook =
    typeof args.webhookUrl === "string" && args.webhookUrl.trim().length > 0;
  const deliverable = hasIp || hasWebhook;
  return {
    type: "applyJson",
    payload: args.payloadString,
    controllerId: args.controllerId,
    controllerIp: args.controllerIp,
    webhookUrl: args.webhookUrl,
    status: deliverable ? "pending" : "failed",
    ...(deliverable ? {} : { error: "no_address" }),
    source: args.source,
    initiatorUid: args.initiatorUid,
    sessionId: args.sessionId,
  };
}

/**
 * The fanout policy: globally enabled, or enabled for a named set of groups.
 *
 * `allowlist === null` means "no list" — every group fans out once `enabled` is
 * true. A non-null list enables ONLY those groupIds; every other group falls
 * through to the host-only path exactly as it does when the flag is off.
 *
 * Deliberately the same shape and the same failure directions as the planner's
 * `uid_allowlist` (planGameDayFires). Two scoping mechanisms that behave
 * differently under a typo would be worse than one.
 */
export interface FanoutPolicy {
  enabled: boolean;
  allowlist: string[] | null;
}

export const FANOUT_OFF: FanoutPolicy = { enabled: false, allowlist: null };

/**
 * PURE. Derive the policy from the flag document's data.
 *
 *   doc absent / undefined data   -> OFF
 *   enabled !== true              -> OFF regardless of any allowlist
 *   enabled true, list present    -> fanout for those groupIds ONLY
 *   enabled true, list absent     -> global (the eventual end state)
 *   enabled true, list MALFORMED  -> OFF, loudly
 *
 * MALFORMED IS OFF, NOT GLOBAL. Anyone who wrote `group_allowlist` INTENDED to
 * scope the enable; treating a typo as "global" would turn it into a fleet-wide
 * fanout — light control across every crew — which is the exact opposite of
 * what the author reached for. An empty array is NOT malformed: it is a
 * deliberate "enabled for nobody" and is honoured.
 */
export function fanoutPolicyFrom(
  data: Record<string, unknown> | undefined
): FanoutPolicy {
  if (!data || data.enabled !== true) return FANOUT_OFF;

  const raw = data.group_allowlist;
  if (raw === undefined || raw === null) {
    return { enabled: true, allowlist: null }; // global
  }
  if (!Array.isArray(raw) || raw.some((g) => typeof g !== "string" || g === "")) {
    console.error(
      "applySyncPattern: group_allowlist is MALFORMED (expected string[]); " +
        "refusing to fan out. Fix or remove the field to enable. Value: " +
        JSON.stringify(raw)
    );
    return FANOUT_OFF;
  }
  return { enabled: true, allowlist: raw as string[] };
}

/** True when THIS group may fan out. */
export function fanoutsForGroup(policy: FanoutPolicy, groupId: string): boolean {
  if (!policy.enabled) return false;
  if (policy.allowlist === null) return true;
  return policy.allowlist.includes(groupId);
}

/** Read the fanout policy (config/sync_fanout). Default OFF. */
async function readSyncFanoutPolicy(
  db: admin.firestore.Firestore
): Promise<FanoutPolicy> {
  try {
    const doc = await db.collection("config").doc("sync_fanout").get();
    if (!doc.exists) return FANOUT_OFF;
    return fanoutPolicyFrom(doc.data());
  } catch (err) {
    console.warn(
      "applySyncPattern: fanout flag read failed; defaulting OFF",
      err
    );
    return FANOUT_OFF;
  }
}

/**
 * PURE. Attach a resolved address to each denormalized controller id.
 *
 * An id with no entry in `ipById`, or an entry that is blank, resolves to
 * `ip:""` — which [buildFanoutCommandDoc] then records as a `no_address`
 * failure rather than a pending command. Unknown is preserved as unknown here;
 * this function never invents a fallback address.
 *
 * Exported for unit verification (#70).
 */
export function mergeDenormTargets(
  ids: string[],
  ipById: Record<string, string>,
  factsById: Record<string, ChannelFacts> = {}
): FanoutTarget[] {
  return ids.map((id) => ({
    id,
    ip: (ipById[id] || "").trim(),
    deviceChannelIds: factsById[id]?.deviceChannelIds ?? null,
    participatingChannelIds: factsById[id]?.participatingChannelIds ?? null,
  }));
}

/** #67 — the two published facts a partition needs, per controller. */
export interface ChannelFacts {
  deviceChannelIds: number[] | null;
  participatingChannelIds: number[] | null;
}

export interface FanoutTarget extends ChannelFacts {
  id: string;
  ip: string;
}

/** Clean integer array or null. Never a partial: one bad entry voids the set. */
function intArray(v: unknown): number[] | null {
  if (!Array.isArray(v)) return null;
  const out: number[] = [];
  for (const x of v) {
    if (typeof x !== "number" || !Number.isInteger(x) || x < 0) return null;
    out.push(x);
  }
  return out;
}

/**
 * Resolve a member's controller targets.
 *   1. Denormalized member.controllerId[] (Slice 1) → one target per id, JOINED
 *      against users/{uid}/controllers for each address.
 *   2. Else LAZY-read users/{uid}/controllers live → {id, ip} (covers existing
 *      members with no controllerId[] yet, and Webhook-Mode members that need a
 *      real IP).
 *   3. Else the legacy single controllerIp on the member doc.
 *   4. Else a single {id:"", ip:""}.
 *
 * #70 — WHY BRANCH 1 READS AFTER ALL. It used to return `ip:""` with no
 * cross-collection read, on the documented assumption that "the bridge
 * self-resolves its paired WLED IP". That was the denormalization win, and the
 * bridge does not have that capability: on 2026-08-12 the bench bridge answered
 * `ERROR: HTTP -1` to every such command and the strip never moved. Because
 * this is the NORMAL member shape, it meant no crew fanout had ever reached
 * hardware. The read costs one getAll per member at crew scale — the price of
 * the command being deliverable.
 */
export async function resolveMemberTargets(
  db: admin.firestore.Firestore,
  memberUid: string,
  memberData: admin.firestore.DocumentData
): Promise<FanoutTarget[]> {
  const denormIds = Array.isArray(memberData.controllerId)
    ? (memberData.controllerId as unknown[]).filter(
        (x) => typeof x === "string" && (x as string).length > 0
      )
    : [];
  if (denormIds.length > 0) {
    const ipById: Record<string, string> = {};
    const factsById: Record<string, ChannelFacts> = {};
    try {
      const refs = (denormIds as string[]).map((id) =>
        db.collection("users").doc(memberUid).collection("controllers").doc(id)
      );
      const docs = await db.getAll(...refs);
      for (const d of docs) {
        if (!d.exists) continue;
        const dd = d.data() || {};
        ipById[d.id] = (dd.ip as string) || "";
        // #67 — participation rides along on the read we are already doing.
        // A separate per-target get would double the reads for a fact that
        // lives on the same document.
        factsById[d.id] = {
          deviceChannelIds: intArray(dd.participating_channels_device_ids),
          participatingChannelIds: intArray(dd.participating_channels),
        };
      }
    } catch (err) {
      // Leave ipById empty: every id then resolves no_address, which is
      // recorded and visible. Falling through to the subcollection scan would
      // silently widen the blast radius to controllers the member did not name.
      console.warn(
        `applySyncPattern: address join failed for ${memberUid}`,
        err
      );
    }
    const targets = mergeDenormTargets(denormIds as string[], ipById, factsById);
    const unresolved = targets.filter((t) => t.ip.length === 0);
    if (unresolved.length > 0) {
      console.warn(
        `applySyncPattern: ${unresolved.length}/${targets.length} controller(s) ` +
          `for ${memberUid} have no address — ` +
          `${unresolved.map((t) => t.id).join(",")} (recorded no_address, not dispatched)`
      );
    }
    return targets;
  }

  try {
    const snap = await db
      .collection("users")
      .doc(memberUid)
      .collection("controllers")
      .get();
    const out: FanoutTarget[] = [];
    snap.forEach((d) => {
      const dd = d.data() || {};
      out.push({
        id: d.id,
        ip: (dd.ip as string) || "",
        deviceChannelIds: intArray(dd.participating_channels_device_ids),
        participatingChannelIds: intArray(dd.participating_channels),
      });
    });
    if (out.length > 0) return out;
  } catch (err) {
    console.warn(
      `applySyncPattern: controller read failed for ${memberUid}`,
      err
    );
  }

  const legacyIp = (memberData.controllerIp as string) || "";
  const bare = { deviceChannelIds: null, participatingChannelIds: null };
  if (legacyIp.length > 0) return [{ id: "", ip: legacyIp, ...bare }];
  return [{ id: "", ip: "", ...bare }];
}


/**
 * #67 — partition a SYNC broadcast across a member's full channel set.
 *
 * Tyler's decision, 2026-08-13: fires assert the full partition;
 * non-participating segments get `{id: N, on: false}` ONLY, look preserved.
 * The same principle governs a crew broadcast: a member who excluded their
 * patio must have it go DARK for the event, not merely stay unchanged. Third
 * appearance — unstated segment state is inherited state, and inherited state
 * is a bug.
 *
 * CONSERVATIVE BY CONSTRUCTION. Partitioning only happens for the canonical
 * broadcast shape: exactly one `seg` entry carrying no `id`, which is what the
 * app sends (`{"seg":[{"fx":88,"pal":5,"col":[...]}]}`). Anything else — a
 * multi-segment design, or entries that already name ids — is passed through
 * UNTOUCHED. A caller that has already decided which segments it addresses is
 * not guessing, and overlaying an exclusion set on top of it would fight a
 * deliberate choice. Saved multi-seg designs are exactly that case.
 *
 * Returns the reason when it declines, so "not partitioned" is never silent.
 */
export function partitionBroadcastPayload(args: {
  payloadString: string;
  deviceChannelIds: number[] | null;
  participatingChannelIds: number[] | null;
}): { payloadString: string; partitioned: boolean; reason: string } {
  const pass = (reason: string) => ({
    payloadString: args.payloadString,
    partitioned: false,
    reason,
  });

  const device = args.deviceChannelIds;
  const participating = args.participatingChannelIds;
  if (!Array.isArray(device) || device.length === 0) {
    return pass("partition_unavailable");
  }
  if (!Array.isArray(participating)) {
    return pass("participation_unknown");
  }

  let obj: Record<string, unknown>;
  try {
    obj = JSON.parse(args.payloadString) as Record<string, unknown>;
  } catch (_) {
    return pass("unparseable_payload");
  }
  const seg = obj.seg;
  if (!Array.isArray(seg) || seg.length !== 1) {
    return pass("not_single_segment");
  }
  const design = seg[0];
  if (typeof design !== "object" || design === null) {
    return pass("not_single_segment");
  }
  if ((design as Record<string, unknown>).id !== undefined) {
    return pass("segment_already_addressed");
  }

  const on = new Set(participating);
  const partitioned = device.map((ch) =>
    on.has(ch)
      ? { ...(design as Record<string, unknown>), id: ch, on: true }
      : { id: ch, on: false }
  );
  return {
    payloadString: JSON.stringify({ ...obj, seg: partitioned }),
    partitioned: true,
    reason: "ok",
  };
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
    const memberUid = memberDoc.id;
    // #69 — PAUSE MUTES THE CREW, NOT YOURSELF.
    //
    // Tyler's decision, 2026-08-13: "pause does NOT mute your own broadcast. A
    // paused member who initiates receives their own command; pause continues
    // to mute INCOMING broadcasts."
    //
    // Before this, the fanout arm RETURNS, so the host-only self-write below it
    // never runs when fanout is on — the initiator's own command could only come
    // from this loop, and this loop skipped them for being paused. A paused
    // member pressing broadcast lit the whole crew and not their own house, and
    // only when the flag was on. Found on the first successful two-node run
    // (3/4, 2026-08-12: `members=1 commands=1 skipped=1`).
    //
    // The exemption is deliberately keyed on identity, not on a relaxed
    // predicate: `isMemberSkipped` is unchanged, so every OTHER member's pause
    // semantics are untouched.
    const isInitiator = memberUid === args.initiatorUid;
    if (!isInitiator && isMemberSkipped(data.participationStatus)) {
      skipped++;
      // This branch used to be SILENT. It incremented `skipped` and returned,
      // so the 3/4 run reported `skipped:1` with no reason anywhere and the
      // cause had to be recovered by reading the roster by hand. The sibling
      // branch below has always logged; this one now matches it.
      console.warn(
        `applySyncPattern FANOUT: skipped ${memberUid} in ${args.groupId} — ` +
          `participationStatus=${String(data.participationStatus)} ` +
          "(not the initiator; pause mutes INCOMING broadcasts)"
      );
      return;
    }
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
          // #67 — partition per TARGET, not once for the crew: every member has
          // their own channel count and their own excluded set.
          const part = partitionBroadcastPayload({
            payloadString: args.payloadString,
            deviceChannelIds: t.deviceChannelIds ?? null,
            participatingChannelIds: t.participatingChannelIds ?? null,
          });
          if (!part.partitioned) {
            console.log(
              `applySyncPattern FANOUT: ${memberUid}/${t.id} NOT partitioned ` +
                `— ${part.reason} (excluded channels stay UNCHANGED, not dark)`
            );
          }
          await commandsRef.add({
            ...buildFanoutCommandDoc({
              payloadString: part.payloadString,
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
//
// DELIBERATE ANTI-STROBE POLICY (not arbitrary defaults — do not weaken without
// re-justifying). A crew fanout writes a command to EVERY member's controller;
// unthrottled, rapid re-fanouts would strobe every crew member's lights (a
// photosensitivity/comfort hazard, not just spam). Two independent gates:
//   • per-INITIATOR cooldown 18s — one person can't machine-gun the crew;
//     ~a real "change the scene" cadence, well above a strobe rate.
//   • per-GROUP ceiling 5 per rolling 60s — even multiple initiators together
//     can't drive the crew faster than ~1 change / 12s sustained.
// Both are enforced transactionally in reserveFanoutSlot (concurrent-safe).
// Locked by test/unit/fanoutRateLimit.test.js — changing these values will
// fail that suite on purpose.

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
export async function reserveFanoutSlot(
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
