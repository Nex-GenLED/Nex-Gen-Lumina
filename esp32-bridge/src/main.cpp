/**
 * Lumina ESP32 Bridge v1.2
 *
 * This firmware runs on an ESP32 and acts as a bridge between
 * Firebase Firestore and WLED devices on the local network.
 *
 * How it works:
 * 1. Connects to local WiFi network
 * 2. Starts local HTTP API + mDNS so the Lumina app can discover & pair
 * 3. Signs in to Firebase Auth to get an ID token
 * 4. Polls Firestore for pending commands (using Bearer token auth)
 * 5. Executes commands by making HTTP requests to WLED devices
 * 6. Updates command status in Firestore
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WiFiManager.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <time.h>

#include "config.h"

// ============================================================================
// Global Variables
// ============================================================================

WiFiClientSecure secureClient;
WebServer server(80);
Preferences prefs;
// True when setup() loaded a UID from NVS (i.e. bridge was paired by the app
// at some point, not just running on compile-time defaults). Surfaced via
// /api/info so the app can detect whether the bridge needs initial pairing.
bool nvsUidFound = false;
bool firebaseReady = false;
unsigned long lastPollTime = 0;
unsigned long lastBlinkTime = 0;
unsigned long lastHeartbeatTime = 0;
unsigned long lastRegistryUpdateTime = 0;
unsigned long lastPairingPollTime = 0;
unsigned long commandsProcessed = 0;
unsigned long commandErrors = 0;
unsigned long bootTime = 0;
unsigned long lastSuccessfulPoll = 0; // millis() of last successful command or heartbeat

// Registry self-registration cadence
#define REGISTRY_HEARTBEAT_INTERVAL_MS 30000
#define PAIRING_POLL_INTERVAL_MS 5000
#define BRIDGE_FIRMWARE_VERSION "1.2"

// Firebase Auth tokens
String firebaseIdToken = "";
String firebaseRefreshToken = "";
unsigned long tokenExpiresAt = 0;  // millis() when token expires
bool firebaseAuthenticated = false;

// Pairing state — initial values come from compile-time config, then are
// overwritten in setup() with NVS-saved values if a previous pair occurred.
bool isPaired = false;
String pairedUserId = FIREBASE_USER_UID;
String pairedWledIp = DEFAULT_WLED_IP;

// Device identity
String deviceName = "Lumina-";
// MAC address with colons stripped (e.g. "D4E9F4FA54B8"). Used as the
// document ID under /bridge_registry — stable across reboots and unique
// per chip, so the app can find this bridge in Firestore without mDNS
// or local network scanning.
String deviceId = "";

// Firestore base URL
String firestoreBaseUrl() {
  return "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) +
         "/databases/(default)/documents/users/" + pairedUserId;
}

// URL of this bridge's document under /bridge_registry/{deviceId}.
// Top-level path so the bridge can register itself before it knows
// which user it belongs to.
String bridgeRegistryUrl() {
  return "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) +
         "/databases/(default)/documents/bridge_registry/" + deviceId;
}

// ============================================================================
// Function Declarations
// ============================================================================

void setupWiFi();
void setupMDNS();
void setupWebServer();
void setupFirebase();
bool signInFirebase();
bool refreshFirebaseToken();
bool ensureValidToken();
void pollCommands();
void executeCommand(const String& commandId, JsonObject& fields);
String makeWledRequest(const String& ip, const String& method,
                       const String& endpoint, const String& body);
void updateCommandStatus(const String& commandId, const String& status,
                         const String& error = "",
                         const String& result = "");
void writeHeartbeat();
void registerBridgeInRegistry();
void updateRegistryHeartbeat();
bool pollPairingRequest();
void blinkLed(int times, int delayMs);
void statusBlink();
String convertFirestorePayloadToJson(JsonObject& fields);

// Web server handlers
void handleApiInfo();
void handleBridgeStatus();
void handleBridgePair();
void handleBridgeAuth();
void handleReboot();
void handleReset();
void handleNotFound();

// ============================================================================
// Setup
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println();
  Serial.println("=========================================");
  Serial.println("   Lumina ESP32 Bridge v1.2");
  Serial.println("=========================================");
  Serial.println();

  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);

  blinkLed(5, 100);

  // Build device name from MAC
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char suffix[5];
  snprintf(suffix, sizeof(suffix), "%02X%02X", mac[4], mac[5]);
  deviceName += String(suffix);

  // Stable per-chip ID for /bridge_registry/{deviceId}
  char idBuf[13];
  snprintf(idBuf, sizeof(idBuf), "%02X%02X%02X%02X%02X%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  deviceId = String(idBuf);

  Serial.print("Device name: ");
  Serial.println(deviceName);
  Serial.print("Device ID: ");
  Serial.println(deviceId);

  // Mark as paired if a user UID is configured
  isPaired = (strlen(FIREBASE_USER_UID) > 0);

  setupWiFi();

  // Load NVS-saved pairing values, if any. These override the compile-time
  // defaults so each customer install can be paired at deploy time without
  // a custom firmware build per UID.
  prefs.begin("bridge", false);
  String savedUid = prefs.getString("uid", String(FIREBASE_USER_UID));
  String savedIp = prefs.getString("wledIp", String(DEFAULT_WLED_IP));
  // We consider the UID "from NVS" only when a value was actually stored
  // (i.e. distinct from the compile-time default). isKey() is the precise
  // check; getString-with-default can't distinguish the two cases.
  nvsUidFound = prefs.isKey("uid");
  prefs.end();

  pairedUserId = savedUid;
  pairedWledIp = savedIp;
  // isPaired requires an actual NVS-stored UID, not just a non-empty default.
  // Defends against the bug class where a non-empty FIREBASE_USER_UID compile-time
  // default would cause fresh bridges to falsely report as paired and self-register
  // with an orphan UID. See Item #47 in MEMORY.md.
  isPaired = nvsUidFound && pairedUserId.length() > 0;

  if (nvsUidFound) {
    Serial.println("[Bridge] Loaded UID from NVS: " + pairedUserId);
    Serial.println("[Bridge] Loaded WLED IP from NVS: " + pairedWledIp);
  } else {
    Serial.println("[Bridge] No NVS data, using compile-time defaults");
    Serial.println("[Bridge] UID: " + pairedUserId);
    Serial.println("[Bridge] WLED IP: " + pairedWledIp);
  }

  setupMDNS();
  setupWebServer();
  setupFirebase();

  // Self-register in /bridge_registry/{deviceId} so the Lumina app can find
  // this bridge via Firestore — no mDNS or LAN scanning needed. Runs after
  // Firebase Auth so the bridge already has an ID token. If sign-in failed,
  // skip — the periodic heartbeat will register on the first cycle that
  // ensureValidToken() succeeds.
  if (firebaseReady) {
    registerBridgeInRegistry();
  }

  bootTime = millis();

  Serial.println();
  Serial.println("Bridge initialized and ready!");
  Serial.println("Polling for commands...");
  Serial.println();

  digitalWrite(STATUS_LED_PIN, HIGH);
  delay(1000);
  digitalWrite(STATUS_LED_PIN, LOW);
}

// ============================================================================
// Main Loop
// ============================================================================

void loop() {
  server.handleClient();
  statusBlink();

  if (millis() - lastPollTime >= POLL_INTERVAL_MS) {
    lastPollTime = millis();

    if (firebaseReady && isPaired && WiFi.status() == WL_CONNECTED) {
      if (ensureValidToken()) {
        pollCommands();
      } else {
        DEBUG_PRINTLN("Token refresh failed, skipping poll");
      }
    }
  }

  // While unpaired, poll the registry doc for an app-initiated pairing
  // request. Stops automatically once isPaired becomes true.
  if (!isPaired &&
      millis() - lastPairingPollTime >= PAIRING_POLL_INTERVAL_MS) {
    lastPairingPollTime = millis();
    if (firebaseReady && WiFi.status() == WL_CONNECTED) {
      pollPairingRequest();
    }
  }

  // Write heartbeat every 30 seconds
  if (millis() - lastHeartbeatTime >= 30000) {
    lastHeartbeatTime = millis();
    if (firebaseReady && isPaired && WiFi.status() == WL_CONNECTED && !firebaseIdToken.isEmpty()) {
      writeHeartbeat();
      lastSuccessfulPoll = millis();
    }
  }

  // Refresh the registry doc on the same cadence — runs whether paired or
  // not, so the app sees lastSeen ticking even on freshly-flashed bridges
  // sitting at the install site waiting to be claimed.
  if (millis() - lastRegistryUpdateTime >= REGISTRY_HEARTBEAT_INTERVAL_MS) {
    lastRegistryUpdateTime = millis();
    if (firebaseReady && WiFi.status() == WL_CONNECTED && !firebaseIdToken.isEmpty()) {
      updateRegistryHeartbeat();
    }
  }

  // Watchdog: reboot if no successful Firestore activity for 5 minutes.
  // Catches silent failures like auth token corruption, memory leaks,
  // or WiFi connected but no internet.
  if (lastSuccessfulPoll > 0 && millis() - lastSuccessfulPoll > 300000UL) {
    Serial.println("WATCHDOG: No successful activity for 5 minutes — rebooting");
    delay(1000);
    ESP.restart();
  }

  delay(10);
}

// ============================================================================
// WiFi Setup
// ============================================================================

void setupWiFi() {
  Serial.println("Setting up WiFi...");

  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);
  delay(1000);

  // If no hardcoded SSID, use WiFiManager captive portal
  if (strlen(WIFI_SSID) == 0) {
    Serial.println("No WiFi credentials configured — starting captive portal");
    Serial.print("Connect to AP: ");
    Serial.println(deviceName);

    WiFiManager wm;
    wm.setConfigPortalTimeout(300); // 5 min timeout, then reboot
    wm.setAPCallback([](WiFiManager* wm) {
      Serial.println("Captive portal started");
      blinkLed(3, 200);
    });

    if (!wm.autoConnect(deviceName.c_str())) {
      Serial.println("WiFi config timed out — rebooting");
      delay(3000);
      ESP.restart();
    }
  } else {
    Serial.print("Connecting to ");
    Serial.println(WIFI_SSID);

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 40) {
      delay(500);
      Serial.print(".");
      Serial.print(WiFi.status());
      attempts++;
    }

    if (WiFi.status() != WL_CONNECTED) {
      Serial.println();
      Serial.print("Failed! WiFi status: ");
      Serial.println(WiFi.status());
      Serial.println("Restarting in 5 seconds...");
      delay(5000);
      ESP.restart();
    }
  }

  Serial.println();
  Serial.print("Connected! IP: ");
  Serial.println(WiFi.localIP());
}

// ============================================================================
// mDNS Setup — advertise _lumina._tcp so the app can discover us
// ============================================================================

void setupMDNS() {
  String hostname = deviceName;
  hostname.toLowerCase();

  if (MDNS.begin(hostname.c_str())) {
    // Advertise _lumina._tcp for bridge discovery
    MDNS.addService("lumina", "tcp", 80);
    // Also advertise _http._tcp as fallback
    MDNS.addService("http", "tcp", 80);
    Serial.print("mDNS started: ");
    Serial.print(hostname);
    Serial.println(".local");
  } else {
    Serial.println("mDNS failed to start");
  }
}

// ============================================================================
// Local Web Server — API endpoints for app pairing/status
// ============================================================================

void setupWebServer() {
  server.on("/api/info", HTTP_GET, handleApiInfo);
  server.on("/api/bridge/status", HTTP_GET, handleBridgeStatus);
  server.on("/api/bridge/pair", HTTP_POST, handleBridgePair);
  server.on("/api/bridge/auth", HTTP_POST, handleBridgeAuth);
  server.on("/api/reboot", HTTP_POST, handleReboot);
  server.on("/api/reset", HTTP_POST, handleReset);
  server.onNotFound(handleNotFound);

  server.begin();
  Serial.println("HTTP server started on port 80");
}

void handleApiInfo() {
  JsonDocument doc;
  doc["name"] = deviceName;
  doc["version"] = BRIDGE_FIRMWARE_VERSION;
  doc["type"] = "bridge";
  doc["ip"] = WiFi.localIP().toString();
  doc["mdns"] = deviceName + ".local";
  doc["ap"] = deviceName;
  // Stable per-chip ID — the app uses this to look up this bridge in
  // /bridge_registry without needing to know the IP or hostname.
  doc["deviceId"] = deviceId;
  doc["savedSSID"] = String(WIFI_SSID);
  // "nvs" → bridge has been paired by the app and the UID was loaded from
  // flash; "default" → no pairing on file, running on compile-time defaults.
  // The setup wizard uses this to decide whether the bridge needs initial pairing.
  doc["pairingSource"] = nvsUidFound ? "nvs" : "default";
  // Self-declare the Firebase Auth email this bridge signs in with. The
  // wizard writes this into the user's bridge_email field so Firestore
  // rules can grant the bridge read/write on the user's commands.
  doc["bridgeEmail"] = String(FIREBASE_AUTH_EMAIL);

  String body;
  serializeJson(doc, body);
  server.send(200, "application/json", body);
}

void handleBridgeStatus() {
  JsonDocument doc;
  doc["paired"] = isPaired;
  doc["authenticated"] = firebaseAuthenticated;
  doc["wifi"] = (WiFi.status() == WL_CONNECTED);
  doc["userId"] = pairedUserId;
  doc["wledIp"] = pairedWledIp;
  doc["commands"] = commandsProcessed;
  doc["errors"] = commandErrors;
  doc["uptime"] = (millis() - bootTime) / 1000;
  doc["version"] = "1.2";

  String body;
  serializeJson(doc, body);
  server.send(200, "application/json", body);
}

void handleBridgePair() {
  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"error\":\"No body\"}");
    return;
  }

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  if (error) {
    server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
    return;
  }

  String userId = doc["userId"] | "";
  String wledIp = doc["wledIp"] | "";

  if (userId.isEmpty()) {
    server.send(400, "application/json", "{\"error\":\"userId required\"}");
    return;
  }

  pairedUserId = userId;
  if (!wledIp.isEmpty()) {
    pairedWledIp = wledIp;
  }
  isPaired = true;

  // Persist to NVS so the values survive reboots — without this every
  // power cycle reverts to the compile-time FIREBASE_USER_UID macro.
  prefs.begin("bridge", false);
  prefs.putString("uid", pairedUserId);
  prefs.putString("wledIp", pairedWledIp);
  prefs.end();
  nvsUidFound = true;

  Serial.println("[Bridge] Paired and saved to NVS");
  Serial.println("[Bridge] UID: " + pairedUserId);
  Serial.println("[Bridge] WLED IP: " + pairedWledIp);

  server.send(200, "application/json", "{\"ok\":true}");
}

// /api/bridge/auth — confirms the bridge is paired to the requesting UID.
// Body: {"userId": "<firebase-uid>"}
//   200 {"ok":true,"uid":...}    → match, this bridge is the caller's
//   403 {"ok":false,"error":...}  → paired to a different account
//   400 {"ok":false,"error":...}  → malformed body or missing userId
void handleBridgeAuth() {
  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"No body\"}");
    return;
  }

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  if (error) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"Invalid JSON\"}");
    return;
  }

  String requestedUid = doc["userId"] | "";

  if (requestedUid.isEmpty()) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"userId required\"}");
    return;
  }

  if (pairedUserId != requestedUid) {
    server.send(403, "application/json",
        "{\"ok\":false,\"error\":\"bridge paired to different account\"}");
    return;
  }

  server.send(200, "application/json",
      "{\"ok\":true,\"uid\":\"" + pairedUserId + "\"}");
}

void handleReboot() {
  server.send(200, "application/json", "{\"ok\":true}");
  delay(500);
  ESP.restart();
}

void handleReset() {
  // Clear all NVS-stored pairing so the bridge boots fresh on next start.
  prefs.begin("bridge", false);
  prefs.clear();
  prefs.end();

  Serial.println("[Bridge] Factory reset — NVS cleared, rebooting");

  server.send(200, "application/json",
              "{\"ok\":true,\"message\":\"Resetting...\"}");
  delay(500);
  ESP.restart();
}

void handleNotFound() {
  server.send(404, "application/json", "{\"error\":\"Not found\"}");
}

// ============================================================================
// Firebase Setup & Auth
// ============================================================================

void setupFirebase() {
  Serial.println("Setting up Firebase connection...");

  // SSL configuration for ESP32
  secureClient.setInsecure();
  secureClient.setHandshakeTimeout(30);
  secureClient.setTimeout(15);

  // Sync time for timestamps
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Syncing time");
  time_t now = time(nullptr);
  while (now < 8 * 3600 * 2) {
    delay(500);
    Serial.print(".");
    now = time(nullptr);
  }
  Serial.println(" Done!");

  Serial.print("Free heap: ");
  Serial.println(ESP.getFreeHeap());

  // Sign in to Firebase Auth
  if (signInFirebase()) {
    Serial.println("Firebase Auth: signed in successfully");
    firebaseReady = true;
    firebaseAuthenticated = true;
    lastSuccessfulPoll = millis();
  } else {
    Serial.println("Firebase Auth: FAILED to sign in");
    Serial.println("Bridge will retry on next poll cycle");
    firebaseAuthenticated = false;
  }
}

/**
 * Sign in to Firebase Auth using email/password.
 * Returns the ID token needed for authenticated Firestore access.
 */
