# Nex-Gen Lumina v2.1 -- ESP32 Bridge Setup Guide

> **Purpose:** Enable remote control of your WLED lighting system from anywhere, without port forwarding.
> The Lumina Bridge is a dedicated ESP32 device that sits on your home WiFi and relays commands from Firebase to your WLED controller(s).

---

## How Remote Access Works in Lumina v2.1

Lumina automatically detects whether you are on your home WiFi or away:

- **On home WiFi:** The app communicates directly with your WLED controller over HTTP (`WledService`). The bridge is not involved.
- **Away from home (cellular or another WiFi):** The app writes commands to your Firebase `/users/{uid}/commands` collection. The Lumina Bridge, which is always connected to your home network, picks up those commands and forwards them to the WLED controller.

On every app startup, Lumina runs a **bridge health check**. It writes a ping document to `/users/{uid}/commands/bridge_health_check` and watches for up to **15 seconds** for the bridge to acknowledge it. The result is exposed via `bridgeHealthProvider` as one of three states:

| State | Meaning |
|-------|---------|
| `BridgeHealth.checking` | Health check is in progress. |
| `BridgeHealth.alive` | Bridge acknowledged the ping within 15 seconds. |
| `BridgeHealth.unreachable` | Bridge did not respond in time. |

The home screen displays a bridge status indicator reflecting this result.

The bridge also writes a **heartbeat** document to `/users/{uid}/bridge_status/current` every 30 seconds containing uptime, IP address, command counts, and firmware version.

---

## What You Need

| Item | Notes |
|------|-------|
| ESP32 dev board (ESP32, ESP32-S3, or ESP32-C3) | Any board with WiFi. A bare ESP32-DevKitC or similar works. |
| USB data cable | **Must support data transfer** -- charge-only cables will not work. |
| Computer with PlatformIO (VS Code extension) | For building and flashing the firmware. |
| Your home WiFi SSID and password | The bridge must join the same network as your WLED controller. |
| WLED controller already set up | The bridge talks to your existing WLED device (e.g., QuinLED Dig-Octa). |
| Lumina app signed in with a Firebase account | The bridge pairs to your Firebase user ID. |
| A Firebase email/password account for the bridge | Used for the bridge to authenticate with Firestore. |

---

## Part 1 -- Flash the Lumina Bridge Firmware

### Step 1: Install PlatformIO

