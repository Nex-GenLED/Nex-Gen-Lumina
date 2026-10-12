---
pdf_options:
  format: Letter
  margin:
    top: 12mm
    right: 12mm
    bottom: 12mm
    left: 20mm
  printBackground: false
  displayHeaderFooter: true
  headerTemplate: '<div></div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#333333;">Nex-Gen LED · Install-day sheet · page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet:
  - _print_write.css
body_class: form
---

<img class="mark" src="nexgen_mark.png" alt="Nex-Gen LED">
<p class="brandline">Nex-Gen LED · Lumina</p>

# Install-day sheet

<p class="meta">Work down the sheet in order on install day (Day 2). Describes build: 2.5.10+116 · Last verified: 2026-10-12 · Keep in the dealer's file. No password, PIN or key is written on this sheet.</p>

<table>
<tr><th style="width:22%">Customer name</th><td class="w"></td><th style="width:18%">Job number</th><td class="w"></td></tr>
<tr><th>Install address</th><td class="w" colspan="3"></td></tr>
<tr><th>Installer</th><td class="w"></td><th>Date</th><td class="w"></td></tr>
</table>

<div class="callout"><strong>Not our work.</strong> Nex-Gen LED and its dealers do the low-voltage wiring and the pre-install. We do no electrical work. Where a job involves line-voltage power (power to the power-supply location, a new outlet, a circuit, a breaker, hardwiring), Nex-Gen LED does not perform that work; the customer arranges it through a licensed professional of their own choosing. If it is not in place, do not improvise: stop and reschedule.</div>

## A. Before you leave the shop

<p><span class="cb"></span>The site and controller record (P3) and the pre-install bench sheet (P1) for this job.</p>
<p><span class="cb"></span>Day 1 pre-install done: low-voltage wiring run for every run back to the controller location, wire ends labelled by run.</p>
<p><span class="cb"></span>Deposit marked collected on the job's card in the <strong>Day 1 Queue</strong>.</p>
<p><span class="cb"></span>Your installer PIN (dealer code plus installer code). &nbsp; <span class="cb"></span>Phone with Lumina signed in, Bluetooth and location on.</p>
<p><span class="cb"></span>Customer's Wi-Fi name confirmed (2.4 GHz); password recorded privately, not on this sheet.</p>
<p><span class="cb"></span>Controller and bridge bench-prepared and labelled.</p>

## B. At the controller

