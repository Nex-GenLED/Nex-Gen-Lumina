---
title: "Nex-Gen Lumina — Dealer & Installer Setup Guide"
subtitle: "How to set up your dealer account and complete customer installations"
author: "Nex-Gen LED"
date: "March 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Nex-Gen Lumina — Dealer & Installer Guide</div>'
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

# Nex-Gen Lumina — Dealer & Installer Setup Guide

Welcome to the Nex-Gen Lumina installation program. This guide walks you through setting up your dealer account, registering your installers, and completing customer installations using the Lumina app's Installer Mode.

---

## 1. Overview

The Lumina installation system uses a two-tier structure:

| Role | Description |
|------|-------------|
| **Dealer** | Your company. Each dealer gets a unique 2-digit code (01--99). |
| **Installer** | A technician under your dealership. Each installer gets a 2-digit code (01--99). |

Every installer receives a **4-digit PIN** combining both codes. For example, if your dealer code is **03** and an installer's code is **12**, their PIN is **0312**.

---

## 2. Getting Your Dealer Account

Dealer accounts are created by the Nex-Gen administrative team.

**What Nex-Gen needs from you:**

- Contact person name
- Company name
- Email address
- Phone number

Once created, you will receive:

- Your **2-digit dealer code** (e.g., `03`)
- Access to the **Admin Portal** for managing your installers

---

## 3. Registering Installers

As a dealer, you can add installers through the Admin Portal in the Lumina app.

### Accessing the Admin Portal

1. Open the Lumina app
2. Navigate to **Installer Mode** (from the login screen or Settings)
3. Tap **Admin Access**
4. Enter the admin PIN provided by Nex-Gen

### Adding a New Installer

1. Tap **Manage Installers**
2. Tap **Add Installer**
3. Enter the installer's information:
   - Full name
   - Email address
   - Phone number
4. The system auto-assigns the next available installer code
5. Tap **Save**

The installer's 4-digit PIN is generated automatically and displayed on screen.

<div class="tip">
<strong>Tip:</strong> Share the PIN securely with your installer. They will need it every time they enter Installer Mode on a job site.
</div>

### Managing Installers

From the Admin Portal you can:

- **Deactivate** an installer (blocks their PIN immediately)
- **View statistics** (total installations per installer)
- **Edit** contact details

<div class="warning">
<strong>Important:</strong> If your dealer account is deactivated, all installers under your account are automatically locked out.
</div>

---

## 4. Installer Mode --- Step by Step

Installer Mode is a guided 5-step wizard that sets up a customer's Lumina system and creates their user account.

### Entering Installer Mode

1. Open the Lumina app
2. Tap **Installer Mode** on the main screen
3. Read the overview screen, then tap **Continue**
4. Enter your **4-digit PIN** on the numeric keypad
5. The PIN auto-submits when all 4 digits are entered

<div class="warning">
<strong>Security:</strong> You are locked out after 5 failed PIN attempts. Contact your dealer admin if locked out.
</div>

### Session Rules

- Your session lasts **30 minutes** of inactivity
- A warning appears **5 minutes** before timeout
- You can **extend the session** from the warning dialog
- If the session expires, your progress is **auto-saved** and can be resumed later

---

### Step 1: Customer Information

Enter the homeowner's details:

| Field | Required | Notes |
|-------|----------|-------|
| Full Name | Yes | Customer's name |
| Email | Yes | Must be unique --- this becomes their login |
| Phone | No | For contact purposes |
| Address | No | Street address |
| City | No | |
| State | No | |
| ZIP Code | No | |
| Notes | No | Any special instructions |

<div class="tip">
<strong>Tip:</strong> The email address is checked for uniqueness in real-time. If the customer already has a Lumina account, you'll see an error --- contact Nex-Gen support to link existing accounts.
</div>

Tap **Next** to proceed.

---

### Step 2: Controller Setup

This step connects the physical WLED controllers you've installed.

**2a. Discover Controllers**

- Make sure your phone/tablet is on the **same WiFi network** as the controllers
- Tap **Scan for Controllers** --- the app uses mDNS to find WLED devices
- Available controllers appear in a list with their IP addresses

**2b. Select Controllers**

- Check the box next to each controller that belongs to this installation
- At least one controller must be selected

**2c. Name Each Controller**

- Tap the name field next to each controller
- Give descriptive names (e.g., "Front Roofline", "Garage Accent", "Side Fascia")