bool signInFirebase() {
  Serial.println("Signing in to Firebase...");

  HTTPClient http;
  String url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" +
               String(FIREBASE_API_KEY);

  JsonDocument doc;
  doc["email"] = FIREBASE_AUTH_EMAIL;
  doc["password"] = FIREBASE_AUTH_PASSWORD;
  doc["returnSecureToken"] = true;

  String body;
  serializeJson(doc, body);

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");

  int httpCode = http.POST(body);

  if (httpCode == 200) {
    String response = http.getString();
    http.end();

    JsonDocument respDoc;
    DeserializationError error = deserializeJson(respDoc, response);
    if (error) {
      Serial.print("Auth JSON parse error: ");
      Serial.println(error.c_str());
      return false;
    }

    firebaseIdToken = respDoc["idToken"].as<String>();
    firebaseRefreshToken = respDoc["refreshToken"].as<String>();
    int expiresIn = respDoc["expiresIn"].as<String>().toInt();

    // Set expiry 5 minutes early to avoid edge cases
    tokenExpiresAt = millis() + ((unsigned long)expiresIn - 300) * 1000UL;

    firebaseAuthenticated = true;

    Serial.print("  Token obtained, expires in ");
    Serial.print(expiresIn);
    Serial.println("s");
    return true;
  } else {
    String response = http.getString();
    http.end();
    Serial.print("  Auth failed: HTTP ");
    Serial.print(httpCode);
    Serial.print(" - ");
    Serial.println(response.substring(0, 200));
    firebaseAuthenticated = false;
    return false;
  }
}

