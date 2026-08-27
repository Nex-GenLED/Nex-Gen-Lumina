# Lumina Sales Mode — Complete Guide

**Describes Lumina app version 2.5.10+88.**

**Audience:** Dealers and sales reps running site visits.

Sales Mode is the app you live in on a home visit. Walk the perimeter, build a complete priced estimate in 15 minutes, collect a signed contract before you leave. Every signed job flows straight into your dealer's Day 1 Queue — no paperwork, no double entry, no lag. Permanent residential and commercial lighting that works as hard as you do, and Sales Mode is how you close faster and hand off cleaner.

## What you'll need

- The Lumina app on your phone or tablet
- Your **4-digit Sales PIN** (first 2 digits = dealer code, last 2 = salesperson code)
- The customer's address and contact info
- A working camera and a measuring wheel or laser for channel lengths
- Phone signal or Wi-Fi on-site — estimates save to the cloud continuously

---

## 1. Getting in

Sales Mode is gated behind a 4-digit PIN. First two digits identify your **dealer**; last two identify you as the **salesperson**.

1. Open the Lumina app
2. Tap the **Lumina logo** 5 times (within 3 seconds) on the login screen to open the Staff PIN screen
3. Type your 4-digit code. The first two dots turn **violet** (dealer) and the last two turn **cyan** (salesperson) so you can see which half you're typing.
4. The session starts automatically as soon as the 4th digit is entered

### Lockout

- **5 attempts.** The 5th miss locks the keypad and you'll need to restart the app.
- The screen tells you exactly how many attempts you have left after each miss.

### Session timeout

- Sessions run **30 minutes** of activity
- A warning appears **5 minutes before** the session ends so you can extend without losing work
- Tap any button or scroll to reset the timer
- Timing out logs you out cleanly. Drafts are saved to the cloud — sign back in to pick up where you left off.

---

## 2. The Sales Landing screen

After you log in, the Sales Mode home screen gives you three primary actions:

| Button | What it does |
|---|---|
| **New Visit** | Start a brand-new prospect from scratch — how every estimate begins. |
| **My Estimates** | Your job list. Use it to find existing prospects, check job status, or resume a draft. |
| **Dashboard** | Opens your Dealer Dashboard (inventory, messaging settings, etc.). |

Three informational cards below (Home Visit, Estimate, Handoff) summarize the workflow for new salespeople.

To leave Sales Mode any time, tap **Exit** in the top-right.

---

## 3. Creating a new prospect

Tap **New Visit**. This opens **Step 1 of 3 — Customer info** with a progress bar at the top.

### Customer fields (all required unless noted)

| Field | What it's used for |
|---|---|
| **First Name** | Used in every customer email and SMS |
| **Last Name** | Shown on the estimate, signed contract, and job cards |
| **Email** | Where the booking confirmation, account invite, and "system is live" emails go. Validated for proper email format. Stored as lowercase. |
| **Phone** | Where every SMS reminder goes (Day 1 confirmation, Day 1 reminder, Day 2 confirmation, Day 2 reminder, "wiring complete" notification). Auto-formatted as `(123) 456-7890`. |
| **Address** | Type the street address — an autocomplete dropdown pops up. Tap a suggestion and **City**, **State**, and **Zip** fill in for you. |
| **City** | Auto-filled. Editable. |
| **State** | 2-letter abbreviation, auto-filled. Editable. |
| **Zip** | 5 digits, auto-filled. Editable. |
| **Referral code** *(optional)* | If the customer was referred, type the LUM-XXXX code. The app checks it in real time — green checkmark = valid, red X = not found. The referrer gets credit automatically once the customer signs. |
| **Salesperson Notes** *(optional)* | Free text for gate codes, dog warnings, "park in driveway," etc. The install crew sees these. |

### Home photos

Below the form, a horizontal **Home photos** strip lets you add up to **6 photos** of the home exterior.

- Tap **Add photo** to open the gallery picker
- Each photo uploads immediately to the job's secure cloud folder
- Remove a photo by tapping the **X** in its corner
- Photos taken here become part of the prospect record. The blueprint background photo is captured separately in the wizard.

### Continuing

Tap **Continue to zones →**. The app will:

1. Validate every required field
2. Save the prospect to a new draft job in the cloud
3. If you typed a valid referral code, mark the referral as "visit scheduled"
4. Open the Estimate Wizard

---

## 4. The Estimate Wizard — 5 steps

