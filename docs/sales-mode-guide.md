# Lumina Sales Mode — Complete Guide

**Audience:** Dealers and sales representatives in the field

This guide walks you through every step of using Sales Mode, from logging in to handing off a signed job to your install crew.

---

## 1. Accessing Sales Mode

Sales Mode lives behind a **4-digit PIN**. The first two digits identify your **dealer**; the last two digits identify the **salesperson**.

### How to log in
1. Open the Lumina app.
2. From the main launch screen, tap **Sales Mode**.
3. Enter your 4-digit code on the keypad. The first two dots will turn **violet** (dealer) and the last two will turn **cyan** (salesperson) so you can see at a glance which half you're typing.
4. The session starts automatically as soon as the 4th digit is entered.

### Lockout
- You get **5 attempts**. After the 5th failed attempt the keypad locks and you'll need to restart the app.
- The screen will tell you exactly how many attempts you have left after each miss.

### Session timeout
- Your session stays active for **30 minutes** of activity.
- A warning will appear **5 minutes before** the session ends so you can extend it without losing work.
- Tap any button or scroll to reset the timer. Timing out logs you out cleanly and clears any draft job — sign back in to pick up where you left off (drafts are saved to the cloud, not lost).

---

## 2. Sales Landing Screen

After you log in you'll land on the Sales Mode home screen. You'll see three primary actions:

| Button | What it does |
|---|---|
| **New Visit** | Starts a brand-new prospect from scratch — this is the start of every estimate. |
| **My Estimates** | Opens your job list. Use this to find existing prospects, see job status, or resume a draft. |
| **Dashboard** | Opens your Dealer Dashboard (inventory, messaging settings, etc.). |

The screen also shows three informational cards (Home Visit, Estimate, Handoff) that summarize the workflow for new salespeople.

To leave Sales Mode at any time, tap **Exit** in the top-right corner.

---

## 3. Creating a New Prospect

Tap **New Visit** to begin. This opens the **Step 1 of 3 — Customer info** screen with a progress bar at the top.

### Customer fields (all required unless noted)

| Field | What it's used for |
|---|---|
| **First Name** | Used in every customer email and SMS. |
| **Last Name** | Shown on the estimate, signed contract, and job cards. |
| **Email** | Where the booking confirmation, account invite, and "system is live" emails go. Validated for proper email format. Stored as lowercase. |
| **Phone** | Where every SMS reminder goes (Day 1 confirmation, Day 1 reminder, Day 2 confirmation, Day 2 reminder, "wiring complete" notification). Auto-formatted as `(123) 456-7890`. |
| **Address** | Type the street address — an autocomplete dropdown will pop up. Tap a suggestion and **City**, **State**, and **Zip** will fill in for you. |
| **City** | Auto-filled by the address picker. Editable. |
| **State** | 2-letter abbreviation, auto-filled. Editable. |
| **Zip** | 5 digits, auto-filled. Editable. |
| **Referral code** *(optional)* | If the customer was referred, type the LUM-XXXX code. The app checks it in real time — green checkmark = valid, red X = not found. The referrer gets credit automatically once the customer signs. |
| **Salesperson Notes** *(optional)* | Free text for things like gate code, dog warning, "park in driveway", etc. The install crew will see these notes. |

### Home photos
Below the form, a horizontal **Home photos** strip lets you add up to **6 photos** of the home exterior.

- Tap **Add photo** to open the gallery picker.
- Each photo uploads immediately to the job's secure cloud folder.
- You can remove a photo by tapping the **X** in its corner.
- Photos taken here become part of the prospect record. The blueprint background photo is captured separately in the wizard.

### Continuing
Tap **Continue to zones →**. The app will:
1. Validate every required field.
2. Save the prospect to a new draft job in the cloud.
3. If you typed a valid referral code, mark the referral as "visit scheduled".
4. Open the Estimate Wizard.

---

## 4. The Estimate Wizard — 5 Steps

The wizard is the heart of every site visit. It collects everything the install crew needs to do their job and everything the customer needs to see on their estimate.

