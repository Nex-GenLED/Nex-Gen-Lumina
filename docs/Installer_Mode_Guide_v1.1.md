# Nex-Gen Lumina: Installer Mode Guide

**For Certified Nex-Gen LED Installers**
**Version 1.1**

---

## Overview

Installer Mode enables certified technicians to onboard new customers and configure Nex-Gen LED lighting systems during installation appointments.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [PIN Format](#2-pin-format)
3. [Customer Information Entry](#3-customer-information-entry)
4. [Controller Setup (Critical)](#4-controller-setup-critical)
5. [Roofline Configuration Wizard (Critical)](#5-roofline-configuration-wizard-critical)
6. [Handoff & Completion](#6-handoff--completion)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Getting Started

1. Open the Lumina app
2. On the Link Account screen, tap **"Installer"** under Professional Access
3. Review the Installer Mode information screen
4. Tap **"Enter Installer PIN"**
5. Enter your 4-digit PIN
6. Begin the customer setup wizard

---

## 2. PIN Format

Your 4-digit Installer PIN consists of two parts:

| Digits | Description | Example |
|--------|-------------|---------|
| First 2 | Dealer Code | 12 |
| Last 2 | Installer Code | 05 |

**Example:** PIN `1205` = Dealer 12, Installer 05

Your PIN was assigned by your dealer administrator.

---

## 3. Customer Information Entry

Collect and enter the following:

- Customer full name
- Email address (this becomes their login username)
- Phone number
- Installation address (street, city, state, zip)
- Site type: **Residential** (5 sub-users max) or **Commercial** (20 sub-users max)

---

## 4. Controller Setup (Critical)

> ⚠️ **WARNING:** This step MUST be completed correctly or the customer's system will not function properly.

### Prerequisites

- Controller must be powered ON
- Controller must be in pairing mode (typically flashing blue)
- Installer must be within 10 feet of the controller
- Bluetooth and Location permissions must be granted

### Step 4.1: Start BLE Scanning

1. Tap **"Start Scanning"** to begin Bluetooth scan
2. Wait for controllers to appear in the list (up to 8 seconds)
3. Controllers appear as "Nex-Gen Controller" with a device ID

### Step 4.2: Connect to Controller

1. Tap **"Connect"** on the discovered controller
2. Wait for connection to establish (may take 5-10 seconds)
3. Connection confirmed when Wi-Fi setup screen appears

### Step 4.3: Wi-Fi Configuration

1. When prompted "Use your current Wi-Fi network?":
   - Tap **"Use This Network"** if on customer's Wi-Fi
   - Tap **"Enter Manually"** to type SSID and password

2. Enter customer's Wi-Fi credentials:
   - **SSID:** The network name (case-sensitive)
   - **Password:** The Wi-Fi password (case-sensitive)

3. Tap **"Connect & Finish Setup"**

4. Wait for confirmation:
   - "Connected to Wi-Fi" message appears
   - IP address is displayed (e.g., 192.168.1.123)
   - Controller LED turns solid (no longer flashing)

### Controller Setup Verification

- ✓ Controller shows solid light (not flashing)
- ✓ IP address displayed in app
- ✓ Controller responds to test commands
- ✓ Controller appears in customer's device list

### Common Wi-Fi Issues

| Issue | Solution |
|-------|----------|
| Wrong password | Double-check with customer, watch for caps |
| 5GHz network | Controller only supports 2.4GHz Wi-Fi |
| Hidden network | Enter SSID exactly as configured in router |
| Signal strength | Move controller closer to router if weak |

---

## 5. Roofline Configuration Wizard (Critical)

> ⚠️ **WARNING:** Incorrect roofline configuration will cause:
> - Patterns not displaying correctly
> - Colors appearing on wrong sections
> - Chase effects running wrong direction
> - AI recommendations failing
> - Anchor point lighting broken

The Roofline Wizard has 5 steps. **Complete ALL steps accurately.**

---

### Step 5.1: Welcome & Overview

Review the overview and tap **"Next"** to begin.

---

### Step 5.2: LED Count & Controller Info

#### A) Select Active Channels

Controllers support up to 8 output channels. Select which are in use.
Most residential installs use **Channel 1 only**.

#### B) Enter Total LED Count

Enter the **EXACT** total number of LEDs installed (1-2600).

> ⚠️ This number MUST match the physical LED count exactly. Count LEDs at junction boxes if unsure.

#### C) Controller Location

Describe where the controller is mounted:
- "Garage attic"
- "Basement utility room"
- "Behind soffit near front door"

#### D) LED Start Location (LED #1)

Describe where the FIRST LED (LED #1) is physically located:
- "Front left corner of house"
- "Above garage door, left side"
- "Southeast corner at roofline"

#### E) LED Direction

Select the overall direction LEDs were installed:
- Left to Right
- Right to Left
- Clockwise
- Counter-clockwise

#### F) LED End Location

Describe where the LAST LED is located:
- "Front right corner, returning to start"
- "Back of house, near patio"

#### G) Architecture Type

Select the roof style that best matches:

| Type | Description |
|------|-------------|
| Ranch | Flat or minimal peaks |
| Gabled | Single peak/gable |
| Multi-Gabled | Multiple peaks |
| Complex | Mixed features, dormers, valleys |
| Modern | Contemporary, unique shapes |
| Colonial | Traditional with dormers |

---

### Step 5.3: Segment Definition (MOST CRITICAL)

> ⚠️ **THIS IS THE MOST IMPORTANT STEP. TAKE YOUR TIME.**

Segments divide the roofline into logical sections.

#### Segment Types

| Type | Use For |
|------|---------|
| **Run** | Straight horizontal/diagonal section |
| **Corner** | 90° corner where roofline changes direction |
| **Peak** | Roof apex/gable point |
| **Column** | Vertical pillar or post |
| **Connector** | Transition between sections |

#### For Each Segment, Enter:

1. **NAME:** Descriptive name (e.g., "Front Left Eave", "Main Peak")

2. **LED COUNT:** Exact number of LEDs in this segment
   > ⚠️ All segment LED counts must add up to TOTAL LED COUNT

3. **TYPE:** Select from table above

4. **DIRECTION:** Which way LEDs flow in this segment
   - Left to Right
   - Right to Left
   - Upward
   - Downward

5. **LOCATION:** Where on the house
   - Front
   - Back
   - Left Side
   - Right Side

6. **IS PROMINENT:** Check if this is a focal point (peaks, front sections)

#### Segment Order

Segments **MUST** be added in the order LEDs are physically connected.
Starting from LED #1, work your way to the last LED.

#### Example Roofline (200 LEDs total)

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

**TOTAL:** 45+8+35+6+35+8+45+18 = **200** ✓

---

### Step 5.4: Anchor Point Identification

Anchor points are special LEDs where accent effects focus (peaks, corners).

The system uses these for:
- "Light up the peaks" voice commands
- Corner accent patterns
- Chase animation reversal points

#### For Each Segment:

1. Review auto-detected anchor points
2. Adjust LED index if anchor is not centered correctly
3. Set anchor zone size (default: 2 LEDs)

#### Anchor Types

| Type | Description |
|------|-------------|
| Peak | Apex of a gable/roof |
| Corner | Where roofline changes direction |
| Boundary | Start/end of a segment |
| Center | Middle of a segment |
| Custom | User-defined special point |

---

### Step 5.5: Review & Save

Before saving, verify:

- ✓ Total LED count matches physical installation
- ✓ All segments add up to total LED count
- ✓ Segment order follows physical LED wiring
- ✓ Peaks and corners are marked correctly
- ✓ Directions are accurate for each segment
- ✓ Anchor points are positioned correctly

Tap **"Save Configuration"** to complete.

---

## 6. Handoff & Completion

After roofline setup:

### Test the System

- Turn lights on/off
- Test a pattern (confirm it displays correctly)
- Test brightness control
- Verify chase direction is correct

### Generate Credentials

- System creates temporary 8-character password
- Customer's email is their username

### Show Handoff Screen

- Display credentials to customer
- Customer can tap to copy password
- Instruct customer to change password on first login

### Complete Installation

- Installation record saved automatically
- 5-year warranty period begins
- Sign out of installer mode

---

## 7. Troubleshooting

### Controller Not Found

- Ensure controller is powered and in pairing mode
- Move closer to controller (within 10 feet)
- Check Bluetooth is enabled on your phone
- Restart controller and try again

### Wi-Fi Connection Fails

- Verify 2.4GHz network (not 5GHz)
- Check password is correct (case-sensitive)
- Ensure router allows new devices
- Try moving controller closer to router

### LED Count Mismatch

- Physically count LEDs at junction points
- Check for dead LEDs that may not be counted
- Verify all LED strips are connected

### Patterns Look Wrong

- Review segment configuration
- Verify LED direction for each segment
- Check segment order matches physical wiring
- Confirm total LED count is accurate

### Anchor Lighting Not Working

- Re-run Step 5.4 (Anchor Point Identification)
- Adjust anchor LED indices
- Ensure peaks/corners are marked as correct type

---

## Contact

**Dealer Support:** Contact your assigned dealer administrator
**Nex-Gen Technical:** support@nexgenled.com
**Emergency Line:** 1-800-NEXGEN-LED

---

*Nex-Gen LED Systems - Installer Mode Guide v1.1*
*© 2024 Nex-Gen LED Systems. All rights reserved.*