The wizard is the heart of every site visit. It collects everything the install crew needs to do their job and everything the customer needs to see on their estimate.

Leave the wizard any time and resume later — progress is saved continuously.

### Step 1 — Home photo

**Goal:** capture the primary photo of the front of the home.

This photo becomes the **blueprint background** that the Day 1 electrician and Day 2 install team work from. The channel runs you draw later will be overlaid on this image.

1. Tap **Capture or choose photo**
2. Pick a clean, well-framed shot showing the **entire front of the home** with the rooflines clearly visible
3. The photo uploads automatically. A green **Saved** checkmark confirms it's stored.
4. Tap **Continue →**. (If you skip the photo, the button reads **Skip for now →** — you can add it later from the job detail screen, but the install crew prefers having it.)

### Step 2 — Controller placement

**Goal:** tell the electrician exactly where the controller will mount.

This is where the brain of the lighting system lives. The Day 1 electrician runs all wiring back to this single point.

**Fields:**

| Field | Notes |
|---|---|
| **Location description** | **Required.** Be specific: "Garage left interior wall, 3 feet from breaker panel" beats "garage" every time. The electrician relies on this. |
| **Mount type** | **Interior** or **Exterior**. Interior is the default and is preferred whenever possible. |
| **Distance to nearest outlet (ft)** | Optional but helpful. The electrician uses this to plan whether a new outlet is needed. |

**Photo:**

- Tap **Capture photo** (or **Replace photo**) to take a picture of the proposed mount location
- A photo makes Day 1 dramatically faster — the electrician can verify the spot before they arrive

Tap **Continue →** when done. The button is disabled until you've entered a location description.

### Step 3 — Channel setup

**Goal:** define every continuous LED strip run on the home.

#### What is a channel?

A **channel** is one continuous LED strip wired to one output port on the controller. A typical home has 1–4 channels:

- Channel 1: Front roofline
- Channel 2: Garage roofline
- Channel 3: Side accent
- Channel 4: Back patio

Each channel must be a single unbroken physical run. If the LEDs turn a corner, that's still one channel. If they restart somewhere else on the house, that's a separate channel.

> **Channels are also how the customer will control their house.** In the app, a schedule or a design can target specific channels rather than the whole run. That capability is derived from the controller's hardware channel configuration, which in turn reflects the channels you define here. A home you quote as one long channel gives the customer nothing to scope — so if a customer talks about wanting "just the garage on a timer," that is a reason to split the run, and worth noting for the install crew.

#### Adding a channel

1. Tap **Add channel** — a bottom sheet opens
2. Fill in the fields:

| Field | What it means |
|---|---|
| **Channel number** | Auto-assigned (1, 2, 3…). Read-only. |
| **Label** | A human-readable name like "Front Roofline" or "Garage Eaves". |
| **Linear feet** | The total length of this run, in feet. Round up. |
| **Start description** | Where this run begins — "Left corner of house, ground level". |
| **End description** | Where this run ends — "Right corner above garage". |
| **Direction** | Which way the strip is fed when installed. Pick **Left → Right**, **Right → Left**, **Top → Bottom**, or **Bottom → Top**. The Day 2 install team relies on this. |
| **Start photo** *(optional)* | A close-up of the starting point. |
| **End photo** *(optional)* | A close-up of the ending point. |

3. Tap **Save**

The new channel appears as a card. You can:

- **Tap a card** to edit it
- **Swipe a card left** to delete it

Add **at least one channel** to continue. The **Continue →** button stays disabled until you have one.

### Step 4 — Power injection points

**Goal:** add power injection points for any channel longer than 100 feet.

#### What is power injection?

LED strips lose voltage as the run gets longer — the LEDs at the far end will be dimmer or color-shifted than those near the controller. To fix it, you "inject" extra power partway down the run via a separate wire from the controller (or a supplemental power supply).

#### The 100-foot rule

**Any channel longer than 100 feet must have at least one injection point.** The wizard will warn you in Step 5 if any channel is over 100 feet without injection.

General guideline:

- **100–200 ft** — 1 injection point at the midpoint
- **200–300 ft** — 2 injection points (1/3 and 2/3)
- **300+ ft** — 3+ injection points

#### Adding an injection point

1. Find the channel section you want to add an injection to
2. Tap **Add injection point** under that channel — a bottom sheet opens
3. Fill in the fields:

| Field | What it means |
|---|---|
| **Channel run** | Read-only — confirms which channel this injection belongs to. |
| **Location description** | Where on the run the injection lives. "Corner of deck, behind downspout" |
| **Distance from start** | How many feet from the start of the run. The wizard uses this to compute the wire gauge. |
| **Outlet status** | **Has nearby outlet** if there's an existing outlet within reach, or **New outlet needed** if the electrician will need to run one. |
| **Distance to outlet** | Only shown if you picked "Has nearby outlet". |
| **Photo** *(optional)* | A picture of the injection location. |

4. The **wire gauge** field auto-calculates based on distance from the controller mount:
   - **Direct** — 0 feet
   - **14/2** — up to 30 ft
   - **12/2** — up to 90 ft
   - **10/2** — up to 140 ft
   - **EXCEEDS 140ft** — over 140 ft (warning — the electrician may need to relocate the controller)

5. Tap **Save injection**

Each injection appears as a card under its channel. Tap to edit, swipe to delete.

Tap **Continue →** to move on. Injection points are technically optional, but the Step 5 review will flag any over-100ft channels that don't have one.

### Step 5 — Summary and generate estimate

**Goal:** review everything and generate the priced estimate.

Read-only summary cards for:

- **Home photo** — captured or not captured
- **Controller location** — description, interior/exterior, distance to outlet
- **Channels & footage** — total channels, total linear feet, total injections
- **Channel breakdown** — every channel listed with its footage, direction, and injection count

**Warnings appear in amber** if anything is missing or out of spec:

- "No home photo — blueprint will be text-only"
- "No controller mount location set"
- "Controller location has no photo"
- "Channel N (X ft) is over 100ft and has no injection point"

Scroll back and fix any of these by tapping the corresponding step at the top of the screen.

When you're satisfied, tap **Generate Estimate →**. The app will:

1. Save your wizard work to the cloud
2. Pull your dealer's pricing rules
3. Build the priced line items (LED strip, controller, power, hardware, labor)
4. Open the **Estimate Preview** screen

---

## 5. Reviewing the estimate with the customer

The **Estimate Preview** screen is what you show the customer. Designed to look like a professional quote.

### What's on the screen

- **Header** — "Custom lighting estimate", with the job number and a "Valid 30 days" note (`Est #NXG-…  ·  Valid 30 days`)
- **Customer name and address** in bold at the top
- **Referral badge** (cyan with a gift card icon) if the customer was referred — shows who referred them
- **Line items grouped by category:**
  - **LED STRIP** — strip footage and per-foot price
  - **CONTROLLER** — the brain of the system
  - **POWER** — wire, supplies, injection connectors
  - **HARDWARE** — mounting clips, brackets
  - **LABOR** — install labor
- **Subtotals** for materials and labor
- **Total estimate** in very large bold text at the bottom
- **What's included** — a static four-item list:
  - Professional 2-day installation
  - Nex-Gen Lumina app — full color control, scheduling, scenes
  - Permanent weatherproof hardware — no seasonal removal
  - Lifetime dealer support and warranty

Individual line items also carry short feature chips (Permanent mount, App-controlled, Holiday-ready, Dusk to dawn). Those are per-item labels, not the included list — don't read them out as the warranty terms.

> **Warranty terms — say these exact words.**
>
> - **Product warranty: 5 years.**
> - **Labor warranty: 1 year minimum** — your dealership may extend it.
> - **Expected service life: rated 50,000 hours** — 20+ years at typical evening use. *This is what "lifetime" lighting means.*
>
> **Never say "lifetime warranty."**
>
> The **What's included** list on this screen currently reads *"Lifetime dealer support and warranty."* That wording is wrong and is being corrected. Until the app is updated, **read the terms above out loud instead** — do not let the on-screen line stand as the quote.

### Walking the customer through it

Take your time. Highlight the line items so the customer understands what they're paying for. Point out the **What's included** section — the included app, the 2-day professional install, and the permanent weatherproof hardware are usually the strongest differentiators.

### Common customer questions

**"So is it a lifetime warranty?"**
No — "lifetime" describes how long the lights last, not how long they're covered. The LEDs are rated for 50,000 hours, which is 20+ years at typical evening use; the warranty is 5 years on the product and a minimum of 1 year on labor.

**"What does the app actually do?"**
Full color control, scheduling (including per-channel schedules and more than one event in a day), saved designs they can apply, rename and duplicate, and automatic game-day lighting for their teams — with a celebration effect that fires when their team scores.

