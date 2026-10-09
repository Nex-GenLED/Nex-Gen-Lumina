# Dealer and Installer Setup Guide

*Replacement text for the Drive file `Dealer_Installer_Setup_Guide.pdf`. Generated 2026-10-09 from docs/guides/; not published until the owner uploads it. Describes build: 2.5.10+116.*


---

# Install checklist

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · For installers*

Work down this list on install day. Each step says what you should see. The two rules that matter most are in bold.

## Before you leave the shop

- [ ] The install sheet from the sale: customer name, address, email, the runs and their LED counts, which outputs they go on, and whether a Lumina Bridge was sold.
- [ ] Your installer PIN (your dealer code plus your installer code).
- [ ] A phone with Lumina signed in, with Bluetooth and location on.
- [ ] The customer's Wi-Fi name and password, confirmed with the customer. The controller needs the 2.4 GHz network; if the router splits bands, use that one.
- [ ] The controller and bridge, bench-prepared per the installer SOP and labelled.

## At the controller

1. Mount, wire and power the controller. Wait about a minute.
2. **Read the firmware version and write it on the install sheet.** It shows on the controller's card in the installer wizard once the controller is on the network, or at `http://4.3.2.1/json/info` while you are on its setup network. **Never flash, update or downgrade a controller.** Never load a generic WLED image.
3. If the controller is not yet on the customer's Wi-Fi: join its setup network from your phone (the network named on the controller's label), open `http://4.3.2.1`, enter the customer's Wi-Fi name and password, and save. The controller restarts and joins the home Wi-Fi.
4. **Set a unique AP password on this controller.** Controllers ship broadcasting their setup network with the manufacturer's public default password. On the controller's Wi-Fi settings page, replace it with a password unique to this unit and record it privately in your dealer's own record: never in a document, a message, a photo or the repo.
5. Once the controller is on the home network, turn "always serve the AP" off on the same page, so the setup network stops broadcasting. UNVERIFIED for Skikbily builds: until the vendor confirms the build supports this while connected, do the step if the page offers it and note on the install sheet what you found. Do not experiment on the controller beyond that setting.
6. Read the output numbers printed on the controller for each run you wired. Write them on the install sheet. Do not rely on a map in a document; the labels on the controller are the truth.

**If the controller stays on its setup network:** the Wi-Fi name or password is wrong, the network is 5 GHz-only, or the name is hidden. Fix the network and repeat step 3.

## In the app: Installer Mode

1. On the sign-in screen tap the Lumina logo five times within three seconds, or tap **Installer** under **Nex-Gen Professional Access** on the Link Account screen. You'll see **Staff Access**.
2. Enter your PIN. You'll see the Installer Mode landing screen with **New Install**, **Existing Customer**, **Day 1 Queue**, **Day 2 Queue** and **Dealer Dashboard**.
3. Tap **New Install** and work through the wizard in order:
   - Customer information: name, email, phone, address. The address is what sunrise and sunset schedules use.
   - Controller setup: tap **Add Controller**, then **BLE Scan (New Device)** for a new controller or **Enter IP Address** for one already on the network. Tap **Test Lights**; the house flashes white for three seconds.
   - Connection method: Ethernet when a wall jack is available, otherwise Wi-Fi. Never leave both connected.
   - Zone configuration: residential homes are one system; leave the toggle on residential unless the sale says commercial.
   - Hardware configuration: one row per output; enter the number of lights on each run and keep the Nex-Gen standard LED settings. Check that the output number on each row matches the label on the controller (see Controller setup). You may tap **Skip for now** behind the warning and finish this later from System & Device Management → My Lights.
   - Map roofline: walk each run with the lit pixel and mark corners, peaks and the start of each run, or choose to map later from Design Studio.
   - Hand-off: set the customer's preferences, then create their account. Copy the credentials for the customer.
4. **Never hand the customer a phone that is still in Installer Mode.** Tap **Tap to exit installer mode** under System first, or finish on your own phone and have the customer sign in on theirs.

**If a controller did not transfer to the customer's account**, the wizard says so and tells you to finish before you leave; do not stop at that screen.

## Bridge (if one was sold)

Follow the Bridge guide: join its setup network, set the home Wi-Fi, then in the customer's account pair it under **System & Device Management → Remote Access → Set Up Bridge**, and test it from your phone on mobile data. Bridges are paired by installers only.

## Five things to show the customer

1. Power and brightness on Home, and a favorite.
2. The Schedule tab: one repeating schedule you set together, and the **Turn lights off at sunrise daily** switch under System.
3. Game Day, if they follow a team: add the team, and tell them the one rule: **open the app at home in the two days before a game**. Score celebrations need the app open.
4. Away from home: works only with the bridge; a change takes a few seconds; about every seven hours the bridge is quiet for ten minutes.
5. Support: **System → Support & Resources → Contact Nex-Gen Support** shows your dealer's phone and email.

