# Day 2 Install Team — Field Guide

**Audience:** Install techs running the Day 2 LED installation on a Lumina job.

Log in, read the blueprint, put up the strip, walk the customer through wrap-up, close the job. Day 2 is the last mile — get it right and the customer is live the same day.

## What you'll need

- Your 4-digit **Installer PIN** (dealer code + installer code)
- The Lumina app on your phone
- All materials from the Day 2 list — LED strip, mounting clips, brackets, connectors
- Your install tools
- Phone signal or Wi-Fi at the job site (required for check-offs, photo uploads, account creation)

---

## 1. Log in

Day 2 happens inside **Installer Mode**, gated by a 4-digit PIN.

### PIN format

- Digits 1–2: dealer code (e.g., `42`)
- Digits 3–4: installer code (e.g., `07`)
- Together: `4207`

You got this from your dealer admin at onboarding.

### Steps

1. Open the Lumina app
2. Tap the **Lumina logo** 5 times on the login screen — the Staff PIN screen opens
3. Type your 4-digit PIN

### Session timeout

- Sessions run **30 minutes** of activity
- Warning pops **5 minutes before** timeout — tap to extend
- Your work is always saved. If you get logged out, sign back in.

---

## 2. Open the Day 2 Queue

From the **Installer Landing** screen, tap **Day 2 Queue**.

### What's in it

Every job for your dealer that's had Day 1 completed and is ready for installation:

- **Pre-wire complete** (amber badge) — wiring done, Day 2 not scheduled yet
- **Install scheduled** (green badge) — Day 2 date locked in

### Card fields

| Element | Meaning |
|---|---|
| **Customer name** | Who the job is for |
| **Address** | Full street, city, state, zip |
| **Status badge** | Amber = Pre-wire complete, green = Install scheduled |
| **Day 2: {date}** | Shown only if scheduled |
| **Reschedule** | Inline button next to the date |
| **Schedule Day 2** | Shown only if not yet scheduled |

---

## 3. Schedule Day 2

For any **Pre-wire complete** job, tap **Schedule Day 2**.

1. Pick a date. Earliest = the day Day 1 was completed. Latest = 365 days out.
2. Tap **OK**.
3. Snackbar: **"Day 2 scheduled for {date}"**.

Job moves from **Pre-wire complete** to **Install scheduled**. Customer gets an SMS confirming the install date. Reminder SMS goes out the night before.

---

## 4. The Day 2 Blueprint

Tap any job card to open the **Day 2 Blueprint**.

### Different from Day 1

If you've worked Day 1 before, familiar but with key differences:

| Element | Day 1 | Day 2 |
|---|---|---|
| **Channel cards** | Wiring tasks | Install tasks with **"Wiring complete ✓"** badge |
| **Run direction** | Listed | Front and center as a direction instruction box |
| **Materials** | Power + Hardware | **Strip + Hardware only** — no power supplies, no wire |
| **Tasks** | Run wire, cap injections | Install strip, connect injections, power on, capture photos |

### "Wiring complete" badge

Green **Wiring complete ✓** badge at the top of every channel detail card. The Day 1 electrician has confirmed every wire for that channel is in place and accessible. You should find each wire end exactly where the blueprint says.

### Run direction instruction

Each channel has a clear instruction box:

> *"Feed strip {direction} starting at {start description}. Run is {feet}ft."*

Example:

> *"Feed strip left to right starting at left corner of house, ground level. Run is 120ft. Injection points at 60ft."*

Tells you:
- Which physical end to start at
- Which direction to roll the strip
- How long the run is
- Where injection points are (so you plug in as you pass each one)

### Materials list

Day 2 materials card shows only:
- **STRIP** — LED strip broken down by channel
- **HARDWARE** — mounting clips, brackets, connectors

Arrive with everything on this list. Short on anything? Call your dealer admin before you arrive.

### Task checklist

Same checkbox interface as Day 1, with Day 2 tasks:

- **Per channel:** "Install {label} strip — feed {direction}, {feet}ft"
- **Per injection point:** "Connect injection at {location}"
- **Plug in controller** (or "at {mount location}")
- **Power on and verify all channels respond**
- **Per channel:** "Capture completion photo for {label}"

Tap each box as you complete. Progress bar shows X of N tasks complete.

---

## 5. Install sequence

Typical Day 2:

