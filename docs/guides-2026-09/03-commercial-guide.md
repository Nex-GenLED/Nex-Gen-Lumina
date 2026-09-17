---
title: "Nex-Gen Lumina — Commercial Guide"
subtitle: "Running your property's lighting — app 2.5.10+98"
author: "Nex-Gen LED LLC"
date: "September 2026"
pdf_options:
  format: Letter
  margin: 18mm
  printBackground: true
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Nex-Gen Lumina — Commercial Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: ["_shared.css"]
body_class: guide
---

<div class="brand">NEX-GEN LUMINA</div>

# Commercial Guide

<div class="sub">Multi-zone architectural lighting for your business — set up, day-to-day, and handed to your team.</div>

**Describes Lumina app version 2.5.10+98.**

---

Your installer has handled the hardware, the network, and your brand colours. What's left is
running the building — and doing it in about four taps a week.

## What you'll need

- An iPhone or Android phone
- The **email and temporary password** from your installer
- The email addresses of any managers or staff you want to give access

---

## 1. What's the same, and what's different

Lumina is one app. A commercial account runs the same screens a residential one does — the same
power and brightness, the same design library, the same scheduling, the same remote access.

> **Note** — **Start with the *Homeowner Guide*.** Everything in it applies to you: the Home screen,
> Design Studio, Explore, schedules and timer slots, Autopilot, remote access, troubleshooting. This
> guide covers only what's different for a business.

Three things are different:

| | Residential | Commercial |
|---|---|---|
| **Zones** | Not shown | A **Zones** card in Settings for independent areas |
| **Team access** | Up to 5 household members | Up to **20** staff accounts |
| **Brand colours** | — | Loaded at install; brand designs pre-built into your library |

---

## 2. Signing in the first time

Sign in with the email and temporary password from your installer. You'll set your own password
immediately — required, not optional.

Then three short welcome screens, and a six-step tour of the Home screen. Replay it any time from
**System → Feature Tour**.

> **Didn't get credentials?** Tap **Forgot Password?** and enter your email, or contact your
> installer.

---

## 3. Your brand, already in the app

If your installer completed brand setup, your brand's colours were loaded during installation and
Lumina generated a set of designs from them. Find them under **Home → My Designs** and in **Explore**.

Use them exactly like any other design: apply one now, schedule one nightly, rename or duplicate one
to make a variation.

> **Note** — Brand colours are set during installation, and editing them afterwards is an installer
> or Nex-Gen action rather than a self-service screen. If your brand palette changes, or a colour
> isn't right, email **support@Nex-GenLED.com** or contact your dealer — don't rebuild it by hand,
> because the corrected palette should flow into your saved designs too.

---

## 4. Zones

**System → Zones.**

A zone is an area you want to control on its own — the entry canopy, the patio, the signage band,
the drive-through lane. Your installer defined them during setup and assigned the physical channels
to each.

From the Zones card you can see each zone and drive it independently, so the patio can run warm and
low while the signage band holds brand colour at full output.

> **Note** — Zones are defined from **hardware channels**, not drawn on a photo. Adding or
> re-cutting a zone means reassigning physical channels, which is an installer task. Ask your dealer
> rather than changing hardware settings yourself.

### Scheduling one area at a time

The schedule editor's **Channels** picker is the tool for this. Leave it on all channels for a
whole-property schedule, or select specific ones to scope it.

> **Warning** — **Scoping turns the rest off.** While a channel-scoped schedule runs, every channel
> you did *not* select is off for its duration. For a business this matters: a schedule scoped to
> the patio will take your signage down with it. If you want two areas on different timings, create
> a schedule for each — and mind the timer-slot budget below.

---

## 5. Scheduling a business

The scheduling rules are the same as residential, and the limits are the ones that bite first on a
commercial property:

| Limit | Value |
|---|---|
| Schedules you can save | **20** |
| **Timer slots on the controller** | **8** |

A clock-based schedule with an on-time and an off-time uses **two** slots. Four of those fills the
controller.

> **Note** — **Sunset and sunrise schedules don't consume slots.** They run from dedicated slots. For
> a business this is usually the right answer anyway — *"on at sunset, off at close"* tracks the
> seasons without anyone touching it, and it frees the general slots for exceptions.

The editor shows a live *"N of 8 timer slots used"* meter before you save.

**Sync** at the top right pushes schedules onto the controller, which is what lets them run with
every phone in the building switched off.

> **Warning** — Schedules can only be pushed while you're **on the property's Wi-Fi**. Edits made
> off-site save to your account and apply the next time a manager opens the app on site.