/**
 * Refresh the Firebase ID token using the refresh token.
 */
bool refreshFirebaseToken() {
  DEBUG_PRINTLN("Refreshing Firebase token...");

  HTTPClient http;
  String url = "https://securetoken.googleapis.com/v1/token?key=" +
               String(FIREBASE_API_KEY);

  String body = "grant_type=refresh_token&refresh_token=" + firebaseRefreshToken;

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/x-www-form-urlencoded");

  int httpCode = http.POST(body);

  if (httpCode == 200) {
    String response = http.getString();
    http.end();

    JsonDocument respDoc;
    DeserializationError error = deserializeJson(respDoc, response);
    if (error) {
      DEBUG_PRINT("Refresh JSON parse error: ");
      DEBUG_PRINTLN(error.c_str());
      return false;
    }

    firebaseIdToken = respDoc["id_token"].as<String>();
    firebaseRefreshToken = respDoc["refresh_token"].as<String>();
    int expiresIn = respDoc["expires_in"].as<String>().toInt();

    tokenExpiresAt = millis() + ((unsigned long)expiresIn - 300) * 1000UL;
    firebaseAuthenticated = true;

    DEBUG_PRINTLN("  Token refreshed");
    return true;
  } else {
    http.end();
    DEBUG_PRINT("  Token refresh failed: HTTP ");
    DEBUG_PRINTLN(httpCode);
    // Fall back to full re-sign-in
    return signInFirebase();
  }
}

