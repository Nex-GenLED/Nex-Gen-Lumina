---
title: "Nex-Gen Lumina — Dealer & Installer Setup Guide"
subtitle: "From onboarding your dealership to handing off a live customer"
author: "Nex-Gen LED LLC"
date: "April 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#DCF0FF;">Nex-Gen Lumina — Dealer & Installer Guide</div>'
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
  .step-box { background: #111527; border: 1px solid #1F2542; border-radius: 8px; padding: 14px; margin: 10px 0; }
  code { background: #1F2542; color: #00D4FF; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
</style>

# Nex-Gen Lumina — Dealer & Installer Setup Guide

This is the complete handbook for getting your dealership up and running and completing customer installations end-to-end. Nex-Gen LED LLC ships permanent residential and commercial lighting that works as hard as you do — this guide is how you deliver that experience to every customer on Day 1.

## What you'll need

- Your **dealer code** from Nex-Gen LED LLC (e.g., `03`)
- Your **Sales PIN** (for reps doing site surveys) and each installer's **4-digit PIN** (dealer code + installer code)
- The Lumina app on every phone or tablet used by your team
- Customer contact info and install notes for the visit
- The physical controllers and LED runs already powered and on the customer's Wi-Fi (for installer sessions)

---

## 1. The two-tier model

Lumina uses a simple structure that keeps your team organized and your accounts clean:

| Role | What it is |
|------|-------------|
| **Dealer** | Your company. You get one unique 2-digit code (`01`–`99`). |
| **Installer** | A technician under your dealership. Each gets a 2-digit code (`01`–`99`). |

Every installer carries a **4-digit PIN** that combines both codes. Dealer code `03` + installer code `12` = PIN `0312`. That PIN is how an installer enters Installer Mode on a customer's phone during a job.

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

Sales data flows into the Dealer Dashboard for pipeline tracking — see Section 5.

For the full sales playbook, see the dedicated **Sales Mode Guide**.

### Demo Mode — for prospects without a system yet

During a site visit, if the prospect doesn't have a Lumina system installed, you can put the experience in their hands anyway.

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

Once your dealership is active, you add installers yourself from the Admin Portal inside the Lumina app.

### Getting into the Admin Portal

1. Open Lumina
2. Open the Staff PIN screen (tap the **Lumina logo** 5 times on the login screen)
3. Enter the **Admin PIN** provided by Nex-Gen LED LLC

### Adding an installer

1. Tap **Manage Installers**
2. Tap **Add Installer**
3. Fill in:
   - Full name
   - Email
   - Phone
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

---

## 5. Your Dealer Dashboard — the business side

As a dealer, you have a live dashboard for tracking your business.

### Getting in

From the Lumina app, navigate to the **Dealer Dashboard**. Your dashboard shows real-time data about your team and pipeline.

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

Track your rewards, tier progress, and payout history from the Dealer Dashboard.

---

## 7. Installer Mode — the six-step setup

Installer Mode is the guided wizard that stands up a customer's Lumina system and creates their account. Plan on about 20 minutes start to finish, assuming the hardware is already installed and on Wi-Fi.

### Getting in

1. Open Lumina
2. Open the Staff PIN screen (tap the **Lumina logo** 5 times on the login screen)
3. On the **Installer Mode** overview screen, tap **Continue**
4. Enter your **4-digit PIN** on the numeric keypad
5. The PIN auto-submits when all 4 digits are entered

<div class="warning">
<strong>Security:</strong> 5 failed PIN attempts triggers a 30-second lockout. Wait it out or dismiss and reopen the Staff PIN screen.
</div>

### Session rules

- Sessions last **30 minutes** of inactivity
- A warning shows **5 minutes** before timeout — you can extend from there
- If the session expires, progress **auto-saves** and you can resume later

---

### Step 1: Customer information

Enter the homeowner's details:

| Field | Required | Notes |
|-------|----------|-------|
| Full Name | Yes | Customer's name |
| Email | Yes | Must be unique — this becomes their login |
| Phone | No | For contact |
| Address | No | Start typing and Google Places suggests matching addresses. Tap to auto-fill, or type it manually if you prefer. |
| Notes | No | Any special instructions |

<div class="tip">
<strong>Tip:</strong> The email is checked for uniqueness in real time. If the customer already has a Lumina account, you'll see an error — contact Nex-Gen support to link the existing account.
</div>

<div class="tip">
<strong>Tip:</strong> The address field uses Google Places autocomplete. Start typing the street and tap a suggestion — much faster than typing the whole address.
</div>

Tap **Next**.

---

### Step 2: Controller setup

Connect the physical controllers you installed.

**2a. Discover controllers**

- Make sure your phone or tablet is on the **same Wi-Fi** as the controllers
- Tap **Scan for Controllers** — the app finds Nex-Gen devices on the network
- Available controllers appear with their IP addresses

**2b. Select controllers**

- Check the box next to each controller that belongs to this installation
- At least one controller must be selected

**2c. Name each controller**

- Tap the name field next to each controller
- Give descriptive names — e.g., "Front Roofline", "Garage Accent", "Side Fascia"

**2d. Test connectivity**

- Tap **Test** next to each controller
- Green checkmark → controller is responding
- Red X → controller is unreachable, check power and Wi-Fi

**2e. Add new controllers via Bluetooth** (optional)

- If a controller hasn't been configured for Wi-Fi yet, tap **Add via BLE**
- This launches the Bluetooth provisioning wizard
- Walk through Wi-Fi credential entry on the controller

**2f. Installation photo** (optional)

- Tap **Capture Photo** to snap the completed install
- Stored with the installation record for reference

Tap **Next**.

---

### Step 3: Roofline configuration

<div class="warning">
<strong>This step is critical.</strong> An incorrect roofline configuration makes patterns display wrong, colors land on wrong sections, chase effects run the wrong direction, AI recommendations fail, and anchor point lighting break. Take the time to get this right.
</div>

The Roofline Wizard has 5 sub-steps.

#### 3a. LED count and controller info

**Select active channels**
Controllers support up to 8 output channels. Select which ones are in use. Most residential installs use **Channel 1 only**.

**Enter total LED count**
Enter the **exact** number of LEDs installed (1–2600). This must match the physical LED count. Count LEDs at junction boxes if you're unsure.

**Controller location**
Describe where the controller is mounted (e.g., "Garage attic", "Basement utility room", "Behind soffit near front door").

**LED start location (LED #1)**
Describe where the first LED is physically located (e.g., "Front left corner of house", "Above garage door, left side").

**LED direction**
Overall direction LEDs were installed: Left to Right, Right to Left, Clockwise, or Counter-clockwise.

**LED end location**
Where the last LED is (e.g., "Front right corner, returning to start").

**Architecture type**
The roof style that best matches:

| Type | Description |
|------|-------------|
| Ranch | Flat or minimal peaks |
| Gabled | Single peak/gable |
| Multi-Gabled | Multiple peaks |
| Complex | Mixed features, dormers, valleys |
| Modern | Contemporary, unique shapes |
| Colonial | Traditional with dormers |

#### 3b. Segment definition

Segments split the roofline into logical sections. Add them **in the order LEDs are physically connected**, starting from LED #1.

**Segment types**

| Type | Use for |
|------|---------|
| **Run** | Straight horizontal/diagonal section |
| **Corner** | 90° corner where roofline changes direction |
| **Peak** | Roof apex/gable point |
| **Column** | Vertical pillar or post |
| **Connector** | Transition between sections |

**For each segment, enter:**

1. **Name** — Descriptive label (e.g., "Front Left Eave", "Main Peak")
2. **LED Count** — Exact number of LEDs in this segment. All segments must add up to the total.
3. **Type** — From the table above
4. **Direction** — Which way LEDs flow (Left to Right, Right to Left, Upward, Downward)
5. **Location** — Where on the house (Front, Back, Left Side, Right Side)
6. **Is Prominent** — Check if this is a focal point (peaks, front sections)

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

#### 3c. Anchor points

Anchor points are the LEDs where accent effects focus — peaks, corners, and any other focal point. The system uses them for voice commands like "Light up the peaks", accent patterns, and chase animation reversal points.

For each segment:

1. Review the auto-detected anchor points
2. Adjust the LED index if the anchor isn't centered correctly
3. Set the anchor zone size (default: 2 LEDs)

**Anchor types**

| Type | Description |
|------|-------------|
| Peak | Apex of a gable or roof |
| Corner | Where roofline changes direction |
| Boundary | Start/end of a segment |
| Center | Middle of a segment |
| Custom | User-defined special point |

#### 3d. Review and save

Before saving, verify:

- Total LED count matches the physical installation
- All segments add up to the total
- Segment order follows the physical wiring
- Peaks and corners are marked correctly
- Directions are accurate for each segment
- Anchor points are positioned correctly

Tap **Save Configuration**.

#### 3e. Test the configuration

After saving:

- Turn lights on/off
- Test a pattern and confirm it displays correctly across segments
- Test brightness control
- Verify chase direction is correct

Tap **Next**.

---

### Step 4: Zone configuration

Choose how the system is organized.

#### Option A: Residential Mode (single property)

Best for single homes with one or more LED runs acting as a unified system.

1. Select **Residential**
2. Choose which controllers to **link together**
3. All linked controllers respond to every command as one system
4. Up to 5 sub-users (family members) can be added later

#### Option B: Commercial Mode (multi-zone)

Best for businesses with independent lighting areas.

1. Select **Commercial**
2. Create zones (e.g., "Storefront", "Patio", "Parking Lot")
3. For each zone:
   - Assign a **primary controller**
   - Optionally add **secondary controllers** (for sync)
   - Enable sync if needed for multi-controller zones
4. Up to 20 sub-users can be added later

Tap **Next**.

---

### Step 5: Customer preferences (the handoff)

This step shapes the customer's first experience. These settings personalize the Autopilot AI and the overall app behavior.

#### Profile type

Confirm **Residential** or **Commercial** (carried from Step 3). For commercial accounts, enter the property manager's email.

#### Favorite sports teams

Select any teams the customer follows. Lumina uses these for automatic game-day lighting.

Available teams include: Chiefs, Royals, Sporting KC, KC Current, Cardinals (STL), Blues (STL), Seahawks, Sounders, Mariners — and many more across the NFL, NBA, WNBA, MLB, NHL, MLS, and NWSL.

#### Favorite holidays

Select holidays the customer wants automated seasonal lighting for:

Christmas, Halloween, 4th of July, New Year's, St. Patrick's Day, Thanksgiving, Easter, Valentine's Day.

#### Lighting style (vibe level)

Use the slider to set the customer's preferred intensity:

| Level | Style |
|-------|-------|
| Low (0.0) | Soft and tasteful — gentle fades, warm whites |
| Medium (0.5) | Balanced — seasonal colors and patterns |
| High (1.0) | Maximum impact — full animations, celebration mode |

#### Auto-Pilot autonomy

How much should the AI manage automatically?

| Level | Behavior |
|-------|----------|
| **Ask Me First** | Passive — always waits for user approval |
| **Smart Suggestions** | Weekly preview, auto-applies if no response in 24 hours |
| **Full Auto-Pilot** | Fully automatic, no approval needed |

#### Simple Mode

Toggle this ON for customers who prefer a simplified interface:

- Large, easy-to-tap buttons
- Only Home and Settings tabs visible
- 3–5 favorite patterns for quick access
- Great for older users or first-time smart-home owners
- Customers can switch to Full Mode anytime in Settings

---

### Step 6: Complete setup

When you tap **Complete Setup**, the app:

1. Creates the customer's Firebase account (email + temporary password)
2. Registers the installation (warranty starts — 5 years)
3. Creates their profile with all preferences
4. Links the selected controllers to their account
5. Increments your installation count
6. Signs you out of the installer session

### The customer credentials screen

A dialog shows the customer's login credentials:

```
SETUP COMPLETE!

CUSTOMER LOGIN CREDENTIALS
----------------------------
Name:               Jane Smith
Email:              jane@email.com
Temporary Password: Xk9mB2nQ

Customer should change their password after first login.
```

**Actions available:**

- **Copy Email** — copies just the email
- **Copy Password** — copies just the password
- **Copy All** — copies everything
- **Done** — finishes setup

<div class="warning">
<strong>Important:</strong> Capture these credentials before tapping <strong>Done</strong>. The temporary password cannot be retrieved later. If it's lost, the customer has to use <strong>Forgot Password</strong> to reset.
</div>

---

## 8. Handing off to the customer

Give them their credentials and walk them through:

1. **Download the Lumina app** from the App Store or Google Play
2. **Open the app** and tap **Sign In**
3. **Enter the email and temporary password** you provided
4. **Change their password** when prompted
5. **Complete the Welcome Wizard** (permissions + white selection)
6. **Dashboard appears** — their system is ready to use

<div class="tip">
<strong>Bridge health check:</strong> On every app launch, Lumina automatically checks the Lumina Bridge (if remote access is configured). The result shows as a small status indicator on the home screen — green means online and reachable, grey means the bridge didn't respond. If a fresh install shows the bridge as unreachable, verify the bridge has power and is connected to the customer's Wi-Fi.
</div>

<div class="tip">
<strong>Pro tip:</strong> Spend 2 minutes walking the customer through the dashboard — toggle a preset, adjust brightness, say "Try asking Lumina to set the lights to warm white." A short live demo dramatically reduces support calls later.
</div>

---

## 9. Configuring remote access

For customers who want to control their lights when they're away, remote access needs to be configured before you leave the job site. It requires a **Lumina Bridge** — a small device that stays plugged in at the customer's home and relays commands from the cloud to the controller.

### Setting up the Lumina Bridge

Before configuring remote access in the app, the bridge itself has to be set up:

1. **Flash the Lumina Bridge firmware** onto the bridge device (see the [ESP32 Bridge Setup Guide](ESP32_Bridge_Setup_Guide.md) for the full walkthrough)
2. **Connect to the bridge's Wi-Fi AP** (`Lumina-XXXX`) from your phone
3. **Walk through the 3-step setup wizard:**
   - **Step 1:** Connect the bridge to the customer's home Wi-Fi
   - **Step 2:** Enter the bridge's cloud credentials (email/password)
   - **Step 3:** Enter the customer's Lumina user ID and controller IP
4. The bridge reboots and begins relaying commands

After setup, verify the bridge at `http://<bridge-ip>/` — all three status indicators (Wi-Fi, authentication, user paired) should show green.

### Configuring remote access in the app

1. Open the **System** tab (gear icon in the bottom navigation)
2. Tap the **Remote Access** tab along the top
3. The tab shows a quick status summary — enabled/disabled, bridge status, home Wi-Fi SSID
4. Tap **Set Up Remote Access** (or **Remote Access Settings** if already enabled) to open the full configuration screen

On the Remote Access settings screen:

- **Enable Remote Access** toggle
- **Home Wi-Fi SSID** — tap **Detect Home Network** while connected to the customer's Wi-Fi
- **Bridge connection** — confirm the Lumina Bridge is online (health indicator should be green)
- **Webhook URL** (if applicable) — for advanced/DIY integrations only

<div class="warning">
<strong>Permissions:</strong> Tapping <strong>Detect Home Network</strong> prompts the customer for <strong>Location permission</strong>. On Android this is required to read the Wi-Fi network name; on iOS it's strongly recommended. If the customer declines, the app shows a friendly message explaining what's needed instead of failing silently. The detected SSID is encrypted before storage — it's never written to Firestore in plain text.
</div>

<div class="tip">
<strong>Tip:</strong> The bridge health check runs automatically on every app launch <strong>only when remote access is enabled</strong>. Customers on local-only Wi-Fi don't incur Firestore traffic from idle health pings. If the bridge shows unreachable during setup, check the bridge dashboard at <code>http://&lt;bridge-ip&gt;/</code>. Power-cycle the bridge and wait 30 seconds before retrying.
</div>

---

## 10. Resuming an incomplete setup

If you exit the wizard before completing, your progress is auto-saved.

Next time you enter Installer Mode:

1. Enter your PIN
2. A dialog appears: **"Resume Previous Setup?"**
3. It shows the customer name, current step, and when it was saved
4. **Resume Setup** continues where you left off
5. **Start Fresh** begins a new installation

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

These records are available to the Nex-Gen LED LLC support team for warranty claims.

---

## 12. Quick reference

### PIN format
`[Dealer Code — 2 digits][Installer Code — 2 digits]`
Example: Dealer 03 + Installer 12 = **0312**

### The six setup steps
1. Customer Information (name, email, address)
2. Controller Setup (discover, select, name, test)
3. Roofline Configuration (segments, anchors, directions)
4. Zone Configuration (residential or commercial)
5. Customer Preferences (teams, holidays, vibe, autonomy)
6. Complete & Hand Off (credentials screen)

### Quick actions

| Action | Where |
|--------|-------|
| Open Staff PIN screen | Login → tap Lumina logo 5 times (within 3 seconds) |
| Enter Sales Mode | Staff PIN → enter Sales PIN |
| View sales jobs | Sales Mode → **My Estimates** |
| Access Dealer Dashboard | Main screen → **Dealer Dashboard** |
| View referral rewards | Dealer Dashboard → **Payouts** tab |
| Use Demo Mode | Login screen → enter demo access code |

### Support
Email: **support@nexgenled.com**

---

## What success looks like

- Customer credentials delivered, first password changed, the Welcome Wizard completed
- Dashboard on the customer's phone shows all controllers online
- A test pattern runs correctly across every segment in the right direction
- Bridge status indicator is green (if remote access was configured)
- Warranty record exists in the system with all controllers and the correct install date
- The customer shows you they can make a change themselves — brightness, preset, or a voice command to Lumina

## If something isn't working

**"My PIN doesn't work."**
1. Confirm your account is **Active** — contact your Nex-Gen admin if unsure.
2. Confirm your dealership is active — a deactivated dealer kills every installer PIN underneath.
3. Check all 4 digits.
4. If you've been locked out after 5 failed attempts, wait 30 seconds or dismiss and reopen the Staff PIN screen.

**"I can't find any controllers during Scan."**
Make sure your phone or tablet is on the **same Wi-Fi network** as the controllers. If the controllers are new and not yet on Wi-Fi, use **Add via BLE** to provision them over Bluetooth first. Also check that they have power and their LEDs indicate a healthy boot.

**"The customer's email is already in use."**
They already have a Lumina account. Don't create a duplicate — email **support@nexgenled.com** and we'll link the existing account to this installation.

**"A pattern ran the wrong direction during the Step 3 test."**
Go back to the roofline config, check the **Direction** field on each segment, and make sure segments are listed in the order LEDs are physically connected starting from LED #1.

**"The bridge shows grey (unreachable) after setup."**
Open the bridge dashboard at `http://<bridge-ip>/`. If Wi-Fi is green but authentication is red, re-enter the bridge's credentials. Power-cycle the bridge and wait 30 seconds before retrying. Confirm the bridge and the controller are on the same Wi-Fi network.

**"I lost the customer's temporary password."**
It can't be retrieved. Walk the customer through **Forgot Password** on the sign-in screen — they'll get a reset email.

For the full troubleshooting reference, see the Lumina Troubleshooting Guide.

### Related guides

- **Sales Mode Guide** — detailed walkthrough for sales field visits
- **Dealer Dashboard Guide** — complete tour of the dashboard
- **Admin Operations Guide** — how the admin system works (for Nex-Gen staff)

---

*Nex-Gen Lumina v2.2 — Dealer & Installer Setup Guide — April 2026*