1. **Arrive on-site** and greet the customer. Confirm gate codes and any access notes from the salesperson.
2. **Walk the perimeter** with the blueprint open. Find each channel's start and end. Locate every Day 1 wire (controller wire, injection wires).
3. **Install the strip** for each channel, feeding in the direction the blueprint specifies. Connect at injection points as you pass them.
4. **Plug in the controller.** All channels should illuminate.
5. **Power on and verify** every channel responds — turn each on/off, change colors, confirm no dark spots or color shifts.
6. **Capture a completion photo** for each channel. Wrap-up requires these.
7. **Check off every task** as you go.

When all tasks are checked, the bottom button changes to **Wrap up install →** (green). Tap it to start wrap-up.

---

## 6. Wrap-up — the most important part

The 4-step wizard that closes the job, hands the system to the customer, and fires all the final automated communications. A step indicator at the top shows where you are.

### Step 1 — Install photos

**Required:** one completion photo per channel.

**Why:** proof of work and quality record. Corporate uses them for warranty claims and dealer audits.

**Steps:**

1. Row per channel (e.g., "Front Roofline", "Garage", "Side Accent")
2. For each row, tap the camera icon and capture a photo showing the installed strip lit up at night or in shadow so the LEDs are visible
3. After capturing, the row shows a thumbnail. Tap the row again to retake.
4. **Continue →** is disabled until every channel has a photo

You can't proceed past Step 1 without a photo for every channel.

### Step 2 — Material check-in

**What it asks for:** how much of each material was actually used vs. how much you brought.

**Why it matters:** feeds the dealer's **Waste Intelligence** dashboard. Over time, it tells your dealer how accurate estimates are and where waste happens — so the dealer orders smarter and reduces shrinkage.

**Steps:**

1. Table of materials from the original estimate
2. **Estimated qty** is shown (read-only) for each material
3. In **Quantity Returned**, type how many units you're bringing back unused
4. App auto-calculates **Used = Estimated − Returned** and displays the **waste %**

Example:
- Estimated: 200 ft of 14/2 wire
- Returned: 15 ft
- Used: 185 ft
- Waste: 7.5%

**Be honest.** Under-reporting returns inflates "used" numbers and corrupts waste data. Over-reporting hides actual waste and doesn't fix underlying problems.

If you're not returning anything for an item, leave the field blank or enter `0`.

Tap **Continue →** when done.

### Step 3 — Customer account

**What it does:** creates the customer's Lumina account so they can control their lights.

**Why it's critical:** the customer can't use the lights until they have an account. This step creates the account, sends the password-reset email, and prepares the handoff.

**Steps:**

1. Fields pre-filled from the prospect record:
   - **First Name**
   - **Last Name**
   - **Email**
   - **Phone** (display only)
2. Verify each field with the customer. Confirm the email — this is where their login link goes.
3. Tap **Create account**.
4. The app creates the user, generates a password-reset link, and sends the customer a welcome email titled **"Set up your Nex-Gen LED Lumina account"** with the reset link and app download links.
5. On success, the screen shows **"Account created for {email}"** and the button changes to **Re-send invite** (in case the customer never receives the email).

**If creation fails:**

- Check the email format and try again.
- If it still fails, complete the rest of the wrap-up — Step 4 still lets you close the job. Note the failure and contact your dealer admin so they can manually provision the account.

Tap **Continue →** when done.

### Step 4 — Launch setup for the customer (optional, recommended)

**What it does:** walks the customer through the in-app first-time setup so they can pair with the controller and learn the basics.

Optional but **highly recommended** — cuts support calls in the first 48 hours dramatically.

**Steps:**

1. After Step 3 succeeds, you'll see **Launch Lumina setup**
2. Tap it. The app pivots into the **Installer Setup Wizard** with customer info pre-loaded.
3. Hand the device to the customer (or sit with them).
4. Walk them through:
   - **Customer Info** confirmation
   - **Controller Setup** — pair the controller with their network
   - **Zone Configuration** — name their zones if needed
   - **Handoff** — final transfer of ownership
5. When done, you're back on the wrap-up screen.

**Coach the customer through the basics before you leave:**

- How to turn lights on/off from the home screen
- How to pick a color or pattern
- How to set a schedule
- The lights will run automatically at dusk to dawn

### Step 5 — Close the job

**What it does:** marks the job as **Install complete** and triggers the final customer email.