/**
 * Ensure we have a valid (non-expired) Firebase ID token.
 */
bool ensureValidToken() {
  if (firebaseIdToken.isEmpty()) {
    return signInFirebase();
  }
  if (millis() >= tokenExpiresAt) {
    return refreshFirebaseToken();
  }
  return true;
}

// ============================================================================
// Command Polling
// ============================================================================

void pollCommands() {
  DEBUG_PRINTLN("Polling for commands...");

  HTTPClient http;
  String url = firestoreBaseUrl() + ":runQuery";

  // Build query: SELECT * FROM commands WHERE status == "pending" LIMIT 5
  JsonDocument queryDoc;
  queryDoc["structuredQuery"]["from"][0]["collectionId"] = "commands";
  queryDoc["structuredQuery"]["where"]["fieldFilter"]["field"]["fieldPath"] = "status";
  queryDoc["structuredQuery"]["where"]["fieldFilter"]["op"] = "EQUAL";
  queryDoc["structuredQuery"]["where"]["fieldFilter"]["value"]["stringValue"] = "pending";
  queryDoc["structuredQuery"]["limit"] = MAX_COMMANDS_PER_POLL;

  String queryBody;
  serializeJson(queryDoc, queryBody);

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int httpCode = http.POST(queryBody);

  if (httpCode == 200) {
    String response = http.getString();
    http.end();

    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, response);

    if (error) {
      DEBUG_PRINT("JSON parse error: ");
      DEBUG_PRINTLN(error.c_str());
      return;
    }

    JsonArray results = doc.as<JsonArray>();
    int pendingCount = 0;

    for (JsonObject result : results) {
      JsonObject document = result["document"];
      if (document.isNull()) continue;

      pendingCount++;
      digitalWrite(STATUS_LED_PIN, HIGH);

      const char* docName = document["name"];
      String fullPath = String(docName);
      int lastSlash = fullPath.lastIndexOf('/');
      String commandId = fullPath.substring(lastSlash + 1);

      JsonObject fields = document["fields"];
      executeCommand(commandId, fields);

      digitalWrite(STATUS_LED_PIN, LOW);
    }

    if (pendingCount == 0) {
      DEBUG_PRINTLN("No pending commands");
    } else {
      DEBUG_PRINTF("Processed %d command(s)\n", pendingCount);
    }
  } else if (httpCode == 401 || httpCode == 403) {
    http.end();
    Serial.print("Auth error on poll (HTTP ");
    Serial.print(httpCode);
    Serial.println("), refreshing token...");
    refreshFirebaseToken();
  } else {
    DEBUG_PRINT("HTTP error: ");
    DEBUG_PRINTLN(httpCode);
    http.end();
    commandErrors++;
  }
}

