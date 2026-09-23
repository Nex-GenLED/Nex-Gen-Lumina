/**
 * assignReferralCode — Firebase Cloud Function
 *
 * Firestore onCreate trigger for /users/{uid}.
 * Generates a unique 8-char referral code (LUM-XXXX) and writes it to:
 *   - /users/{uid}/referralCode   (user's own doc)
 *   - /referral_codes/{code}      (reverse-lookup for redemption)
 *
 * Collision-safe: retries up to 5 times if the generated code already exists.
 *
 * WHO GETS A CODE (residential-path-audit-2026-09-23 §3.4, §9.2.2)
 *   Only real accounts. 46 of 72 production codes had been burned on
 *   anonymous and staff PIN sessions, because the trigger fires for every
 *   users/{uid} create and the FCM token store creates a stub document for
 *   every non-anonymous sign-in — including staff custom-token sessions.
 *   The gate is decided from FIREBASE AUTH, not from document fields: the
 *   created document is usually that stub and carries no profile key to
 *   decide on.
 *     • staff_* uids            → skip (deterministic mintStaffToken uids)
 *     • no Auth record          → skip
 *     • anonymous (no email, no provider) → skip
 *     • anything else           → assign
 *   A customer whose first document is a stub still gets a code; the
 *   healUserProfile trigger repairs the stub independently.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:assignReferralCode
 */
import * as admin from "firebase-admin";
import { AuthUserLike } from "./authIdentity";
export type ReferralSkipReason = "staff_uid" | "auth_missing" | "anonymous";
export type ReferralGate = {
    assign: true;
} | {
    assign: false;
    reason: ReferralSkipReason;
};
/** Pure decision from the uid and its Auth record (null = no record). */
export declare function referralCodeGate(uid: string, authUser: AuthUserLike | null): ReferralGate;
export interface ReferralDeps {
    db: admin.firestore.Firestore;
    getAuthUser: (uid: string) => Promise<AuthUserLike | null>;
}
export type ReferralResult = {
    assigned: string;
} | {
    assigned: null;
    reason: ReferralSkipReason | "exhausted";
};
/**
 * The trigger body, exported so tests can drive it directly.
 */
export declare function runAssignReferralCode(uid: string, deps?: Partial<ReferralDeps>): Promise<ReferralResult>;
export declare const assignReferralCode: import("firebase-functions/core").CloudFunction<import("firebase-functions/v2/firestore").FirestoreEvent<import("firebase-functions/v2/firestore").QueryDocumentSnapshot | undefined, {
    uid: string;
}>>;
