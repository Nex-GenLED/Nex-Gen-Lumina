# Install checklist

*Describes build: 2.5.10+116 · Last verified: 2026-10-12 · For installers*

The job in order: what the dealer does before install day (pre-install), what you do on install day, and what the customer must have before you leave (handoff). Each step says what you should see. The rules that matter most are in bold. The pen version of this page is the install-day sheet in the [print forms](../print/README.md).

## Not our work

Nex-Gen LED and its dealers do the low-voltage wiring and the pre-install. We do no electrical work. Our installer may plug the power supply into an existing customer outlet. Nex-Gen LED and its dealers do not install outlets and do not run line-voltage (household power) wiring; that is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing. If there is no working outlet at the supply location, the installer does not install one: stop and tell the customer. Anything needed on that side is arranged before install day.

Not yet decided by the owner, so do not improvise an answer on site (ask): whether the installer may plug into an outlet that is not weatherproof or GFCI; junction boxes; where the power supply mounts; fusing; extension cords; permits and inspections. The exact boundary is UNVERIFIED.

## Pre-install (the dealer, before install day)

- [ ] The site and controller record from the sale (print form): customer name, address, email, the runs and their LED counts, which outputs they go on, and whether a Lumina Bridge was sold.
- [ ] A working outlet at the power-supply location confirmed in place, or confirmed arranged by the homeowner (see *Not our work*). Note it on the record.
- [ ] The 50 % deposit marked collected on the job's card in the **Day 1 Queue** (**Mark Deposit Collected**); the app will not schedule Day 1 before that.
- [ ] Day 1, the pre-install visit: the dealer's installer runs the low-voltage wiring for each run back to the controller location and labels every wire end by run, so install day is lights, controller and app. No lights go up on Day 1.
- [ ] The controller and bridge bench-prepared per the [pre-install SOP](13-installer-sop.md) and labelled; the pre-install bench sheet completed and filed.
- [ ] Your installer PIN (your dealer code plus your installer code), and a phone with Lumina signed in, with Bluetooth and location on.
- [ ] The customer's Wi-Fi name, confirmed with the customer. The controller needs the 2.4 GHz network; if the router splits bands, use that one. The password is recorded privately, never on a sheet.

## Install day

### At the controller

