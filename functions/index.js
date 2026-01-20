const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

// Define the OpenAI API key parameter (reads from .env file)
const openaiApiKey = defineString("OPENAI_API_KEY");

/**
 * OpenAI Proxy Cloud Function for Lumina AI
 *
 * This function acts as a secure proxy between the Flutter app and OpenAI API.
 * The API key is stored in .env file in the functions folder.
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

  try {
    // Forward the request to OpenAI
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(request.data),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("OpenAI API error:", response.status, errorText);
      throw new HttpsError(
        "internal",
        `OpenAI API error: ${response.status}`
      );
    }

    const result = await response.json();
    return result;
  } catch (error) {
    console.error("OpenAI proxy error:", error);
    throw new HttpsError("internal", error.message);
  }
});

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
