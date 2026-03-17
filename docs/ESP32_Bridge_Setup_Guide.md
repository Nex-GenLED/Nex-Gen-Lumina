# Nex-Gen Lumina — ESP32 Bridge Setup Guide

> **Purpose:** Enable remote control of your WLED lighting system from anywhere, without port forwarding.
> The ESP32 Bridge sits on your home WiFi and relays commands from Firebase to your WLED controller(s).

---

## What You Need

| Item | Notes |
|------|-------|
| ESP32 dev board (ESP32, ESP32-S3, or ESP32-C3) | Any board with WiFi. A bare ESP32-DevKitC or similar works. |
| USB data cable | **Must support data transfer** — charge-only cables won't work. |
| Computer with Chrome or Edge | For the WLED web flasher. |
| Your home WiFi SSID & password | The bridge must join the same network as your WLED controller. |
| WLED controller already set up | The bridge talks *to* your existing WLED device (e.g., QuinLED Dig-Octa). |
| Lumina app signed in with a Firebase account | Bridge pairs to your Firebase user ID. |

---

## Part 1 — Flash WLED Firmware onto the Bridge ESP32

> If your bridge ESP32 already has WLED firmware, skip to Part 2.

### Step 1: Connect the ESP32 to your computer
- Plug in the USB data cable. If it's a new board, you may need a **CP2102** or **CH340** USB driver — install the appropriate one for your OS if the board doesn't appear as a COM/serial port.
- **Windows:** Check Device Manager → Ports (COM & LPT) for the COM port number.
- **Mac/Linux:** Run `ls /dev/tty.*` or `ls /dev/ttyUSB*`.

### Step 2: Open the WLED Web Installer
- Navigate to **https://install.wled.me** in Chrome or Edge (must be a Chromium-based browser for Web Serial).
- If that site is down, use the mirror: **https://wled-install.github.io**

### Step 3: Select firmware & board
- Choose the **latest stable WLED version** (0.14.x+ recommended).
- Select **ESP32** as the board type.

### Step 4: Flash the firmware
1. Click **Install**.
2. A browser dialog will list available serial ports — select your ESP32's COM port and click **Connect**.
3. Check **"Erase device"** (recommended for a clean install).
4. Click **Next**, verify the firmware version, then click **Install**.
5. Wait for the flash to complete (1–2 minutes). The progress bar will reach 100%.

> **If the flash hangs at "Connecting...":** Hold the **BOOT** button on the ESP32 for 3–5 seconds while the flasher is trying to connect, then release.

### Step 5: Configure WiFi on the freshly flashed ESP32
- After flashing, the installer will prompt you to enter your **WiFi SSID** and **password**. Enter your home network credentials.
- Alternatively, the ESP32 will create a hotspot called **"WLED-AP"** (password: `wled1234`). Connect to it, open `http://4.3.2.1`, go to **Config → WiFi Setup**, enter your home network credentials, and save.
- The ESP32 will reboot and join your home network.

### Step 6: Find the bridge's IP address
- Check your router's connected devices list, or
- Use the Lumina app's device discovery (it scans for `_wled._tcp` mDNS), or
- Open `http://wled.local` in a browser on the same network.
- **Write down the IP** — you'll need it to confirm the bridge is online. Example: `192.168.50.62`

### Step 7: Verify WLED is running
- Open `http://<bridge-ip>/json/info` in a browser. You should get a JSON response with firmware version, build info, etc.
- If this works, the ESP32 hardware is ready.

---

## Part 2 — Configure the Bridge for Firebase Command Relay

> The bridge ESP32 needs custom firmware (or a WLED usermod) that polls your Firebase `/users/{uid}/commands` collection and forwards commands to your WLED controller. This section covers the configuration after the bridge firmware is loaded.

### Step 1: Ensure the bridge is on the same network as your WLED controller
- Both the bridge ESP32 and your WLED lighting controller must be on the **same WiFi network / subnet**.
- Verify by pinging both IPs from your phone or computer.

### Step 2: Register the bridge in the Lumina app
1. Open the Lumina app and sign in.
2. Go to **System → Remote Access** (found in the bottom nav → System tab).
3. The app defaults to **"ESP32 Bridge"** mode — confirm this is selected under **Connection Mode**.

### Step 3: Save your home network
1. While connected to your home WiFi, tap **"Detect Home Network"** in the Remote Access screen.
2. The app will save your WiFi SSID (e.g., `MyHomeNetwork`). This tells the app when you're home (use local) vs. away (use bridge relay).

### Step 4: Enable remote access
- Toggle **"Enable Remote Access"** to ON.

### Step 5: Test the bridge connection
1. Tap **"Test Bridge"** in the app.
2. The app writes a test command (`getInfo`) to Firebase under `/users/{uid}/commands` with status `pending`.
3. The bridge has **10 seconds** to pick up the command, execute it against the WLED controller, and update the status to `completed`.
4. If successful, you'll see **"Bridge Connected"** with a green checkmark.

