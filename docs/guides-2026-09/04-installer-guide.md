---
title: "Nex-Gen Lumina — Installer Guide"
subtitle: "Controller to customer hand-off — app 2.5.10+98"
author: "Nex-Gen LED LLC"
date: "September 2026"
pdf_options:
  format: Letter
  margin: 18mm
  printBackground: true
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Nex-Gen Lumina — Installer Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: ["_shared.css"]
body_class: guide
---

<div class="brand">NEX-GEN LUMINA</div>

# Installer Guide

<div class="sub">Eight steps from a powered controller to a customer signed into their own account.</div>

**Describes Lumina app version 2.5.10+98.**

---

This is a tailgate document. It assumes the strip is mounted, the power is proven, and the
controller is energised — everything before that is in the *Day 1 Electrician* and *Day 2 Install*
field guides.

## What you'll need

- The Lumina app on your phone or tablet
- Your **4-digit installer PIN**
- The customer's **name, email, and service address**
- The property's **Wi-Fi name and password** — 2.4 GHz
- Diode counts per channel, from the run you just built

---

## 1. Getting into Installer Mode

Two doors, both landing on the same PIN pad:

- **Five taps on the Lumina logo** on the sign-in screen.
- **Nex-Gen Professional Access → Installer**, on the account-linking screen.

Enter your PIN on **Staff Access**. You'll land on **Installer Mode**.

> **Warning** — Five wrong attempts locks the pad for 30 seconds. The lockout is per-device and
> counts both successes and failures against a per-minute ceiling, so don't let a helper guess.

**Installer Mode** gives you five destinations:

| Button | Use it for |
|---|---|
| **New Install** | The eight-step setup wizard — the bulk of this guide |
| **Existing Customer** | Open a customer's system to troubleshoot |
| **Day 1 Queue** | Electrical pre-wire jobs dispatched to you |
| **Day 2 Queue** | Install-day jobs dispatched to you |
| **Dealer Dashboard** | Your dealership's pipeline |

> **Note** — If you're installing a SKIKBILY or a dual-network controller, open the collapsible card
> on the landing screen before you start. Those two cases have specific steps, and the dual-network
> one is where most reworks come from.

---

## 2. Session rules

Read these once; they prevent most failed installs.

> **Warning** — **Finish the wizard in one session.** Your installer session holds the credentials
> that move the controller records onto the customer's account. If the session expires partway, the
> customer may end up signed in with no controller attached, and you'll re-run the wizard.

> **Warning** — **Never hand a customer a phone that's still in Installer Mode.** Exit first. The
> installer session can reach every account on your dealer code.

---

## 3. The eight steps

| # | Step | Skippable? |
|---|---|---|
| 1 | **Customer Info** | No |
| 2 | **Controller Setup** | No |
| 3 | **Connection Method** | Resolve or explicitly skip |
| 4 | **Zone Configuration** | No |
| 5 | **Hardware Config** | No |
| 6 | **Map Roofline** | Yes — *"Map later"* |
| 7 | **Brand Setup** | Commercial only; auto-skips on residential |
| 8 | **Customer Handoff** | No |

---

### Step 1 — Customer Info

Name, email, service address. The email becomes their sign-in, so read it back to them — a typo
here is the single most common cause of a customer who "never got their account."

---

### Step 2 — Controller Setup

Get the controller onto the property network.

**Bluetooth provisioning** is the normal path: the controller advertises over BLE, you hand it the
Wi-Fi credentials from the app, it joins, reports its address back, and the app saves it.

1. Stand within about 10 feet of the controller.
2. Scan, and select the controller.
3. Choose **Use This Network** if you're already on the property Wi-Fi, or **Enter Manually**.
4. **Connect & Finish Setup**.

> **Warning** — **2.4 GHz only.** The controller has no 5 GHz radio. On a combined-band router this
> normally just works; on a router that hides the 2.4 GHz band behind band-steering you may need to
> split the SSIDs temporarily, or join the phone to the 2.4 GHz network before provisioning.

If BLE provisioning won't take, **Add Controller** lets you point the app at an address directly
once the controller is on the network by other means.

---

### Step 3 — Connection Method

For each controller, record how it stays on the network. Ethernet is more reliable for a permanent
install — take it whenever a jack is in reach.

The screen reports what it finds:

| What it says | What to do |
|---|---|
| *Ethernet detected* | Nothing. This is the recommended configuration. |
| *WiFi only. No Ethernet detected.* | Nothing, if that's the design. |
| **Both connections active. Pick one to keep.** | Resolve it — see below. |
| *Could not read controller state* | Confirm the controller is online, then **Retry**. |

