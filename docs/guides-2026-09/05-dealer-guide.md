---
title: "Nex-Gen Lumina — Dealer Guide"
subtitle: "Pipeline, team, and field tools — app 2.5.10+98"
author: "Nex-Gen LED LLC"
date: "September 2026"
pdf_options:
  format: Letter
  margin: 18mm
  printBackground: true
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Nex-Gen Lumina — Dealer Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: ["_shared.css"]
body_class: guide
---

<div class="brand">NEX-GEN LUMINA</div>

# Dealer Guide

<div class="sub">Your pipeline, your crews, and the field tools that carry a job from a driveway conversation to a live system.</div>

**Describes Lumina app version 2.5.10+98.**

---

Everything your dealership runs day to day lives in two places: **Sales Mode** for the field, and
the **Dealer Dashboard** for the business. This guide covers both, plus the referral programme.

## What you'll need

- The Lumina app on a phone or tablet
- Your **Sales PIN** or your personal **Installer PIN**
- A few minutes at the start of the day on the Overview and Pipeline tabs

---

## 1. The two-tier model

| Tier | Who holds it | What it opens |
|---|---|---|
| **Dealership** | You, the principal | The Dealer Dashboard for your dealer code |
| **Staff** | Each rep and installer | Their own PIN, scoped to your dealership |

Every PIN is scoped to your dealer code, so a rep sees your jobs and only your jobs.

### Getting in

Two doors, both landing on the same PIN pad:

- **Five taps on the Lumina logo** on the sign-in screen.
- **Nex-Gen Professional Access → Installer**, on the account-linking screen.

Enter your PIN. Where you land depends on which PIN you used — a sales PIN opens **Sales Mode**, an
installer PIN opens **Installer Mode**, and both carry a **Dealer Dashboard** button.

> **Warning** — Five wrong attempts locks the pad for 30 seconds. Attempts are also rate-limited per
> minute across a network, so don't let a crew brute-force a forgotten PIN — ask your admin to look
> it up instead.

---

## 2. Sales Mode — the field workflow

**Sales Mode** opens on three cards — **Home Visit**, **Estimate**, **Handoff** — and three buttons:
**New Visit**, **My Estimates**, **Dashboard**.

### The visit, start to finish

**New Visit** is a three-step flow. Finish it on site, in front of the customer.

#### Step 1 — Prospect

Name, email, phone, city, state, ZIP, and **Salesperson Notes**. If they came in on a referral
code, enter it here — it validates live and tells you **Code accepted** or **Code not found**.

> **Note** — Enter the referral code at this step, not later. This is what links the reward to the
> person who sent them, and it drives the referrer's status updates automatically as the job
> progresses.

#### Step 2 — Zones

Build the system, zone by zone. **Add zone**, then for each one:

zone name · product type · diodes per foot · run length · corners in the zone · rail type ·
rail colour · connector run length · colour preset · zone notes · zone price

> **Note** — Walk the house and add a zone per elevation or per run as you go. It's faster than
> reconstructing it in the truck, and the run lengths and corner counts you capture here become the
> install blueprint your crew works from.

#### Step 3 — Review

Customer, totals, system configuration, and the two install dates:

- **Day 1 — Electrical pre-wire**
- **Day 2 — Install**

Day 2 must be after Day 1; the app enforces it. Sending the estimate sets the job to
*estimate sent* and updates the referrer's status if there was a code.

**Save draft** if you need to leave and come back.

### The estimate and the signature

**Estimate** renders the customer-facing document from the zones you built. You can copy a link to
it to send.

**Sign** captures the customer's signature on the device. Once signed, the job flips to *signed* —
and that single action is what dispatches the work:

1. The job appears in the **Day 1 Queue** for electrical pre-wire.
2. The Day 2 team is notified.
3. Install reminders are scheduled automatically.

> **Note** — The signature is the trigger for the whole install chain. An estimate that's verbally
> agreed but unsigned dispatches nothing. Get the signature on site.

---

## 3. The Dealer Dashboard

Six tabs.

### Overview

The start-of-day screen: live job counts, what's moving, and what's waiting on someone.

### Pipeline

Every job on your dealer code and what stage it's at — visit, estimate sent, signed, Day 1, Day 2,
complete. This is where follow-ups come from. A job sitting at *estimate sent* for a week is a phone
call, and the Pipeline tab is the only place that shows you it's stalled.

### Team

Your installers and reps, who's active, and their workload.

> **Warning** — **The Team tab is admin-only.** If you signed in with an installer or sales PIN
> you'll see *"Team roster is admin-only."* Installer records contain sign-in credentials, so they're
> restricted to admin and owner sessions. Ask your dealer admin to view or change the roster. The
> active-installer count on Overview is suppressed for the same reason and shows a dash.

