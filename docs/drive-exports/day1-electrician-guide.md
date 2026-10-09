# Day 1 and Day 2 field guide

*Replacement text for the Drive file `day1-electrician-guide.pdf`. Generated 2026-10-09 from docs/guides/; not published until the owner uploads it. Describes build: 2.5.10+116.*


---

# Dealer guide

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · For dealer principals and office staff*

## Getting in

1. On the Lumina sign-in screen tap the Lumina logo five times within three seconds, or tap **Installer** under **Nex-Gen Professional Access** on the Link Account screen. You'll see **Staff Access**.
2. Enter your PIN: your two-digit dealer code followed by your two-digit personal code. Five wrong attempts lock the pad for 30 seconds.
3. Your session lasts 30 minutes, with a warning five minutes before it ends. Sales and installer PINs both land on their own landing screen; the Dealer Dashboard is reachable from either.

Never write a PIN in a message, a document or on a label.

## The Dealer Dashboard

From the Installer Mode landing screen tap **Dealer Dashboard**. Six tabs:

| Tab | What is there |
|---|---|
| **Overview** | Eight stat cards (active jobs, completed installs, active installers, pending payouts, month- and year-to-date revenue, average ticket, conversion) and a feed of the ten most recent events. Installer and payout cards show a dash for non-admin sessions. |
| **Pipeline** | Every job with its status. Job numbers read NXG, the date, and a sequence number. |
| **Team** | Admin and owner sessions only. **Manage team** opens the installer list: add, deactivate, filter. |
| **Payouts** | Referral rewards by status, with an approve action on each pending reward. |
| **Inventory** | On-hand stock, which changes only when you receive stock. The committed, available and reorder sections are not available today, and the waste section cannot fill from live jobs. |
| **Messaging** | Your sender name, reply phone and support email, the automated message toggles, and a 30-character sign-off. |

## The pipeline, and the one gate everybody misses

Statuses run: draft → estimate sent → signed → pre-wire scheduled → pre-wire complete → install scheduled → install complete → complete (paid).

**A signed job cannot be scheduled for Day 1 until someone marks the 50 % deposit collected.** The only control for that is on the job's card in the **Day 1 Queue** on the Installer Mode landing screen: tap the deposit action and confirm. Sales Mode has no way to mark it, and the customer is told nothing while the job waits. Decide who collects the deposit and who marks it.

After Day 1 and Day 2, the final payment is confirmed on the Day 2 wrap-up's close step; that moves the job to complete (paid).

## Day 1 and Day 2 queues

Both queues live on the Installer Mode landing screen (**Day 1 Queue**, **Day 2 Queue**), not in the Dealer Dashboard. A sales PIN cannot open them.

## Referrals

Customers find **Refer a Friend** under System in their app. Codes issue on signature; rewards appear on your **Payouts** tab for approval. There is a yearly cap per referrer. Do not quote reward figures in your own materials; point customers to the screen.

## Messaging

**Messaging** tab: set the sender name customers see, the reply phone and support email, and which automated messages go out (scheduling confirmations, reminders, install complete). Message bodies are fixed. Whether texts are delivered depends on the messaging service being configured for your dealership; confirm with Nex-Gen if customers report no texts.

## What is not in the app today

- Ordering stock from Nex-Gen through the app. The corporate side has an orders queue, but the dealer ordering screens are not reachable. Order the way you do today.
- The five-step estimate wizard. The live sales flow is Prospect → Zones → Review → Estimate → Sign (see Sales mode).
- Waste intelligence and material check-in figures. They depend on data the live flow does not write.
- An admin dashboard. An admin PIN opens the Corporate Dashboard.

## When a customer calls

| They say | Do this |
|---|---|
| "I can sign in but nothing responds" | Ask them to open **System → System & Device Management → Controllers**, tap their controller and choose **Set as Active**. If no controller is listed, the install never linked it: an installer opens the account with **Existing Customer** and re-runs controller setup. |
| "Away from home it says it needs a bridge" | They have no paired bridge. Sell and install one, or explain that control is home-Wi-Fi only. |
| "Away from home it failed / the bridge hasn't checked in" | About every seven hours the bridge is quiet for ten minutes. Try again then. If it fails for longer, the bridge is unplugged or the home internet is down. |
| "The lights came back wrong after a power outage" | Open the app at home for a minute. See the customer page After a power outage. |
| "Game Day didn't switch back" | Open the app at home and tap the everyday schedule. If the Game Day screen says the everyday lighting needs repairing, an installer or Nex-Gen support corrects the presets; the app cannot yet. |
| "Can I use Alexa / Google?" | No. Siri Shortcuts on iPhone and Android app shortcuts only. Never promise the others. |
| "Can you update my firmware?" | No. Firmware is recorded at install and never changed. |

