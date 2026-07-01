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