### The switch to turn on first

**System → Turn lights off at sunrise daily.** The controller kills the lights at sunrise every
day, whatever is running, app closed. On a commercial property this is the single best protection
against a building that stayed lit all night after a one-off manual change.

---

## 6. Your team

**System → Manage Users.** Tap **Invite**, enter an email address, send. Each person gets their own
sign-in and sets their own password. A commercial account supports up to **20**.

**Remove Access** revokes immediately — use it the same day someone leaves.

> **Note** — Invited staff currently receive full control of the lighting. Per-person restrictions,
> role levels and per-zone permissions are in development. Until then, treat an invitation as
> "trusted with the building's lighting," and remove access promptly when a role changes.

---

## 7. Seasonal and event lighting

Two approaches, and most properties use both:

**Save a design per occasion.** Build or pick the look once — holiday, brand campaign, awareness
month, game night — and save it. Applying it later is one tap, and any saved design can be attached
to a schedule.

**Let Autopilot carry the calendar.** **Schedule → Autopilot**, in **Suggest** mode, proposes
seasonal and holiday changes and waits for you to accept. For a business, Suggest is the right mode:
you keep the final say over what the building does.

### Team nights

If your property trades on local sport, **Home → Game Day** puts team colours up automatically on
game days, with a configurable lead time and an option to skip daytime games.

> **Warning** — **Game Day needs the app open on a phone.** Team turnovers and score celebrations
> run only while Lumina is in the foreground. For a bar or restaurant that's workable — a manager's
> phone or a back-office tablet with the app up — but it is not unattended automation. For
> guaranteed nightly colour, use a schedule.

---

## 8. Away from the property

**System → System & Device Management → Remote Access.**

On site, the app talks straight to the controller. Off site, it routes through your **Lumina
Bridge**. Set it up once:

1. **Detect Home Network** while on the property's Wi-Fi.
2. Leave **Connection Mode** on **ESP32 Bridge**.
3. Turn on **Enable Remote Access**.
4. **Test Bridge**.

See the *Lumina Bridge Setup* guide for the hardware side.

> **Warning** — Off site you can control the lights, but you **can't push schedule changes**. Those
> apply the next time the app is opened on the property.

---

## 9. Troubleshooting

### "We can't find your lights"

1. Are you on the property Wi-Fi? Off-site control needs the bridge.
2. Check power to the controller — breaker, and any switch feeding it.
3. **Retry**, then power-cycle the controller: off 10 seconds, on, wait 30.
4. Still down: email your dealer. Note whether *all* zones are dark or only some — that single
   detail usually locates the fault.

### One zone is dark, the others are fine

Check for a channel-scoped schedule running (§4) before assuming hardware. If no schedule explains
it, it's a wiring or channel fault — call your dealer.

### The lights changed and nobody touched them

Check the Schedule tab's weekly view; every entry is badged with what created it. Then check whether
a staff member with access made a change.

### A schedule didn't run

Did anyone tap **Sync** on the property Wi-Fi after the last edit? That's the usual answer.

---

## 10. Quick reference

| I want to… | Go to |
|---|---|
| Turn everything on or off | Home → power button |
| Drive one area only | System → Zones |
| Apply a brand design | Home → My Designs |
| Browse designs | Explore |
| Set nightly hours | Schedule → **+** |
| Push schedules to the controller | Schedule → **Sync** |
| Kill the lights every sunrise | System → Turn lights off at sunrise daily |
| Seasonal suggestions | Schedule → Autopilot → Suggest |
| Team colours on game days | Home → Game Day |
| Add a manager | System → Manage Users |
| Control off site | System → System & Device Management → Remote Access |

---

## 11. Your warranty

| Cover | Term |
|---|---|
| **Product** | **5 years** from install |
| **Labor** | **1 year minimum** — your dealer may extend it |
| **Expected service life** | **Rated 50,000 hours** — 20+ years at typical evening use |

> **Warning** — Rated service life is how long the diodes are expected to last, not a warranty term.
> Your covered terms are the five-year product and one-year-minimum labor above.

Claims go through your installing dealer.

---

## 12. Getting help

Your installing dealer first — they know your channel layout and your brand configuration. Beyond
that, email **support@Nex-GenLED.com**, and use **System → Help Center → Upload system logs** before
you write so the diagnostics arrive with your message.

---

<div class="mantra">THE SYSTEM IS THE DIFFERENCE.</div>

**Nex-GenLED.com**
