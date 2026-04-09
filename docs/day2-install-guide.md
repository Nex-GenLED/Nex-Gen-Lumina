# Day 2 Install Team — Field Guide

**Audience:** Install technicians performing the Day 2 LED installation on a Lumina job

This guide covers the Day 2 workflow end-to-end: getting into the app, reading the blueprint, installing the strip, and walking the customer through the wrap-up sequence that hands the system over to them.

---

## 1. Logging In

Day 2 work happens inside **Installer Mode**, which is gated behind a 4-digit PIN.

### PIN format
- **Digits 1–2:** Your dealer code (e.g., `42`)
- **Digits 3–4:** Your personal installer code (e.g., `07`)
- Together: `4207`

You'll get this PIN from your dealer admin during onboarding.

### How to log in
1. Open the Lumina app.
2. From the main launch screen, tap **Installer Mode**.
3. Tap **Enter Installer PIN**.
4. Type your 4-digit PIN.

### Session timeout
- The session stays active for **30 minutes** of activity.
- A warning appears **5 minutes before** timeout — tap to extend.
- Logged-out work is always saved. Just sign back in.

---

## 2. The Day 2 Queue

From the **Installer Landing** screen, tap **Day 2 Queue**.

### What the Day 2 Queue shows

The queue lists every job for your dealer that's had Day 1 completed and is ready for installation — specifically, jobs in one of these statuses:

- **Pre-wire complete** (amber badge) — Wiring is done but Day 2 isn't scheduled yet
- **Install scheduled** (green badge) — Day 2 has a date locked in

### What each card shows

| Card element | Meaning |
|---|---|
| **Customer name** (top, bold) | Who the job is for |
| **Address** | Full street, city, state, zip |
| **Status badge** (top-right) | Amber = Pre-wire complete, Green = Install scheduled |
| **Day 2: {date}** (green calendar icon) | Shown only if Day 2 is scheduled |
| **Reschedule** | Inline text button next to the date |
| **Schedule Day 2** button | Shown only if Day 2 hasn't been scheduled yet |

---

## 3. Scheduling Day 2

For any job in **Pre-wire complete**, tap **Schedule Day 2**.