**Steps:**

1. Summary card lists:
   - X channel photos captured
   - X items checked in
   - Customer account created (checkmark)
2. Tap **Finish & Close Job** (green)
3. Confirmation dialog appears with totals
4. Tap **Confirm**
5. The app:
   - Moves the job status to **Install complete**
   - Records you as the Day 2 tech
   - Saves the completion timestamp
   - Triggers the customer's **"Your Nex-Gen LED system is live!"** email with app download links
6. You're back in the Day 2 Queue. Job is closed and gone.

---

## 7. What the customer gets after Install Complete

1. **"Your Nex-Gen LED system is live!" email** with:
   - Confirmation the system is installed
   - Download buttons for Lumina (iPhone + Android)
   - A pointer to the account setup email from Step 3
   - Welcome message from your dealer

2. **The account setup email** (sent earlier in Step 3) titled **"Set up your Nex-Gen LED Lumina account"**:
   - Password reset link
   - Download links for Lumina

Customer should be fully self-sufficient at this point.

---

## 8. Recording returns (Step 2)

The app expects the **quantity returned**, not the quantity used. "Used" is computed automatically.

### Why it matters

Waste Intelligence uses this data to:

- Identify materials that are consistently overbought
- Spot installers who are wasteful or efficient
- Tune future estimates so the dealer doesn't tie up cash in unnecessary inventory

### Tips for accurate check-in

- **Count the actual returns** — don't estimate
- **Record returns as decimals** when needed (e.g., `12.5` ft of wire)
- **Don't pad the numbers** — the long-term value depends on every install being honest
- **If you used more than estimated,** leave returned at 0 and flag it to your dealer admin so they can adjust the estimate template

---

## 9. Critical Day 2 rules

| Rule | Why it matters |
|---|---|
| **Capture a completion photo for every channel.** | Required for warranty and audit. Step 1 won't let you proceed without them. |
| **Verify every channel powers on before wrap-up.** | A dead channel after the customer is unhappy costs 10× what fixing it now costs. |
| **Be accurate in material check-in.** | Bad data corrupts waste tracking and inventory ordering. |
| **Confirm the customer's email before creating their account.** | A typo means they won't get the password setup email. |
| **Walk the customer through the basics.** | 5 minutes of training prevents 30 minutes of support calls. |
| **Always close the job through Step 4.** | Skip it and the customer never gets the welcome email and never gets their account. |

---

## What success looks like

- Every channel lit, no dark spots, no color shifts
- Completion photo captured for every channel
- Material check-in numbers entered accurately
- Customer account created; "Account created for {email}" confirmation showing
- Customer walked through basics — they've turned lights on, changed a color, saved a favorite
- **Finish & Close Job** tapped; job moved out of your queue
- Customer has received both the account setup email and the "Your system is live!" email

## If something isn't working

**"A channel is dead after I plug in the controller."**
Stop. Find the wire feeding that channel and the injection wires. Verify Day 1 ran wire all the way to the strip end. If wires are missing or buried in walls, the job is not Day 2 ready — call your dealer admin.

**"Customer account creation fails with 'Email already exists'."**
The customer has a Lumina account from a previous install. Tap **Re-send invite** to send a fresh password link. If they don't recognize the existing account, contact your dealer admin to investigate.

**"I forgot to take a completion photo before leaving."**
Step 1 requires every photo. Either return to the site or take a photo from a different angle that still shows the lights. Don't skip it.

**"The Day 1 wires aren't where the blueprint says."**
Day 1 issue — electrician didn't leave wires accessible. Document the problem, call your dealer admin, reschedule. Don't cut into walls to install.

**"I'm partway through wrap-up and need to leave."**
Wrap-up doesn't auto-save between steps the way the blueprint does. If you abandon mid-wrap-up, you'll need to redo steps when you return. **Do not** mark the job complete until everything is actually done.

**"The customer's email is wrong and they've already left."**
Complete the rest of wrap-up. Contact your dealer admin to update the email and re-trigger account creation.

**"PIN won't work."**
Confirm all 4 digits. If locked out after 5 failed attempts, wait 30 seconds or dismiss and reopen the Staff PIN screen. Still blocked? Your dealer admin needs to confirm your installer account is active.

---

**Need help?** Call your dealer admin or your Nex-Gen LED LLC corporate contact.
