/**
 * purgeUserAccount — server-side account data purge.
 *
 * WHY THIS EXISTS
 * `audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md` F-1 (P0): the app's "Delete
 * Account" button called `UserService.deleteUser()`, which is one
 * `users/{uid}.delete()`. Firestore does NOT cascade — every one of the ~34
 * subcollections enumerated in that audit's §2.1 survived, along with the
 * Cloud Storage house photo (§2.3, F-3). `audit/OVERNIGHT_PRIVACY_AUDIT.md`
 * §2.5 sharpens it: `runDataCleanup` iterates `db.collection("users").get()`,
 * and a deleted parent doc is not returned by `.get()`, so the orphaned
 * subcollections are unreachable by ANY retention pass, on any schedule,
 * forever. The published policy promises delete-or-anonymise within 30 days.
 *
 * WHY A CALLABLE AND NOT `beforeUserDeleted`
 * A `beforeUserDeleted` blocking function would make the purge atomic with the
 * Auth delete, and it is the shape the audit prefers (§4 item 1, first
 * clause). It requires Google Cloud Identity Platform. Probed live on
 * 2026-08-26 against `identitytoolkit.googleapis.com/admin/v2/projects/
 * icrt6menwsv2d8all8oijs021b06s5/config`:
 *
 *     subtype = "FIREBASE_AUTH"        (GCIP reports "IDENTITY_PLATFORM")
 *     blockingFunctions = {}
 *
 * The project is NOT upgraded to Identity Platform, so blocking functions are
 * unavailable. This is the audit's own stated fallback (§4 item 1, second
 * clause): an authenticated callable that the client invokes BEFORE
 * `user.delete()`.
 *
 * ORDERING CONTRACT — the F-2 half of the fix lives on the client
 * (`security_settings_screen.dart`), but it only works if this function keeps
 * its half: it deletes DATA ONLY and never touches Firebase Auth. The client
 * re-authenticates first, calls this, confirms success, and only then calls
 * `user.delete()`. If Auth deletion fails at that point the user still has a
 * live session and can retry from the top — degraded, but recoverable, which
 * is the opposite of today's behaviour.
 *
 * SCOPE — PHASE 1 ONLY.
 * This purges `users/{uid}` (doc + every subcollection) and the user's Cloud
 * Storage prefix. It deliberately does NOT yet perform the §2.4 top-level
 * teardowns that the audit also recommends:
 *   - §4.3 neighborhood `leaveGroup` for every group in `memberUids` (D-2)
 *   - §4.4 OAuth refresh-token revocation (D-3)
 *   - §4.5 `bridge_registry.pairedUid` release (D-1, F-5)
 * Those are later phases with their own deploy gates. `PENDING_PHASE_2` below
 * records them in code so the gap is not silently forgotten.
 *
 * NOT DEPLOYED by the session that wrote this. Tyler gates:
 *   cd functions && npm run build
 *   firebase deploy --only functions:purgeUserAccount
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ───────────────────────────────────────────────────────────────────────────
// Collection inventory
// ───────────────────────────────────────────────────────────────────────────

/**
 * Every subcollection of `users/{uid}` enumerated in
 * `audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md` §2.1, in that table's order.
 *
 * `recursiveDelete` discovers subcollections itself via `listCollections()`,
 * so this list is NOT what drives the delete. It drives the VERIFICATION pass:
 * after the sweep we re-probe each named path and report anything still
 * standing. A purge that silently half-completes is the failure mode this
 * whole exercise exists to remove, so it is checked rather than assumed.
 *
 * Rows 2, 3, 10, 12, 20, 21, 22, 23, 30, 32, 34 have no `firestore.rules`
 * match block (audit F-6). A client-credential probe on 2026-08-26 confirmed
 * writes to all of them are DENIED 403 today, so in practice they are empty —
 * but they are swept and verified anyway, because "empty today" is a fact
 * about the current ruleset, not about the data.
 */
