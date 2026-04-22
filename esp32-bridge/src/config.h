// Lumina ESP32 Bridge Configuration
//
// This file contains the configuration for the ESP32 bridge device.
// You need to update these values with your Firebase project credentials.

#ifndef CONFIG_H
#define CONFIG_H

// ============================================================================
// Firebase Configuration
// ============================================================================
// Get these from your Firebase Console:
// 1. Go to Project Settings (gear icon)
// 2. Under "Your apps", select your web app
// 3. Find the firebaseConfig object

// Your Firebase project's API key
#define FIREBASE_API_KEY "AIzaSyCWwqffD-ggRh5-IYwR2ldjaztd-Jgz0JY"

// Your Firebase project ID (e.g., "lumina-12345")
#define FIREBASE_PROJECT_ID "icrt6menwsv2d8all8oijs021b06s5"

// Firebase Auth - The user ID whose commands this bridge will execute.
// Phase 1: BLANK at factory. Written to NVS at install time via
// /api/bridge/pair. The bridge will not poll Firestore until this is set.
#define FIREBASE_USER_UID ""

// Firebase Auth credentials for the bridge's own Firebase account.
// The bridge signs in with these to get an ID token for authenticated
// Firestore access. Create this account in Firebase Console > Authentication.
#define FIREBASE_AUTH_EMAIL    "bridge@lumina.local"
#define FIREBASE_AUTH_PASSWORD "bridge@lumina.local"

// ============================================================================
// WiFi Configuration (optional - can use WiFiManager instead)
// ============================================================================
// Phase 1: BLANK at factory. Empty SSID triggers the WiFiManager
// captive portal at boot ("Lumina-XXXX" AP) so the installer can
// enter the homeowner's WiFi credentials. Do not hardcode creds
// before factory flash.

#define WIFI_SSID ""
#define WIFI_PASSWORD ""

// ============================================================================
// Bridge Configuration
// ============================================================================

// How often to poll Firestore for new commands (in milliseconds)
#define POLL_INTERVAL_MS 2000

// Timeout for HTTP requests to WLED devices (in milliseconds)
#define WLED_HTTP_TIMEOUT_MS 10000

// Maximum number of pending commands to process per poll cycle
#define MAX_COMMANDS_PER_POLL 5

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
