# Complete Job Lifecycle — From Prospect to Installed Customer

**Describes Lumina app version 2.5.10+89.**

**Audience:** All roles — the operational overview document for understanding how a Lumina job flows from first prospect visit through installed, live customer.

This is the master reference for the entire job pipeline. Use it to understand who owns each stage, what messages fire automatically, where payment gates block progress, and how to recover from common failure modes. Permanent residential and commercial lighting that works as hard as you do — delivered by a pipeline that communicates with the customer at every milestone so no one ever has to chase for status.

## What you'll need

- Access to your role's Lumina interface (Sales Mode, Installer Mode, Dealer Dashboard, or Corporate Dashboard)
- Familiarity with your role's specific guide (Sales Mode Guide, Day 1 Electrician Guide, Day 2 Install Guide, Dealer Dashboard Guide, Corporate Dashboard Guide)
- If you're debugging a stalled or broken job: dealer admin access or backend access

---

## 1. The full pipeline at a glance

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   PROSPECT                  INSTALL                  CUSTOMER        │
│   (Salesperson)             (Field crews)            (Live)          │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

  ┌────────┐    ┌──────────┐    ┌────────┐   ╔═════════╗   ┌──────────┐
  │ Draft  │───▶│ Estimate │───▶│ Signed │──▶║ DEPOSIT ║──▶│ Pre-wire │
  │        │    │   Sent   │    │        │   ║  GATE   ║   │Scheduled │
  └────────┘    └──────────┘    └────────┘   ╚═════════╝   └──────────┘
                                                                 │
                                                                 ▼
  ┌──────────┐   ╔═════════╗   ┌──────────┐   ┌──────────┐  ┌──────────┐
  │ Complete │◀──║  FINAL  ║◀──│  Install │◀──│  Install │◀─│ Pre-wire │
  │  (paid)  │   ║ PAYMENT ║   │ Complete │   │Scheduled │  │ Complete │
  └──────────┘   ╚═════════╝   └──────────┘   └──────────┘  └──────────┘
