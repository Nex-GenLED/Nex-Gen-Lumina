# Nex-Gen Lumina Installer & Media Mode Guide

This guide explains how installers and media professionals can use the Nex-Gen Lumina app to set up customer systems and capture content.

---

## Table of Contents

1. [Installer Mode Overview](#installer-mode-overview)
2. [Entering Installer Mode](#entering-installer-mode)
3. [Customer Setup Wizard](#customer-setup-wizard)
4. [Media Dashboard](#media-dashboard)
5. [Viewing Customer Systems](#viewing-customer-systems)
6. [Troubleshooting](#troubleshooting)

---

## Installer Mode Overview

Installer Mode is a special access level that allows authorized installers to:

- Set up new customer accounts during installation
- Configure WLED controllers on the customer's network
- Access the Media Dashboard to view existing customer systems
- Hand off a fully configured system to the customer

### Who Can Access Installer Mode?

Only registered installers with a valid 4-digit PIN can access Installer Mode. PINs are assigned by your dealer administrator.

**PIN Format:** `DDII`
- `DD` = 2-digit dealer code (assigned to your company)
- `II` = 2-digit installer code (your personal code)

**Example:** If your dealer code is `05` and your installer code is `12`, your PIN is `0512`.

---

## Entering Installer Mode

### Step 1: Access the PIN Entry Screen

1. Open the Nex-Gen Lumina app
2. Navigate to **Settings** (gear icon in bottom navigation)
3. Scroll down to find **Installer Mode**
4. Tap to open the PIN entry screen

### Step 2: Enter Your PIN

1. Use the on-screen keypad to enter your 4-digit PIN
2. The PIN auto-submits when all 4 digits are entered
3. If successful, you'll see the Installer Setup Wizard

**Note:** After 5 failed attempts, you'll be temporarily locked out. Contact your dealer administrator if you've forgotten your PIN.

### Step 3: Installer Mode is Now Active

Once authenticated, you'll see:
- Your name and dealer company in the header
- An "INSTALLER" badge showing your active PIN
- Access to the setup wizard and media dashboard

**Session Timeout:** Installer mode automatically ends after 30 minutes of inactivity for security.

---

## Customer Setup Wizard

The setup wizard guides you through configuring a new customer's system.

### Step 1: Customer Information

Enter the customer's details:
- **Name** (required)
- **Email** (required - used for their account)
- **Phone** (optional)
- **Address** (required for service records)
- **City, State, ZIP**
- **Notes** (installation notes, special instructions)

Tap **Continue** when complete.

### Step 2: Controller Setup

1. Ensure you're connected to the customer's WiFi network
2. The app will scan for WLED controllers
3. Select each controller to add to the customer's system
4. Name each controller by location (e.g., "Front Roofline", "Garage", "Backyard")

### Step 3: Zone Configuration

For multi-controller installations:
1. Group controllers into zones if needed
2. Set primary/secondary relationships for sync
3. Test zone coordination

### Step 4: Schedule Setup (Optional)

Help the customer set up their initial schedule:
1. Configure daily on/off times
2. Set up sunrise/sunset automation
3. Add holiday presets if desired

### Step 5: Handoff

1. Review all configuration with the customer
2. Have them sign in or create their account
3. Transfer ownership of the system
4. Provide any final instructions

---

## Media Dashboard

The Media Dashboard allows authorized users to search for and view any customer's system for content creation purposes.

### Accessing the Media Dashboard

**From Installer Mode:**
1. Enter Installer Mode with your PIN
2. In the Installer Wizard, tap the **camera icon** in the top-right corner
3. The Media Dashboard opens

**Requirements:**
- Must be in Installer Mode (authenticated with PIN)
- Your account must have media access privileges

### Media Dashboard Features

#### Search Tab

Search for customers by:
- **Email address** - Enter exact email for direct lookup
- **Street address** - Partial match supported (e.g., "123 Oak" finds "123 Oak Street")
- **Customer name** - Partial match supported

**How to Search:**
1. Tap the search bar
2. Enter at least 3 characters
3. Results appear automatically
4. Tap a customer card to view their system

#### Installations Tab

Browse recent installations by your dealer:
- Shows all customers installed by your dealer network
- Sorted by installation date (newest first)
- Displays customer name, address, and install date
- Tap any card to view that system

---

## Viewing Customer Systems

When you select a customer from the Media Dashboard, you enter "View As" mode.

### What You'll See

In View As mode, you see the customer's dashboard exactly as they see it:
- **House Photo** - Their uploaded home photo with roofline overlay
- **Controllers** - All their connected WLED devices
- **Current State** - Brightness, power, active pattern
- **Schedules** - Their automation schedules
- **Design Studio** - Their saved designs

### View As Banner

A cyan banner appears at the top of the screen showing:
- "Viewing customer system: [Customer Name]"
- **Exit** button - Returns to your own account
- **Switch** button - Opens Media Dashboard to select another customer

### What You Can Do in View As Mode

**Allowed:**
- View house photo and roofline configuration
- See current lighting state and patterns
- Browse their schedule and designs
- Control lights (turn on/off, adjust brightness, change patterns)
- Preview patterns on their system

**Not Allowed:**
- Modify their account settings
- Change their profile information
- Delete their data
- Access their payment or subscription info

### Exiting View As Mode

To return to your own account:
1. Tap **Exit** in the cyan banner, OR
2. Tap **Switch** and close the Media Dashboard without selecting a customer

---

## Troubleshooting

### "Invalid PIN" Error

- Verify your dealer code and installer code are correct
- Check with your dealer administrator that your account is active
- Ensure you're entering exactly 4 digits

### "Too Many Attempts" Lockout

- Wait 15 minutes before trying again
- Contact your dealer administrator if the problem persists

### Can't Find Customer in Search

- Verify the email address is spelled correctly
- Try searching by address instead
- The customer may not have completed account setup yet
- Check the Installations tab if they were recently installed

### "No Access" Error in Media Dashboard

- Ensure you're in Installer Mode (check for INSTALLER badge)
- Your account may not have media privileges - contact your administrator

### Customer's System Shows Offline

- The customer's controllers may not be powered on
- They may have changed their WiFi network
- The system works on local network only (remote access requires additional setup)

### View As Mode Not Working

- Ensure the customer has completed their account setup
- Their profile must exist in the system
- Try refreshing by exiting and re-entering View As mode

---

## Quick Reference

| Action | How To |
|--------|--------|
| Enter Installer Mode | Settings > Installer Mode > Enter 4-digit PIN |
| Access Media Dashboard | Installer Wizard > Camera icon (top-right) |
| Search for Customer | Media Dashboard > Type email or address |
| View Customer System | Tap customer card in search results |
| Exit View As Mode | Tap "Exit" in cyan banner |
| Switch Customers | Tap "Switch" in cyan banner |
| Exit Installer Mode | Tap X in Installer Wizard header |

---

## Contact & Support

For PIN issues or access problems, contact your dealer administrator.

For technical issues with the app, contact Nex-Gen support at:
- Email: support@nexgenled.com
- Phone: [Your support number]

---

*Last Updated: January 2026*
