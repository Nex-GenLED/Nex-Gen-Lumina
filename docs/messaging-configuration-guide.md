# Customer Messaging Configuration — Guide

**Audience:** Dealers configuring how Lumina automatically communicates with their customers

Lumina sends automated emails and SMS messages to customers throughout the install process. This guide explains every message that goes out, when it fires, what the customer sees, and how to customize the parts you control.

---

## 1. Overview of the Automated Messaging System

Lumina sends messages on your behalf at every meaningful point in the customer journey. You don't have to send them manually — the system fires them automatically based on the job's status.

### What gets sent

There are **8 automated customer touchpoints** in total:

| # | Trigger | Channel | When |
|---|---|---|---|
| 1 | Estimate signed | **Email** | Immediately when the customer signs the estimate |
| 2 | Day 1 scheduled | **SMS** | Immediately when an electrician schedules Day 1 |
| 3 | Day 1 reminder | **SMS** | 6:00 PM Central, the evening before Day 1 |
| 4 | Day 1 complete | **SMS** | Immediately when the electrician marks Day 1 complete |
| 5 | Day 2 scheduled | **SMS** | Immediately when an installer schedules Day 2 |
| 6 | Day 2 reminder | **SMS** | 6:00 PM Central, the evening before Day 2 |
| 7 | Customer account created | **Email** | When the install team creates the account during Day 2 wrap-up |
| 8 | Install complete | **Email** | Immediately when the install team closes the job |

You can toggle several of these on or off in the Messaging Configuration screen — see Section 4.

---

## 2. Full Message Timeline

Here's what every customer sees, in the order they see it.

### Trigger 1 — Estimate signed → Booking confirmation email

**When it fires:** The moment the customer taps **Approve & confirm** on the signature screen.

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

**Purpose:** Sets expectations immediately so the customer isn't surprised by the 2-day process.

**Toggle:** Booking Confirmation Email *(can be disabled per dealer)*

---

### Trigger 2 — Day 1 scheduled → Date confirmation SMS

**When it fires:** The moment a Day 1 electrician picks a date in the Day 1 Queue.

**Type:** SMS

**Contents (paraphrased):**
> *"Hi {first name}, your Nex-Gen LED prep day is confirmed for {date}. {Tech name or 'Our technician'} will handle the wiring — no lights go up this day, that's Day 2. Questions? Reply here. — {dealer sign-off}"*

**Purpose:** Locks in the appointment in writing so the customer can plan around it.

**Toggle:** Always sends — cannot be disabled.

---

### Trigger 3 — Day 1 reminder → Reminder SMS the evening before

**When it fires:** Automatically every day at **6:00 PM Central Time**, for jobs whose Day 1 date is **tomorrow** (in the Central time zone).

**Type:** SMS

**Contents (paraphrased):**
> *"Hi {first name}! 👋 Just a reminder — tomorrow is your {dealer sign-off} prep day. {Tech name or 'Our technician'} will be there at your home to run all wiring. Please make sure we have access to: your electrical panel, garage or utility area, and exterior eaves. No lights go up tomorrow — that's Day 2! See you then. — {dealer sign-off}"*

**Purpose:** Cuts no-shows and access problems by reminding the customer just before the visit.

**Toggle:** Day 1 Reminder SMS

---

### Trigger 4 — Day 1 complete → "Wiring done" SMS

**When it fires:** The moment the electrician marks Day 1 complete in the Day 1 Blueprint screen.

**Type:** SMS

**Contents (paraphrased):**
> *"Great news, {first name}! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — {dealer sign-off}"*

**Purpose:** Reassures the customer that progress is happening even though they don't see lights yet.

**Toggle:** Always sends — cannot be disabled.

---

### Trigger 5 — Day 2 scheduled → Install confirmation SMS

**When it fires:** The moment a Day 2 install team picks a date in the Day 2 Queue.

**Type:** SMS

**Contents (paraphrased):**
> *"Hi {first name}, your Nex-Gen LED light installation is confirmed for {date}. Our install team will have your lights up and running. Get excited! — {dealer sign-off}"*

**Purpose:** Locks in the install appointment and builds anticipation.

**Toggle:** Always sends — cannot be disabled.

---

### Trigger 6 — Day 2 reminder → Reminder SMS the evening before

