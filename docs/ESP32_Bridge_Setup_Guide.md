---
title: "Nex-Gen Lumina — Lumina Bridge Setup"
subtitle: "Control your lights from anywhere — app 2.5.10+89"
author: "Nex-Gen LED LLC"
date: "August 2026"
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

<div class="warning">
<strong>SUPERSEDED 2026-09-17.</strong> This guide is replaced by <code>docs/guides-2026-09/07-bridge-setup-guide.md</code>, which is verified against shipping code at 2.5.10+98. It is kept for reference because its rendered PDF is still in circulation. Inline <em>Corrected 2026-09-17</em> notices mark the passages that were factually wrong; everything else is accurate but may be less current.
</div>


**Describes Lumina app version 2.5.10+89 and bridge firmware v1.2.**

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

<div class="warning">
<strong>What the bridge does and doesn't carry.</strong> Remote commands cover the things you'd reach for while away — power, brightness, colors, patterns, and scenes. <strong>Schedule (timer) configuration is a local-network write only.</strong> Creating or editing a schedule while you're away saves it to your account, but it does not arm on the controller until the app is back on your home Wi-Fi. Open the Schedule tab once when you get home and it syncs itself.
</div>

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

# (No web UI to upload — firmware v1.2 serves JSON endpoints only)
pio run -t uploadfs
```

<div class="tip">
<strong>If the flash hangs at "Connecting...":</strong> Hold the <strong>BOOT</strong> button on the bridge for 3–5 seconds while the flasher is trying to connect, then let go.
</div>

### Step 5: Confirm the flash worked

Open the Serial Monitor at **115200 baud**. You should see something like this:

```
╔══════════════════════════════╗
║  Lumina Bridge v1.2          ║
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

There are two ways to pair. **The in-app flow is easier and is what we recommend.**

#### Option A — Pair from the app (recommended)

1. In Lumina, go to **System → System Management → Remote Access → Set Up Bridge**.
2. Tap **Find Your Bridge**. Powered-on bridges on your network appear in the list within a minute or so, showing **Ready to pair**.
3. Tap your bridge, then confirm the pair. The app writes your account to the bridge for you — no user ID to copy by hand.
4. If discovery doesn't find it, open **Advanced → Enter Bridge IP** and type the bridge's IP directly.

<div class="warning">
<strong>If you see "Bridge already paired":</strong> this bridge is paired to a different Nex-Gen account. Only continue with <strong>Transfer to my account</strong> if you are the authorized installer for this property — otherwise contact Nex-Gen support to transfer ownership.

<p><strong>Why this appears even after an account was deleted:</strong> the bridge stores its pairing in its own onboard memory, not on the server, and it re-asserts that pairing every 30 seconds. Releasing a bridge from the server side does not free a bridge that is still powered on and online — it will simply overwrite the release on its next check-in. See <em>Releasing a bridge</em> below.</p>
</div>

<div class="tip">
<strong>"This bridge firmware is outdated. Please reflash…"</strong> means the bridge predates the in-app pairing handshake. Reflash it (Part 1), or use Option B.
</div>

#### Option B — Pair from the bridge's web page

1. Enter your **Lumina user ID**. Find it in the app under **System → System Management → Remote Access** — it's shown as **Your User ID**, with a **Copy User ID** button.
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

