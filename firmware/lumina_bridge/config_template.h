/**
 * Lumina Cloud Bridge - Configuration Template
 *
 * Copy this file to 'config.h' and update with your values.
 * DO NOT commit config.h to version control!
 */

#ifndef CONFIG_H
#define CONFIG_H

// ==================== WiFi Configuration ====================
// Customer's home WiFi credentials
#define WIFI_SSID "CustomerWiFi"
#define WIFI_PASSWORD "CustomerPassword123"

// ==================== Firebase Configuration ====================
// Get these from Firebase Console > Project Settings

// Project ID (e.g., "lumina-prod-12345")
#define FIREBASE_PROJECT_ID "your-project-id"

// Web API Key (from Project Settings > General)
#define FIREBASE_API_KEY "AIzaSy..."

// Bridge authentication
// Option 1: Use a dedicated service account (recommended for production)
// Option 2: Create a "bridge" user in Firebase Auth
#define FIREBASE_USER_EMAIL "bridge@lumina.local"
#define FIREBASE_USER_PASSWORD "secure-bridge-password"

// ==================== Controller Configuration ====================
// These are set during installation/provisioning

// The user's Firebase UID (from their account)
#define USER_ID "abc123def456"

// The controller's Firestore document ID
// This is created when the controller is registered in the app
#define CONTROLLER_ID "controller_001"

// ==================== WLED Configuration ====================
// Local IP address of the WLED controller
// The bridge will forward commands to this address
#define WLED_IP "192.168.1.50"
#define WLED_PORT 80

// ==================== Optional Settings ====================
// Heartbeat interval (milliseconds) - how often to report bridge is online
#define HEARTBEAT_INTERVAL 60000

// Command poll interval (milliseconds) - how often to check for pending commands
#define COMMAND_POLL_INTERVAL 2000

// WiFi reconnect attempts before reboot
#define WIFI_MAX_RETRIES 30

// Status LED pin (GPIO2 is built-in LED on most ESP32 boards)
#define STATUS_LED_PIN 2

#endif // CONFIG_H