export const USER_SUBCOLLECTIONS: readonly string[] = [
  "ai_usage",
  "autopilot_events",
  "autopilot_feedback",
  "brand_profile",
  "bridge_status",
  "commands",
  "commercial_events",
  "commercial_hours",
  "commercial_locations",
  "commercial_schedule",
  "controllers", // incl. controllers/{id}/pixelMap (§2.1 row 11a)
  "controller_health",
  "debug_errors",
  "designs",
  "detected_habits",
  "ephemeral_game_sessions",
  "favorites",
  "game_day_autopilot",
  "geofences",
  "handoff",
  "integrations",
  "learned_preferences",
  "lumina_usage",
  "pattern_feedback",
  "pattern_usage",
  "patterns",
  "properties",
  "referrals",
  "roofline_config",
  "scenes",
  "schedules",
  "simple_mode",
  "suggestions",
  "user_events",
];

/**
 * §2.4 teardowns this phase does NOT perform. Exported so a Phase 2 change has
 * one place to consume, and so a test can assert the list has not been quietly
 * emptied to make a green run.
 */
export const PENDING_PHASE_2: readonly string[] = [
  "neighborhoods.memberUids", // D-2 — needs the #105 server-side leave callable
  "oauth_refresh_tokens", // D-3
  "google_oauth_refresh_tokens", // D-3
  "bridge_registry.pairedUid", // D-1 / F-5 — hardware stays pinned to a dead uid
];

/**
 * Cloud Storage prefix owned by a user. `image_upload_service.dart:59` writes
 * `users/{uid}/house_photo.jpg`; the prefix form covers that plus anything
 * else that lands under the same folder later.
 */
export function storagePrefixForUid(uid: string): string {
  return `users/${uid}/`;
}

// ───────────────────────────────────────────────────────────────────────────
// Result shape
// ───────────────────────────────────────────────────────────────────────────

export interface PurgeResult {
  uid: string;
  /** Subcollection paths that still hold at least one doc after the sweep. */
  residualCollections: string[];
  /** True when `users/{uid}` itself no longer exists. */
  userDocDeleted: boolean;
  /** Number of Cloud Storage objects removed under the user's prefix. */
  storageObjectsDeleted: number;
  /** Non-fatal problems. A non-empty list means the caller must NOT proceed. */
  warnings: string[];
}

/** Minimal surface of the pieces of Firestore/Storage this module touches. */
export interface PurgeDeps {
  db: {
    doc(path: string): {
      get(): Promise<{ exists: boolean }>;
    };
    collection(path: string): {
      limit(n: number): { get(): Promise<{ empty: boolean }> };
    };
    recursiveDelete(ref: unknown): Promise<void>;
  };
  /** Deletes every object under `prefix`; resolves to the count removed. */
  deleteStoragePrefix(prefix: string): Promise<number>;
}

// ───────────────────────────────────────────────────────────────────────────
// The purge itself
// ───────────────────────────────────────────────────────────────────────────

/**
 * Recursively deletes `users/{uid}` and everything beneath it, then the user's
 * Cloud Storage prefix, then VERIFIES both.
 *
 * Dependency-injected so the orchestration is testable without an emulator —
 * `functions/test/unit/purgeUserAccount.test.js` drives it with a fake.
 */
