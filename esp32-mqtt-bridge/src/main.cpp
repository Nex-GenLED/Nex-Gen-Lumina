/**
 * Lumina ESP32 MQTT Bridge
 *
 * This firmware runs on an ESP32 and bridges MQTT messages from HiveMQ Cloud
 * to local WLED devices via HTTP. It enables remote control without requiring
 * WLED to support MQTT+TLS.
 *
 * How it works:
 * 1. Connects to WiFi and HiveMQ Cloud (with TLS)
 * 2. Subscribes to `lumina/{deviceId}/command`
 * 3. When a command arrives, makes HTTP request to WLED
 * 4. Publishes WLED's response to `lumina/{deviceId}/status`
 *
 * This works with T-Mobile Home Internet and other CGNAT situations
 * because it only makes outbound connections.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <WiFiManager.h>

#include "config.h"

// ============================================================================
// HiveMQ Cloud Root CA Certificate
// ============================================================================
// This is the ISRG Root X1 certificate used by Let's Encrypt (HiveMQ's CA)
const char* root_ca = R"EOF(
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
)EOF";

// ============================================================================
// Global Variables
// ============================================================================

WiFiClientSecure espClient;
PubSubClient mqttClient(espClient);

// State
bool wifiConnected = false;
bool mqttConnected = false;
unsigned long lastStatusPublish = 0;
unsigned long lastReconnectAttempt = 0;
int commandsProcessed = 0;
int commandsFailed = 0;

// LED blink state
unsigned long lastBlinkTime = 0;

// ============================================================================
// Function Declarations
// ============================================================================

void setupWiFi();
void setupMQTT();
bool connectMQTT();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void processCommand(const char* payload, unsigned int length);
String makeWledRequest(const String& method, const String& endpoint, const String& body);
void publishStatus(const String& status);
void publishDeviceState();
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
  Serial.println("   Lumina ESP32 MQTT Bridge v1.0");
  Serial.println("=========================================");
  Serial.println();
  Serial.print("Device ID: ");
  Serial.println(DEVICE_ID);
  Serial.print("WLED IP: ");
  Serial.println(WLED_IP);
  Serial.println();

  // Initialize status LED
  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);

  // Rapid blink to indicate startup
  blinkLed(5, 100);

  // Setup WiFi
  setupWiFi();

  // Setup MQTT
  setupMQTT();

  Serial.println();
  Serial.println("Bridge initialized!");
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
  // Status blink
  statusBlink();

  // Handle MQTT
  if (!mqttClient.connected()) {
    unsigned long now = millis();
    if (now - lastReconnectAttempt > 5000) {
      lastReconnectAttempt = now;
      if (connectMQTT()) {
        lastReconnectAttempt = 0;
      }
    }
  } else {
    mqttClient.loop();
  }

  // Periodically publish device status
  if (STATUS_PUBLISH_INTERVAL_MS > 0 && mqttClient.connected()) {
    if (millis() - lastStatusPublish > STATUS_PUBLISH_INTERVAL_MS) {
      lastStatusPublish = millis();
      publishDeviceState();
    }
  }

  delay(10);
}

// ============================================================================
// WiFi Setup
// ============================================================================

void setupWiFi() {
  Serial.println("Setting up WiFi...");

#if defined(USE_STATIC_IP) && USE_STATIC_IP
  // Configure static IP before connecting
  IPAddress staticIP, gateway, subnet, dns;
  staticIP.fromString(STATIC_IP);
  gateway.fromString(STATIC_GATEWAY);
  subnet.fromString(STATIC_SUBNET);
  dns.fromString(STATIC_DNS);

  Serial.print("Configuring static IP: ");
  Serial.println(STATIC_IP);

  if (!WiFi.config(staticIP, gateway, subnet, dns)) {
    Serial.println("Static IP configuration failed!");
  }
#endif

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
    wifiConnected = true;
    return;
  }

  Serial.println();
  Serial.println("Failed to connect with hardcoded credentials");
#endif

  // Use WiFiManager for configuration
  Serial.println("Starting WiFiManager...");
  Serial.println("Connect to 'Lumina-MQTT-Bridge' AP to configure WiFi");

  WiFiManager wifiManager;
  wifiManager.setConfigPortalTimeout(180); // 3 minute timeout

#if defined(USE_STATIC_IP) && USE_STATIC_IP
  // Configure static IP for WiFiManager (reuse variables from above if they exist)
  {
    IPAddress wmStaticIP, wmGateway, wmSubnet, wmDns;
    wmStaticIP.fromString(STATIC_IP);
    wmGateway.fromString(STATIC_GATEWAY);
    wmSubnet.fromString(STATIC_SUBNET);
    wmDns.fromString(STATIC_DNS);
    wifiManager.setSTAStaticIPConfig(wmStaticIP, wmGateway, wmSubnet, wmDns);
    Serial.print("Static IP configured for WiFiManager: ");
    Serial.println(STATIC_IP);
  }
#endif

  if (!wifiManager.autoConnect("Lumina-MQTT-Bridge", "luminabridge")) {
    Serial.println("Failed to connect and config portal timed out");
    Serial.println("Restarting...");
    delay(3000);
    ESP.restart();
  }

  Serial.println();
  Serial.print("Connected! IP: ");
  Serial.println(WiFi.localIP());
  wifiConnected = true;
}

// ============================================================================
// MQTT Setup
// ============================================================================

void setupMQTT() {
  Serial.println("Setting up MQTT...");

  // Configure TLS
  espClient.setCACert(root_ca);

  // Configure MQTT client
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(2048); // Larger buffer for JSON payloads
  mqttClient.setKeepAlive(MQTT_KEEPALIVE);

  // Connect
  connectMQTT();
}

bool connectMQTT() {
  Serial.print("Connecting to HiveMQ Cloud...");

  if (mqttClient.connect(MQTT_CLIENT_ID, MQTT_USERNAME, MQTT_PASSWORD)) {
    Serial.println(" Connected!");
    mqttConnected = true;

    // Subscribe to command topic
    Serial.print("Subscribing to: ");
    Serial.println(MQTT_TOPIC_COMMAND);
    mqttClient.subscribe(MQTT_TOPIC_COMMAND);

    // Publish online status
    publishStatus("{\"online\": true, \"bridge\": \"esp32-mqtt\"}");

    return true;
  } else {
    Serial.print(" Failed, rc=");
    Serial.print(mqttClient.state());
    Serial.println(" - will retry in 5 seconds");
    mqttConnected = false;
    return false;
  }
}

// ============================================================================
// MQTT Callback
// ============================================================================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  Serial.println();
  Serial.print("Message received on topic: ");
  Serial.println(topic);

  // LED on while processing
  digitalWrite(STATUS_LED_PIN, HIGH);

  // Process the command
  processCommand((const char*)payload, length);

  digitalWrite(STATUS_LED_PIN, LOW);
}

// ============================================================================
// Command Processing
// ============================================================================

void processCommand(const char* payload, unsigned int length) {
  // Parse the incoming JSON command
  DynamicJsonDocument doc(2048);
  DeserializationError error = deserializeJson(doc, payload, length);

  if (error) {
    Serial.print("JSON parse error: ");
    Serial.println(error.c_str());
    publishStatus("{\"error\": \"JSON parse error\"}");
    commandsFailed++;
    return;
  }

  // Extract action and payload
  const char* action = doc["action"] | "setState";
  JsonObject cmdPayload = doc["payload"].as<JsonObject>();

  Serial.print("Action: ");
  Serial.println(action);

  // Determine endpoint and method based on action
  String endpoint;
  String method = "POST";
  String body;

  if (strcmp(action, "getState") == 0) {
    endpoint = "/json/state";
    method = "GET";
  } else if (strcmp(action, "getInfo") == 0) {
    endpoint = "/json/info";
    method = "GET";
  } else if (strcmp(action, "setState") == 0 || strcmp(action, "applyJson") == 0) {
    endpoint = "/json/state";
    serializeJson(cmdPayload, body);
  } else if (strcmp(action, "setConfig") == 0 || strcmp(action, "applyConfig") == 0) {
    endpoint = "/json/cfg";
    serializeJson(cmdPayload, body);
  } else {
    // Default to state update
    endpoint = "/json/state";
    serializeJson(cmdPayload, body);
  }

  Serial.print("-> ");
  Serial.print(method);
  Serial.print(" http://");
  Serial.print(WLED_IP);
  Serial.println(endpoint);

  if (body.length() > 0) {
    Serial.print("Body: ");
    Serial.println(body);
  }

  // Make the HTTP request to WLED
  String response = makeWledRequest(method, endpoint, body);

  if (response.startsWith("ERROR:")) {
    Serial.print("Request failed: ");
    Serial.println(response);

    // Publish error status
    DynamicJsonDocument errDoc(256);
    errDoc["error"] = response;
    errDoc["action"] = action;
    String errJson;
    serializeJson(errDoc, errJson);
    publishStatus(errJson);
    commandsFailed++;
  } else {
    Serial.println("Request successful!");
    commandsProcessed++;

    // Publish the WLED response as status
    publishStatus(response);
  }
}

// ============================================================================
// HTTP Request to WLED
// ============================================================================

String makeWledRequest(const String& method, const String& endpoint, const String& body) {
  HTTPClient http;
  String url = "http://" + String(WLED_IP) + ":" + String(WLED_PORT) + endpoint;

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
    httpCode = http.POST(body);
  } else {
    http.end();
    return "ERROR: Unsupported method";
  }

  if (httpCode > 0) {
    if (httpCode == HTTP_CODE_OK || httpCode == 200) {
      String response = http.getString();
      http.end();
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
// Publish Status to MQTT
// ============================================================================

void publishStatus(const String& status) {
  if (!mqttClient.connected()) {
    Serial.println("Cannot publish - MQTT not connected");
    return;
  }

  Serial.print("Publishing to ");
  Serial.print(MQTT_TOPIC_STATUS);
  Serial.print(": ");
  Serial.println(status.substring(0, 100) + (status.length() > 100 ? "..." : ""));

  mqttClient.publish(MQTT_TOPIC_STATUS, status.c_str(), false);
}

void publishDeviceState() {
  // Fetch current state from WLED and publish it
  String state = makeWledRequest("GET", "/json/state", "");
  if (!state.startsWith("ERROR:")) {
    // Add bridge metadata
    DynamicJsonDocument doc(2048);
    deserializeJson(doc, state);
    doc["_bridge"] = "esp32-mqtt";
    doc["_uptime"] = millis() / 1000;
    doc["_commands"] = commandsProcessed;
    doc["_errors"] = commandsFailed;

    String enrichedState;
    serializeJson(doc, enrichedState);
    publishStatus(enrichedState);
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

    if (mqttConnected && wifiConnected) {
      // Single short blink = all good
      blinkLed(1, 50);
    } else if (wifiConnected) {
      // Two blinks = WiFi OK, MQTT issue
      blinkLed(2, 100);
    } else {
      // Three blinks = WiFi issue
      blinkLed(3, 100);
    }
  }
}