```

The two double-ruled boxes are **payment gates**, not statuses. They do not appear in the status list — they are conditions on the job that block the next action until satisfied.

| Status | Owner | Plain English |
|---|---|---|
| **Draft** | Salesperson | Estimate is being built but not generated. |
| **Estimate Sent** | Salesperson | Estimate generated but customer hasn't signed. *(Used in legacy flows; the wizard usually goes straight to Signed.)* |
| **Signed** | Day 1 electrician | Customer signed. Job is officially booked. |
| **Pre-wire Scheduled** | Day 1 electrician | Day 1 has a date. |
| **Pre-wire Complete** | Day 2 install team | Wires are run. Ready for Day 2. |
| **Install Scheduled** | Day 2 install team | Day 2 has a date. |
| **Install Complete** | Day 2 install team | Lights are up and the customer has an account. Balance still outstanding. |
| **Complete (paid)** | Nobody | Final payment collected. Job is archived out of the active queues. |

---

## 2. The two payment gates

These are the most common reason a job appears to be "stuck" when nothing is actually broken. Read this section before Section 5.

### Gate 1 — the 50% deposit, before Day 1 can be scheduled

A signed job lands in the Day 1 Queue, but until the deposit is marked collected, its card renders a **deposit banner where the Schedule Day 1 button would be**. There is no way to schedule around it.

When the deposit is marked collected, the job records:

- `depositCollected` → true
- `depositCollectedAt` — the timestamp
- `depositCollectedBy` — the uid (or installer PIN) of whoever marked it
- `depositAmount` — a **snapshot** of 50% of the total at that moment, so a later edit to the job's price does not rewrite history

<div>

> **Who is responsible:** the salesperson closes the sale, but nothing in the signature flow collects money. Somebody has to mark the deposit on the job. Make that an explicit handoff in your dealership's process, or you will accumulate signed jobs that no electrician can book.

</div>

### Gate 2 — final payment, after Day 2

After the install is complete, the Day 2 wrap-up's close step offers a **final payment** confirmation: *"Confirm that {customer} has paid the remaining balance? The job will be archived as complete."* Confirming it flips the job to **Complete (paid)** and records `finalPaymentCollected`, its timestamp, and who marked it.

A job left at **Install Complete** is done in the field but still open on the books. That is a legitimate resting state, not an error.

---

## 3. Stage-by-stage walkthrough

For each stage:

- **Owner** — whose responsibility it is to advance the job
- **What the user does** — the action that moves the job forward
- **What gets created/updated** — data side effects
- **Automated messages fired** — what the customer receives
- **Customer experience** — what they see from their side

### Stage 1 — Prospect → Draft

**Owner:** Salesperson

**What the user does:**

1. Salesperson opens Sales Mode and taps **New Visit**.
2. Fills in the **Customer Info** form (name, email, phone, address, optional referral code, notes, photos).
3. Taps **Continue to zones →**.

**What gets created:**

- A new sales job in the dealer's collection with auto-generated job number (`NXG-{date}-{seq}`)
- The job has status **Draft**, embedded prospect record, dealer code, salesperson identifier, creation timestamp
- Any home photos uploaded are stored against the job
- If a valid referral code was entered, the referral pipeline is updated to "visit scheduled"

**Automated messages:** None. The customer is unaware so far.

**Customer experience:** Sitting with the salesperson. Nothing automated has fired yet.

---

### Stage 2 — Draft → (still Draft, building estimate)

**Owner:** Salesperson

**What the user does:**

The salesperson walks through the 5-step Estimate Wizard:

1. **Home Photo** — captures the blueprint background photo
2. **Controller Placement** — describes mount location, interior/exterior, distance to outlet, optional photo
3. **Channel Setup** — adds one or more LED channel runs
4. **Power Injection Points** — adds injection points for runs over 100 ft
5. **Summary and Review** — reviews everything and taps **Generate Estimate**

**What gets updated:**

- The job is updated continuously as the wizard progresses (home photo URL, controller mount, channel runs, injection points)
- On **Generate Estimate**, the system loads dealer pricing and writes a full **EstimateBreakdown** (line items by category, subtotals, margin)
- Job is still **Draft**

**Automated messages:** None.

**Customer experience:** Sitting with the salesperson. Watches the estimate build live on the device.

---

### Stage 3 — Draft → Signed

**Owner:** Salesperson (handing the device to the customer)

**What the user does:**

1. Salesperson continues from the estimate preview to the signature screen
2. Hands the device to the customer
3. Customer reviews the estimate, draws a signature, and taps **Approve & confirm**

**What gets updated:**

- Customer signature PNG is uploaded to the job's cloud folder
- Job status → **Signed (`estimateSigned`)**
- `estimateSignedAt` timestamp set
- `customerSignatureUrl` populated
- If a referral code was used, the referral pipeline moves to "confirmed" and the referrer's credit is locked in
- The job becomes visible in the dealer's Day 1 Queue — **behind the deposit gate**

**Automated messages fired:**

- **Booking Confirmation Email** to the customer (subject: *"You're booked with Nex-Gen LED! 🎉"*) — explains the 2-day process, access requirements, and dealer contact. *(Toggleable per dealer.)*

**Customer experience:** Signs and immediately sees the confirmation *"Estimate approved — install is confirmed."* Within seconds, the booking email arrives.

---

### Stage 3a — the deposit gate

**Owner:** Whoever your dealership assigns — the salesperson, the office, or the electrician on arrival

**What the user does:** marks the 50% deposit collected on the job.

**What gets updated:** `depositCollected`, `depositCollectedAt`, `depositCollectedBy`, `depositAmount`.

**Automated messages:** None. **The customer is not told the deposit gate exists**, so a job sitting here looks — from their side — exactly like a booked job nobody has scheduled.

**Until this is done, Stage 4 is unavailable.**

---

### Stage 4 — Signed → Pre-wire Scheduled

**Owner:** Day 1 electrician

**What the user does:**

1. Electrician opens the Day 1 Queue
2. Finds the new signed job (with its deposit collected)
3. Taps **Schedule Day 1**
4. Picks a date

**What gets updated:**

- Job status → **Pre-wire Scheduled (`prewireScheduled`)**
- `day1Date` set

**Automated messages fired:**

- **Day 1 Confirmation SMS** to the customer:
  > *"Hi {first name}, your Nex-Gen LED prep day is confirmed for {date}. Our technician will handle the wiring — no lights go up this day, that's Day 2. Questions? Reply here. — {dealer sign-off}"*

**Customer experience:** SMS confirming the Day 1 date.

---

### Stage 5 — Pre-wire Scheduled → (Day 1 visit happens)

**Owner:** Day 1 electrician

**What the user does:**

1. **The night before** the visit (6:00 PM Central), the system automatically sends the **Day 1 Reminder SMS**
2. On the day of the visit, the electrician arrives, opens the **Day 1 Blueprint**, and works through every task
3. Each task is checked off in the app as completed

**Automated messages fired during this stage:**

- **Day 1 Reminder SMS** (the night before, automatic) — reminds the customer about access requirements. *(Toggleable per dealer.)*

**What gets updated:**

- `day1CompletedTaskIds` array updated as tasks are checked
- No status change yet — that happens at check-out

**Customer experience:** Gets the reminder SMS the night before. On the day, the electrician shows up and runs wiring. No lights yet.

---

### Stage 6 — Pre-wire Scheduled → Pre-wire Complete

**Owner:** Day 1 electrician

**What the user does:**

1. Completes all tasks on the Day 1 Blueprint, including the verification task ("Verify all wires are accessible outside wall for Day 2")
2. Taps **Mark Day 1 complete**
3. Confirms by entering their name in the dialog

**What gets updated:**

- Job status → **Pre-wire Complete (`prewireComplete`)**
- `day1CompletedAt` timestamp set
- `day1TechUid` recorded
- Job disappears from Day 1 Queue, appears in Day 2 Queue

**Automated messages fired:**

- **Day 1 Complete SMS** to the customer:
  > *"Great news, {first name}! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — {dealer sign-off}"*

**Customer experience:** "Wiring done" SMS the same day.

---

### Stage 7 — Pre-wire Complete → Install Scheduled

**Owner:** Day 2 install team

**What the user does:**

1. Day 2 installer opens the Day 2 Queue
2. Finds the new pre-wire complete job
3. Taps **Schedule Day 2**
4. Picks a date (must be on or after the Day 1 completion date)

**What gets updated:**

- Job status → **Install Scheduled (`installScheduled`)**
- `day2Date` set

**Automated messages fired:**

- **Day 2 Confirmation SMS** to the customer:
  > *"Hi {first name}, your Nex-Gen LED light installation is confirmed for {date}. Our install team will have your lights up and running. Get excited! — {dealer sign-off}"*

**Customer experience:** SMS confirming the install date.

---

### Stage 8 — Install Scheduled → (Day 2 visit happens)

**Owner:** Day 2 install team

**What the user does:**

1. **The night before** the visit (6:00 PM Central), the system automatically sends the **Day 2 Reminder SMS**
2. On the day, install team arrives, opens the Day 2 Blueprint, works through every install task

**Automated messages fired:**

- **Day 2 Reminder SMS** (the night before, automatic). *(Toggleable per dealer.)*

**Customer experience:** Gets the reminder SMS, then watches the install team put up the lights.

---

### Stage 9 — Day 2 Wrap-Up Sequence (the most important step)

**Owner:** Day 2 install team

**What the user does:**

After all install tasks are checked, the installer taps **Wrap up install →** and walks through the 4-step wrap-up:

#### Step 1 — Install Photos

- Captures one completion photo per channel
- Photos uploaded to the job's cloud folder
- Step is gated — cannot proceed without photos for every channel

#### Step 2 — Material Check-In

- Records returned quantity for each material in the estimate
- App auto-calculates used quantity and waste percentage
- Data persisted to the job's `actualMaterialUsage` field
- Feeds the dealer's Waste Intelligence dashboard

#### Step 3 — Customer Account Creation

- Installer confirms the customer's name and email
- Taps **Create account**
- The system:
  - Creates a new Firebase Auth user
  - Generates a password reset link
  - Sends the **Account Setup Email** (subject: *"Set up your Nex-Gen LED Lumina account"*) with the reset link and app download buttons
  - Creates a `/users/{uid}` document tagged as the customer's primary account
- The new UID is saved on the job as `linkedUserId`

<div>

> **This step does not link the customer's controllers.** Account creation and controller migration are separate mechanisms — the Installer Mode setup wizard is what moves controllers into a customer's account. A customer whose account was created here, and only here, will sign in to an app with no system attached. If Day 2 created the account, confirm the controllers actually appear before you leave.

</div>

#### Step 4 — Close Job

- Installer reviews the summary card (photos captured, materials checked in, account created)
- Taps **Finish & Close Job** and confirms in the dialog
- The close step is also where **final payment** is confirmed, if it is being collected on site

**What gets updated at close:**

- Job status → **Install Complete (`installComplete`)**
- `day2CompletedAt` timestamp set
- `day2TechUid` recorded
- Job disappears from the Day 2 Queue

**Automated messages fired at close:**

- **Install Complete Email** to the customer (subject: *"Your Nex-Gen LED system is live! 💡"*) — confirms the install, provides app download links, references the account setup email, and signs off with the dealer name. *(Toggleable per dealer.)*

**Customer experience:**

1. While the installer is on Step 3, the customer gets the **Account Setup Email** with their password link.
2. After Step 4 closes, the customer gets the **Install Complete Email** with download links.
3. Customer downloads Lumina, sets their password, signs in, controls their lights for the first time.

---

### Stage 10 — Install Complete → Complete (paid)

**Owner:** Whoever collects the balance

**What the user does:** confirms final payment (from the Day 2 wrap-up close step, or later).

**What gets updated:** `finalPaymentCollected`, `finalPaymentCollectedAt`, `finalPaymentCollectedBy`; status → **Complete (paid)**. The job is filtered out of the active queues and appears only in historical job lists.

**Automated messages:** None. This is a bookkeeping transition, not a customer milestone.

---

## 4. Stage summary — who owns what and what fires

| # | Status / gate | Owner | Trigger | Customer messages |
|---|---|---|---|---|
| 1 | **Draft** | Salesperson | Wizard in progress | None |
| 2 | **Estimate Sent** | Salesperson | (legacy) | None |
| 3 | **Signed** | Salesperson → Day 1 | Customer taps **Approve & confirm** | Booking Confirmation Email |
| 3a | *Deposit gate* | Dealer's choice | Deposit marked collected | **None** — the customer is never told |
| 4 | **Pre-wire Scheduled** | Day 1 electrician | Electrician picks Day 1 date | Day 1 Confirmation SMS |
| 5 | *(during wait)* | Day 1 electrician | Cron at 6pm Central night before | Day 1 Reminder SMS |
| 6 | **Pre-wire Complete** | Day 2 install team | Electrician taps **Mark Day 1 complete** | Day 1 Complete SMS |
| 7 | **Install Scheduled** | Day 2 install team | Installer picks Day 2 date | Day 2 Confirmation SMS |
| 8 | *(during wait)* | Day 2 install team | Cron at 6pm Central night before | Day 2 Reminder SMS |
| 9 | *(during wrap-up)* | Day 2 install team | Installer taps **Create account** in Step 3 | Account Setup Email |
| 10 | **Install Complete** | Day 2 install team | Installer taps **Finish & Close Job** | Install Complete Email |
| 11 | **Complete (paid)** | Bookkeeping | Final payment confirmed | None |

---

## 5. Technical integration notes

For technical operators. Field crews can skip this.

### Firestore documents touched at each stage

| Stage | Documents |
|---|---|
| **Draft creation** | `sales_jobs/{jobId}` created with embedded prospect; optional referral pipeline updated |
| **Wizard progress** | `sales_jobs/{jobId}` updated continuously (home photo URL, controller mount, channels, injections) |
| **Estimate generation** | `sales_jobs/{jobId}.estimateBreakdown` written |
| **Signature** | Signature PNG uploaded to Cloud Storage; job status → `estimateSigned`; signature URL written |
| **Deposit gate** | `sales_jobs/{jobId}.depositCollected`, `depositCollectedAt`, `depositCollectedBy`, `depositAmount` |
| **Day 1 schedule** | `sales_jobs/{jobId}.day1Date` + status → `prewireScheduled` |
| **Day 1 complete** | `sales_jobs/{jobId}.day1CompletedAt`, `day1TechUid`, status → `prewireComplete` |
| **Day 2 schedule** | `sales_jobs/{jobId}.day2Date` + status → `installScheduled` |
| **Wrap-up Step 1** | `sales_jobs/{jobId}.installCompletePhotoUrls` (positional list, 1 per channel) |
| **Wrap-up Step 2** | `sales_jobs/{jobId}.actualMaterialUsage` map (per item: estimated, returned, used, waste %) |
| **Wrap-up Step 3** | New Firebase Auth user; new `users/{uid}` document; `sales_jobs/{jobId}.linkedUserId` |
| **Wrap-up Step 4** | `sales_jobs/{jobId}.day2CompletedAt`, `day2TechUid`, status → `installComplete` |
| **Final payment** | `sales_jobs/{jobId}.finalPaymentCollected` + status → `completePaid` |

Note that the payment fields use camelCase, matching the rest of the `SalesJob` model, rather than the snake_case convention used elsewhere in the inventory build.

### Cloud functions

| Function | Trigger | Purpose |
|---|---|---|
| **onSalesJobStatusChanged** | Firestore update on `sales_jobs/{jobId}` | Detects status transitions and Day 1 completion; sends Booking Confirmation Email, Day 1/Day 2 confirmation SMS, Day 1 complete SMS, and Install Complete Email |
| **sendInstallReminders** | Scheduled cron, `every day 18:00`, `America/Chicago` | Queries jobs whose Day 1 or Day 2 date is tomorrow (Central time), sends reminder SMS to each |
| **createCustomerAccount** | Callable from Day 2 wrap-up Step 3 | Creates Firebase Auth user, sends Account Setup Email, seeds user profile document |

### Customer account deletion

The customer-side account lifecycle now has a real end. When a customer taps **Delete Account** in the app, the client re-authenticates, calls the `purgeUserAccount` callable, waits for it to succeed, and only then deletes the Auth user. The purge sweeps `users/{uid}` — the document *and* every subcollection — plus the customer's Cloud Storage prefix, and releases the paired-user field on any Lumina Bridge registered to them. The in-app confirmation dialog enumerates exactly what goes.

Four caveats that matter operationally:

- **The lights keep running.** Whatever schedule is already stored on the controller continues firing until an installer resets the hardware. Account deletion is not de-commissioning.
- **The bridge does not actually get released.** The purge calls a server-side release of the bridge's paired user, but **the bridge stores its paired uid in NVS (its own flash) and re-asserts that uid on every heartbeat**. A powered, live bridge writes the old pairing straight back, so the release only sticks for a bridge that is unplugged or dead. Freeing a live bridge is a **physical step**: `POST http://<bridge-ip>/api/reset`, then re-pair from the new owner's app. Reset the controller too before re-deploying it. Tracked as **P2-57**.
- **Not everything is purged yet.** Neighborhood Sync group membership and OAuth refresh tokens are known remaining gaps.
- **Verify the callable is deployed** in your environment before relying on this. The purge function is a separate deployment from the app build, and an app calling a callable that was never deployed will fail the delete rather than silently half-completing — but you want to know that before a customer discovers it.

