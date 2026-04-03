---
title: "Nex-Gen Lumina — Sales Mode Guide"
subtitle: "A field guide for sales representatives conducting site surveys and generating estimates"
author: "Nex-Gen LED"
date: "April 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Nex-Gen Lumina — Sales Mode Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: []
body_class: guide
---

<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; color: #222; line-height: 1.6; }
  h1 { color: #00B8D4; border-bottom: 2px solid #00B8D4; padding-bottom: 8px; }
  h2 { color: #00E5FF; margin-top: 28px; }
  h3 { color: #333; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; }
  th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
  th { background: #00B8D4; color: white; }
  .tip { background: #E0F7FA; border-left: 4px solid #00B8D4; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .warning { background: #FFF3E0; border-left: 4px solid #FF9800; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .step-box { background: #F5F5F5; border: 1px solid #ddd; border-radius: 8px; padding: 14px; margin: 10px 0; }
  code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
</style>

# Nex-Gen Lumina — Sales Mode Guide

Welcome to the Nex-Gen Lumina Sales Mode guide. This document is written for **sales representatives** who use the Lumina app to conduct on-site LED lighting surveys, build zone plans, generate professional estimates, and collect customer signatures — all from a single mobile device.

---

## 1. Overview

Sales Mode is a dedicated field tool built into the Nex-Gen Lumina app. It gives you everything you need to run a complete site visit without leaving the app:

- **Prospect capture** — record customer contact information and home photos on-site
- **Zone builder** — map LED run lengths, injection points, power mounts, and product types for each area of the home
- **Estimate generation** — automatically build a professional, itemized estimate from your zone measurements
- **Customer signature** — present the estimate and collect a digital signature right on your phone or tablet
- **Job tracking** — follow each job from draft through pre-wire to completed installation

Sales Mode is accessible from the login screen or from Settings within the app. You do not need a customer account to use it — just your Sales PIN.

---

## 2. Entering Sales Mode

### From the Login Screen

1. Open the Nex-Gen Lumina app
2. On the login screen, tap **Sales Mode**
3. You are taken to the **Sales PIN Screen**

### From Settings (if already logged in)

1. Navigate to **System > Settings**
2. Tap **Sales Mode**

### Entering Your PIN

<div class="step-box">

1. The Sales PIN Screen displays a 4-digit numeric keypad
2. Enter your **4-digit Sales PIN**
3. The PIN **auto-submits** as soon as all 4 digits are entered — no need to tap a button
4. If the PIN is valid, you land on the **Sales Landing Screen**

</div>

Your PIN is validated against the master sales PIN stored securely in Firestore. The first two digits of your PIN identify your dealer code.

<div class="warning">
<strong>Lockout:</strong> After <strong>5 failed PIN attempts</strong>, you are locked out. You must restart the app to reset the attempt counter. If you cannot remember your PIN, contact your dealer admin.
</div>

---

## 3. Session Rules

Sales Mode sessions are time-limited to protect sensitive customer and pricing data.

| Rule | Detail |
|------|--------|
| **Session length** | 30 minutes of inactivity |
| **Warning** | A dialog appears 5 minutes before timeout |
| **Extend** | Tap **Extend** on the warning dialog to reset the timer |
| **Timeout** | If the session expires, your progress is **auto-saved** |

Any interaction with the app (tapping, scrolling, entering data) counts as activity and resets the inactivity timer. You do not need to worry about losing work — the app saves your progress automatically if you time out.

<div class="tip">
<strong>Tip:</strong> If you step away from your device during a visit, keep an eye out for the timeout warning. A quick tap on "Extend" keeps your session alive.
</div>

---

## 4. The Sales Landing Screen

After PIN authentication, you arrive at the **Sales Landing Screen**. This is your home base in Sales Mode. It shows three feature cards summarizing what Sales Mode can do:

- **Home Visit** — Log zones, run lengths, injection points, and power mounts during a site survey
- **Estimate** — Generate a professional estimate with pricing and send it for customer signature
- **Handoff** — Connect the signed job to an installer team for Day 1 pre-wire and Day 2 install

Below the feature cards, you have three action buttons:

| Button | What it does |
|--------|--------------|
| **New Visit** | Start a brand-new site survey from scratch |
| **My Estimates** | View your list of all saved jobs and estimates |
| **Dashboard** | Open your dealer dashboard for a high-level view |

To **exit Sales Mode**, tap the **Exit** button in the top-right corner of the landing screen.

---

## 5. The Sales Workflow — Step by Step

A complete site visit follows a five-step flow. Each step builds on the previous one, and your progress is saved along the way.

```
Prospect Info  -->  Zone Builder  -->  Visit Review  -->  Estimate Preview  -->  Customer Signature
   (Step 1)          (Step 2)          (Step 3)            (Step 4)               (Step 5)
```

---

### Step 1: Prospect Information

**Screen:** ProspectInfoScreen

This is the first thing you fill out when you arrive at a customer's home. Collect their contact details and document the property.

| Field | Required | Notes |
|-------|----------|-------|
| First Name | Yes | Customer's first name |
| Last Name | Yes | Customer's last name |
| Email | Yes | Customer's email address |
| Phone | Yes | Best contact number |
| Address | Yes | Street address — start typing and Google Places will suggest matches |
| City | Yes | Auto-fills from address selection |
| State | Yes | Auto-fills from address selection |
| Zip Code | Yes | Auto-fills from address selection |
| Referral Code | No | If the customer was referred, enter their `LUM-XXXX` code |
| Notes | No | Any observations about the property or customer preferences |

<div class="tip">
<strong>Tip:</strong> The address field uses Google Places autocomplete. Start typing the street address and tap a suggestion from the dropdown to auto-fill the city, state, and zip code fields. If autocomplete is not available (no internet), you can type the full address manually.
</div>

**Home Photos:** You can also take or upload photos of the property directly from this screen. Tap the camera icon to capture photos of the home's roofline, fascia, or any areas you plan to include in the estimate. Photos are uploaded and attached to the job record.

**Referral Validation:** If the customer provides a referral code, the app validates it in real-time. A green checkmark confirms the referral is valid; a red indicator means the code was not found.

When everything looks good, tap **Next** to move to the Zone Builder.

<div class="tip">
<strong>Tip:</strong> If you are resuming a previous visit, the fields will be pre-filled with the data you already entered. Just verify and update as needed.
</div>

---

### Step 2: Zone Builder

**Screen:** ZoneBuilderScreen

This is the core of the site survey. You will walk the perimeter of the home and document each LED zone — where the lights will go, how long each run is, and where power needs to connect.

#### Adding a Zone

Tap the **+** button to add a new zone. A bottom sheet opens where you enter the zone details:

| Field | Description |
|-------|-------------|
| **Zone Name** | A descriptive label (e.g., "Front Roofline", "Garage Accent", "Side Fascia") |
| **Run Length (ft)** | Total linear footage of the LED run for this zone |
| **Product Type** | Choose from: Roofline (9" spacing), Diffused rope light, or Custom |
| **Color Preset** | RGBW, Warm White, Cool White, or Full RGB |
| **Injection Points** | Where power connects along the LED run (see below) |
| **Power Mounts** | Where power supplies and controllers are physically mounted |
| **Photos** | Take photos of the zone area for reference |
| **Notes** | Any special considerations (obstacles, mounting challenges, etc.) |

#### Injection Points

An injection point is a location along the LED run where power is fed into the strip. For each injection point, you record:

- **Position (ft)** — how far along the run this injection sits
- **Served by controller** — whether this point is powered by the main controller or an additional power supply
- **Wire gauge** — automatically calculated based on the wire run distance:

| Wire Run Distance | Recommended Gauge |
|-------------------|-------------------|
| Direct connection | Direct |
| Up to 30 ft | 14/2 |
| Up to 90 ft | 12/2 |
| Up to 140 ft | 10/2 |
| Over 140 ft | EXCEEDS — requires redesign |

- **Wire run (ft)** — distance from the mount to the injection point
- **Architectural note** — any field observations (e.g., "runs behind gutter", "needs conduit")

<div class="warning">
<strong>Important:</strong> If the wire gauge calculator shows <strong>EXCEEDS 140ft</strong>, the wire run is too long. You will need to reposition the power mount or add an additional power supply closer to the injection point.
</div>

#### Power Mounts

A power mount is where a controller or power supply is physically installed. For each mount, you record:

- **Position (ft)** — location along the run
- **Is controller** — whether this mount holds the primary controller or just a power supply
- **Supply size** — 350W, 600W, or controller
- **Outlet type** — Existing outlet or New outlet needed
- **Outlet note** — details about the outlet situation
- **Mount location note** — where exactly the mount will go (e.g., "inside attic near soffit vent", "garage wall left of door")

#### Zone Summary

As you add zones, the Zone Builder screen shows running totals at the top:

- Total linear footage across all zones
- Total controller slots used
- Total injection points
- Estimated total price

When all zones are documented, tap **Next** to proceed to the Visit Review.

<div class="tip">
<strong>Tip:</strong> You can tap any existing zone to edit it, or swipe to delete. Take your time getting accurate measurements — they directly affect the estimate.
</div>

---

### Step 3: Visit Review

**Screen:** VisitReviewScreen

Before generating the estimate, this screen gives you a complete summary of everything you have collected:

- **Prospect information** — name, contact details, address
- **Zone details** — each zone with its run length, product type, injection points, and power mounts
- **Totals** — overall footage, pixel count, controller slots, and pricing

Review every section carefully. If anything needs to be corrected, you can go back to the relevant step to make changes.

#### Scheduling Installation Dates

The Visit Review screen also lets you tentatively schedule:

- **Day 1 (Pre-wire)** — the date for running wires and mounting hardware
- **Day 2 (Install)** — the date for installing the LED strips and commissioning the system

Tap the date fields to open a date picker. Day 2 must be on or after Day 1.

When everything is verified, tap **Generate Estimate** to proceed.

---

### Step 4: Estimate Preview

**Screen:** EstimatePreviewScreen

The app generates a professional, customer-facing estimate based on your zone measurements and pricing data. This screen shows:

- **Customer name and address** at the top
- **Itemized line items** for each zone — product type, footage, pixel count, and price
- **Total price** for the complete installation
- **Referral credit** (if a valid referral code was entered)

You can:

- **Share the estimate** — copies a link to the estimate to your clipboard, which you can send via text or email
- **Review line items** — verify that quantities and pricing look correct before presenting to the customer

<div class="tip">
<strong>Tip:</strong> Walk the customer through the estimate on your screen before asking for a signature. Explain each zone, what product is being used, and what the total includes. Transparency builds trust.
</div>

When the customer is ready to approve, tap **Proceed to Signature**.

---

### Step 5: Customer Signature

**Screen:** CustomerSignatureScreen

This is the final step. Hand your phone or tablet to the customer so they can review and sign the estimate digitally.

<div class="step-box">

1. The screen displays a white signature pad
2. The customer signs with their finger on the pad
3. If they make a mistake, tap **Clear** to reset the pad
4. Once satisfied, tap **Approve & Sign** to submit

</div>

After the customer signs:

- The signature is captured as an image and uploaded securely
- The job status updates to **Estimate Signed**
- If a referral code was provided, the referral pipeline is triggered automatically
- The job is saved to Firestore and appears in your **My Estimates** list

<div class="warning">
<strong>Important:</strong> Make sure the customer understands what they are signing. The signature constitutes approval of the estimate as presented.
</div>

---

## 6. Job Tracking

### My Estimates Screen

Tap **My Estimates** on the Sales Landing Screen to see all of your jobs. Each job card shows:

- **Job number** (e.g., NXG-0847)
- **Customer name**
- **Status badge**
- **Date created**

You can filter the list by status using the filter chips at the top of the screen.

### Job Statuses

Each job progresses through a series of statuses:

| Status | Meaning |
|--------|---------|
| **Draft** | Survey started but not yet complete — you can resume and finish it |
| **Estimate sent** | Estimate has been generated and presented to the customer |
| **Signed** | Customer has signed the estimate — ready for scheduling |
| **Pre-wire scheduled** | Day 1 pre-wire work has been scheduled with an installer |
| **Pre-wire complete** | Pre-wire work is finished — ready for Day 2 |
| **Install complete** | Full installation is finished — the job is closed |

### Job Detail Screen

Tap any job in the list to open its full detail view. From here you can:

- View all customer and prospect information
- Review zone measurements and the itemized estimate
- See the customer's signature (if signed)
- View scheduled Day 1 and Day 2 dates
- **Update the job status** as work progresses (e.g., mark pre-wire as complete)
- **Generate a PDF** of the estimate for printing or emailing
- **Create an install plan** for the installer team

<div class="tip">
<strong>Tip:</strong> Keep job statuses up to date. Your dealer admin and the installer team rely on accurate status information to coordinate schedules.
</div>

---

## 7. Best Practices

### Before the Visit

- Charge your device fully — a site survey can take 30--60 minutes
- Make sure you have a reliable internet connection (cellular is fine)
- Have your Sales PIN ready

### During the Visit

- **Measure twice.** Accurate run lengths are critical for a correct estimate. Walk the full perimeter and measure each zone carefully.
- **Document injection points on-site.** Note where power can realistically be connected — look for nearby outlets, attic access, and conduit paths.
- **Take photos.** Capture the roofline, fascia, soffits, and any tricky areas. Photos help the installer team during pre-wire and install.
- **Record power mount locations in detail.** Note whether existing outlets are available or if new ones are needed. This avoids surprises during installation.
- **Check for obstructions.** Gutters, downspouts, cameras, and decorative trim can affect LED placement. Note these in the zone's special considerations.

### Presenting the Estimate

- Walk the customer through each line item before asking for a signature
- Explain what each zone covers and what product type is being used
- If the customer has questions about pricing, refer them to your dealer admin
- Be transparent — customers appreciate knowing exactly what they are paying for

### After the Visit

- Verify the job appears in your **My Estimates** list
- Update the job status promptly as work is scheduled and completed
- Follow up with the customer if they did not sign on-site

---

## 8. Troubleshooting

| Problem | Solution |
|---------|----------|
| **PIN not working** | Double-check that you are entering the correct 4-digit PIN. If locked out after 5 attempts, close and reopen the app to reset. If the PIN is still rejected, contact your dealer admin to verify your account is active. |
| **Session expired mid-visit** | Your progress is auto-saved. Re-enter Sales Mode with your PIN and your previous work will be restored. |
| **Address autocomplete not showing suggestions** | Check your internet connection. Google Places requires connectivity. If suggestions still do not appear, type the full address manually — city, state, and zip can be entered by hand. |
| **Photos not uploading** | Ensure you have a stable internet connection. Photos are uploaded to cloud storage and require connectivity. Try again when you have a stronger signal. |
| **Wire gauge shows "EXCEEDS"** | The wire run distance is over 140 ft, which is too long. Reposition the power mount closer to the injection point, or add an additional power supply. |
| **Estimate totals look wrong** | Go back to the Zone Builder and verify run lengths and product types for each zone. Pricing is calculated automatically from these values. |
| **Cannot find a previous job** | Make sure you are logged in with the same Sales PIN. Jobs are associated with the PIN used to create them. Check the filter chips on the My Estimates screen — you may have a status filter active. |
| **Customer signature not saving** | Ensure the customer has drawn a visible signature on the pad. The "Approve & Sign" button only activates when a signature is present. Check your internet connection if the upload fails. |

---

## 9. Quick Reference Card

| Action | How |
|--------|-----|
| **Enter Sales Mode** | Login screen → Sales Mode → enter 4-digit PIN |
| **Start a new survey** | Sales Landing → **New Visit** |
| **View existing jobs** | Sales Landing → **My Estimates** |
| **Open dealer dashboard** | Sales Landing → **Dashboard** |
| **Add a zone** | Zone Builder → tap **+** button |
| **Edit a zone** | Zone Builder → tap the zone card |
| **Take a photo** | Prospect Info or Zone Editor → tap camera icon |
| **Enter a referral code** | Prospect Info → Referral Code field → enter `LUM-XXXX` |
| **Schedule install dates** | Visit Review → tap Day 1 / Day 2 date fields |
| **Share an estimate** | Estimate Preview → tap **Share** (copies link to clipboard) |
| **Collect signature** | Estimate Preview → **Proceed to Signature** → hand device to customer |
| **Extend session** | Tap **Extend** on the timeout warning dialog |
| **Exit Sales Mode** | Sales Landing → **Exit** (top-right corner) |

---

*Nex-Gen Lumina v2.1 — Sales Mode Guide — April 2026*
