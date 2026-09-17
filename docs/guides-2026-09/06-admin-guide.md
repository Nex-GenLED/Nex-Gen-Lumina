---
title: "Nex-Gen Lumina — Admin Operations Guide"
subtitle: "Internal — running the network behind the app — app 2.5.10+98"
author: "Nex-Gen LED LLC"
date: "September 2026"
pdf_options:
  format: Letter
  margin: 18mm
  printBackground: true
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Nex-Gen Lumina — Admin Operations Guide (Internal)</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: ["_shared.css"]
body_class: guide
---

<div class="brand">NEX-GEN LUMINA</div>

# Admin Operations Guide

<div class="sub">Internal. The dealer network, the staff tiers, the flags, and the things that only look like they work.</div>

**Describes Lumina app version 2.5.10+98. Internal distribution only.**

> **Warning** — **This document contains no PIN values.** Every master PIN is held offline. If you
> are reading a copy of this guide with PINs written into it, that copy is a security incident —
> destroy it and rotate the PINs.

---

## What you'll need

- The Lumina app, signed in on a phone or tablet
- The **Corporate PIN** or **Admin PIN** — held offline
- Firebase Console access to the Lumina production project, for flags and PIN hashes
- Your current dealer roster

---

## 1. The staff tiers

Four tiers resolve from one PIN pad, in descending privilege. The first match wins.

| Tier | Mode | Lands on | PIN source |
|---|---|---|---|
| **Owner** | Corporate | Corporate Dashboard | `app_config/master_corporate_pin` |
| **Admin** | Admin | Corporate Dashboard | `app_config/master_admin`, or an installer record with an admin role |
| **Installer** | Installer | Installer Mode | `app_config/master_installer`, or an installer record |
| **Sales** | Sales | Sales Mode | `app_config/master_sales_pin`, or an installer record |

Owner and admin share the Corporate Dashboard UI; the real privilege boundary is enforced
server-side in Firestore rules, not in the interface. An owner session carries no dealer code —
that absence is precisely how the rules tell an unscoped owner from scoped staff.

### Entry points

- Five taps on the Lumina logo on the sign-in screen.
- **Nex-Gen Professional Access → Installer** on the account-linking screen.

> **Warning** — The second door is **permanently visible** to every account whose installation role
> is unlinked, which is every fresh signup. It is a known open question for store review. Don't be
> surprised to find it; do raise it before submission.

> **Warning** — The PIN pad signs in anonymously before it can validate anything. **Anonymous
> sign-in must stay enabled** in the Firebase Console. If it's disabled, every staff PIN fails with
> *"Auth unavailable."* This is a single switch that takes the entire field organisation offline.

Lockout is five attempts, then 30 seconds, plus a per-minute ceiling per source address that counts
successes as well as failures.

---

## 2. The Corporate Dashboard

Five tabs.

| Tab | What it's for |
|---|---|
| **Network** | Every dealer, with drill-down into any dealership |
| **Pipeline** | Every job across the network, read-only |
| **Warehouse** | Stock, purchase orders, received shipments |
| **Orders** | Dealer orders awaiting review — carries a live count badge |
| **Admin** | Everything below |

Tapping a dealer in **Network** opens that dealership's own Dealer Dashboard with their dealer code
applied — the same six tabs a dealer sees, in an admin view, marked in amber so you always know
you're looking at someone else's business.

---

## 3. The Admin tab

### Dealer Management

Onboard, edit and deactivate dealerships.

### Dealer Accounts

Find a user account and **Promote to dealer** or **Revoke dealer role**. Both ask for confirmation
and report back by name.

### Product Catalog and Pricing Defaults

**Manage Catalog** maintains the material catalog the estimate and material tooling draws on.
Pricing Defaults sets the network baseline.

### Network Announcements

Messages pushed to dealers.

### System PINs

Read-only status for the four master slots — each badged **Set** or **Not set**.