---

## 6. Common failure points and how to recover

Things go wrong. Here's how to fix them without losing customer data.

### Failure 0 — "The job is signed but I can't schedule Day 1"

**Symptom:** the Day 1 Queue card shows a deposit banner instead of the **Schedule Day 1** button.

**This is not a bug.** The 50% deposit has not been marked collected. Collect it (or confirm with the office that it was collected), mark it on the job, and the scheduling controls appear. See Section 2.

Check this **first** on any job that appears stalled at Signed — it is the single most common cause and it looks identical to an unclaimed job.

### Failure 1 — Customer phone number is invalid

**Symptom:** SMS reminders bounce or never arrive.

**What to do:**

1. Open the job in the dealer's My Estimates list
2. Find the customer's phone field on the prospect info section
3. Correct the number using the dealer admin's edit-job flow
4. Subsequent SMS uses the corrected number. Previous failed messages will not auto-retry.
5. If the customer missed a reminder because of this, contact them directly to confirm the appointment.

### Failure 2 — Day 1 check-out is blocked because tasks are incomplete

**Symptom:** **Mark Day 1 complete** is grayed out and reads *"Complete all tasks to mark complete"*.

**What to do:**

1. Scroll up through the task checklist on the Day 1 Blueprint
2. Look for any task without a green checkmark
3. Common culprit: the verification task ("Verify all wires are accessible outside wall for Day 2") at the bottom — easy to miss
4. Check the missing task(s)
5. The button activates

