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
import * as admin from "firebase-admin";
export declare const applySyncPattern: import("firebase-functions/v2/https").HttpsFunction;
/**
 * PURE. A crew member in these states is NOT commanded by an ad-hoc fanout
 * (explicit pause / opt-out). NOTE: `isParticipating` is deliberately NOT
 * checked here — it is a runtime apply-state that is false on every resting
 * member, so gating START on it would skip the entire crew and the fanout
 * would no-op. (isParticipating is a STOP-path gate, a later slice.)
 * Exported for unit verification.
 */
export declare function isMemberSkipped(participationStatus: unknown): boolean;
/**
 * PURE. The exact command-doc body the autonomous bridge already executes —
 * byte-compatible with the self-only path above and the app's
 * CloudRelayRepository writer. The server `createdAt` timestamp is added by the
 * caller (it can't be a pure value). Exported for unit verification.
 */
export declare function buildFanoutCommandDoc(args: {
    payloadString: string;
    controllerId: string;
    controllerIp: string;
    webhookUrl: string | null;
    source: string;
    initiatorUid: string;
    sessionId: string;
}): Record<string, unknown>;
/**
 * SYNC-1 server-side mutual-membership verification. A fanout may only target a
 * uid that is a VERIFIED member of the crew — present in the group's
 * `memberUids[]` (which the self-join flow maintains for both the group doc and
 * the member subcollection). A member SUBCOLLECTION doc that is NOT backed by
 * memberUids membership is not a mutual/self-consented member (e.g. an orphaned
 * or out-of-band doc) and must NOT receive a fanout write to its command queue.
 * Pure + exported for unit verification (mirrors evaluateRateLimit).
 */
export declare function verifyFanoutTarget(targetUid: string, groupMemberUids: string[]): {
    ok: boolean;
    reason?: string;
};
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
export declare function fanoutToCrew(db: admin.firestore.Firestore, args: {
    groupId: string;
    initiatorUid: string;
    payloadString: string;
    sessionId: string;
    source: string;
}): Promise<{
    memberCount: number;
    commandCount: number;
    skipped: number;
}>;
/** Per-group ceiling: max ad-hoc fanouts committed in any rolling 60s. */
export declare const GROUP_CEILING_PER_MIN = 5;
/** Per-initiator cooldown: minimum ms between one initiator's fanouts. */
export declare const INITIATOR_COOLDOWN_MS = 18000;
/** Rolling window for the per-group ceiling. */
export declare const RATE_WINDOW_MS = 60000;
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
export declare function evaluateRateLimit(state: RateState, initiatorUid: string, nowMs: number): {
    allowed: boolean;
    retryAfterMs: number;
    windowStarts: number[];
    lastByInitiator: Record<string, number>;
};
/**
 * TRANSACTIONAL check-and-reserve against
 * neighborhoods/{groupId}/rate_limits/state. Runs inside db.runTransaction so
 * the function's concurrent instances serialize on this single doc — two calls
 * that would both pass a naive check can't both commit; Firestore aborts and
 * retries one against the other's committed state. Single-doc read+write → no
 * composite index. Admin-SDK only (new subcollection has no client rule →
 * default-deny for clients).
 */
export declare function reserveFanoutSlot(db: admin.firestore.Firestore, groupId: string, initiatorUid: string, nowMs: number): Promise<{
    allowed: boolean;
    retryAfterMs: number;
}>;
export {};
