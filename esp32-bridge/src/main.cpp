/**
 * Lumina ESP32 Bridge
 *
 * This firmware runs on an ESP32 and acts as a bridge between
 * Firebase Firestore and WLED devices on the local network.
 *
 * How it works:
 * 1. Connects to local WiFi network
 * 2. Authenticates with Firebase (anonymous auth)
 * 3. Polls Firestore for pending commands
 * 4. Executes commands by making HTTP requests to WLED devices
 * 5. Updates command status in Firestore
 *
 * This enables remote control of WLED devices without requiring
 * WLED to support MQTT+TLS or any port forwarding.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Firebase_ESP_Client.h>
#include <WiFiManager.h>

// Firebase helper includes
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

#include "config.h"

// ============================================================================
// Global Variables
// ============================================================================

// Firebase objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// State
bool firebaseReady = false;
unsigned long lastPollTime = 0;
int commandsProcessed = 0;
int commandsFailed = 0;

// LED blink state
unsigned long lastBlinkTime = 0;
bool ledState = false;

// ============================================================================
// Function Declarations
// ============================================================================

void setupWiFi();
void setupFirebase();
void pollCommands();
void executeCommand(const String& commandId, FirebaseJson& commandData);
String makeWledRequest(const String& ip, const String& method,
                       const String& endpoint, const String& body);
void updateCommandStatus(const String& commandId, const String& status,
                         const String& error = "", FirebaseJson* result = nullptr);
void blinkLed(int times, int delayMs);
void statusBlink();

// ============================================================================
// Setup
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println();
  Serial.println("=========================================");
  Serial.println("   Lumina ESP32 Bridge v1.0");
  Serial.println("=========================================");
  Serial.println();

  // Initialize status LED
  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);

  // Rapid blink to indicate startup
  blinkLed(5, 100);

  // Setup WiFi
  setupWiFi();

  // Setup Firebase
  setupFirebase();

  Serial.println();
  Serial.println("Bridge initialized and ready!");
  Serial.println("Polling for commands...");
  Serial.println();

  // Solid LED for 1 second to indicate ready
  digitalWrite(STATUS_LED_PIN, HIGH);
  delay(1000);
  digitalWrite(STATUS_LED_PIN, LOW);
}

// ============================================================================
// Main Loop
// ============================================================================

void loop() {
  // Status blink every 5 seconds to show we're alive
  statusBlink();

  // Check if it's time to poll for commands
  if (millis() - lastPollTime >= POLL_INTERVAL_MS) {
    lastPollTime = millis();

    if (firebaseReady && Firebase.ready()) {
      pollCommands();
    } else {
      DEBUG_PRINTLN("Firebase not ready, skipping poll");
    }
  }

  // Give WiFi/Firebase time to process
  delay(10);
}

// ============================================================================
// WiFi Setup
// ============================================================================

void setupWiFi() {
  Serial.println("Setting up WiFi...");

#if defined(WIFI_SSID) && defined(WIFI_PASSWORD)
  // Use hardcoded credentials if provided
  Serial.print("Connecting to ");
  Serial.println(WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.print("Connected! IP: ");
    Serial.println(WiFi.localIP());
    return;
  }

  Serial.println();
  Serial.println("Failed to connect with hardcoded credentials");
#endif

  // Use WiFiManager for configuration
  Serial.println("Starting WiFiManager...");
  Serial.println("Connect to 'Lumina-Bridge' AP to configure WiFi");

  WiFiManager wifiManager;

  // Reset settings for testing (comment out in production)
  // wifiManager.resetSettings();

  // Set custom AP name
  wifiManager.setConfigPortalTimeout(180); // 3 minute timeout

  // Try to connect, or start AP for configuration
  if (!wifiManager.autoConnect("Lumina-Bridge", "luminabridge")) {
    Serial.println("Failed to connect and config portal timed out");
    Serial.println("Restarting...");
    delay(3000);
    ESP.restart();
  }

  Serial.println();
  Serial.print("Connected! IP: ");
  Serial.println(WiFi.localIP());
}

// ============================================================================
// Firebase Setup
// ============================================================================

void setupFirebase() {
  Serial.println("Setting up Firebase...");

  // Configure Firebase
  config.api_key = FIREBASE_API_KEY;

  // For Firestore, we use anonymous auth or a service account
  // Anonymous auth is simpler for this use case
  auth.user.email = "";
  auth.user.password = "";

  // Token status callback
  config.token_status_callback = tokenStatusCallback;

  // Initialize Firebase
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Wait for Firebase to be ready
  Serial.print("Waiting for Firebase...");
  unsigned long startTime = millis();
  while (!Firebase.ready() && millis() - startTime < 30000) {
    Serial.print(".");
    delay(500);
  }

  if (Firebase.ready()) {
    Serial.println(" Ready!");
    firebaseReady = true;
  } else {
    Serial.println(" Failed!");
    Serial.println("Firebase initialization failed. Check your credentials.");
  }
}

// ============================================================================
// Command Polling
// ============================================================================

void pollCommands() {
  // Build the Firestore path
  String documentPath = "users/" + String(FIREBASE_USER_UID) + "/commands";

  DEBUG_PRINTLN("Polling for commands...");

  // Query for pending commands
  // Firestore query: where status == "pending" order by createdAt limit 5
  FirebaseJson queryJson;
  queryJson.set("structuredQuery/from/[0]/collectionId", "commands");
  queryJson.set("structuredQuery/where/fieldFilter/field/fieldPath", "status");
  queryJson.set("structuredQuery/where/fieldFilter/op", "EQUAL");
  queryJson.set("structuredQuery/where/fieldFilter/value/stringValue", "pending");
  queryJson.set("structuredQuery/orderBy/[0]/field/fieldPath", "createdAt");
  queryJson.set("structuredQuery/orderBy/[0]/direction", "ASCENDING");
  queryJson.set("structuredQuery/limit", MAX_COMMANDS_PER_POLL);

  // Execute query
  String projectId = FIREBASE_PROJECT_ID;
  String parentPath = "projects/" + projectId + "/databases/(default)/documents/users/" + String(FIREBASE_USER_UID);

  if (Firebase.Firestore.runQuery(&fbdo, projectId.c_str(), "",
                                   queryJson.raw(), parentPath.c_str())) {
    // Parse response
    FirebaseJsonData jsonData;
    FirebaseJsonArray arr;

    if (fbdo.jsonArray().get(jsonData, 0)) {
      // Got results
      int commandCount = fbdo.jsonArray().size();
      if (commandCount > 0) {
        DEBUG_PRINTF("Found %d pending command(s)\n", commandCount);

        // LED on while processing
        digitalWrite(STATUS_LED_PIN, HIGH);

        // Process each command
        for (int i = 0; i < commandCount; i++) {
          FirebaseJsonData item;
          if (fbdo.jsonArray().get(item, i)) {
            // Extract document name and fields
            FirebaseJson docJson;
            docJson.setJsonData(item.to<String>());

            FirebaseJsonData docName;
            if (docJson.get(docName, "document/name")) {
              String fullPath = docName.to<String>();
              // Extract command ID from path
              int lastSlash = fullPath.lastIndexOf('/');
              String commandId = fullPath.substring(lastSlash + 1);

              FirebaseJsonData fieldsData;
              if (docJson.get(fieldsData, "document/fields")) {
                FirebaseJson fields;
                fields.setJsonData(fieldsData.to<String>());
                executeCommand(commandId, fields);
              }
            }
          }
        }

        digitalWrite(STATUS_LED_PIN, LOW);
      }
    } else {
      DEBUG_PRINTLN("No pending commands");
    }
  } else {
    DEBUG_PRINT("Query failed: ");
    DEBUG_PRINTLN(fbdo.errorReason());
  }
}

// ============================================================================
// Command Execution
// ============================================================================

void executeCommand(const String& commandId, FirebaseJson& fields) {
  Serial.println();
  Serial.print("Executing command: ");
  Serial.println(commandId);

  // Extract command fields
  FirebaseJsonData typeData, payloadData, controllerIpData;
  String commandType = "";
  String controllerIp = "";
  String payload = "{}";

  if (fields.get(typeData, "type/stringValue")) {
    commandType = typeData.to<String>();
  }

  if (fields.get(controllerIpData, "controllerIp/stringValue")) {
    controllerIp = controllerIpData.to<String>();
  }

  if (fields.get(payloadData, "payload/mapValue")) {
    // Convert Firestore map to JSON
    FirebaseJson payloadMap;
    payloadMap.setJsonData(payloadData.to<String>());

    // Parse the Firestore format and convert to plain JSON
    DynamicJsonDocument doc(4096);

    // TODO: Properly convert Firestore map format to JSON
    // For now, use the payload directly if it's simple
    payload = payloadData.to<String>();
  }

  Serial.print("  Type: ");
  Serial.println(commandType);
  Serial.print("  Controller IP: ");
  Serial.println(controllerIp);

  // Validate we have what we need
  if (controllerIp.isEmpty()) {
    Serial.println("  ERROR: No controller IP specified");
    updateCommandStatus(commandId, "failed", "No controller IP specified");
    commandsFailed++;
    return;
  }

  // Mark as executing
  updateCommandStatus(commandId, "executing");

  // Build the WLED endpoint and method
  String endpoint;
  String method;
  String body = "";

  if (commandType == "getState") {
    endpoint = "/json/state";
    method = "GET";
  } else if (commandType == "getInfo") {
    endpoint = "/json/info";
    method = "GET";
  } else if (commandType == "setState" || commandType == "applyJson" ||
             commandType == "renameSegment" || commandType == "applyToSegments") {
    endpoint = "/json/state";
    method = "POST";
    // Extract payload - need to convert Firestore format to WLED JSON
    body = convertFirestorePayloadToJson(fields);
  } else if (commandType == "applyConfig" || commandType == "configureSyncReceiver" ||
             commandType == "configureSyncSender") {
    endpoint = "/json/cfg";
    method = "POST";
    body = convertFirestorePayloadToJson(fields);
  } else {
    // Default to state update
    endpoint = "/json/state";
    method = "POST";
    body = convertFirestorePayloadToJson(fields);
  }

  Serial.print("  -> ");
  Serial.print(method);
  Serial.print(" http://");
  Serial.print(controllerIp);
  Serial.println(endpoint);

  // Execute the HTTP request
  String response = makeWledRequest(controllerIp, method, endpoint, body);

  if (response.startsWith("ERROR:")) {
    Serial.print("  ERROR: ");
    Serial.println(response);
    updateCommandStatus(commandId, "failed", response);
    commandsFailed++;
  } else {
    Serial.println("  SUCCESS!");
    // Parse response as JSON and include in result
    FirebaseJson result;
    result.setJsonData(response);
    updateCommandStatus(commandId, "completed", "", &result);
    commandsProcessed++;
  }
}

// ============================================================================
// Helper: Convert Firestore Payload to WLED JSON
// ============================================================================

String convertFirestorePayloadToJson(FirebaseJson& fields) {
  FirebaseJsonData payloadData;
  if (!fields.get(payloadData, "payload/mapValue/fields")) {
    return "{}";
  }

  FirebaseJson payloadFields;
  payloadFields.setJsonData(payloadData.to<String>());

  // Convert Firestore format to plain JSON
  DynamicJsonDocument doc(4096);

  // Iterate through payload fields and convert
  // Firestore stores values like: {"on": {"booleanValue": true}, "bri": {"integerValue": "128"}}
  // We need: {"on": true, "bri": 128}

  size_t count = payloadFields.iteratorBegin();
  String key, value;
  int type;

  for (size_t i = 0; i < count; i++) {
    payloadFields.iteratorGet(i, type, key, value);

    if (type == FirebaseJson::JSON_OBJECT) {
      FirebaseJson fieldValue;
      fieldValue.setJsonData(value);

      FirebaseJsonData v;
      if (fieldValue.get(v, "booleanValue")) {
        doc[key] = v.to<bool>();
      } else if (fieldValue.get(v, "integerValue")) {
        doc[key] = v.to<int>();
      } else if (fieldValue.get(v, "doubleValue")) {
        doc[key] = v.to<double>();
      } else if (fieldValue.get(v, "stringValue")) {
        doc[key] = v.to<String>();
      } else if (fieldValue.get(v, "arrayValue")) {
        // Handle arrays (like 'seg' array)
        // This is complex - for now just pass through
        doc[key] = serialized(v.to<String>());
      } else if (fieldValue.get(v, "mapValue")) {
        // Handle nested maps
        doc[key] = serialized(v.to<String>());
      }
    }
  }
  payloadFields.iteratorEnd();

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
  http.addHeader("Accept", "application/json");

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

  if (httpCode > 0) {
    if (httpCode == HTTP_CODE_OK || httpCode == 200) {
      String response = http.getString();
      http.end();
      DEBUG_PRINTLN("Response received");
      return response;
    } else {
      String error = "ERROR: HTTP " + String(httpCode);
      http.end();
      return error;
    }
  } else {
    String error = "ERROR: " + http.errorToString(httpCode);
    http.end();
    return error;
  }
}

// ============================================================================
// Update Command Status in Firestore
// ============================================================================

void updateCommandStatus(const String& commandId, const String& status,
                         const String& error, FirebaseJson* result) {
  String documentPath = "users/" + String(FIREBASE_USER_UID) + "/commands/" + commandId;

  FirebaseJson updateContent;
  updateContent.set("fields/status/stringValue", status);

  // Add completedAt timestamp for terminal states
  if (status == "completed" || status == "failed" || status == "timeout") {
    // Firestore timestamp format
    time_t now = time(nullptr);
    char timestamp[30];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
    updateContent.set("fields/completedAt/timestampValue", timestamp);
  }

  if (!error.isEmpty()) {
    updateContent.set("fields/error/stringValue", error);
  }

  if (result != nullptr) {
    // Add result as a map
    updateContent.set("fields/result/mapValue/fields", result->raw());
  }

  if (Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID,
                                         "", documentPath.c_str(),
                                         updateContent.raw(),
                                         "status,completedAt,error,result")) {
    DEBUG_PRINTLN("Status updated successfully");
  } else {
    DEBUG_PRINT("Failed to update status: ");
    DEBUG_PRINTLN(fbdo.errorReason());
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
  // Heartbeat blink every 5 seconds
  if (millis() - lastBlinkTime >= 5000) {
    lastBlinkTime = millis();

    if (firebaseReady && WiFi.status() == WL_CONNECTED) {
      // Single short blink = all good
      blinkLed(1, 50);
    } else if (WiFi.status() == WL_CONNECTED) {
      // Two blinks = WiFi OK, Firebase issue
      blinkLed(2, 100);
    } else {
      // Three blinks = WiFi issue
      blinkLed(3, 100);
    }
  }
}
