/**
 * joinNeighborhood — F-3 fix. Server-side crew join.
 *
 * WHY THIS EXISTS
 * Joining used to be a pure client operation: the app queried
 * `/neighborhoods where inviteCode == <typed code>`, then appended its own uid
 * to that group's `memberUids` and wrote its own `members/{uid}` doc. Two rules
 * carried that: an open group read (`request.auth != null`) and an update clause
 * accepting self-insertion into `memberUids`, commented "enforced app-side".
 * Neither is enforcement. Consequences (audited as F-3, P0, in
 * audit/COMPLIANCE_AND_SECURITY.md):
 *   • the open read exposed every crew's `streetName`, `latitude`, `longitude`
 *     and `inviteCode` to any authenticated — including anonymous — token;
 *   • self-insertion let any caller join any crew WITHOUT a code at all, which
 *     satisfied isGroupMemberLookup() and unlocked that crew's commands /
 *     schedules / syncEvents;
 *   • it also went around SYNC-1: `verifyFanoutTarget` checks that a fanout
 *     target is in `memberUids[]`, and a self-joined attacker is in there
 *     legitimately. Light control was held shut only by
 *     `config/sync_fanout.enabled == false`.
 *
 * So the invite code has to be checked somewhere the client cannot reach, and
 * membership has to be written by that same authority. This callable is that
 * authority: it runs with the admin SDK (rules do not apply to it), and the
 * rules now deny the client both the cross-tenant read and the self-insert.
 *
 * TWO JOIN SHAPES, deliberately:
 *   • `inviteCode` (private crews) — the code is resolved HERE. The client
 *     never reads a group it does not belong to, so it cannot harvest codes.
 *   • `groupId` alone (public crews) — the discovery list comes from the
 *     /neighborhood_public projection, which carries no invite code by design.
 *     A code-free join is allowed ONLY when the group is `isPublic == true`.
 *
 * Deployment (Tyler gates — NOT deployed by the session that wrote this):
 *   cd functions && npm run build
 *   firebase deploy --only functions:joinNeighborhood
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ── Policy constants ───────────────────────────────────────────────────────
// Crew ceiling. There is no `maxMembers` field on the group model, so the cap
// is a server policy rather than per-group config. Chosen to be well above any
// real street (the census on 2026-08-12 found a max of 2 members) while still
// bounding a fanout: applySyncPattern writes one command per member, so this
// is also the per-fanout write ceiling.
export const MAX_CREW_SIZE = 24;

// Rate limiting mirrors the SYNC-2 anti-strobe envelope (INITIATOR_COOLDOWN_MS
// 18s / GROUP_CEILING_PER_MIN 5 per RATE_WINDOW_MS 60s) so the two server
// entry points into this feature share one policy shape.
//
// The dimension is different on purpose, though: SYNC-2 limits PER GROUP,
// because strobing is a property of a group's lights. Join attempts are limited
// PER CALLER, because the thing being protected is the invite-code space and a
// brute-forcer supplies no groupId at all — it rotates codes. Per-group would
// not see those attempts as related.
//
// Brute-force margin: codes are 6 chars from a 32-symbol alphabet
// (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, confusables omitted) = 32^6 ≈ 1.07e9.
// The binding limb for a sequential attacker is the COOLDOWN, not the ceiling:
// one attempt per 18s is ~1.75M/year, so a single live code expects ~600 years
// to hit. The limiter is what makes the code a credential rather than a speed
// bump.
//
// The two limbs deliberately do NOT overlap. Five attempts spaced by an 18s
// cooldown span 72s, which is already outside the 60s window, so the trim drops
// the oldest and a sequential caller can never reach the ceiling. The ceiling
// covers what the cooldown cannot see — a CONCURRENT burst whose requests all
// read the same state before any of them writes. That is why the call site
// wraps this in a transaction, and both directions are asserted in
// test/unit/joinNeighborhood.test.js.
export const JOIN_COOLDOWN_MS = 18_000;
export const JOIN_CEILING_PER_WINDOW = 5;
export const JOIN_RATE_WINDOW_MS = 60_000;

/** Collection holding per-caller join attempt state. Admin-written only; it has
 * no rules block, so it is default-denied to every client. */