If the electrician genuinely can't complete a task (a pre-run wire is missing, for example), do **not** check it off falsely. Instead:

- Document the issue with the dealer admin
- Leave the job in `prewireScheduled`
- Schedule a follow-up Day 1 visit

### Failure 3 — Customer account creation fails during wrap-up

**Symptom:** Step 3 of wrap-up shows an error, no account created, no email sent.

**Possible causes:**

- Email already exists (the customer has a previous Lumina account)
- Email format invalid
- Network failure
- Backend service issue

**What to do:**

1. **If the email already exists:** Tap **Re-send invite** to send a fresh password reset link to the existing account. If the customer doesn't recognize the existing account, contact the dealer admin to investigate.
2. **If the format is invalid:** Verify the email with the customer, edit it on the prospect record, try again.
3. **If you can't resolve on-site:** Continue through Step 4 to close the job. The customer won't receive their account setup email automatically — contact your dealer admin and have them manually provision the account afterwards.

### Failure 3a — Account created, but the customer's app is empty

**Symptom:** the customer signs in successfully and sees no controllers, no schedules, nothing to control.

**Cause:** account creation and controller migration are separate. The Day 2 wrap-up creates an account; the Installer Mode setup wizard is what moves controllers into it.

**What to do:** run the Installer Mode wizard against that customer (or use **Existing Customer** to attach the hardware to the account that already exists). Do not create a second account — that produces a duplicate and a second set of credentials.