#### Resolving a dual-homed controller

A controller on Ethernet *and* Wi-Fi has two addresses. It will appear to work on install day and
then become unreachable later when the network hands out a different one. Fix it now.

- **Keep Ethernet, disable WiFi from app** — the app turns the radio off. Preferred.
- **Keep WiFi, I will unplug Ethernet** — pull the cable, then **Verify**.
- **Skip for now (leaves controller dual-homed)** — only when you genuinely cannot resolve it.

> **Warning** — Skipping is recorded against the install: *"controller will stay dual-homed. Service
> calls may be harder to troubleshoot."* Don't skip to save two minutes. You or a colleague pays it
> back on a warranty call.

**Continue** stays disabled until every controller is resolved or explicitly skipped.

---

### Step 4 — Zone Configuration

Assign channels to zones, and set the installation type.

> **Warning** — **The Residential / Commercial toggle on this screen is the one that counts.** It is
> the source of truth for the account type. The "Profile Type" cards on the hand-off screen look
> like they set the same thing; they don't — this toggle silently wins. Set it correctly **here**,
> and if the account needs to be commercial, do not rely on the hand-off screen to make it so.

---

### Step 5 — Hardware Config

The physical truth about the run. Diode counts per channel, diode type, colour order.

| Setting | Standard Lumina install |
|---|---|
| Diode type | SK6812 RGBW (WS2814 RGBW compatible) |
| WLED type code | **30** |
| Colour order | **GRB** |
| Default diodes per channel | 100 — change it to the real count |

> **Warning** — Get the counts right on install day. Diode count drives the roofline map, the
> per-pixel designs, and every accent placement the customer will ever use. A wrong count doesn't
> fail loudly; it just puts accents in the wrong places forever.

---

### Step 6 — Map Roofline

The pixel walk. This is what turns a strip into a system, and it is the step most worth your time.

For each channel, a cursor runs along the strip and you mark the architecture as it passes:

| Control | What it does |
|---|---|
| **Chase** / **Pause** | Run or hold the cursor |
| **−10 / −1 / +1 / +10** | Nudge to the exact diode |
| **Speed** | Cursor rate |
| **Corner · Peak · Run split · Column** | Mark a feature at the cursor |
| **Undo** | Remove the last mark |
| **Copy to…** | Duplicate a mapped channel's structure onto another |

Symmetric peaks have their own dialog — mark one side, preview the sweep, and add the matching peak.

> **Warning** — **"Map later" is allowed and is the wrong choice.** An unmapped house loses Smart
> Presets, corner and peak selection in the editor, and accurate accent placement. The customer's
> Home screen will read *"Map your roofline to unlock corner & peak accents."* If you truly must
> defer it, tell the customer and book the return.

If the map fails to save, you'll get **Roofline map didn't save** with a **Retry**. Don't continue
past a failed save assuming it took.

---

### Step 7 — Brand Setup (commercial only)

Auto-skips on residential. On commercial, confirm the brand and its colours; Lumina seeds the brand
profile and generates a starter set of designs into the customer's library.

> **Note** — Commercial activation needs your installer session to still be valid. If it has
> expired, you'll see a message saying the system is installed and the customer can sign in, but the
> account is still Residential. That's recoverable: re-enter your PIN and re-run setup for that
> customer.

---

### Step 8 — Customer Handoff

Generates the customer's account and a temporary password.

The credentials screen is the one thing you must not skip past. The customer will be forced to
change the password at first sign-in.

**Before you leave, show them these five things.** This is the difference between a happy customer
and a support call tonight:

1. **Power and brightness** — the two controls they'll use every day.
2. **One saved design, applied.** Prove the system does what they bought it for.
3. **One schedule, created and synced.** Then explain that **Sync** is what puts it on the
   controller, and that it only works on their home Wi-Fi.
4. **The sunrise-off switch.** *System → Turn lights off at sunrise daily.* Turn it on with them.
   It prevents the most common "my lights stayed on all night" call.
5. **How to get help** — their dealer first, and that the app isn't in the app stores yet, so the
   invitation link is how they install it on a second phone.

> **Note** — If you set up a Lumina Bridge, also show them that remote control works, and tell them
> plainly that **schedules can only be changed at home**. That one sentence prevents a lot of
> confusion later.

---

## 4. Solar schedules and controller coordinates

Sunrise and sunset schedules are live, and they depend on coordinates stored on the controller.

> **Warning** — **A coordinate change does not take effect immediately.** The controller only
> recomputes sunrise and sunset when it syncs its clock — overnight, or on restart. If you change a
> customer's location, either **reboot the controller** before you leave, or tell them the solar
> timing starts tomorrow. Do not tell them it's applied and walk away; it isn't yet.

