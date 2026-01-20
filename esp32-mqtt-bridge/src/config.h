// Lumina ESP32 MQTT Bridge Configuration
//
// This file contains the configuration for the ESP32 MQTT bridge device.
// Update these values with your HiveMQ Cloud credentials and WLED device info.

#ifndef CONFIG_H
#define CONFIG_H

// ============================================================================
// HiveMQ Cloud Configuration
// ============================================================================
// Get these from your Lumina Backend .env file or HiveMQ Cloud console

// HiveMQ Cloud broker hostname (without protocol)
#define MQTT_BROKER "4429fe3219f64734b912d6bef5d6688b.s1.eu.hivemq.cloud"

// HiveMQ Cloud TLS port
#define MQTT_PORT 8883

// MQTT credentials (from device provisioning or HiveMQ console)
// You can use the same credentials as your Lumina Backend, or device-specific ones
#define MQTT_USERNAME "NexGen"
#define MQTT_PASSWORD "Grayson8817*"

// ============================================================================
// Device Configuration
// ============================================================================

// The device ID from your Lumina Backend (from /api/devices/provision)
// This determines which MQTT topics this bridge listens to
#define DEVICE_ID "a55fbb4d-ecea-4c66-aaff-278985528588"

// Local IP address of your WLED controller (static IP)
#define WLED_IP "192.168.50.200"

// WLED HTTP port (usually 80)
#define WLED_PORT 80

// ============================================================================
// WiFi Configuration (optional - can use WiFiManager instead)
// ============================================================================
// If you leave these commented out, the bridge will start in AP mode
// and let you configure WiFi via a web portal

// WiFi credentials for "Nexgen" network (Router mode)
#define WIFI_SSID "Nexgen"
#define WIFI_PASSWORD "Nexgen365"

// ============================================================================
// Static IP Configuration (optional - recommended to avoid IP conflicts)
// ============================================================================
// Set a static IP for the bridge so it doesn't conflict with WLED
// Make sure this IP is outside your router's DHCP range, or reserve it

// Use static IP to avoid conflict with WLED (192.168.50.210)
#define USE_STATIC_IP true
#define STATIC_IP "192.168.50.100"       // Bridge gets .100, WLED keeps .210
#define STATIC_GATEWAY "192.168.50.1"    // Nexgen network gateway
#define STATIC_SUBNET "255.255.255.0"
#define STATIC_DNS "8.8.8.8"             // Google DNS

// ============================================================================
// MQTT Topics
// ============================================================================
// These are derived from DEVICE_ID - don't change unless you know what you're doing

#define MQTT_TOPIC_COMMAND "lumina/" DEVICE_ID "/command"
#define MQTT_TOPIC_STATUS "lumina/" DEVICE_ID "/status"

// Client ID for MQTT connection (must be unique per device)
#define MQTT_CLIENT_ID "lumina-bridge-" DEVICE_ID

// ============================================================================
// Timing Configuration
// ============================================================================

// How often to send MQTT keepalive (seconds)
#define MQTT_KEEPALIVE 60

// Timeout for HTTP requests to WLED (milliseconds)
#define WLED_HTTP_TIMEOUT_MS 10000

// How often to publish device status (milliseconds) - 0 to disable
#define STATUS_PUBLISH_INTERVAL_MS 30000

// LED pin for status indication (built-in LED on most ESP32 dev boards)
#define STATUS_LED_PIN 2

// ============================================================================
// Debug Configuration
// ============================================================================

// Set to 1 to enable verbose debug output
#define DEBUG_ENABLED 1

#if DEBUG_ENABLED
  #define DEBUG_PRINT(x) Serial.print(x)
  #define DEBUG_PRINTLN(x) Serial.println(x)
  #define DEBUG_PRINTF(...) Serial.printf(__VA_ARGS__)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINTLN(x)
  #define DEBUG_PRINTF(...)
#endif

#endif // CONFIG_H