1. A dark date picker opens.
2. Pick a date. The earliest selectable date is the day Day 1 was completed (you can't schedule Day 2 before Day 1 is done). The latest is 365 days out.
3. Tap **OK**.
4. A snackbar confirms: **"Day 2 scheduled for {date}"**.

The job moves from **Pre-wire complete** to **Install scheduled**, and the customer immediately receives an SMS confirming the install date. The night before the visit, they'll get a reminder SMS automatically.

---

## 4. The Day 2 Blueprint Screen

Tap any job card to open the **Day 2 Blueprint**. This is the main work screen.

### What's different from the Day 1 Blueprint

If you've worked Day 1 before, the screen will look familiar but with key differences:

| Element | Day 1 | Day 2 |
|---|---|---|
| **Channel cards** | Show wiring tasks | Show install tasks with **"Wiring complete ✓"** badge in green |
| **Run direction** | Listed but not emphasized | Front and center as a **direction instruction box** |
| **Materials** | Power + Hardware only | **Strip + Hardware only** — no power supplies, no wire |
| **Tasks** | Run wire, cap injections | Install strip, connect injections, power on, capture photos |

### The "Wiring complete" badge
At the top of every channel detail card you'll see a green **Wiring complete ✓** badge. This means the Day 1 electrician has confirmed every wire for that channel is in place and accessible. You should be able to find each wire end exactly where the blueprint says.

### Reading the run direction instruction
Each channel has a clear instruction box that reads:

> *"Feed strip {direction} starting at {start description}. Run is {feet}ft."*

For example:
> *"Feed strip left to right starting at left corner of house, ground level. Run is 120ft. Injection points at 60ft."*

This tells you:
- Which physical end to start at
- Which direction to roll the strip
- How long the run is
- Where injection points are along the run (so you can plug them in as you pass each one)

### Materials list
The Day 2 materials card shows only:
- **STRIP** — the LED strip itself, broken down by channel
- **HARDWARE** — mounting clips, brackets, connectors

You should arrive with all materials on this list. If you're short, call your dealer admin before you arrive on-site.

### Task checklist
Same checkbox interface as Day 1, but with Day 2 tasks:
- **Per channel:** "Install {label} strip — feed {direction}, {feet}ft"
- **Per injection point:** "Connect injection at {location}"
- **Plug in controller** (or "at {mount location}" if specified)
- **Power on and verify all channels respond**
- **Per channel:** "Capture completion photo for {label}"

Tap each box as you complete it. The progress bar shows X of N tasks complete.

---

## 5. Doing the Install

Typical Day 2 sequence:

1. **Arrive on-site** and greet the customer. Confirm gate codes and any access notes from the salesperson.
2. **Walk the perimeter** with the blueprint open. Find each channel's start and end. Locate every Day 1 wire (controller wire, injection wires).
3. **Install the strip** for each channel, feeding it in the direction the blueprint specifies. Connect at injection points as you pass them.
4. **Plug in the controller.** All channels should illuminate.
5. **Power on and verify** every channel responds — turn each one on/off, change colors, confirm there are no dark spots or color shifts.
6. **Capture a completion photo** for each channel. The wrap-up sequence will require these.
7. **Check off every task** in the blueprint as you go.

When all tasks are checked, the bottom button changes to **Wrap up install →** (green). Tap it to start the wrap-up sequence.

---

## 6. The Wrap-Up Sequence

The wrap-up is the most important part of Day 2. It's a **4-step wizard** that closes the job, hands the system over to the customer, and triggers all the final automated communications.

You'll see a step indicator at the top showing where you are in the sequence.

### Step 1: Install Photos

**What it asks for:** One completion photo per channel.

**Why it's required:** The photos serve as proof of work and a quality record. Corporate uses them for warranty claims and dealer audits.

**How to do it:**
1. You'll see a row for each channel (e.g., "Front Roofline", "Garage", "Side Accent").
2. For each row, tap the camera icon and capture a photo showing the installed strip lit up at night or in shadow so the LEDs are visible.
3. After capturing, the row shows a thumbnail. If you need to retake, tap the row again.
4. The **Continue →** button is disabled until **every** channel has a photo.

You cannot proceed past Step 1 without a photo for every channel.

### Step 2: Material Check-In

**What it asks for:** How much of each material was actually used vs. how much you brought.

**Why it matters:** This data feeds your dealer's **Waste Intelligence** dashboard. Over time, it tells your dealer how accurate the salesperson's estimates are and where waste is happening — which lets the dealer order smarter and reduce shrinkage.

**How to do it:**
1. You'll see a table of materials from the original estimate.
2. For each material, the **Estimated qty** is shown (read-only).
3. In the **Quantity Returned** field, type how many units you're bringing back unused.
4. The app auto-calculates **Used = Estimated − Returned** and displays the **waste %**.

For example:
- Estimated: 200 ft of 14/2 wire
- Returned: 15 ft
- Used: 185 ft
- Waste: 7.5%

**Be honest and accurate.** Underreporting returns inflates the dealer's "used" numbers and corrupts the waste data. Overreporting hides actual waste and doesn't fix underlying problems.

If you're not bringing anything back for a particular item, leave the field blank or enter `0`.

When you're done, tap **Continue →**.

### Step 3: Customer Account Creation

**What it does:** Creates the customer's Lumina account so they can control their lights from their phone.

**Why it's critical:** The customer cannot use the lights until they have an account. This step creates the account, sends them a password reset email, and prepares the handoff.

**How to do it:**
1. You'll see fields pre-filled from the prospect record:
   - **First Name**
   - **Last Name**
   - **Email**
   - **Phone** (display only)
2. Verify each field with the customer. Confirm the email is correct — this is where their login link goes.
3. Tap **Create account**.
4. The app calls a secure cloud function that:
   - Creates a new Firebase Auth user with the customer's email
   - Generates a password reset link
   - Sends the customer a welcome email titled **"Set up your Nex-Gen LED Lumina account"** with the password reset link and links to download the Lumina app
   - Creates the customer's user profile in the cloud
5. On success, the screen updates to show **"Account created for {email}"** and the button changes to **Re-send invite** (in case the customer never receives the email).

**If account creation fails:**
- Check the email format and try again.
- If it still fails, you can complete the rest of the wrap-up — Step 4 will still let you close the job. Note the failure and contact your dealer admin so they can manually provision the customer's account afterwards.

When you're done, tap **Continue →**.

### Step 4: Launching the Lumina Setup Wizard for the Customer

**What it does:** Walks the customer through the in-app first-time setup so they can pair their phone with the controller and learn the basics.

This step is **optional** but highly recommended — it dramatically reduces support calls in the first 48 hours.

**How to do it:**
1. After Step 3 succeeds, you'll see a **Launch Lumina setup** option.
2. Tap it. The app pivots into the **Installer Setup Wizard** with the customer's info pre-loaded.
3. Hand the device to the customer (or sit with them).
4. Walk them through:
   - **Customer Info** confirmation
   - **Controller Setup** — pair the WLED controller with their network
   - **Zone Configuration** — name their zones if needed
   - **Handoff** — final transfer of ownership
5. When the wizard is done, you're returned to the wrap-up screen.

**Coach the customer through the basics before you leave:**
- How to turn lights on/off from the home screen
- How to pick a color or pattern
- How to set a schedule
- That the lights will run automatically at dusk to dawn

### Step 5: Closing the Job

**What it does:** Marks the job as **Install complete** and triggers the final customer email.

**How to do it:**
1. You'll see a summary card listing:
   - X channel photos captured
   - X items checked in
   - Customer account created (with checkmark)
2. Tap **Finish & Close Job** (green button).
3. A confirmation dialog appears with the totals.
4. Tap **Confirm**.
5. The app:
   - Moves the job status to **Install complete**
   - Records you as the Day 2 technician
   - Saves the completion timestamp
   - Triggers the customer's **"Your Nex-Gen LED system is live!"** email with app download links
6. You're returned to the Day 2 Queue. The job is now closed and disappears from your queue.

---

## 7. What the Customer Receives After Install Complete

The moment you close the job, the customer gets:

1. **An email titled "Your Nex-Gen LED system is live!"** with:
   - Confirmation that the system is installed
   - Download buttons for the Lumina app (iPhone and Android)
   - A note pointing to the account setup email they got in Step 3
   - A welcome message from your dealer

2. **The account setup email** (sent earlier in Step 3) titled **"Set up your Nex-Gen LED Lumina account"**, containing:
   - A password reset link to set their password
   - Links to download Lumina

That's it. The customer should be fully self-sufficient at this point.

---

## 8. Recording Unused Materials (Returns)

Step 2 of the wrap-up is where you record returns. The app expects you to enter the **quantity returned**, not the quantity used. The "used" number is computed automatically.

### Why this matters
The dealer's **Waste Intelligence** dashboard uses this data to:
- Identify which materials are consistently overbought
- Spot installers who are wasteful or efficient
- Tune future estimates so the dealer doesn't tie up cash in unnecessary inventory

### Tips for accurate check-in
- **Count the actual returns** — don't estimate.
- **Record returns as decimals** when needed (e.g., `12.5` ft of wire).
- **Don't pad the numbers** — the long-term value of the data depends on every install being honest.
- **If you used more than estimated**, leave the returned field at 0 and flag it to your dealer admin so they can adjust the estimate template.

---

## 9. Critical Day 2 Rules

| Rule | Why it matters |
|---|---|
| **Capture a completion photo for every channel.** | Required for warranty and audit. Step 1 won't let you proceed without them. |
| **Verify every channel powers on before wrap-up.** | If a channel is dead, troubleshoot it now — not after the customer is unhappy. |
| **Be accurate in material check-in.** | Bad data corrupts the dealer's waste tracking and inventory ordering. |
| **Confirm the customer's email before creating their account.** | A typo here means they won't get the password setup email. |
| **Walk the customer through the basics.** | 5 minutes of training prevents 30 minutes of support calls. |
| **Always close the job through Step 4.** | Skipping the wrap-up means the customer never gets the welcome email and never gets their account. |

---

## 10. Troubleshooting

**A channel is dead after I plug in the controller.**
Stop. Find the wire that feeds that channel and the injection wires for it. Verify Day 1 ran wire all the way to the strip end. If wires are missing or buried in walls, the job is not Day 2 ready — call your dealer admin.

**Customer account creation fails with "Email already exists".**
The customer already has a Lumina account from a previous install. Tap **Re-send invite** to send a fresh password link. If they don't recognize the existing account, contact your dealer admin to investigate.

**I forgot to take a completion photo before leaving.**
Step 1 requires every photo. You'll have to either return to the site or take a photo from a different angle that still shows the lights. Don't skip this step.

**The Day 1 wires aren't where the blueprint says.**
This is a Day 1 issue — the electrician didn't leave wires accessible. Document the problem, call your dealer admin, and reschedule. Don't try to install by cutting into walls.

**I'm partway through the wrap-up and need to leave.**
The wrap-up doesn't auto-save between steps the way the blueprint does. If you abandon mid-wrap-up, you'll need to redo the steps when you return. **Do not** mark the job complete until everything is actually done.

**The customer's email is wrong and they've already left.**
Complete the rest of the wrap-up. Then contact your dealer admin to update the email and re-trigger the account creation.

---

**Need help?** Contact your dealer admin or your Nex-Gen LED corporate contact.