// ============================================================================
// Command Execution
// ============================================================================

void executeCommand(const String& commandId, JsonObject& fields) {
  Serial.println();
  Serial.print("Executing command: ");
  Serial.println(commandId);

  String commandType = "";
  String controllerIp = "";

  if (fields["type"]["stringValue"]) {
    commandType = fields["type"]["stringValue"].as<String>();
  }

  if (fields["controllerIp"]["stringValue"]) {
    controllerIp = fields["controllerIp"]["stringValue"].as<String>();
  }

  Serial.print("  Type: ");
  Serial.println(commandType);
  Serial.print("  Controller IP: ");
  Serial.println(controllerIp);

  // Handle ping command — no WLED request needed, just acknowledge
  if (commandType == "ping") {
    Serial.println("  PING — acknowledging");
    updateCommandStatus(commandId, "completed");
    commandsProcessed++;
    lastSuccessfulPoll = millis();
    return;
  }

  if (controllerIp.isEmpty()) {
    controllerIp = pairedWledIp;
    Serial.print("  Using paired WLED IP: ");
    Serial.println(controllerIp);
  }

  if (controllerIp.isEmpty()) {
    Serial.println("  ERROR: No controller IP specified");
    updateCommandStatus(commandId, "failed", "No controller IP specified");
    commandErrors++;
    return;
  }

  updateCommandStatus(commandId, "executing");

  String endpoint;
  String method;
  String body = "";

  if (commandType == "getState") {
    endpoint = "/json/state";
    method = "GET";
  } else if (commandType == "getInfo") {
    endpoint = "/json/info";
    method = "GET";
  } else {
    endpoint = "/json/state";
    method = "POST";
    body = convertFirestorePayloadToJson(fields);
  }

  Serial.print("  -> ");
  Serial.print(method);
  Serial.print(" http://");
  Serial.print(controllerIp);
  Serial.println(endpoint);

  String response = makeWledRequest(controllerIp, method, endpoint, body);

  if (response.startsWith("ERROR:")) {
    Serial.print("  ERROR: ");
    Serial.println(response);
    updateCommandStatus(commandId, "failed", response);
    commandErrors++;
  } else {
    Serial.println("  SUCCESS!");
    updateCommandStatus(commandId, "completed", "", response);
    commandsProcessed++;
    lastSuccessfulPoll = millis();
  }
}