---

## 5. Day 1 and Day 2 queues

### Day 1 Queue — electrical pre-wire

Jobs land here once an estimate is signed. Open a job for its **Day 1 Blueprint**: the customer, the
site, the planned channel layout, and the power and hardware list.

**Mark Deposit Collected** records the deposit against the job. It asks for confirmation because it
is a financial record.

### Day 2 Queue — install day

Open the job for its **Day 2 Blueprint**, work the install, then **Day 2 Wrap-Up**:

| Step | What it captures |
|---|---|
| **Install photos** | The finished run. Do this properly — it's your warranty evidence |
| **Material check-in** | What was actually consumed |
| **Customer account** | Creates the customer's account and emails their setup link |
| **Close job** | Marks the job complete |

> **Warning** — **Creating the account does not attach the controllers.** The account step makes the
> customer a sign-in; it does not link hardware, zones, or configuration. You still have to run the
> eight-step wizard — **Launch Lumina Setup** on the wrap-up screen starts it with the customer's
> details pre-filled. A customer who can sign in but sees no lights is almost always this step
> missed.

> **Note** — The zone and run data you captured in the sales visit does not currently flow into the
> wizard. Re-enter channel counts from the physical run — which is the right source anyway.

If account creation is unavailable, you'll be told you can skip and create it later. Skipping is
safe; finish the install and come back to it.

---

## 6. Existing Customer — troubleshooting a live system

**Installer Mode → Existing Customer**, search by name, email or address, and tap through. You're
now viewing their system, with a banner across the top naming whose house you're in.

**Exit** on that banner returns you to Installer Mode. Use it.

> **Warning** — While that banner is showing, every change you make lands on the **customer's**
> system. Check the name in the banner before you touch anything.

---

## 7. Field troubleshooting

### Controller won't provision over Bluetooth

Within 10 feet? Controller powered and not already joined to a network? Phone Bluetooth on? If the
property runs band-steering, join your phone to the 2.4 GHz network first.

### Controller joins, then goes unreachable

Classic dual-homed symptom. Go back to **Connection Method** and resolve it (§3).

### "System Offline" on a system you just installed

Confirm you're on the property's 2.4 GHz network. On some gateways an automatic channel choice makes
the controller reachable from 2.4 GHz clients but slow or unreachable from 5 GHz ones — pinning the
2.4 GHz band to a fixed channel at 20 MHz resolves it.

### Roofline map won't save

Retry from the failure dialog. If it keeps failing, confirm the controller is still reachable — the
map save needs it online. Don't mark the job done on an unsaved map.

### Customer can sign in but has no lights

The controllers were never migrated to their account. Re-run the wizard (§5).

### Colours look washed out or wrong after config

A controller configuration value, not a wiring fault. Reconnect the app to the controller on the
local network and let it re-assert its configuration; if it persists, escalate rather than hand-editing.

---

## 8. Quick reference

| Detail | Value |
|---|---|
| PIN length | 4 digits |
| Lockout | 5 attempts → 30 seconds |
| Wi-Fi band | 2.4 GHz only |
| Controller supply | 12 V DC |
| Diode type / code | SK6812 RGBW / type **30** |
| Colour order | GRB |
| Customer timer slots | **8** on the controller; 20 saved schedules in the app |
| Solar schedules | Free — dedicated slots, don't count against the 8 |
| Sub-users | 5 residential · 20 commercial |
| Product warranty | 5 years |
| Labor warranty | 1 year minimum |
| Rated service life | 50,000 hours |

> **Warning** — Never say "lifetime warranty." The rated 50,000-hour service life is how long the
> diodes last; the covered terms are five years product and one year minimum labor.

### The eight steps, in order

Customer Info → Controller Setup → Connection Method → Zone Configuration → Hardware Config →
Map Roofline → Brand Setup *(commercial)* → Customer Handoff

---

## 9. What a finished install looks like

- Controller on one network path, resolved — not dual-homed
- Real diode counts per channel
- Roofline mapped, saved, and verified
- Account type set on the **Zone Configuration** toggle
- Customer signed in on their own phone, with their own password
- At least one design applied and one schedule synced, in front of them
- Sunrise-off switch on
- Bridge paired and round-trip tested, if one was supplied
- No phone left in Installer Mode

---

## 10. Support

Your dealer admin first. For anything that needs Nex-Gen, email **support@Nex-GenLED.com** with the
customer's email, the dealer code, and what step failed.

---

<div class="mantra">THE SYSTEM IS THE DIFFERENCE.</div>

**Nex-GenLED.com**