### Failure 4 — Job is stuck in a status

**Symptom:** A job sits in one status for many days. Customer or dealer wants to advance it.

**Check the deposit gate first** (Failure 0). If that's not it:

**Common scenarios:**

- A job is **Signed** with its deposit collected, but no electrician has picked it up
- A job is **Pre-wire Complete** but no installer has scheduled Day 2
- A job somehow got into the wrong status (manual data correction needed)

**For genuinely stalled jobs:**

1. Open the job in the dealer's **My Estimates** list (or for corporate, the Pipeline tab)
2. Tap the job to open the **Job Detail** screen
3. The Job Detail screen has **manual status advance buttons** that appear depending on the current status:
   - **Signed** → "Schedule pre-wire" (advances to `prewireScheduled`)
   - **Pre-wire Scheduled** → "Mark pre-wire complete" (advances to `prewireComplete`)
   - **Pre-wire Complete** → "Mark install complete" (advances to `installComplete`)
   - **Install Scheduled** → "Mark install complete" (advances to `installComplete`)
4. Tap the appropriate button to manually move the job forward

> **Important:** Manual advances still trigger the corresponding automated messages. Use this only when you actually want the customer to receive the next message — don't manually advance a job whose physical work hasn't actually been done.

> **Note:** there is no manual button that advances **Install Complete** to **Complete (paid)** from this screen — that transition comes from the final-payment confirmation.

