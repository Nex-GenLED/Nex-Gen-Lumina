# Complete Job Lifecycle — From Prospect to Installed Customer

**Audience:** All roles — overview document for understanding how a Lumina job flows from initial prospect through installed, live customer

This is the master reference for the entire job pipeline. Use it to understand who owns each stage, what messages fire automatically, and how to recover from common failure modes.

---

## 1. The Full Pipeline at a Glance

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   PROSPECT                  INSTALL                  CUSTOMER        │
│   (Salesperson)             (Field crews)            (Live)          │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

  ┌────────┐    ┌──────────┐    ┌────────┐    ┌──────────┐    ┌──────────┐
  │ Draft  │───▶│ Estimate │───▶│ Signed │───▶│ Pre-wire │───▶│ Pre-wire │
  │        │    │   Sent   │    │        │    │Scheduled │    │ Complete │
  └────────┘    └──────────┘    └────────┘    └──────────┘    └──────────┘
                                     │                              │
                                     │                              ▼
                                     │                       ┌──────────┐
                                     │                       │  Install │
                                     │                       │Scheduled │
                                     │                       └──────────┘
                                     │                              │
                                     │                              ▼
                                     │                       ┌──────────┐
                                     └──────────────────────▶│  Install │
                                                             │ Complete │
                                                             └──────────┘
