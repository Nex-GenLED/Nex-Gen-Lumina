/**
 * healUserProfile — Firebase Cloud Function
 *
 * Firestore onCreate trigger for /users/{uid}. The server-side closer for the
 * "Path C" sign-in race (residential-path-audit-2026-09-23 §1.3, §9.2.1).
 *
 * THE RACE
 *   On every non-anonymous sign-in two subscribers fire on the same
 *   authStateChanges tick: the FCM token store and the router. The FCM store
 *   does users/{uid}.set({fcmToken, fcmTokenUpdatedAt}, merge) and the rules
 *   (firestore.rules:431-436, `|| request.auth != null`) let it CREATE the
 *   document with no profile keys. The router's lazy skeleton
 *   (route_guards.dart:186 / :261 → createUnlinkedUserProfile) is guarded on
 *   `doc.exists`, so if the FCM write lands first the skeleton is never
 *   written: UserModel.fromJson throws on the missing non-null casts
 *   (user_model.dart:433-439) and the account is a permanent stub.
 *
 * WHAT THIS DOES
 *   When a users/{uid} document is created WITHOUT owner_id and the Firebase
 *   Auth user for that uid has an email, merge the fields UserModel.fromJson
 *   requires (id, owner_id, email, display_name, created_at, updated_at) plus
 *   installation_role:'unlinked', sourced from Auth. This repairs the stub
 *   for every app build already in the field, without a client release.
 *
 * WHAT IT NEVER DOES
 *   • never overwrites a field that is already set (absent/null/'' only);
 *   • never touches anonymous sessions or staff_* PIN sessions;
 *   • never creates a document — a deleted doc is skipped;
 *   • never logs an email or display name.
 *
 * The decision is made from FIREBASE AUTH, not document fields — the created
 * document is usually the FCM stub and says nothing about who the uid is.
 *
 * COORDINATION WITH THE CLIENT SKELETON
 *   route_guards.dart:28-41 writes the same keys with set(merge:true). Both
 *   writers are merges of the same values for id / owner_id / email /
 *   display_name / installation_role, so whichever lands second changes
 *   nothing that matters; only the timestamps differ by writer (Auth creation
 *   time here, serverTimestamp() there). The write runs in a transaction, so a
 *   skeleton that lands between our read and write is seen (owner_id set →
 *   skip) rather than overwritten.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:healUserProfile
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import {
  AuthUserLike,
  isAnonymousAuthUser,
  isStaffUid,
  lookupAuthUser,
} from "./authIdentity";

type Timestamp = admin.firestore.Timestamp;

export const UNLINKED_ROLE = "unlinked";

/** The keys this trigger may merge, in the order UserModel.fromJson reads them. */
export const HEALED_FIELDS = [
  "id",
  "owner_id",
  "email",
  "display_name",
  "created_at",
  "updated_at",
  "installation_role",
] as const;

export type HealSkipReason =
  | "staff_uid"
  | "doc_missing"
  | "already_provisioned"
  | "auth_missing"
  | "anonymous"
  | "no_email";

export type HealPlan =
  | { action: "skip"; reason: HealSkipReason }
  | { action: "heal"; fields: Record<string, unknown> };

/**
 * "Set" for the purpose of never-overwrite. `''` counts as unset because the
 * rules' own provisioning test is `owner_id != ''` (isProvisionedUser,
 * firestore.rules:253) and the client skeleton writes email:'' for a user
 * with no email — an empty string carries no information worth preserving.
 */
export function isSetField(v: unknown): boolean {
  if (v === undefined || v === null) return false;
  if (typeof v === "string" && v.trim() === "") return false;
  return true;
}

/** Auth displayName, else the email's local part (mirrors route_guards.dart:31). */
export function displayNameFor(user: AuthUserLike): string {
  const dn = (user.displayName ?? "").trim();
  if (dn) return dn;
  const local = (user.email ?? "").split("@")[0].trim();
  return local || "User";
}

