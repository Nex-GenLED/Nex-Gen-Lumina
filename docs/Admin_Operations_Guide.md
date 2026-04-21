---
title: "Nex-Gen Lumina — Admin Operations Guide"
subtitle: "Run the dealer, installer, and corporate side of Lumina from inside the app"
author: "Nex-Gen LED LLC"
date: "April 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#DCF0FF;">Nex-Gen Lumina — Admin Operations Guide (Internal)</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#DCF0FF;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: []
body_class: guide
---

<style>
  body { font-family: 'DM Sans', 'Segoe UI', Arial, sans-serif; color: #DCF0FF; background: #07091A; line-height: 1.6; }
  h1, h2, h3 { font-family: 'Exo 2', 'Segoe UI', Arial, sans-serif; }
  h1 { background: linear-gradient(90deg, #6E2FFF, #00D4FF); -webkit-background-clip: text; background-clip: text; color: transparent; border-bottom: 2px solid #00D4FF; padding-bottom: 8px; }
  h2 { color: #00D4FF; margin-top: 28px; }
  h3 { color: #DCF0FF; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; background: #111527; }
  th, td { border: 1px solid #1F2542; padding: 8px 12px; text-align: left; }
  th { background: #6E2FFF; color: #DCF0FF; }
  .tip { background: rgba(0, 212, 255, 0.12); border-left: 4px solid #00D4FF; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .warning { background: rgba(255, 170, 60, 0.12); border-left: 4px solid #FFAA3C; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .danger { background: rgba(244, 67, 54, 0.15); border-left: 4px solid #F44336; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .step-box { background: #111527; border: 1px solid #1F2542; border-radius: 8px; padding: 14px; margin: 10px 0; }
  code { background: #1F2542; color: #00D4FF; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
</style>

# Nex-Gen Lumina — Admin Operations Guide

This is your playbook for running the admin side of Lumina — the dealer network, installer team, corporate dashboard, and everything your dealers and installers never see. Permanent residential and commercial lighting that works as hard as you do, and this guide keeps the machine behind it running smoothly.

## What you'll need

- Access to the Lumina app on a phone or tablet, signed in as Nex-Gen LED LLC staff
- The **Corporate PIN** (for the Corporate Dashboard) or **Admin PIN** `9999` (for dealer/installer management)
- Access to the Firebase Console for the Lumina production project — used for PIN hashing, demo codes, and `app_config` changes
- A list of your active dealers and installers if you're onboarding or auditing

---

## 1. Staff credentials at a glance

Every staff PIN flows through one screen — the **Staff PIN** screen. The PIN you type decides which mode you land in.

| Item | Value | Lands you in |
|------|-------|------|
| **Corporate PIN** | Set in Firestore — see Section 7 | Corporate Dashboard |
| **Admin PIN** | `9999` | Admin Dashboard (dealer + installer management) |
| **Master Installer PIN** | `8817` (Nex-Gen LED LLC bypass) | Installer Mode |
| **Sales PIN** | Set in Firestore `app_config/master_sales_pin` | Sales Mode |
| **Dev/Test PIN** | `0000` — disable before launch | Installer Mode |

### How PIN validation is prioritized

When a PIN is entered, the app checks sources in this order:

1. **Corporate PIN** — SHA-256 hash compared against `app_config/master_corporate_pin`
2. **Installer PINs** — master installer PIN (`8817`), then individual installer PINs in the `installers` collection
3. **Sales PIN** — master sales PIN, then per-installer sales fallback

Corporate is checked first because it has no collection fallback, so it can never accidentally claim someone else's PIN. The order prevents PIN collisions from routing staff to the wrong mode.

<div class="danger">
<strong>Before you launch publicly:</strong> The Admin PIN (<code>9999</code>) and Master Installer PIN (<code>8817</code>) are hardcoded in the app. Plan to migrate both to hashed Firestore values — the same pattern the Corporate PIN already uses — so they can be rotated without an app release.
</div>

---

## 2. Getting to the Staff PIN screen

There is no visible "Installer Mode" or "Admin Access" button on the login screen — by design. Staff access is hidden behind a gesture so the customer-facing UI stays clean.

<div class="step-box">

1. Open Lumina to the **login screen**
2. Tap the **Lumina logo** 5 times within 3 seconds (the large icon and "LUMINA" wordmark at the top)
3. The taps give no visual feedback — that's intentional
4. After the 5th tap the **Staff PIN** screen opens automatically
5. Enter your PIN — the app routes you to the correct mode (see Section 1)

</div>

<div class="warning">
<strong>Heads-up:</strong> The 5 taps must happen inside a 3-second window. If you pause too long the counter silently resets — just start over.
</div>

### How the PIN pad behaves

- 4 digits total
- Filled digits glow **LUMINA cyan**; empty positions show as outlined circles
- Validation runs automatically on the 4th digit — no Submit button
- Success: light haptic, then you land in the right mode
- Failure: the dots shake, and you see the remaining attempts

### Lockout

- 5 failed attempts triggers a **30-second lockout**
- A countdown shows the remaining seconds in amber
- After 30 seconds the counter clears and you can try again
- The lockout is local to the screen — dismissing and reopening the screen resets it

### Entering the Admin Dashboard

Type `9999` on the Staff PIN screen. You land on the **Admin Dashboard**, which shows three live stats across the top:

- **Active Dealers** — companies you've onboarded
- **Active Installers** — technicians across all dealers
- **Installations** — completed customer setups to date

### App Store reviewer reveal

There's a second hidden gesture: **5 taps on the "POWERED BY NEX-GEN" subtitle** (under the logo). That reveals an "App Store Review" button that autofills the reviewer test credentials. No time window on this one — taps can be spaced out. Only relevant during App Store review submissions.

---

## 3. The big picture

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

- You create **Dealers** — companies that sell and install Nex-Gen
- Each dealer gets a 2-digit code (`01`–`99`) → up to 99 dealers
- Under each dealer you create **Installers** — their field technicians
- Each installer gets a 2-digit code (`01`–`99`) → up to 99 per dealer
- The installer's **4-digit PIN** = dealer code + installer code
- That PIN is how the installer enters Installer Mode on a customer's phone during setup

---

## 4. Creating a dealer

1. From the Admin Dashboard, tap **Manage Dealers**
2. Tap **+ Add Dealer**
3. Fill in their info:

| Field | Required | Notes |
|-------|----------|-------|
| Contact Name | Yes | Primary contact at the company |
| Company Name | Yes | Their business name |
| Email | Yes | For correspondence |
| Phone | Yes | Business phone |

4. The system auto-assigns the next available dealer code (starting at `01`)
5. Tap **Save**

The dealer is live and appears in the dealer list.

<div class="tip">
<strong>Tip:</strong> Dealer codes are sequential and don't recycle. If you've used 01, 02, 03 and deactivate 02, the next new dealer still gets 04 — not 02. That prevents PIN collisions with previous installers.
</div>

### What to hand the dealer

- Their **dealer code** (e.g., `03`)
- The **Dealer & Installer Setup Guide** PDF (`docs/Dealer_Installer_Setup_Guide.pdf`)
- A heads-up that you'll create their initial installer PINs, or that you can give them admin access to create their own

---

## 5. Adding installers under a dealer

1. From the Admin Dashboard, tap **Manage Installers**
2. If you have multiple dealers, pick the dealer this installer belongs to
3. Tap **+ Add Installer**
4. Fill in the installer's info:

| Field | Required | Notes |
|-------|----------|-------|
| Full Name | Yes | Installer's name |
| Email | Yes | Their email |
| Phone | Yes | Their phone |

5. The system auto-assigns the next installer code under that dealer
6. Tap **Save**
7. The **4-digit PIN** is displayed — share this with the technician

### Example

You're adding the first installer under Dealer 03 (Bright Ideas Inc.):

- System assigns installer code `01`
- Combined PIN: `0301`
- Tell Carlos: "Your PIN is 0301"

Carlos opens Lumina → taps the Lumina logo 5 times → enters `0301` on the Staff PIN screen → he's in Installer Mode.

---

## 6. Day-to-day management

### All dealers view

**Admin Dashboard → Manage Dealers** lists every dealer with:

- Dealer code
- Company name
- Contact name
- Active/inactive status
- Installer count

### All installers view

**Admin Dashboard → Manage Installers** lists every installer with:

- 4-digit PIN
- Name
- Parent dealer
- Active/inactive status
- Total installations completed

Filter by dealer to narrow down to one company's team.

### Editing a dealer or installer

Tap any dealer or installer to edit their contact info (name, email, phone). The dealer code and installer code **cannot change** after creation — they're baked into live PINs.

---

## 7. Corporate Dashboard — network-level oversight

The **Corporate Dashboard** is a separate admin experience from the Admin Dashboard. The Admin Dashboard (PIN `9999`) handles dealer and installer records one at a time. The Corporate Dashboard is where you see the whole network — analytics, inventory intelligence, and cross-dealer oversight.

### Admin Dashboard vs. Corporate Dashboard

| | Admin Dashboard | Corporate Dashboard |
|---|---|---|
| **Access** | PIN `9999` (hardcoded today) | Corporate PIN (SHA-256 hash in Firestore) |
| **Purpose** | Dealer + installer CRUD, installation records | Network analytics, pipeline, inventory, pricing |
| **Scope** | One dealer at a time | Cross-dealer, network-wide |
| **Session timeout** | Standard | 60 minutes with 5-minute warning |

### Getting in

Same hidden 5-tap gesture on the Lumina logo (Section 2), then enter the Corporate PIN. Validated as a SHA-256 hash against `app_config/master_corporate_pin`.

### Corporate roles

Each corporate PIN record has a **role** that controls what the holder sees and changes.

| Role | Read access | Write access |
|------|-------------|--------------|
| **Owner** | All tabs, all data | Full admin — dealer CRUD, pricing, PIN management, announcements |
| **Officer** | All tabs, all data | Announcements, dealer status toggle. Cannot change PINs. |
| **Warehouse** | Network + Pipeline (read-only); full Warehouse tab | Reorder intelligence insights (read-only) |
| **Read-only** | All tabs (data only) | None — pure observability |

### The four tabs

1. **Network** — Dealer health overview. Header cards show active dealers, jobs this month, revenue, average job value. Dealer cards are classified as active, quiet, or stalled.
2. **Pipeline** — Cross-dealer job pipeline. Filter by status, search jobs, watch stall indicators (amber at 7–14 days, red at 14+ days).
3. **Warehouse** — Network-wide inventory intelligence: demand view, waste analysis, reorder triggers.
4. **Admin** — Dealer management, network pricing defaults, announcements, and system PIN management (Owner role only).

### Changing the Corporate PIN

The Corporate PIN is stored as a SHA-256 hash in `app_config/master_corporate_pin`. Document fields:

| Field | Type | What it is |
|-------|------|------------|
| `pin_hash` | string | SHA-256 hex digest of the PIN |
| `displayName` | string | Label shown in-session (e.g., "Nex-Gen Corporate") |
| `role` | string | `owner`, `officer`, `warehouse`, or `readonly` |

Generate the SHA-256 hash of the new PIN with any standard SHA-256 tool and update `pin_hash`.

<div class="tip">
<strong>Tip:</strong> For the full Corporate Dashboard walkthrough — tab details, metric definitions, workflow guides — see <code>docs/corporate-dashboard-guide.md</code>.
</div>

---

## 8. Sales Mode management

The Lumina app includes a **Sales Mode** for field reps who run site surveys and generate estimates.

### How it works

- Reps use the **same hidden 5-tap gesture** on the Lumina logo (Section 2) to open the Staff PIN screen
- They enter the 4-digit Sales PIN, validated against `master_sales_pin` in the `app_config` collection
- Sessions last 30 minutes with a 5-minute timeout warning
- Progress auto-saves on timeout

### What you manage

- Master Sales PIN lives at `app_config/master_sales_pin`
- Single shared PIN today — all reps use the same one
- To rotate: update the value in Firebase Console → Firestore → `app_config`

### Sales job data

Sales jobs are stored in Firestore — created by the reps in the field. Each job tracks prospect info, zone measurements, estimate, and signatures.

**Status flow:**

`Draft` → `EstimateSent` → `EstimateSigned` → `PrewireScheduled` → `PrewireComplete` → `InstallComplete`

### Where you see the data

- Sales job data appears in the Admin Dashboard under sales tracking
- Each row shows customer name, address, status, assigned rep, dealer code, date
- Dealers also see their own team's jobs in their Dealer Dashboard

### Automated customer messaging

The sales pipeline triggers automated SMS and email at key milestones — estimate signed, Day 1 scheduled, wiring complete, and more. Dealers configure messaging templates and timing from their Dealer Dashboard. For the full list of 8 automated touchpoints and how to customize them, see `docs/messaging-configuration-guide.md`.

---

## 9. Referral rewards — approvals and payouts

Lumina includes a referral program. Dealers and customers earn rewards for referrals.

### How the pipeline works

1. A dealer or customer shares their referral code
2. The prospect goes through Sales Mode → Installation
3. On install completion, referral attribution records the source
4. A reward is calculated from the installation value and the referrer's ambassador tier
5. The reward goes to **pending** status, waiting for your approval

### Ambassador tiers

| Tier | Installs | Benefits |
|------|---------|----------|
| Bronze | 0+ | Base referral reward |
| Silver | 3+ | Increased reward |
| Gold | 8+ | Higher reward + perks |
| Platinum | 15+ | Maximum reward + premium perks |

### Approving payouts

1. Admin Dashboard → **Payout Approval**
2. Review pending payouts — dealer, referral details, amount, reward type
3. Reward types: **Visa Gift Card** or **Nex-Gen Credit**
4. Annual gift card cap per dealer: **$599** (IRS reporting threshold)
5. Approve or reject each payout
6. Approved payouts move to **fulfilled**

### Firestore storage

- Referral tracking lives under dealer/user documents
- Payout records track status: `pending`, `approved`, `fulfilled`, `gcCapReached`

<div class="tip">
<strong>Tip:</strong> Watch dealers approaching the $599 annual gift card cap — once they hit it, future rewards automatically default to Nex-Gen Credit until the next calendar year.
</div>

---

## 10. Deactivating and reactivating

### Deactivating an installer

Tap the installer → toggle **Active** off.

- Their PIN stops working **immediately**
- Any in-progress installations they had are preserved — another installer can resume
- Completed installation records stay intact

### Deactivating a dealer

Tap the dealer → toggle **Active** off.

<div class="warning">
<strong>Cascade:</strong> Deactivating a dealer <strong>automatically deactivates every installer</strong> under that dealer. All of their PINs stop working immediately.
</div>

### Reactivating

Toggle **Active** back on. For dealers, you must **manually reactivate each installer** — the cascade only runs one direction (deactivation).

---

## 11. What actually happens during an installation

When an installer completes a customer setup, the system:

1. Creates a **Firebase Auth** account for the customer (email + temp password)
2. Creates a **user profile** at `/users/{uid}` in Firestore
3. Creates an **installation record** at `/installations/{id}` containing:
   - Customer info — name, email, address
   - Your dealer code and installer code
   - Installer name and dealer company name
   - Install date
   - Warranty expiration (5 years from install date)
   - Controller serial numbers
   - Site mode — residential or commercial
4. Links the physical controllers to the customer's account
5. Increments the installer's install count
6. Displays the customer's login credentials on screen for the installer to hand off

You can audit every installation record from the Firebase Console under the `installations` collection.

---

## 12. Manual IP entry for controller setup

Installers can add controllers to a customer's account by typing an IP address directly — in addition to the usual BLE scan flow. This helps on service calls or reinstalls where the controller is already on the customer's Wi-Fi.

### How it works

1. During controller setup, the installer taps **Add Controller**
2. A bottom sheet offers two options:
   - **BLE Scan (New Device)** — for controllers not yet on Wi-Fi (existing flow)
   - **Enter IP Address** — for controllers already on the network
3. If they choose IP entry, a dialog asks for:

| Field | Required | Notes |
|-------|----------|-------|
| **IP Address** | Yes | The controller's local IP (e.g., `192.168.1.100`) |
| **Name** | No | Friendly label (e.g., "Front Roofline"). Defaults to `Controller (IP)` if blank |

4. The controller is saved to `users/{uid}/controllers` with `wifiConfigured: true`
5. The app immediately pings the controller (5-second timeout) to confirm connectivity
6. Status indicator: green (online), red (offline), gray (unchecked)

<div class="tip">
<strong>Tip:</strong> Especially useful for service calls and reinstalls where the controller is already on the customer's Wi-Fi — no BLE re-pairing needed.
</div>

---

## 13. Firestore collections you own

| Collection | What's in it | Who writes |
|------------|-------------|------------|
| `/dealers/{id}` | Dealer companies — code, name, contact, active status | You |
| `/installers/{id}` | Installer accounts — PIN, name, dealer, active status | You |
| `/installations/{id}` | Completed installation records — customer, warranty, controllers | Installers during setup |
| `/users/{uid}` | Customer accounts — profile, preferences, linked controllers | Installer creates; customer owns |
| `/users/{uid}/properties` | Customer properties with linked controller IDs | Customer creates/manages |
| `/dealerDemoCodes/{id}` | Demo/trial access codes for Media and Demo Mode | You (via Firebase Console) |
| `app_config` | App-wide config — master sales PIN, corporate PIN hash | You (via Firebase Console) |

---

## 14. Media Mode — content team access

Media Mode is separate from Installer Mode. It gives the content/marketing team access to any customer's system for video shoots without granting installer privileges.

### How it works

1. You create a **demo access code** in the `dealerDemoCodes` Firestore collection
2. The media person opens Lumina → **Media Mode** → enters the 6-character code
3. They can search for any customer by email or address
4. They can **control the lights** but **cannot modify settings or create accounts**

### Creating a media access code

Currently done in Firebase Console:

1. Go to Firestore → `dealerDemoCodes`
2. Add a document:

| Field | Type | Example |
|-------|------|---------|
| `code` | string | `MEDIA1` |
| `dealerCode` | string | `00` (internal Nex-Gen) |
| `dealerName` | string | `Nex-Gen LED LLC` |
| `market` | string | `Internal` |
| `isActive` | boolean | `true` |
| `usageCount` | number | `0` |
| `maxUses` | number | `null` (unlimited) or a number |
| `createdAt` | timestamp | (current time) |
| `expiresAt` | timestamp | `null` (never) or a date |

---

## 15. Demo Mode management

Demo Mode lets prospects experience the Lumina app without a real account or hardware.

### How it works

- Prospects enter a demo code on the Demo Welcome Screen
- They go through: welcome → consent → profile collection → photo capture → roofline demo → completion
- Demo Mode simulates lighting so no real hardware is needed
- Prospect contact info is captured for follow-up

### Managing demo codes

Demo codes live in the same `dealerDemoCodes` collection as Media Mode codes. Each document uses the same fields described in Section 14.

- Codes can have expiration dates (`expiresAt`) and usage limits (`maxUses`)
- `usageCount` tells you which channels are pulling traffic
- Set `isActive: false` to revoke a code without deleting the record

### Lead capture

- Demo sessions capture prospect name, email, phone
- The sales team uses this data to follow up
- Review leads in Firebase Console or from the Admin Dashboard

<div class="tip">
<strong>Tip:</strong> Create a dedicated demo code per marketing campaign or event so you can attribute leads to the right channel.
</div>

---

## 16. What your dealers see

When dealers sign in, they land on a 4-tab Dealer Dashboard. Knowing what they see helps you support them.

### Overview tab

- Stat cards — total jobs, active installs, team size
- Pipeline status bar — visual job status breakdown
- Recent activity feed

### Pipeline tab

- Every sales job from their team
- Filterable by status
- Tap any job for full detail

### Team tab

- Their installer roster
- Active/inactive status
- Install count per installer

### Payouts tab

- Pending rewards waiting on your admin approval
- Approved and fulfilled payout history
- Ambassador tier progress indicator

---

## 17. Weekly Brief notifications

The system sends an automated weekly push to every user with Autopilot enabled.

### How it works

- A scheduled Cloud Function (`sendWeeklyBrief`) fires every Sunday at 18:30 UTC
- For each user with `autopilot_enabled` and `weekly_schedule_preview_enabled` set to `true`:
  1. Pulls their upcoming `autopilot_events` for the next week
  2. Calls Claude Haiku to generate a personalized 1–2 sentence body
  3. Sends an FCM push titled **"Your Week in Lights"** with a deep-link to the autopilot schedule

### Requirements

- `ANTHROPIC_API_KEY` must be set as an environment variable in the Cloud Functions runtime
- Users must have a valid `fcmToken` in their Firestore user document
- The function cleans up stale FCM tokens automatically

### Deploying

```bash
cd functions
npm run build
firebase deploy --only functions:sendWeeklyBrief
```

### Android notification channel

Channel ID: `autopilot_weekly`. Registered in the app as **"Weekly Schedule Preview"**. Users can disable the channel in Android settings without affecting other Lumina notifications.

### Monitoring

- Function logs show eligible user count, sent/skipped/error counts
- Firebase Console → Functions → `sendWeeklyBrief` for execution logs
- If nothing's being sent: verify `ANTHROPIC_API_KEY` is set and that users have valid FCM tokens

---

## 18. Firestore security rules — quick summary

Your rules enforce this access model:

| Who | Can do |
|-----|--------|
| **Regular users** | Read/write their own data only — profile, controllers, properties, schedules, geofences |
| **Media / dealer / admin users** | Read any user's data including properties (for customer lookup and content) |
| **Installers** | Create installation records (with required fields) |
| **Admins** | Full CRUD on dealers, installers, installations |

The `user_role` field on each profile (`residential`, `media`, `dealer`, `admin`) decides access level.

Subcollections under `/users/{uid}` — owner-only write, media/dealer/admin read:
- `controllers` — registered WLED controllers
- `properties` — properties/locations with linked controller IDs
- `commands` — cloud relay commands (ESP32 bridge can read/write too)
- `bridge_status` — ESP32 bridge heartbeat
- `geofences` — location-based automation triggers

---

## 19. Onboarding a new dealer — complete checklist

When you sign up a new dealer, here's the full sequence:

- [ ] Collect their info — contact name, company name, email, phone
- [ ] Open the Staff PIN screen — Lumina login → tap Lumina logo 5 times → enter `9999`
- [ ] Create the dealer — **Manage Dealers** → **Add Dealer** → fill in info → **Save**
- [ ] Note the dealer code (e.g., `03`)
- [ ] Create their installers — **Manage Installers** → select dealer → **Add Installer** for each technician
- [ ] Note each installer PIN (e.g., `0301`, `0302`)
- [ ] Send the dealer:
  - Their dealer code
  - Every installer's 4-digit PIN
  - The **Dealer & Installer Setup Guide** PDF
  - A reminder that access is via the **hidden 5-tap gesture** on the Lumina logo (no visible button)
- [ ] Confirm they can sign in — have one installer test their PIN via the 5-tap gesture

---

## 20. Quick reference

| Action | Where |
|--------|-------|
| Open Staff PIN screen | Login → tap Lumina logo 5 times (within 3 seconds) |
| Enter Admin Dashboard | Staff PIN → `9999` |
| Enter Corporate Dashboard | Staff PIN → Corporate PIN |
| Enter Sales Mode | Staff PIN → Sales PIN |
| Enter Installer Mode | Staff PIN → Installer PIN (e.g., `0301`) |
| Create a dealer | Admin Dashboard → **Manage Dealers** → **Add** |
| Create an installer | Admin Dashboard → **Manage Installers** → **Add** |
| Deactivate a dealer | **Manage Dealers** → tap dealer → toggle **Active** off |
| Deactivate an installer | **Manage Installers** → tap installer → toggle **Active** off |
| View installation stats | Admin Dashboard (top cards) |
| Add controller by IP | Installer Mode → Controller Setup → **Add Controller** → **Enter IP Address** |
| Create a media access code | Firebase Console → `dealerDemoCodes` |
| View all installations | Firebase Console → `installations` |
| Change sales PIN | Firebase Console → Firestore → `app_config/master_sales_pin` |
| Change corporate PIN | Firebase Console → Firestore → `app_config/master_corporate_pin` → update `pin_hash` |
| Approve payouts | Admin Dashboard → **Payout Approval** |
| View sales pipeline | Admin Dashboard → **Sales Jobs** |
| View network analytics | Corporate Dashboard → **Network** tab |
| Deploy Weekly Brief | `firebase deploy --only functions:sendWeeklyBrief` |
| Manage demo codes | Firebase Console → `dealerDemoCodes` |
| Reveal App Store review button | Login → tap **POWERED BY NEX-GEN** subtitle 5 times |

---

## 21. Security notes

### What's solid in v2.2

- **Hidden staff entry** — the visible "Installer / Dealer Access" button is gone. Staff access now requires the 5-tap gesture, dramatically lowering the chance customers stumble onto it.
- **Corporate PIN uses SHA-256** — never stored in plaintext. This is the pattern to replicate for the other admin PINs.
- **30-second lockout** — 5 failed attempts triggers a screen-local lockout, which rate-limits brute force.
- **Priority-based PIN routing** — the check order (Corporate → Installer → Sales) prevents PIN collisions from routing to the wrong mode.

<div class="warning">
<strong>Things to tighten before scaling:</strong>

- <strong>Admin PIN is hardcoded</strong> (<code>9999</code> in <code>admin_providers.dart</code>). Anyone who guesses it gets full admin. Migrate to a hashed Firestore value.
- <strong>Master Installer PIN is hardcoded</strong> (<code>8817</code> in <code>installer_providers.dart</code>). Same migration path.
- <strong>Demo/media codes</strong> are managed in Firebase Console today — consider an in-app screen.
- <strong>No audit log</strong> — dealer/installer changes aren't tracked. A Firestore <code>audit_log</code> collection would fix this.
- <strong>Deletes are soft</strong> — deactivation only, data is preserved.
- <strong>Lockout is screen-local</strong> — dismissing and reopening resets the counter. Persisting lockout state in local storage would close that gap.
</div>

---

## What success looks like

- Every active dealer has at least one active installer with a working 4-digit PIN
- New installs appear in `/installations` with dealer code, installer code, warranty date, and controller serials filled in
- Sales pipeline moves jobs through `Draft` → `EstimateSent` → … → `InstallComplete` without stalling beyond 14 days
- Corporate Dashboard's Network tab shows "active" dealer classifications across the network
- Weekly Brief function logs show a healthy eligible-user count and near-zero error rate every Sunday evening
- Payout approvals clear within your SLA and no dealer is unknowingly blocked by the $599 gift card cap

## If something isn't working

**"I can't find the Admin Access button."**
It's gone — that's by design in v2.2. Go to the Lumina login screen and tap the **Lumina logo** 5 times within 3 seconds. No visual feedback during the taps. The Staff PIN screen opens on tap 5.

**"Maximum dealer limit (99) reached."**
You've used all 99 dealer codes. You'd need to reclaim deactivated codes (a code change) or expand the code format.

**"An installer says their PIN doesn't work."**
1. Check the installer's **Active** status.
2. Check their parent dealer — a deactivated dealer kills every installer PIN underneath.
3. Verify all 4 digits.
4. Confirm they're using the 5-tap gesture on the Lumina logo, not looking for an old button.
5. If locked out after 5 failed attempts, the screen clears after 30 seconds — or dismiss and reopen.

**"A PIN is routing to the wrong mode."**
The Staff PIN screen checks in priority order — Corporate → Installer → Sales. If a Sales PIN is routing to Installer Mode, the number matches an installer PIN. Assign a different Sales PIN.

**"A dealer left the program."**
1. **Manage Dealers** → find them → toggle **Active** off.
2. All their installers are deactivated automatically.
3. Existing customer installations are untouched — those accounts keep working.
4. The dealer code is not reused.

**"I need to transfer an installer to a different dealer."**
You can't — the dealer code is baked into the PIN. Instead: deactivate the old installer record, create a new one under the new dealer, hand the tech their new PIN.

**"Weekly Brief didn't send."**
Check Firebase Console → Functions → `sendWeeklyBrief` logs. Most common causes: `ANTHROPIC_API_KEY` missing from the runtime environment, or stale `fcmToken` values in user docs. The function logs show both.

---

*Nex-Gen Lumina v2.2 — Admin Operations Guide — April 2026 — INTERNAL USE ONLY*