export const JOIN_RATE_LIMIT_COLLECTION = "join_rate_limits";

// ── Pure helpers (exported for unit verification, mirroring SYNC-1/SYNC-2) ──

/**
 * Normalize a submitted invite code. Codes are generated uppercase from a
 * 32-symbol alphabet; users type them with stray case and whitespace.
 * Returns "" for anything that cannot be a code, so callers have a single
 * falsy check instead of scattered type guards.
 */
export function normalizeInviteCode(raw: unknown): string {
  if (typeof raw !== "string") return "";
  const trimmed = raw.trim().toUpperCase();
  // Codes are exactly 6 chars from the generator's alphabet. Rejecting the
  // shape here means a malformed code costs no Firestore query — it cannot be
  // used to probe, and it still consumes a rate-limit slot at the call site.
  if (!/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/.test(trimmed)) return "";
  return trimmed;
}

export interface JoinRateState {
  attempts?: number[];
  lastAttemptMs?: number;
}

export interface RateDecision {
  allowed: boolean;
  reason?: "cooldown" | "ceiling";
  retryAfterMs?: number;
  nextState?: JoinRateState;
}

/**
 * Pure rate decision for one caller. Mirrors `evaluateRateLimit` in
 * applySyncPattern.ts — same two-limb shape (cooldown, then rolling ceiling),
 * same trim-the-window behavior so state cannot grow without bound.
 */
export function evaluateJoinRateLimit(
  state: JoinRateState | undefined,
  nowMs: number
): RateDecision {
  const s = state ?? {};
  const cutoff = nowMs - JOIN_RATE_WINDOW_MS;
  const trimmed = (s.attempts ?? []).filter(
    (t) => typeof t === "number" && t > cutoff
  );

  const sinceLast =
    typeof s.lastAttemptMs === "number" ? nowMs - s.lastAttemptMs : Infinity;
  if (sinceLast < JOIN_COOLDOWN_MS) {
    return {
      allowed: false,
      reason: "cooldown",
      retryAfterMs: JOIN_COOLDOWN_MS - sinceLast,
    };
  }

  if (trimmed.length >= JOIN_CEILING_PER_WINDOW) {
    const earliest = Math.min(...trimmed);
    return {
      allowed: false,
      reason: "ceiling",
      retryAfterMs: Math.max(0, earliest + JOIN_RATE_WINDOW_MS - nowMs),
    };
  }

  return {
    allowed: true,
    nextState: { attempts: [...trimmed, nowMs], lastAttemptMs: nowMs },
  };
}

export interface JoinGroupFacts {
  exists: boolean;
  inviteCode?: unknown;
  isPublic?: unknown;
  memberUids?: unknown;
}

export type JoinRefusal =
  | "group_not_found"
  | "invalid_code"
  | "code_required"
  | "crew_full";

export interface JoinDecision {
  ok: boolean;
  alreadyMember?: boolean;
  reason?: JoinRefusal;
}

/**
 * Pure join decision. Separated from the I/O so every branch is unit-testable
 * without an emulator.
 *
 * Idempotence: an existing member returns ok with `alreadyMember`, matching the
 * old client behavior (re-entering your own crew's code was a no-op that
 * returned the group, and the rejoin shortcut in the UI depends on that).
 */
