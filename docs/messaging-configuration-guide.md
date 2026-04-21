# Customer Messaging Configuration — Guide

**Audience:** Dealers configuring how Lumina automatically communicates with their customers.

Lumina sends emails and SMS to your customers on your behalf at every meaningful moment in the install. Booking confirmations, scheduled-date texts, night-before reminders, "wiring done" updates, account handoff, "your system is live." All automatic. This guide shows every message that goes out, when it fires, what it says, and the parts you control. Get your sender identity and toggles dialed in and the customer experience runs itself — that's fewer support calls, higher review scores, and more referrals.

## What you'll need

- The Lumina app on your phone or tablet
- Your **Sales PIN** or **Installer PIN**
- Your dealer's sender name (what customers see in the signature on every SMS and email)
- A support phone and email that you actually answer

---

## 1. How the automated messaging system works

Lumina sends messages on your behalf at every meaningful point in the customer journey. You don't send them manually — the system fires them automatically based on the job's status.

### What gets sent

**8 automated customer touchpoints** total:

| # | Trigger | Channel | When |
|---|---|---|---|
| 1 | Estimate signed | **Email** | Immediately when the customer signs |
| 2 | Day 1 scheduled | **SMS** | Immediately when an electrician schedules Day 1 |
| 3 | Day 1 reminder | **SMS** | 6:00 PM Central, the evening before Day 1 |
| 4 | Day 1 complete | **SMS** | Immediately when the electrician marks Day 1 complete |
| 5 | Day 2 scheduled | **SMS** | Immediately when an installer schedules Day 2 |
| 6 | Day 2 reminder | **SMS** | 6:00 PM Central, the evening before Day 2 |
| 7 | Customer account created | **Email** | When the install team creates the account during Day 2 wrap-up |
| 8 | Install complete | **Email** | Immediately when the install team closes the job |

Several of these are toggleable — see Section 4.

---

## 2. The full message timeline

Here's what every customer sees, in the order they see it.

### Trigger 1 — Estimate signed → Booking confirmation email

**When it fires:** the moment the customer taps **Approve & confirm** on the signature screen.

**Type:** Email

**Subject:** *"You're booked with Nex-Gen LED!"*

**Contents (paraphrased):**

- Personal greeting using the customer's first name
- Confirmation that their permanent LED lighting system is booked
- Explanation of the 2-day install process:
  - **Day 1** — Electrician runs all the wiring; **no lights go up that day**
  - **Day 2** — Install team arrives and the lights go up
- Note that they'll receive a text reminder the night before each visit
- Access requirements list: electrical panel, garage/utility area, exterior eaves
- Sign-off: *"Questions or scheduling changes? Reach out to {your dealer name} anytime."*
- Welcome to the Nex-Gen LED family

**Purpose:** sets expectations immediately so the customer isn't surprised by the 2-day process.

**Toggle:** Booking Confirmation Email *(can be disabled per dealer)*

---

### Trigger 2 — Day 1 scheduled → Date confirmation SMS

**When it fires:** the moment a Day 1 electrician picks a date in the Day 1 Queue.

**Type:** SMS

**Contents (paraphrased):**

> *"Hi {first name}, your Nex-Gen LED prep day is confirmed for {date}. {Tech name or 'Our technician'} will handle the wiring — no lights go up this day, that's Day 2. Questions? Reply here. — {dealer sign-off}"*

**Purpose:** locks in the appointment in writing so the customer can plan around it.

**Toggle:** always sends — cannot be disabled.

---

### Trigger 3 — Day 1 reminder → Reminder SMS the evening before

**When it fires:** automatically every day at **6:00 PM Central**, for jobs whose Day 1 date is tomorrow (Central time).

**Type:** SMS

**Contents (paraphrased):**

> *"Hi {first name}! 👋 Just a reminder — tomorrow is your {dealer sign-off} prep day. {Tech name or 'Our technician'} will be there at your home to run all wiring. Please make sure we have access to: your electrical panel, garage or utility area, and exterior eaves. No lights go up tomorrow — that's Day 2! See you then. — {dealer sign-off}"*