// ============================================================================
// Convert Firestore Payload to WLED JSON
// ============================================================================

String convertFirestorePayloadToJson(JsonObject& fields) {
  if (fields["payload"]["stringValue"]) {
    String payloadStr = fields["payload"]["stringValue"].as<String>();
    DEBUG_PRINT("  Payload (string): ");
    DEBUG_PRINTLN(payloadStr);
    return payloadStr;
  }

  JsonObject payload = fields["payload"]["mapValue"]["fields"];
  if (payload.isNull()) {
    return "{}";
  }

  JsonDocument doc;

  for (JsonPair kv : payload) {
    const char* key = kv.key().c_str();
    JsonObject val = kv.value().as<JsonObject>();

    if (val["booleanValue"]) {
      doc[key] = val["booleanValue"].as<bool>();
    } else if (val["integerValue"]) {
      doc[key] = val["integerValue"].as<int>();
    } else if (val["doubleValue"]) {
      doc[key] = val["doubleValue"].as<double>();
    } else if (val["stringValue"]) {
      doc[key] = val["stringValue"].as<String>();
    }
  }

  String result;
  serializeJson(doc, result);
  return result;
}

// ============================================================================
// HTTP Request to WLED
// ============================================================================

String makeWledRequest(const String& ip, const String& method,
                       const String& endpoint, const String& body) {
  HTTPClient http;
  String url = "http://" + ip + endpoint;

  DEBUG_PRINT("HTTP Request: ");
  DEBUG_PRINT(method);
  DEBUG_PRINT(" ");
  DEBUG_PRINTLN(url);

  http.begin(url);
  http.setTimeout(WLED_HTTP_TIMEOUT_MS);
  http.addHeader("Content-Type", "application/json");

  int httpCode;
  if (method == "GET") {
    httpCode = http.GET();
  } else if (method == "POST") {
    DEBUG_PRINT("Body: ");
    DEBUG_PRINTLN(body);
    httpCode = http.POST(body);
  } else {
    http.end();
    return "ERROR: Unsupported method";
  }

  if (httpCode > 0 && (httpCode == 200 || httpCode == HTTP_CODE_OK)) {
    String response = http.getString();
    http.end();
    return response;
  } else {
    String error = "ERROR: HTTP " + String(httpCode);
    http.end();
    return error;
  }
}

// ============================================================================
// Update Command Status in Firestore
// ============================================================================

void updateCommandStatus(const String& commandId, const String& status,
                         const String& error, const String& result) {
  HTTPClient http;
  String url = firestoreBaseUrl() + "/commands/" + commandId +
               "?updateMask.fieldPaths=status";

  JsonDocument doc;
  doc["fields"]["status"]["stringValue"] = status;

  if (status == "completed" || status == "failed") {
    time_t now = time(nullptr);
    char timestamp[30];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
    doc["fields"]["completedAt"]["timestampValue"] = timestamp;
    url += "&updateMask.fieldPaths=completedAt";
  }

  if (!error.isEmpty()) {
    doc["fields"]["error"]["stringValue"] = error;
    url += "&updateMask.fieldPaths=error";
  }

  if (!result.isEmpty()) {
    doc["fields"]["result"]["stringValue"] = result;
    url += "&updateMask.fieldPaths=result";
  }

  String body;
  serializeJson(doc, body);

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    DEBUG_PRINTLN("Status updated");
  } else {
    DEBUG_PRINT("Status update failed: ");
    DEBUG_PRINTLN(httpCode);
    commandErrors++;
  }

  http.end();
}

// ============================================================================
// Heartbeat — writes bridge status to Firestore every 30s
// ============================================================================

void writeHeartbeat() {
  DEBUG_PRINTLN("Writing heartbeat...");

  HTTPClient http;
  String url = firestoreBaseUrl() + "/bridge_status/current"
               "?updateMask.fieldPaths=uptime"
               "&updateMask.fieldPaths=ip"
               "&updateMask.fieldPaths=commands"
               "&updateMask.fieldPaths=errors"
               "&updateMask.fieldPaths=version"
               "&updateMask.fieldPaths=wifi"
               "&updateMask.fieldPaths=heap";

  unsigned long uptimeSec = (millis() - bootTime) / 1000;

  JsonDocument doc;
  doc["fields"]["uptime"]["integerValue"] = String(uptimeSec);
  doc["fields"]["ip"]["stringValue"] = WiFi.localIP().toString();
  doc["fields"]["commands"]["integerValue"] = String(commandsProcessed);
  doc["fields"]["errors"]["integerValue"] = String(commandErrors);
  doc["fields"]["version"]["stringValue"] = "1.2";
  doc["fields"]["wifi"]["booleanValue"] = (WiFi.status() == WL_CONNECTED);
  doc["fields"]["heap"]["integerValue"] = String(ESP.getFreeHeap());

  String body;
  serializeJson(doc, body);

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    DEBUG_PRINTLN("Heartbeat OK");
  } else {
    DEBUG_PRINT("Heartbeat failed: ");
    DEBUG_PRINTLN(httpCode);
  }

  http.end();
}

