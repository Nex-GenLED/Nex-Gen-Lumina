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
import * as admin from "firebase-admin";
interface PollRequest {
    groupId?: string;
    fireId?: string;
}
/**
 * PURE. The status a target is REPORTED with. A command still open past the
 * fire's expiry is `no_response` — the bridge never picked it up (or died
 * holding it). The command doc itself is left to the sweeper; this is the
 * fire's view, so the initiator is not kept waiting on a corpse.
 */
export declare function deriveTargetStatus(stored: string, nowMs: number, expiresAtMs: number): string;
export interface FireTargetView {
    key: string;
    uid: string;
    displayName: string;
    controllerId: string;
    route: string;
    status: string;
    reason: string;
    error: string;
    completedAtMs: number | null;
}
export interface FireSummary {
    /** Every house the fire considered, including skipped ones. */
    total: number;
    /** Houses a command was actually written for. */
    commanded: number;
    confirmed: number;
    failed: number;
    waiting: number;
    noResponse: number;
    noBridge: number;
    noAddress: number;
    skipped: number;
    /** True once nothing is still waiting — the fire's outcome is final. */
    settled: boolean;
}
/** PURE. Counts over derived statuses. */
export declare function summarizeFireTargets(statuses: string[]): FireSummary;
export interface FireStatusResponse {
    fireId: string;
    groupId: string;
    createdAtMs: number | null;
    expiresAtMs: number;
    targets: FireTargetView[];
    summary: FireSummary;
}
/**
 * Read the fire, refresh every open target from its command doc, persist what
 * changed, and return the view. Exported so the emulator suite can drive it
 * without the callable wrapper.
 */
export declare function refreshFireStatus(db: admin.firestore.Firestore, groupId: string, fireId: string, nowMs: number): Promise<FireStatusResponse>;
export declare const pollSyncFire: import("firebase-functions/v2/https").CallableFunction<PollRequest, Promise<FireStatusResponse>, unknown>;
export {};
