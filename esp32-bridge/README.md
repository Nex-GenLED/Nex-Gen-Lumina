# Lumina ESP32 Bridge

This ESP32 firmware acts as a bridge between Firebase Firestore and WLED devices on your local network, enabling remote control without requiring WLED to support MQTT+TLS.

## How It Works

1. **ESP32 connects to your home WiFi** - Same network as your WLED devices
2. **ESP32 authenticates with Firebase** - Uses your Firebase project credentials
3. **ESP32 polls Firestore** - Checks for pending commands every 2 seconds
4. **ESP32 executes commands locally** - Makes HTTP requests to WLED devices
5. **ESP32 updates command status** - Reports success/failure back to Firestore

The Flutter app writes commands to Firestore when you're away from home, and this bridge executes them on your behalf.

## Requirements

- ESP32 development board (any variant)
- USB cable for programming
- PlatformIO IDE (VS Code extension recommended)

## Setup

### 1. Install PlatformIO

Install the [PlatformIO IDE extension](https://platformio.org/install/ide?install=vscode) in VS Code.

### 2. Configure Credentials

Edit `src/config.h` and update the following:

```cpp
// Your Firebase API key (from Firebase Console → Project Settings)
#define FIREBASE_API_KEY "AIzaSy..."

// Your Firebase project ID (e.g., "lumina-app-12345")
#define FIREBASE_PROJECT_ID "lumina-app-12345"

// The Firebase UID of the user whose commands this bridge will execute
// (Find this in Firebase Console → Authentication → Users)
#define FIREBASE_USER_UID "abc123xyz..."
```

### 3. Build and Upload

1. Connect your ESP32 via USB
2. Open this folder in VS Code
3. Click the PlatformIO icon in the sidebar
4. Click "Build" to compile
5. Click "Upload" to flash the ESP32

### 4. Configure WiFi

On first boot (or if WiFi credentials are lost):

1. The ESP32 creates an AP called "Lumina-Bridge"
2. Connect to it from your phone (password: `luminabridge`)
3. A configuration portal opens automatically
4. Select your home WiFi network and enter the password
5. The ESP32 saves the credentials and connects

### 5. Verify Operation

Open the Serial Monitor (115200 baud) to see status messages:

```
=========================================
   Lumina ESP32 Bridge v1.0
=========================================

Setting up WiFi...
Connected! IP: 192.168.1.100

Setting up Firebase... Ready!

Bridge initialized and ready!
Polling for commands...
```

The blue LED will blink once every 5 seconds to indicate it's running:
- 1 blink: All systems OK
- 2 blinks: WiFi OK, Firebase issue
- 3 blinks: WiFi disconnected

## LED Indicators

| Pattern | Meaning |
|---------|---------|
| Rapid blinks on startup | Initializing |
| Solid 1 second | Successfully initialized |
| Single blink every 5s | Normal operation |
| LED on during processing | Executing command |
| 2 blinks every 5s | Firebase connection issue |
| 3 blinks every 5s | WiFi disconnected |

## Troubleshooting

### "Firebase not ready"
- Check your API key and project ID in `config.h`
- Ensure your Firebase project has Firestore enabled
- Check that Firestore security rules allow reads/writes

### "Failed to connect to WiFi"
- The ESP32 will create an AP for configuration
- Connect to "Lumina-Bridge" and configure WiFi
- Make sure the password is correct

### Commands not executing
- Check that `FIREBASE_USER_UID` matches your app's logged-in user
- Verify the WLED device IP is correct in your app
- Check Serial Monitor for detailed error messages

### Commands timing out
- Ensure the WLED device is powered on
- Check that ESP32 is on the same network as WLED
- Try increasing `WLED_HTTP_TIMEOUT_MS` in config.h

## Security Notes

- The ESP32 uses anonymous Firebase authentication by default
- Firestore security rules should validate that only the bridge can update command status
- Consider adding a device token for additional security in production

## Updating Firmware

1. Connect the ESP32 via USB
2. Open this project in VS Code
3. Click "Upload" in PlatformIO

The WiFi credentials are stored in flash and will persist after firmware updates.