---

## Part 3 — Pairing Verification Checklist

Run through each of these to confirm end-to-end operation:

- [ ] **Bridge ESP32 powered on** and connected to home WiFi (solid LED or WLED interface accessible via browser)
- [ ] **Bridge IP reachable** — open `http://<bridge-ip>` from your phone on the same network
- [ ] **WLED controller reachable** — open `http://<controller-ip>` (e.g., `http://192.168.50.91`)
- [ ] **Lumina app signed in** — same Firebase account the bridge is registered under
- [ ] **Home network saved** — Remote Access screen shows your WiFi SSID
- [ ] **Remote access enabled** — toggle is ON
- [ ] **Bridge test passes** — "Test Bridge" shows green "Bridge Connected"
- [ ] **Remote test** — disconnect from home WiFi (use cellular data), open Lumina, toggle lights. Confirm the command reaches the controller.

---

## Troubleshooting

### Flashing Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Flasher stuck on "Connecting..." | ESP32 not in bootloader mode | Hold **BOOT** button for 3–5 sec during flash, then release |
| COM port not showing in browser | Missing USB driver or charge-only cable | Install CP2102/CH340 driver; try a different USB cable that supports data |
| Flash fails partway through | Loose USB connection or insufficient power | Use a shorter cable; plug directly into computer (not a hub); try a different USB port |
| "Port is already in use" | Another program (Arduino IDE, serial monitor) has the port open | Close all serial monitor programs and retry |

### WiFi / Network Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| ESP32 creates "WLED-AP" hotspot but won't join home WiFi | Wrong SSID/password, or 5GHz-only network | Double-check credentials; ensure your router broadcasts a **2.4GHz** SSID (ESP32 does not support 5GHz) |
| Bridge IP keeps changing | DHCP lease expires | Assign a **static IP** or DHCP reservation in your router for the bridge's MAC address |
| Bridge and controller on different subnets | Dual-band router with AP isolation | Ensure both devices are on the same VLAN/subnet; disable AP isolation if enabled |
| `http://wled.local` doesn't resolve | mDNS not supported on your network/OS | Use the IP address directly; check router's connected device list |

### Bridge Health Check Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| **"No response from ESP32 Bridge within 10 seconds"** | Bridge is offline, not polling Firebase, or Firebase credentials are wrong | 1) Confirm bridge is powered on and WiFi-connected. 2) Check bridge serial logs for Firebase auth errors. 3) Reboot the bridge. |
| **"Bridge reached controller but got an error"** | Bridge is online but can't talk to the WLED controller | Verify WLED controller IP hasn't changed; confirm both are on the same subnet; check that the WLED controller is powered on. |
| **"Not signed in"** | App not authenticated | Sign in to the Lumina app before testing. |
| Test passes locally but **fails on cellular** | Home network detection issue | Re-save your home network via "Detect Home Network" so the app correctly switches to remote mode when off-WiFi. |
| Bridge was working but **stopped responding** | Power loss, WiFi dropout, or IP change | Check bridge power supply; assign a static IP; consider a watchdog timer or auto-reboot schedule on the ESP32. |

### General Watch-Outs

- **GPIO Pin Selection:** If you're using the bridge ESP32 for *any* LED output as well, avoid GPIO 0, 3, and 12 on ESP32 — these are strapping pins and are unreliable for RGBW LED data.
- **Power Supply:** A bridge-only ESP32 draws minimal power (~150mA), but if you're also driving LEDs from it, ensure adequate 5V power.
- **Firestore Rules:** The bridge needs read/write access to `/users/{uid}/commands`. Ensure your Firestore security rules allow authenticated access to this path.
- **Polling Interval:** The bridge polls Firestore every few seconds. There will be a 2–5 second delay between tapping a button in the app and the lights responding. This is normal for bridge mode.
- **Firebase Quotas:** Each poll counts as a Firestore read. At a 3-second poll interval, that's ~28,800 reads/day. Stay within your Firebase plan limits (Spark free tier: 50K reads/day).
- **Health Check Polling:** The Lumina app's Remote Access screen automatically re-checks bridge status every 30 seconds while the screen is open. No need to spam "Test Bridge."
- **Multiple Controllers:** The bridge forwards commands to whichever controller IP is set as the active device in the app. If you have multiple WLED controllers, ensure the correct one is selected before sending remote commands.

---

## Quick Reference

| Detail | Value |
|--------|-------|
| WLED Web Flasher | https://install.wled.me |
| WLED-AP default password | `wled1234` |
| WLED-AP config URL | `http://4.3.2.1` |
| WLED mDNS service | `_wled._tcp` |
| Firebase command path | `/users/{uid}/commands` |
| Bridge test timeout | 10 seconds |
| App health check interval | 30 seconds |
| Lumina app remote access | System tab → Remote Access |
| ESP32 WiFi band | **2.4GHz only** (no 5GHz support) |