### Failure 5 — Wrong photo or info on the prospect

**Symptom:** Salesperson typed something incorrectly or attached the wrong photo.

**What to do:**

1. Open the job from My Estimates
2. Resume the wizard or use the dealer admin's edit flow
3. Correct the field, save
4. If the job is still in **Draft**, no automated messages have fired — edit freely
5. If the job is **Signed** or beyond, edits don't re-trigger prior messages — they only affect future messages and the install crews' view of the job

> One exception worth knowing: editing the total price after a deposit was collected does **not** change `depositAmount`. That field is a deliberate snapshot of the figure at collection time.

### Failure 6 — Installer marks Day 1 or Day 2 complete by accident

**Symptom:** Job is at `prewireComplete` or `installComplete` but the work isn't actually done.

**What to do:**

1. Contact the dealer admin immediately
2. The dealer admin can manually correct the job status using backend tools
3. **The customer has already received the next-stage SMS or email.** Reach out directly to clarify
4. Re-do the work with the proper check-out flow

This is one of the most damaging errors because it triggers customer messages that don't match reality. Train installers to double-check before tapping the complete button.

### Failure 7 — Reminder SMS didn't arrive the night before

**Symptom:** Customer says they didn't get the reminder.

**Possible causes:**

- The dealer disabled the reminder toggle
- The customer's phone is wrong
- The job's date wasn't actually scheduled
- SMS provider hiccup

**What to do:**

1. Check the dealer's messaging configuration — confirm the relevant reminder toggle (Day 1 or Day 2) is on
2. Verify the customer's phone number on the job
3. Verify the job's `day1Date` or `day2Date` is correct
4. If everything's correct, this was probably a one-off provider hiccup. Send a manual reminder via your usual support channels and confirm the appointment with the customer directly.

### Failure 8 — Photo upload fails during the wizard or wrap-up

**Symptom:** A photo capture fails to upload.

**What to do:**

1. Check the device's network connection
2. Retry the capture
3. If upload still fails, save the photo to the device gallery and try uploading from there
4. If Wrap-up Step 1 (install photos) is the blocker, you cannot proceed past Step 1 without a photo for every channel — keep trying until they upload