/** Auth creation time as a Firestore Timestamp; `fallback` when unparseable. */
export function authCreationTimestamp(
  user: AuthUserLike,
  fallback: Timestamp
): Timestamp {
  const raw = user.metadata?.creationTime;
  if (!raw) return fallback;
  const ms = Date.parse(raw);
  if (!Number.isFinite(ms)) return fallback;
  return admin.firestore.Timestamp.fromMillis(ms);
}

/**
 * Pure decision: given the document as it exists (null = deleted), the Auth
 * record (null = none) and "now", return what to merge — or why not.
 */
export function planHeal(
  uid: string,
  existing: Record<string, unknown> | null,
  authUser: AuthUserLike | null,
  now: Timestamp
): HealPlan {
  if (isStaffUid(uid)) return { action: "skip", reason: "staff_uid" };
  if (existing === null) return { action: "skip", reason: "doc_missing" };
  if (isSetField(existing.owner_id)) {
    return { action: "skip", reason: "already_provisioned" };
  }
  if (authUser === null) return { action: "skip", reason: "auth_missing" };
  if (isAnonymousAuthUser(authUser)) return { action: "skip", reason: "anonymous" };
  if (!authUser.email) return { action: "skip", reason: "no_email" };

  const candidate: Record<string, unknown> = {
    id: uid,
    owner_id: uid,
    email: authUser.email,
    display_name: displayNameFor(authUser),
    created_at: authCreationTimestamp(authUser, now),
    updated_at: now,
    installation_role: UNLINKED_ROLE,
  };

  // Merge only: a key that is already set on the document is left alone.
  const fields: Record<string, unknown> = {};
  for (const key of HEALED_FIELDS) {
    if (!isSetField(existing[key])) fields[key] = candidate[key];
  }
  return { action: "heal", fields };
}

export interface HealDeps {
  db: admin.firestore.Firestore;
  getAuthUser: (uid: string) => Promise<AuthUserLike | null>;
  now: () => Timestamp;
}

function defaultDeps(): HealDeps {
  return {
    db: admin.firestore(),
    getAuthUser: lookupAuthUser,
    now: () => admin.firestore.Timestamp.now(),
  };
}

/**
 * The trigger body, exported so tests can drive it directly (same pattern
 * as runSetAccountProfile). Idempotent: a second run finds owner_id set and
 * skips.
 */
export async function runHealUserProfile(
  uid: string,
  deps: Partial<HealDeps> = {}
): Promise<HealPlan> {
  const d: HealDeps = { ...defaultDeps(), ...deps };

  // Staff sessions never reach Auth or Firestore.
  if (isStaffUid(uid)) return { action: "skip", reason: "staff_uid" };

  const ref = d.db.collection("users").doc(uid);

  // Cheap pre-check so the common case (a fully-written profile, e.g.
  // createCustomerAccount or the installer's A7 merge) costs one read and
  // no Auth call.
  const pre = await ref.get();
  if (!pre.exists) return { action: "skip", reason: "doc_missing" };
  if (isSetField(pre.get("owner_id"))) {
    return { action: "skip", reason: "already_provisioned" };
  }

  const authUser = await d.getAuthUser(uid);

  // Re-read inside the transaction: if the client skeleton landed between
  // the pre-check and here, owner_id is now set and we skip.
  return d.db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists ? (snap.data() as Record<string, unknown>) : null;
    const plan = planHeal(uid, existing, authUser, d.now());
    if (plan.action === "heal") tx.set(ref, plan.fields, { merge: true });
    return plan;
  });
}

export const healUserProfile = onDocumentCreated(
  { document: "users/{uid}", region: "us-central1" },
  async (event) => {
    const uid = event.params.uid;
    try {
      const plan = await runHealUserProfile(uid);
      if (plan.action === "heal") {
        // Key names only — never the values (email / display name).
        logger.info(`healUserProfile: healed ${uid}`, {
          uid,
          fields: Object.keys(plan.fields),
        });
      } else {
        logger.info(`healUserProfile: skipped ${uid} (${plan.reason})`, {
          uid,
          reason: plan.reason,
        });
      }
    } catch (err) {
      logger.error(`healUserProfile: failed for ${uid}`, err);
      throw err;
    }
  }
);
