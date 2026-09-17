---
title: "Nex-Gen Lumina — Lumina Bridge Setup"
subtitle: "Control your lights from anywhere — app 2.5.10+98, firmware v1.2"
author: "Nex-Gen LED LLC"
date: "September 2026"
pdf_options:
  format: Letter
  margin: 18mm
  printBackground: true
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Nex-Gen Lumina — Lumina Bridge Setup</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: ["_shared.css"]
body_class: guide
---

<div class="brand">NEX-GEN LUMINA</div>

# Lumina Bridge Setup

<div class="sub">The small device that puts your house in your pocket.</div>

**Describes Lumina app version 2.5.10+98 and Lumina Bridge firmware v1.2.**

---

The **Lumina Bridge** sits on your home Wi-Fi and relays commands from the app to your controller —
from the office, from a hotel, from the end of the driveway. No port forwarding. No dynamic DNS. No
router configuration at all.

At home the app talks straight to your controller, because that's faster. Away from home it routes
through the bridge. The handoff is automatic; you'll never choose.

## What you'll need

- Your **Lumina Bridge**
- A **USB power supply** — any 5 V USB adapter
- Your **home Wi-Fi name and password** — 2.4 GHz
- Your Lumina controller already installed and working
- A phone with the Lumina app, signed in

---

## Part 1 — Get the bridge on your Wi-Fi

### 1. Power it up

Plug the bridge into USB power somewhere central — near the router is ideal, and it does not need to
be near the controller. Give it about 30 seconds.

### 2. Join its setup network

On your phone, open Wi-Fi settings. You'll see a network named **`Lumina-XXXX`**, where the last
four characters are unique to your bridge. Join it.

> **Note** — The setup network is open and has no password. That's deliberate — it only exists for a
> few minutes during setup and carries nothing but your Wi-Fi credentials, over a direct connection
> to a device in your hand.

### 3. Hand it your Wi-Fi

A setup page opens by itself once you join. If it doesn't, open a browser and go to
**`http://192.168.4.1`**.

Choose your home network, enter its password, and save. The bridge reboots and joins your Wi-Fi.

> **Warning** — **2.4 GHz only.** The bridge has no 5 GHz radio. If your network hides the 2.4 GHz
> band behind a single combined name, you may need to split the bands temporarily, or move your phone
> onto the 2.4 GHz network before setting the bridge up.

> **Warning** — The setup window closes after **five minutes**. If you take longer, the bridge
> restarts and broadcasts `Lumina-XXXX` again — just rejoin and start this step over.

### 4. Confirm it's online

The bridge checks in with your account every 30 seconds once it's on your Wi-Fi. Give it a minute
before moving on.

---

## Part 2 — Pair it to your account

This half happens in the app, not in a browser.

1. Open Lumina and go to **System → System & Device Management → Remote Access**.
2. Make sure a controller is selected. **The pairing button stays disabled until one is**, because
   pairing tells the bridge which controller to talk to.
3. Tap **Set Up Bridge**. You'll see three steps: **Find**, **Pair**, **Verify**.

### Find

The app looks for bridges that are online and not yet claimed. Yours appears by name, marked
**Ready to pair**.

> **Note** — If nothing appears, tap **Search Again**. The app only lists bridges that have checked
> in within the last few minutes, so a bridge that just booted may need another moment. Confirm it's
> actually on your Wi-Fi — your router's device list is the quickest way to tell.

### Pair

Check the details, confirm the **Controller Target** is the right controller, and tap **Pair
Bridge**. It completes within about 30 seconds.

> **Warning** — **If you see "Bridge already paired"**, this bridge belongs to a different Nex-Gen
> account. Only continue if you're the authorised installer for this property. A bridge coming from
> another house needs a factory reset first — see Part 4.

### Verify

The app sends a real command out to the cloud and back through the bridge to your controller. Success
reads **Bridge is working!**

If verification fails, **Retry**. If it keeps failing, the bridge is on the network but can't reach
your controller — confirm the controller is online and that the Controller Target was right.

---

## Part 3 — Turn remote access on

Back on **Remote Access**:

1. While you're still on your home Wi-Fi, tap **Detect Home Network**. This teaches the app which
   network is home, so it knows when to go direct and when to relay.
2. Leave **Connection Mode** on **ESP32 Bridge**.
3. Turn on **Enable Remote Access**.
4. Tap **Test Bridge** to confirm.

Now leave the house, drop off Wi-Fi, and turn your lights on from cellular.

> **Note** — **Remote commands take a few seconds.** The bridge checks for new commands about once a
> second, so expect a short pause — typically well under ten seconds, occasionally longer on a busy
> network. It is not instant like being at home, and that's normal.

> **Warning** — **You can control your lights remotely, but you can't change schedules remotely.**
> The bridge relays commands, not controller configuration. Schedule edits save to your account and
> apply the next time you open the app at home. Lumina tells you when this happens: *"Saved, but
> your controller can only be updated on your home Wi-Fi."*