You can leave the wizard at any time and resume later — your progress is saved continuously.

### Step 1: Home Photo

**Goal:** Capture the primary photo of the front of the home.

This photo becomes the **blueprint background** that the Day 1 electrician and Day 2 install team will work from. The channel runs you draw later will be overlaid on this image.

**What to do:**
1. Tap **Capture or choose photo**.
2. Pick a clean, well-framed shot showing the **entire front of the home** with the rooflines clearly visible.
3. The photo uploads automatically. A green **Saved** checkmark confirms it's stored.
4. Tap **Continue →**. (If you skip the photo, the button reads **Skip for now →** — you can add the photo later from the job detail screen, but the install crew prefers having it.)

### Step 2: Controller Placement

**Goal:** Tell the electrician exactly where the WLED controller will mount.

This is where the brain of the lighting system lives. The Day 1 electrician will run all wiring back to this single point.

**Fields to fill:**

| Field | Notes |
|---|---|
| **Location description** | **Required.** Be specific: "Garage left interior wall, 3 feet from breaker panel" is far better than "garage". The electrician relies on this. |
| **Mount type** | Tap **Interior** or **Exterior**. Interior is the default and is preferred whenever possible. |
| **Distance to nearest outlet (ft)** | Optional but very helpful. The electrician uses this to plan whether a new outlet is needed. |

**Photo:**
- Tap **Capture photo** (or **Replace photo**) to take a picture of the proposed mount location.
- A photo here makes Day 1 dramatically faster — the electrician can verify the spot before they even arrive.

Tap **Continue →** when you're done. The button is disabled until you've entered a location description.

### Step 3: Channel Setup

**Goal:** Define every continuous LED strip "run" on the home.

#### What is a channel?
A **channel** is one continuous LED strip wired to one output port on the WLED controller. A typical home has 1–4 channels — for example:
- Channel 1: Front roofline
- Channel 2: Garage roofline
- Channel 3: Side accent
- Channel 4: Back patio

Each channel must be a single unbroken physical run. If the LEDs make a corner, that's still one channel. If they restart somewhere else on the house, that's a separate channel.

#### Adding a channel
1. Tap **Add channel**. A bottom sheet opens.
2. Fill in the fields:

| Field | What it means |
|---|---|
| **Channel number** | Auto-assigned (1, 2, 3...). Read-only. |
| **Label** | A human-readable name like "Front Roofline" or "Garage Eaves". |
| **Linear feet** | The total length of this run, measured in feet. Round up. |
| **Start description** | Where this run begins — "Left corner of house, ground level". |
| **End description** | Where this run ends — "Right corner above garage". |
| **Direction** | Which way the strip is fed when installed. Pick **Left → Right**, **Right → Left**, **Top → Bottom**, or **Bottom → Top**. The Day 2 install team relies on this. |
| **Start photo** *(optional)* | A close-up of the starting point. |
| **End photo** *(optional)* | A close-up of the ending point. |

3. Tap **Save**.

The new channel appears as a card in the list. You can:
- **Tap a card** to edit it.
- **Swipe a card left** to delete it.

You must add **at least one channel** to continue. The **Continue →** button stays disabled until you have one.

### Step 4: Power Injection Points

**Goal:** Add power injection points for any channel longer than 100 feet.

#### What is power injection?
LED strips lose voltage as the run gets longer — the LEDs at the far end will be dimmer or color-shifted than those near the controller. To fix this, you "inject" extra power partway down the run via a separate wire from the controller (or from a supplemental power supply).

#### The 100-foot rule
**Any channel longer than 100 feet must have at least one injection point.** The wizard will warn you in Step 5 if any of your channels are over 100 feet without injection.

A general guideline:
- 100–200 ft: 1 injection point at the midpoint
- 200–300 ft: 2 injection points (1/3 and 2/3)
- 300+ ft: 3+ injection points

#### Adding an injection point
1. Find the channel section you want to add an injection to.
2. Tap **Add injection point** under that channel. A bottom sheet opens.
3. Fill in the fields:

| Field | What it means |
|---|---|
| **Channel run** | Read-only — confirms which channel this injection belongs to. |
| **Location description** | Where on the run the injection lives. "Corner of deck, behind downspout" |
| **Distance from start** | How many feet from the start of the run. The wizard uses this to compute the wire gauge. |
| **Outlet status** | Tap **Has nearby outlet** if there's an existing outlet within reach, or **New outlet needed** if the electrician will need to run one. |
| **Distance to outlet** | Only shown if you picked "Has nearby outlet". |
| **Photo** *(optional)* | A picture of the injection location. |

4. The **wire gauge** field auto-calculates based on the distance from the controller mount:
   - **Direct** — 0 feet
   - **14/2** — up to 30 ft
   - **12/2** — up to 90 ft
   - **10/2** — up to 140 ft
   - **EXCEEDS 140ft** — over 140 ft (this is a warning — the electrician may need to relocate the controller)

5. Tap **Save injection**.

Each injection appears as a card under its channel. You can edit by tapping or delete by swiping.

Tap **Continue →** to move on. Injection points are technically optional but the Step 5 review will flag any over-100ft channels that don't have one.

### Step 5: Summary and Generate Estimate

**Goal:** Review everything and generate the priced estimate.

You'll see read-only summary cards for:
- **Home photo** — captured or not captured
- **Controller location** — description, interior/exterior, distance to outlet
- **Channels & footage** — total channels, total linear feet, total injections
- **Channel breakdown** — every channel listed with its footage, direction, and injection count

**Warnings appear in amber** if anything is missing or out of spec:
- "No home photo — blueprint will be text-only"
- "No controller mount location set"
- "Controller location has no photo"
- "Channel N (X ft) is over 100ft and has no injection point"

You can scroll back to fix any of these by tapping the corresponding step at the top of the screen.

When you're satisfied, tap **Generate Estimate →**.

The app will:
1. Save your wizard work to the cloud.
2. Pull your dealer's pricing rules.
3. Build the priced line items (LED strip, controller, power, hardware, labor).
4. Open the **Estimate Preview** screen.

---

## 5. Reviewing the Estimate with the Customer

The **Estimate Preview** screen is what you show the customer. It's designed to look like a professional quote.

### What's on the screen
- **Header:** "NEX-GEN LED — Custom lighting estimate", with the job number and a "Valid 30 days" note.
- **Customer name and address** in bold at the top.
- **Referral badge** (cyan with a gift card icon) if the customer was referred — shows who referred them.
- **Line items grouped by category:**
  - **LED STRIP** — strip footage and per-foot price
  - **CONTROLLER** — the WLED brain
  - **POWER** — wire, supplies, injection connectors
  - **HARDWARE** — mounting clips, brackets
  - **LABOR** — install labor
- **Subtotals** for materials and labor.
- **Total estimate** in very large bold text at the bottom.
- **What's included** static feature list: Permanent mount, App-controlled, Holiday-ready, Dusk to dawn, 1-year warranty.

### Walking the customer through it
Take your time here. Highlight the line items so the customer understands what they're paying for. Point out the **What's included** section — the recurring app, dusk-to-dawn automation, and warranty are usually the strongest differentiators.

### Sharing the estimate
Tap **Share with customer** to copy a unique estimate link to your clipboard. You can paste this into a text or email if the customer wants a copy to think about before signing.

When the customer is ready to sign, tap the same **Generate Estimate** flow forward to the signature screen, or use the dedicated signature route from the bottom of the preview.

---

## 6. Customer Signature

The **Signature** screen is where the customer formally approves the job.

### What the customer sees
- A large **Approve your estimate** heading
- Their name and the **grand total** in cyan
- A scrollable summary of the estimate
- A **signature canvas** (white box) where they draw their signature with a finger
- Boilerplate terms text below the canvas

### How to capture the signature
1. Hand the device to the customer.
2. Have them sign in the white canvas area.
3. If they make a mistake, tap **Clear** and try again.
4. The **Approve & confirm** button only becomes active once a signature is present.
5. The customer (or you) taps **Approve & confirm**.