- [ ] **Bridge is powered on** and connected to home Wi-Fi (check your router's device list)
- [ ] **App reports the bridge paired** — System → System & Device Management → Remote Access, then **Test Bridge**
- [ ] **Your controller is reachable** — open `http://<controller-ip>` in a browser
- [ ] **Lumina is signed in** to the same account the bridge is paired to
- [ ] **Home network saved** — Remote Access shows your Wi-Fi name
- [ ] **Remote access toggle is on**
- [ ] **Bridge status is green** on the home screen after an app restart
- [ ] **The real test:** turn off your home Wi-Fi on your phone (use cell data), open Lumina, toggle the lights. The command should reach the controller within a few seconds. If it does, you're fully set up.

---

## Checking on the bridge

<div class="warning">
<strong>Corrected 2026-09-17 — there is no bridge web dashboard.</strong> Earlier revisions of this guide described a status page at <code>http://&lt;bridge-ip&gt;/</code> with Re-run Setup, Reboot and Factory Reset buttons. Firmware v1.2 serves six JSON API endpoints and returns <code>404</code> for everything else — it has never served a web page, and there are no web assets in the firmware image. Verified against <code>esp32-bridge/src/main.cpp</code> (no <code>serveStatic</code>, no filesystem serving, <code>handleNotFound</code> returns JSON).
</div>

Check on the bridge from the app instead: **System → System & Device Management → Remote Access**.
That screen shows whether the bridge is paired, which controller it targets, and a **Test Bridge**
button that runs a real round trip through the cloud and back.

The dashboard's **Direct / Via Bridge** badge tells you which path your last command took — tap it
for recent commands and the network decision behind each one.

---

## Releasing a bridge — moving it to a different account

This is the step most people get wrong, so it is worth reading before you try it.

**The bridge remembers its own pairing.** Your account ID is written into the bridge's onboard memory during setup, and the bridge re-publishes that pairing to the cloud **every 30 seconds** while it is powered on. The cloud record is a copy; the bridge is the original.

That has one consequence that surprises people:

<div class="warning">
<strong>Clearing the pairing on the server does not free a live bridge.</strong> If the bridge is plugged in and on Wi-Fi, it overwrites the release within 30 seconds and goes straight back to showing <em>paired</em> — to the old account. Deleting the old owner's Nex-Gen account does not free it either. Nothing you do from the app or the cloud will release a bridge that is still running.
</div>

### The reliable way to release a bridge

A factory reset is what actually frees a bridge. It erases the stored pairing, reboots, and the
bridge comes back up unpaired — broadcasting its `Lumina-XXXX` setup Wi-Fi again. Re-pair it to the
new account using Part 2, Step 4.

<div class="warning">
<strong>A factory reset currently requires installer assistance.</strong> There is no reset control in the app and no web dashboard on the bridge. Contact your dealer or email <strong>support@Nex-GenLED.com</strong>.
</div>

<div class="note">
<strong>Installers.</strong> The firmware accepts a factory reset as <code>POST http://&lt;bridge-ip&gt;/api/reset</code> from any client on the same Wi-Fi — it clears NVS and restarts. Reflashing over USB also clears it. Before build 98 the app's own reset call targeted <code>/api/bridge/reset</code>, which the firmware does not serve, so it silently 404'd; that call is corrected in the app as of this release, but note it is not yet surfaced as a button anywhere.
</div>

Unplugging the bridge is not a substitute — it only stops the re-assertion while it is off. The
moment it is plugged back in on the old network it re-claims the old account.

<div class="tip">
<strong>If the bridge is already gone</strong> — unplugged for good, discarded, or at a house you no longer service — a server-side release <em>does</em> stick, because there is nothing left to overwrite it. The problem is only ever a bridge that is still running.
</div>

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
| Firmware | Lumina Bridge v1.2 |
| Bridge Wi-Fi name | `Lumina-XXXX` (unique per device) |
| Setup URL (while connected to the bridge's Wi-Fi) | `http://192.168.4.1/setup` |
| Status / testing | In the app: System → System & Device Management → Remote Access |
| Short-name URL | `http://lumina-xxxx.local/` |
| Health check timeout | 15 seconds |
| Remote command timeout | 30 seconds |
| Supported Wi-Fi | **2.4 GHz only** (no 5 GHz) |
| Remote access in the app | **System → Remote Access** |

---

## What success looks like

- The app's Remote Access screen shows the bridge paired, and **Test Bridge** succeeds
- Your Lumina home screen shows a green bridge status indicator after an app restart
- When you turn off home Wi-Fi on your phone and use cell data, the app still controls your lights within a couple of seconds
- The dashboard badge reads **Via Bridge** when you change something from away

## If something isn't working

**"The bridge never authenticates to the cloud."**
Its credentials are compiled into the firmware, so this is a firmware/account issue rather than something you can re-enter. Contact your dealer.

**"The app says the bridge isn't paired."**
Re-run **Set Up Bridge** from System → System & Device Management → Remote Access. Pairing is driven from the app, not from the bridge.

**"Commands aren't making it to my lights."**
- Run **Test Bridge** in the app — a failure there means the bridge can't reach your controller.
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
A factory reset erases all settings and boots the bridge back into its setup Wi-Fi. It needs installer assistance — see *Releasing a bridge*. It is also the only reliable way to move a bridge to a different account.

Still stuck? Contact Nex-Gen LED LLC support — include your bridge's Wi-Fi name (`Lumina-XXXX`) and what the app's Remote Access screen reports.

---

*Nex-Gen Lumina — Lumina Bridge Setup — August 2026 — describes app version 2.5.10+89, bridge firmware v1.2*
