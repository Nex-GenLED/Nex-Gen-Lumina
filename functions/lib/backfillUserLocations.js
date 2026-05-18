"use strict";
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
 * Configuration: requires GOOGLE_MAPS_API_KEY in functions/.env with both
 * Geocoding API and Time Zone API enabled in Google Cloud Console.
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
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.backfillUserLocations = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
// admin.initializeApp() is called in index.js — do not call again here.
const googleMapsApiKey = (0, params_1.defineString)("GOOGLE_MAPS_API_KEY");
exports.backfillUserLocations = (0, https_1.onCall)({ region: "us-central1", timeoutSeconds: 540, memory: "512MiB" }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign-in required");
    }
    if (request.auth.token.admin !== true) {
        throw new https_1.HttpsError("permission-denied", "backfillUserLocations requires the admin custom claim");
    }
    const apiKey = googleMapsApiKey.value();
    if (!apiKey || apiKey === "") {
        throw new https_1.HttpsError("failed-precondition", "GOOGLE_MAPS_API_KEY not configured in functions/.env");
    }
    const db = admin.firestore();
    const result = {
        processed: 0,
        succeeded: 0,
        failed: 0,
        skipped: 0,
        errors: [],
    };
    // The `latitude` field is stripped by UserService.sanitizeForFirestore
    // when null, so a `where('latitude', '==', null)` filter would miss
    // most affected docs. Scan everything and filter in code. This is a
    // one-shot operation — collection size is small enough not to matter.
    let snapshot;
    try {
        snapshot = await db.collection("users").get();
    }
    catch (error) {
        firebase_functions_1.logger.error("backfillUserLocations: scan failed", error);
        throw new https_1.HttpsError("internal", "Failed to scan /users");
    }
    firebase_functions_1.logger.info(`backfillUserLocations: scanning ${snapshot.size} user docs`);
    for (const doc of snapshot.docs) {
        const user = doc.data();
        const existingLat = user.latitude;
        const existingLon = user.longitude;
        const address = user.address?.trim() ?? "";
        // Skip users that already have valid coordinates.
        if (typeof existingLat === "number" &&
            Number.isFinite(existingLat) &&
            typeof existingLon === "number" &&
            Number.isFinite(existingLon)) {
            result.skipped++;
            continue;
        }
        // Skip users with no address — nothing to geocode against.
        if (address.length === 0) {
            result.skipped++;
            continue;
        }
        result.processed++;
        try {
            const outcome = await geocodeAddress(address, apiKey);
            if (outcome === null) {
                result.failed++;
                result.errors.push({
                    uid: doc.id,
                    reason: "geocoding returned no results",
                });
                continue;
            }
            const updatePayload = {
                latitude: outcome.latitude,
                longitude: outcome.longitude,
                last_backfill_at: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (outcome.timeZone !== null) {
                updatePayload.time_zone = outcome.timeZone;
            }
            await doc.ref.update(updatePayload);
            result.succeeded++;
            firebase_functions_1.logger.info(`backfillUserLocations: ${doc.id} -> ${outcome.latitude},${outcome.longitude} (${outcome.timeZone ?? "no tz"})`);
        }
        catch (error) {
            const reason = error instanceof Error ? error.message : String(error);
            result.failed++;
            result.errors.push({ uid: doc.id, reason });
            firebase_functions_1.logger.warn(`backfillUserLocations: ${doc.id} failed: ${reason}`);
        }
    }
    firebase_functions_1.logger.info(`backfillUserLocations: done — processed=${result.processed} succeeded=${result.succeeded} failed=${result.failed} skipped=${result.skipped}`);
    return result;
});
/**
 * Geocodes a free-text address via Google Geocoding API, then resolves the
 * IANA timezone for the resulting coordinates via Google Time Zone API.
 *
 * Returns null when the Geocoding API returns ZERO_RESULTS or any non-OK
 * status. Timezone failure is treated as soft: returns the lat/lng with
 * timeZone: null so the user-doc still benefits from the coordinate fix.
 *
 * Throws on HTTP failure (caller catches and counts as failed).
 */
async function geocodeAddress(address, apiKey) {
    const geocodeUrl = "https://maps.googleapis.com/maps/api/geocode/json" +
        `?address=${encodeURIComponent(address)}&key=${apiKey}`;
    const geocodeRes = await fetch(geocodeUrl);
    if (!geocodeRes.ok) {
        throw new Error(`Geocoding HTTP ${geocodeRes.status}`);
    }
    const geocodeBody = (await geocodeRes.json());
    if (geocodeBody.status !== "OK") {
        if (geocodeBody.status === "ZERO_RESULTS") {
            return null;
        }
        throw new Error(`Geocoding status ${geocodeBody.status}`);
    }
    const location = geocodeBody.results?.[0]?.geometry?.location;
    if (!location || typeof location.lat !== "number" || typeof location.lng !== "number") {
        return null;
    }
    const latitude = location.lat;
    const longitude = location.lng;
    // Best-effort timezone lookup. Failure is non-fatal — return the
    // coordinates with timeZone: null.
    let timeZone = null;
    try {
        const nowSec = Math.floor(Date.now() / 1000);
        const tzUrl = "https://maps.googleapis.com/maps/api/timezone/json" +
            `?location=${latitude},${longitude}&timestamp=${nowSec}&key=${apiKey}`;
        const tzRes = await fetch(tzUrl);
        if (tzRes.ok) {
            const tzBody = (await tzRes.json());
            if (tzBody.status === "OK" && typeof tzBody.timeZoneId === "string") {
                timeZone = tzBody.timeZoneId;
            }
        }
    }
    catch (error) {
        firebase_functions_1.logger.warn("backfillUserLocations: timezone lookup failed", error);
    }
    return { latitude, longitude, timeZone };
}
//# sourceMappingURL=backfillUserLocations.js.map