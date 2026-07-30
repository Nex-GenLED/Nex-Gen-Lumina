---
title: "Nex-Gen Lumina — Dealer & Installer Setup Guide"
subtitle: "From onboarding your dealership to handing off a live customer"
author: "Nex-Gen LED LLC"
date: "July 2026"
pdf_options:
  format: Letter
  margin: 18mm
  printBackground: true
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Nex-Gen Lumina — Dealer &amp; Installer Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: []
body_class: guide
---

<style>
  body { font-family: 'DM Sans', 'Segoe UI', Arial, sans-serif; color: #DCF0FF; background: #07091A; line-height: 1.6; font-size: 10.5pt; }
  h1, h2, h3, h4 { font-family: 'Exo 2', 'Segoe UI', Arial, sans-serif; }
  h1 { font-size: 25pt; background: linear-gradient(90deg, #6E2FFF, #00D4FF); -webkit-background-clip: text; background-clip: text; color: transparent; border-bottom: 2px solid #00D4FF; padding-bottom: 10px; }
  h2 { color: #00D4FF; margin-top: 30px; font-size: 15.5pt; border-bottom: 1px solid #1F2542; padding-bottom: 5px; }
  h3 { color: #FFFFFF; margin-top: 20px; font-size: 12pt; }
  h4 { color: #9FD8FF; margin-top: 14px; margin-bottom: 3px; font-size: 10.5pt; }
  strong { color: #FFFFFF; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; background: #111527; font-size: 9.5pt; }
  th, td { border: 1px solid #1F2542; padding: 7px 10px; text-align: left; vertical-align: top; }
  th { background: #241A55; color: #DCF0FF; }
  ol, ul { padding-left: 22px; }
  li { margin: 3px 0; }
  .tip { background: rgba(0, 212, 255, 0.10); border-left: 4px solid #00D4FF; padding: 9px 14px; margin: 12px 0; border-radius: 4px; }
  .warning { background: rgba(255, 170, 60, 0.10); border-left: 4px solid #FFAA3C; padding: 9px 14px; margin: 12px 0; border-radius: 4px; }
  .note { background: rgba(110, 47, 255, 0.14); border-left: 4px solid #6E2FFF; padding: 9px 14px; margin: 12px 0; border-radius: 4px; }
  .step-box { background: #111527; border: 1px solid #1F2542; border-radius: 8px; padding: 14px; margin: 10px 0; }
  code { background: #1F2542; color: #00D4FF; padding: 2px 6px; border-radius: 3px; font-size: 0.88em; }
  hr { border: none; border-top: 1px solid #1F2542; margin: 24px 0; }
  .pagebreak { page-break-before: always; }
</style>

# Nex-Gen Lumina — Dealer & Installer Setup Guide

This is the complete handbook for getting your dealership up and running and completing customer installations end-to-end. Nex-Gen LED LLC ships permanent residential and commercial lighting that works as hard as you do — this guide is how you deliver that experience to every customer on Day 1.

## What you'll need

- Your **dealer code** from Nex-Gen LED LLC (e.g., `03`)
- Your **Sales PIN** (for reps doing site surveys) and each installer's **4-digit PIN** (dealer code + installer code)
- The Lumina app on every phone or tablet used by your team
- Customer contact info and install notes for the visit
- The physical controllers and LED runs installed, powered, and reachable on the customer's network

<div class="warning">
<strong>Before you flash or install anything:</strong> every controller must be on the <strong>pinned WLED version</strong> — <code>0.15.1</code> for both SKIKBILY 4-channel and Dig-Octa 8-channel. Flashing "latest" (0.15.4) produces a controller that stalls periodically in the field <em>and passes every other check in this guide</em>. The <strong>Dealer Pre-Install Setup SOP</strong> (§2.0) is the authority on bench prep; this guide assumes you have followed it.
</div>

---

## 1. The two-tier model

Lumina uses a simple structure that keeps your team organized and your accounts clean:

| Role | What it is |
|------|-------------|
| **Dealer** | Your company. You get one unique 2-digit code (`01`–`99`). |
| **Installer** | A technician under your dealership. Each gets a 2-digit code (`01`–`99`). |

Every installer carries a **4-digit PIN** that combines both codes. Dealer code `03` + installer code `12` = PIN `0312`. That PIN is how an installer enters Installer Mode during a job.

<div class="note">
<strong>Code <code>55</code> is reserved.</strong> It is the fleet-shared code that Nex-Gen master support PINs mint. It is never assigned to a dealership and it cannot be used to install a customer — see Section 7.
</div>

---

## 2. Sales Mode — for field reps

Sales Mode is a separate workflow for reps doing site surveys and generating estimates. It does not install or configure systems.

### Getting in

1. Open Lumina
2. On the login screen, tap the **Lumina logo** 5 times within 3 seconds — this opens the Staff PIN screen
3. Enter your **Sales PIN** (Nex-Gen admin provides this)
4. Sessions run 30 minutes with auto-save on timeout

### The sales workflow

1. **Prospect Info** — customer contact details and address
2. **Zone Builder** — map LED zones, record run lengths, mark injection points and power mount locations
3. **Visit Review** — verify the survey data before generating the estimate
4. **Estimate Preview** — review pricing with the customer
5. **Customer Signature** — present the estimate and collect a digital signature

### Seeing your pipeline

- From the Sales landing screen, tap **My Estimates** to see every job you've created
- Each row shows status, customer name, and date
- Status progression: Draft → Estimate Sent → Estimate Signed → Pre-Wire Scheduled → Pre-Wire Complete → Install Complete

Sales data flows into the Dealer Dashboard for pipeline tracking — see Section 5. For the full playbook, see the **Sales Mode Guide**.

### Demo Mode — for prospects without a system yet

During a site visit, if the prospect doesn't have a Lumina system installed, you can still put the experience in their hands.

1. On the Lumina login screen, enter the **demo access code** (provided by Nex-Gen)
2. The prospect sees a simulated Lumina experience on their phone or yours
3. They can browse patterns, try the AI assistant, and see the dashboard
4. The app captures their contact info as a lead for follow-up

Demo Mode uses simulated lighting — no real hardware required — and it's one of the most persuasive parts of a sales visit.

---

## 3. Getting your dealer account

Dealer accounts are created by the Nex-Gen LED LLC administrative team.

**Send Nex-Gen:**

- Contact person name
- Company name
- Email address
- Phone number

Back from Nex-Gen you'll get:

- Your **2-digit dealer code** (e.g., `03`)
- Access to the **Admin Portal** for managing your installers

---

## 4. Registering installers

Once your dealership is active, you add installers from the Admin Portal inside the Lumina app.

### Getting into the Admin Portal

1. Open Lumina
2. Open the Staff PIN screen (tap the **Lumina logo** 5 times on the login screen)
3. Enter the **Admin PIN** provided by Nex-Gen LED LLC

### Adding an installer

1. Tap **Manage Installers**
2. Tap **Add Installer**
3. Fill in full name, email, and phone
4. The system auto-assigns the next installer code
5. Tap **Save**

The 4-digit PIN is generated and shown on screen.

<div class="tip">
<strong>Tip:</strong> Share the PIN with your installer through a secure channel. They'll use it every time they enter Installer Mode on a job.
</div>

### What else you can do

- **Deactivate** an installer — blocks their PIN immediately
- **View stats** — total installations per installer
- **Edit** contact details

<div class="warning">
<strong>Heads-up:</strong> If your dealer account is deactivated, every installer under your dealership is automatically locked out.
</div>

<div class="warning">
<strong>Onboarding a brand-new dealership is currently a Nex-Gen-assisted process.</strong> Adding installers under an <em>already-active</em> dealer code works as described above. If you are standing up a new dealership, coordinate with Nex-Gen — do not assume the portal will complete it unattended.
</div>

---

## 5. Your Dealer Dashboard — the business side

As a dealer, you have a live dashboard for tracking your business.

### What's there

| Tab | What it shows |
|-----|--------------|
| **Overview** | Total jobs, active installs, team size, pipeline summary |
| **Pipeline** | Every sales job across your team, with status filters |
| **Team** | Your installers — active/inactive status, install counts |
| **Payouts** | Referral rewards, payout status, ambassador tier progress |

### Working the pipeline

- See every job your team has in progress
- Filter by status to focus where follow-up is needed
- Tap any job for full detail

<div class="tip">
<strong>If the Team tab looks empty</strong> on a brand-new dealership, add your first installer from the Admin Portal (Section 4) rather than from the Team tab — the empty state there does not yet offer a create action.
</div>

For the complete dashboard walkthrough, see the **Dealer Dashboard Guide**.

---

## 6. Referral Rewards program

Every converted referral earns you (and your customers) a reward.

### How it works

1. Share your unique referral code with prospects and customers
2. A referral that leads to a completed installation earns a reward
3. Rewards are tracked automatically through Lumina
4. Nex-Gen LED LLC admin reviews and approves payouts

### Your referral code

- On the Dealer Dashboard under the **Payouts** tab
- Also on the **Refer & Earn** customer-facing screen

### Ambassador tiers

| Tier | Installs Required | Reward level |
|------|------------------|-------------|
| Bronze | 0+ | Base |
| Silver | 3+ | Increased |
| Gold | 8+ | Higher |
| Platinum | 15+ | Maximum |

### Reward types

- **Visa Gift Card** — capped at $599 per calendar year
- **Nex-Gen Credit** — no annual cap

### Payout flow

1. Installation completes → reward is calculated
2. Reward enters **Pending**
3. Nex-Gen admin reviews and approves
4. Payout is processed

<div class="pagebreak"></div>

## 7. Installer Mode — the eight-step setup

Installer Mode is the guided wizard that stands up a customer's Lumina system and creates their account. Plan on about 30 minutes, assuming the hardware is installed, powered, and reachable on the network.

### The eight steps at a glance

| # | Step | What it does |
|---|------|-------------|
| 1 | **Customer Info** | Name, email (becomes their login), phone, address, notes |
| 2 | **Controller Setup** | Discover, select, name, and test the controllers |
| 3 | **Connection Method** | Pick Ethernet *or* Wi-Fi per controller — never both |
| 4 | **Zone Configuration** | Residential (link controllers) or Commercial (build zones) |
| 5 | **Hardware Config** | LED type, color order, per-channel bus assignments |
| 6 | **Map Roofline** | Pixel-walk each channel, marking corners, peaks, columns |
| 7 | **Brand Setup** | Commercial only — auto-skipped on residential installs |
| 8 | **Customer Handoff** | Preferences, pre-flight check, credentials |

### Getting in

1. Open Lumina
2. Open the Staff PIN screen (tap the **Lumina logo** 5 times on the login screen)
3. On the **Installer Mode** overview screen, tap **Continue**
4. Enter your **4-digit PIN** on the numeric keypad
5. The PIN auto-submits when all 4 digits are entered

<div class="warning">
<strong>Security:</strong> 5 failed PIN attempts triggers a 30-second lockout. Wait it out, or dismiss and reopen the Staff PIN screen.
</div>

<div class="warning">
<strong>Master support PINs cannot install.</strong> A master PIN mints the reserved dealer code <code>55</code>, and a customer stamped <code>55</code> lands in a shared scope every master-PIN holder can read. The wizard refuses it before any account work with: <em>"That's a master support PIN — it can't be used to set up a customer."</em> Use your own installer PIN for every real install.
</div>

### Session rules

- Sessions last **30 minutes** of inactivity
- A warning shows **5 minutes** before timeout — you can extend from there
- If the session expires, progress **auto-saves** and you can resume later

---

### Step 1: Customer information

| Field | Required | Notes |
|-------|----------|-------|
| Full Name | Yes | Customer's name |
| Email | Yes | Must be unique — this becomes their login |
| Phone | No | For contact |
| Address | No | Start typing and Google Places suggests matching addresses. Tap to auto-fill, or type it manually. |
| Notes | No | Any special instructions |

<div class="tip">
<strong>Tip:</strong> The email is checked for uniqueness in real time. If the customer already has a Lumina account, you'll see an error — contact Nex-Gen support to link the existing account rather than creating a duplicate.
</div>

Tap **Next**.

---

### Step 2: Controller setup

**2a. Discover controllers**

- Make sure your phone or tablet is on the **same network** as the controllers
- Tap **Scan for Controllers** — the app finds Nex-Gen devices on the network
- Available controllers appear with their IP addresses

**2b. Select controllers**

- Check the box next to each controller that belongs to this installation
- At least one controller must be selected

**2c. Name each controller**

- Give descriptive names — "Front Roofline", "Garage Accent", "Side Fascia"

**2d. Test connectivity**

- Tap **Test** next to each controller
- Green check → responding. Red X → unreachable; check power and network

**2e. Add new controllers via Bluetooth** (optional)

- If a controller isn't on the network yet, tap **Add via BLE** to launch Bluetooth provisioning and enter Wi-Fi credentials

**2f. Installation photo** (optional)

- Tap **Capture Photo** to store a photo of the completed install with the record

Tap **Next**.

---

### Step 3: Connection method

<div class="warning">
<strong>Never leave a controller on both Ethernet and Wi-Fi.</strong> A dual-homed controller can answer on either IP, so its address changes out from under the app and future service calls become guesswork. Pick one connection per controller — every time.
</div>

For each selected controller the wizard reads its current state and offers the right choice:

- **Wi-Fi only, no Ethernet detected** — nothing to do. If a wall jack is reachable, Ethernet is still the recommended upgrade.
- **Both connections active** — pick one to keep:
  - **Keep Ethernet, disable Wi-Fi from app** — the app turns Wi-Fi off on the controller and confirms it comes back on Ethernet. If it doesn't return, check the Ethernet cable.
  - **Keep Wi-Fi, I will unplug Ethernet** — the wizard prompts **Unplug Ethernet now**, then you tap **Verify**. If the Ethernet IP is still answering, the cable is still seated.

Use **Ethernet whenever a wall jack is reachable** — it's more reliable than Wi-Fi for a permanent install. Tap the **Why we pick one connection** card in the app if a customer asks.

Tap **Continue**.

---

### Step 4: Zone configuration

#### Option A: Residential (single property)

Best for single homes with one or more LED runs acting as a unified system.

1. Select **Residential**
2. Tap **Link All Controllers**, or link them individually
3. Linked controllers sync brightness and effects — turn one on, they all turn on
4. Family members can be invited later (5 by default)

#### Option B: Commercial (multi-zone)

Best for businesses with independent lighting areas.

1. Select **Commercial**
2. Tap **Add Zone** and name it ("Storefront", "Patio", "Parking Lot")
3. For each zone, set a **Primary Controller**, add **Secondary Controllers** if needed, and enable **DDP Sync** to sync effects across the zone
4. At least one zone is required to continue

Tap **Continue**.

---

### Step 5: Hardware configuration

This sets LED type, color order, and per-channel bus assignments on the controller.

- **Apply Nex-Gen Standard** — the fast path, and what you should use on a standard install. Applies the Nex-Gen defaults and confirms with *"Nex-Gen Standard applied."*
- **Custom configuration** — for non-standard hardware; set the values by hand.
- **Skip for now** — leaves whatever the controller is already configured for. The wizard warns you first: *"Your lights and schedules need controller setup to work…"*

<div class="warning">
Only skip this step if the controller was already fully configured on the bench. Wrong LED counts or color order are the #1 cause of "the colors are wrong" and "a section is dark" callbacks.
</div>

Tap **Continue**.

---

### Step 6: Map roofline

This is the pixel-walk mapping step. Instead of typing segment tables, you drive a lit pixel along the run and mark the features as you go.

1. Pick a channel — the list comes from the device's hardware config, so Step 5 must be done first
2. Tap **Chase** to start the lit pixel moving; **Pause** to stop it on a feature
3. With the cursor on a feature, tap **Mark at cursor** and choose:
   - **Corner** — the roofline changes direction
   - **Run split** — one straight run becomes another
   - **Column** — a vertical post or pillar
   - **Custom** — anything else worth naming
4. For gables, use **Add peak** with **Symmetric peak** to mirror both sides at once
5. **Sweep preview** plays the mapped result back so you can confirm it before moving on
6. Repeat for each channel, then tap **Continue**

**Inferred features** shows what the app derived from your marks.

<div class="tip">
<strong>Map later</strong> is always available and an install is never blocked by mapping. But an unmapped system can't do peak/corner accent effects or Design Studio previews properly — map it on the job if you possibly can.
</div>

<div class="note">
The older segment-and-anchor <strong>Roofline Setup Wizard</strong> still exists for detailed edits and for systems mapped before pixel-walk shipped. Reach it from the customer's app: <strong>System → System Management → Roofline Setup → Setup Wizard</strong> (or <strong>Edit Layout</strong>). See Appendix A.
</div>

---

### Step 7: Brand setup (commercial only)

On a **commercial** install this step pre-seeds the business's brand — name, logo, and brand colors — so the customer's zones open with their palette already loaded. You can complete it or skip it.

On a **residential** install the wizard skips this step automatically. You will not see it.

---

### Step 8: Customer handoff

This step shapes the customer's first experience *and* runs the final safety checks.

#### Preferences

**Profile Type** — confirm **Residential** or **Commercial**. Commercial accounts also take a **Manager Email**.

**Favorite Teams** — teams the customer follows, used for automatic game-day lighting. Coverage spans the NFL, NBA, WNBA, MLB, NHL, MLS, NWSL, and major college programs.

**Favorite Holidays** — Christmas, Halloween, 4th of July, New Year's, St. Patrick's Day, Thanksgiving, Easter, Valentine's Day.

**Lighting Style** — slide between **Subtle & Elegant** and **Bold & Energetic**.

**How should Lumina handle changes?**

| Option | Behavior |
|--------|----------|
| **Ask me first** | Passive — suggests changes, waits for approval |
| **Smart suggestions** | Weekly preview, auto-applies if no response in 24 hours |
| **Full auto-pilot** | Fully automatic, no approval needed |

**Simple Mode** — toggle ON for customers who want large buttons, only Home and Settings, and simple brightness control. Recommended for older users, first-time smart-home owners, and anyone who wants one-tap control. They can switch modes later in Settings.

#### Pre-flight check

Below the preferences, the wizard verifies **every controller is actually on the connection method you picked in Step 3**. **Complete Setup stays locked until this passes.**

| Row | Meaning |
|-----|---------|
| Green check | Controller verified on the chosen connection |
| Amber warning | Advisory — worth a look, doesn't block |
| Red X | Blocking. Tap **Back to Connection Step** and resolve it |

There's also an advisory **Controller clock** line covering clock, timezone, and location. It **warns but never blocks**:

- *"Clock, timezone & location OK"* — good to go
- A named controller plus an issue — fix it before the customer relies on schedules. The remedy is in the controller's own web UI: **Config → Time & Macros** (enable NTP, set the Time Zone, set Latitude/Longitude).

<div class="warning">
Don't hand off a system with a clock warning. A controller whose clock never synced fires <strong>no schedules at all</strong>, and the customer will experience that as "the app doesn't work."
</div>

<div class="note">
<strong>Coordinates are what make sunset schedules work.</strong> Sunrise/sunset scheduling is live, and the app <strong>refuses to arm a solar timer</strong> when the controller's latitude/longitude are unset or left at <code>0,0</code> — the customer's "on at sunset" schedule then silently never arms. Set them during the defaults push (or in the controller's <code>Config → Time &amp; Macros</code>) and confirm the pre-flight clock row is green. Two constraints worth knowing when you build the first schedule: the system supports <strong>one sunrise and one sunset schedule</strong>, and there's no offset field yet, so a sunset schedule fires at sunset rather than a set number of minutes before.
</div>

#### Complete Setup

When you tap **Complete Setup**, the app:

1. Creates the customer's Firebase account (email + temporary password)
2. Registers the installation (warranty starts — 5 years)
3. Creates their profile with all preferences
4. Migrates the controllers you added — including any roofline mapping — to the customer's account
5. Increments your installation count
6. Signs you out of the installer session

### The customer credentials screen

```
CUSTOMER LOGIN CREDENTIALS
----------------------------
Name:               Jane Smith
Email:              jane@email.com
Temporary Password: Xk9mB2nQ

Customer should change their password after first login.
```

**Actions:** **Copy Email**, **Copy Password**, **Copy All**, **Done**.

<div class="warning">
<strong>Important:</strong> Capture these credentials before tapping <strong>Done</strong>. The temporary password cannot be retrieved later. If it's lost, the customer has to use <strong>Forgot Password</strong>.
</div>

<div class="tip">
<strong>If you see a warning instead of a clean finish:</strong> when the customer's account has already been created, the wizard now completes the install and shows you the credentials screen with a warning, rather than claiming "Setup failed." If you get the credentials screen, <strong>the install landed</strong> — hand them off. Only a failure reported <em>before</em> the credentials screen means nothing was provisioned.
</div>

---

## 8. Handing off to the customer

Give them their credentials and walk them through:

1. **Download the Lumina app** from the App Store or Google Play
2. **Open the app** and sign in with the email and temporary password
3. **Change their password** when prompted
4. **Allow the permission prompts** they care about (location for Welcome Home / home-network detection)
5. **Dashboard appears** — their system is ready

<div class="tip">
<strong>Pro tip:</strong> Spend 2 minutes on the dashboard with them — toggle a favorite, drag brightness, and say "Try asking Lumina to set the lights to warm white." A short live demo dramatically reduces support calls. Hand them the <strong>Lumina Homeowner Guide</strong> as well.
</div>

---

## 9. Configuring remote access

For customers who want control while away, remote access should be configured before you leave. It requires a **Lumina Bridge** — a small device that stays plugged in at the customer's home and relays commands from the cloud to the controller.

### Setting up the Lumina Bridge

1. **Flash the Lumina Bridge firmware** (see the **ESP32 Bridge Setup Guide**)
2. **Connect to the bridge's Wi-Fi AP** (`Lumina-XXXX`) from your phone
3. **Walk the 3-step setup wizard:**
   - Connect the bridge to the customer's home Wi-Fi
   - Enter the bridge's cloud credentials
   - Enter the customer's Lumina user ID and controller IP
4. The bridge reboots and begins relaying

Verify at `http://<bridge-ip>/` — Wi-Fi, authentication, and user-paired indicators should all be green.

### Configuring remote access in the app

**System → System Management → Remote Access**, then:

- **Enable Remote Access**
- **Detect Home Network** while connected to the customer's Wi-Fi
- **Connection Mode** → **ESP32 Bridge** (recommended) or **Webhook** (DIY, needs DDNS + port forwarding)
- **Test Bridge** — you want **Bridge Connected**

The screen also shows the customer's **User ID** with a **Copy User ID** action — that's the value the bridge needs.

<div class="warning">
<strong>Permissions:</strong> <strong>Detect Home Network</strong> prompts for <strong>Location permission</strong>, which is what allows the app to read the Wi-Fi network name. If the customer declines, the app explains what's needed instead of failing silently. The SSID is encrypted before storage.
</div>

<div class="note">
<strong>Schedules are LAN-only writes.</strong> Timer configuration is pushed over the local network. Remote access covers on/off, brightness, and patterns — it does not arm schedules. Do any schedule setup while you're still on the customer's Wi-Fi.
</div>

---

## 10. Resuming an incomplete setup

If you exit the wizard before completing, progress auto-saves.

Next time you enter Installer Mode:

1. Enter your PIN
2. **"Resume Previous Setup?"** shows the customer name, current step, and save time
3. **Resume Setup** continues where you left off; **Start Fresh** begins a new installation

---

## 11. Warranty and installation records

Each completed installation automatically creates a warranty record:

| Field | Value |
|-------|-------|
| **Warranty start** | Date of installation |
| **Warranty duration** | 5 years |
| **Installer** | Your name and PIN |
| **Dealer** | Your company name and code |
| **Controllers** | Serial numbers of every installed device |
| **Address** | Customer's installation address |

These records are available to the Nex-Gen support team for warranty claims.

<div class="pagebreak"></div>

## 12. Quick reference

### PIN format
`[Dealer Code — 2 digits][Installer Code — 2 digits]` — dealer 03 + installer 12 = **0312**. Code `55` is reserved for master support PINs and cannot install.

### The eight setup steps
1. Customer Info
2. Controller Setup
3. Connection Method (Ethernet *or* Wi-Fi)
4. Zone Configuration (residential / commercial)
5. Hardware Config (Apply Nex-Gen Standard)
6. Map Roofline (pixel-walk; skippable)
7. Brand Setup (commercial only)
8. Customer Handoff (preferences + pre-flight + credentials)

### Quick actions

| Action | Where |
|--------|-------|
| Open Staff PIN screen | Login → tap Lumina logo 5 times (within 3 seconds) |
| Enter Sales Mode | Staff PIN → Sales PIN |
| Enter Installer Mode | Staff PIN → 4-digit installer PIN |
| View sales jobs | Sales Mode → **My Estimates** |
| Access Dealer Dashboard | Main screen → **Dealer Dashboard** |
| View referral rewards | Dealer Dashboard → **Payouts** |
| Use Demo Mode | Login screen → demo access code |
| Look up an existing customer | Installer Mode → **Existing Customer** |

### Support
Email: **support@nexgenled.com**

---

## What success looks like

- Credentials delivered, password changed, customer signed in
- Every controller shows online in the customer's app, on **one** connection each
- Pre-flight check passed green, with no clock warning outstanding
- A test pattern runs correctly across the whole run, in the right direction
- Bridge status green (if remote access was configured)
- A schedule created and synced **while you were still on the customer's Wi-Fi**
- Warranty record exists with all controllers and the correct install date
- The customer shows *you* they can change something themselves

## If something isn't working

**"My PIN doesn't work."**
1. Confirm your installer account is **Active**.
2. Confirm your dealership is active — a deactivated dealer kills every installer PIN under it.
3. Check all 4 digits.
4. Locked out after 5 failed attempts? Wait 30 seconds, or dismiss and reopen the Staff PIN screen.

**"The wizard says my PIN can't set up a customer."**
You used a master support PIN (dealer code `55`). Re-enter your own installer PIN.

**"I can't find any controllers during Scan."**
Confirm your phone is on the **same network** as the controllers. New controllers not yet on the network need **Add via BLE** first. Check power and that they booted cleanly.

**"The customer's email is already in use."**
They already have a Lumina account. Don't create a duplicate — email **support@nexgenled.com** to link the existing account.

**"Complete Setup is greyed out."**
The pre-flight check hasn't passed. A red row means a controller isn't on the connection method you chose — tap **Back to Connection Step** and resolve it.

**"A pattern ran the wrong direction after mapping."**
Re-open Map Roofline and confirm the marks are in the order the pixel actually travels, starting from pixel 1 on that channel.

**"The install said it failed but the customer got an email."**
If you reached the credentials screen, the install committed. Verify the customer can sign in before re-running anything — a second run would create a duplicate.

**"The bridge shows unreachable after setup."**
Open `http://<bridge-ip>/`. Wi-Fi green but auth red → re-enter the bridge credentials. Power-cycle and wait 30 seconds. Confirm bridge and controller are on the same network.

**"I lost the customer's temporary password."**
It can't be retrieved. Walk them through **Forgot Password** on the sign-in screen.

<div class="pagebreak"></div>

## Appendix A — Roofline Setup Wizard (segments and anchors)

The pixel-walk mapper in Step 6 is the fast path. This older wizard is still available for detailed edits, unusual layouts, and systems mapped before pixel-walk shipped. Reach it from the customer's app: **System → System Management → Roofline Setup → Setup Wizard** (or **Edit Layout**).

<div class="warning">
Roofline configuration drives pattern placement. If it's wrong, patterns land on wrong sections, chase effects run backwards, accent lighting misses the peaks, and AI recommendations degrade.
</div>

### A1. LED count and controller info

- **Active channels** — controllers support up to 8 output channels; select the ones in use
- **Total LED count** — the exact installed count (1–2600). Count at junction boxes if unsure
- **Controller location** — e.g. "Garage attic"
- **LED start location (LED #1)** — e.g. "Front left corner"
- **LED direction** — Left to Right, Right to Left, Clockwise, Counter-clockwise
- **LED end location** — where the last LED sits
- **Architecture type** — Ranch, Gabled, Multi-Gabled, Complex, Modern, Colonial

### A2. Segment definition

Add segments **in the order LEDs are physically connected**, starting from LED #1.

| Type | Use for |
|------|---------|
| **Run** | Straight horizontal/diagonal section |
| **Corner** | 90° change of direction |
| **Peak** | Roof apex / gable point |
| **Column** | Vertical pillar or post |
| **Connector** | Transition between sections |

Each segment takes a name, LED count, type, direction, location (Front / Back / Left / Right), and an **Is Prominent** flag for focal points.

**Example roofline (200 LEDs)**

| # | Name | LEDs | Type | Direction |
|---|------|------|------|-----------|
| 1 | Left Eave | 45 | Run | L→R |
| 2 | Left Corner | 8 | Corner | Upward |
| 3 | Left Gable | 35 | Run | Upward |
| 4 | Main Peak | 6 | Peak | L→R |
| 5 | Right Gable | 35 | Run | Downward |
| 6 | Right Corner | 8 | Corner | Downward |
| 7 | Right Eave | 45 | Run | L→R |
| 8 | Return | 18 | Run | L→R |

**Total:** 45+8+35+6+35+8+45+18 = **200**

### A3. Anchor points

Anchor points are the LEDs accent effects focus on — peaks, corners, and other focal points. They drive "light up the peaks"-style commands, accent patterns, and chase reversal points.

For each segment: review the auto-detected anchor, adjust the LED index if it isn't centered, and set the anchor zone size (default 2 LEDs).

Anchor types: **Peak**, **Corner**, **Boundary**, **Center**, **Custom**.

### A4. Review, save, and test

Verify before saving:

- Total LED count matches the physical install
- Segments add up to the total
- Segment order follows the physical wiring
- Peaks and corners marked correctly, directions accurate
- Anchors positioned correctly

Then **Save Configuration** and test: lights on/off, a pattern across all segments, brightness, and chase direction.

---

### Related guides

- **Dealer Pre-Install Setup SOP** — bench prep, firmware pinning, flash procedure (read this first)
- **Lumina Homeowner Guide** — hand this to the customer
- **Sales Mode Guide** — field sales visits and estimates
- **Dealer Dashboard Guide** — full dashboard tour
- **Day 1 Electrician Guide** / **Day 2 Install Guide** — dispatch-day workflows
- **ESP32 Bridge Setup Guide** — bridge firmware and pairing
- **Admin Operations Guide** — for Nex-Gen staff

---

*Nex-Gen Lumina — Dealer & Installer Setup Guide — July 2026*