**Purpose:** cuts no-shows and access problems by reminding the customer just before the visit.

**Toggle:** Day 1 Reminder SMS

---

### Trigger 4 — Day 1 complete → "Wiring done" SMS

**When it fires:** the moment the electrician marks Day 1 complete in the Day 1 Blueprint.

**Type:** SMS

**Contents (paraphrased):**

> *"Great news, {first name}! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — {dealer sign-off}"*

**Purpose:** reassures the customer that progress is happening even though they don't see lights yet.

**Toggle:** always sends — cannot be disabled.

---

### Trigger 5 — Day 2 scheduled → Install confirmation SMS

**When it fires:** the moment a Day 2 install team picks a date in the Day 2 Queue.

**Type:** SMS

**Contents (paraphrased):**

> *"Hi {first name}, your Nex-Gen LED light installation is confirmed for {date}. Our install team will have your lights up and running. Get excited! — {dealer sign-off}"*

**Purpose:** locks in the install appointment and builds anticipation.

**Toggle:** always sends — cannot be disabled.

---

### Trigger 6 — Day 2 reminder → Reminder SMS the evening before

**When it fires:** automatically every day at **6:00 PM Central**, for jobs whose Day 2 date is tomorrow.

**Type:** SMS

**Contents (paraphrased):**

> *"Hi {first name}! 🎉 Big day tomorrow — your {dealer sign-off} lights go up! Our install team will be at your home to complete the full installation. No electrical access needed tomorrow — just the exterior of your home. Get ready to see it light up! — {dealer sign-off}"*

**Purpose:** maximizes excitement and confirms the appointment one final time.

**Toggle:** Day 2 Reminder SMS

---

### Trigger 7 — Customer account created → Account setup email

**When it fires:** during Day 2 wrap-up Step 3, when the install team taps **Create account**.

**Type:** Email

**Subject:** *"Set up your Nex-Gen LED Lumina account"*

**Contents (paraphrased):**

- Personal greeting using the customer's first name
- Note that their Lumina account is ready and just needs a password
- A **password reset link** that takes them to a secure page where they set their password
- App Store / Google Play download buttons
- Welcome message

**Purpose:** hands the customer the keys to their lighting system. They use this email to create their password and download the app.

