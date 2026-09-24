/**
 * claimCustomerByEmail — Firebase Cloud Function (callable)
 *
 * Unblocks the installer wizard's "this email already has an account" branch.
 *
 * THE PROBLEM (residential path audit 2026-09-23 §4.3 point 2, §9.1 item 4):
 * when `createUserWithEmailAndPassword` reports `email-already-in-use`, the
 * wizard recovers the customer's uid with a client query scoped
 * `where('dealer_code', == myDealerCode)` — because the /users read rule for a
 * staff session is caller-and-resource scoped on dealer_code, so an unscoped
 * list is denied outright. An account that has NO dealer_code (self-registered,
 * or created by a wizard run that failed after the auth user was made) can
 * therefore never be found, and the install hard-stops with "contact support".
 * Production census: 32 email Auth accounts with no /users document at all, plus
 * self-registered accounts with a profile but no dealer_code.
 *
 * WHY A CALLABLE: the lookup has to go through Firebase Auth by email (the
 * client cannot), and the repair has to write `dealer_code` + the skeleton
 * profile onto a document the installer's session may not be able to read yet.
 * The Admin SDK is the only place that composes.
 *
 * Contract:
 *   request.data: { email: string }
 *   response: ClaimCustomerResult {
 *     uid, email, profileCreated, dealerCodeStamped, dealerCode,
 *     installationRole,
 *   }
 *
 * WHAT IT WILL NOT DO — it never reassigns a dealer_code that is already set to
 * a different dealer. That is customer-stealing, and it is the same transition
 * firestore.rules:388-391 denies on the client (set-when-absent is allowed,
 * reassignment is not). Such a call fails `permission-denied`, which is exactly
 * the "contact support" case the wizard already words correctly.
 *
 * IDEMPOTENT: every write is a merge keyed by the uid. Re-running returns the
 * same uid with profileCreated / dealerCodeStamped false.
 *
 * Deployment (NOT deployed as of 2026-09-23 — client-side branch ships first):
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:claimCustomerByEmail
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

// ── Types ───────────────────────────────────────────────────────────────────

export interface ClaimCustomerResult {
  /** The existing customer's Firebase Auth uid. */
  uid: string;
  email: string;
  /** True when this call wrote the skeleton profile (doc missing or a stub). */
  profileCreated: boolean;
  /** True when this call stamped `dealer_code` for the first time. */
  dealerCodeStamped: boolean;
  /** The dealer_code on the profile after this call. */
  dealerCode: string;
  /** `installation_role` after this call. */
  installationRole: string;
}

/** The slices of firebase-admin this function needs, so tests can fake them. */
export interface ClaimDeps {
  db: {
    collection(path: string): {
      doc(id: string): {
        get(): Promise<{
          exists: boolean;
          data(): Record<string, unknown> | undefined;
        }>;
        set(
          data: Record<string, unknown>,
          options: { merge: boolean }
        ): Promise<unknown>;
      };
    };
  };
  auth: {
    getUserByEmail(email: string): Promise<{
      uid: string;
      email?: string;
      displayName?: string;
      metadata?: { creationTime?: string };
    }>;
  };
  /** Injected so the fake can assert on it without a Firestore sentinel. */
  serverTimestamp: () => unknown;
}

// ── Policy ──────────────────────────────────────────────────────────────────

/**
 * A staff session with a dealerCode, or an admin/owner claim.
 *
 * Deliberately NO bare `request.auth != null` branch: this function can write a
 * dealer_code onto an account the caller does not own, so an
 * any-signed-in-user arm would be a customer-stealing primitive. Mirrors
 * `assertCallerMayActOn` in setAccountProfile.ts.
 *
 * Returns the caller's dealer code (empty for an unscoped admin/owner session).
 */
export function assertStaffMayClaim(params: {
  callerUid: string | undefined;
  token: Record<string, unknown> | undefined;
}): string {
  const { callerUid, token } = params;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Sign-in required");
  }
  const role = (token?.role as string) ?? "";
  if (role === "admin" || role === "owner") {
    return (token?.dealerCode as string) ?? "";
  }
  const dealerCode = (token?.dealerCode as string) ?? "";
  if ((role === "installer" || role === "salesperson") && dealerCode !== "") {
    return dealerCode;
  }
  // Generic message: callers must not be able to probe dealer scoping.
  throw new HttpsError(
    "permission-denied",
    "Not authorized to look up customer accounts"
  );
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Decides what the profile write owes, given the doc as it stands.
 *
 * "Needs a profile" is keyed on `owner_id` being ABSENT, not on the document
 * being absent — a stub written by the FCM token path exists but parses as
 * nothing (audit §1.3 C4b). Pure, so the rule is testable on its own.
 */