Do not promise voice assistants. Siri Shortcuts on iPhone and Android app shortcuts work; nothing else does today. Do not say "lifetime warranty": it is 5 years on the product, 1 year minimum on labor, 50,000-hour rated life.

## Before you leave

- [ ] Firmware version, output numbers and LED counts written on the install sheet.
- [ ] Customer signed in on their own phone, lights responding, badge reads **Direct**.
- [ ] One repeating schedule saved and the header reads "Schedules synced to controller".
- [ ] Bridge paired and tested from mobile data, if supplied.
- [ ] A unique AP password set on the controller and recorded privately; "always serve the AP" turned off if the controller's page offers it (note what you found).
- [ ] Your phone out of Installer Mode.

*Facts: T-F2, T-F3, T-A1, T-A2, T-A3, T-A5, T-X5, T-X9, T-X25, T-X26, T-R9, T-R6, T-R7, T-GD3, T-C2, T-VA1, T-VA2, T-O6, T-SU1, T-R10.*

---

# Controller setup: outputs, channels and the roofline

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · For installers*

## Outputs are channels

Each physical output on the controller drives one run of lights. The app calls each output a channel. Channels come from the controller's hardware, not from how the roofline is drawn: when the app connects at home it reads the outputs and splits the controller's lighting to match them.

**Read the output numbers from the controller's own labels.** The app's hardware editor proposes output numbers from a fixed list when you add a row; installed units do not always use those numbers. After you save, confirm each row drives the right run with **Test Lights** or by walking the lit pixel. If a row lights the wrong run, change its output number to the one printed on the controller. This mismatch is logged as a likely app defect; until it is fixed, the label on the controller wins.

## Hardware configuration (Installer Mode → the hardware step, or System & Device Management → My Lights)

For each output:

1. Enter the number of lights on that run ("Count the bulbs on this strand").
2. Keep the Nex-Gen standard LED settings. The standard is an RGBW strip with colour order RGB. Do not set GRB.
3. Save. The controller restarts.

The app also keeps the controller's clock, time zone and location correct on every connection at home, using the customer's address from their profile. You do not set those on the controller.

## Roofline marking

Design Studio needs to know where the corners, peaks and runs are. Two tools do this:

- **Mark Your Roofline** (from Design Studio → **Roofline setup**, also the wizard's map step). One light is lit on the house; move it along the run and tap what it is sitting on: a corner, a peak, or the start of a new run. You can merge or delete sections, **Undo**, or **Start over** on a channel. Customers can use this one.
- **Roofline Segments** (installer-only, behind the installer lock) for detailed edits and clean-up of duplicate sections.

Get the light counts right first: the count drives the map and everything downstream.

## Adding or changing an output after install

Do it in the app, never on the controller's own web page.

1. In the customer's account (Installer Mode → **Existing Customer**), open System & Device Management → My Lights and add the row with the output number printed on the controller and its light count. Save.
2. Open the app on the home Wi-Fi and wait a minute, so the channels are re-read.
3. Re-check the roofline map and any schedule that targets specific channels.
4. Tell Nex-Gen support that an output was added. Game Day checks that the everyday lighting presets describe every output; after a change they may not, and until that is corrected Game Day stays blocked for the house. An in-app repair is coming; today support corrects it.

A change made on the controller's own page bypasses all of this and can leave Game Day blocked and the house stuck in team colours after a game.

## Time, location and the microphone setting

- The customer's address in their profile is what sunrise and sunset use. Confirm it is right.
- The controller's audio-reactive add-on must be off; the app turns it off on connection if it finds it on.

## Firmware

Record the version. Never flash, update or downgrade. See the install checklist.

*Facts: T-G1, T-G2, T-X4, T-X5, T-X25, T-GD8, T-GD7, T-D2, T-F2.*

---

# The Lumina Bridge

*Describes build: 2.5.10+116 · Bridge firmware 1.2 · Last verified: 2026-10-09 · For installers*

The bridge is a small box that stays plugged in at the customer's house, on their Wi-Fi. It lets the app control the lights from anywhere. Bridges are installed, paired, replaced and moved by installers only; customers do not pair a bridge.

## What it can and cannot do

- It relays light changes (power, brightness, looks, Game Day looks) from the cloud to the controller. A change takes a few seconds.
- It cannot change controller settings or schedules. Schedule edits made away from home apply when the customer's phone is next at home.
- It has no web page. The only page it ever shows is its Wi-Fi setup page during first setup. Status and testing are in the app.
- It checks in every 30 seconds. About every seven hours it goes quiet for roughly ten minutes; during that window remote commands fail and the app may say the bridge has not checked in. Home Wi-Fi control is unaffected. This is known; the fix is on the server side and is coming.
- Its firmware is updated only by Nex-Gen, by cable, at the bench. Never try to update a bridge in the field.

## Pair a bridge

**At the house, step 1: put the bridge on the home Wi-Fi.**

1. Plug the bridge in. Within a minute it broadcasts its own setup network; the name starts with "Lumina-".
2. On your phone, join that network. The setup page opens by itself; if not, open `http://192.168.4.1`.
3. Choose the customer's Wi-Fi, enter its password, save. The bridge restarts and joins the home Wi-Fi; its setup network disappears.

You have five minutes on the setup page before the bridge restarts and shows it again.

**Step 2: pair it to the customer's account, in the app.**

1. In Installer Mode tap **Existing Customer** and open the customer's account, or sign in as the customer on their phone. Your phone must be on the same home Wi-Fi as the bridge.
2. Open **System → System & Device Management → Remote Access** and tap **Set Up Bridge**.
3. **Find**: the bridge appears as "Ready to pair". If it does not, tap the advanced option and enter the bridge's address from the router's device list.
4. **Pair**: check that the controller target shows the customer's controller, then tap **Pair Bridge**.
5. **Verify**: the app runs a round trip through the cloud. You'll see "Bridge is working!".
6. Back on Remote Access, turn on **Enable Remote Access** and tap **Detect Home Network** so the app knows this Wi-Fi is home.
7. Switch your phone to mobile data and change the brightness. The lights follow within a few seconds and the Home badge reads **Via Bridge**.

**If Verify fails:** "The bridge has not heartbeated to Firestore in the last 60 seconds" means it is not on the Wi-Fi or has no internet; check the router and repeat step 1. "This bridge is paired to a different Nex-Gen account" means the previous owner's pairing was never cleared; see *Reset* below.

## Test a bridge later

**System → System & Device Management → Remote Access → Test Bridge**. It waits ten seconds. **Bridge Connected** is good. **Bridge Not Responding** means unplugged, no internet, or the quiet window: wait ten minutes and test again. **No Bridge Paired** means pair it.

## Status light

The bridge blinks every five seconds: one blink, Wi-Fi and cloud are up; two blinks, Wi-Fi only (no internet); three blinks, no Wi-Fi. It blinks fast five times when it starts.

## Reset a bridge

A reset clears the pairing and keeps the Wi-Fi settings. Use it before moving a bridge to a different account.

From a computer or phone on the same Wi-Fi as the bridge, send an HTTP POST to the bridge's address with the path `/api/reset`. It replies ok and restarts. The app has no reset button today.

## Replace a bridge

1. Reset the old bridge (above) if it still works, so it stops claiming the account.
2. Pair the new bridge as above. The old pairing is replaced in the account.

## Move a bridge to another house

1. Reset it at the old house.
2. At the new house its old Wi-Fi is absent, so the setup network comes back by itself. Set the new Wi-Fi and pair it to the new account.

## The customer changed their router or Wi-Fi

1. The bridge's setup network reappears when the old Wi-Fi is gone. Join it and set the new Wi-Fi. The pairing is kept.
2. The controller needs the new Wi-Fi too (see the install checklist, step 3). If the controller got a new address, open System & Device Management → Controllers, tap the controller and re-sync it.
3. In the app tap **Detect Home Network** on the new network.

## Do not

- Do not reset a working customer bridge "to check it". It wipes the pairing.
- Do not use the Webhook (Dynamic DNS) connection mode for an install. It is a do-it-yourself path that needs port forwarding; leave **Connection Mode** on the bridge.
- Do not describe a bridge web page or dashboard to a customer. There is none.

*Facts: T-R1, T-R4, T-R5, T-R6, T-R7, T-R8, T-R9, T-R10, T-X1, T-X2, T-O9.*

---

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
5. Turning "always serve the AP" off is done on site, once the controller is on the home network (install checklist step 5). UNVERIFIED for Skikbily builds: whether the build supports this while connected is an open vendor question; do not experiment on the controller to find out.

### 1.3 Lights settings

Prefer to do this in the Lumina app on site (the wizard's hardware step sets the Nex-Gen standard). If you set it at the bench on the controller's page, use: one output per run, the number of lights per run, the Nex-Gen standard LED type (RGBW), colour order RGB, and the output numbers printed on the controller. Do not use a pin table from a document; the controller's labels are the truth.

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

Customer name, date, and "bridge". Pairing happens on site, in the customer's account, by the installer. See the Bridge guide.

## Section 3 — On site

Use the install checklist.

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
- Any password, address, device id or pin table. The controller's labels are the source for outputs; passwords live in the dealer's own record.
- Bridge firmware flashing. That is an internal Nex-Gen procedure (see the internal bridge firmware page).

*Facts: T-F2, T-F3, T-A1, T-A2, T-A3, T-A5, T-X4, T-X5, T-R4, T-R9, T-R7, T-X1, T-G2, T-P1.*