### Sharing the estimate

Tap **Share with customer** to copy a unique estimate link to your clipboard. Paste it into a text or email if the customer wants a copy before signing.

When the customer is ready to sign, continue forward to the signature screen.

---

## 6. Customer signature

The **Signature** screen is where the customer formally approves the job.

### What the customer sees

- A large **Approve your estimate** heading
- Their name and the **grand total** in cyan
- A scrollable summary of the estimate
- A **signature canvas** (white box) where they draw their signature with a finger
- Boilerplate terms text below the canvas

### Capturing the signature

1. Hand the device to the customer
2. Have them sign in the canvas area
3. If they make a mistake, tap **Clear** and try again
4. **Approve & confirm** only becomes active once a signature is present
5. The customer (or you) taps **Approve & confirm**

### What happens next (automatically)

The moment the signature is approved, the app:

1. Saves the signature image to the job's cloud folder
2. Moves the job status to **Signed (`estimateSigned`)**
3. Records the timestamp of the signature
4. If the job had a valid referral code, marks the referral as "confirmed" — the referrer's credit is locked in
5. Sends the customer a **booking confirmation email** explaining the 2-day install process
6. Drops the job into your dealer's **Day 1 Queue**
7. Returns you to the Sales Landing screen

You'll see a green confirmation: **"Estimate approved — install is confirmed"**.

---

## 7. The deposit — the one thing signing does NOT do

<div>

> **Read this section. It is the single most common reason a job you closed never gets installed.**

</div>

Signing the estimate does not collect any money, and **the job cannot be scheduled for Day 1 until a 50% deposit is marked collected.** Until then, the electrician opening the Day 1 Queue sees a deposit banner where the **Schedule Day 1** button would be. There is no way to schedule around it.

The customer is sent **nothing** about this. From their side, a job held at the deposit gate looks exactly like a booked job nobody has gotten to yet — which means the first person to notice is usually the customer, calling to ask when someone is coming.

**What to do:**

- Know your dealership's process. Somebody has to collect the deposit and mark it on the job — the rep, the office, or the electrician on arrival. Find out which, and don't assume.
- Tell the customer about the deposit at signing, while you're still in the home. It is far easier there than on a follow-up call.
- Check your own signed jobs periodically. A job sitting at **Signed** for more than a day or two is usually waiting on this.

When the deposit is marked, the app records the amount as a snapshot of 50% of the total **at that moment** — so a later price correction doesn't quietly rewrite what was collected.

There is a second gate at the end: after Day 2, confirming **final payment** moves the job to **Complete (paid)** and archives it out of the active queues.

---

## 8. The job status pipeline

Every job moves through a sequence of statuses. Here's the full pipeline.

| Status | Plain English | Who owns it next |
|---|---|---|
| **Draft** | Estimate is being built but not generated or signed | The salesperson — finish the wizard |
| **Estimate sent** | Estimate generated and shared with the customer but not yet signed. *(Legacy; the wizard usually goes straight to Signed.)* | The salesperson — follow up |
| **Signed** | Customer has signed. Job is booked. Booking email goes out. | **Whoever collects the deposit** — Day 1 cannot be scheduled until it's marked |
| **Pre-wire scheduled** | Day 1 has a date. Day 1 confirmation SMS goes out. | The Day 1 electrician — show up and do the work |
| **Pre-wire complete** | Day 1 is done. Wires are run. "Wiring complete" SMS goes out. | The Day 2 install team — schedule the visit |
| **Install scheduled** | Day 2 has a date. Day 2 confirmation SMS goes out. | The Day 2 install team — show up and install |
| **Install complete** | Job is fully done in the field. Customer welcome email with download links goes out. Customer's Lumina account is created. | Whoever collects the balance |
| **Complete (paid)** | Final payment collected. Job is archived out of the active queues. | Nobody — the job is closed |

Each status moves the job between queues automatically. You don't manually advance statuses unless something goes wrong (the **Job Detail** screen has manual buttons for those rare cases).

---

## 9. The My Estimates screen

Tap **My Estimates** from the Sales Landing screen (or the **+** floating action button to start a new visit from this screen).

### Filter chips

A horizontal row of chips narrows the list:

- **All** — every job for your dealer
- **Draft** — gray
- **Sent** — violet
- **Signed** — cyan
- **Pre-wire** — amber
- **Complete** — green