export function decideJoin(args: {
  group: JoinGroupFacts;
  callerUid: string;
  submittedCode: string;
  memberDocCount: number;
}): JoinDecision {
  const { group, callerUid, submittedCode, memberDocCount } = args;

  if (!group.exists) return { ok: false, reason: "group_not_found" };

  const memberUids = Array.isArray(group.memberUids)
    ? group.memberUids.filter((x): x is string => typeof x === "string")
    : [];
  if (memberUids.includes(callerUid)) {
    return { ok: true, alreadyMember: true };
  }

  if (submittedCode) {
    const actual =
      typeof group.inviteCode === "string" ? group.inviteCode.toUpperCase() : "";
    // A group with no code on it can never be matched by code — otherwise an
    // empty stored code would match an empty submission.
    if (actual === "" || actual !== submittedCode) {
      return { ok: false, reason: "invalid_code" };
    }
  } else if (group.isPublic !== true) {
    // Code-free joins are the public-discovery path only.
    return { ok: false, reason: "code_required" };
  }

  // Count against member DOCS, not memberUids: the docs are what a fanout
  // iterates, and the two can drift (SYNC-1 exists because they did).
  if (memberDocCount >= MAX_CREW_SIZE) {
    return { ok: false, reason: "crew_full" };
  }

  return { ok: true };
}

// ── Callable ───────────────────────────────────────────────────────────────

interface JoinRequest {
  groupId?: unknown;
  inviteCode?: unknown;
  displayName?: unknown;
  controllerId?: unknown;
}

/**
 * Map a refusal to a client-visible error. `invalid_code` and `group_not_found`
 * BOTH surface as `not-found` with one generic message: distinguishing them
 * would turn this callable into an oracle for "does this code exist", which is
 * the thing the rate limit is protecting.
 */
function refusalToError(reason: JoinRefusal): HttpsError {
  switch (reason) {
    case "crew_full":
      return new HttpsError(
        "resource-exhausted",
        `This crew is full (${MAX_CREW_SIZE} homes).`
      );
    case "code_required":
      return new HttpsError(
        "permission-denied",
        "This crew is private — an invite code is required."
      );
    case "group_not_found":
    case "invalid_code":
    default:
      return new HttpsError(
        "not-found",
        "No crew found for that invite code."
      );
  }
}