Install the [PlatformIO IDE extension](https://platformio.org/install/ide?install=vscode) in VS Code if you don't already have it.

### Step 2: Open the firmware project

Open the `lumina-firmware/` directory in VS Code. PlatformIO will detect the `platformio.ini` and set up the build environment automatically.

### Step 3: Connect the ESP32

Plug in the USB data cable. If the board does not appear as a serial port:
- **Windows:** Install the CP2102 or CH340 USB driver. Check Device Manager > Ports (COM & LPT).
- **Mac/Linux:** Run `ls /dev/tty.*` or `ls /dev/ttyUSB*`.

### Step 4: Build and flash

Run the following PlatformIO commands (from the VS Code PlatformIO sidebar or terminal):

```bash
# Build and upload the firmware
pio run -t upload

# Upload the web UI files (setup page, dashboard, logo) to LittleFS
pio run -t uploadfs
```

> **If the flash hangs at "Connecting...":** Hold the **BOOT** button on the ESP32 for 3-5 seconds while the flasher is trying to connect, then release.

### Step 5: Verify the flash

Open the Serial Monitor at **115200 baud**. You should see:

```
╔══════════════════════════════╗
║  Lumina Bridge v1.0.0        ║
╚══════════════════════════════╝

[FS] LittleFS mounted
[CFG] Device: Lumina-XXXX
[CFG] User ID: (not paired)
[CFG] WLED IP: 192.168.50.91:80
[WiFi] Starting AP: Lumina-XXXX
[WiFi] AP IP: 192.168.4.1
[API] HTTP server started on port 80
[Bridge] Firestore bridge module initialized
```

---

## Part 2 -- Configure the Bridge (3-Step Setup Wizard)

The bridge runs a branded captive portal with a 3-step setup wizard. No WLED firmware is involved -- the Lumina Bridge firmware handles everything.

### Step 1: Connect to the bridge's WiFi AP

1. On your phone or computer, look for a WiFi network named **"Lumina-XXXX"** (the last 4 characters are unique to your device).
2. Connect to it (no password required).
3. A captive portal should open automatically. If not, open a browser and navigate to `http://192.168.4.1/setup`.

### Step 2: Connect the bridge to your home WiFi

1. The setup page scans for available networks and displays them.
2. Tap your **home WiFi network** from the list.
3. Enter the **WiFi password** and tap **Connect**.
4. Wait for the connection confirmation. The page will show "Connected! IP: x.x.x.x" and advance to the next step.

> **Important:** The bridge only supports **2.4GHz WiFi**. If your router has separate 2.4GHz and 5GHz networks, select the 2.4GHz one.

### Step 3: Enter bridge credentials

1. Enter the **email** and **password** for the bridge's Firebase account. This is a dedicated account the bridge uses to authenticate with Firestore -- create one in the Firebase Console under Authentication > Users if you haven't already.
2. Tap **Save & Continue**.

### Step 4: Pair with your Lumina user account

1. Enter your **Lumina User ID** (your Firebase UID). You can find this in the Lumina app under System > Account, or in the Firebase Console under Authentication > Users.
2. Enter the **WLED controller's local IP address** (e.g., `192.168.50.91`).
3. Enter the **WLED port** (default: `80`).
4. Tap **Pair & Finish**.

The bridge will reboot and begin polling Firestore for commands.

---

## Part 3 -- Register the Bridge in the Lumina App

### Step 1: Ensure the bridge is on the same network as your WLED controller

Both the bridge and your WLED controller must be on the **same WiFi network / subnet**. Verify by pinging both IPs from your phone or computer.

### Step 2: Configure remote access in the app

1. Open the Lumina app and sign in.
2. Go to **System > Remote Access**.
3. While connected to your home WiFi, tap **Detect Home Network** to save your WiFi SSID.
4. Toggle **Enable Remote Access** on.

### Step 3: Verify the bridge

1. Close and reopen the Lumina app.
2. On startup, the app automatically runs a bridge health check.
3. Check the home screen bridge status indicator:
   - **Green** -- bridge responded, remote access is operational.
   - **Red** -- bridge did not respond. Check that it is powered on and connected to WiFi.

---

## Part 4 -- Pairing Verification Checklist

Run through each of these to confirm end-to-end operation:

- [ ] **Bridge powered on** and connected to home WiFi (check via `http://<bridge-ip>/` for the dashboard)
- [ ] **Bridge dashboard shows all green** -- WiFi connected, Firebase authenticated, user paired
- [ ] **WLED controller reachable** -- open `http://<controller-ip>` (e.g., `http://192.168.50.91`)
- [ ] **Lumina app signed in** -- same Firebase account the bridge is paired to
- [ ] **Home network saved** -- Remote Access status shows your WiFi SSID
- [ ] **Remote access enabled** -- toggle is ON
- [ ] **Bridge health check passes** -- home screen indicator shows bridge alive after app restart
- [ ] **Remote test** -- disconnect from home WiFi (use cellular data), open Lumina, toggle lights. Confirm the command reaches the controller within a few seconds.

---

## Bridge Dashboard

Once the bridge is connected to your home WiFi, you can access its status dashboard at `http://<bridge-ip>/` from any device on the same network. The dashboard shows:

- **WiFi status** -- connected or disconnected
- **Firebase Auth** -- whether the bridge is authenticated
- **User Paired** -- whether a user ID is configured
- **Commands processed** -- total commands relayed to WLED
- **Errors** -- total failed commands
- **WLED Target** -- the IP address of the WLED controller
- **Uptime** -- how long the bridge has been running

From the dashboard you can also:
- **Re-run Setup** -- go back to the setup wizard
- **Reboot Bridge** -- restart the device
- **Factory Reset** -- erase all settings and start over

---

## LED Indicators

| Pattern | Meaning |
|---------|---------|
| LED on briefly during boot | Initializing |
| LED blinks during each poll cycle | Normal operation -- polling Firestore |
| LED stays off between polls | Idle, waiting for next poll |

---

## Quick Reference

| Detail | Value |
|--------|-------|
| Firmware | Lumina Bridge v1.0.0 (custom, PlatformIO) |
| Bridge AP name | `Lumina-XXXX` (unique per device) |
| Setup URL (AP mode) | `http://192.168.4.1/setup` |
| Dashboard URL (connected) | `http://<bridge-ip>/` |
| mDNS | `http://lumina-xxxx.local/` |
| Firebase command path | `/users/{uid}/commands` |
| Bridge health check doc ID | `bridge_health_check` |
| Bridge heartbeat path | `/users/{uid}/bridge_status/current` |
| Bridge health check timeout | 15 seconds |
| Command timeout (remote relay) | 30 seconds |
| Firestore poll interval | 500 ms |
| Heartbeat interval | 30 seconds |
| Lumina app remote access | System tab > Remote Access |
| ESP32 WiFi band | **2.4GHz only** (no 5GHz support) |

---

## Troubleshooting

### Bridge dashboard shows "Not authenticated"

- Verify the bridge email/password are correct. Go to `http://<bridge-ip>/setup` to re-enter them.
- Check that the Firebase account exists in your Firebase Console under Authentication > Users.
- Ensure Firestore security rules allow the bridge user to read/write the commands collection.

### Bridge dashboard shows "Not paired"

- Go to `http://<bridge-ip>/setup` and re-enter your Lumina user ID.
- Verify the user ID matches your Lumina app's logged-in Firebase UID.

### Commands not executing

- Check the bridge dashboard for error counts.
- Verify the WLED controller IP is correct and reachable from the bridge's network.
- Check the Serial Monitor (115200 baud) for detailed error messages.
- Ensure the WLED device is powered on.

### Commands timing out in the app

- The app waits 30 seconds for a response. If the bridge is slow to poll, commands may time out.
- Check that the bridge has a strong WiFi signal.
- Try increasing `WLED_HTTP_TIMEOUT_MS` in `config.h` if the WLED device is slow to respond.

### Bridge not connecting to WiFi

- The bridge only supports 2.4GHz WiFi.
- If credentials are wrong, the bridge falls back to AP mode after 15 seconds. Reconnect to the `Lumina-XXXX` AP and re-enter credentials.
- Check your router's connected devices list to confirm the bridge is online.

### How to factory reset

- Access the dashboard at `http://<bridge-ip>/` and tap **Factory Reset**, or
- Via the Serial Monitor, the bridge logs its AP name on startup -- connect to the AP and re-run setup.

---

For additional troubleshooting, see the Lumina Troubleshooting Guide.