```

| Status | Owner | Plain English |
|---|---|---|
| **Draft** | Salesperson | Estimate is being built but not generated. |
| **Estimate Sent** | Salesperson | Estimate generated but customer hasn't signed. *(Used in legacy flows; the wizard usually goes straight to Signed.)* |
| **Signed** | Day 1 electrician | Customer signed. Job is officially booked. |
| **Pre-wire Scheduled** | Day 1 electrician | Day 1 has a date. |
| **Pre-wire Complete** | Day 2 install team | Wires are run. Ready for Day 2. |
| **Install Scheduled** | Day 2 install team | Day 2 has a date. |
| **Install Complete** | Customer | Job is closed. Customer has the lights. |

---

## 2. Stage-by-Stage Walkthrough

For each stage below, this section covers:
- **Owner** — whose responsibility it is to advance the job
- **What the user does** — the action that moves the job forward
- **What gets created/updated** — the data side effects
- **Automated messages fired** — what the customer receives
- **Customer experience** — what the customer sees from their side

### Stage 1 — Prospect → Draft

**Owner:** Salesperson

**What the user does:**
1. Salesperson opens Sales Mode and taps **New Visit**.
2. Fills in the **Customer Info** form (name, email, phone, address, optional referral code, notes, photos).
3. Taps **Continue to zones →**.

**What gets created:**
- A new sales job document in the dealer's collection with auto-generated job number (`NXG-{date}-{seq}`).
- The job has status **Draft**, the embedded prospect record, the dealer code, the salesperson's identifier, and a creation timestamp.
- Any home photos uploaded are stored against the job.
- If a valid referral code was entered, the referral pipeline is updated to "visit scheduled".

**Automated messages:** None. The customer is unaware so far.

**Customer experience:** Customer is sitting with the salesperson at this point. Nothing automated has fired yet.

---

### Stage 2 — Draft → (still Draft, building estimate)

**Owner:** Salesperson

**What the user does:**
The salesperson walks through the **5-step Estimate Wizard**:
1. **Step 1: Home Photo** — captures blueprint background photo.
2. **Step 2: Controller Placement** — describes mount location, interior/exterior, distance to outlet, optional photo.
3. **Step 3: Channel Setup** — adds one or more LED channel runs.
4. **Step 4: Power Injection Points** — adds injection points for runs over 100 ft.
5. **Step 5: Summary and Review** — reviews everything and taps **Generate Estimate**.

**What gets updated:**
- The job document is continuously updated as the wizard progresses (home photo URL, controller mount object, channel runs list, injection points list).
- On **Generate Estimate**, the system loads the dealer pricing and writes a full **EstimateBreakdown** to the job (line items by category, subtotals, margin).
- The job is still **Draft**.

**Automated messages:** None.

**Customer experience:** Still sitting with the salesperson. Sees the live estimate building on the device.

---

### Stage 3 — Draft → Signed

**Owner:** Salesperson (handing the device to the customer)

**What the user does:**
1. Salesperson taps the **Sign** flow from the estimate preview.
2. Hands the device to the customer.
3. Customer reviews the estimate, draws a signature in the canvas, and taps **Approve & confirm**.

**What gets updated:**
- Customer signature PNG is uploaded to the job's cloud folder.
- Job status moves to **Signed (`estimateSigned`)**.
- `estimateSignedAt` timestamp set.
- `customerSignatureUrl` populated.
- If a referral code was used, the referral pipeline moves to "confirmed" and the referrer's credit is locked in.
- The job becomes visible in the dealer's Day 1 Queue.

**Automated messages fired:**
- **Booking Confirmation Email** to the customer (subject: *"You're booked with Nex-Gen LED!"*) — explains the 2-day process, access requirements, and dealer contact.
  - *(Toggleable per dealer.)*

**Customer experience:** Customer signs and immediately sees a confirmation. Within seconds, they receive the booking email in their inbox.

---

### Stage 4 — Signed → Pre-wire Scheduled

**Owner:** Day 1 electrician

**What the user does:**
1. Electrician opens the Day 1 Queue.
2. Finds the new signed job.
3. Taps **Schedule Day 1**.
4. Picks a date in the date picker.

**What gets updated:**
- Job status moves to **Pre-wire Scheduled (`prewireScheduled`)**.
- `day1Date` is set.

**Automated messages fired:**
- **Day 1 Confirmation SMS** to the customer:
  > *"Hi {first name}, your Nex-Gen LED prep day is confirmed for {date}. Our technician will handle the wiring — no lights go up this day, that's Day 2. Questions? Reply here. — {dealer sign-off}"*

**Customer experience:** Customer receives an SMS confirming the Day 1 date.

---

### Stage 5 — Pre-wire Scheduled → (Day 1 visit happens)

**Owner:** Day 1 electrician

**What the user does:**
1. **The night before** the visit (6:00 PM Central), the system automatically sends the **Day 1 Reminder SMS** to the customer.
2. On the day of the visit, the electrician arrives on-site, opens the **Day 1 Blueprint** screen, and works through every task.
3. Each task is checked off in the app as it's completed.

**Automated messages fired during this stage:**
- **Day 1 Reminder SMS** (the night before, automatically) — reminds the customer about access requirements.
  - *(Toggleable per dealer.)*

**What gets updated:**
- `day1CompletedTaskIds` array is updated as tasks are checked.
- No status change yet — that happens at check-out.

**Customer experience:** Customer gets the reminder SMS the night before. On the day of the visit, the electrician shows up and runs all the wiring. The customer sees no lights yet.

---

### Stage 6 — Pre-wire Scheduled → Pre-wire Complete

**Owner:** Day 1 electrician

**What the user does:**
1. Electrician completes all tasks on the Day 1 Blueprint, including the verification task ("Verify all wires are accessible outside wall for Day 2").
2. Taps **Mark Day 1 complete**.
3. Confirms by entering their name in the dialog.

**What gets updated:**
- Job status moves to **Pre-wire Complete (`prewireComplete`)**.
- `day1CompletedAt` timestamp set.
- `day1TechUid` recorded.
- The job disappears from the Day 1 Queue and appears in the Day 2 Queue.

**Automated messages fired:**
- **Day 1 Complete SMS** to the customer:
  > *"Great news, {first name}! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — {dealer sign-off}"*

**Customer experience:** Customer receives a "wiring done" SMS the same day.

---

### Stage 7 — Pre-wire Complete → Install Scheduled

**Owner:** Day 2 install team

**What the user does:**
1. Day 2 installer opens the Day 2 Queue.
2. Finds the new pre-wire complete job.
3. Taps **Schedule Day 2**.
4. Picks a date (must be on or after the Day 1 completion date).

**What gets updated:**
- Job status moves to **Install Scheduled (`installScheduled`)**.
- `day2Date` is set.

**Automated messages fired:**
- **Day 2 Confirmation SMS** to the customer:
  > *"Hi {first name}, your Nex-Gen LED light installation is confirmed for {date}. Our install team will have your lights up and running. Get excited! — {dealer sign-off}"*

**Customer experience:** Customer receives an SMS confirming the install date.

---

### Stage 8 — Install Scheduled → (Day 2 visit happens)

**Owner:** Day 2 install team

**What the user does:**
1. **The night before** the visit (6:00 PM Central), the system automatically sends the **Day 2 Reminder SMS** to the customer.
2. On the day of the visit, the install team arrives, opens the Day 2 Blueprint, and works through every install task.

**Automated messages fired:**
- **Day 2 Reminder SMS** (the night before, automatically).
  - *(Toggleable per dealer.)*

**Customer experience:** Customer gets the reminder SMS, then watches the install team put up the lights.

---

### Stage 9 — Day 2 Wrap-Up Sequence (the most important step)

**Owner:** Day 2 install team

**What the user does:**
After all install tasks are checked, the installer taps **Wrap up install →** and walks through the 4-step wrap-up:

#### Step 1 — Install Photos
- Captures one completion photo per channel.
- Photos uploaded to the job's cloud folder.
- Step is gated — cannot proceed without photos for every channel.

#### Step 2 — Material Check-In
- Records returned quantity for each material in the estimate.
- App auto-calculates used quantity and waste percentage.
- Data persisted to the job's `actualMaterialUsage` field.
- Feeds the dealer's Waste Intelligence dashboard.

#### Step 3 — Customer Account Creation
- Installer confirms the customer's name and email.
- Taps **Create account**.
- The system calls a secure cloud function that:
  - Creates a new Firebase Auth user
  - Generates a password reset link
  - Sends the **Account Setup Email** to the customer (subject: *"Set up your Nex-Gen LED Lumina account"*) with the password reset link and app download buttons
  - Creates a `/users/{uid}` Firestore document tagged as the customer's primary account
- The new user's UID is saved on the job as `linkedUserId`.

#### Step 4 — Close Job
- Installer reviews the summary card (photos captured, materials checked in, account created).
- Taps **Finish & Close Job** and confirms in the dialog.

**What gets updated at close:**
- Job status moves to **Install Complete (`installComplete`)**.
- `day2CompletedAt` timestamp set.
- `day2TechUid` recorded.
- The job disappears from the Day 2 Queue.

**Automated messages fired at close:**
- **Install Complete Email** to the customer (subject: *"Your Nex-Gen LED system is live!"*) — confirms the install, provides app download links, references the account setup email, and signs off with the dealer name.
  - *(Toggleable per dealer.)*

**Customer experience:**
1. While the installer is on Step 3, the customer receives the **Account Setup Email** with their password link.
2. After Step 4 closes, the customer receives the **Install Complete Email** with download links.
3. The customer downloads Lumina, sets their password, signs in, and controls their lights for the first time.

---

## 3. Stage Summary Table — Who Owns What and What Fires

| # | Status | Owner | Trigger | Customer messages |
|---|---|---|---|---|
| 1 | **Draft** | Salesperson | Wizard in progress | None |
| 2 | **Estimate Sent** | Salesperson | (legacy) | None |
| 3 | **Signed** | Day 1 electrician | Customer taps **Approve & confirm** | Booking Confirmation Email |
| 4 | **Pre-wire Scheduled** | Day 1 electrician | Electrician picks Day 1 date | Day 1 Confirmation SMS |
| 5 | *(during wait)* | Day 1 electrician | Cron at 6pm Central night before | Day 1 Reminder SMS |
| 6 | **Pre-wire Complete** | Day 2 install team | Electrician taps **Mark Day 1 complete** | Day 1 Complete SMS |
| 7 | **Install Scheduled** | Day 2 install team | Installer picks Day 2 date | Day 2 Confirmation SMS |
| 8 | *(during wait)* | Day 2 install team | Cron at 6pm Central night before | Day 2 Reminder SMS |
| 9 | *(during wrap-up)* | Day 2 install team | Installer taps **Create account** in Step 3 | Account Setup Email |
| 10 | **Install Complete** | Customer | Installer taps **Finish & Close Job** | Install Complete Email |

---

## 4. Technical Integration Notes

This section is for technical operators who need to understand the data side. Field crews can skip this.

### Firestore documents touched at each stage

| Stage | Documents |
|---|---|
| **Draft creation** | `sales_jobs/{jobId}` created with embedded prospect; optional referral pipeline updated |
| **Wizard progress** | `sales_jobs/{jobId}` updated continuously (home photo URL, controller mount, channels, injections) |
| **Estimate generation** | `sales_jobs/{jobId}.estimateBreakdown` written |
| **Signature** | Signature PNG uploaded to Cloud Storage; job status → `estimateSigned`; signature URL written |
| **Day 1 schedule** | `sales_jobs/{jobId}.day1Date` + status → `prewireScheduled` |
| **Day 1 complete** | `sales_jobs/{jobId}.day1CompletedAt`, `day1TechUid`, status → `prewireComplete` |
| **Day 2 schedule** | `sales_jobs/{jobId}.day2Date` + status → `installScheduled` |
| **Wrap-up Step 1** | `sales_jobs/{jobId}.installCompletePhotoUrls` (positional list, 1 per channel) |
| **Wrap-up Step 2** | `sales_jobs/{jobId}.actualMaterialUsage` map (per item: estimated, returned, used, waste %) |
| **Wrap-up Step 3** | New Firebase Auth user; new `users/{uid}` document; `sales_jobs/{jobId}.linkedUserId` |
| **Wrap-up Step 4** | `sales_jobs/{jobId}.day2CompletedAt`, `day2TechUid`, status → `installComplete` |

### Cloud functions involved

| Function | Trigger | Purpose |
|---|---|---|
| **onSalesJobStatusChanged** | Firestore update on `sales_jobs/{jobId}` | Detects status transitions and Day 1 completion; sends Booking Confirmation Email, Day 1/Day 2 confirmation SMS, Day 1 complete SMS, and Install Complete Email |
| **sendInstallReminders** | Scheduled cron at 6pm Central daily | Queries jobs whose Day 1 or Day 2 date is tomorrow (Central time), sends reminder SMS to each |
| **createCustomerAccount** | Callable from Day 2 wrap-up Step 3 | Creates Firebase Auth user, sends Account Setup Email, seeds user profile document |

---

## 5. Common Failure Points and How to Recover

Things go wrong. This section covers the most common issues and how to fix them without losing customer data.

### Failure 1 — Customer phone number is invalid

**Symptom:** SMS reminders bounce or never arrive.

**What to do:**
1. Open the job in the dealer's My Estimates list.
2. Find the customer's phone field on the prospect info section.
3. Correct the number using the dealer admin's edit-job flow.
4. Subsequent SMS will use the corrected number. The previous failed messages will not auto-retry.
5. If the customer missed a reminder because of this, contact them directly to confirm the appointment.

### Failure 2 — Day 1 check-out is blocked because tasks are incomplete

**Symptom:** The **Mark Day 1 complete** button is grayed out and reads *"Complete all tasks to mark complete"*.

**What to do:**
1. Scroll up through the task checklist on the Day 1 Blueprint.
2. Look for any task without a green checkmark.
3. Common culprit: the verification task ("Verify all wires are accessible outside wall for Day 2") at the bottom — it's easy to miss.
4. Check the missing task(s).
5. The button will activate.

If the electrician genuinely cannot complete a task (e.g., a wire that should have been pre-run is missing), do **not** check it off falsely. Instead:
- Document the issue in the dealer admin
- Leave the job in `prewireScheduled` status
- Schedule a follow-up Day 1 visit

### Failure 3 — Customer account creation fails during wrap-up

**Symptom:** Step 3 of the wrap-up shows an error, no account is created, no email is sent.

**Possible causes:**
- Email already exists (the customer has a previous Lumina account)
- Email format invalid
- Network failure
- Backend service issue

**What to do:**
1. **If the email already exists:** Tap **Re-send invite** to send a fresh password reset link to the existing account. If the customer doesn't recognize the existing account, contact your dealer admin to investigate.
2. **If the format is invalid:** Verify the email with the customer, edit it on the prospect record, and try again.
3. **If you cannot resolve it on-site:** Continue through Step 4 to close the job. The customer will not receive their account setup email automatically — contact your dealer admin and have them manually provision the account afterwards.

### Failure 4 — Job is stuck in a status

**Symptom:** A job sits in one status for many days. Customer or dealer wants to advance it.

**Common scenarios:**
- A job is **Signed** but no electrician has picked it up.
- A job is **Pre-wire Complete** but no installer has scheduled Day 2.
- A job somehow got into the wrong status (e.g., manual data correction needed).

**What to do:**

**For genuinely stalled jobs:**
1. Open the job in the dealer's **My Estimates** list (or for corporate, the Pipeline tab).
2. Tap the job to open the **Job Detail** screen.
3. The Job Detail screen has **manual status advance buttons** that appear depending on the current status:
   - **Signed** → "Schedule pre-wire" (advances to `prewireScheduled`)
   - **Pre-wire Scheduled** → "Mark pre-wire complete" (advances to `prewireComplete`)
   - **Pre-wire Complete** → "Mark install complete" (advances to `installComplete`)
   - **Install Scheduled** → "Mark install complete" (advances to `installComplete`)
4. Tap the appropriate button to manually move the job forward.

**Important:** Manual advances will still trigger the corresponding automated messages. Use this only when you actually want the customer to receive the next message — don't manually advance a job whose physical work hasn't actually been done.

### Failure 5 — Wrong photo or info on the prospect

**Symptom:** Salesperson typed something incorrectly or attached the wrong photo.

**What to do:**
1. Open the job from My Estimates.
2. Resume the wizard or use the dealer admin's edit flow.
3. Correct the field, save.
4. If the job is still in **Draft**, no automated messages have fired and you can edit freely.
5. If the job is **Signed** or beyond, edits to the prospect data don't re-trigger any prior messages — they only affect future messages and the install crews' view of the job.

### Failure 6 — Installer marks Day 1 or Day 2 complete by accident

**Symptom:** Job is at `prewireComplete` or `installComplete` but the work isn't actually done.

**What to do:**
1. Contact the dealer admin immediately.
2. The dealer admin can manually correct the job status using backend tools.
3. **The customer will have already received the next-stage SMS or email.** Reach out to the customer directly to clarify the situation.
4. Re-do the work with the proper check-out flow.

This is one of the most damaging errors because it triggers customer messages that don't match reality. Train installers to double-check before tapping the complete button.

### Failure 7 — Reminder SMS didn't arrive the night before

**Symptom:** Customer says they didn't get the reminder.

**Possible causes:**
- The dealer disabled the reminder toggle
- The customer's phone is wrong
- The job's date wasn't actually scheduled
- SMS provider hiccup

**What to do:**
1. Check the dealer's messaging configuration — confirm the relevant reminder toggle (Day 1 or Day 2) is on.
2. Verify the customer's phone number on the job.
3. Verify the job's `day1Date` or `day2Date` is correct.
4. If everything is correct, this was probably a one-off provider hiccup. Send a manual reminder via your usual support channels and confirm the appointment with the customer directly.

### Failure 8 — Photo upload fails during the wizard or wrap-up

**Symptom:** A photo capture fails to upload.

**What to do:**
1. Check the device's network connection.
2. Retry the capture.
3. If the upload still fails, save the photo to the device gallery and try uploading from there.
4. If the wrap-up Step 1 (install photos) is the blocker, you cannot proceed past Step 1 without a photo for every channel — keep trying until they upload.

---

## 6. The Customer's End-to-End Experience

From the customer's point of view, here's what happens during a Lumina install:

| Day | Event | Channel |
|---|---|---|
| **Day 0** (sales visit) | Salesperson visits and walks through the wizard live | In person |
| **Day 0** | Customer signs the estimate on the device | In person |
| **Day 0** (within seconds) | Booking confirmation email arrives | Email |
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

The whole experience is designed so the customer is always informed and never has to chase the dealer for status updates.

---

**Need help?** This document is the master reference for the job pipeline. For role-specific guides, see the Sales Mode Guide, Day 1 Electrician Guide, Day 2 Install Guide, and Corporate Dashboard Guide.
