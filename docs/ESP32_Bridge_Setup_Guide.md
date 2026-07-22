---
title: "Nex-Gen Lumina — Lumina Bridge Setup"
subtitle: "Control your lights from anywhere"
author: "Nex-Gen LED LLC"
date: "April 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#DCF0FF;">Nex-Gen Lumina — Lumina Bridge Setup</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#DCF0FF;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: []
body_class: guide
---

<style>
  body { font-family: 'DM Sans', 'Segoe UI', Arial, sans-serif; color: #DCF0FF; background: #07091A; line-height: 1.6; }
  h1, h2, h3 { font-family: 'Exo 2', 'Segoe UI', Arial, sans-serif; }
  h1 { background: linear-gradient(90deg, #6E2FFF, #00D4FF); -webkit-background-clip: text; background-clip: text; color: transparent; border-bottom: 2px solid #00D4FF; padding-bottom: 8px; }
  h2 { color: #00D4FF; margin-top: 28px; }
  h3 { color: #DCF0FF; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; background: #111527; }
  th, td { border: 1px solid #1F2542; padding: 8px 12px; text-align: left; }
  th { background: #6E2FFF; color: #DCF0FF; }
  .tip { background: rgba(0, 212, 255, 0.12); border-left: 4px solid #00D4FF; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .warning { background: rgba(255, 170, 60, 0.12); border-left: 4px solid #FFAA3C; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .step-box { background: #111527; border: 1px solid #1F2542; border-radius: 8px; padding: 14px; margin: 10px 0; }
  code { background: #1F2542; color: #00D4FF; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
</style>

# Nex-Gen Lumina — Lumina Bridge Setup

The **Lumina Bridge** is a small device that sits on your home Wi-Fi and lets you control your lights from anywhere — the office, a vacation, the driveway. No port forwarding, no tinkering with your router. Once it's set up, remote control just works.

## What you'll need

- Your **Lumina Bridge** (a small plug-in device from Nex-Gen LED LLC)
- A **USB data cable** for the bridge (it needs data transfer, not just charging)
- A computer with an internet connection
- Your **home Wi-Fi name and password**
- Your Lumina controller already installed and working on your home Wi-Fi
- Your Lumina app signed in on your phone

<div class="tip">
<strong>Most Nex-Gen customers have their installer set up the bridge at the end of the installation.</strong> If yours was already configured when you got home, skip to Part 3 — you only need to verify it in the app.
</div>

---

## How remote access works

Lumina is smart about where you are:

- **At home on your Wi-Fi:** the app talks to your lights directly — fast and local. The bridge isn't involved.
- **Away from home (cell data, a hotel, another Wi-Fi):** the app sends commands through the cloud. The bridge — always online at your house — picks them up and passes them to your lights within a couple of seconds.

Every time you open the app, Lumina runs a quick **bridge health check** — a friendly handshake that makes sure the bridge is awake and listening. The check only runs when **Remote Access is enabled** in your settings; if you only use Lumina on your home Wi-Fi, no idle pings are sent. The result shows up as a small status dot on your home screen:

| Indicator | What it means |
|-----------|---------|
| Checking | Health check is in progress |
| Online (green) | Bridge responded — remote control is ready |
| Offline (grey) | Bridge didn't respond — check power and Wi-Fi |

The bridge also phones home every 30 seconds with a short status update, so you always know how long it's been running and how many commands it's processed.

---

## Part 1 — Flash the bridge firmware

If your bridge already has firmware loaded (most do), you can skip to Part 2.

### Step 1: Install PlatformIO

Install the [PlatformIO IDE extension](https://platformio.org/install/ide?install=vscode) in VS Code. It's free, and it handles all the build and flash steps for you.

### Step 2: Open the firmware project

Open the `esp32-bridge/` folder in VS Code. PlatformIO detects it automatically.

### Step 3: Connect the bridge

Plug in the USB cable. If the bridge doesn't show up as a serial port:

- **Windows:** Install the CP2102 or CH340 USB driver. Check Device Manager → Ports (COM & LPT).
- **Mac/Linux:** Run `ls /dev/tty.*` or `ls /dev/ttyUSB*`.

### Step 4: Build and flash

Run these PlatformIO commands from the sidebar or terminal:

```bash
# Build and upload the firmware
pio run -t upload

# Upload the web UI (setup page, dashboard, logo)
pio run -t uploadfs
```

<div class="tip">
<strong>If the flash hangs at "Connecting...":</strong> Hold the <strong>BOOT</strong> button on the bridge for 3–5 seconds while the flasher is trying to connect, then let go.
</div>

### Step 5: Confirm the flash worked

Open the Serial Monitor at **115200 baud**. You should see something like this:

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

That's the bridge booting up and announcing itself. You're ready for Part 2.

---

## Part 2 — Set up the bridge

The bridge runs a friendly setup wizard in a web browser. You connect to the bridge's temporary Wi-Fi, walk through three quick steps, and the bridge takes care of the rest.

### Step 1: Connect to the bridge's Wi-Fi

1. On your phone or computer, look for a Wi-Fi network called **Lumina-XXXX** (the last 4 characters are unique to your bridge).
2. Connect to it — no password required.
3. A setup page should open automatically. If it doesn't, open a browser and go to `http://192.168.4.1/setup`.

### Step 2: Connect the bridge to your home Wi-Fi

1. The setup page scans for available networks and lists them.
2. Tap your **home Wi-Fi** in the list.
3. Enter your Wi-Fi password and tap **Connect**.
4. Wait for the confirmation. You'll see "Connected! IP: x.x.x.x" and the wizard moves to the next step.

<div class="warning">
<strong>Heads-up:</strong> The bridge only supports <strong>2.4 GHz Wi-Fi</strong>. If your router has separate 2.4 GHz and 5 GHz networks, pick the 2.4 GHz one. Most routers show them as two separate network names.
</div>

### Step 3: Enter the bridge credentials

1. Enter the **email** and **password** for the bridge's cloud account. (Your installer will have provided these, or you'll create them in your Nex-Gen cloud console under Authentication → Users.)
2. Tap **Save & Continue**.

### Step 4: Pair with your Lumina account

1. Enter your **Lumina user ID** — find this in the Lumina app under **System → Account**.
2. Enter your controller's local IP address (e.g., `192.168.50.91`).
3. Enter the controller port (default: `80`).
4. Tap **Pair & Finish**.

The bridge reboots and starts listening for commands from the cloud.

---

## Part 3 — Turn on remote access in the app

### Step 1: Make sure the bridge and your controller are on the same network

They need to be on the same Wi-Fi network. If you can open both in a browser from a computer on your home Wi-Fi, you're good.

### Step 2: Enable remote access

1. Open the Lumina app and sign in
2. Tap **System** (gear icon) → **Remote Access**
3. While connected to your home Wi-Fi, tap **Detect Home Network** to save your Wi-Fi name
   - The first time you tap this, the app asks for **Location permission**. Required on Android (Android gates Wi-Fi network names behind location), recommended on iOS. If you decline, the app will tell you what's needed instead of failing silently.
   - Your network name is encrypted before it's saved — it never sits in plain text on the server.
4. Toggle **Enable Remote Access** on

### Step 3: Verify it works

1. Close and reopen the Lumina app
2. The app automatically runs a bridge health check on startup
3. Check the bridge status dot on the home screen:
   - **Green** → bridge is online, remote access is ready
   - **Grey** → bridge didn't respond; check that it has power and is on your Wi-Fi

---

## Part 4 — End-to-end check

Run through this list to confirm everything is really working:

- [ ] **Bridge is powered on** and connected to home Wi-Fi (open `http://<bridge-ip>/` for its dashboard)
- [ ] **Bridge dashboard is all green** — Wi-Fi connected, cloud authenticated, user paired
- [ ] **Your controller is reachable** — open `http://<controller-ip>` in a browser
- [ ] **Lumina is signed in** to the same account the bridge is paired to
- [ ] **Home network saved** — Remote Access shows your Wi-Fi name
- [ ] **Remote access toggle is on**
- [ ] **Bridge status is green** on the home screen after an app restart
- [ ] **The real test:** turn off your home Wi-Fi on your phone (use cell data), open Lumina, toggle the lights. The command should reach the controller within a few seconds. If it does, you're fully set up.

---

## The bridge dashboard

Any time you want to check on the bridge, open `http://<bridge-ip>/` from a browser on your home Wi-Fi. The dashboard shows:

- **Wi-Fi status** — connected or disconnected
- **Authentication** — whether the bridge is logged into the cloud
- **User paired** — whether your Lumina account is connected
- **Commands processed** — total commands the bridge has relayed
- **Errors** — total failed commands
- **Controller target** — the IP of your controller
- **Uptime** — how long the bridge has been running

From the dashboard you can also:

- **Re-run Setup** — go back to the wizard
- **Reboot Bridge** — restart the device
- **Factory Reset** — erase all settings and start fresh

---

## Bridge LED indicators

| Pattern | What it means |
|---------|---------|
| LED on briefly at boot | Starting up |
| LED blinks each poll cycle | Normal — checking for new commands |
| LED off between polls | Idle, waiting for the next poll |

---

## Quick reference

| Detail | Value |
|--------|-------|
| Firmware | Lumina Bridge v1.0.0 |
| Bridge Wi-Fi name | `Lumina-XXXX` (unique per device) |
| Setup URL (while connected to the bridge's Wi-Fi) | `http://192.168.4.1/setup` |
| Dashboard URL (on your home network) | `http://<bridge-ip>/` |
| Short-name URL | `http://lumina-xxxx.local/` |
| Health check timeout | 15 seconds |
| Remote command timeout | 30 seconds |
| Supported Wi-Fi | **2.4 GHz only** (no 5 GHz) |
| Remote access in the app | **System → Remote Access** |

---

## What success looks like

- The bridge dashboard at `http://<bridge-ip>/` shows green for Wi-Fi, authentication, and user paired
- Your Lumina home screen shows a green bridge status indicator after an app restart
- When you turn off home Wi-Fi on your phone and use cell data, the app still controls your lights within a couple of seconds
- The **Commands processed** counter on the bridge dashboard ticks up each time you change something from away

## If something isn't working

**"The bridge dashboard shows 'Not authenticated'."**
The bridge credentials are wrong or the account doesn't exist. Open `http://<bridge-ip>/setup` and re-enter the email and password. If you just created the account, confirm it exists in your Nex-Gen cloud console.

**"The bridge dashboard shows 'Not paired'."**
Your Lumina user ID isn't entered. Open `http://<bridge-ip>/setup` and re-enter it. Make sure the user ID matches the one in your Lumina app under **System → Account**.

**"Commands aren't making it to my lights."**
- Check the error counter on the bridge dashboard — rising errors mean the bridge can't reach your controller.
- Confirm your controller's IP is correct and the controller itself is powered on.
- Make sure the bridge and the controller are on the same Wi-Fi network.
- If you're comfortable, open the serial monitor (115200 baud) for detailed messages.

**"My commands time out from the app."**
- The app waits 30 seconds for a response. If the bridge has weak Wi-Fi, move it closer to your router.
- Make sure the bridge is connected to 2.4 GHz Wi-Fi, not 5 GHz.

**"The bridge won't connect to my Wi-Fi."**
- The bridge only supports 2.4 GHz. Select the 2.4 GHz network name on your router.
- If the password was wrong, the bridge falls back to its setup Wi-Fi after about 15 seconds. Reconnect to the `Lumina-XXXX` network and re-enter credentials.
- Check your router's connected devices list — if the bridge is there but Lumina says it's offline, power-cycle the bridge and wait 30 seconds.

**"I need to start over from scratch."**
Open `http://<bridge-ip>/` and tap **Factory Reset**. The bridge erases all settings and boots back into its setup Wi-Fi, ready for a fresh walkthrough.

Still stuck? Contact Nex-Gen LED LLC support — include your bridge's Wi-Fi name (`Lumina-XXXX`) and a quick description of what the dashboard shows.

---

*Nex-Gen Lumina v2.2 — Lumina Bridge Setup — April 2026*
