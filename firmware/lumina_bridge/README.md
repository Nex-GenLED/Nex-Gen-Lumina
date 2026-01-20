# Lumina Cloud Bridge - ESP32 Firmware

This firmware enables remote control of WLED lighting systems without requiring port forwarding or Dynamic DNS setup at the customer's home.

## How It Works

```
[Customer's Phone] → [Firebase Cloud] ← [ESP32 Bridge] → [WLED Controller]
       (anywhere)         ↑                (home WiFi)      (home WiFi)
                          │
                    Commands stored
                    in Firestore
```

1. Customer opens Lumina app and sends a command (e.g., "turn on lights")
2. App writes command to Firestore: `/users/{uid}/commands/{commandId}`
3. ESP32 Bridge (on customer's home WiFi) polls Firestore for pending commands
4. Bridge forwards command to local WLED controller via HTTP
5. Bridge updates command status in Firestore
6. App sees command completed

**Key benefit:** The ESP32 initiates outbound connections to Firebase, so no router configuration is needed!

## Hardware Requirements

- ESP32 board (any variant with WiFi)
  - Recommended: ESP32-WROOM-32, ESP32-S3, or ESP32-C3
  - Can use the same ESP32 that runs WLED if it has enough resources
- USB cable for programming
- Customer's WiFi network credentials

## Software Requirements

### Arduino IDE Setup

1. Install [Arduino IDE](https://www.arduino.cc/en/software) (2.x recommended)

2. Add ESP32 board support:
   - Go to File → Preferences
   - Add to "Additional Board Manager URLs":
     ```
     https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
     ```
   - Go to Tools → Board → Boards Manager
   - Search "esp32" and install "ESP32 by Espressif Systems"

3. Install required libraries (Tools → Manage Libraries):
   - **Firebase ESP Client** by mobizt (v4.4.x or later)
   - **ArduinoJson** by Benoit Blanchon (v6.x or v7.x)

### PlatformIO Setup (Alternative)

If using PlatformIO, add to `platformio.ini`:

```ini
[env:esp32]
platform = espressif32
board = esp32dev
framework = arduino
lib_deps =
    mobizt/Firebase ESP Client@^4.4.0
    bblanchon/ArduinoJson@^7.0.0
monitor_speed = 115200
```

## Firebase Setup

### 1. Enable Firestore

In Firebase Console:
1. Go to Firestore Database
2. Create database (start in production mode)
3. Firestore should already be configured from the Lumina app

### 2. Create Bridge User

Option A: Use Firebase Auth (recommended for development)
1. Go to Firebase Console → Authentication → Users
2. Add a new user for the bridge:
   - Email: `bridge@lumina.local`
   - Password: (generate a secure password)

Option B: Use Service Account (recommended for production)
1. Go to Firebase Console → Project Settings → Service Accounts
2. Generate new private key
3. Use service account credentials in firmware

### 3. Get Firebase Credentials

From Firebase Console → Project Settings → General:
- **Project ID**: e.g., `lumina-prod-12345`
- **Web API Key**: e.g., `AIzaSy...`

## Firmware Configuration

1. Copy `config_template.h` to `config.h`
2. Update all values in `config.h`:

```cpp
// Customer's WiFi
#define WIFI_SSID "CustomerWiFi"
#define WIFI_PASSWORD "CustomerPassword"

// Firebase (same for all bridges)
#define FIREBASE_PROJECT_ID "lumina-prod-12345"
#define FIREBASE_API_KEY "AIzaSy..."
#define FIREBASE_USER_EMAIL "bridge@lumina.local"
#define FIREBASE_USER_PASSWORD "bridge-password"

// Customer-specific (set during installation)
#define USER_ID "customer-firebase-uid"
#define CONTROLLER_ID "controller-doc-id"
#define WLED_IP "192.168.1.50"
```

3. Flash to ESP32:
   - Select board: Tools → Board → ESP32 Dev Module
   - Select port: Tools → Port → (your ESP32 port)
   - Click Upload

## Installation Workflow

### For Installers

1. **Before arriving at customer site:**
   - Customer creates account in Lumina app
   - Customer adds their controller in the app (gets `CONTROLLER_ID`)
   - Note the customer's Firebase UID (`USER_ID`)

2. **At customer site:**
   - Connect to customer's WiFi to get credentials
   - Get WLED controller's local IP address
   - Update `config.h` with all values
   - Flash firmware to ESP32
   - Power on ESP32 and verify connection

3. **Verification:**
   - Open Serial Monitor (115200 baud)
   - Should see: "WiFi connected!", "Firebase authenticated!", "Bridge ready!"
   - In Lumina app, send a test command
   - Verify lights respond

### Provisioning Tool (Future)

For easier installation, we can create:
- A mobile app that provisions the ESP32 via BLE
- A web interface that configures via WiFi AP mode
- Pre-flashed devices that self-configure on first boot

## Troubleshooting

### WiFi Connection Issues
- Check SSID and password are correct
- Ensure customer's router allows 2.4GHz connections
- Try moving ESP32 closer to router

### Firebase Authentication Issues
- Verify API key is correct
- Check bridge user email/password
- Ensure Firestore security rules allow bridge access

### WLED Not Responding
- Verify WLED IP address is correct
- Ensure WLED is on the same network
- Check if WLED's HTTP API is enabled

### Commands Not Processing
- Check Firestore for pending commands
- Verify USER_ID and CONTROLLER_ID match Firestore documents
- Check Serial Monitor for error messages

## LED Status Indicators

| Pattern | Meaning |
|---------|---------|
| Blinking during startup | Connecting to WiFi |
| Solid on | Connected and ready |
| 3 quick blinks | Bridge initialized successfully |
| 1 quick blink | Command executed successfully |
| 5 rapid blinks | Command execution error |
| Off | Error or no power |

## Security Considerations

1. **Never commit `config.h`** - it contains credentials
2. **Use unique bridge passwords** per installation for production
3. **Firestore rules** should validate that commands come from authenticated users
4. **HTTPS** - Firebase connections are encrypted by default

## Firestore Security Rules

Add these rules to allow bridge access:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read/write their own commands
    match /users/{userId}/commands/{commandId} {
      allow read, write: if request.auth != null &&
        (request.auth.uid == userId ||
         request.auth.token.email == 'bridge@lumina.local');
    }

    // Bridge can update controller status
    match /users/{userId}/controllers/{controllerId} {
      allow read: if request.auth != null;
      allow update: if request.auth != null &&
        request.auth.token.email == 'bridge@lumina.local';
    }
  }
}
```

## Version History

- **v1.0.0** - Initial release
  - Basic command polling and execution
  - Heartbeat reporting
  - Status LED indicators