With an admin session, **Manage team** opens the roster, where you can add installers, deactivate
them, and filter by dealer.

> **Warning** — After adding an installer, **have them test their PIN before you dispatch them to a
> job.** A newly-added installer record may need a role value set that the add form doesn't currently
> capture, and the symptom is a PIN that simply won't sign in. Catch it in the office, not in a
> customer's driveway. If it happens, email **support@Nex-GenLED.com** with the dealer code and the
> installer's PIN and we'll repair the record.

### Payouts

Referral payouts in three sections: pending, approved and awaiting fulfilment, and fulfilled.
Work top down — anything sitting in *approved* is a commitment you've made that hasn't been
delivered yet.

### Inventory

| Section | Status |
|---|---|
| **On Hand** | Live. Current dealership stock; tap an item to record a received order |
| **Committed to active jobs** | Not yet available — shows an *"Inventory bridge required"* card |
| **Available** | Not yet available; depends on the section above |
| **Waste Intelligence** | Live. Built from actual material usage on completed installs |
| **Reorder suggestions** | Not yet available |

> **Note** — **Waste Intelligence is the one to actually read.** It compares what your crews
> estimated against what they consumed on completed jobs, and needs at least three completed jobs
> before it will show a trend. It's the fastest way to find a crew that's consistently over-cutting.

> **Warning** — Automatic stock movement isn't live yet. Recording received orders under **On Hand**
> works, but stock is not decremented automatically as jobs are installed. Keep your authoritative
> count wherever you keep it today, and treat On Hand as a working figure until the remaining
> sections come online.

### Messaging

Your dealership's message configuration — the templates and notifications that go out to customers
as jobs move.

---

## 4. Referral Rewards

Customers refer, and the app tracks it end to end.

**How it flows:** a customer shares their code from **System → Refer a Friend** → your rep enters it
at Step 1 of a new visit → the referrer's status updates automatically when the estimate is sent and
again when it's signed → the reward appears on your **Payouts** tab for approval.

Your own dealership code and the codes issued to your customers are visible from the dashboard.
Ambassador tiers escalate as a customer refers more successfully.

> **Note** — The one manual link in the chain is entering the code at Step 1. If a rep forgets, the
> referrer is never credited and there's no automatic way to reattach it later. Make it part of the
> visit script.

---

## 5. Running the day

**Morning, five minutes:**

1. **Overview** — what changed overnight.
2. **Pipeline** — anything stalled at *estimate sent*? Those are today's calls.
3. **Day 1 / Day 2 queues** — is every dispatched job assigned to someone who knows it's theirs?
4. **Payouts** — clear anything sitting in *approved*.

**Weekly:**

- **Waste Intelligence**, once you have a few completed jobs.
- Team roster — deactivate anyone who's left. A live PIN is access to customer systems.

---

## 6. Troubleshooting

### A rep's PIN won't sign in

Confirm the PIN with your admin, and confirm the installer record is active. A brand-new record may
need repair — see the Team section above.

### A signed job never reached the Day 1 Queue

Confirm the signature actually captured — the job status should read *signed*, not *estimate sent*.
If it's stuck at *estimate sent*, the signature step didn't complete; re-open the estimate and sign
it again.

### A customer says they never got their account

Two common causes: a typo in the email at Step 1, or the install wrap-up's account step was skipped.
Both are recoverable — the installer can create the account from the Day 2 wrap-up, or re-run setup.

### A customer can sign in but has no lights

The controllers were never linked to their account. The installer needs to re-run the eight-step
setup wizard. See the *Installer Guide*.

### A referral wasn't credited

The code has to be entered at Step 1 of the visit. If it was missed, email
**support@Nex-GenLED.com** with the two customers' emails and the job, and we'll look at it.

---

## 7. Quick reference

| Detail | Value |
|---|---|
| PIN length | 4 digits |
| Lockout | 5 attempts → 30 seconds |
| Dashboard tabs | Overview · Pipeline · Team · Payouts · Inventory · Messaging |
| Team tab | Admin and owner sessions only |
| Visit flow | Prospect → Zones → Review → Estimate → Signature |
| Dispatch trigger | The customer's signature |
| Product warranty | 5 years |
| Labor warranty | 1 year minimum — your dealership may extend it |
| Rated service life | 50,000 hours |

> **Warning** — **Never say "lifetime warranty," and don't let a rep say it either.** The rated
> 50,000-hour service life describes how long the diodes last. The covered terms are five years on
> the product and a one-year minimum on labor. Getting this wrong creates a warranty expectation
> your dealership has to honour.

---

## 8. Support

Email **support@Nex-GenLED.com**. Include your dealer code, and for anything job-specific the
customer's email and the stage it's stuck at.

---

<div class="mantra">THE SYSTEM IS THE DIFFERENCE.</div>

**Nex-GenLED.com**
