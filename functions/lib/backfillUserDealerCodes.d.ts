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
interface BackfillResult {
    processed: number;
    succeeded: number;
    failed: number;
    skipped: number;
    errors: Array<{
        uid: string;
        reason: string;
    }>;
}
export declare const backfillUserDealerCodes: import("firebase-functions/v2/https").CallableFunction<any, Promise<BackfillResult>, unknown>;
export {};
