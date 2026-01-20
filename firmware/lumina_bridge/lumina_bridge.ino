/**
 * Lumina Cloud Bridge - ESP32 Firmware
 *
 * This firmware connects to Firebase Firestore and listens for commands,
 * then forwards them to the local WLED controller via HTTP.
 *
 * No port forwarding or Dynamic DNS required - the ESP32 initiates
 * an outbound connection to Firebase.
 *
 * Hardware: ESP32 (any variant with WiFi)
 *
 * Setup:
 * 1. Install required libraries (see below)
 * 2. Update WiFi credentials
 * 3. Update Firebase credentials
 * 4. Update WLED IP address
 * 5. Flash to ESP32
 *
 * Required Libraries (install via Arduino Library Manager):
 * - Firebase ESP Client by mobizt (v4.4.x or later)
 * - ArduinoJson by Benoit Blanchon (v6.x or v7.x)
 * - WiFi (built-in for ESP32)
 * - HTTPClient (built-in for ESP32)
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>

// ==================== CONFIGURATION ====================
// WiFi credentials - UPDATE THESE
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// Firebase project credentials - UPDATE THESE
// Get these from Firebase Console > Project Settings > General
#define FIREBASE_PROJECT_ID "your-firebase-project-id"

// Firebase API key - Get from Firebase Console > Project Settings > General > Web API Key
#define FIREBASE_API_KEY "your-firebase-api-key"

// Firebase Auth - Service account or anonymous auth
// For production, use a service account. For testing, enable anonymous auth in Firebase Console.
#define FIREBASE_USER_EMAIL "bridge@lumina.local"
#define FIREBASE_USER_PASSWORD "your-bridge-password"

// Controller identification - UPDATE THESE
// This should match the controller document ID in Firestore
#define CONTROLLER_ID "your-controller-id"
#define USER_ID "your-user-id"

// WLED device IP address on local network - UPDATE THIS
#define WLED_IP "192.168.1.50"
#define WLED_PORT 80

// ==================== END CONFIGURATION ====================

// Firebase objects
FirebaseData fbdo;
FirebaseData stream;
FirebaseAuth auth;
FirebaseConfig config;

// State tracking
bool firebaseReady = false;
unsigned long lastHeartbeat = 0;
const unsigned long HEARTBEAT_INTERVAL = 60000; // 1 minute

// Status LED (built-in on most ESP32 boards)
#define STATUS_LED 2

void setup() {
  Serial.begin(115200);
  Serial.println("\n\n=== Lumina Cloud Bridge ===");
  Serial.println("Firmware v1.0.0");

  // Setup status LED
  pinMode(STATUS_LED, OUTPUT);
  digitalWrite(STATUS_LED, LOW);

  // Connect to WiFi
  connectWiFi();

  // Initialize Firebase
  initFirebase();

  // Start listening for commands
  startCommandListener();

  Serial.println("Bridge ready!");
  blinkLED(3, 200); // 3 quick blinks = ready
}

void loop() {
  // Handle Firebase stream
  if (Firebase.ready() && firebaseReady) {
    // Check for new commands periodically (backup to stream)
    checkPendingCommands();

    // Send heartbeat to show bridge is online
    if (millis() - lastHeartbeat > HEARTBEAT_INTERVAL) {
      sendHeartbeat();
      lastHeartbeat = millis();
    }
  }

  // Reconnect WiFi if disconnected
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected, reconnecting...");
    connectWiFi();
  }

  delay(100);
}

// ==================== WiFi Functions ====================

void connectWiFi() {
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    digitalWrite(STATUS_LED, !digitalRead(STATUS_LED)); // Blink while connecting
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected!");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
    digitalWrite(STATUS_LED, HIGH);
  } else {
    Serial.println("\nWiFi connection failed!");
    digitalWrite(STATUS_LED, LOW);
  }
}

// ==================== Firebase Functions ====================

void initFirebase() {
  Serial.println("Initializing Firebase...");

  config.api_key = FIREBASE_API_KEY;

  auth.user.email = FIREBASE_USER_EMAIL;
  auth.user.password = FIREBASE_USER_PASSWORD;

  config.token_status_callback = tokenStatusCallback;

  // Initialize Firebase
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Wait for authentication
  Serial.println("Authenticating with Firebase...");
  unsigned long authStart = millis();
  while (!Firebase.ready() && millis() - authStart < 30000) {
    delay(100);
  }

  if (Firebase.ready()) {
    Serial.println("Firebase authenticated!");
    firebaseReady = true;
  } else {
    Serial.println("Firebase authentication failed!");
    firebaseReady = false;
  }
}

void startCommandListener() {
  if (!firebaseReady) return;

  // Build the Firestore path for commands
  String commandsPath = "projects/" + String(FIREBASE_PROJECT_ID) +
                        "/databases/(default)/documents/users/" +
                        String(USER_ID) + "/commands";

  Serial.print("Listening for commands at: ");
  Serial.println(commandsPath);

  // Note: For real-time listening, we'll poll for pending commands
  // Full Firestore streaming requires more complex setup
}

void checkPendingCommands() {
  static unsigned long lastCheck = 0;
  if (millis() - lastCheck < 2000) return; // Check every 2 seconds
  lastCheck = millis();

  // Query for pending commands
  String basePath = "projects/" + String(FIREBASE_PROJECT_ID) +
                    "/databases/(default)/documents/users/" +
                    String(USER_ID) + "/commands";

  // Use Firestore REST API to query pending commands
  if (Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "",
      String("users/") + USER_ID + "/commands", "")) {

    // Parse the response
    FirebaseJson json;
    json.setJsonData(fbdo.payload());

    // Look for documents array
    FirebaseJsonData documents;
    if (json.get(documents, "documents")) {
      FirebaseJsonArray arr;
      documents.getArray(arr);

      for (size_t i = 0; i < arr.size(); i++) {
        FirebaseJsonData doc;
        arr.get(doc, i);

        // Parse each document
        FirebaseJson docJson;
        docJson.setJsonData(doc.stringValue);

        // Check if status is "pending"
        FirebaseJsonData statusField;
        if (docJson.get(statusField, "fields/status/stringValue")) {
          if (statusField.stringValue == "pending") {
            // Extract document name to get command ID
            FirebaseJsonData nameField;
            if (docJson.get(nameField, "name")) {
              String docPath = nameField.stringValue;
              int lastSlash = docPath.lastIndexOf('/');
              String commandId = docPath.substring(lastSlash + 1);

              Serial.print("Found pending command: ");
              Serial.println(commandId);

              processCommand(docJson, commandId);
            }
          }
        }
      }
    }
  }
}

void processCommand(FirebaseJson& docJson, String commandId) {
  Serial.println("Processing command: " + commandId);

  // Mark as executing
  updateCommandStatus(commandId, "executing", "");

  // Extract command type
  FirebaseJsonData typeField;
  String commandType = "setState";
  if (docJson.get(typeField, "fields/type/stringValue")) {
    commandType = typeField.stringValue;
  }

  // Extract payload
  FirebaseJsonData payloadField;
  String payload = "{}";
  if (docJson.get(payloadField, "fields/payload/mapValue")) {
    payload = convertFirestoreMapToJson(payloadField.stringValue);
  }

  Serial.print("Command type: ");
  Serial.println(commandType);
  Serial.print("Payload: ");
  Serial.println(payload);

  // Execute the command on WLED
  String result;
  bool success = executeWledCommand(commandType, payload, result);

  // Update command status
  if (success) {
    Serial.println("Command executed successfully!");
    updateCommandStatus(commandId, "completed", result);
    blinkLED(1, 100); // Quick blink = success
  } else {
    Serial.println("Command execution failed!");
    updateCommandStatus(commandId, "failed", result);
    blinkLED(5, 50); // Rapid blinks = error
  }
}

bool executeWledCommand(String commandType, String payload, String& result) {
  HTTPClient http;
  String url;
  String method = "POST";

  // Build URL based on command type
  if (commandType == "getState") {
    url = "http://" + String(WLED_IP) + ":" + String(WLED_PORT) + "/json/state";
    method = "GET";
  } else if (commandType == "getInfo") {
    url = "http://" + String(WLED_IP) + ":" + String(WLED_PORT) + "/json/info";
    method = "GET";
  } else if (commandType == "applyConfig") {
    url = "http://" + String(WLED_IP) + ":" + String(WLED_PORT) + "/json/cfg";
  } else {
    // Default: setState, applyJson, etc.
    url = "http://" + String(WLED_IP) + ":" + String(WLED_PORT) + "/json/state";
  }

  Serial.print("Calling WLED: ");
  Serial.print(method);
  Serial.print(" ");
  Serial.println(url);

  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(10000); // 10 second timeout

  int httpCode;
  if (method == "GET") {
    httpCode = http.GET();
  } else {
    httpCode = http.POST(payload);
  }

  if (httpCode > 0) {
    result = http.getString();
    Serial.print("WLED response (");
    Serial.print(httpCode);
    Serial.print("): ");
    Serial.println(result.substring(0, 200)); // Print first 200 chars

    http.end();
    return (httpCode == 200);
  } else {
    result = "HTTP error: " + String(http.errorToString(httpCode).c_str());
    Serial.println(result);
    http.end();
    return false;
  }
}

void updateCommandStatus(String commandId, String status, String result) {
  String docPath = "users/" + String(USER_ID) + "/commands/" + commandId;

  FirebaseJson content;
  content.set("fields/status/stringValue", status);
  content.set("fields/completedAt/timestampValue", getISOTimestamp());

  if (result.length() > 0) {
    if (status == "completed") {
      // Try to parse result as JSON
      content.set("fields/result/stringValue", result);
    } else {
      content.set("fields/error/stringValue", result);
    }
  }

  if (Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "",
      docPath, content.raw(), "status,completedAt,result,error")) {
    Serial.println("Command status updated: " + status);
  } else {
    Serial.println("Failed to update command status: " + fbdo.errorReason());
  }
}

void sendHeartbeat() {
  // Update controller document with last seen timestamp
  String docPath = "users/" + String(USER_ID) + "/controllers/" + String(CONTROLLER_ID);

  FirebaseJson content;
  content.set("fields/bridgeLastSeen/timestampValue", getISOTimestamp());
  content.set("fields/bridgeOnline/booleanValue", true);
  content.set("fields/bridgeIP/stringValue", WiFi.localIP().toString());

  if (Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "",
      docPath, content.raw(), "bridgeLastSeen,bridgeOnline,bridgeIP")) {
    Serial.println("Heartbeat sent");
  } else {
    Serial.println("Heartbeat failed: " + fbdo.errorReason());
  }
}

// ==================== Utility Functions ====================

String getISOTimestamp() {
  // Get current time - in production, use NTP
  // For now, return a placeholder that Firebase will accept
  time_t now;
  time(&now);
  char buf[30];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  return String(buf);
}

String convertFirestoreMapToJson(String firestoreMap) {
  // Convert Firestore map format to standard JSON
  // This is a simplified conversion - expand as needed
  FirebaseJson json;
  json.setJsonData(firestoreMap);

  // Extract fields and convert to simple JSON
  FirebaseJson output;
  FirebaseJsonData data;

  // Common WLED fields
  if (json.get(data, "fields/on/booleanValue")) {
    output.set("on", data.boolValue);
  }
  if (json.get(data, "fields/bri/integerValue")) {
    output.set("bri", data.intValue);
  }
  if (json.get(data, "fields/seg/arrayValue")) {
    // Handle segment array - this needs more complex parsing
    output.set("seg", data.stringValue);
  }

  String result;
  output.toString(result, false);
  return result;
}

void blinkLED(int times, int delayMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(STATUS_LED, HIGH);
    delay(delayMs);
    digitalWrite(STATUS_LED, LOW);
    delay(delayMs);
  }
}

void tokenStatusCallback(TokenInfo info) {
  if (info.status == token_status_error) {
    Serial.print("Token error: ");
    Serial.println(info.error.message.c_str());
  }
}