Tap a chip to filter. Tap **All** to clear.

> Note the chip set does not cover every status. **Install scheduled** and **Complete (paid)** have no chip of their own — use **All** to see those jobs. **Complete** filters on *install complete*, not on paid.

### What each card shows

| Element | Meaning |
|---|---|
| **Customer name** (bold, large) | Who the job is for |
| **Job number** (right-aligned) | Auto-generated — looks like `NXG-20260409-001` |
| **Address** | Street + city, ellipsized if long |
| **Status pill** (left, color-coded) | Where the job is in the pipeline |
| **Total price** (right, green) | The signed estimate total |
| **Progress bar** (bottom) | Visual fill from 0% (draft) to 100% (complete and paid) |

Tap any card to open the **Job Detail** screen — full job info, a **Download install plan PDF** action (the Day 1 and Day 2 task lists for that job), and manual status-advance buttons (only use if a job is stuck — see the Full Job Lifecycle doc for recovery procedures).

### Empty state

No jobs yet? You'll see a large receipt icon and a **Start a new visit** button.

---

## Quick reference — first-visit checklist

When you arrive at a new prospect's home, this is the order:

1. **Take exterior photos** — at least one clean shot of the front, plus close-ups of any tricky areas
2. **Walk the perimeter** with the customer. Identify which surfaces will get LEDs.
3. **Find the controller location** — near an outlet, ideally interior, ideally in the garage
4. **Measure each channel** with a wheel or laser. Round up.
5. **Note injection point candidates** for any run clearly over 100 feet
6. **Sit down with the customer** and walk them through the wizard live. Show them the price as it builds.
7. **Hand them the device** to sign
8. **Talk about the deposit before you leave** — 50%, and Day 1 can't be booked without it
9. Done. The booking email goes out automatically.

---

## What success looks like

- You finish the wizard on-site in 15 minutes or less
- The customer signs before you leave the home
- **The deposit is arranged before you leave the driveway** — this is what actually gets the job scheduled
- The job appears in the dealer's Day 1 Queue within seconds of signature
- The customer receives the booking confirmation email while you're still in the driveway
- The channel count, footage, injection points, and controller location on the estimate match what the install crew will actually find when they arrive

## If something isn't working

**"My PIN won't work."**
Confirm all 4 digits. Check that your dealer is active and that your salesperson account hasn't been deactivated — contact your dealer admin if unsure. 5 failed attempts locks the keypad; restart the app.

**"Photos aren't uploading."**
Check your phone signal or Wi-Fi. Photos upload the moment you capture them. If the upload icon keeps spinning, move to better coverage and retry — the app holds the capture until it succeeds.

**"The referral code shows red X."**
The code isn't valid. Double-check with the customer — LUM-XXXX format, 4 characters after the dash. If they insist the code is right, proceed without it and contact your dealer admin to investigate.

**"The Continue button is disabled."**
Every required field on the current step needs a value. Scroll through and look for amber warnings or empty required fields. Step 3 needs at least one channel. Step 2 needs a controller location description.

**"I can't get a clean signature on the canvas."**
Tap **Clear** and try again. A shaky line is fine — the signature just needs to be non-empty to unlock the **Approve & confirm** button.

**"I generated the estimate but the price looks wrong."**
Your dealer's pricing defaults fell back to something unexpected. Check the dealer pricing config in the Dealer Dashboard. If it still looks off, contact your dealer admin or Nex-Gen LED LLC — they can audit the pricing rule.

**"I left mid-wizard and lost my work."**
You didn't. Drafts save continuously to the cloud. Open **My Estimates**, find the customer, tap to resume.

**"My customer signed weeks ago and nobody has scheduled them."**
Check the deposit. A signed job with no deposit marked cannot be scheduled, and nothing notifies anyone that it's waiting. See Section 7.

**"The customer is asking about warranty terms."**
Product warranty is **5 years**. Labor warranty is **1 year minimum**, and your dealership may extend it. Expected service life is **50,000 hours** — 20+ years at typical evening use, which is what "lifetime" lighting means. **Never say "lifetime warranty."** The estimate screen's "What's included" line still reads "Lifetime dealer support and warranty"; that wording is being corrected — say the terms above instead. See Section 5.

---

**Need help?** Reach out to your Nex-Gen LED LLC corporate contact or check the support resources in the Dealer Dashboard.