> **Note** — This screen shows *status*, never values. Changing a PIN requires verifying the current
> one before writing the new value, and the write itself is done in the Firebase Console against
> `app_config`. Rotating a master PIN invalidates every session using it, so schedule it — don't do
> it at 4pm on an install day.

### Brand Library and Brand Corrections

> **Warning** — **Both buttons are currently unusable from any PIN session.** The screens behind
> them check for an `admin` value in a user profile document. A PIN session authenticates as a
> synthetic staff identity that has no user profile document, so the check returns false and you get
> *"Not authorized."* Worse, nothing in the app ever writes that admin value, so no account can
> satisfy it today. The count tiles on the Admin tab load normally, which makes the surface look
> healthy right up until you tap it.
>
> **Workaround:** brand library changes require a hand-edited Firestore profile document, or direct
> console work. Treat brand library administration as a console task, not an in-app one, until this
> is fixed.

---

## 4. Feature flags — the live values

Five Firestore documents gate behaviour fleet-wide. **All of them default to `false` in code** —
that is the fail-safe fallback, not the live value. Read the console, never the code, and never an
admin-credentialed read alone: verify under rules with a constrained credential, because an admin
read bypasses the rules that decide whether the app can see the flag at all.

| Flag | Live value | What it controls |
|---|---|---|
| `config/solar_scheduling.enabled` | **true** | Sunrise/sunset schedules. Bench-verified firing on hardware. |
| `config/calendar_leases.liveWritesEnabled` | **true** | Dated calendar entries reserving controller timer slots. |
| `config/sync_fanout.enabled` | **false** | Server-side Neighborhood Sync delivery to other members. |
| `config/schedules_subcollection.enabled` | **false** | New schedule storage backend. Supports allowlist and percentage rollout. |
| `config/gameday_planner.write_jobs` | **false** | Unattended server-side Game Day firing. Log-only today. |

> **Warning** — **Do not flip `sync_fanout` casually.** With it off, a sync reaches other members
> only while their app is open. With it on, server-side fanout can drive other members'
> controllers — and there is an open self-join hardening item that must land first. This flag is
> console-only by design. Confirm it reads `false` before any submission.

> **Warning** — **Game Day does not fire unattended.** With `write_jobs` false the planner is
> log-only and dispatch is in shadow mode, so nothing happens with the app closed. Customers are
> told this in their guide; make sure support knows it too, because "my lights didn't come on for
> the game and my phone was in my pocket" is expected behaviour, not a fault.

### Deploy discipline

> **Warning** — **Firestore rules are not deployed automatically.** Changing `firestore.rules` in
> the repo changes nothing in production until someone runs the deploy. And before deploying rules
> or functions, **assert that the SHA you're deploying is an ancestor of `main`** — deploying a
> server half from an unmerged branch has previously stranded every client and broken a feature for
> the entire fleet.

---

## 5. Things that look shipped and are not

Keep this list in front of support. Every row is a screen or capability that exists, appears
functional, and cannot be used — so a report about one of them is not a bug to investigate.

| Surface | Status |
|---|---|
| **Audio Mode** | Debug builds only. Release builds show My Designs in its place. |
| **The commercial shell** (`/commercial` and its Dashboard/Fleet/Brand/Events/Profile tabs) | Orphaned. Commercial customers land on the standard dashboard; nothing navigates to the commercial shell. |
| **Commercial onboarding wizard** | Eight complete screens, no caller. |
| **Estimate Wizard** (5 steps) | Orphaned — which is why estimates fall back to manually-entered zone pricing and why the Inventory tab's committed/available sections can't resolve. |
| **Material checkout and check-in screens** | Orphaned. No dealer stock moves automatically. |
| **Dealer inventory and ordering screens** | Four screens, no route. The dealer Inventory tab is a different screen. |
| **Brand Library admin** | Permission check cannot pass — §3. |
| **Game Day crews** | Missing Firestore rules block → every read and write is denied, silently. The whole crew UI is inert. |
| **Alexa and Google Home linking** | Missing rules block on the integrations path → the link never launches. Backends are deployed; the in-app entry is dead. Siri Shortcuts work. |
| **Welcome Home / geofence setup** | The screen is complete; no route navigates to it, so the config can never be written and the monitor stays inert. |
| **Neighborhood scheduled syncs** | Saved and listed; nothing executes them. |
| **Autopilot First-Week Reveal and Calendar screens** | No inbound navigation. |
| **Payout approval screen** at `/dealer/payouts` | Orphaned duplicate of the inline Payouts tab. |
| **Game Day "Alerts" sensitivity and "Motion style"** | Persisted, not consumed. The live path treats every scoring play the same. |