<p><span class="cb"></span>1. Controller mounted; low-voltage wiring and lights connected; powered up from its supply; waited about a minute.</p>
<p><span class="cb"></span>2. Firmware version read (controller card in the installer wizard, or <code>http://4.3.2.1/json/info</code> on its setup network). Never flash, update or downgrade.</p>
<div class="row top"><span class="lbl"><code>ver</code></span><span class="box"></span><span class="lbl"><code>release</code></span><span class="box wide"></span></div>
<p><span class="cb"></span>3. On the customer's Wi-Fi (if not: joined the setup network named on the label, opened <code>http://4.3.2.1</code>, entered the Wi-Fi name and password, saved; controller restarted and joined).</p>
<div class="row"><span class="lbl">Controller's address on the home network:</span><span class="fill"></span></div>
<p><span class="cb"></span>4. Unique AP password set on this controller and recorded privately in the dealer's record (never in a document, a message, a photo or the repo).</p>
<p><span class="cb"></span>5. "Access Point opens" option set to a "when there is no connection" choice, never "never".</p>
<div class="row"><span class="lbl">Option labels the page offered:</span><span class="fill"></span></div>
<div class="row"><span class="lbl">Choice made:</span><span class="fill"></span></div>
<p><span class="cb"></span>6. Controller confirmed still answering on the home network afterwards (<strong>Test Lights</strong> on its card, or its page reloaded at the home-network address).</p>
<p><span class="cb"></span>7. Each run mapped to one of the four outputs (output 1 = GPIO 2, 2 = GPIO 14, 3 = GPIO 16, 4 = GPIO 18). Never more than four.</p>

<table>
<tr><th class="n">Output</th><th style="width:14%">GPIO</th><th>Run name</th><th style="width:18%">Light count</th><th style="width:22%">Walked with the lit pixel</th></tr>
<tr><td class="w">1</td><td class="w">2</td><td class="w"></td><td class="w"></td><td class="w"></td></tr>
<tr><td class="w">2</td><td class="w">14</td><td class="w"></td><td class="w"></td><td class="w"></td></tr>
<tr><td class="w">3</td><td class="w">16</td><td class="w"></td><td class="w"></td><td class="w"></td></tr>
<tr><td class="w">4</td><td class="w">18</td><td class="w"></td><td class="w"></td><td class="w"></td></tr>
</table>

<p>If the controller stays on its setup network: wrong Wi-Fi name or password, a 5 GHz-only network, or a hidden name. Fix the network and repeat step 3.</p>

## C. In the app: Installer Mode

<p><span class="cb"></span>Signed in to <strong>Staff Access</strong> (logo tapped five times within three seconds, or <strong>Installer</strong> under <strong>Nex-Gen Professional Access</strong>); PIN entered.</p>
<p><span class="cb"></span><strong>New Install</strong>: customer information (the address drives sunrise and sunset).</p>
<p><span class="cb"></span>Controller setup: <strong>Add Controller</strong> → <strong>BLE Scan (New Device)</strong> or <strong>Enter IP Address</strong>; <strong>Test Lights</strong> flashed the house white for three seconds.</p>
<p><span class="cb"></span>Connection method: Ethernet when a wall jack is available, otherwise Wi-Fi; never both.</p>
<p><span class="cb"></span>Zone configuration left on residential (unless the sale says commercial).</p>
<p><span class="cb"></span>Hardware configuration: one row per output, light counts entered, Nex-Gen standard settings kept; GPIO numbers read from the controller are 2, 14, 16, 18; no port added in the app's editor (app bug #187).</p>
<p><span class="cb"></span>Roofline mapped (corners, peaks, start of each run), or left for Design Studio later.</p>
<p><span class="cb"></span>Hand-off: preferences set; account created; credentials copied for the customer.</p>
<p><span class="cb"></span>The controller transferred to the customer's account (the wizard did not stop at a transfer warning).</p>

<div class="pagebreak"></div>

## D. Bridge (if sold)

<p><span class="cb"></span>On the home Wi-Fi (setup network "Lumina-…" joined, Wi-Fi chosen, saved).</p>
<p><span class="cb"></span>Paired in the customer's account: <strong>System & Device Management → Remote Access → Set Up Bridge</strong>; the controller target showed the customer's controller; <strong>Pair Bridge</strong>; "Bridge is working!".</p>
<p><span class="cb"></span><strong>Enable Remote Access</strong> on, <strong>Detect Home Network</strong> tapped on the home Wi-Fi.</p>
<p><span class="cb"></span>Tested from mobile data: brightness changed within a few seconds; Home badge read <strong>Via Bridge</strong>.</p>

## E. Handoff (what the customer gets)

<p><span class="cb"></span>Account created with <strong>Send Account Setup Email</strong>; invitation sent (TestFlight on iPhone, Play testing link on Android).</p>
<p><span class="cb"></span>Customer signed in on their own phone; lights respond; badge reads <strong>Direct</strong>.</p>
<p><span class="cb"></span>One repeating schedule saved together; header reads "Schedules synced to controller".</p>
<p><span class="cb"></span>Shown on the customer's phone: power, brightness and a favorite on Home.</p>
<p><span class="cb"></span>The Schedule tab and the sunrise-off switch under System.</p>
<p><span class="cb"></span>Game Day and the one rule: open the app at home in the two days before a game.</p>
<p><span class="cb"></span>Away from home needs the bridge; a change takes a few seconds; a ten-minute quiet window about every seven hours.</p>
<p><span class="cb"></span>The Support card, and general@nex-genled.com.</p>
<p><span class="cb"></span>Homeowner guide handed over. &nbsp; <span class="cb"></span>Final payment confirmed on the Day 2 wrap-up's close step.</p>
<p><span class="cb"></span>Nothing on paper left with the customer carries a password, PIN or key. &nbsp; <span class="cb"></span>Your phone is out of Installer Mode.</p>

## F. Notes

<div class="note"></div>

<table>
<tr><th style="width:22%">Installer</th><td class="w"></td><th style="width:18%">Date</th><td class="w"></td></tr>
</table>

*Facts: T-W1, T-W2, T-W5, T-W6, T-F2, T-A2, T-A3, T-A5, T-X5, T-X11, T-X13, T-X25, T-X26, T-R9, T-R10, T-GD3, T-O8, T-SU1, T-SU2.*
