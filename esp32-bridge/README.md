# Lumina ESP32 Bridge (Legacy — Firebase Polling)

> **Note:** This is the **legacy** ESP32 bridge implementation. The current recommended bridge firmware is in the [`lumina-firmware/`](../lumina-firmware/) directory, which provides a branded setup experience with a captive portal wizard, web dashboard, and NVS-based configuration (no hardcoded credentials).

This firmware acts as a bridge between Firebase Firestore and WLED devices on your local network, enabling remote control without requiring port forwarding.

## Status: Superseded

This version required hardcoding the Firebase API key, project ID, and user UID in `src/config.h` at compile time. The new `lumina-firmware/` bridge replaces this with:

- **Captive portal WiFi setup** — no hardcoded WiFi credentials
- **3-step web wizard** — configure bridge auth, user pairing, and WLED IP from a phone browser
- **NVS persistence** — settings survive firmware updates
- **Web dashboard** — monitor bridge status, commands, and errors from a browser
- **Heartbeat** — writes to `/users/{uid}/bridge_status/current` every 30 seconds

For setup instructions, see [docs/ESP32_Bridge_Setup_Guide.md](../docs/ESP32_Bridge_Setup_Guide.md).

## How It Worked

1. ESP32 connects to home WiFi (credentials in `config.h`)
2. ESP32 authenticates with Firebase using anonymous auth
3. ESP32 polls Firestore `/users/{uid}/commands` for pending commands
4. ESP32 forwards commands to local WLED device via HTTP
5. ESP32 updates command status in Firestore

## Migration

To migrate from this bridge to the new `lumina-firmware/` bridge:

1. Flash the new firmware from `lumina-firmware/` using PlatformIO
2. Connect to the `Lumina-XXXX` AP from your phone
3. Walk through the 3-step setup wizard (WiFi, auth, pairing)
4. No changes needed in the Lumina app — the Firestore command format is identical

The new bridge uses email/password Firebase Auth instead of anonymous auth, providing better security and the ability to restrict Firestore access via security rules.