// ============================================================================
// Bridge Registry — self-registration & pairing handshake
// ============================================================================
//
// The bridge writes its own document at /bridge_registry/{deviceId} so the
// Lumina app can discover and pair it via Firestore — no mDNS, no manual
// IP entry, no "phone and bridge on same WiFi" requirement. The pairing
// handshake is also Firestore-driven: app writes status="pairing" +
// pendingUid, the bridge sees it on the next pollPairingRequest() and
// promotes itself to status="paired".

// Build the JSON body containing every field the registry doc supports.
// Used for the initial full-doc write at boot.
static String buildRegistryFullPayload() {
  JsonDocument doc;
  doc["fields"]["deviceId"]["stringValue"] = deviceId;
  doc["fields"]["deviceName"]["stringValue"] = deviceName;
  doc["fields"]["apName"]["stringValue"] = deviceName;
  doc["fields"]["bridgeEmail"]["stringValue"] = String(FIREBASE_AUTH_EMAIL);
  doc["fields"]["ip"]["stringValue"] = WiFi.localIP().toString();
  doc["fields"]["status"]["stringValue"] = isPaired ? "paired" : "unpaired";
  doc["fields"]["pairedUid"]["stringValue"] = isPaired ? pairedUserId : "";
  // Empty string means "no pairing request pending" — see Part 7 of the
  // self-registration design (we deliberately avoid Firestore field
  // deletion in favor of a simple sentinel value).
  doc["fields"]["pendingUid"]["stringValue"] = "";
  doc["fields"]["firmwareVersion"]["stringValue"] = BRIDGE_FIRMWARE_VERSION;

  time_t now = time(nullptr);
  char ts[30];
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  doc["fields"]["lastSeen"]["timestampValue"] = ts;

  doc["fields"]["rssi"]["integerValue"] = String(WiFi.RSSI());
  doc["fields"]["heap"]["integerValue"] = String(ESP.getFreeHeap());
  doc["fields"]["freeHeap"]["integerValue"] = String(ESP.getFreeHeap());
  doc["fields"]["flashSize"]["integerValue"] = String(ESP.getFlashChipSize());

  String body;
  serializeJson(doc, body);
  return body;
}

void registerBridgeInRegistry() {
  if (!ensureValidToken()) {
    Serial.println("[Registry] Cannot register — no valid token");
    return;
  }

  HTTPClient http;
  // Write every field via updateMask so the PATCH creates the doc on
  // first run and overwrites stale fields on subsequent boots.
  String url = bridgeRegistryUrl() +
               "?updateMask.fieldPaths=deviceId" +
               "&updateMask.fieldPaths=deviceName" +
               "&updateMask.fieldPaths=apName" +
               "&updateMask.fieldPaths=bridgeEmail" +
               "&updateMask.fieldPaths=ip" +
               "&updateMask.fieldPaths=status" +
               "&updateMask.fieldPaths=pairedUid" +
               "&updateMask.fieldPaths=pendingUid" +
               "&updateMask.fieldPaths=firmwareVersion" +
               "&updateMask.fieldPaths=lastSeen" +
               "&updateMask.fieldPaths=rssi" +
               "&updateMask.fieldPaths=heap" +
               "&updateMask.fieldPaths=freeHeap" +
               "&updateMask.fieldPaths=flashSize";

  String body = buildRegistryFullPayload();

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    Serial.print("[Registry] Self-registered as ");
    Serial.print(deviceId);
    Serial.print(" (status=");
    Serial.print(isPaired ? "paired" : "unpaired");
    Serial.println(")");
    // Counts as "successful Firestore activity" so the watchdog doesn't
    // reboot a freshly-installed unpaired bridge sitting idle.
    lastSuccessfulPoll = millis();
  } else {
    String response = http.getString();
    Serial.print("[Registry] Self-registration failed: HTTP ");
    Serial.print(httpCode);
    Serial.print(" - ");
    Serial.println(response.substring(0, 200));
  }

  http.end();
}

void updateRegistryHeartbeat() {
  if (!ensureValidToken()) return;

  HTTPClient http;
  // Only the dynamic fields — keep deviceId/apName/bridgeEmail/firmwareVersion
  // immutable across heartbeats so a corrupted payload can't rewrite identity.
  // Status + pairedUid are included so the doc reflects pairing changes
  // (e.g. immediately after pollPairingRequest promotes us).
  String url = bridgeRegistryUrl() +
               "?updateMask.fieldPaths=lastSeen" +
               "&updateMask.fieldPaths=ip" +
               "&updateMask.fieldPaths=rssi" +
               "&updateMask.fieldPaths=heap" +
               "&updateMask.fieldPaths=freeHeap" +
               "&updateMask.fieldPaths=status" +
               "&updateMask.fieldPaths=pairedUid";

  JsonDocument doc;
  doc["fields"]["ip"]["stringValue"] = WiFi.localIP().toString();
  doc["fields"]["status"]["stringValue"] = isPaired ? "paired" : "unpaired";
  doc["fields"]["pairedUid"]["stringValue"] = isPaired ? pairedUserId : "";

  time_t now = time(nullptr);
  char ts[30];
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  doc["fields"]["lastSeen"]["timestampValue"] = ts;

  doc["fields"]["rssi"]["integerValue"] = String(WiFi.RSSI());
  doc["fields"]["heap"]["integerValue"] = String(ESP.getFreeHeap());
  doc["fields"]["freeHeap"]["integerValue"] = String(ESP.getFreeHeap());

  String body;
  serializeJson(doc, body);

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    DEBUG_PRINTLN("[Registry] Heartbeat OK");
    lastSuccessfulPoll = millis();
  } else if (httpCode == 404) {
    // Registry doc missing — re-create it. Happens if an admin deleted
    // the doc to force re-pairing, or on a brand-new project.
    Serial.println("[Registry] Heartbeat 404 — re-registering");
    http.end();
    registerBridgeInRegistry();
    return;
  } else {
    DEBUG_PRINT("[Registry] Heartbeat failed: HTTP ");
    DEBUG_PRINTLN(httpCode);
  }

  http.end();
}