### Confirming which path a command took

The Home screen shows a small badge reading **Direct** or **Via Bridge** for your most recent
command. Tap it for the last several commands and what the app concluded about your network each
time.

Use it to prove the bridge is doing its job: away from home it should read **Via Bridge**, and at
home it should read **Direct**. **Via Bridge** while you're at home means the app hasn't recognised
your network — re-run **Detect Home Network** from inside the house.

### Detect Home Network again if your Wi-Fi changes

If you rename your network or change providers, redo **Detect Home Network** from the house.
Otherwise the app may think you're away while you're standing in your kitchen, and route everything
the slow way.

---

## Part 4 — Moving a bridge to a different account

Read this before you try it, because the obvious approach doesn't work.

**The bridge remembers its own pairing.** Your account is written into the bridge's onboard memory
during setup, and the bridge re-publishes that pairing to the cloud **every 30 seconds** while it's
powered on. The cloud record is a copy; the bridge holds the original.

> **Warning** — **Clearing the pairing from the app or the cloud does not free a live bridge.** If
> it's plugged in and on Wi-Fi, it overwrites the release within 30 seconds and goes straight back
> to showing *paired* — to the old account. Deleting the old owner's Nex-Gen account doesn't free it
> either. Nothing done from the app or the server releases a bridge that is still running.

> **Warning** — **A factory reset currently requires installer assistance.** There is no reset button
> in the app and no web dashboard on the bridge. Contact your dealer or email
> **support@Nex-GenLED.com** and we'll walk through it, or reflash the bridge. *(Installers: the
> firmware accepts a factory reset as an HTTP POST to `/api/reset` on the bridge's local address. The
> app's own reset action currently targets a different path and does not work — don't rely on it.)*

If the bridge is genuinely gone — unplugged for good, discarded, or at a house you no longer
service — a server-side release **does** hold, because there's nothing left to overwrite it. The
problem is only ever a bridge that's still running.

---

## Bridge facts

| Detail | Value |
|---|---|
| Firmware | Lumina Bridge **v1.2** |
| Power | 5 V USB |
| Wi-Fi | 2.4 GHz only |
| Setup network | `Lumina-XXXX` — open, unique per device |
| Setup page | `http://192.168.4.1` |
| Check-in interval | Every 30 seconds |
| Command check interval | About once per second |
| Setup window | 5 minutes, then the bridge restarts |
| Remote command timeout | 45 seconds |
| Schedule changes while away | Not supported — home Wi-Fi only |

> **Note** — **The bridge has no web dashboard.** Earlier guides described a status page at the
> bridge's own address; there has never been one. Everything you need — pairing, status, testing —
> is in the app under **Remote Access**.

> **Note** — **Firmware updates are not over-the-air.** Updating a bridge means physically
> reflashing it over USB. Your dealer handles this; there is nothing for you to check or install.

---

## Troubleshooting

### `Lumina-XXXX` doesn't appear

Unplug the bridge, wait ten seconds, plug it back in, and wait 30. If it had already joined a
network it won't broadcast the setup name at all — that's success, not a fault, so skip to Part 2.

### The setup page doesn't load

Confirm your phone is actually joined to `Lumina-XXXX` and not back on your home network — phones
like to jump back to a network with internet. Then go to `http://192.168.4.1` by hand.

### The bridge never appears in the app's Find step

1. Is it on your home Wi-Fi? Check your router's device list.
2. Did you give it a minute to check in?
3. **Search Again.**
4. Power-cycle it and wait 30 seconds.
5. Is it on the same network as your phone? A guest network won't work.

### Pairing times out

The bridge didn't confirm within 30 seconds. Power-cycle it, wait for it to come back online, and
pair again.

### "This bridge firmware is outdated"

The bridge needs reflashing to a current firmware. Contact your dealer.

### Verification fails, but the bridge is online

The bridge can reach the cloud but not your controller. Confirm the controller is powered and
online, and that the Controller Target chosen during pairing is the right one. Re-run **Set Up
Bridge** to correct it.

### Remote control worked, then stopped

1. Is the bridge still powered? It's the most common answer.
2. Did your Wi-Fi password change? The bridge needs re-setup from Part 1.
3. Is **Enable Remote Access** still on?
4. Power-cycle the bridge and wait 30 seconds.

### Everything works at home, nothing works away

**Detect Home Network** was probably never run, or your network name changed. Redo Part 3, step 1
from inside the house.

---

## Getting help

Your installing dealer first. For anything else, email **support@Nex-GenLED.com** — include your
bridge's `Lumina-XXXX` name and whether it's reachable on your home network.

---

<div class="mantra">BEYOND THE LIGHT.</div>

**Nex-GenLED.com**