export const joinNeighborhood = onCall(
  { region: "us-central1", maxInstances: 10 },
  async (request: CallableRequest<JoinRequest>) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Sign-in required to join a crew.");
    }

    const db = admin.firestore();
    const nowMs = Date.now();

    const submittedCode = normalizeInviteCode(request.data?.inviteCode);
    const rawGroupId = request.data?.groupId;
    const groupId = typeof rawGroupId === "string" ? rawGroupId.trim() : "";

    if (!submittedCode && !groupId) {
      // Not rate-limited: this is a malformed call, not an attempt.
      throw new HttpsError(
        "invalid-argument",
        "Provide an invite code or a public crew id."
      );
    }

    // ── Rate limit (per caller) ─────────────────────────────────────────
    // Transactional so a caller firing concurrent requests cannot slip past
    // the ceiling — the same reason reserveFanoutSlot is a transaction.
    const rlRef = db.collection(JOIN_RATE_LIMIT_COLLECTION).doc(callerUid);
    const decision = await db.runTransaction(async (tx) => {
      const snap = await tx.get(rlRef);
      const d = evaluateJoinRateLimit(
        snap.exists ? (snap.data() as JoinRateState) : undefined,
        nowMs
      );
      if (d.allowed && d.nextState) tx.set(rlRef, d.nextState);
      return d;
    });
    if (!decision.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many join attempts. Try again in a moment.",
        { retryAfterMs: decision.retryAfterMs }
      );
    }

    // ── Resolve the group ───────────────────────────────────────────────
    // By code when one was given (the client cannot do this lookup any more),
    // else by the public-projection id.
    let groupRef: admin.firestore.DocumentReference;
    if (submittedCode) {
      const q = await db
        .collection("neighborhoods")
        .where("inviteCode", "==", submittedCode)
        .limit(1)
        .get();
      if (q.empty) throw refusalToError("invalid_code");
      groupRef = q.docs[0].ref;
    } else {
      groupRef = db.collection("neighborhoods").doc(groupId);
    }

    const groupSnap = await groupRef.get();
    const membersSnap = await groupRef.collection("members").get();

    const verdict = decideJoin({
      group: {
        exists: groupSnap.exists,
        inviteCode: groupSnap.data()?.inviteCode,
        isPublic: groupSnap.data()?.isPublic,
        memberUids: groupSnap.data()?.memberUids,
      },
      callerUid,
      submittedCode,
      memberDocCount: membersSnap.size,
    });

    if (!verdict.ok) throw refusalToError(verdict.reason!);

    const groupData = groupSnap.data() ?? {};

    if (!verdict.alreadyMember) {
      // ── Write membership ─────────────────────────────────────────────
      // Both docs in ONE batch. The old client path wrote memberUids and
      // members/{uid} as two independent operations, so a failure between them
      // left a uid in memberUids with no member doc — a shape SYNC-1 then had
      // to defend against. One batch, one outcome.
      const positionIndex = membersSnap.size;
      const displayName =
        typeof request.data?.displayName === "string" &&
        request.data.displayName.trim() !== ""
          ? request.data.displayName.trim()
          : `Home #${positionIndex + 1}`;
      const controllerId = Array.isArray(request.data?.controllerId)
        ? (request.data.controllerId as unknown[]).filter(
            (x): x is string => typeof x === "string"
          )
        : [];

      const batch = db.batch();
      batch.update(groupRef, {
        memberUids: admin.firestore.FieldValue.arrayUnion(callerUid),
      });
      batch.set(groupRef.collection("members").doc(callerUid), {
        displayName,
        positionIndex,
        // #78 — NULL, not a placeholder. 300 was the per-channel pixel cap
        // reused as a default and 15.0 m is 49.2 ft, the figure customers saw
        // in the UI. Neither was ever measured, and because they LOOKED like
        // data no consumer could tell a real 300-pixel home from a default.
        // Null says "not measured", which is the truth until the geometry
        // layer computes it from the member's own bus data (D2).
        ledCount: null,
        rooflineMeters: null,
        rooflineDirection: "leftToRight",
        controllerIp: null,
        controllerId,
        isOnline: true,
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        participationStatus: "active",
        optedOutScheduleIds: [],
        // isParticipating is a SYNC-SESSION flag, not a membership flag — the
        // sync engine sets it true when a sync starts. false on join is correct
        // (the creator's own doc is false too); see 002b0b7's ruled-out list.
        isParticipating: false,
      });
      await batch.commit();

      console.log(
        `joinNeighborhood: uid=${callerUid.slice(0, 8)} joined ` +
          `group=${groupRef.id} via=${submittedCode ? "code" : "public"} ` +
          `position=${positionIndex}`
      );
    }

    // Return the full group. The caller is a member now, so they are entitled
    // to it — and returning it keeps the client's post-join sequence (which
    // needs the group id and name) a single round trip.
    const memberUids = Array.isArray(groupData.memberUids)
      ? (groupData.memberUids as unknown[]).filter(
          (x): x is string => typeof x === "string"
        )
      : [];

    return {
      ok: true,
      alreadyMember: verdict.alreadyMember === true,
      group: {
        id: groupRef.id,
        name: groupData.name ?? "",
        description: groupData.description ?? null,
        streetName: groupData.streetName ?? null,
        city: groupData.city ?? null,
        isPublic: groupData.isPublic === true,
        inviteCode: groupData.inviteCode ?? "",
        creatorUid: groupData.creatorUid ?? "",
        createdAtMs:
          groupData.createdAt instanceof admin.firestore.Timestamp
            ? groupData.createdAt.toMillis()
            : null,
        memberUids: verdict.alreadyMember
          ? memberUids
          : [...memberUids, callerUid],
        isActive: groupData.isActive === true,
        activePatternId: groupData.activePatternId ?? null,
        activePatternName: groupData.activePatternName ?? null,
        activeSyncType: groupData.activeSyncType ?? null,
        latitude: groupData.latitude ?? null,
        longitude: groupData.longitude ?? null,
      },
    };
  }
);
