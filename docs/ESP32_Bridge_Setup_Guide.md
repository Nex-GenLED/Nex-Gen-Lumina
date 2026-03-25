# Nex-Gen Lumina v2.1 -- ESP32 Bridge Setup Guide

> **Purpose:** Enable remote control of your WLED lighting system from anywhere, without port forwarding.
> The ESP32 Bridge sits on your home WiFi and relays commands from Firebase to your WLED controller(s).

---

## How Remote Access Works in Lumina v2.1

Lumina automatically detects whether you are on your home WiFi or away:

- **On home WiFi:** The app communicates directly with your WLED controller over HTTP (`WledService`). The bridge is not involved.
- **Away from home (cellular or another WiFi):** The app writes commands to your Firebase `/users/{uid}/commands` collection. The ESP32 Bridge, which is always connected to your home network, picks up those commands and forwards them to the WLED controller.

On every app startup, Lumina runs a **bridge health check**. It writes a ping document to `/users/{uid}/commands/bridge_health_check` and watches for up to **15 seconds** for the bridge to acknowledge it. The result is exposed via `bridgeHealthProvider` as one of three states:

| State | Meaning |
|-------|---------|
| `BridgeHealth.checking` | Health check is in progress. |
| `BridgeHealth.alive` | Bridge acknowledged the ping within 15 seconds. |
| `BridgeHealth.unreachable` | Bridge did not respond in time. |

The home screen displays a bridge status indicator reflecting this result.

---

## What You Need

| Item | Notes |
|------|-------|
| ESP32 dev board (ESP32, ESP32-S3, or ESP32-C3) | Any board with WiFi. A bare ESP32-DevKitC or similar works. |
| USB data cable | **Must support data transfer** -- charge-only cables will not work. |
| Computer with Chrome or Edge | For the WLED web flasher. |
| Your home WiFi SSID and password | The bridge must join the same network as your WLED controller. |
| WLED controller already set up | The bridge talks to your existing WLED device (e.g., QuinLED Dig-Octa). |
| Lumina app signed in with a Firebase account | The bridge pairs to your Firebase user ID. |

---

## Part 1 -- Flash WLED Firmware onto the Bridge ESP32

> If your bridge ESP32 already has WLED firmware, skip to Part 2.

### Step 1: Connect the ESP32 to your computer
- Plug in the USB data cable. If it is a new board, you may need a **CP2102** or **CH340** USB driver -- install the appropriate one for your OS if the board does not appear as a COM/serial port.
- **Windows:** Check Device Manager > Ports (COM & LPT) for the COM port number.
- **Mac/Linux:** Run `ls /dev/tty.*` or `ls /dev/ttyUSB*`.

### Step 2: Open the WLED Web Installer
- Navigate to **https://install.wled.me** in Chrome or Edge (must be a Chromium-based browser for Web Serial).
- If that site is down, use the mirror: **https://wled-install.github.io**

### Step 3: Select firmware and board
- Choose the **latest stable WLED version** (0.14.x+ recommended).
- Select **ESP32** as the board type.

### Step 4: Flash the firmware
1. Click **Install**.
2. A browser dialog will list available serial ports -- select your ESP32's COM port and click **Connect**.
3. Check **"Erase device"** (recommended for a clean install).
4. Click **Next**, verify the firmware version, then click **Install**.
5. Wait for the flash to complete (1-2 minutes). The progress bar will reach 100%.

> **If the flash hangs at "Connecting...":** Hold the **BOOT** button on the ESP32 for 3-5 seconds while the flasher is trying to connect, then release.

### Step 5: Configure WiFi on the freshly flashed ESP32
- After flashing, the installer will prompt you to enter your **WiFi SSID** and **password**. Enter your home network credentials.
- Alternatively, the ESP32 will create a hotspot called **"WLED-AP"** (password: `wled1234`). Connect to it, open `http://4.3.2.1`, go to **Config > WiFi Setup**, enter your home network credentials, and save.
- The ESP32 will reboot and join your home network.

### Step 6: Find the bridge's IP address
- Check your router's connected devices list, or
- Use the Lumina app's device discovery (it scans for `_wled._tcp` mDNS), or
- Open `http://wled.local` in a browser on the same network.
- **Write down the IP** -- you will need it to confirm the bridge is online. Example: `192.168.50.62`

### Step 7: Verify WLED is running
- Open `http://<bridge-ip>/json/info` in a browser. You should get a JSON response with firmware version, build info, etc.
- If this works, the ESP32 hardware is ready.

---

## Part 2 -- Configure the Bridge for Firebase Command Relay

> The bridge ESP32 needs custom firmware (or a WLED usermod) that polls your Firebase `/users/{uid}/commands` collection and forwards commands to your WLED controller. This section covers the configuration after the bridge firmware is loaded.

### Step 1: Ensure the bridge is on the same network as your WLED controller
- Both the bridge ESP32 and your WLED lighting controller must be on the **same WiFi network / subnet**.
- Verify by pinging both IPs from your phone or computer.

### Step 2: Register the bridge in the Lumina app
1. Open the Lumina app and sign in.
2. Go to **System > Remote Access**. In v2.1 this screen shows a status banner at the top reflecting the current bridge health, configuration chips for key settings, and a single settings button for advanced options.

### Step 3: Save your home network
1. While connected to your home WiFi, use the **home network** configuration chip to detect and save your WiFi SSID. This tells the app when you are home (use direct HTTP) vs. away (use bridge relay).

### Step 4: Enable remote access
- Enable remote access using the toggle in the Remote Access settings.

### Step 5: Verify the bridge on next app launch
1. Close and reopen the Lumina app.
2. On startup, the app automatically runs a bridge health check -- it writes a ping document to `/users/{uid}/commands/bridge_health_check` and watches for up to **15 seconds**.
3. Check the home screen bridge status indicator:
   - **Alive** -- the bridge responded and remote access is operational.
   - **Unreachable** -- the bridge did not respond. Confirm it is powered on and connected to WiFi.

---

## Part 3 -- Pairing Verification Checklist

Run through each of these to confirm end-to-end operation:

- [ ] **Bridge ESP32 powered on** and connected to home WiFi (solid LED or WLED interface accessible via browser)
- [ ] **Bridge IP reachable** -- open `http://<bridge-ip>` from your phone on the same network
- [ ] **WLED controller reachable** -- open `http://<controller-ip>` (e.g., `http://192.168.50.91`)
- [ ] **Lumina app signed in** -- same Firebase account the bridge is registered under
- [ ] **Home network saved** -- Remote Access status banner shows your WiFi SSID
- [ ] **Remote access enabled** -- toggle is ON
- [ ] **Bridge health check passes** -- home screen indicator shows bridge alive after app restart
- [ ] **Remote test** -- disconnect from home WiFi (use cellular data), open Lumina, toggle lights. Confirm the command reaches the controller within a few seconds.

---

## Quick Reference

| Detail | Value |
|--------|-------|
| WLED Web Flasher | https://install.wled.me |
| WLED-AP default password | `wled1234` |
| WLED-AP config URL | `http://4.3.2.1` |
| WLED mDNS service | `_wled._tcp` |
| Firebase command path | `/users/{uid}/commands` |
| Bridge health check doc ID | `bridge_health_check` |
| Bridge health check timeout | 15 seconds |
| Command timeout (remote relay) | 30 seconds |
| Lumina app remote access | System tab > Remote Access |
| ESP32 WiFi band | **2.4GHz only** (no 5GHz support) |

---

For troubleshooting, see the separate Lumina Troubleshooting Guide.
