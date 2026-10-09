# Bench preparation SOP

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · For dealer shop staff*

Prepare each controller and bridge at the shop so install day is wiring and testing, not configuration. Do the whole sheet once per unit.

## What you need

- The controller, its power supply, and (for a bridge) the bridge and a USB power adapter.
- A laptop or phone with Wi-Fi.
- The customer's Wi-Fi name and password, confirmed with the customer. If the router splits 2.4 GHz and 5 GHz under different names, use the 2.4 GHz one. Avoid guest networks; they usually block devices from talking to each other.
- Labels and a marker.

## Information to capture from the customer first

Name, email (the one the account will use), phone, address (used for sunrise and sunset), Wi-Fi name and password, number of runs and the light count of each, and whether a bridge was sold.

## Section 1 — Controller

### 1.0 Firmware: record it, never change it

Controllers arrive with their firmware installed. **Never flash, update or downgrade a controller. Never load a generic WLED image.** Read the version at `http://4.3.2.1/json/info` while on the controller's setup network (the `ver` and `release` values) and write it on the install sheet and the controller label. Every version in service is supported as shipped.

### 1.1 Power up

Connect the power supply (no lights needed). After about 30 seconds the controller broadcasts its setup network (the network named on the controller's label) because it has no Wi-Fi saved yet.

### 1.2 Save the customer's Wi-Fi and secure the setup network

A new unit broadcasts its setup network with the manufacturer's public default password, and at the bench that network is always on. Every unit leaves the shop with its own password.

1. Join the setup network from your laptop or phone (a new unit still has the manufacturer's default password).
2. Open `http://4.3.2.1`. Enter the customer's Wi-Fi name and password and save.
3. On the same Wi-Fi settings page, set a unique AP password for this unit. Record it privately in the dealer's secure record: never in a document, a message, a photo or the repo. Never keep the default.
4. The controller restarts and tries the customer's Wi-Fi. At the shop it cannot reach it, so after about 30 seconds its setup network returns, now with the unit's own password. That is expected.
5. On the same page, set the option that decides when the setup network opens to one of the "when there is no connection" choices, never "never", so an installer can always reach a controller whose network is gone. The exact option labels, and which choice is right for Skikbily builds, are UNVERIFIED until observed on a spare unit; note what the page offers. Do not experiment beyond that setting.
6. On site, after the controller joins the home network, confirm it still answers there before leaving (install checklist step 6).

### 1.3 Lights settings

Set the outputs at the bench on the controller's own LED settings page (the app's hardware editor proposes wrong GPIO numbers for new rows today, app bug #187; it keeps numbers it reads from the controller). Use: one output per run, the number of lights per run, the Nex-Gen standard LED type (RGBW), colour order RGB, and the four canonical outputs: output 1 = GPIO 2, output 2 = GPIO 14, output 3 = GPIO 16, output 4 = GPIO 18. Never use more than four; how many outputs a Skikbily unit has beyond these is UNVERIFIED. Write the mapping on the install sheet.

### 1.4 Time and location

Nothing to do at the bench. The app sets the clock source, time zone and coordinates from the customer's profile every time it connects at home.

### 1.5 Audio add-on off

If the controller's usermods page shows an audio-reactive add-on enabled, turn it off; our hardware has no microphone. The app also turns it off on connection.

### 1.6 Label and power down

Label: customer name, firmware version, output numbers used, date. Power down.

## Section 2 — Bridge

### 2.1 Power up and set Wi-Fi

1. Power the bridge from USB. Within a minute it broadcasts a setup network whose name starts with "Lumina-".
2. Join it. The setup page opens (or open `http://192.168.4.1`). Choose the customer's Wi-Fi, enter the password, save. The bridge restarts and, at the shop, falls back to its setup network after a while because the customer's Wi-Fi is not here. That is expected; the credentials are saved.

You have five minutes on the setup page before the bridge restarts.

### 2.2 Optional check with a phone hotspot

Set a phone hotspot with the customer's exact Wi-Fi name and password. The bridge joins it and its light settles to one blink every five seconds (Wi-Fi and cloud up). Remove the hotspot afterwards.

### 2.3 Label

Customer name, date, and "bridge". Pairing happens on site, in the customer's account, by the installer. See the [Bridge guide](12-bridge-guide.md).

## Section 3 — On site

Use the [install checklist](10-install-checklist.md). Questions: general@nex-genled.com.

## Section 4 — Troubleshooting at the bench or on site

| Symptom | Likely cause | What to do |
|---|---|---|
| Controller stays on its setup network at the house | Wrong Wi-Fi name or password; 5 GHz-only network; hidden network | Re-enter the credentials on the setup page; use the 2.4 GHz network; un-hide the network |
| Bridge keeps showing its setup network at the house | Same as above | Same |
| The app's Find step does not see the bridge | Phone not on the same Wi-Fi; bridge still on its setup network | Put the phone on the home Wi-Fi; finish the bridge's Wi-Fi setup; use the advanced option and enter the bridge's address |
| "Could not read WiFi name" when tapping Detect Home Network | Location permission denied | Allow Location for Lumina "While Using the App" |
| A power change takes 30 seconds or fails while off Wi-Fi | Normal bridge latency is a few seconds; longer means the bridge's quiet window | Wait ten minutes and retry |
| Lights come on briefly then go dark at power-on | Normal start-up, then the schedule | Open the app at home for a minute |

## What this SOP no longer contains

- Any firmware pin or flash step. Withdrawn.
- Any password, address or device id. The only pin map is the four canonical outputs above; passwords live in the dealer's own record.
- Bridge firmware flashing. That is an internal Nex-Gen procedure (see the internal bridge firmware page).

*Facts: T-F2, T-F3, T-A1, T-A2, T-A3, T-A5, T-X4, T-X5, T-R4, T-R9, T-R7, T-X1, T-G2, T-P1, T-SU2.*
