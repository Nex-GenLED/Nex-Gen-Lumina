const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { claudeProxy } = require('./src/claudeProxy');
exports.claudeProxy = claudeProxy;

admin.initializeApp();

// Import TypeScript-compiled Lumina AI schedule command processor
const { processScheduleCommand } = require("./lib/processScheduleCommand");
exports.processScheduleCommand = processScheduleCommand;

// Import TypeScript-compiled Neighborhood Sync notification sender
const { sendSyncNotification } = require("./lib/sendSyncNotification");
exports.sendSyncNotification = sendSyncNotification;

// Import TypeScript-compiled Sync Session lifecycle functions (background service)
const { initiateSyncSession } = require("./lib/initiateSyncSession");
exports.initiateSyncSession = initiateSyncSession;

const { endSyncSession } = require("./lib/endSyncSession");
exports.endSyncSession = endSyncSession;

const { applySyncPattern } = require("./lib/applySyncPattern");
exports.applySyncPattern = applySyncPattern;

const { triggerSyncFailover } = require("./lib/triggerSyncFailover");
exports.triggerSyncFailover = triggerSyncFailover;

// Import TypeScript-compiled referral code assignment (onCreate /users/{uid})
const { assignReferralCode } = require("./lib/assignReferralCode");
exports.assignReferralCode = assignReferralCode;

// Import TypeScript-compiled referral code redemption (callable)
const { redeemReferralCode } = require("./lib/redeemReferralCode");
exports.redeemReferralCode = redeemReferralCode;

// Import TypeScript-compiled referral status change notification (onUpdate trigger)
const { onReferralStatusChanged } = require("./lib/onReferralStatusChanged");
exports.onReferralStatusChanged = onReferralStatusChanged;

// Import TypeScript-compiled Day 2 install team notification
const { notifyDay2Team } = require("./lib/notifyDay2Team");
exports.notifyDay2Team = notifyDay2Team;

// Import TypeScript-compiled referrer reward approval notification
const { notifyReferrerOfApproval } = require("./lib/notifyReferrerOfApproval");
exports.notifyReferrerOfApproval = notifyReferrerOfApproval;

// Import TypeScript-compiled weekly brief scheduled function (Sunday 18:30 UTC)
const { sendWeeklyBrief } = require("./lib/sendWeeklyBrief");
exports.sendWeeklyBrief = sendWeeklyBrief;

// Import TypeScript-compiled schedule-limit enforcer (Sunday 19:00 UTC)
const { enforceScheduleLimits } = require("./lib/enforceScheduleLimits");
exports.enforceScheduleLimits = enforceScheduleLimits;

// Admin callable: backfill legacy schedules array -> subcollection (Prompt A-4)
const { backfillSchedulesSubcollection } = require("./lib/backfillSchedulesSubcollection");
exports.backfillSchedulesSubcollection = backfillSchedulesSubcollection;

// ── Command safety (S1 + S2) ───────────────────────────────────────────────
// Expires stale `pending` commands so a bridge that reconnects after an outage
// cannot fire a backlog at the wrong time. The bridge has NO age check of its
// own and the age check below (executeWledCommand) is webhook-only, so this is
// the ONLY expiry enforcement that reaches the bridge-mode fleet.
// See audit/COMMAND_SAFETY.md.
const { sweepExpiredCommands } = require("./lib/sweepExpiredCommands");
exports.sweepExpiredCommands = sweepExpiredCommands;

// Maintains users/{uid}.controller_ips — the allowlist firestore.rules uses to
// reject a command naming a controllerIp that is not the customer's own.
// DEPLOY + BACKFILL BEFORE the tightened commands rule (COMMAND_SAFETY.md §5).
const { syncControllerIps, backfillControllerIps } = require("./lib/syncControllerIps");
exports.syncControllerIps = syncControllerIps;
exports.backfillControllerIps = backfillControllerIps;

// S6 — CONTROLLER HEALTH TELEMETRY (cloud half). audit/CONTROLLER_HEALTH.md.
//
// A daily READ-ONLY getInfo probe per controller, read back 15 minutes later
// into /users/{uid}/controller_health/{controllerId}, plus the two fleet alerts
// and a push digest.
//
// Why this exists: on 2026-08-05 two customer bridges had been dark for 15.0 and
// 21.4 days and a third customer had a powered, online, never-paired bridge for
// five days with 17 failed commands — none of it visible to the customer, the
// dealer or Tyler, because everyday lighting is device-resident and kept
// working (audit/BRIDGE_TRIAGE.md). The mechanism needs NO firmware: the bridge
// already copies WLED's response body into the command doc's `result` field.
const { probeControllerHealth } = require("./lib/probeControllerHealth");
const {
  collectControllerHealth,
  backfillControllerHealth,
} = require("./lib/collectControllerHealth");
exports.probeControllerHealth = probeControllerHealth;
exports.collectControllerHealth = collectControllerHealth;
exports.backfillControllerHealth = backfillControllerHealth;

// S3 — FIRE-JOB DISPATCHER (audit/S3_DISPATCHER.md). The minute cron that makes
// unattended Game Day and Neighborhood Sync possible at all: both are 100%
// app-open-only today because kSportsBackgroundServiceEnabled = false and iOS
// background fetch cannot wake an app for a wall-clock instant.
//
// Reconciles dispatched jobs, then writes ONE command per due job — always
// naming a server-resolved controllerIp, always with an explicit expiresAt, and
// always through the one-in-flight guard so a fire never competes with customer
// traffic. Ships in PING SHADOW MODE: no real payload fires until the measured
// P50/P95 in /fire_metrics says the transport behaves.
//
// REQUIRES the COLLECTION_GROUP index on fire_jobs(state, fireAt) — deploy
// indexes BEFORE this function or every tick throws.
const { dispatchFireJobs } = require("./lib/dispatchFireJobs");
exports.dispatchFireJobs = dispatchFireJobs;

// S5 — GAME DAY PLANNER (audit/S5_GAMEDAY.md). The producer S3 was waiting for.
// SHIPS LOG-ONLY: config/gameday_planner.write_jobs defaults FALSE, so it records
// what it WOULD fire and writes no jobs until deliberately flipped.
const { planGameDayFires } = require("./lib/planGameDayFires");
exports.planGameDayFires = planGameDayFires;

// The single residential<->commercial activation path. Owns the cross-doc
// batch (users + installations) that no client can write; absorbs the two
// diverged in-app batches (item #32).
const { setAccountProfile } = require("./lib/setAccountProfile");
exports.setAccountProfile = setAccountProfile;

// ── Messaging ──────────────────────────────────────────────────────────────
// SMS + email customer messaging pipeline. messaging-helpers.ts is a
// shared support module imported by both functions below — it has no
// require/exports entry of its own.

const { onSalesJobStatusChanged } = require("./lib/onSalesJobStatusChanged");
exports.onSalesJobStatusChanged = onSalesJobStatusChanged;

const { createCustomerAccount } = require("./lib/createCustomerAccount");
exports.createCustomerAccount = createCustomerAccount;

const { sendInstallReminders } = require("./lib/sendInstallReminders");
exports.sendInstallReminders = sendInstallReminders;

// Server-side staff PIN validation — replaces the client-side hash
// reads in sales_providers.dart / installer_providers.dart.
const { mintStaffToken } = require("./lib/staffAuth");
exports.mintStaffToken = mintStaffToken;