> **Note** — Several of these are missing Firestore rules blocks rather than missing code. That
> class of fault is silent by construction: the client swallows the denial and renders an empty
> state. When a customer reports a feature that "does nothing," check the rules before the code.

---

## 6. Customer account operations

### Deletion

Customers self-serve from **System → Security → Delete Account**. It removes the profile, designs,
schedules and photos.

> **Warning** — Deletion is **not** complete. Three things survive and need manual attention:
>
> - **The controller keeps running.** Deletion doesn't turn lights off or clear the hardware.
>   Whatever schedule is stored on the controller keeps firing until an installer resets it.
> - **A live bridge stays claimed.** The bridge holds its pairing in its own memory and re-asserts
>   it every 30 seconds. Releasing it server-side does nothing while it's powered on. It needs a
>   factory reset — see the *Lumina Bridge Setup* guide, and note the reset path itself is currently
>   an open item.
> - **Residual data.** Crew membership and voice-assistant links aren't purged automatically. Clear
>   them by hand on request.

### Purges and wipes

> **Warning** — **Never trust a purge script's own summary.** Known gaps: referral code lookups,
> Game Day plan logs that sit in no purge path at all, and field names that differ from what the
> scripts assume. Verify against Firestore directly after every run, and record the operation in the
> wipe log.

### Verifying anything

> **Warning** — **Verify with a client credential, not an admin one.** An admin read bypasses
> security rules entirely, so it proves a document exists and proves nothing about whether the app
> can read it. A readback under admin is not a verification. This distinction has cost a full day of
> debugging before.

---

## 7. Runbook — recurring tasks

**Onboarding a dealer**

1. Corporate → Admin → Dealer Management → add the dealership.
2. Confirm the dealer record is active — staff PIN validation checks it, and an inactive dealership
   silently fails every one of its PINs.
3. Add installers to the roster.
4. **Have each new installer test their PIN before dispatch.** A new installer record may need a
   role value the add form doesn't capture; the symptom is a PIN that won't sign in.

**Rotating a master PIN**

1. Verify the current PIN, then write the new value in the Firebase Console against `app_config`.
2. Confirm the slot reads **Set** on the System PINs screen.
3. Notify whoever holds it. Every existing session on the old PIN is invalidated.

**Before a store submission**

1. Confirm `config/sync_fanout.enabled` is `false`.
2. Confirm anonymous sign-in is still enabled.
3. Confirm the deployed rules SHA is an ancestor of `main`.
4. Bump the Android version code — a built bundle consumes its code whether or not it's uploaded.

---

## 8. Support escalation

| Symptom | First check |
|---|---|
| A whole dealership's PINs fail | Anonymous sign-in enabled? Dealership active? |
| One installer's PIN fails | Role value on the installer record |
| Customer signed in, no lights | Controllers never migrated — installer re-runs the wizard |
| A schedule never fired | Was **Sync** tapped on the home network? Slot budget? Solar coordinates changed recently without a reboot? |
| Solar schedule didn't fire the first night | Expected. Coordinates only take effect on clock sync or restart. |
| Game Day didn't fire with the app closed | Expected. Server firing is log-only. |
| A neighbour's lights didn't respond | Expected. Fanout is off; members need the app open. |
| A feature "does nothing" | Check for a missing Firestore rules block before reading code |

---

<div class="mantra">THE SYSTEM IS THE DIFFERENCE.</div>

Internal document — Nex-Gen LED LLC. Not for dealer or customer distribution.
**Nex-GenLED.com**
