---
title: "Nex-Gen Lumina — Commercial User Guide"
subtitle: "Multi-zone lighting control for business owners and property managers"
author: "Nex-Gen LED"
date: "March 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Nex-Gen Lumina — Commercial User Guide</div>'
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
  code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
</style>

# Nex-Gen Lumina — Commercial User Guide

Welcome to Nex-Gen Lumina for commercial properties. This guide covers everything you need to operate your multi-zone LED lighting system from the Lumina app. Your installer has already configured the hardware and network -- this guide focuses on day-to-day control.

---

## 1. Signing In

Your installer provided you with a Lumina account during system handoff.

1. Open the **Lumina** app on your phone or tablet
2. Tap **Sign In**
3. Enter the **email** and **temporary password** provided by your installer
4. You will be prompted to **create a new password** -- choose something secure
5. After sign-in, the app detects your commercial account and loads the multi-zone dashboard

<div class="tip">
<strong>Tip:</strong> If you did not receive credentials, contact your installer directly. They can generate a new account or resend the invitation.
</div>

---

## 2. Dashboard Overview

The Home Dashboard is your central command for all lighting zones. It provides an at-a-glance view of your entire property.

### Hero Image

The large image at the top shows your property (your installer may have uploaded a photo during setup). You can change this photo later in **System** settings.

### Power Button

The main power button toggles all zones on or off simultaneously. It glows cyan when any zone is currently active.

### Brightness Slider

The vertical brightness slider adjusts the master brightness across all active zones. Changes take effect instantly.

### Quick Presets

Preset buttons along the right side of the hero image provide one-tap access to common settings:

| Preset | What It Does |
|--------|-------------|
| **Run Schedule** | Activates tonight's scheduled pattern for all zones |
| **Warm White** | Applies your primary white across all zones |
| **Bright White** | Applies your complementary white across all zones |
| **Custom Favorites** | Any patterns you have saved |

### Zone Status

Below the hero image, you can see the current status of each zone at a glance -- which zones are on, what pattern is running, and the brightness level for each.

### Tonight Card

Shows what is scheduled for tonight across your zones, with a color preview of the upcoming patterns.

---

## 3. Navigation

The app has 5 tabs along the bottom:

| Tab | Icon | Purpose |
|-----|------|---------|
| **Home** | House | Main dashboard with zone overview and master controls |
| **Schedule** | Calendar | View and edit lighting schedules per zone |
| **Lumina** | Center star | AI assistant -- type or speak lighting commands |
| **Explore** | Compass | Browse the pattern library and apply to zones |
| **System** | Gear | Settings, user management, remote access |

---

## 4. Zone Control

Commercial systems divide your property into independent **zones** -- for example, "Storefront", "Patio", "Parking Lot", or "Building Perimeter". Each zone can be controlled separately or together.

### The Channel Selector Bar

Whenever you are on a screen that applies patterns or adjusts settings, you will see the **Channel Selector Bar** at the top. This is your primary tool for targeting specific zones.

| Selection | Behavior |
|-----------|----------|
| **All** | Commands apply to every zone simultaneously |
| **Individual zone** (e.g., "Storefront") | Commands apply only to that zone |

**How to use it:**

1. Tap a zone name in the Channel Selector Bar to select it
2. The bar highlights the active selection
3. Any brightness change, pattern, or preset you apply now targets only that zone
4. Tap **All** to return to controlling the entire property

### Independent Zone Operation

Each zone operates independently. This means you can:

- Run animated holiday patterns on the storefront while the parking lot stays on steady bright white
- Dim the patio at closing time without affecting the building perimeter
- Schedule different on/off times for each zone based on its purpose

### Multi-Controller Sync

If a zone spans multiple physical controllers (common for large buildings), those controllers stay in sync automatically using DDP/UDP broadcast. No action is needed from you -- your installer configured this during setup, and it operates transparently.

<div class="tip">
<strong>Tip:</strong> If you notice a portion of a zone falling out of sync, contact your installer. This is a hardware configuration matter, not something adjusted from the app.
</div>

---

## 5. Lumina AI Assistant

Lumina is your AI lighting assistant. It understands natural language and is fully zone-aware for commercial properties.

### Accessing Lumina

- **Lumina tab** (center of bottom bar) for full-screen conversation
- **Chat bar** at the bottom of the dashboard for quick commands

### Typing and Voice Commands

Type or tap the **microphone icon** to speak. Lumina automatically submits after a 2-second pause when using voice.

### Zone-Aware Commands

Lumina understands zone references. You can be specific or general:

| Say This | Lumina Does This |
|----------|-----------------|
| "Turn on warm white" | Applies warm white to all zones |
| "Turn on the storefront" | Powers on only the Storefront zone |
| "Set patio to 50% brightness" | Adjusts patio brightness only |
| "Christmas theme on the storefront, bright white on parking lot" | Applies different settings to each zone |
| "Turn off everything except the parking lot" | Selective zone control |
| "Brighten up the patio" | Increases patio brightness |
| "What's running on the storefront?" | Reports current status for that zone |
| "Schedule warm white on the patio at sunset" | Creates a zone-specific schedule |
| "Turn off all lights" | Powers down every zone |

<div class="tip">
<strong>Tip:</strong> Lumina learns your zone names and preferences over time. Use it regularly for the best experience.
</div>

---

## 6. Scheduling

The Schedule tab lets you automate your lighting on a weekly basis. Commercial schedules are typically built around business hours and can be set independently per zone.

### Viewing Your Schedule

1. Tap the **Schedule** tab
2. The week view shows each day with its scheduled patterns
3. Tap a day to see details -- pattern name, times, and which zones are affected
4. Use arrows to navigate between weeks

### Creating a Schedule

1. On the Schedule tab, tap the **+** button
2. Choose:
   - **Zone** -- select which zone this schedule applies to, or **All** for the entire property
   - **Pattern/Scene** -- the lighting to display
   - **Start Time** -- when to turn on (clock time, or Sunrise/Sunset with an offset)
   - **End Time** -- when to turn off (optional)
   - **Repeat Days** -- which days of the week
3. Tap **Save**

Schedules sync directly to the WLED controllers as native timers. They run even when the app is closed and your phone is off-site.

### Business Hours Automation

A typical commercial schedule might look like:

| Zone | Schedule | Days |
|------|----------|------|
| Storefront | Holiday pattern, sunset to 11 PM | Mon--Sun |
| Storefront | Warm white, 5:30 AM to sunrise | Mon--Sat |
| Patio | Warm white, sunset to closing (10 PM) | Mon--Sun |
| Parking Lot | Bright white, sunset to sunrise | Every day |
| Building Perimeter | Bright white, dusk to dawn | Every day |

<div class="tip">
<strong>Tip:</strong> Use sunset/sunrise offsets for schedules that should adapt to the season automatically. For example, "sunset minus 15 minutes" ensures the lights come on just before dark year-round.
</div>

### Auto-Pilot

Lumina's Auto-Pilot can generate weekly schedule suggestions based on upcoming holidays, your preferences, and the time of year. You control the level of automation:

| Mode | Behavior |
|------|----------|
| **Ask Me First** | You approve each weekly plan manually |
| **Smart Suggestions** | Auto-applies after 24 hours if you do not respond |
| **Full Auto-Pilot** | Applies automatically with no approval needed |

You can always override Auto-Pilot by editing any scheduled item manually.

---

## 7. Explore -- The Pattern Library

### Browsing Patterns

1. Tap the **Explore** tab
2. Browse by category:
   - **Holidays** -- Christmas, Halloween, 4th of July, and more
   - **Sports** -- Team colors and game-day themes
   - **Nature** -- Ocean, forest, sunset, aurora
   - **Mood** -- Relaxing, energetic, festive
   - **Seasonal** -- Spring, summer, fall, winter
   - **Whites** -- Various white tones and temperatures
   - **Solid Colors** -- Single-color fills
   - **Animations** -- Moving effects (chase, breathe, rainbow)

### Applying Patterns to Specific Zones

1. Open a pattern from the library
2. Use the **Channel Selector Bar** at the top to choose your target zone (or **All**)
3. Tap the pattern to **preview it live** on the selected zone
4. Tap **Apply** to keep it active
5. Tap the **heart icon** to save it as a favorite for quick access later

### Editing a Pattern

- Tap the **edit icon** on any pattern
- Adjust speed, intensity, brightness, and colors
- Save as a new custom pattern

<div class="tip">
<strong>Tip:</strong> Create a few go-to favorites for your business -- for example, a branded color scheme or a warm white preset at your preferred brightness. These appear on the dashboard for one-tap access.
</div>

---

## 8. White Presets

Your system uses **RGBW LEDs** with a dedicated white channel, producing clean, true whites that standard RGB LEDs cannot match.

### Built-In Presets

| Preset | Description |
|--------|-------------|
| **Warm White** | Cozy, amber-tinted glow |
| **Soft White** | Gentle, slightly warm tone |
| **Natural White** | Balanced, true-to-life white |
| **Cool White** | Clean, blue-tinted white |
| **Bright White** | Pure white from the dedicated W LED |

### Changing Your Defaults

1. Go to **System** tab, then **My Whites**
2. Tap any preset to preview it live
3. Select your **Primary** white (everyday default) and your **Complement** white
4. Tap **Save**

### Custom White

Use the R, G, B, and W sliders to create a custom white tone for your property. The W slider controls the dedicated white LED independently, allowing precise color temperature tuning.

---

## 9. My Properties

