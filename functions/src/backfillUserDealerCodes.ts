/**
 * backfillUserDealerCodes — Firebase Cloud Function (callable)
 *
 * One-shot admin tool that backfills `dealer_code` onto /users docs for
 * customers who were onboarded by an installer before the field was added
 * to UserModel. The source of truth is /installations: each install doc
 * carries `dealer_code` and `primary_user_id`, so the join recovers the
 * dealer affiliation without requiring re-input.
 *
 * Why this exists: the installer customer-search rule on /users uses
 *   resource.data.dealer_code == auth.token.dealerCode
 * for installer/salesperson PIN sessions. Customers whose user doc lacks
 * the field are invisible to PIN searches. The installer wizard now writes
 * dealer_code on every new install and the email-already-in-use link path
 * picks it up via the existing set+merge; this function recovers pre-fix
 * customers.
 *
 * Orphan policy (intentional): customers with no /installations doc
 * (self-registered, dev accounts, reviewer seeds without an install)
 * stay unaffiliated and remain invisible to installer PIN searches. They
 * are still visible to dealer/media/admin user-doc roles and to admin/
 * owner staff sessions via canReadUserData / hasAdminOrOwnerClaim.
 *
 * Idempotency: skips users whose dealer_code is already set. Running the
 * function multiple times is safe — already-backfilled users are filtered
 * out at the per-user check. Users whose lookup fails on one run will be
 * retried on the next.
 *
 * Auth: requires the caller to have the `admin` custom claim (same gate
 * as backfillUserLocations). Tyler mints this for himself via:
 *   node -e "require('firebase-admin').initializeApp(); \
 *     require('firebase-admin').auth().setCustomUserClaims('<UID>', {admin: true})"
 *
 * Manual invocation (Tyler runs this once after deploy):
 *   Firebase Console -> Functions -> backfillUserDealerCodes -> Test the
 *   function -> submit empty body `{}` -> review the returned summary.
 *
 * Contract:
 *   request.data: {} (no parameters)
 *   response:     {
 *     processed: number,    // installations inspected with both fields present
 *     succeeded: number,    // user docs updated with dealer_code
 *     failed: number,       // user-doc lookups or updates that errored
 *     skipped: number,      // installs missing fields, missing user docs,
 *                           // or users that already had dealer_code set
 *     errors: Array<{ uid: string, reason: string }>,
 *   }
 *
 * Errors:
 *   unauthenticated      caller is not signed in
 *   permission-denied    caller lacks `admin: true` custom claim
 *   internal             unexpected error during scan
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

interface BackfillResult {
  processed: number;
  succeeded: number;
  failed: number;
  skipped: number;
  errors: Array<{ uid: string; reason: string }>;
}

export const backfillUserDealerCodes = onCall(
  { region: "us-central1", timeoutSeconds: 540, memory: "512MiB" },
  async (request): Promise<BackfillResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required");
    }
    if (request.auth.token.admin !== true) {
      throw new HttpsError(
        "permission-denied",
        "backfillUserDealerCodes requires the admin custom claim"
      );
    }

    const db = admin.firestore();
    const result: BackfillResult = {
      processed: 0,
      succeeded: 0,
      failed: 0,
      skipped: 0,
      errors: [],
    };

    // Scan /installations and filter in code. Mirrors backfillUserLocations:
    // a Firestore .where('field', '!=', null) on two fields would require
    // a composite index and a more complex query plan; full scan is fine
    // for a one-shot admin op and keeps the function simple.
    let snapshot: FirebaseFirestore.QuerySnapshot;
    try {
      snapshot = await db.collection("installations").get();
    } catch (error) {
      logger.error("backfillUserDealerCodes: scan failed", error);
      throw new HttpsError("internal", "Failed to scan /installations");
    }

    logger.info(
      `backfillUserDealerCodes: scanning ${snapshot.size} installation docs`
    );

    for (const installDoc of snapshot.docs) {
      const data = installDoc.data();
      const uid = data.primary_user_id as string | undefined;
      const dealerCode = data.dealer_code as string | undefined;

      // Skip installs missing either field — nothing to join on.
      if (!uid || uid.length === 0 || !dealerCode || dealerCode.length === 0) {
        result.skipped++;
        continue;
      }

      result.processed++;

      try {
        const userRef = db.collection("users").doc(uid);
        const userSnap = await userRef.get();

        // Skip if the user doc doesn't exist — the installation references
        // a deleted or never-fully-provisioned user. Not an error; just
        // nothing to backfill.
        if (!userSnap.exists) {
          result.skipped++;
          continue;
        }

        // Skip if dealer_code is already populated. Idempotency — a second
        // run won't churn already-backfilled users.
        const existingDealerCode = userSnap.data()?.dealer_code;
        if (
          typeof existingDealerCode === "string" &&
          existingDealerCode.length > 0
        ) {
          result.skipped++;
          continue;
        }

        await userRef.update({
          dealer_code: dealerCode,
          last_dealer_code_backfill_at:
            admin.firestore.FieldValue.serverTimestamp(),
        });
        result.succeeded++;
        logger.info(
          `backfillUserDealerCodes: ${uid} -> dealer_code=${dealerCode}`
        );
      } catch (error) {
        const reason =
          error instanceof Error ? error.message : String(error);
        result.failed++;
        result.errors.push({ uid, reason });
        logger.warn(`backfillUserDealerCodes: ${uid} failed: ${reason}`);
      }
    }

    logger.info(
      `backfillUserDealerCodes: done — processed=${result.processed} succeeded=${result.succeeded} failed=${result.failed} skipped=${result.skipped}`
    );
    return result;
  }
);