**2d. Test Connectivity**

- Tap the **Test** button next to each controller
- A green checkmark confirms the controller is responding
- A red X means the controller is unreachable --- check power and WiFi

**2e. Add New Controllers via Bluetooth** (optional)

- If a controller hasn't been configured for WiFi yet, tap **Add via BLE**
- This launches the Bluetooth provisioning wizard
- Walk through WiFi credential entry on the controller

**2f. Installation Photo** (optional)

- Tap **Capture Photo** to photograph the completed installation
- This photo is stored with the installation record for reference

Tap **Next** to proceed.

---

### Step 3: Zone Configuration

Choose how the system is organized:

#### Option A: Residential Mode (Single Property)

Best for: Single homes with one or more LED runs acting as a unified system.

1. Select **Residential**
2. Choose which controllers to **link together**
3. All linked controllers respond to every command as one system
4. Maximum 5 sub-users (family members) can be added later

#### Option B: Commercial Mode (Multi-Zone)

Best for: Businesses with independent lighting areas.

1. Select **Commercial**
2. Create zones (e.g., "Storefront", "Patio", "Parking Lot")
3. For each zone:
   - Assign a **primary controller**
   - Optionally add **secondary controllers** (for DDP/UDP sync)
   - Enable DDP sync if needed for multi-controller zones
4. Maximum 20 sub-users can be added later

Tap **Next** to proceed.

---

### Step 4: Customer Preferences (Handoff)

This step configures the customer's initial experience. These settings personalize the Autopilot AI and overall app behavior.

#### Profile Type

Confirm **Residential** or **Commercial** (carried from Step 3).
For commercial accounts, enter the property manager's email.

#### Favorite Sports Teams

Select any teams the customer follows. Lumina uses these for automatic game-day lighting.

Available teams include: Chiefs, Royals, Sporting KC, KC Current, Cardinals (STL), Blues (STL), Seahawks, Sounders, Mariners, and more.

#### Favorite Holidays

Select holidays the customer wants automated seasonal lighting for:

Christmas, Halloween, 4th of July, New Year's, St. Patrick's Day, Thanksgiving, Easter, Valentine's Day

#### Lighting Style (Vibe Level)

Use the slider to set the customer's preferred intensity:

| Level | Style |
|-------|-------|
| Low (0.0) | Soft and tasteful --- gentle fades, warm whites |
| Medium (0.5) | Balanced --- seasonal colors and patterns |
| High (1.0) | Maximum impact --- full animations, celebration mode |

#### Auto-Pilot Autonomy

How much should the AI manage automatically?

| Level | Behavior |
|-------|----------|
| **Ask Me First** | Passive --- always waits for user approval |
| **Smart Suggestions** | Shows weekly preview, auto-applies if no response in 24 hours |
| **Full Auto-Pilot** | Fully automatic, no approval needed |

#### Simple Mode

Toggle this ON for customers who prefer a simplified interface:

- Large, easy-to-tap buttons
- Only Home and Settings tabs visible
- 3--5 favorite patterns for quick access
- Great for older users or first-time smart home owners
- Customers can switch to Full Mode anytime in Settings

---

### Step 5: Complete Setup

When you tap **Complete Setup**, the app:

1. Creates the customer's Firebase account (email + temporary password)
2. Registers the installation in the system (warranty starts: 5 years)
3. Creates the user profile with all preferences
4. Links the selected controllers to their account
5. Increments your installation count
6. Signs you out of the installer session

### Customer Credentials Screen

A dialog displays the customer's login credentials:

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

- **Copy Email** --- copies just the email
- **Copy Password** --- copies just the password
- **Copy All** --- copies everything
- **Done** --- finishes the setup

<div class="warning">
<strong>Important:</strong> Write down or copy these credentials before tapping Done. The temporary password cannot be retrieved later. If lost, the customer must use "Forgot Password" to reset.
</div>

---

## 5. Handing Off to the Customer

Give the customer their credentials and walk them through:

1. **Download the Lumina app** from the App Store or Google Play
2. **Open the app** and tap **Sign In**
3. **Enter the email and temporary password** you provided
4. **Change their password** when prompted
5. **Complete the Welcome Wizard** (permissions + white selection)
6. **Dashboard appears** --- their system is ready to use

