/**
 * backfillUserLocations — Firebase Cloud Function (callable)
 *
 * One-shot admin tool that scans /users docs missing latitude/longitude,
 * geocodes their stored `address` field via Google Geocoding API, looks up
 * the IANA timezone via Google Timezone API, and writes the resolved
 * lat/lng/time_zone back to each user doc.
 *
 * Why this exists: prior to the installer-flow fix that captures lat/lon
 * during address selection, every customer user-doc was written with
 * latitude/longitude null. That silently disabled astronomical scheduling
 * (sunset/sunrise fires at wrong times), Game Day autopilot timing, and
 * any geofence trigger that needs the home coordinate. This function
 * recovers those users without requiring them to re-enter their address.
 *
 * Idempotency: the underlying query skips users whose latitude is already
 * a finite number. Running this function multiple times is safe — already-
 * resolved users are filtered out at scan time. Users whose geocoding
 * fails on one run will be retried on the next.
 *
 * Auth: requires the caller to have the `admin` custom claim. Tyler mints
 * this for himself via:
 *   gcloud auth login
 *   node -e "require('firebase-admin').initializeApp(); \
 *     require('firebase-admin').auth().setCustomUserClaims('<UID>', {admin: true})"
 * or via a one-shot script in functions/ with the admin SDK.
 *
 * Configuration: requires GOOGLE_MAPS_API_KEY in Google Cloud Secret
 * Manager (set via `firebase functions:secrets:set GOOGLE_MAPS_API_KEY`)
 * with both Geocoding API and Time Zone API enabled in Google Cloud
 * Console. The function declares the secret in its onCall `secrets`
 * option so the runtime auto-mounts it for `.value()` to resolve.
 *
 * Manual invocation (Tyler runs this once after deploy):
 *   Firebase Console → Functions → backfillUserLocations → Test the
 *   function → submit empty body `{}` → review the returned summary.
 *
 * Contract:
 *   request.data: {} (no parameters)
 *   response:     {
 *     processed: number,    // total users inspected
 *     succeeded: number,    // users updated with new lat/lon
 *     failed: number,       // users whose address geocoding failed
 *     skipped: number,      // users skipped (lat already set, no address)
 *     errors: Array<{ uid: string, reason: string }>,
 *   }
 *
 * Errors:
 *   unauthenticated      caller is not signed in
 *   permission-denied    caller lacks `admin: true` custom claim
 *   failed-precondition  GOOGLE_MAPS_API_KEY not configured
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
export declare const backfillUserLocations: import("firebase-functions/v2/https").CallableFunction<any, Promise<BackfillResult>, unknown>;
export {};