Commercial accounts can manage multiple properties (e.g., multiple storefronts, office buildings, or mixed-use sites) from a single Lumina account.

### Accessing My Properties

1. Go to the **System** tab
2. Tap **My Properties**

### Adding a Property

1. Tap the **+** button or **Add Property**
2. Enter a name (e.g., "Downtown Storefront", "Warehouse")
3. Start typing the address --- Google Places will suggest matching addresses as you type. Tap a suggestion to auto-fill, or type the full address manually.
4. Choose an icon that represents the property
5. Tap **Save**

### Linking Controllers to a Property

After creating a property, link the WLED controllers installed at that location:

1. Tap the **Controllers** button on the property card
2. A list of all your registered controllers appears with toggle switches
3. Toggle on each controller that belongs to this property
4. Changes save automatically

### Setting a Primary Property

Set your most-used property as the primary (default) location:

1. Tap **Set Primary** on the property card
2. The primary property loads by default when you open the app

---

## 10. Remote Access

Lumina supports controlling your lights from anywhere -- not just when you are on-site connected to the property WiFi.

### How It Works

Your installer configured an **ESP32 Bridge** device on your property network. This bridge relays commands between the Lumina cloud and your local controllers. When you are on the property WiFi, the app communicates directly with the controllers for instant response. When you are off-site, commands route automatically through the bridge.

You do not need to configure anything. The app detects your network and switches between local and remote modes transparently.

### Verifying Remote Access

1. Go to **System** tab, then **Remote Access**
2. Confirm that **ESP32 Bridge** is shown as the connection mode
3. Confirm the status shows **Connected** or **Bridge Online**
4. You can tap **Test Bridge** at any time to verify

<div class="warning">
<strong>Note:</strong> If the bridge appears offline, ensure the bridge device at your property is powered on and connected to the network. Contact your installer if the issue persists.
</div>

---

## 11. Managing Users

Commercial accounts support up to **20 users**. As the property manager, you control who has access to the lighting system.

### Inviting a User

1. Go to **System** tab, then **Manage Users**
2. Tap **Invite User**
3. Enter the person's email address
4. They receive an invitation to download the Lumina app and create their account
5. Once they accept, they appear in your user list

### User Roles

| Role | Capabilities |
|------|-------------|
| **Property Manager** | Full control -- all zones, scheduling, user management, system settings |
| **Standard User** | Control lights, apply patterns, adjust brightness. Cannot manage other users or modify system settings |

### Removing a User

1. Go to **System** tab, then **Manage Users**
2. Tap the user you want to remove
3. Tap **Remove User**
4. Their access is revoked immediately

<div class="tip">
<strong>Tip:</strong> Invite shift managers or trusted staff so they can adjust lighting as needed without requiring your direct involvement.
</div>

---

## 12. Connection Status

The app displays your connection status so you always know the state of your system.

| Indicator | Meaning |
|-----------|---------|
| **Green dot** | Connected -- controllers responding normally |
| **Bridge icon (green)** | Connected remotely via the ESP32 Bridge |
| **"Reconnecting..."** | Temporary connection loss -- the app is retrying automatically |
| **"System Offline"** | Cannot reach any controller -- check property power and network |

**If you see "System Offline" while on-site:**

1. Confirm your phone or tablet is on the **same WiFi network** as the lighting system
2. Verify the controllers are powered on
3. Close and reopen the app

**If you see "System Offline" while off-site:**

1. The bridge device at the property may be offline -- verify with on-site staff
2. Check that the property has internet connectivity
3. Contact your installer if the issue persists

---

## 13. Quick Reference Card

| Action | How |
|--------|-----|
| Turn all lights on/off | Tap the power button on the dashboard |
| Control a specific zone | Use the Channel Selector Bar -- tap the zone name |
| Control all zones at once | Channel Selector Bar -- tap **All** |
| Change brightness | Slide the brightness control |
| Apply warm white | Tap "Warm White" preset |
| Apply a pattern to a zone | Explore tab -- select zone in Channel Selector -- tap pattern |
| Ask Lumina | Chat bar -- type or tap the microphone |
| Ask Lumina about a zone | "Set storefront to warm white" or "Turn off the patio" |
| View schedule | Schedule tab |
| Add a zone schedule | Schedule tab -- **+** button -- select zone |
| Change white preset | System -- My Whites |
| Check remote access | System -- Remote Access |
| Invite a user | System -- Manage Users -- Invite User |
| Remove a user | System -- Manage Users -- tap user -- Remove |

---

## Need Help?

- **In-app:** Ask Lumina -- "Help" or "How do I..."
- **Email:** support@nexgenled.com
- **Your installer:** Contact the dealer who installed your system

For troubleshooting, see the separate Lumina Troubleshooting Guide.

---

*Nex-Gen Lumina v2.1 -- Commercial User Guide -- March 2026*
