/**
 * initiateSyncSession — Firebase Cloud Function
 *
 * Called by the background service (or foreground app) to create a sync
 * session server-side. This function:
 *   1. Validates the event exists and is enabled
 *   2. Resolves participants from group members with consent checks
 *   3. Determines host (prefers group creator, falls back to initiator)
 *   4. Creates the session document in Firestore
 *   5. Sends FCM notifications to participants
 *   6. Returns the session ID
 *
 * This runs server-side because the background isolate cannot use Riverpod
 * or Firestore listeners — it only has SharedPreferences and HTTP.
 *
 * Transport: onRequest (raw HTTPS) with manual ID-token verification.
 *
 * Request body — accepts BOTH `{data: {...}}` (legacy callable-shape) and
 * flat shapes. Returns a flat 200 body — no callable-protocol `{result:}`
 * wrapping.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:initiateSyncSession
 */
export type InitiatorVerdict = {
    ok: true;
} | {
    ok: false;
    reason: string;
    message: string;
};
/**
 * PURE. May THIS initiator start a session in this category?
 *
 * CONSENT > PAUSE. Pause is a mood; consent is a contract. This function knows
 * only about the contract — `participationStatus` is deliberately not an input,
 * because the initiator is exempt from it and passing it here would invite a
 * future edit to blend the two back together.
 *
 * Three distinct refusals, because the remedies differ: never answered, said no
 * to the category, said skip-this-one.
 */
export declare function initiatorConsentVerdict(args: {
    consentExists: boolean;
    categoryOptIns: Record<string, unknown> | undefined | null;
    skipNextEventIds: unknown;
    category: string;
    eventId: string;
}): InitiatorVerdict;
/**
 * PURE. Is this member dropped for participationStatus?
 *
 * #71: the initiator never is. Identity-keyed, mirroring #69's fix in
 * applySyncPattern — NOT a relaxed predicate, so every other member's pause
 * semantics are byte-identical to before.
 */
export declare function memberSkippedForSession(isInitiator: boolean, participationStatus: unknown): boolean;
/**
 * PURE. Host selection, unchanged in rule and now reachable by a paused
 * initiator: they are in `participants`, so the existing preference order can
 * pick them.
 */
export declare function chooseHost(participants: string[], creatorUid: unknown, initiatorUid: string): string;
export declare const initiateSyncSession: import("firebase-functions/v2/https").HttpsFunction;
