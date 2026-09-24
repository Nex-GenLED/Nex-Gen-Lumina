/**
 * authIdentity — "who is this uid, really?" helpers shared by the
 * users/{uid} onCreate triggers (healUserProfile, assignReferralCode).
 *
 * Both triggers must decide from FIREBASE AUTH, not from document fields.
 * The document that fires onCreate is very often a stub written by the FCM
 * token store ({fcmToken, fcmTokenUpdatedAt}) before any profile field
 * exists (residential-path-audit-2026-09-23 §1.1 A2b, §1.3, §3.1), so the
 * document says nothing about whether the uid is a customer, an anonymous
 * session, or a staff PIN session.
 *
 *   • staff_* uids are minted deterministically by mintStaffToken
 *     (staffAuth.ts:541, `staff_${mode}_${pin}`). They are custom-token
 *     sessions with no email and no providerData, so by Auth record alone
 *     they look exactly like an anonymous user. The uid prefix is the
 *     discriminator, and it needs no Auth round-trip.
 *   • anonymous sessions (signInAnonymously) have no email and no providers.
 *   • a customer has an email (password provider today; any provider later).
 */

import * as admin from "firebase-admin";

export const STAFF_UID_PREFIX = "staff_";

/**
 * The subset of admin.auth.UserRecord the triggers read. Declared as its
 * own shape so pure-logic unit tests can pass plain objects.
 */
export interface AuthUserLike {
  uid: string;
  email?: string | null;
  displayName?: string | null;
  providerData?: ReadonlyArray<{ providerId: string }>;
  metadata?: { creationTime?: string | null };
  disabled?: boolean;
}

export function isStaffUid(uid: string): boolean {
  return uid.startsWith(STAFF_UID_PREFIX);
}

/** No email and no sign-in provider → an anonymous (or custom-token) session. */
export function isAnonymousAuthUser(user: AuthUserLike): boolean {
  const providers = user.providerData ?? [];
  return !user.email && providers.length === 0;
}

/**
 * Fetches the Auth record for a uid. Returns null when the record does not
 * exist (the audit's "Auth record no longer exists" population, §3.2) so the
 * caller can skip instead of throwing and retrying forever.
 */
export async function lookupAuthUser(uid: string): Promise<AuthUserLike | null> {
  try {
    return await admin.auth().getUser(uid);
  } catch (err: unknown) {
    const code = (err as { code?: string }).code;
    if (code === "auth/user-not-found") return null;
    throw err;
  }
}
