/**
 * mintStaffToken — Firebase Cloud Function (callable)
 *
 * Server-side validation of the staff PIN flow that today runs entirely
 * in the Flutter client. Mirrors:
 *   • lib/features/sales/sales_providers.dart
 *     SalesModeNotifier.enterSalesMode (lines 60-144)
 *   • lib/features/installer/installer_providers.dart
 *     InstallerModeNotifier.enterInstallerMode (lines 164-258)
 *   • lib/features/installer/admin/admin_providers.dart
 *     validateAdminPin (lines 60-115; will be migrated to call this
 *     callable in Prompt 8-iii)
 *   • lib/features/corporate/providers/corporate_providers.dart
 *     CorporateModeNotifier.authenticate — to be migrated as 'owner' mode
 *
 * Why this exists: the existing client flow forces the staff-pin
 * screen to read the master PIN hashes directly out of Firestore. A
 * 4-digit PIN is trivially brute-forceable from a leaked SHA-256, so
 * exposing the hash to anonymous sessions is effectively the same as
 * exposing the PIN. This callable validates server-side and returns a
 * Firebase Auth custom token with role + dealerCode claims so the
 * client never reads the hashes.
 *
 * Contract:
 *   request.data: { pin: string, mode: 'sales' | 'installer' | 'admin' | 'owner' }
 *   response:     { token, role, dealerCode, displayName, source }
 *
 *   `dealerCode` in the response is an empty string for owner mode
 *   (cross-dealer god mode); for other modes it's the dealer this
 *   session is scoped to. The custom token's `dealerCode` claim is
 *   only minted for non-owner modes — owner sessions have no
 *   dealerCode claim at all so rule helpers cleanly distinguish
 *   "scoped staff" from "unscoped owner."
 *
 * Mode → master doc → role mapping:
 *   sales      → app_config/master_sales_pin     → role: 'salesperson'
 *   installer  → app_config/master_installer     → role: 'installer'
 *   admin      → app_config/master_admin         → role: 'admin'
 *   owner      → app_config/master_corporate_pin → role: 'owner'
 *                (no installers fallback, no dealer.isActive check)
 *
 * Strict mode-role enforcement on the per-installer fallback:
 *   When the master PIN doesn't match, sales/installer/admin modes
 *   look up the PIN in the `installers` collection. The matched doc's
 *   `role` field MUST equal the role corresponding to the requested
 *   mode. A salesperson PIN cannot accidentally authenticate under
 *   installer mode (or vice versa) just because it's a 4-digit number
 *   that exists in the collection. Missing role field is treated as
 *   a mismatch (PIN miss).
 *
 *   Owner mode skips the installers fallback entirely — corporate
 *   credentials are master-only by design.
 *
 * Errors:
 *   invalid-argument    pin is not 4-6 digits, or mode is not one of
 *                       the allowed values.
 *   resource-exhausted  rate limit exceeded for the caller's IP
 *                       (10 attempts per 60 seconds).
 *   permission-denied   no master PIN match AND no active installer
 *                       doc match — OR matched installer's role
 *                       doesn't match the requested mode — OR matched
 *                       installer's dealer is inactive. The error
 *                       message is intentionally generic — clients
 *                       should not be able to distinguish between
 *                       these failure modes.
 *   internal            createCustomToken failed (e.g. IAM
 *                       Service Account Token Creator role missing
 *                       on the Cloud Functions runtime SA).
 *
 * Audit log:
 *   Every attempt (success and failure) appends one doc to
 *   `staff_auth_log`. The PIN itself is NEVER written. The custom
 *   token claim `pin` is server-side only and is not read by any
 *   firestore.rules expression.
 *
 *   `source` field on audit-log entries:
 *     'master'           success via master PIN doc
 *     'installer_doc'    success via per-installer fallback
 *     null               PIN miss (no branch matched, OR role mismatch
 *                        on installers fallback)
 *     'dealer_inactive'  per-installer match but dealer.isActive false
 *     'mint_failed'      createCustomToken threw (e.g. IAM denial)
 *     'rate_limited'     IP exceeded the 10/60s window
 *
 * Rate limit:
 *   Tracked per-IP in `staff_auth_rate_limit/{ipAddress}`. Window is
 *   10 attempts per 60 seconds. Failed and successful attempts both
 *   count. On Firestore transaction failure the check fails OPEN
 *   (allows the request, logs the failure) so a Firestore blip never
 *   locks all staff out — security trade-off chosen for MVP.
 *
 *   FOLLOW-UP: configure Firestore TTL policy on
 *   `staff_auth_rate_limit` to expire docs at `windowStart + 1h`
 *   so attacker counter docs don't accumulate. Console-only step;
 *   not deployable from this file.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:mintStaffToken
 */
type StaffSource = "master" | "installer_doc";
type StaffRole = "salesperson" | "installer" | "admin" | "owner";
interface MintStaffTokenResult {
    token: string;
    role: StaffRole;
    dealerCode: string;
    displayName: string;
    source: StaffSource;
}
export declare const mintStaffToken: import("firebase-functions/v2/https").CallableFunction<any, Promise<MintStaffTokenResult>, unknown>;
export {};