### Failure 9 — The customer's system works but their schedules never fire

**Symptom:** the customer can control the lights from the app, but a schedule they created does nothing.

This is a hardware-configuration problem, not a pipeline problem, and it almost always traces to Day 2:

1. **Controller clock.** A controller whose clock never synced to NTP fires no schedules at all. Check the pre-flight clock row in Installer Mode.
2. **Coordinates, for sunrise/sunset schedules.** The app refuses to arm a solar timer when latitude/longitude are unset or `0,0`.
3. **Off-LAN schedule writes.** In Bridge Mode — the default — schedule and configuration writes cannot be delivered remotely. All schedule setup must happen on the customer's Wi-Fi.

The Dealer & Installer Setup Guide covers all three in Steps 5, 8 and Section 9.

---

## 7. The customer's end-to-end experience

From the customer's point of view:

| Day | Event | Channel |
|---|---|---|
| **Day 0** (sales visit) | Salesperson visits and walks through the wizard live | In person |
| **Day 0** | Customer signs the estimate on the device | In person |
| **Day 0** (within seconds) | Booking confirmation email arrives | Email |
| **Day 0–X** | *(deposit collected — invisible to the customer as a pipeline event)* | — |
| **Day X** (some days/weeks later) | Day 1 confirmation SMS arrives | SMS |
| **Day X − 1** (evening) | Day 1 reminder SMS arrives | SMS |
| **Day X** (during visit) | Electrician arrives and runs all wiring | In person |
| **Day X** (after visit) | Day 1 complete SMS arrives | SMS |
| **Day Y** (some days later) | Day 2 confirmation SMS arrives | SMS |
| **Day Y − 1** (evening) | Day 2 reminder SMS arrives | SMS |
| **Day Y** (during visit) | Install team arrives and the lights go up | In person |
| **Day Y** (during wrap-up) | Account setup email arrives | Email |
| **Day Y** (after visit) | Install complete email arrives | Email |
| **Day Y** (after install) | Customer downloads Lumina, sets password, controls their lights | App |

The whole experience is designed so the customer is always informed and never has to chase the dealer for status updates. **The one blind spot is the deposit gate** — a job held there sends the customer nothing, so it is on the dealership to communicate.

---

## What success looks like

- Jobs move through the pipeline at a steady cadence — no status sitting more than 7–14 days unattended
- **No signed job sits behind an uncollected deposit for more than a day or two** — this is the pipeline's most common silent stall
- Every automated message fires on its intended stage transition, and the customer sees confirmations arrive within seconds
- The night-before reminders reduce missed appointments to near zero
- Wrap-up Step 3 creates the customer account on the first try, and Step 4 closes the job cleanly
- The customer's controllers are actually attached to the account that was created for them
- Final payment is collected and the job reaches **Complete (paid)** rather than resting at Install Complete indefinitely
- By the time the installer leaves, the customer has downloaded Lumina, set their password, and toggled their lights at least once

## If something isn't working

Start with the failure point that matches the symptom — they're all covered in Section 6. The short version:

**Signed job you can't schedule?** The 50% deposit hasn't been marked collected. That's Failure 0, and it's the first thing to check.
**Customer not getting messages?** Check phone/email on the job, then the dealer's messaging toggles.
**Job stuck in a status?** Rule out the deposit gate, then use the manual advance buttons on the Job Detail screen (but only when the physical work has been done).
**Account creation failing?** Look for an existing Lumina account; use **Re-send invite** if found.
**Account created but the app is empty?** Account creation doesn't attach controllers — run Installer Mode against that customer.
**Wrong data on the prospect?** Edit via the dealer admin flow. Past messages don't retrigger; future ones use the corrected data.
**Installer marked complete by accident?** Contact the dealer admin immediately, reach out to the customer, re-do the check-out properly.
**Schedules never fire?** Controller clock, missing coordinates, or a schedule that was pushed off-LAN. See Failure 9.

If a failure isn't covered in Section 6, contact your Nex-Gen LED LLC corporate contact.

---

**Need help?** This document is the master reference for the job pipeline. For role-specific guides, see the Sales Mode Guide, Day 1 Electrician Guide, Day 2 Install Guide, Dealer & Installer Setup Guide, and Corporate Dashboard Guide.