// One-shot admin tool: backfills lat/lon/time_zone for /users docs that
// were created before the installer-flow geo capture landed. Requires
// the admin custom claim on the caller's account.
const { backfillUserLocations } = require("./lib/backfillUserLocations");
exports.backfillUserLocations = backfillUserLocations;

// One-shot admin tool: backfills dealer_code on /users docs by joining
// from /installations.primary_user_id -> /users.uid, copying
// /installations.dealer_code onto the user doc. Required so installer
// PIN sessions can find pre-fix customers via the per-dealer rule clause
// on /users. Requires the admin custom claim on the caller's account.
const { backfillUserDealerCodes } = require("./lib/backfillUserDealerCodes");
exports.backfillUserDealerCodes = backfillUserDealerCodes;

// One-time WLED dow off-by-one fix migration (Item #72). Clears every
// user's `schedules` array so the production fleet starts clean on the
// corrected Mon=bit 0 convention. Idempotent — tracks completion in
// config/migrations/items/migrateClearScheduleItemsV1. Gated to
// @nex-genled.com authenticated callers. Must be invoked manually via
// Firebase Console or `firebase functions:shell` after the new build
// is in production.
const { migrateClearScheduleItemsV1 } = require("./lib/migrateClearScheduleItemsV1");
exports.migrateClearScheduleItemsV1 = migrateClearScheduleItemsV1;

const db = admin.firestore();

// Define the OpenAI API key parameter (reads from .env file)
const openaiApiKey = defineString("OPENAI_API_KEY");

// Alexa OAuth configuration (add to .env file)
const alexaClientId = defineString("ALEXA_CLIENT_ID");
const alexaClientSecret = defineString("ALEXA_CLIENT_SECRET");

// Google Home OAuth configuration (add to .env file)
const googleClientId = defineString("GOOGLE_CLIENT_ID");
const googleClientSecret = defineString("GOOGLE_CLIENT_SECRET");

// Messaging — Twilio (SMS) configuration (add to .env file)
const twilioAccountSid = defineString("TWILIO_ACCOUNT_SID");
const twilioAuthToken = defineString("TWILIO_AUTH_TOKEN");
const twilioFromNumber = defineString("TWILIO_FROM_NUMBER");

// Messaging — Resend (email) configuration (add to .env file)
const resendApiKey = defineString("RESEND_API_KEY");
const resendFromEmail = defineString("RESEND_FROM_EMAIL");
const resendFromName = defineString("RESEND_FROM_NAME");

/**
 * OpenAI Proxy Cloud Function for Lumina AI
 *
 * This function acts as a secure proxy between the Flutter app and OpenAI API.
 * The API key is stored in .env file in the functions folder.
 *
 * SECURITY FEATURES:
 * - Rate limiting: 10 requests per user per hour
 * - Token limiting: Max 2000 tokens per request
 * - Usage tracking and monitoring
 * - Input validation and sanitization
 */
exports.openaiProxy = onCall({ region: "us-central1" }, async (request) => {
  const apiKey = openaiApiKey.value();

  if (!apiKey || apiKey === "YOUR_API_KEY_HERE") {
    console.error("OpenAI API key not configured");
    throw new HttpsError(
      "failed-precondition",
      "OpenAI API key not configured in .env file"
    );
  }

  // Authentication check
  if (!request.auth) {
    console.error("Unauthenticated request to openaiProxy");
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = request.auth.uid;
  const now = admin.firestore.Timestamp.now();
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);

  try {
    // SECURITY: Rate limiting - check requests in last hour
    const usageRef = db.collection("users").doc(userId).collection("ai_usage");
    const recentRequests = await usageRef
      .where("timestamp", ">", admin.firestore.Timestamp.fromDate(oneHourAgo))
      .get();

    const requestsInLastHour = recentRequests.size;
    const RATE_LIMIT = 10; // Max 10 requests per hour

    if (requestsInLastHour >= RATE_LIMIT) {
      console.warn(`Rate limit exceeded for user ${userId}: ${requestsInLastHour} requests in last hour`);
      throw new HttpsError(
        "resource-exhausted",
        `Rate limit exceeded. Maximum ${RATE_LIMIT} AI requests per hour. Please try again later.`
      );
    }

    // SECURITY: Validate and limit token count
    const requestData = request.data;
    const MAX_TOKENS = 2000;

    if (requestData.max_tokens && requestData.max_tokens > MAX_TOKENS) {
      console.warn(`Token limit exceeded for user ${userId}: ${requestData.max_tokens}`);
      requestData.max_tokens = MAX_TOKENS;
    }

    // SECURITY: Validate model is allowed
    const ALLOWED_MODELS = ["gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"];
    if (!ALLOWED_MODELS.includes(requestData.model)) {
      console.error(`Invalid model requested: ${requestData.model}`);
      throw new HttpsError("invalid-argument", "Invalid model requested");
    }

    // SECURITY: Validate messages structure
    if (!requestData.messages || !Array.isArray(requestData.messages)) {
      throw new HttpsError("invalid-argument", "Invalid messages format");
    }

    // SECURITY: Sanitize user input - prevent prompt injection
    for (const msg of requestData.messages) {
      if (msg.role === "user" && msg.content) {
        // Limit message length
        const MAX_MESSAGE_LENGTH = 5000;
        if (msg.content.length > MAX_MESSAGE_LENGTH) {
          msg.content = msg.content.substring(0, MAX_MESSAGE_LENGTH);
          console.warn(`Truncated long message for user ${userId}`);
        }
      }
    }

    // Forward the request to OpenAI
    const startTime = Date.now();
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(requestData),
    });

    const latency = Date.now() - startTime;

    if (!response.ok) {
      const errorText = await response.text();
      console.error("OpenAI API error:", response.status, errorText);

      // Log failed request for monitoring
      await usageRef.add({
        timestamp: now,
        status: "failed",
        error: response.status,
        latency: latency,
      });

      throw new HttpsError(
        "internal",
        `OpenAI API error: ${response.status}`
      );
    }

    const result = await response.json();

    // Calculate tokens used
    const tokensUsed = result.usage?.total_tokens || 0;
    const cost = calculateCost(requestData.model, tokensUsed);

    // MONITORING: Log successful request with usage metrics
    await usageRef.add({
      timestamp: now,
      status: "success",
      model: requestData.model,
      tokensUsed: tokensUsed,
      estimatedCost: cost,
      latency: latency,
      requestCount: requestsInLastHour + 1,
    });

    // MONITORING: Check if user is approaching limits
    if (requestsInLastHour >= RATE_LIMIT * 0.8) {
      console.warn(`User ${userId} approaching rate limit: ${requestsInLastHour + 1}/${RATE_LIMIT}`);
    }

    // MONITORING: Log high cost requests
    if (cost > 0.10) {
      console.warn(`High cost request for user ${userId}: $${cost.toFixed(4)}`);
    }

    return result;
  } catch (error) {
    console.error("OpenAI proxy error:", error);

    // Re-throw HttpsError instances
    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError("internal", error.message);
  }
});

/**
 * Calculate estimated cost for OpenAI API call
 * Prices as of Jan 2025 - update as needed
 */
function calculateCost(model, tokens) {
  const pricing = {
    "gpt-4o": { input: 0.0025 / 1000, output: 0.01 / 1000 },
    "gpt-4o-mini": { input: 0.00015 / 1000, output: 0.0006 / 1000 },
    "gpt-3.5-turbo": { input: 0.0005 / 1000, output: 0.0015 / 1000 },
  };

  const modelPricing = pricing[model] || pricing["gpt-4o"];
  // Estimate 50/50 split between input and output tokens
  return tokens * (modelPricing.input + modelPricing.output) / 2;
}