**When it fires:** Automatically every day at **6:00 PM Central Time**, for jobs whose Day 2 date is **tomorrow** (in the Central time zone).

**Type:** SMS

**Contents (paraphrased):**
> *"Hi {first name}! 🎉 Big day tomorrow — your {dealer sign-off} lights go up! Our install team will be at your home to complete the full installation. No electrical access needed tomorrow — just the exterior of your home. Get ready to see it light up! — {dealer sign-off}"*

**Purpose:** Maximizes excitement and confirms the appointment one final time.

**Toggle:** Day 2 Reminder SMS

---

### Trigger 7 — Customer account created → Account setup email

**When it fires:** During Day 2 wrap-up Step 3, when the install team taps **Create account**.

**Type:** Email

**Subject:** *"Set up your Nex-Gen LED Lumina account"*

**Contents (paraphrased):**
- Personal greeting using the customer's first name
- Note that their Lumina account is ready and just needs a password
- A **password reset link** that takes them to a secure page where they set their password
- App Store / Google Play download buttons
- Welcome message

**Purpose:** Hands the customer the keys to their lighting system. They use this email to create their password and download the app.

**Toggle:** Always sends as part of account creation. *(There is no separate dealer-level toggle for this email — it's tied to the account creation step itself.)*

---

### Trigger 8 — Install complete → Welcome email with download links

**When it fires:** The moment the install team confirms **Finish & Close Job** in Step 4 of the Day 2 wrap-up.

**Type:** Email

**Subject:** *"Your Nex-Gen LED system is live!"*

**Contents (paraphrased):**
- Personal greeting using the customer's first name
- Confirmation that the system is installed and ready
- App Store / Google Play download buttons
- A note pointing to the account setup email they got in Trigger 7
- Welcome to the family
- Sign-off referencing the dealer name

**Purpose:** Final wrap-up touchpoint. Tells the customer everything is done and reminds them how to get into the app.

**Toggle:** Install Complete Email

---

## 3. Accessing Messaging Configuration

The Messaging Configuration screen lives in the **Dealer Dashboard**.

1. Sign in to **Sales Mode** or **Installer Mode** with your dealer PIN.
2. Tap **Dashboard** (or **Dealer Dashboard** from the installer landing screen).
3. Navigate to the **Messaging** tab.

You'll see four sections:
1. **Sender Identity**
2. **Message Toggles**
3. **Custom SMS Sign-Off**
4. **Live Preview**

A sticky **Save messaging settings** button lives at the bottom of the screen.

---

## 4. Sender Identity Settings

These three fields define how your dealer name appears in customer-facing messages.

| Field | What it controls |
|---|---|
| **Sender Name** | The name that appears at the end of every SMS message (e.g., *"— Smith Lighting"*). This is the default sign-off if you don't set a custom one. **Required.** |
| **Reply Phone** | A US phone number shown in customer emails so they know how to reach you directly. Use a number you actually answer. |
| **Support Email** | An email address shown in booking confirmation and completion emails. Customers may reply here with questions. |

**Validation:**
- **Sender Name** is required. If you try to save with it blank, you'll get an error.
- The phone and email fields are free-text and not strictly validated, but use real values — customers will see them.

---

## 5. Message Toggles

Five switches control which message types are enabled. Each toggle has a subtitle explaining when the message fires.

| Toggle | Default | Subtitle |
|---|---|---|
| **Booking Confirmation Email** | On | "Sent immediately when a customer signs their estimate" |
| **Day 1 Reminder SMS** | On | "Sent the evening before the wiring prep visit" |
| **Day 2 Reminder SMS** | On | "Sent the evening before the light installation" |
| **Install Complete Email** | On | "Sent when the job is marked complete with Lumina download links" |
| **Default SMS Opt-In** | On | "New prospects are opted in to text messages by default" |

### Notes on toggles

- **Confirmation messages** (Day 1 scheduled, Day 1 complete, Day 2 scheduled) are NOT toggleable — they always send. These are essential operational notifications and disabling them would break the customer experience.
- **Reminder messages** (Day 1 reminder, Day 2 reminder) are toggleable. Most dealers leave them on.
- **Default SMS Opt-In** controls whether new prospects you create are opted in to text messaging by default. Turning this off means you'd need to manually opt customers in before they could receive any SMS.
- The **Account Setup Email** (Trigger 7) always sends as part of account creation — there is no separate dealer-level toggle.

---

## 6. Custom SMS Sign-Off

Below the toggles is a single text field for a **Custom SMS Sign-Off**.

- **Character limit:** 30 characters
- A character counter shows your usage (e.g., `12/30`)
- Leave it blank to use **"Nex-Gen LED"** as the default sign-off

### How the sign-off is resolved

The system picks the sign-off in this order of precedence:

1. **Custom SMS Sign-Off** (if set and not empty)
2. **Sender Name** (if set and not empty)
3. **"Nex-Gen LED"** (final fallback)

### When to use it

Most dealers set the **Sender Name** field and leave the custom sign-off blank — that gives them a single name everywhere. But if you want a punchier or branded text-message sign-off (e.g., *"Smith Lighting Crew"* in SMS but *"Smith Lighting LLC"* in formal emails), use the custom SMS sign-off to override.

---

## 7. Live Preview

Below the form fields is a **Live Preview** card that shows a sample SMS — usually the Day 1 reminder template — rendered with your current settings applied.

As you type into the **Sender Name** or **Custom SMS Sign-Off** fields, the preview updates in real time so you can see exactly what the customer will receive before you save.

Use this to:
- Check the spelling and tone of your sign-off
- Verify the character count looks good
- Make sure your dealer name reads naturally in the message

---

## 8. Saving Changes

When you're ready, tap **Save messaging settings** at the bottom of the screen.

### What happens
1. The button shows a spinner while saving.
2. The app validates the form (Sender Name must not be empty).
3. On success, a **green snackbar** appears: *"Messaging settings saved"*.
4. The new settings take effect immediately for all future automated messages.
5. If save fails, a **red snackbar** explains the error.

### What gets saved
Your settings are stored against your dealer record. Every customer message — across every salesperson and installer in your dealer — uses these settings.

---

## 9. What Customers See — Example Messages

Below are the actual texts customers receive with your dealer settings applied. Your dealer's sign-off and sender identity will substitute into the placeholders.

### Example Booking Confirmation Email (Trigger 1)

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

### Example Day 1 Confirmation SMS (Trigger 2)

> Hi Sarah, your Nex-Gen LED prep day is confirmed for Tuesday, April 15. Our technician will handle the wiring — no lights go up this day, that's Day 2. Questions? Reply here. — Smith Lighting

### Example Day 1 Reminder SMS (Trigger 3)

> Hi Sarah! 👋 Just a reminder — tomorrow is your Smith Lighting prep day. Our technician will be there at your home to run all wiring. Please make sure we have access to: your electrical panel, garage or utility area, and exterior eaves. No lights go up tomorrow — that's Day 2! See you then. — Smith Lighting

### Example Day 1 Complete SMS (Trigger 4)

> Great news, Sarah! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — Smith Lighting

### Example Day 2 Confirmation SMS (Trigger 5)

> Hi Sarah, your Nex-Gen LED light installation is confirmed for Friday, April 18. Our install team will have your lights up and running. Get excited! — Smith Lighting

### Example Day 2 Reminder SMS (Trigger 6)

> Hi Sarah! 🎉 Big day tomorrow — your Smith Lighting lights go up! Our install team will be at your home to complete the full installation. No electrical access needed tomorrow — just the exterior of your home. Get ready to see it light up! — Smith Lighting

### Example Account Setup Email (Trigger 7)

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

### Example Install Complete Email (Trigger 8)

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

## 10. Quick Reference

| I want to... | Do this |
|---|---|
| **Change how my dealer name appears in SMS** | Update **Sender Name** (or use **Custom SMS Sign-Off** for a different SMS-only version) |
| **Stop sending night-before reminders** | Toggle off **Day 1 Reminder SMS** and/or **Day 2 Reminder SMS** |
| **Skip the booking confirmation email** | Toggle off **Booking Confirmation Email** |
| **Set the support email customers see** | Update **Support Email** under Sender Identity |
| **Preview a message before saving** | Watch the **Live Preview** card update as you type |
| **Push my changes live** | Tap **Save messaging settings** at the bottom |

---

**Need help?** Contact your Nex-Gen LED corporate contact.