### What happens next (automatically)
The moment the signature is approved, the app:
1. Saves the signature image to the job's cloud folder.
2. Moves the job status to **Signed (`estimateSigned`)**.
3. Records the timestamp of the signature.
4. If the job had a valid referral code, marks the referral as "confirmed" — the referrer's credit is now locked in.
5. Sends the customer a **booking confirmation email** explaining the 2-day install process. (See the messaging guide for the exact wording.)
6. Drops the job into your dealer's **Day 1 Queue** so the electrician can pick it up.
7. Returns you to the Sales Landing screen.

You'll see a green confirmation: **"Estimate approved — install is confirmed"**.

---

## 7. The Job Status Pipeline

Every job moves through a sequence of statuses as it progresses. Here's the full pipeline in plain English:

| Status | Plain-English meaning | Who owns it next |
|---|---|---|
| **Draft** | Estimate is being built but not yet generated or signed. | The salesperson — finish the wizard. |
| **Estimate sent** | Estimate has been generated and shared with the customer but not yet signed. *(Used in legacy flows; the wizard usually goes straight to Signed.)* | The salesperson — follow up. |
| **Signed** | Customer has signed. Job is officially booked. Booking email goes out. | The Day 1 electrician — schedule the visit. |
| **Pre-wire scheduled** | Day 1 has been scheduled. Day 1 confirmation SMS goes out. | The Day 1 electrician — show up and do the work. |
| **Pre-wire complete** | Day 1 is done. Wires are run. "Wiring complete" SMS goes out. | The Day 2 install team — schedule the visit. |
| **Install scheduled** | Day 2 has been scheduled. Day 2 confirmation SMS goes out. | The Day 2 install team — show up and install. |
| **Install complete** | Job is fully done. Customer welcome email with app download links goes out. Customer's Lumina account is created. | Nobody — the job is closed. |

Each status moves the job between queues automatically. You don't need to manually advance statuses unless something goes wrong (the **Job Detail** screen has manual buttons for those rare cases).

---

## 8. The My Estimates Screen

Tap **My Estimates** from the Sales Landing screen (or the **+** floating action button to start a new visit from this screen).

### Filter chips
A horizontal row of chips lets you narrow the list:

- **All** — every job for your dealer
- **Draft** — gray
- **Sent** — violet
- **Signed** — cyan
- **Pre-wire** — amber
- **Complete** — green

Tap a chip to filter. Tap **All** to clear.

### What each card shows

| Card element | Meaning |
|---|---|
| **Customer name** (bold, large) | Who the job is for |
| **Job number** (right-aligned) | Auto-generated — looks like `NXG-20260409-001` |
| **Address** | Street + city, ellipsized if long |
| **Status pill** (left, color-coded) | Where the job is in the pipeline |
| **Total price** (right, green) | The signed estimate total |
| **Progress bar** (bottom) | Visual fill from 0% (draft) to 100% (install complete) |

Tap any card to open the **Job Detail** screen, which shows the full job info with manual status-advance buttons (only use these if a job is stuck — see the Full Job Lifecycle doc for recovery procedures).

### Empty state
If you have no jobs yet, you'll see a large receipt icon and a **Start a new visit** button.

---

## Quick Reference: First Visit Checklist

When you arrive at a new prospect's home, this is the order to work through:

1. **Take exterior photos** of the home — at least one clean shot of the front, plus close-ups of any tricky areas.
2. **Walk the perimeter** with the customer. Identify which surfaces will get LEDs.
3. **Find the controller location** — pick a spot near an outlet, ideally interior, ideally in the garage.
4. **Measure each channel** with a wheel or laser. Round up.
5. **Note injection point candidates** for any run that's clearly over 100 feet.
6. **Sit down with the customer** and walk them through the wizard live. Show them the price as it builds.
7. **Hand them the device** to sign.
8. Done. The booking email goes out automatically.

---

**Need help?** Reach out to your Nex-Gen LED corporate contact or check the support resources in the Dealer Dashboard.
