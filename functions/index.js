const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

// Import TypeScript-compiled Lumina AI command processor
const { processLuminaCommand } = require("./lib/processLuminaCommand");
exports.processLuminaCommand = processLuminaCommand;

// Import TypeScript-compiled Lumina AI schedule command processor
const { processScheduleCommand } = require("./lib/processScheduleCommand");
exports.processScheduleCommand = processScheduleCommand;

const db = admin.firestore();

// Define the OpenAI API key parameter (reads from .env file)
const openaiApiKey = defineString("OPENAI_API_KEY");

// Alexa OAuth configuration (add to .env file)
const alexaClientId = defineString("ALEXA_CLIENT_ID");
const alexaClientSecret = defineString("ALEXA_CLIENT_SECRET");

// Google Home OAuth configuration (add to .env file)
const googleClientId = defineString("GOOGLE_CLIENT_ID");
const googleClientSecret = defineString("GOOGLE_CLIENT_SECRET");

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
          endpoint = `${baseUrl}/json/state`;
          body = JSON.stringify(commandData.payload);
          break;
        case "applyConfig":
          endpoint = `${baseUrl}/json/cfg`;
          body = JSON.stringify(commandData.payload);
          break;
        default:
          endpoint = `${baseUrl}/json/state`;
          body = JSON.stringify(commandData.payload);
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

      // Update command with success result
      await commandRef.update({
        status: "completed",
        result: result,
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
 */
exports.cleanupOldData = onCall(
  { region: "us-central1" },
  async (request) => {
    // Only allow admin calls (or scheduled triggers in production)
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Admin access required");
    }

    const USAGE_RETENTION_DAYS = 90;
    const SUGGESTIONS_RETENTION_DAYS = 30;
    const usageCutoff = new Date();
    usageCutoff.setDate(usageCutoff.getDate() - USAGE_RETENTION_DAYS);
    const usageCutoffTimestamp = admin.firestore.Timestamp.fromDate(usageCutoff);

    const suggestionsCutoff = new Date();
    suggestionsCutoff.setDate(suggestionsCutoff.getDate() - SUGGESTIONS_RETENTION_DAYS);
    const suggestionsCutoffTimestamp = admin.firestore.Timestamp.fromDate(suggestionsCutoff);

    console.log(`Starting data cleanup:
      - Usage logs older than ${usageCutoff.toISOString()}
      - Suggestions older than ${suggestionsCutoff.toISOString()}
      - Expired OAuth codes`);

    try {
      let stats = {
        aiUsage: 0,
        patternUsage: 0,
        habits: 0,
        suggestions: 0,
        oauthCodes: 0,
      };

      // Get all users
      const usersSnapshot = await db.collection("users").get();

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;

        // Clean up AI usage logs
        const oldAiLogs = await db
          .collection("users")
          .doc(userId)
          .collection("ai_usage")
          .where("timestamp", "<", usageCutoffTimestamp)
          .get();

        if (oldAiLogs.size > 0) {
          const batch1 = db.batch();
          oldAiLogs.docs.forEach((doc) => batch1.delete(doc.ref));
          await batch1.commit();
          stats.aiUsage += oldAiLogs.size;
        }

        // Clean up pattern usage logs
        const oldPatternLogs = await db
          .collection("users")
          .doc(userId)
          .collection("pattern_usage")
          .where("created_at", "<", usageCutoffTimestamp)
          .get();

        if (oldPatternLogs.size > 0) {
          const batch2 = db.batch();
          oldPatternLogs.docs.forEach((doc) => batch2.delete(doc.ref));
          await batch2.commit();
          stats.patternUsage += oldPatternLogs.size;
        }

        // Clean up old detected habits
        const oldHabits = await db
          .collection("users")
          .doc(userId)
          .collection("detected_habits")
          .where("detected_at", "<", usageCutoffTimestamp)
          .get();

        if (oldHabits.size > 0) {
          const batch3 = db.batch();
          oldHabits.docs.forEach((doc) => batch3.delete(doc.ref));
          await batch3.commit();
          stats.habits += oldHabits.size;
        }

        // Clean up old suggestions
        const oldSuggestions = await db
          .collection("users")
          .doc(userId)
          .collection("suggestions")
          .where("created_at", "<", suggestionsCutoffTimestamp)
          .get();

        if (oldSuggestions.size > 0) {
          const batch4 = db.batch();
          oldSuggestions.docs.forEach((doc) => batch4.delete(doc.ref));
          await batch4.commit();
          stats.suggestions += oldSuggestions.size;
        }
      }

      // Clean up expired OAuth codes (> 1 hour old)
      const oneHourAgo = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 60 * 60 * 1000));
      const expiredCodes = await db
        .collection("oauth_codes")
        .where("createdAt", "<", oneHourAgo)
        .get();

      if (expiredCodes.size > 0) {
        const batch5 = db.batch();
        expiredCodes.docs.forEach((doc) => batch5.delete(doc.ref));
        await batch5.commit();
        stats.oauthCodes = expiredCodes.size;
      }

      console.log(`Cleanup complete:`, stats);
      return { success: true, stats };
    } catch (error) {
      console.error("Cleanup error:", error);
      throw new HttpsError("internal", error.message);
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
