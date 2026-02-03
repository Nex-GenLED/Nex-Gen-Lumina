/**
 * Lumina ESP32 Bridge
 *
 * This firmware runs on an ESP32 and acts as a bridge between
 * Firebase Firestore and WLED devices on the local network.
 *
 * How it works:
 * 1. Connects to local WiFi network
 * 2. Polls Firestore for pending commands
 * 3. Executes commands by making HTTP requests to WLED devices
 * 4. Updates command status in Firestore
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WiFiManager.h>
#include <time.h>

#include "config.h"

// ============================================================================
// Global Variables
// ============================================================================

WiFiClientSecure secureClient;
bool firebaseReady = false;
unsigned long lastPollTime = 0;
unsigned long lastBlinkTime = 0;

// Firestore base URL
String firestoreBaseUrl() {
  return "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) +
         "/databases/(default)/documents/users/" + String(FIREBASE_USER_UID);
}

// ============================================================================
// Function Declarations
// ============================================================================

void setupWiFi();
void setupFirebase();
void pollCommands();
void executeCommand(const String& commandId, JsonObject& fields);
String makeWledRequest(const String& ip, const String& method,
                       const String& endpoint, const String& body);
void updateCommandStatus(const String& commandId, const String& status,
                         const String& error = "");
void blinkLed(int times, int delayMs);
void statusBlink();
String convertFirestorePayloadToJson(JsonObject& fields);

// ============================================================================
// Setup
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println();
  Serial.println("=========================================");
  Serial.println("   Lumina ESP32 Bridge v1.1");
  Serial.println("=========================================");
  Serial.println();

  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);

  blinkLed(5, 100);

  setupWiFi();
  setupFirebase();

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
  statusBlink();

  if (millis() - lastPollTime >= POLL_INTERVAL_MS) {
    lastPollTime = millis();

    if (firebaseReady && WiFi.status() == WL_CONNECTED) {
      pollCommands();
    } else {
      DEBUG_PRINTLN("Not ready, skipping poll");
    }
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

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.print("Connected! IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println();
    Serial.print("Failed! WiFi status: ");
    Serial.println(WiFi.status());
    Serial.println("Restarting in 5 seconds...");
    delay(5000);
    ESP.restart();
  }
}

// ============================================================================
// Firebase Setup
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

  // Test connection by checking the commands collection
  Serial.print("Free heap: ");
  Serial.println(ESP.getFreeHeap());
  Serial.print("Testing Firestore connection...");
  HTTPClient http;
  String testUrl = firestoreBaseUrl() + "/commands?key=" + String(FIREBASE_API_KEY) + "&pageSize=1";

  http.begin(secureClient, testUrl);
  int httpCode = http.GET();
  http.end();

  if (httpCode == 200 || httpCode == 404) {
    Serial.println(" Connected!");
    firebaseReady = true;
  } else {
    Serial.print(" Failed! HTTP ");
    Serial.println(httpCode);
    Serial.println("Check your Firebase project ID.");
  }
}

// ============================================================================
// Command Polling
// ============================================================================

void pollCommands() {
  DEBUG_PRINTLN("Polling for commands...");

  HTTPClient http;
  // Use structured query to only fetch pending commands
  String url = firestoreBaseUrl() + ":runQuery?key=" + String(FIREBASE_API_KEY);

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
  } else {
    DEBUG_PRINT("HTTP error: ");
    DEBUG_PRINTLN(httpCode);
    http.end();
  }
}

// ============================================================================
// Command Execution
// ============================================================================

void executeCommand(const String& commandId, JsonObject& fields) {
  Serial.println();
  Serial.print("Executing command: ");
  Serial.println(commandId);

  // Extract command fields from Firestore format
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

  if (controllerIp.isEmpty()) {
    Serial.println("  ERROR: No controller IP specified");
    updateCommandStatus(commandId, "failed", "No controller IP specified");
    return;
  }

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
  } else {
    Serial.println("  SUCCESS!");
    updateCommandStatus(commandId, "completed");
  }
}

// ============================================================================
// Convert Firestore Payload to WLED JSON
// ============================================================================

String convertFirestorePayloadToJson(JsonObject& fields) {
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
                         const String& error) {
  HTTPClient http;
  String url = firestoreBaseUrl() + "/commands/" + commandId +
               "?key=" + String(FIREBASE_API_KEY) + "&updateMask.fieldPaths=status";

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

  String body;
  serializeJson(doc, body);

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    DEBUG_PRINTLN("Status updated");
  } else {
    DEBUG_PRINT("Status update failed: ");
    DEBUG_PRINTLN(httpCode);
  }

  http.end();
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