1. Mount the controller, connect the low-voltage wiring and the lights, and plug the power supply into the existing outlet. If there is no working outlet, do not install one: stop and tell the customer. Wait about a minute.
2. **Read the firmware version and write it on the record.** It shows on the controller's card in the installer wizard once the controller is on the network, or at `http://4.3.2.1/json/info` while you are on its setup network. **Never flash, update or downgrade a controller.** Never load a generic WLED image. The controller's own settings page offers an update; do not use it.
3. If the controller is not yet on the customer's Wi-Fi: join its setup network from your phone (the network named on the controller's label), open `http://4.3.2.1`, enter the customer's Wi-Fi name and password, and save. The controller restarts and joins the home Wi-Fi.
4. **Set a unique AP password on this controller.** Controllers ship broadcasting their setup network with the manufacturer's public default password. On the controller's Wi-Fi settings page, replace it with a password unique to this unit and record it privately in your dealer's own record: never in a document, a message, a photo or the repo.
5. On the same page (the controller's own settings, "Wi-Fi Setup"), set the option that decides when the setup network opens to one of the "when there is no connection" choices. Never choose "never": if the home network ever disappears, the setup network is how an installer reaches the controller again. The exact option labels, and which choice is right for Skikbily builds, are UNVERIFIED until someone observes them on a spare unit; write on the record what the page offered and what you chose. Do not experiment beyond that one setting.
6. **Confirm the controller still answers on the home network after the change.** On the installer phone, open the controller's card and tap **Test Lights**, or reload the controller's page at its home-network address. Do not leave the site until it answers.
7. Map each run to one of the controller's four outputs. The canonical outputs are: output 1 = GPIO 2, output 2 = GPIO 14, output 3 = GPIO 16, output 4 = GPIO 18. Write each run's output number on the record. Never use more than four; how many outputs a Skikbily unit has beyond these four is UNVERIFIED.

**If the controller stays on its setup network:** the Wi-Fi name or password is wrong, the network is 5 GHz-only, or the name is hidden. Fix the network and repeat step 3.

### In the app: Installer Mode

1. On the sign-in screen tap the Lumina logo five times within three seconds, or tap **Installer** under **Nex-Gen Professional Access** on the Link Account screen. You'll see **Staff Access**.
2. Enter your PIN. You'll see the Installer Mode landing screen with **New Install**, **Existing Customer**, **Day 1 Queue**, **Day 2 Queue** and **Dealer Dashboard**.
3. Tap **New Install** and work through the wizard in order:
   - Customer information: name, email, phone, address. The address is what sunrise and sunset schedules use.
   - Controller setup: tap **Add Controller**, then **BLE Scan (New Device)** for a new controller or **Enter IP Address** for one already on the network. Tap **Test Lights**; the house flashes white for three seconds.
   - Connection method: Ethernet when a wall jack is available, otherwise Wi-Fi. Never leave both connected.
   - Zone configuration: residential homes are one system; leave the toggle on residential unless the sale says commercial.
   - Hardware configuration: one row per output; enter the number of lights on each run and keep the Nex-Gen standard LED settings. Each row's GPIO number must be 2, 14, 16 or 18 for outputs 1 to 4. The app keeps the numbers it reads from the controller, but a row it proposes on its own comes from a list that does not match these outputs (app bug #187), so set the four outputs on the controller's own LED settings page at the bench first (SOP 1.3) and never add a new port in the app's editor. See [Controller setup](11-controller-setup.md). You may tap **Skip for now** behind the warning and finish this later from System & Device Management → My Lights.
   - Map roofline: walk each run with the lit pixel and mark corners, peaks and the start of each run, or choose to map later from Design Studio.
   - Hand-off: set the customer's preferences, then create their account. Copy the credentials for the customer.
4. **Never hand the customer a phone that is still in Installer Mode.** Tap **Tap to exit installer mode** under System first, or finish on your own phone and have the customer sign in on theirs.

**If a controller did not transfer to the customer's account**, the wizard says so and tells you to finish before you leave; do not stop at that screen.

### Bridge (if one was sold)

Follow the [Bridge guide](12-bridge-guide.md): join its setup network, set the home Wi-Fi, then in the customer's account pair it under **System & Device Management → Remote Access → Set Up Bridge**, and test it from your phone on mobile data. Bridges are paired by installers only.

## Handoff (what the customer gets)

1. Their account, created in the Day 2 wrap-up with **Send Account Setup Email**, and the app invitation (TestFlight on iPhone, a Play testing link on Android). The app is not in the public stores.
2. Their own phone signed in, the lights responding, and the Home badge reading **Direct**.
3. Five things shown on their phone:
   1. Power and brightness on Home, and a favorite.
   2. The Schedule tab: one repeating schedule you set together, and the **Turn lights off at sunrise daily** switch under System.
   3. Game Day, if they follow a team: add the team, and tell them the one rule: **open the app at home in the two days before a game**. Score celebrations need the app open.
   4. Away from home: works only with the bridge; a change takes a few seconds; about every seven hours the bridge is quiet for ten minutes.
   5. Support: **System → Support & Resources → Contact Nex-Gen Support** shows your dealer's phone and email, and anyone can email general@nex-genled.com.
4. The homeowner guide (the dealer's copy), and the final payment confirmed on the Day 2 wrap-up's close step.
5. Nothing on paper that carries a password, a PIN or a key. The site and controller record stays in the dealer's file.

Do not promise voice assistants. Siri Shortcuts on iPhone and Android app shortcuts work; nothing else does today. Do not say "lifetime warranty": it is 5 years on the product, 1 year minimum on labor, 50,000-hour rated life. Local dealers may add additional coverage at their discretion. Do not describe anyone from Nex-Gen LED or the dealer as an electrician, and do not offer electrical work.

## Before you leave

- [ ] Firmware version, output numbers (GPIO 2, 14, 16, 18) and LED counts written on the record.
- [ ] Customer signed in on their own phone, lights responding, badge reads **Direct**.
- [ ] One repeating schedule saved and the header reads "Schedules synced to controller".
- [ ] Bridge paired and tested from mobile data, if supplied.
- [ ] A unique AP password set on the controller and recorded privately; the setup network set to open only when there is no connection (never "never"); the controller confirmed answering on the home network afterwards.
- [ ] Your phone out of Installer Mode.

*Facts: T-W1, T-W2, T-W3, T-W5, T-W6, T-W7, T-W8, T-F2, T-F3, T-F9, T-F12, T-A1, T-A2, T-A3, T-A5, T-X5, T-X9, T-X11, T-X13, T-X25, T-X26, T-R9, T-R6, T-R7, T-GD3, T-C2, T-VA1, T-VA2, T-O6, T-O8, T-SU1, T-SU2, T-R10.*