export async function purgeUserData(
  deps: PurgeDeps,
  uid: string
): Promise<PurgeResult> {
  if (typeof uid !== "string" || uid.trim().length === 0) {
    throw new Error("purgeUserData: uid must be a non-empty string");
  }

  const warnings: string[] = [];
  const userRef = deps.db.doc(`users/${uid}`);

  // ── 1. Firestore: doc + every subcollection, depth-unbounded. ───────────
  // recursiveDelete walks listCollections() itself, so nested paths like
  // controllers/{id}/pixelMap are covered without being named.
  await deps.db.recursiveDelete(userRef);

  // ── 2. Cloud Storage. ──────────────────────────────────────────────────
  // Runs with admin credentials, so `storage.rules` does not apply — which
  // matters, because F-3 is precisely that the OWNER cannot delete this object
  // under the shipped rules. Part C fixes the rules; this does not depend on
  // that fix having landed.
  let storageObjectsDeleted = 0;
  try {
    storageObjectsDeleted = await deps.deleteStoragePrefix(
      storagePrefixForUid(uid)
    );
  } catch (err) {
    // A Storage failure must not abort the Firestore purge that already
    // succeeded, but it IS reported so the caller can refuse to delete Auth.
    warnings.push(
      `storage: failed to delete prefix ${storagePrefixForUid(uid)}: ${
        err instanceof Error ? err.message : String(err)
      }`
    );
  }

  // ── 3. Verify. ─────────────────────────────────────────────────────────
  const residualCollections: string[] = [];
  for (const name of USER_SUBCOLLECTIONS) {
    const path = `users/${uid}/${name}`;
    try {
      const snap = await deps.db.collection(path).limit(1).get();
      if (!snap.empty) residualCollections.push(path);
    } catch (err) {
      warnings.push(
        `verify: could not probe ${path}: ${
          err instanceof Error ? err.message : String(err)
        }`
      );
    }
  }

  let userDocDeleted = false;
  try {
    const doc = await userRef.get();
    userDocDeleted = !doc.exists;
    if (doc.exists) {
      warnings.push(`verify: users/${uid} still exists after recursiveDelete`);
    }
  } catch (err) {
    warnings.push(
      `verify: could not probe users/${uid}: ${
        err instanceof Error ? err.message : String(err)
      }`
    );
  }

  if (residualCollections.length > 0) {
    warnings.push(
      `verify: ${residualCollections.length} subcollection(s) still hold data`
    );
  }

  return {
    uid,
    residualCollections,
    userDocDeleted,
    storageObjectsDeleted,
    warnings,
  };
}

/** True when the purge is clean enough that the caller may delete the Auth user. */
export function isPurgeComplete(result: PurgeResult): boolean {
  return (
    result.userDocDeleted &&
    result.residualCollections.length === 0 &&
    result.warnings.length === 0
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Callable
// ───────────────────────────────────────────────────────────────────────────

function liveDeps(): PurgeDeps {
  const db = admin.firestore();
  return {
    db: db as unknown as PurgeDeps["db"],
    deleteStoragePrefix: async (prefix: string) => {
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({ prefix });
      await Promise.all(files.map((f) => f.delete({ ignoreNotFound: true })));
      return files.length;
    },
  };
}

/**
 * Self-service only: a caller may purge their OWN uid and nothing else.
 *
 * There is no admin branch on purpose. `scripts/wipe_customer_data.js` already
 * covers operator-driven deletion with an interactive WIPE confirmation and a
 * protected-account list; a uid-taking admin path reachable over HTTPS would be
 * a strictly worse copy of it with none of those guards.
 */
export const purgeUserAccount = onCall(
  { region: "us-central1", maxInstances: 10 },
  async (request: CallableRequest<unknown>): Promise<PurgeResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;

    console.log(`purgeUserAccount: starting purge for uid=${uid}`);
    let result: PurgeResult;
    try {
      result = await purgeUserData(liveDeps(), uid);
    } catch (err) {
      console.error(`purgeUserAccount: purge threw for uid=${uid}`, err);
      throw new HttpsError(
        "internal",
        "Account data could not be deleted. Nothing was removed from your " +
          "sign-in. Please try again."
      );
    }

    if (!isPurgeComplete(result)) {
      // Surfacing this as an error is deliberate: the client uses a successful
      // return as its gate for calling user.delete(). A partial purge that
      // reported success would recreate F-1 with extra steps.
      console.error(
        `purgeUserAccount: INCOMPLETE for uid=${uid} — residual=${JSON.stringify(
          result.residualCollections
        )} warnings=${JSON.stringify(result.warnings)}`
      );
      throw new HttpsError(
        "internal",
        "Account data was only partially deleted. Your sign-in has not been " +
          "removed. Please try again or contact support."
      );
    }

    console.log(
      `purgeUserAccount: complete for uid=${uid} — ` +
        `storageObjectsDeleted=${result.storageObjectsDeleted}`
    );
    return result;
  }
);