export function planProfileRepair(params: {
  existing: Record<string, unknown> | undefined;
  callerDealerCode: string;
}): {
  needsSkeleton: boolean;
  stampDealerCode: boolean;
  existingDealerCode: string;
  conflictingDealerCode: boolean;
} {
  const existing = params.existing ?? {};
  const ownerId = existing.owner_id;
  const needsSkeleton = typeof ownerId !== "string" || ownerId === "";
  const existingDealerCode =
    typeof existing.dealer_code === "string" ? existing.dealer_code : "";
  const caller = params.callerDealerCode;
  // An unscoped admin/owner session (caller empty) stamps nothing and conflicts
  // with nothing — it is only here to repair the profile.
  const conflictingDealerCode =
    caller !== "" && existingDealerCode !== "" && existingDealerCode !== caller;
  const stampDealerCode =
    caller !== "" && existingDealerCode === "" && !conflictingDealerCode;
  return {
    needsSkeleton,
    stampDealerCode,
    existingDealerCode,
    conflictingDealerCode,
  };
}

// ── Core (exported for the unit suite) ──────────────────────────────────────

export async function runClaimCustomerByEmail(params: {
  deps: ClaimDeps;
  callerUid: string | undefined;
  token: Record<string, unknown> | undefined;
  email: unknown;
}): Promise<ClaimCustomerResult> {
  const { deps } = params;
  const callerDealerCode = assertStaffMayClaim({
    callerUid: params.callerUid,
    token: params.token,
  });

  if (typeof params.email !== "string" || !EMAIL_RE.test(params.email.trim())) {
    throw new HttpsError("invalid-argument", "A valid email is required");
  }
  const email = params.email.trim().toLowerCase();

  let authUser;
  try {
    authUser = await deps.auth.getUserByEmail(email);
  } catch {
    // Do not distinguish "no such user" from a lookup failure — an installer
    // typo and a real absence need the same wording either way, and a
    // distinguishable answer turns this into an account-enumeration oracle.
    throw new HttpsError(
      "not-found",
      "No Nex-Gen account exists for that email"
    );
  }

  const userRef = deps.db.collection("users").doc(authUser.uid);
  const snap = await userRef.get();
  const existing = snap.exists ? snap.data() : undefined;

  const plan = planProfileRepair({ existing, callerDealerCode });
  if (plan.conflictingDealerCode) {
    logger.warn("claimCustomerByEmail: refusing cross-dealer claim", {
      uid: authUser.uid,
    });
    throw new HttpsError(
      "permission-denied",
      "That account already belongs to another dealer"
    );
  }

  const now = deps.serverTimestamp();
  const patch: Record<string, unknown> = { updated_at: now };

  if (plan.needsSkeleton) {
    // The exact key set UserModel.fromJson casts non-null, plus the two flags
    // the router reads. Same shape as route_guards.createUnlinkedUserProfile
    // and createCustomerAccount's seed, so a later set(merge) of
    // UserModel.toJson() lands on the same keys instead of forking the doc.
    patch.id = authUser.uid;
    patch.owner_id = authUser.uid;
    patch.email = authUser.email ?? email;
    const displayFrom = authUser.email ?? email;
    patch.display_name =
      authUser.displayName && authUser.displayName !== ""
        ? authUser.displayName
        : displayFrom.split("@")[0];
    // Keep the real signup date when Auth knows it; never overwrite an existing
    // created_at (a stub may already carry one from another writer).
    if (existing?.created_at === undefined) {
      const created = authUser.metadata?.creationTime;
      patch.created_at = created ? new Date(created) : now;
    }
    if (existing?.installation_role === undefined) {
      patch.installation_role = "unlinked";
    }
    if (existing?.welcome_completed === undefined) {
      patch.welcome_completed = false;
    }
  }

  if (plan.stampDealerCode) {
    patch.dealer_code = callerDealerCode;
  }

  await userRef.set(patch, { merge: true });

  const installationRole =
    (typeof existing?.installation_role === "string"
      ? (existing.installation_role as string)
      : undefined) ??
    (patch.installation_role as string | undefined) ??
    "unlinked";

  logger.info("claimCustomerByEmail: claimed", {
    uid: authUser.uid,
    profileCreated: plan.needsSkeleton,
    dealerCodeStamped: plan.stampDealerCode,
  });

  return {
    uid: authUser.uid,
    email,
    profileCreated: plan.needsSkeleton,
    dealerCodeStamped: plan.stampDealerCode,
    dealerCode: plan.stampDealerCode
      ? callerDealerCode
      : plan.existingDealerCode,
    installationRole,
  };
}

// ── Callable ────────────────────────────────────────────────────────────────

export const claimCustomerByEmail = onCall(
  async (req: CallableRequest): Promise<ClaimCustomerResult> => {
    const data = (req.data ?? {}) as Record<string, unknown>;
    return runClaimCustomerByEmail({
      deps: {
        db: admin.firestore() as unknown as ClaimDeps["db"],
        auth: admin.auth() as unknown as ClaimDeps["auth"],
        serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
      },
      callerUid: req.auth?.uid,
      token: req.auth?.token as unknown as Record<string, unknown> | undefined,
      email: data.email,
    });
  }
);