/**
 * Cloud Relay Command Executor
 *
 * Triggers when a new command document is created in /users/{userId}/commands/{commandId}
 *
 * Supports two modes:
 * 1. ESP32 Bridge Mode (recommended): No webhookUrl provided. The Cloud Function does nothing,
 *    and the ESP32 bridge device at the customer's home picks up and executes the command.
 * 2. Webhook Mode (DIY): webhookUrl provided. The Cloud Function forwards the command to the
 *    user's Dynamic DNS URL (requires port forwarding setup).
 */
exports.executeWledCommand = onDocumentCreated(
  {
    document: "users/{userId}/commands/{commandId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data in snapshot");
      return;
    }

    const commandData = snapshot.data();
    const commandRef = snapshot.ref;
    const { userId, commandId } = event.params;

    console.log(`📤 Processing command ${commandId} for user ${userId}`);
    console.log(`   Type: ${commandData.type}`);
    console.log(`   Controller: ${commandData.controllerId} (${commandData.controllerIp})`);

    // Check execution mode
    if (!commandData.webhookUrl || commandData.webhookUrl === "") {
      // ESP32 Bridge Mode: Don't execute here, let the ESP32 bridge handle it
      console.log("🔌 ESP32 Bridge Mode: Skipping Cloud Function execution");
      console.log("   The ESP32 bridge will pick up and execute this command");
      return;
    }

    console.log("🌐 Webhook Mode: Executing via Cloud Function");

    // Check command age - reject commands older than 5 minutes
    const createdAt = commandData.createdAt?.toDate?.() || new Date();
    const ageMs = Date.now() - createdAt.getTime();
    if (ageMs > 5 * 60 * 1000) {
      console.log(`⚠️ Command is too old (${Math.round(ageMs / 1000)}s), marking as timeout`);
      await commandRef.update({
        status: "timeout",
        error: "Command expired (older than 5 minutes)",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    // Mark as executing
    await commandRef.update({
      status: "executing",
    });

    try {
      // Build the WLED endpoint URL
      // The webhook URL should be the base URL (e.g., https://myhome.duckdns.org:8080)
      // We append the appropriate WLED JSON API path
      let endpoint;
      let method = "POST";
      let body = null;

      const baseUrl = commandData.webhookUrl.replace(/\/$/, ""); // Remove trailing slash

      // The Dart app stores payload as a JSON string in Firestore (to avoid
      // nested-array issues with the iOS Firestore SDK). Detect this and avoid
      // double-encoding: if it's already a string, use it directly; if it's an
      // object (legacy or bridge-written), JSON.stringify it.
      const rawPayload = commandData.payload;
      const payloadString =
        typeof rawPayload === "string" ? rawPayload : JSON.stringify(rawPayload);

      switch (commandData.type) {
        case "getState":
          endpoint = `${baseUrl}/json/state`;
          method = "GET";
          break;
        case "getInfo":
          endpoint = `${baseUrl}/json/info`;
          method = "GET";
          break;
        case "setState":
        case "applyJson":
        case "configureSyncReceiver":
        case "configureSyncSender":
        case "renameSegment":
        case "applyToSegments":
        case "savePreset":
        case "loadPreset":
          endpoint = `${baseUrl}/json/state`;
          body = payloadString;
          break;
        case "applyConfig":
          endpoint = `${baseUrl}/json/cfg`;
          body = payloadString;
          break;
        default:
          endpoint = `${baseUrl}/json/state`;
          body = payloadString;
      }

      console.log(`📡 Calling ${method} ${endpoint}`);

      // Execute the HTTP request to the user's WLED device
      const fetchOptions = {
        method,
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      };

      if (body && method !== "GET") {
        fetchOptions.body = body;
        console.log(`   Body: ${body.substring(0, 200)}...`);
      }

      const response = await fetch(endpoint, fetchOptions);

      if (!response.ok) {
        const errorText = await response.text();
        console.error(`❌ WLED request failed: ${response.status} ${errorText}`);
        await commandRef.update({
          status: "failed",
          error: `HTTP ${response.status}: ${errorText.substring(0, 200)}`,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      // Parse response
      let result;
      const contentType = response.headers.get("content-type");
      if (contentType && contentType.includes("application/json")) {
        result = await response.json();
      } else {
        result = { success: true, rawResponse: await response.text() };
      }

      console.log(`✅ Command executed successfully`);

      // Update command with success result.
      // Store result as a JSON string (matching Dart-side convention) to avoid
      // nested-array structures that crash the iOS Firestore SDK.
      await commandRef.update({
        status: "completed",
        result: typeof result === "string" ? result : JSON.stringify(result),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error(`❌ Error executing command: ${error.message}`);
      await commandRef.update({
        status: "failed",
        error: error.message,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

// ============================================================================
// ALEXA ACCOUNT LINKING OAUTH ENDPOINTS
// ============================================================================

/**
 * Generate secure authorization code for Alexa OAuth
 *
 * SECURITY: Stores authorization codes server-side with cryptographic tokens
 * instead of client-side base64 encoding
 */
exports.generateAlexaAuthCode = onCall({ region: "us-central1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const { idToken, state } = request.data;

  if (!idToken || !state) {
    throw new HttpsError("invalid-argument", "Missing required parameters");
  }

  try {
    // Verify the ID token
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const userId = decodedToken.uid;

    // SECURITY: Generate cryptographically secure authorization code
    const crypto = require("crypto");
    const authCode = crypto.randomBytes(32).toString("base64url");

    // Store the authorization code in Firestore with expiration
    await db.collection("oauth_codes").doc(authCode).set({
      userId: userId,
      state: state,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 5 * 60 * 1000) // 5 minutes
      ),
      used: false,
    });

    console.log(`Generated auth code for user ${userId}`);

    return { code: authCode };
  } catch (error) {
    console.error("Error generating auth code:", error);
    throw new HttpsError("internal", error.message);
  }
});
// These endpoints implement OAuth 2.0 authorization code flow for Alexa
// Smart Home Skill account linking.
//
// Flow:
// 1. User enables skill in Alexa app
// 2. Alexa redirects to /alexaAuth with client_id, redirect_uri, state
// 3. User signs in with Firebase Auth
// 4. We redirect back to Alexa with authorization code
// 5. Alexa calls /alexaToken to exchange code for access token
// 6. We return Firebase ID token as the access token
// ============================================================================

/**
 * Alexa OAuth Authorization Endpoint
 *
 * This endpoint handles the initial OAuth authorization request from Alexa.
 * It displays a login page where users sign in with their Firebase credentials.
 *
 * Query Parameters:
 * - client_id: Alexa skill client ID
 * - redirect_uri: Alexa callback URL
 * - state: OAuth state parameter (must be returned)
 * - response_type: Should be "code"
 */
exports.alexaAuth = onRequest({ region: "us-central1" }, async (req, res) => {
  // SECURITY: Add security headers
  addSecurityHeaders(res);

  const { client_id, redirect_uri, state, response_type } = req.query;

  // Validate required parameters
  if (!client_id || !redirect_uri || !state) {
    res.status(400).send("Missing required OAuth parameters");
    return;
  }

  // Validate client_id matches our Alexa skill
  const expectedClientId = alexaClientId.value();
  if (expectedClientId && client_id !== expectedClientId) {
    console.error(`Invalid client_id: ${client_id}`);
    res.status(400).send("Invalid client_id");
    return;
  }

  // Validate redirect_uri is from Amazon
  if (!redirect_uri.includes("amazon.com") && !redirect_uri.includes("alexa.amazon")) {
    console.error(`Invalid redirect_uri: ${redirect_uri}`);
    res.status(400).send("Invalid redirect_uri");
    return;
  }

  // SECURITY: Generate a secure state token to prevent CSRF attacks
  const secureState = Buffer.from(JSON.stringify({
    originalState: state,
    timestamp: Date.now(),
    nonce: Math.random().toString(36).substring(7)
  })).toString('base64');

  // Return a simple HTML login page
  // In production, you might want to use Firebase Hosting for a nicer UI
  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Link Nex-Gen Lumina to Alexa</title>
  <!-- SECURITY: Load Firebase SDK from CDN -->
  <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-auth-compat.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .container {
      background: rgba(255,255,255,0.05);
      backdrop-filter: blur(10px);
      border-radius: 16px;
      padding: 40px;
      max-width: 400px;
      width: 100%;
      border: 1px solid rgba(255,255,255,0.1);
    }
    .logo {
      width: 80px;
      height: 80px;
      background: linear-gradient(135deg, #00e5ff 0%, #7c4dff 100%);
      border-radius: 20px;
      margin: 0 auto 24px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 36px;
    }
    h1 {
      color: #fff;
      text-align: center;
      font-size: 24px;
      margin-bottom: 8px;
    }
    p {
      color: rgba(255,255,255,0.7);
      text-align: center;
      margin-bottom: 32px;
      font-size: 14px;
    }
    .form-group {
      margin-bottom: 16px;
    }
    label {
      display: block;
      color: rgba(255,255,255,0.9);
      margin-bottom: 8px;
      font-size: 14px;
    }
    input {
      width: 100%;
      padding: 12px 16px;
      border: 1px solid rgba(255,255,255,0.2);
      border-radius: 8px;
      background: rgba(255,255,255,0.05);
      color: #fff;
      font-size: 16px;
    }
    input:focus {
      outline: none;
      border-color: #00e5ff;
    }
    button {
      width: 100%;
      padding: 14px;
      background: linear-gradient(135deg, #00e5ff 0%, #00b8d4 100%);
      border: none;
      border-radius: 8px;
      color: #000;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      margin-top: 8px;
    }
    button:hover { opacity: 0.9; }
    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }
    .error {
      color: #ff5252;
      text-align: center;
      margin-top: 16px;
      font-size: 14px;
    }
    .loading {
      display: none;
      text-align: center;
      color: #00e5ff;
      margin-top: 16px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">💡</div>
    <h1>Link to Alexa</h1>
    <p>Sign in with your Nex-Gen Lumina account to enable voice control with Alexa.</p>

    <form id="loginForm">
      <div class="form-group">
        <label for="email">Email</label>
        <input type="email" id="email" required placeholder="you@example.com">
      </div>
      <div class="form-group">
        <label for="password">Password</label>
        <input type="password" id="password" required placeholder="Your password">
      </div>
      <button type="submit" id="submitBtn">Link Account</button>
    </form>

    <div class="loading" id="loading">Linking your account...</div>
    <div class="error" id="error"></div>
  </div>

  <script>
    // Firebase config for Nex-Gen Lumina
    const firebaseConfig = {
      apiKey: "AIzaSyB2VhrbVD1lBbs_b_JuCkjLa1Yh_AsbWJs",
      authDomain: "icrt6menwsv2d8all8oijs021b06s5.firebaseapp.com",
      projectId: "icrt6menwsv2d8all8oijs021b06s5",
    };

    firebase.initializeApp(firebaseConfig);

    const redirectUri = decodeURIComponent("${redirect_uri}");
    const state = "${state}";

    document.getElementById('loginForm').addEventListener('submit', async (e) => {
      e.preventDefault();

      const email = document.getElementById('email').value;
      const password = document.getElementById('password').value;
      const submitBtn = document.getElementById('submitBtn');
      const loading = document.getElementById('loading');
      const error = document.getElementById('error');

      submitBtn.disabled = true;
      loading.style.display = 'block';
      error.textContent = '';

      try {
        // Sign in with Firebase
        const userCredential = await firebase.auth().signInWithEmailAndPassword(email, password);
        const user = userCredential.user;

        // Get the ID token
        const idToken = await user.getIdToken();

        // SECURITY: Call backend to generate secure authorization code
        // The code is stored server-side in Firestore, not in client-side base64
        const generateCodeFunction = firebase.functions().httpsCallable('generateAlexaAuthCode');
        const result = await generateCodeFunction({
          idToken: idToken,
          state: "${secureState}"
        });

        const authCode = result.data.code;

        // Redirect back to Alexa with the authorization code
        const callbackUrl = redirectUri + '?state=' + encodeURIComponent(state) + '&code=' + encodeURIComponent(authCode);
        window.location.href = callbackUrl;

      } catch (err) {
        console.error('Login error:', err);
        error.textContent = err.message || 'Failed to sign in. Please try again.';
        submitBtn.disabled = false;
        loading.style.display = 'none';
      }
    });
  </script>
</body>
</html>
  `;

  res.status(200).send(html);
});

/**
 * Alexa OAuth Token Endpoint
 *
 * Exchanges authorization code for access token.
 * Also handles refresh token requests.
 *
 * POST Body:
 * - grant_type: "authorization_code" or "refresh_token"
 * - code: The authorization code (for authorization_code grant)
 * - refresh_token: The refresh token (for refresh_token grant)
 * - client_id: Alexa skill client ID
 * - client_secret: Alexa skill client secret
 */
exports.alexaToken = onRequest({ region: "us-central1" }, async (req, res) => {
  // SECURITY: Add security headers
  addSecurityHeaders(res);

  // Only allow POST
  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }

  const { grant_type, code, refresh_token, client_id, client_secret } = req.body;

  // Validate client credentials
  const expectedClientId = alexaClientId.value();
  const expectedClientSecret = alexaClientSecret.value();

  if (expectedClientId && expectedClientSecret) {
    if (client_id !== expectedClientId || client_secret !== expectedClientSecret) {
      console.error("Invalid client credentials");
      res.status(401).json({ error: "invalid_client" });
      return;
    }
  }

  try {
    if (grant_type === "authorization_code") {
      // SECURITY: Look up authorization code from Firestore
      const codeDoc = await db.collection("oauth_codes").doc(code).get();

      if (!codeDoc.exists) {
        console.error("Invalid authorization code");
        res.status(400).json({ error: "invalid_grant", error_description: "Invalid authorization code" });
        return;
      }

      const codeData = codeDoc.data();

      // SECURITY: Validate the code hasn't been used
      if (codeData.used) {
        console.error("Authorization code already used");
        res.status(400).json({ error: "invalid_grant", error_description: "Authorization code already used" });
        return;
      }

      // SECURITY: Validate the code hasn't expired
      if (Date.now() > codeData.expiresAt.toDate().getTime()) {
        console.error("Authorization code expired");
        res.status(400).json({ error: "invalid_grant", error_description: "Authorization code expired" });
        return;
      }

      const userId = codeData.userId;

      // Mark the code as used (one-time use only)
      await codeDoc.ref.update({ used: true });

      // Generate a fresh custom token for the user
      const customToken = await admin.auth().createCustomToken(userId);

      // Store the link in Firestore
      await db.collection("users").doc(userId).collection("integrations").doc("alexa").set({
        isLinked: true,
        linkedAt: admin.firestore.FieldValue.serverTimestamp(),
        amazonUserId: client_id, // In reality, Alexa sends the user ID in directives
      }, { merge: true });

      console.log(`Alexa account linked for user ${userId}`);

      // SECURITY: Generate cryptographically secure refresh token
      const crypto = require("crypto");
      const refreshToken = crypto.randomBytes(32).toString("base64url");

      // Store refresh token in Firestore
      await db.collection("oauth_refresh_tokens").doc(refreshToken).set({
        userId: userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        active: true,
      });

      // Return tokens
      res.json({
        access_token: customToken,
        token_type: "Bearer",
        expires_in: 3600,
        refresh_token: refreshToken,
      });

    } else if (grant_type === "refresh_token") {
      // SECURITY: Look up refresh token from Firestore
      const tokenDoc = await db.collection("oauth_refresh_tokens").doc(refresh_token).get();

      if (!tokenDoc.exists) {
        console.error("Invalid refresh token");
        res.status(400).json({ error: "invalid_grant", error_description: "Invalid refresh token" });
        return;
      }

      const tokenData = tokenDoc.data();

      // SECURITY: Validate token is still active
      if (!tokenData.active) {
        console.error("Refresh token revoked");
        res.status(400).json({ error: "invalid_grant", error_description: "Refresh token revoked" });
        return;
      }

      const userId = tokenData.userId;

      // Generate a new custom token for the user
      const customToken = await admin.auth().createCustomToken(userId);

      console.log(`Refreshed access token for user ${userId}`);

      res.json({
        access_token: customToken,
        token_type: "Bearer",
        expires_in: 3600,
        refresh_token: refresh_token, // Return the same refresh token
      });

    } else {
      res.status(400).json({ error: "unsupported_grant_type" });
    }

  } catch (error) {
    console.error("Token exchange error:", error);
    res.status(400).json({ error: "invalid_grant", error_description: error.message });
  }
});

/**
 * Alexa Account Unlink Notification
 *
 * Called when user disables the skill or unlinks account in Alexa app.
 */
exports.alexaUnlink = onRequest({ region: "us-central1" }, async (req, res) => {
  // SECURITY: Add security headers
  addSecurityHeaders(res);

  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const token = authHeader.substring(7);

  try {
    // Verify the token and get user ID
    const decodedToken = await admin.auth().verifyIdToken(token);
    const userId = decodedToken.uid;

    // Remove the Alexa integration
    await db.collection("users").doc(userId).collection("integrations").doc("alexa").delete();

    // SECURITY: Revoke all refresh tokens for this user
    const refreshTokens = await db.collection("oauth_refresh_tokens")
      .where("userId", "==", userId)
      .get();

    const batch = db.batch();
    refreshTokens.docs.forEach((doc) => {
      batch.update(doc.ref, { active: false });
    });
    await batch.commit();

    console.log(`Alexa account unlinked for user ${userId}, revoked ${refreshTokens.size} refresh tokens`);
    res.status(200).json({ success: true });

  } catch (error) {
    console.error("Unlink error:", error);
    res.status(400).json({ error: "invalid_token" });
  }
});

// ============================================================================
// SECURITY MONITORING & UTILITIES
// ============================================================================

/**
 * Add security headers to HTTP responses
 * Prevents XSS, clickjacking, and other common attacks
 */
function addSecurityHeaders(res) {
  res.set("X-Content-Type-Options", "nosniff");
  res.set("X-Frame-Options", "DENY");
  res.set("X-XSS-Protection", "1; mode=block");
  res.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  res.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.set("Permissions-Policy", "geolocation=(), microphone=(), camera=()");
}

/**
 * Scheduled function to clean up old data
 * Runs daily at midnight UTC to maintain 90-day retention policy
 *
 * Cleans up:
 * - AI usage logs older than 90 days
 * - Pattern usage logs older than 90 days
 * - Detected habits older than 90 days
 * - Expired OAuth codes
 * - Suggestions older than 30 days
 * - Crash-sink records (debug_errors) older than 30 days
 */
// Shared cleanup routine. Extracted from the onCall handler so a scheduled
// trigger can run it too (Slice 0 — previously onCall-only, so it NEVER fired
// automatically and command docs accumulated forever). Returns the stats map;
// throws on error for the caller to handle.
// Per-user delete cap for every subcollection this routine drains (C5,
// audit/DIAGNOSTICS_FIX.md). A Firestore batch commits at most 500 operations,
// so an UNBOUNDED query that matches >500 docs for a single user fails
// batch.commit() and — because the whole routine is one try/catch — ABORTS THE
// ENTIRE RUN, starving every user later in the loop. Silent and total.
//
// 450 leaves headroom under 500 and is the value already proven by the commands
// and debug_errors blocks. Every capped query filters on a single timestamp
// field with no second filter and no orderBy, so it is served by the automatic
// single-field index; adding a limit does NOT create a composite-index
// requirement. Backlogs drain over successive daily runs.
const PER_USER_DELETE_CAP = 450;

// oauth_codes is the one collection that must NOT simply reuse the cap above —
// see the drain loop at the end of runDataCleanup() for why.
const OAUTH_CODES_MAX_PAGES = 5;

async function runDataCleanup() {
    const USAGE_RETENTION_DAYS = 90;
    const SUGGESTIONS_RETENTION_DAYS = 30;
    const COMMANDS_RETENTION_DAYS = 7;
    const DEBUG_ERRORS_RETENTION_DAYS = 30;
    const usageCutoff = new Date();
    usageCutoff.setDate(usageCutoff.getDate() - USAGE_RETENTION_DAYS);
    const usageCutoffTimestamp = admin.firestore.Timestamp.fromDate(usageCutoff);

    const suggestionsCutoff = new Date();
    suggestionsCutoff.setDate(suggestionsCutoff.getDate() - SUGGESTIONS_RETENTION_DAYS);
    const suggestionsCutoffTimestamp = admin.firestore.Timestamp.fromDate(suggestionsCutoff);

    const commandsCutoff = new Date();
    commandsCutoff.setDate(commandsCutoff.getDate() - COMMANDS_RETENTION_DAYS);
    const commandsCutoffTimestamp = admin.firestore.Timestamp.fromDate(commandsCutoff);

    const debugErrorsCutoff = new Date();
    debugErrorsCutoff.setDate(debugErrorsCutoff.getDate() - DEBUG_ERRORS_RETENTION_DAYS);
    const debugErrorsCutoffTimestamp =
      admin.firestore.Timestamp.fromDate(debugErrorsCutoff);

    console.log(`Starting data cleanup:
      - Usage logs older than ${usageCutoff.toISOString()}
      - Suggestions older than ${suggestionsCutoff.toISOString()}
      - Crash-sink records older than ${debugErrorsCutoff.toISOString()}
      - Expired OAuth codes`);

    try {
      let stats = {
        aiUsage: 0,
        patternUsage: 0,
        habits: 0,
        suggestions: 0,
        commands: 0,
        oauthCodes: 0,
        debugErrors: 0,
      };

      // Get all users
      const usersSnapshot = await db.collection("users").get();

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;

        // Clean up AI usage logs.
        //
        // limit(PER_USER_DELETE_CAP) — see the constant's comment. Queries
        // `timestamp` only (single-field auto-index); the limit does not
        // introduce a composite-index requirement.
        const oldAiLogs = await db
          .collection("users")
          .doc(userId)
          .collection("ai_usage")
          .where("timestamp", "<", usageCutoffTimestamp)
          .limit(PER_USER_DELETE_CAP)
          .get();

        if (oldAiLogs.size > 0) {
          const batch1 = db.batch();
          oldAiLogs.docs.forEach((doc) => batch1.delete(doc.ref));
          await batch1.commit();
          stats.aiUsage += oldAiLogs.size;
        }

        // Clean up pattern usage logs. Bounded; `created_at` only.
        const oldPatternLogs = await db
          .collection("users")
          .doc(userId)
          .collection("pattern_usage")
          .where("created_at", "<", usageCutoffTimestamp)
          .limit(PER_USER_DELETE_CAP)
          .get();

        if (oldPatternLogs.size > 0) {
          const batch2 = db.batch();
          oldPatternLogs.docs.forEach((doc) => batch2.delete(doc.ref));
          await batch2.commit();
          stats.patternUsage += oldPatternLogs.size;
        }

        // Clean up old detected habits. Bounded; `detected_at` only.
        const oldHabits = await db
          .collection("users")
          .doc(userId)
          .collection("detected_habits")
          .where("detected_at", "<", usageCutoffTimestamp)
          .limit(PER_USER_DELETE_CAP)
          .get();

        if (oldHabits.size > 0) {
          const batch3 = db.batch();
          oldHabits.docs.forEach((doc) => batch3.delete(doc.ref));
          await batch3.commit();
          stats.habits += oldHabits.size;
        }

        // Clean up old suggestions. Bounded; `created_at` only. This is the
        // collection that motivated C5 — it grows with usage, so it is the
        // most likely of the five to reach 500 for a single user.
        const oldSuggestions = await db
          .collection("users")
          .doc(userId)
          .collection("suggestions")
          .where("created_at", "<", suggestionsCutoffTimestamp)
          .limit(PER_USER_DELETE_CAP)
          .get();

        if (oldSuggestions.size > 0) {
          const batch4 = db.batch();
          oldSuggestions.docs.forEach((doc) => batch4.delete(doc.ref));
          await batch4.commit();
          stats.suggestions += oldSuggestions.size;
        }

        // Clean up old WLED relay command docs (Slice 0 — the TTL). Any command
        // past the retention window is terminal-or-abandoned: the bridge/app
        // acted on it long ago. Bounded per run (limit 450) to stay under the
        // 500-op batch cap; the daily schedule drains any backlog over
        // successive runs. Queries createdAt only (single-field auto-index), so
        // no composite index is needed.
        const oldCommands = await db
          .collection("users")
          .doc(userId)
          .collection("commands")
          .where("createdAt", "<", commandsCutoffTimestamp)
          .limit(PER_USER_DELETE_CAP)
          .get();

        if (oldCommands.size > 0) {
          const batchC = db.batch();
          oldCommands.docs.forEach((doc) => batchC.delete(doc.ref));
          await batchC.commit();
          stats.commands += oldCommands.size;
        }

        // Clean up old crash-sink records (audit/DIAGNOSTICS_DECLARATION.md §4).
        //
        // users/{uid}/debug_errors is written by the global uncaught-error sink
        // in main.dart and holds error text + stack traces keyed to the uid. It
        // was absent from this routine entirely, so it had NO retention at all —
        // even a correctly deployed cleanup would never have touched it. That is
        // a data-minimisation problem on top of a declaration one: "how long do
        // you keep it?" had no good answer for a reviewer or a data-subject
        // request.
        //
        // 30 days: the sink exists to answer "what crashed recently" — Tyler has
        // no Crashlytics and no Mac, so he reads these in the console within
        // days of a report. Older records have no diagnostic value.
        //
        // Same bounded shape as the commands block above: limit 450 keeps a
        // single user's backlog under the 500-op batch cap, and successive daily
        // runs drain the rest. Queries `timestamp` only (single-field
        // auto-index), so no composite index is required.
        const oldDebugErrors = await db
          .collection("users")
          .doc(userId)
          .collection("debug_errors")
          .where("timestamp", "<", debugErrorsCutoffTimestamp)
          .limit(PER_USER_DELETE_CAP)
          .get();

        if (oldDebugErrors.size > 0) {
          const batchD = db.batch();
          oldDebugErrors.docs.forEach((doc) => batchD.delete(doc.ref));
          await batchD.commit();
          stats.debugErrors += oldDebugErrors.size;
        }
      }

      // Clean up expired OAuth codes (> 1 hour old).
      //
      // THIS ONE IS DELIBERATELY NOT A PLAIN limit(450), and it is the only one
      // of the five that differs. Two properties make it unlike the per-user
      // subcollections above:
      //
      //   1. It is TOP-LEVEL and sits OUTSIDE the per-user loop, so it runs
      //      once per invocation. A bare cap would be 450 per RUN in total,
      //      not 450 per user — roughly a 24x smaller drain rate here.
      //   2. Its retention window is ONE HOUR, not 30 or 90 days. These are
      //      spent OAuth authorization codes; letting them accumulate for days
      //      because of a throughput ceiling is a poor match for a
      //      security-sensitive artifact with a one-hour life.
      //
      // Capping it at a flat 450 would therefore have been a REGRESSION: the
      // unbounded query drained every expired code on each run, and a bare cap
      // would newly strand the remainder until the next day. So it pages
      // instead — bounded work per page to protect the batch limit, repeated
      // until exhausted, with a hard page ceiling so a runaway backlog cannot
      // threaten the 60s function timeout (measured at 17.4s on the heaviest
      // run to date; see audit/DIAGNOSTICS_FIX.md C4).
      const oneHourAgo = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 60 * 60 * 1000));
      for (let page = 0; page < OAUTH_CODES_MAX_PAGES; page++) {
        const expiredCodes = await db
          .collection("oauth_codes")
          .where("createdAt", "<", oneHourAgo)
          .limit(PER_USER_DELETE_CAP)
          .get();

        if (expiredCodes.empty) break;

        const batch5 = db.batch();
        expiredCodes.docs.forEach((doc) => batch5.delete(doc.ref));
        await batch5.commit();
        stats.oauthCodes += expiredCodes.size;

        // A short page means the backlog is exhausted; no need to re-query.
        if (expiredCodes.size < PER_USER_DELETE_CAP) break;
      }

      console.log(`Cleanup complete:`, stats);
      return stats;
    } catch (error) {
      console.error("Cleanup error:", error);
      throw error;
    }
}

// Manual admin invocation (unchanged surface): callable, auth-gated. Returns
// the same { success, stats } envelope as before.
exports.cleanupOldData = onCall(
  { region: "us-central1" },
  async (request) => {
    // Only allow admin calls
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Admin access required");
    }
    try {
      const stats = await runDataCleanup();
      return { success: true, stats };
    } catch (error) {
      throw new HttpsError("internal", error.message);
    }
  }
);

// Scheduled trigger so cleanup ACTUALLY runs without a manual call — this is
// what finally gives users/{uid}/commands a real TTL (Slice 0). Daily 04:00 UTC.
exports.scheduledDataCleanup = onSchedule(
  { schedule: "0 4 * * *", region: "us-central1" },
  async () => {
    try {
      const stats = await runDataCleanup();
      console.log("scheduledDataCleanup complete:", stats);
    } catch (error) {
      console.error("scheduledDataCleanup error:", error);
    }
  }
);

// ============================================================================
// GOOGLE HOME SMART HOME ACTION ENDPOINTS
// ============================================================================

/**
 * Google Smart Home Fulfillment Endpoint
 *
 * Handles all Google Smart Home intents:
 * - SYNC: Returns available devices
 * - QUERY: Returns current device state
 * - EXECUTE: Executes commands
 * - DISCONNECT: Handles account unlinking
 */
exports.googleSmartHome = onRequest({ region: "us-central1" }, async (req, res) => {
  addSecurityHeaders(res);

  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const token = authHeader.substring(7);
  let userId;

  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    userId = decodedToken.uid;
  } catch (error) {
    console.error("Token verification failed:", error);
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const body = req.body;
  const { requestId } = body;
  const input = body.inputs?.[0];

  if (!input) {
    res.status(400).json({ error: "invalid_request" });
    return;
  }

  const intent = input.intent;
  console.log(`Google Home ${intent} for user ${userId}`);

  try {
    switch (intent) {
      case "action.devices.SYNC":
        res.json(await handleGoogleSync(requestId, userId));
        break;
      case "action.devices.QUERY":
        res.json(await handleGoogleQuery(requestId, userId, input.payload));
        break;
      case "action.devices.EXECUTE":
        res.json(await handleGoogleExecute(requestId, userId, input.payload));
        break;
      case "action.devices.DISCONNECT":
        await handleGoogleDisconnect(userId);
        res.json({});
        break;
      default:
        res.status(400).json({ error: "unsupported_intent" });
    }
  } catch (error) {
    console.error(`Google Home ${intent} error:`, error);
    res.status(500).json({ error: "internal_error" });
  }
});

/**
 * Handle Google SYNC intent
 */
async function handleGoogleSync(requestId, userId) {
  const userDoc = await db.collection("users").doc(userId).get();
  const profile = userDoc.exists ? userDoc.data() : {};
  const propertyName = profile.propertyName || "House Lights";

  const scenesSnapshot = await db
    .collection("users")
    .doc(userId)
    .collection("scenes")
    .get();

  const devices = [];

  // Main lighting device
  devices.push({
    id: "lumina-main",
    type: "action.devices.types.LIGHT",
    traits: [
      "action.devices.traits.OnOff",
      "action.devices.traits.Brightness",
    ],
    name: {
      name: propertyName,
      defaultNames: ["Lumina Lights", "House Lights"],
      nicknames: [propertyName, "outdoor lights", "house lights"],
    },
    willReportState: true,
    roomHint: "Outside",
    deviceInfo: {
      manufacturer: "Nex-Gen Lumina",
      model: "WLED Controller",
      hwVersion: "1.0",
      swVersion: "1.0",
    },
    customData: { userId, type: "main" },
  });

  // Add scenes
  scenesSnapshot.docs.forEach((doc) => {
    const scene = doc.data();
    if (scene.type === "system") return;

    devices.push({
      id: `scene-${doc.id}`,
      type: "action.devices.types.SCENE",
      traits: ["action.devices.traits.Scene"],
      name: {
        name: scene.name,
        defaultNames: [scene.name],
      },
      willReportState: false,
      attributes: { sceneReversible: false },
      customData: { userId, type: "scene", sceneId: doc.id },
    });
  });

  console.log(`Google SYNC returning ${devices.length} devices`);

  return {
    requestId,
    payload: {
      agentUserId: userId,
      devices,
    },
  };
}

/**
 * Handle Google QUERY intent
 */
async function handleGoogleQuery(requestId, userId, payload) {
  const { devices } = payload;
  const deviceStates = {};

  const stateDoc = await db
    .collection("users")
    .doc(userId)
    .collection("device_state")
    .doc("current")
    .get();

  const state = stateDoc.exists ? stateDoc.data() : { on: false, brightness: 200 };

  for (const device of devices) {
    if (device.id === "lumina-main") {
      deviceStates[device.id] = {
        online: true,
        on: state.on ?? false,
        brightness: Math.round((state.brightness ?? 200) / 255 * 100),
      };
    } else {
      deviceStates[device.id] = { online: true };
    }
  }

  return {
    requestId,
    payload: { devices: deviceStates },
  };
}

/**
 * Handle Google EXECUTE intent
 */
async function handleGoogleExecute(requestId, userId, payload) {
  const { commands } = payload;
  const results = [];

  for (const command of commands) {
    for (const device of command.devices) {
      for (const execution of command.execution) {
        try {
          const newState = await executeGoogleCommand(userId, device, execution);
          results.push({
            ids: [device.id],
            status: "SUCCESS",
            states: newState,
          });
        } catch (error) {
          console.error(`Execute error for ${device.id}:`, error);
          results.push({
            ids: [device.id],
            status: "ERROR",
            errorCode: error.code || "hardError",
          });
        }
      }
    }
  }

  return {
    requestId,
    payload: { commands: results },
  };
}

/**
 * Execute a Google command
 */
async function executeGoogleCommand(userId, device, execution) {
  const { command, params } = execution;
  let commandPayload = {};
  let newState = {};

  switch (command) {
    case "action.devices.commands.OnOff":
      commandPayload = { type: "power", payload: { on: params.on } };
      newState = { on: params.on };
      break;

    case "action.devices.commands.BrightnessAbsolute":
      const bri = Math.round(params.brightness / 100 * 255);
      commandPayload = { type: "brightness", payload: { brightness: bri, on: true } };
      newState = { on: true, brightness: params.brightness };
      break;

    case "action.devices.commands.ActivateScene":
      const sceneId = device.customData?.sceneId;
      if (!sceneId) throw { code: "notSupported" };
      commandPayload = { type: "scene", payload: { sceneId } };
      newState = { on: true };
      break;

    default:
      throw { code: "notSupported" };
  }

  // Send command to Firestore for processing
  await db.collection("users").doc(userId).collection("commands").add({
    type: commandPayload.type,
    payload: commandPayload.payload,
    controllerId: "primary",
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    source: "google_home",
    expiresAt: new Date(Date.now() + 60000),
  });

  return newState;
}

/**
 * Handle Google DISCONNECT intent
 */
async function handleGoogleDisconnect(userId) {
  await db
    .collection("users")
    .doc(userId)
    .collection("integrations")
    .doc("google_home")
    .set({
      isLinked: false,
      unlinkedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

  console.log(`Google Home unlinked for user ${userId}`);
}

/**
 * Google Home OAuth Authorization Endpoint
 */
exports.googleAuth = onRequest({ region: "us-central1" }, async (req, res) => {
  addSecurityHeaders(res);

  const { client_id, redirect_uri, state, response_type } = req.query;

  if (!client_id || !redirect_uri || !state) {
    res.status(400).send("Missing required OAuth parameters");
    return;
  }

  // Validate client_id
  const expectedClientId = googleClientId.value();
  if (expectedClientId && client_id !== expectedClientId) {
    res.status(400).send("Invalid client_id");
    return;
  }

  // Validate redirect_uri is from Google
  if (!redirect_uri.includes("google.com") && !redirect_uri.includes("googleusercontent.com")) {
    res.status(400).send("Invalid redirect_uri");
    return;
  }

  // Return login page (similar to Alexa but for Google)
  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Link Nex-Gen Lumina to Google Home</title>
  <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-auth-compat.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .container {
      background: rgba(255,255,255,0.05);
      backdrop-filter: blur(10px);
      border-radius: 16px;
      padding: 40px;
      max-width: 400px;
      width: 100%;
      border: 1px solid rgba(255,255,255,0.1);
    }
    .logo {
      width: 80px;
      height: 80px;
      background: linear-gradient(135deg, #4285f4 0%, #ea4335 25%, #fbbc05 50%, #34a853 75%);
      border-radius: 20px;
      margin: 0 auto 24px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 36px;
    }
    h1 { color: #fff; text-align: center; font-size: 24px; margin-bottom: 8px; }
    p { color: rgba(255,255,255,0.7); text-align: center; margin-bottom: 32px; font-size: 14px; }
    .form-group { margin-bottom: 16px; }
    label { display: block; color: rgba(255,255,255,0.9); margin-bottom: 8px; font-size: 14px; }
    input {
      width: 100%;
      padding: 12px 16px;
      border: 1px solid rgba(255,255,255,0.2);
      border-radius: 8px;
      background: rgba(255,255,255,0.05);
      color: #fff;
      font-size: 16px;
    }
    input:focus { outline: none; border-color: #4285f4; }
    button {
      width: 100%;
      padding: 14px;
      background: linear-gradient(135deg, #4285f4 0%, #34a853 100%);
      border: none;
      border-radius: 8px;
      color: #fff;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      margin-top: 8px;
    }
    button:hover { opacity: 0.9; }
    button:disabled { opacity: 0.5; cursor: not-allowed; }
    .error { color: #ff5252; text-align: center; margin-top: 16px; font-size: 14px; }
    .loading { display: none; text-align: center; color: #4285f4; margin-top: 16px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">🏠</div>
    <h1>Link to Google Home</h1>
    <p>Sign in with your Nex-Gen Lumina account to enable voice control with Google Assistant.</p>
    <form id="loginForm">
      <div class="form-group">
        <label for="email">Email</label>
        <input type="email" id="email" required placeholder="you@example.com">
      </div>
      <div class="form-group">
        <label for="password">Password</label>
        <input type="password" id="password" required placeholder="Your password">
      </div>
      <button type="submit" id="submitBtn">Link Account</button>
    </form>
    <div class="loading" id="loading">Linking your account...</div>
    <div class="error" id="error"></div>
  </div>
  <script>
    const firebaseConfig = {
      apiKey: "AIzaSyB2VhrbVD1lBbs_b_JuCkjLa1Yh_AsbWJs",
      authDomain: "icrt6menwsv2d8all8oijs021b06s5.firebaseapp.com",
      projectId: "icrt6menwsv2d8all8oijs021b06s5",
    };
    firebase.initializeApp(firebaseConfig);
    const redirectUri = decodeURIComponent("${redirect_uri}");
    const state = "${state}";
    document.getElementById('loginForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      const email = document.getElementById('email').value;
      const password = document.getElementById('password').value;
      const submitBtn = document.getElementById('submitBtn');
      const loading = document.getElementById('loading');
      const error = document.getElementById('error');
      submitBtn.disabled = true;
      loading.style.display = 'block';
      error.textContent = '';
      try {
        const userCredential = await firebase.auth().signInWithEmailAndPassword(email, password);
        const idToken = await userCredential.user.getIdToken();
        const generateCodeFunction = firebase.functions().httpsCallable('generateGoogleAuthCode');
        const result = await generateCodeFunction({ idToken, state });
        const authCode = result.data.code;
        window.location.href = redirectUri + '?state=' + encodeURIComponent(state) + '&code=' + encodeURIComponent(authCode);
      } catch (err) {
        error.textContent = err.message || 'Failed to sign in.';
        submitBtn.disabled = false;
        loading.style.display = 'none';
      }
    });
  </script>
</body>
</html>
  `;

  res.status(200).send(html);
});

/**
 * Generate secure authorization code for Google OAuth
 */
exports.generateGoogleAuthCode = onCall({ region: "us-central1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const { idToken, state } = request.data;

  if (!idToken || !state) {
    throw new HttpsError("invalid-argument", "Missing required parameters");
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const userId = decodedToken.uid;

    const crypto = require("crypto");
    const authCode = crypto.randomBytes(32).toString("base64url");

    await db.collection("google_oauth_codes").doc(authCode).set({
      userId,
      state,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)),
      used: false,
    });

    return { code: authCode };
  } catch (error) {
    console.error("Error generating Google auth code:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * Google Home OAuth Token Endpoint
 */
exports.googleToken = onRequest({ region: "us-central1" }, async (req, res) => {
  addSecurityHeaders(res);

  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }

  const { grant_type, code, refresh_token, client_id, client_secret } = req.body;

  // Validate client credentials
  const expectedClientId = googleClientId.value();
  const expectedClientSecret = googleClientSecret.value();

  if (expectedClientId && expectedClientSecret) {
    if (client_id !== expectedClientId || client_secret !== expectedClientSecret) {
      res.status(401).json({ error: "invalid_client" });
      return;
    }
  }

  try {
    if (grant_type === "authorization_code") {
      const codeDoc = await db.collection("google_oauth_codes").doc(code).get();

      if (!codeDoc.exists) {
        res.status(400).json({ error: "invalid_grant" });
        return;
      }

      const codeData = codeDoc.data();

      if (codeData.used || Date.now() > codeData.expiresAt.toDate().getTime()) {
        res.status(400).json({ error: "invalid_grant" });
        return;
      }

      const userId = codeData.userId;
      await codeDoc.ref.update({ used: true });

      const customToken = await admin.auth().createCustomToken(userId);

      await db.collection("users").doc(userId).collection("integrations").doc("google_home").set({
        isLinked: true,
        linkedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      const crypto = require("crypto");
      const refreshToken = crypto.randomBytes(32).toString("base64url");

      await db.collection("google_oauth_refresh_tokens").doc(refreshToken).set({
        userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        active: true,
      });

      console.log(`Google Home linked for user ${userId}`);

      res.json({
        access_token: customToken,
        token_type: "Bearer",
        expires_in: 3600,
        refresh_token: refreshToken,
      });

    } else if (grant_type === "refresh_token") {
      const tokenDoc = await db.collection("google_oauth_refresh_tokens").doc(refresh_token).get();

      if (!tokenDoc.exists || !tokenDoc.data().active) {
        res.status(400).json({ error: "invalid_grant" });
        return;
      }

      const userId = tokenDoc.data().userId;
      const customToken = await admin.auth().createCustomToken(userId);

      res.json({
        access_token: customToken,
        token_type: "Bearer",
        expires_in: 3600,
        refresh_token: refresh_token,
      });

    } else {
      res.status(400).json({ error: "unsupported_grant_type" });
    }
  } catch (error) {
    console.error("Google token error:", error);
    res.status(400).json({ error: "invalid_grant" });
  }
});

/**
 * Admin endpoint to get AI usage statistics
 * Useful for monitoring costs and detecting abuse
 */
exports.getAiUsageStats = onCall({ region: "us-central1" }, async (request) => {
  // Check authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const userId = request.auth.uid;

  try {
    // Get user's usage in last 30 days
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const usageSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("ai_usage")
      .where("timestamp", ">", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
      .where("status", "==", "success")
      .get();

    let totalRequests = 0;
    let totalTokens = 0;
    let totalCost = 0;

    usageSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      totalRequests++;
      totalTokens += data.tokensUsed || 0;
      totalCost += data.estimatedCost || 0;
    });

    return {
      period: "30_days",
      totalRequests: totalRequests,
      totalTokens: totalTokens,
      estimatedCost: totalCost,
      averageCostPerRequest: totalRequests > 0 ? totalCost / totalRequests : 0,
    };
  } catch (error) {
    console.error("Error getting usage stats:", error);
    throw new HttpsError("internal", error.message);
  }
});