<div class="tip">
<strong>Bridge Health Check:</strong> When the customer first opens the app (and on every subsequent launch), Lumina automatically runs a bridge health check. The app pings the ESP32 bridge via Firestore and waits for an acknowledgment. The result appears as a status indicator on the home screen --- a green icon means the bridge is online and reachable, while a grey icon means the bridge did not respond. If the bridge shows as unreachable after a fresh install, verify that the bridge is powered on and connected to the customer's WiFi network.
</div>

<div class="tip">
<strong>Pro Tip:</strong> Take 2 minutes to show the customer the dashboard. Toggle a preset, adjust brightness, and say "Try asking Lumina to set the lights to warm white." This builds confidence and reduces support calls.
</div>

---

## 6. Configuring Remote Access

For customers who want to control their lights away from home, Remote Access must be configured before you leave the job site. This requires a **Lumina Bridge** --- a small ESP32 device that stays plugged in at the customer's home and relays commands from the cloud to the WLED controller.

### Setting Up the Lumina Bridge

Before configuring remote access in the app, the bridge device itself must be set up:

1. **Flash the Lumina Bridge firmware** onto an ESP32 using PlatformIO (see the [ESP32 Bridge Setup Guide](ESP32_Bridge_Setup_Guide.md) for detailed instructions)
2. **Connect to the bridge's WiFi AP** (`Lumina-XXXX`) from your phone
3. **Walk through the 3-step setup wizard:**
   - **Step 1:** Connect the bridge to the customer's home WiFi
   - **Step 2:** Enter the bridge's Firebase credentials (email/password)
   - **Step 3:** Enter the customer's Lumina user ID and WLED controller IP
4. The bridge reboots and begins polling Firestore for commands

After setup, you can verify the bridge is working by opening `http://<bridge-ip>/` in a browser to see the bridge dashboard. All three status indicators (WiFi, Firebase Auth, User Paired) should show green.

### Configuring Remote Access in the App

1. Open the **System** tab (gear icon in the bottom navigation)
2. Tap the **Remote Access** tab along the top
3. The tab shows a quick status summary (enabled/disabled, bridge status, home WiFi SSID)
4. Tap the **Set Up Remote Access** button (or **Remote Access Settings** if already enabled) to open the full configuration screen

On the Remote Access settings screen:

- **Enable Remote Access** toggle
- **Home WiFi SSID** --- tap **Detect Home Network** while connected to the customer's WiFi (used to detect whether the customer is home or away)
- **Bridge connection** --- confirm the Lumina Bridge is online (the bridge health indicator should show green)
- **Webhook URL** (if applicable) --- for advanced/DIY integrations only

<div class="tip">
<strong>Tip:</strong> The bridge health check runs automatically on every app launch. If the bridge shows as unreachable during setup, check the bridge dashboard at <code>http://&lt;bridge-ip&gt;/</code> to diagnose the issue. Power-cycle the ESP32 and wait 30 seconds before retrying.
</div>

---

## 7. Resuming an Incomplete Setup

If you exit the wizard before completing, your progress is saved automatically.

Next time you enter Installer Mode:

1. Enter your PIN
2. A dialog appears: **"Resume Previous Setup?"**
3. Shows the customer name, current step, and when it was saved
4. Choose **Resume Setup** to continue where you left off
5. Or **Start Fresh** to begin a new installation

---

## 8. Warranty & Installation Records

Each completed installation automatically creates a warranty record:

| Field | Value |
|-------|-------|
| **Warranty Start** | Date of installation |
| **Warranty Duration** | 5 years |
| **Installer** | Your name and PIN |
| **Dealer** | Your company name and code |
| **Controllers** | Serial numbers of all installed devices |
| **Address** | Customer's installation address |

These records are accessible to the Nex-Gen support team for warranty claims.

---

## 9. Quick Reference

### PIN Format
`[Dealer Code (2 digits)][Installer Code (2 digits)]`
Example: Dealer 03 + Installer 12 = **0312**

### Setup Steps
1. Customer Information (name, email, address)
2. Controller Setup (discover, select, name, test)
3. Zone Configuration (residential or commercial)
4. Customer Preferences (teams, holidays, vibe, autonomy)
5. Complete & Hand Off (credentials screen)

### Support
Email: support@nexgenled.com

---

For troubleshooting, see the separate **Lumina Troubleshooting Guide**.

---

*Nex-Gen Lumina v2.1 --- Dealer & Installer Guide --- March 2026*