bool pollPairingRequest() {
  if (!ensureValidToken()) return false;

  HTTPClient http;
  http.begin(secureClient, bridgeRegistryUrl());
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int httpCode = http.GET();

  if (httpCode == 404) {
    // Doc doesn't exist yet — the initial registerBridgeInRegistry() call
    // probably failed (e.g. token wasn't ready). Try again now.
    http.end();
    Serial.println("[Registry] Doc missing — re-registering");
    registerBridgeInRegistry();
    return false;
  }

  if (httpCode != 200) {
    DEBUG_PRINT("[Registry] Pairing poll failed: HTTP ");
    DEBUG_PRINTLN(httpCode);
    http.end();
    return false;
  }

  String response = http.getString();
  http.end();

  JsonDocument doc;
  if (deserializeJson(doc, response)) {
    DEBUG_PRINTLN("[Registry] Pairing poll JSON parse error");
    return false;
  }

  String pendingUid =
      doc["fields"]["pendingUid"]["stringValue"].as<String>();
  String currentStatus =
      doc["fields"]["status"]["stringValue"].as<String>();

  // Empty pendingUid (sentinel) or non-pairing status → nothing to do.
  if (pendingUid.length() == 0 || currentStatus != "pairing") {
    lastSuccessfulPoll = millis();
    return false;
  }

  Serial.println();
  Serial.print("[Registry] Pairing request received — UID: ");
  Serial.println(pendingUid);

  // Persist the new UID to NVS before confirming, so a power loss between
  // the local commit and the Firestore confirm leaves the bridge in a
  // recoverable state (next boot will see itself as paired and the app's
  // pending request will resolve naturally on reconnect).
  prefs.begin("bridge", false);
  prefs.putString("uid", pendingUid);
  prefs.end();

  pairedUserId = pendingUid;
  isPaired = true;
  nvsUidFound = true;

  // Confirm the pairing in the registry doc — clears pendingUid and flips
  // status to "paired" so the app's poll completes.
  HTTPClient confirmHttp;
  String confirmUrl = bridgeRegistryUrl() +
                      "?updateMask.fieldPaths=status" +
                      "&updateMask.fieldPaths=pairedUid" +
                      "&updateMask.fieldPaths=pendingUid" +
                      "&updateMask.fieldPaths=lastSeen";

  JsonDocument confirmDoc;
  confirmDoc["fields"]["status"]["stringValue"] = "paired";
  confirmDoc["fields"]["pairedUid"]["stringValue"] = pendingUid;
  confirmDoc["fields"]["pendingUid"]["stringValue"] = "";

  time_t now = time(nullptr);
  char ts[30];
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  confirmDoc["fields"]["lastSeen"]["timestampValue"] = ts;

  String confirmBody;
  serializeJson(confirmDoc, confirmBody);

  confirmHttp.begin(secureClient, confirmUrl);
  confirmHttp.addHeader("Content-Type", "application/json");
  confirmHttp.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int confirmCode = confirmHttp.PATCH(confirmBody);
  confirmHttp.end();

  if (confirmCode == 200) {
    Serial.println("[Registry] Pairing confirmed in Firestore");
    lastSuccessfulPoll = millis();
    return true;
  } else {
    Serial.print("[Registry] Pairing confirmation failed: HTTP ");
    Serial.println(confirmCode);
    // Local NVS already updated — the next heartbeat cycle will retry the
    // status PATCH and the app's pairing poll will eventually see "paired".
    return false;
  }
}

// ============================================================================
// LED Status Functions
// ============================================================================

void blinkLed(int times, int delayMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(delayMs);
    digitalWrite(STATUS_LED_PIN, LOW);
    delay(delayMs);
  }
}

void statusBlink() {
  if (millis() - lastBlinkTime >= 5000) {
    lastBlinkTime = millis();

    if (firebaseReady && WiFi.status() == WL_CONNECTED) {
      blinkLed(1, 50);
    } else if (WiFi.status() == WL_CONNECTED) {
      blinkLed(2, 100);
    } else {
      blinkLed(3, 100);
    }
  }
}
