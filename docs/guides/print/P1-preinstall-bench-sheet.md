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
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#333333;">Nex-Gen LED · Pre-install bench sheet · page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet:
  - _print_write.css
body_class: form
---

<img class="mark" src="nexgen_mark.png" alt="Nex-Gen LED">
<p class="brandline">Nex-Gen LED · Lumina</p>

# Pre-install bench sheet

<p class="meta">One sheet per controller (and its bridge). Describes build: 2.5.10+116 · Last verified: 2026-10-12 · Keep in the dealer's file. No password, PIN or key is written on this sheet.</p>

<table>
<tr><th style="width:22%">Customer name</th><td class="w"></td><th style="width:18%">Job number</th><td class="w"></td></tr>
<tr><th>Install address</th><td class="w" colspan="3"></td></tr>
<tr><th>Install day (Day 2)</th><td class="w"></td><th>Day 1 (pre-install)</th><td class="w"></td></tr>
<tr><th>Prepared by</th><td class="w"></td><th>Date</th><td class="w"></td></tr>
</table>

<div class="callout"><strong>Not our work.</strong> Nex-Gen LED and its dealers do the low-voltage wiring and the pre-install. We do no line-voltage work. Our installer can plug the power supply into an existing outlet, but we do not install outlets or run line-voltage (household power) wiring. That is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing. If there is no working outlet at the supply location, the installer does not install one: stop and tell the customer.</div>

## A. Captured from the customer

<p><span class="cb"></span>Name, email, phone and address are on the site and controller record (P3).</p>
<p><span class="cb"></span>Wi-Fi name (2.4 GHz network; if the router splits bands, the 2.4 GHz one): <span class="box wide"></span></p>
<p><span class="cb"></span>Customer's Wi-Fi password recorded privately in the dealer's secure record (never on this sheet).</p>
<p><span class="cb"></span>Not a guest network. &nbsp; <span class="cb"></span>Not a hidden network.</p>
<p><span class="cb"></span>Runs and light counts are on the record (P3). &nbsp; Bridge sold: <span class="cb"></span>yes &nbsp; <span class="cb"></span>no</p>
<p>Working outlet at the power-supply location: <span class="cb"></span>in place &nbsp; <span class="cb"></span>arranged by the homeowner &nbsp; <span class="cb"></span>not needed</p>

## B. Controller

### 1.0 Firmware: record it, never change it

<p><span class="cb"></span>Read at <code>http://4.3.2.1/json/info</code> while on the controller's setup network.</p>
<div class="row top"><span class="lbl"><code>ver</code></span><span class="box"></span><span class="lbl"><code>release</code></span><span class="box wide"></span></div>
<p><span class="cb"></span>Version written on the controller label. Never flash, update or downgrade a controller; never load a generic WLED image; do not use the update item on the controller's own settings page.</p>

### 1.1 Power up

<p><span class="cb"></span>Powered from its supply (no lights needed). After about 30 s the setup network named on the controller's label appeared.</p>

### 1.2 Customer Wi-Fi saved and the setup network secured

<p><span class="cb"></span>Joined the setup network (new unit: manufacturer's public default password) and opened <code>http://4.3.2.1</code>.</p>
<p><span class="cb"></span>Customer's Wi-Fi name and password entered and saved.</p>
<p><span class="cb"></span>A unique AP password set for this unit and recorded privately in the dealer's secure record. The default was not kept.</p>
<p><span class="cb"></span>The option that decides when the setup network opens set to a "when there is no connection" choice, never "never".</p>
<div class="row"><span class="lbl">Option labels the page offered:</span><span class="fill"></span></div>
<div class="row"><span class="lbl">Choice made:</span><span class="fill"></span></div>
<p><span class="cb"></span>After the restart the setup network came back with the unit's own password (expected at the shop: the customer's Wi-Fi is not here).</p>

### 1.3 Lights settings (on the controller's own LED settings page, not in the app)

<table>
<tr><th class="n">Output</th><th style="width:14%">GPIO</th><th>Run name</th><th style="width:18%">Light count</th><th style="width:16%">LED type</th><th style="width:16%">Colour order</th></tr>
<tr><td class="w">1</td><td class="w">2</td><td class="w"></td><td class="w"></td><td class="w">RGBW</td><td class="w">RGB</td></tr>
<tr><td class="w">2</td><td class="w">14</td><td class="w"></td><td class="w"></td><td class="w">RGBW</td><td class="w">RGB</td></tr>
<tr><td class="w">3</td><td class="w">16</td><td class="w"></td><td class="w"></td><td class="w">RGBW</td><td class="w">RGB</td></tr>
<tr><td class="w">4</td><td class="w">18</td><td class="w"></td><td class="w"></td><td class="w">RGBW</td><td class="w">RGB</td></tr>
</table>

<p>One output per run. The Nex-Gen standard is an RGBW strip with colour order RGB (not GRB). Never use more than four outputs; the number beyond four on a Skikbily unit is UNVERIFIED. Do not add a port in the app's hardware editor (app bug #187).</p>

### 1.4 to 1.6

<p><span class="cb"></span>Time and location: nothing to do; the app sets them from the customer's profile at home.</p>
<p><span class="cb"></span>Audio add-on turned off if the usermods page showed it enabled (our hardware has no microphone).</p>
<p><span class="cb"></span>Label: customer name, firmware version, outputs used, date. &nbsp; <span class="cb"></span>Powered down.</p>

<div class="pagebreak"></div>

## C. Bridge (if sold)

<p><span class="cb"></span>Powered from USB; within a minute a setup network whose name starts with "Lumina-" appeared.</p>
<p><span class="cb"></span>Joined it; on the setup page (or <code>http://192.168.4.1</code>) chose the customer's Wi-Fi, entered the password, saved. Five minutes before the bridge restarts.</p>
<p><span class="cb"></span>Optional hotspot check with the customer's exact Wi-Fi name: one blink every five seconds. Hotspot removed afterwards.</p>
<p><span class="cb"></span>Label: customer name, date, "bridge". Pairing happens on site, in the customer's account, by the installer only.</p>

## D. Notes

<div class="note"></div>

<table>
<tr><th style="width:22%">Prepared by</th><td class="w"></td><th style="width:18%">Checked by</th><td class="w"></td></tr>
</table>

*Facts: T-W1, T-W2, T-W6, T-W8, T-W12, T-F2, T-F3, T-F9, T-A1, T-A2, T-A3, T-A5, T-X4, T-X5, T-R9, T-X1.*
