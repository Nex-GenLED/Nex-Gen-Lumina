# Install checklist

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · For installers*

Work down this list on install day. Each step says what you should see. The two rules that matter most are in bold.

## Before you leave the shop

- [ ] The install sheet from the sale: customer name, address, email, the runs and their LED counts, which outputs they go on, and whether a Lumina Bridge was sold.
- [ ] Your installer PIN (your dealer code plus your installer code).
- [ ] A phone with Lumina signed in, with Bluetooth and location on.
- [ ] The customer's Wi-Fi name and password, confirmed with the customer. The controller needs the 2.4 GHz network; if the router splits bands, use that one.
- [ ] The controller and bridge, bench-prepared per the [installer SOP](13-installer-sop.md) and labelled.

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
   - Hardware configuration: one row per output; enter the number of lights on each run and keep the Nex-Gen standard LED settings. Check that the output number on each row matches the label on the controller (see [Controller setup](11-controller-setup.md)). You may tap **Skip for now** behind the warning and finish this later from System & Device Management → My Lights.
   - Map roofline: walk each run with the lit pixel and mark corners, peaks and the start of each run, or choose to map later from Design Studio.
   - Hand-off: set the customer's preferences, then create their account. Copy the credentials for the customer.
4. **Never hand the customer a phone that is still in Installer Mode.** Tap **Tap to exit installer mode** under System first, or finish on your own phone and have the customer sign in on theirs.

**If a controller did not transfer to the customer's account**, the wizard says so and tells you to finish before you leave; do not stop at that screen.

## Bridge (if one was sold)

Follow the [Bridge guide](12-bridge-guide.md): join its setup network, set the home Wi-Fi, then in the customer's account pair it under **System & Device Management → Remote Access → Set Up Bridge**, and test it from your phone on mobile data. Bridges are paired by installers only.

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