**Toggle:** always sends as part of account creation. *(No separate dealer-level toggle — it's tied to the account creation step itself.)*

---

### Trigger 8 — Install complete → Welcome email with download links

**When it fires:** the moment the install team confirms **Finish & Close Job** in Step 4 of the Day 2 wrap-up.

**Type:** Email

**Subject:** *"Your Nex-Gen LED system is live!"*

**Contents (paraphrased):**

- Personal greeting using the customer's first name
- Confirmation that the system is installed and ready
- App Store / Google Play download buttons
- A note pointing to the account setup email they got in Trigger 7
- Welcome to the family
- Sign-off referencing the dealer name

**Purpose:** final wrap-up touchpoint. Tells the customer everything is done and reminds them how to get into the app.

**Toggle:** Install Complete Email

---

## 3. Getting to the Messaging Configuration screen

The Messaging Configuration screen lives in the **Dealer Dashboard**.

1. Sign in to Sales Mode or Installer Mode with your dealer PIN
2. Tap **Dashboard** (or **Dealer Dashboard** from the installer landing screen)
3. Tap the **Messaging** tab

You'll see four sections:

1. **Sender Identity**
2. **Message Toggles**
3. **Custom SMS Sign-Off**
4. **Live Preview**

A sticky **Save messaging settings** button lives at the bottom.

---

## 4. Sender identity

Three fields that define how your dealer name appears in customer-facing messages.

| Field | What it controls |
|---|---|
| **Sender Name** | The name that appears at the end of every SMS (e.g., *"— Smith Lighting"*). Default sign-off if you don't set a custom one. **Required.** |
| **Reply Phone** | A US phone number shown in customer emails so they know how to reach you. **Use a number you actually answer.** |
| **Support Email** | The email address in booking confirmation and completion emails. Customers may reply here. |

**Validation:**

- **Sender Name** is required — save fails if blank
- Phone and email aren't strictly validated, but use real values — customers see them

---

## 5. Message toggles

Five switches control which message types are enabled. Each has a subtitle explaining when it fires.

| Toggle | Default | Subtitle |
|---|---|---|
| **Booking Confirmation Email** | On | "Sent immediately when a customer signs their estimate" |
| **Day 1 Reminder SMS** | On | "Sent the evening before the wiring prep visit" |
| **Day 2 Reminder SMS** | On | "Sent the evening before the light installation" |
| **Install Complete Email** | On | "Sent when the job is marked complete with Lumina download links" |
| **Default SMS Opt-In** | On | "New prospects are opted in to text messages by default" |

### Notes

- **Confirmation messages** (Day 1 scheduled, Day 1 complete, Day 2 scheduled) are NOT toggleable — they always send. These are essential operational notifications and disabling them would break the customer experience.
- **Reminder messages** (Day 1 reminder, Day 2 reminder) are toggleable. Most dealers leave them on — every minute spent on missed-appointment recovery is time you don't get back.
- **Default SMS Opt-In** controls whether new prospects you create are opted in to text messaging by default. Turn this off and you'd need to manually opt customers in before they could receive any SMS.
- The **Account Setup Email** (Trigger 7) always sends as part of account creation — no separate dealer-level toggle.

---

## 6. Custom SMS sign-off

A single text field for a **Custom SMS Sign-Off**.

- **Character limit:** 30 characters
- A character counter shows your usage (e.g., `12/30`)
- Leave it blank to use **"Nex-Gen LED"** as the default sign-off

### How the sign-off is resolved

The system picks in this order:

1. **Custom SMS Sign-Off** (if set and not empty)
2. **Sender Name** (if set and not empty)
3. **"Nex-Gen LED"** (final fallback)

### When to use it

Most dealers set the **Sender Name** and leave the custom sign-off blank — one name everywhere. But if you want a punchier or branded text sign-off (e.g., *"Smith Lighting Crew"* in SMS, *"Smith Lighting LLC"* in formal emails), use the custom SMS sign-off to override.

---

## 7. Live Preview

Below the form fields is a **Live Preview** card showing a sample SMS — usually the Day 1 reminder template — rendered with your current settings.

As you type into **Sender Name** or **Custom SMS Sign-Off**, the preview updates in real time so you can see exactly what the customer will receive before you save.

Use it to:

- Check the spelling and tone of your sign-off
- Verify the character count looks good
- Make sure your dealer name reads naturally in the message

---

## 8. Saving changes

Tap **Save messaging settings** at the bottom.

1. The button shows a spinner while saving
2. The app validates the form (Sender Name must not be empty)
3. On success: green snackbar — *"Messaging settings saved"*
4. New settings take effect immediately for all future messages
5. If save fails, a red snackbar explains the error

### What gets saved

Your settings are stored against your dealer record. Every customer message — across every salesperson and installer in your dealer — uses these settings.

---

## 9. Example messages — what customers actually see

Below are the real texts customers receive with your dealer settings applied. Your sign-off and sender identity substitute into the placeholders.

### Booking Confirmation Email (Trigger 1)

> Subject: **You're booked with Nex-Gen LED!**
>
> Hi Sarah,
>
> Your permanent LED lighting system is confirmed. Here's what happens next:
>
> **Step 1 — Day 1 (Wiring prep):** An electrician will visit your home to run all wiring. No lights go up this day.
>
> **Step 2 — Day 2 (Installation):** Our install team will arrive and the lights will go up.
>
> We'll send you a text reminder the night before each visit. To make Day 1 smooth, please make sure we'll have access to: your electrical panel, garage or utility area, and the exterior eaves of your home.
>
> Questions or scheduling changes? Reach out to **{your dealer name}** anytime.
>
> Welcome to the Nex-Gen LED family!

### Day 1 Confirmation SMS (Trigger 2)

> Hi Sarah, your Nex-Gen LED prep day is confirmed for Tuesday, April 15. Our technician will handle the wiring — no lights go up this day, that's Day 2. Questions? Reply here. — Smith Lighting

### Day 1 Reminder SMS (Trigger 3)

> Hi Sarah! 👋 Just a reminder — tomorrow is your Smith Lighting prep day. Our technician will be there at your home to run all wiring. Please make sure we have access to: your electrical panel, garage or utility area, and exterior eaves. No lights go up tomorrow — that's Day 2! See you then. — Smith Lighting

### Day 1 Complete SMS (Trigger 4)

> Great news, Sarah! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — Smith Lighting

### Day 2 Confirmation SMS (Trigger 5)

> Hi Sarah, your Nex-Gen LED light installation is confirmed for Friday, April 18. Our install team will have your lights up and running. Get excited! — Smith Lighting

### Day 2 Reminder SMS (Trigger 6)

> Hi Sarah! 🎉 Big day tomorrow — your Smith Lighting lights go up! Our install team will be at your home to complete the full installation. No electrical access needed tomorrow — just the exterior of your home. Get ready to see it light up! — Smith Lighting

### Account Setup Email (Trigger 7)

> Subject: **Set up your Nex-Gen LED Lumina account**
>
> Hi Sarah,
>
> Welcome to Nex-Gen LED! Your Lumina account is ready and just needs a password.
>
> **Set your password using this link:** [secure password setup link]
>
> (This link is tied to sarah@example.com. If you didn't expect this email, you can safely ignore it.)
>
> Once your password is set, download Lumina to control your lights:
>
> [Download for iPhone] [Download for Android]
>
> Welcome to the family!
>
> — Nex-Gen LED

### Install Complete Email (Trigger 8)

> Subject: **Your Nex-Gen LED system is live!**
>
> Hi Sarah,
>
> Your permanent LED lighting system is installed and ready.
>
> **Download Lumina to control your lights:**
>
> [Download for iPhone] [Download for Android]
>
> Your login was sent to sarah@example.com. Check your inbox for your account setup email.
>
> Welcome to the Nex-Gen LED family — we can't wait to see your home lit up.
>
> Questions? **{your dealer name}** is here for you.

---

## 10. Quick reference

| I want to... | Do this |
|---|---|
| Change how my dealer name appears in SMS | Update **Sender Name** (or **Custom SMS Sign-Off** for a different SMS-only version) |
| Stop sending night-before reminders | Toggle off **Day 1 Reminder SMS** and/or **Day 2 Reminder SMS** |
| Skip the booking confirmation email | Toggle off **Booking Confirmation Email** |
| Set the support email customers see | Update **Support Email** under Sender Identity |
| Preview a message before saving | Watch the **Live Preview** update as you type |
| Push changes live | Tap **Save messaging settings** at the bottom |

---

## What success looks like

- Every customer gets a booking confirmation email within seconds of signing
- Customers consistently reply to your reminder SMS with "see you then" instead of rescheduling
- No-shows on Day 1 and Day 2 drop to near zero after you turn reminders on
- Your sender name reads cleanly in every message — no awkward abbreviations or missing characters
- Review scores mention the "smooth communication" through the process

## If something isn't working

**"Customers aren't getting the booking confirmation."**
Verify **Booking Confirmation Email** is toggled on. Confirm the customer's email on the prospect record. If the email is correct and the toggle is on, check with Nex-Gen LED LLC support — the delivery service may be flagged.

**"Reminders aren't sending the night before."**
Confirm **Day 1 Reminder SMS** (or Day 2) is toggled on. Confirm the customer's phone number is valid and US-format. Confirm the job actually has a `day1Date` or `day2Date` set — if the date field is empty the cron won't fire.

**"The sign-off looks weird in messages."**
Open the **Live Preview** and retype your Sender Name or Custom SMS Sign-Off. Watch the preview update. The 30-character limit on custom sign-offs means long dealer names get truncated — use a shorter version for SMS.

**"A customer replied 'STOP' and now they get no messages."**
That's carrier-level opt-out — you can't override it from the dashboard. Reach the customer directly to confirm their appointment; subsequent automated messages won't deliver until they opt back in.

**"Save fails with 'Sender Name required'."**
You blanked out the **Sender Name** field. It's required. Add your dealer name and save again.

---

**Need help?** Contact your Nex-Gen LED LLC corporate contact.
