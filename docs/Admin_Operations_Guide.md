---
title: "Nex-Gen Lumina — Admin Operations Guide"
subtitle: "How to manage dealers, installers, and installations as the system owner"
author: "Nex-Gen LED"
date: "April 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Nex-Gen Lumina — Admin Operations Guide (Internal)</div>'
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
  .danger { background: #FFEBEE; border-left: 4px solid #F44336; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .step-box { background: #F5F5F5; border: 1px solid #ddd; border-radius: 8px; padding: 14px; margin: 10px 0; }
  code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
</style>

# Nex-Gen Lumina — Admin Operations Guide

This guide is for **you, the owner of Nex-Gen LED**. It covers how to set up and manage the entire dealer/installer ecosystem from within the Lumina app. Your dealers and installers have their own guide — this one is about the admin operations they can't see.

---

## 1. Your Admin Credentials

| Item | Value |
|------|-------|
| **Admin PIN** | `9999` |
| **Master Installer PIN** | `8817` (Nex-Gen Administrator bypass) |
| **Dev/Test PIN** | `0000` (development only — disable before launch) |

<div class="danger">
<strong>Before launch:</strong> The admin PIN is currently hardcoded. Plan to move this to a Firebase Auth role check or a secure remote config value so it can be changed without an app update.
</div>

---

## 2. Accessing the Admin Portal

1. Open the Lumina app on any device
2. Go to **Installer Mode** (from the login screen or Settings)
3. Tap **Admin Access**
4. Enter your admin PIN: `9999`
5. You land on the **Admin Dashboard**

The dashboard shows three live stats at the top:

- **Active Dealers** — companies you've onboarded
- **Active Installers** — technicians across all dealers
- **Installations** — total completed customer setups

---

## 3. The Big Picture: How It All Fits Together

```
YOU (Admin PIN 9999)
 │
 ├── Dealer 01: "ABC Lighting Co."
 │    ├── Installer 01 → PIN 0101 (Mike)
 │    ├── Installer 02 → PIN 0102 (Sarah)
 │    └── Installer 03 → PIN 0103 (Jake)
 │
 ├── Dealer 02: "Premier Outdoor LLC"
 │    ├── Installer 01 → PIN 0201 (Tony)
 │    └── Installer 02 → PIN 0202 (Lisa)
 │
 └── Dealer 03: "Bright Ideas Inc."
      └── Installer 01 → PIN 0301 (Carlos)
```

- **You** create **Dealers** (companies that sell/install your product)
- Each **Dealer** gets a 2-digit code (01–99) → up to 99 dealers
- Under each Dealer you create **Installers** (their technicians)
- Each **Installer** gets a 2-digit code (01–99) → up to 99 per dealer
- The installer's **4-digit PIN** = dealer code + installer code
- Installers use that PIN to enter Installer Mode and complete customer setups

---

## 4. Creating Your First Dealer

### Step-by-Step

1. From the Admin Dashboard, tap **Manage Dealers**
2. Tap the **+ Add Dealer** button
3. Fill in the dealer's information:

| Field | Required | Notes |
|-------|----------|-------|
| Contact Name | Yes | Primary contact at the company |
| Company Name | Yes | Their business name |
| Email | Yes | For correspondence |
| Phone | Yes | Business phone |

4. The system **auto-assigns the next available dealer code** (starting at `01`)
5. Tap **Save**

The dealer is now active and visible in the dealer list.

<div class="tip">
<strong>Tip:</strong> Dealer codes are assigned sequentially. If you've used 01, 02, 03 and deactivated 02, the next new dealer still gets 04 (not 02). Codes don't recycle — this prevents PIN collisions with old installers.
</div>

### What to Tell the Dealer

After creating their account, give them:

- Their **dealer code** (e.g., `03`)
- The **Dealer & Installer Setup Guide** PDF (you already have this at `docs/Dealer_Installer_Setup_Guide.pdf`)
- Explain that you'll create their initial installer PINs, or give them admin access to do it themselves

---

## 5. Adding Installers Under a Dealer

### Step-by-Step

1. From the Admin Dashboard, tap **Manage Installers**
2. If you have multiple dealers, select which dealer this installer belongs to
3. Tap **+ Add Installer**
4. Fill in the installer's information:

| Field | Required | Notes |
|-------|----------|-------|
| Full Name | Yes | Installer's name |
| Email | Yes | Their email |
| Phone | Yes | Their phone |

5. The system auto-assigns the next installer code under that dealer
6. Tap **Save**
7. The **4-digit PIN** is displayed — this is what the installer uses in the field

### Example

You're adding the first installer under Dealer 03 ("Bright Ideas Inc."):

- System assigns installer code: `01`
- Combined PIN: `0301`
- You tell Carlos: "Your PIN is 0301"

Carlos opens the Lumina app → Installer Mode → enters `0301` → he's in.

---

## 6. Day-to-Day Management

### Viewing All Dealers

**Admin Dashboard → Manage Dealers** shows every dealer with:

- Dealer code
- Company name
- Contact name
- Active/inactive status
- Number of installers under them

### Viewing All Installers

**Admin Dashboard → Manage Installers** shows every installer with:

- Their 4-digit PIN
- Name
- Parent dealer
- Active/inactive status
- Total installations completed

You can filter by dealer to see only one company's team.

### Editing a Dealer or Installer

Tap any dealer or installer in the list to edit their contact details (name, email, phone). The dealer code and installer code **cannot be changed** after creation.

---

## 7. Sales Mode Management

The Lumina app includes a Sales Mode for field representatives to conduct site surveys and generate estimates.

### How Sales Mode Works

- Sales reps access Sales Mode from the login screen
- They enter a 4-digit Sales PIN (validated against `master_sales_pin` in Firestore `app_config` collection)
- Sessions last 30 minutes with a 5-minute warning before timeout
- Progress auto-saves on session timeout

### What You Manage

- The master sales PIN is stored in Firestore at `app_config/master_sales_pin`
- Currently a single shared PIN — all sales reps use the same PIN
- To change the PIN: update the value in Firebase Console → Firestore → `app_config` collection

### Sales Job Data

Sales jobs are stored in Firestore (created by the sales reps). Jobs track: prospect info, zone measurements, estimates, and signatures.

**Job status flow:**

`Draft` → `EstimateSent` → `EstimateSigned` → `PrewireScheduled` → `PrewireComplete` → `InstallComplete`

### Viewing Sales Data

- Sales job data is visible in the Admin Dashboard under sales tracking
- Each job shows: customer name, address, status, assigned sales rep, dealer code, date
- The Dealer Dashboard also shows jobs filtered by that dealer's team

---

## 8. Referral Reward Approval and Payout Management

The Lumina app includes a referral program where dealers and customers earn rewards for referrals.

### How the Referral Pipeline Works

1. A dealer or customer shares their referral code
2. The referred prospect goes through Sales Mode → Installation
3. Upon installation completion, the referral attribution service tracks the source
4. A reward is calculated based on the installation value and the referrer's ambassador tier
5. The reward enters "pending" status awaiting admin approval

### Ambassador Tiers

| Tier | Installs Required | Benefits |
|------|------------------|----------|
| Bronze | 0+ | Base referral reward |
| Silver | 3+ | Increased reward |
| Gold | 8+ | Higher reward + perks |
| Platinum | 15+ | Maximum reward + premium perks |

### Approving Payouts

1. From the Admin Dashboard, go to the **Payout Approval** screen
2. Review pending payouts — each shows: dealer name, referral details, reward amount, reward type
3. Reward types: **Visa Gift Card** or **Nex-Gen Credit**
4. Annual gift card cap: **$599 per dealer** (IRS reporting threshold)
5. Approve or reject each payout
6. Approved payouts move to "fulfilled" status

### Firestore Collections for Referrals

- Referral tracking data lives under dealer/user documents
- Payout records are tracked with status (`pending`, `approved`, `fulfilled`, `gcCapReached`)

<div class="tip">
<strong>Tip:</strong> Keep an eye on dealers approaching the $599 annual gift card cap. When they hit the cap, future rewards automatically default to Nex-Gen Credit until the next calendar year.
</div>

---

## 9. Deactivating & Reactivating

### Deactivating an Installer

Tap the installer → toggle **Active** to off.

- Their PIN stops working **immediately**
- Any in-progress installations they had are preserved (can be resumed by another installer)
- Their completed installation records remain intact

### Deactivating a Dealer

Tap the dealer → toggle **Active** to off.

<div class="warning">
<strong>Cascade effect:</strong> Deactivating a dealer <strong>automatically deactivates ALL installers</strong> under that dealer. Every one of their PINs stops working immediately.
</div>

### Reactivating

Toggle **Active** back to on. For dealers, you must **manually reactivate each installer** — the cascade only works one direction (deactivation).

---

## 10. What Happens During an Installation

When an installer uses their PIN and completes a setup, the system:

1. Creates a **Firebase Auth account** for the customer (email + temp password)
2. Creates a **user profile** in Firestore at `/users/{uid}`
3. Creates an **installation record** at `/installations/{id}` containing:
   - Customer info (name, email, address)
   - Your dealer code and installer code
   - Installer name and dealer company name
   - Date installed
   - Warranty expiration (5 years from install date)
   - Controller serial numbers
   - Site mode (residential or commercial)
4. Links the physical controllers to the customer's account
5. Increments the installer's installation count
6. Shows the customer's login credentials on screen for the installer to hand off

You can view all installation records from the Firebase Console under the `installations` collection.

---

## 11. Firebase Collections You Own

| Collection | What's In It | Who Writes |
|------------|-------------|------------|
| `/dealers/{id}` | Dealer companies (code, name, contact, active status) | You (admin) |
| `/installers/{id}` | Installer accounts (PIN, name, dealer, active status) | You (admin) |
| `/installations/{id}` | Completed installation records (customer, warranty, controllers) | Installers (during setup) |
| `/users/{uid}` | Customer accounts (profile, preferences, linked controllers) | Installer creates; customer owns |
| `/users/{uid}/properties` | Customer properties (homes, locations) with linked controller IDs | Customer creates/manages |
| `/dealerDemoCodes/{id}` | Demo/trial access codes for media and demo mode | You (admin, via Firebase Console) |
| `app_config` | App-wide config (master sales PIN, etc.) | You (admin, via Firebase Console) |

---

## 12. Media Mode (Content Team Access)

Media Mode is separate from Installer Mode. It lets your content/marketing team access any customer's system for video shoots without giving them installer privileges.

### How It Works

1. You create a **demo access code** in the `dealerDemoCodes` Firestore collection
2. The media person opens Lumina → **Media Mode** → enters the 6-character code
3. They can search for any customer by email or address
4. They can **control the lights** but **cannot modify settings or create accounts**

### Creating a Media Access Code

Currently done directly in Firebase Console:

1. Go to Firestore → `dealerDemoCodes` collection
2. Add a document with these fields:

| Field | Type | Example |
|-------|------|---------|
| `code` | string | `MEDIA1` |
| `dealerCode` | string | `00` (use 00 for internal Nex-Gen) |
| `dealerName` | string | `Nex-Gen LED` |
| `market` | string | `Internal` |
| `isActive` | boolean | `true` |
| `usageCount` | number | `0` |
| `maxUses` | number | `null` (unlimited) or a number |
| `createdAt` | timestamp | (current time) |
| `expiresAt` | timestamp | `null` (never) or a date |

---

## 13. Demo Mode Management

Demo Mode allows prospects to experience the Lumina app without a real account or hardware.

### How It Works

- Prospects enter a demo code on the Demo Welcome Screen
- They go through: welcome → consent → profile collection → photo capture → roofline demo → completion
- The demo uses `MockWledRepository` to simulate lighting without real hardware
- Lead information is captured via the demo lead service

### Managing Demo Codes

Demo codes are stored in the `dealerDemoCodes` Firestore collection (same collection as Media Mode codes). Each code document has the same fields described in Section 12 above.

- Codes can have expiration dates (`expiresAt`) and usage limits (`maxUses`)
- Track `usageCount` to measure marketing effectiveness
- Set `isActive` to `false` to revoke a code without deleting it

### Lead Capture

- Demo sessions capture prospect contact info (name, email, phone)
- This data can be used for follow-up by the sales team
- Review leads in Firebase Console or through the Admin Dashboard

<div class="tip">
<strong>Tip:</strong> Create dedicated demo codes per marketing campaign or event so you can track which channels are generating the most interest.
</div>

---

## 14. Dealer Dashboard Overview

When dealers log in to their dashboard, they see a 4-tab interface. Understanding what your dealers see helps you support them and answer their questions.

### Overview Tab

- Stat cards showing total jobs, active installs, team size
- Pipeline status bar (visual breakdown of job statuses)
- Recent activity feed

### Pipeline Tab

- All sales jobs for their team
- Filterable by status
- Tap to view full job details

### Team Tab

- List of their installers
- Active/inactive status for each
- Installation counts per installer

### Payouts Tab

- Pending rewards awaiting your (admin) approval
- Approved/fulfilled payout history
- Ambassador tier progress indicator

---

## 15. Weekly Brief Notifications

The system sends automated weekly push notifications to users with Autopilot enabled.

### How It Works

- A Firebase Cloud Function (`sendWeeklyBrief`) fires every Sunday at 18:30 UTC
- For each user with `autopilot_enabled` and `weekly_schedule_preview_enabled` set to `true`:
  1. Queries their upcoming `autopilot_events` for the next week
  2. Calls Claude Haiku to generate a personalized 1-2 sentence notification body
  3. Sends an FCM push with title **"Your Week in Lights"** and a deep-link to the autopilot schedule

### Requirements

- `ANTHROPIC_API_KEY` must be set as an environment variable in the Cloud Functions runtime
- Users must have a valid `fcmToken` in their Firestore user document
- The function automatically cleans up stale FCM tokens

### Deployment

```bash
cd functions
npm run build
firebase deploy --only functions:sendWeeklyBrief
```

### Android Notification Channel

The notification channel ID is `autopilot_weekly`, registered in the app as **"Weekly Schedule Preview"**. Users can disable this channel in their Android notification settings without affecting other Lumina notifications.

### Monitoring

- Function logs show: eligible user count, sent/skipped/error counts
- Check Firebase Console → Functions → `sendWeeklyBrief` for execution logs
- If no notifications are being sent, verify the `ANTHROPIC_API_KEY` is set and that users have valid FCM tokens

---

## 16. Firestore Security Rules Summary

Your security rules enforce this access model:

| Who | Can Do |
|-----|--------|
| **Regular users** | Read/write only their own data (profile, controllers, properties, schedules, geofences) |
| **Media/dealer/admin users** | Read any user's data including properties (for customer lookup and content) |
| **Installers** | Create installation records (with required fields) |
| **Admins** | Full CRUD on dealers, installers, installations |

The `user_role` field on each user's profile (`residential`, `media`, `dealer`, `admin`) determines their access level.

**Subcollections under `/users/{uid}`** with owner-only write access and media/dealer/admin read access:
- `controllers` — registered WLED controllers
- `properties` — user's properties/locations with linked controller IDs
- `commands` — cloud relay commands (bridge can also read/write)
- `bridge_status` — ESP32 bridge heartbeat
- `geofences` — location-based automation triggers

---

## 17. Onboarding a New Dealer — Complete Checklist

Here's the full process when you sign up a new dealer:

- [ ] **Get their info**: contact name, company name, email, phone
- [ ] **Open Admin Portal**: Lumina app → Installer Mode → Admin Access → PIN `9999`
- [ ] **Create the dealer**: Manage Dealers → Add Dealer → fill in info → Save
- [ ] **Note the dealer code** (e.g., `03`)
- [ ] **Create their installers**: Manage Installers → select dealer → Add Installer for each tech
- [ ] **Note each PIN** (e.g., `0301`, `0302`, etc.)
- [ ] **Send the dealer**:
  - Their dealer code
  - Each installer's 4-digit PIN
  - The **Dealer & Installer Setup Guide** PDF
- [ ] **Confirm they can log in**: Have one installer test their PIN in Installer Mode

---

## 18. Troubleshooting

### "Maximum dealer limit (99) reached"

You have 99 dealer codes used. You'd need to delete or reclaim unused ones, or expand the code format. This is a code change.

### An installer says their PIN doesn't work

1. Check the Admin Portal — is their account set to **Active**?
2. Check their parent dealer — is the **dealer** active? (Deactivated dealer = all PINs dead)
3. Verify they're entering all 4 digits correctly
4. If they've been locked out (5 failed attempts), the lockout resets after restarting the app

### A dealer left the program

1. Admin Portal → Manage Dealers → find them → toggle **Active** off
2. All their installers are automatically deactivated
3. Existing customer installations are unaffected — those accounts still work
4. The dealer code is not reused

### Need to transfer an installer to a different dealer

You can't move an installer between dealers — the dealer code is baked into their PIN. Instead:
1. Deactivate the old installer account
2. Create a new installer under the new dealer
3. Give the technician their new PIN

---

## 19. Security Notes

<div class="warning">
<strong>Current limitations to address before scaling:</strong>

- **Admin PIN is hardcoded** (`9999` in `admin_providers.dart`). Anyone with the app who guesses it has full admin access. Move to Firebase Auth custom claims or remote config.
- **Master installer PIN is hardcoded** (`8817` in `installer_providers.dart`). Same concern.
- **Demo/media codes** are managed in Firebase Console, not in the app. Consider adding an in-app screen for this.
- **No audit log** — dealer/installer changes are not tracked. Consider adding a Firestore `audit_log` collection.
- **Deletes are soft deletes** — deactivation only. Data is preserved.
</div>

---

## 20. Quick Reference

| Action | Where |
|--------|-------|
| Enter Admin Portal | Installer Mode → Admin Access → PIN `9999` |
| Create a dealer | Admin Dashboard → Manage Dealers → Add |
| Create an installer | Admin Dashboard → Manage Installers → Add |
| Deactivate a dealer | Manage Dealers → tap dealer → toggle Active off |
| Deactivate an installer | Manage Installers → tap installer → toggle Active off |
| View installation stats | Admin Dashboard (top cards) |
| Create media access code | Firebase Console → `dealerDemoCodes` collection |
| View all installations | Firebase Console → `installations` collection |
| Change sales PIN | Firebase Console → Firestore → `app_config` |
| Approve payouts | Admin Dashboard → Payout Approval |
| View sales pipeline | Admin Dashboard → Sales Jobs |
| Deploy weekly brief | `firebase deploy --only functions:sendWeeklyBrief` |
| Manage demo codes | Firebase Console → `dealerDemoCodes` |

---

*Nex-Gen Lumina v2.1 — Admin Operations Guide — April 2026 — INTERNAL USE ONLY*