## Claims you may make

See Claims policy. In short: no voice assistants other than Siri Shortcuts, no "lifetime warranty" (5-year product, 1-year labor minimum, 50,000-hour rated life), no store-download instructions (installer invitation only), no "AR".

## Support

Your customers' app shows your dealership's phone and email under **Support & Resources** once their profile carries it (set at install). For anything you cannot solve, email general@nex-genled.com with the customer's name and the date and time.

*Facts: T-X9, T-X10, T-X11, T-X8, T-X12, T-O2, T-S2, T-R1, T-R7, T-P2, T-GD5, T-GD6, T-VA1, T-VA2, T-F2, T-O6, T-O8, T-SU1, T-SU2.*

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
5. On the same page (the controller's own settings, "Wi-Fi Setup"), set the option that decides when the setup network opens to one of the "when there is no connection" choices. Never choose "never": if the home network ever disappears, the setup network is how an installer reaches the controller again. The exact option labels, and which choice is right for Skikbily builds, are UNVERIFIED until someone observes them on a spare unit; write on the install sheet what the page offered and what you chose. Do not experiment beyond that one setting.
6. **Confirm the controller still answers on the home network after the change.** On the installer phone, open the controller's card and tap **Test Lights**, or reload the controller's page at its home-network address. Do not leave the site until it answers.
7. Map each run to one of the controller's four outputs. The canonical outputs are: output 1 = GPIO 2, output 2 = GPIO 14, output 3 = GPIO 16, output 4 = GPIO 18. Write each run's output number on the install sheet. Never use more than four; how many outputs a Skikbily unit has beyond these four is UNVERIFIED.

**If the controller stays on its setup network:** the Wi-Fi name or password is wrong, the network is 5 GHz-only, or the name is hidden. Fix the network and repeat step 3.

## In the app: Installer Mode

1. On the sign-in screen tap the Lumina logo five times within three seconds, or tap **Installer** under **Nex-Gen Professional Access** on the Link Account screen. You'll see **Staff Access**.
2. Enter your PIN. You'll see the Installer Mode landing screen with **New Install**, **Existing Customer**, **Day 1 Queue**, **Day 2 Queue** and **Dealer Dashboard**.
3. Tap **New Install** and work through the wizard in order:
   - Customer information: name, email, phone, address. The address is what sunrise and sunset schedules use.
   - Controller setup: tap **Add Controller**, then **BLE Scan (New Device)** for a new controller or **Enter IP Address** for one already on the network. Tap **Test Lights**; the house flashes white for three seconds.
   - Connection method: Ethernet when a wall jack is available, otherwise Wi-Fi. Never leave both connected.
   - Zone configuration: residential homes are one system; leave the toggle on residential unless the sale says commercial.
   - Hardware configuration: one row per output; enter the number of lights on each run and keep the Nex-Gen standard LED settings. Each row's GPIO number must be 2, 14, 16 or 18 for outputs 1 to 4. The app keeps the numbers it reads from the controller, but a row it proposes on its own comes from a list that does not match these outputs (app bug #187), so set the four outputs on the controller's own LED settings page at the bench first (SOP 1.3) and never add a new port in the app's editor. See Controller setup. You may tap **Skip for now** behind the warning and finish this later from System & Device Management → My Lights.
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
5. Support: **System → Support & Resources → Contact Nex-Gen Support** shows your dealer's phone and email, and anyone can email general@nex-genled.com.

Do not promise voice assistants. Siri Shortcuts on iPhone and Android app shortcuts work; nothing else does today. Do not say "lifetime warranty": it is 5 years on the product, 1 year minimum on labor, 50,000-hour rated life.

## Before you leave

- [ ] Firmware version, output numbers (GPIO 2, 14, 16, 18) and LED counts written on the install sheet.
- [ ] Customer signed in on their own phone, lights responding, badge reads **Direct**.
- [ ] One repeating schedule saved and the header reads "Schedules synced to controller".
- [ ] Bridge paired and tested from mobile data, if supplied.
- [ ] A unique AP password set on the controller and recorded privately; the setup network set to open only when there is no connection (never "never"); the controller confirmed answering on the home network afterwards.
- [ ] Your phone out of Installer Mode.

*Facts: T-F2, T-F3, T-A1, T-A2, T-A3, T-A5, T-X5, T-X9, T-X25, T-X26, T-R9, T-R6, T-R7, T-GD3, T-C2, T-VA1, T-VA2, T-O6, T-SU1, T-SU2, T-R10.*
