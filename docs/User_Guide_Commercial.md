---
title: "Nex-Gen Lumina — Commercial User Guide"
subtitle: "Multi-zone lighting control for business owners and property managers"
author: "Nex-Gen LED"
date: "April 2026"
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

## 2. Commercial Onboarding Wizard

When your account is first set up (or when adding a new location), you go through an 8-step commercial onboarding wizard that tailors the app to your business.

### Step 1: Business Type

Select your business type (retail, restaurant, bar, office, hotel, mixed-use, etc.). This tailors the default settings and day part suggestions to match your industry.

### Step 2: Brand Identity

Set up your brand colors and visual identity. These colors are available as quick presets throughout the app and can be pushed to all locations.

### Step 3: Hours of Operation

Define your business hours for each day of the week. These are used to automatically create default schedules and determine when lights should be active.

### Step 4: Channel Setup

Configure your lighting channels. Commercial properties typically have multiple channels:

| Channel Role | Example Use |
|-------------|-------------|
| Interior | Indoor ambient lighting |
| Outdoor Facade | Building exterior |
| Window Display | Storefront windows |
| Patio | Outdoor dining/seating area |
| Canopy | Covered outdoor structures |
| Signage/Accent | Signs and architectural accents |

Each channel has a **Coverage Policy** (Always On, Smart Fill, Scheduled Only) and a **Daylight Mode** (Soft Dim, Hard Off, Disabled).

### Step 5: Your Teams

Set up team members and assign roles. See **Roles and Permissions** (Section 12) for details on the four-tier role system.

### Step 6: Day Part Configuration

Configure day parts to automate lighting transitions throughout the day:

| Day Part | Typical Hours | Example Use |
|----------|--------------|-------------|
| Morning/Open | 6 AM -- 11 AM | Bright, welcoming lighting |
| Midday | 11 AM -- 2 PM | Full brightness, natural feel |
| Afternoon | 2 PM -- 5 PM | Maintain visibility |
| Evening/Dinner | 5 PM -- 9 PM | Warm, ambient mood |
| Late Night/Close | 9 PM -- Close | Dimmed, wind-down |

Day parts automatically transition lighting without manual intervention. You can adjust these at any time after setup.

### Step 7: Multi-Location Setup

If you manage multiple locations, add them here. Each location gets its own schedule, controllers, and team assignments. Single-location businesses can skip this step.

### Step 8: Review and Go Live

Final review of all settings. Tap **Go Live** to activate your commercial lighting system. Everything can be adjusted later from the System tab.

<div class="tip">
<strong>Tip:</strong> You can re-run parts of the onboarding wizard at any time from System -- Settings if you need to reconfigure your business type, channels, or day parts.
</div>

---

## 3. Dashboard Overview

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

## 4. Navigation

The app has 5 tabs along the bottom:

| Tab | Icon | Purpose |
|-----|------|---------|
| **Home** | House | Main dashboard with zone overview and master controls |
| **Schedule** | Calendar | View and edit lighting schedules per zone |
| **Lumina** | Center star | AI assistant -- type or speak lighting commands |
| **Explore** | Compass | Browse the pattern library and apply to zones |
| **System** | Gear | Settings, user management, remote access |

---

## 5. Zone Control

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

## 6. Lumina AI Assistant

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

## 7. Scheduling

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

### Day Part Automation

Day parts automate lighting transitions throughout the business day without manual intervention. Unlike individual schedules, day parts define a continuous program that covers the entire day.

**How to configure:**

1. Go to **System** tab, then **Settings** -- **Day Parts** (or configure during onboarding Step 6)
2. Define time ranges for each day part
3. Assign a lighting preset to each day part
4. Day parts apply automatically every day

**Example restaurant setup:**

| Day Part | Time | Lighting |
|----------|------|----------|
| Breakfast | 6:00 AM -- 11:00 AM | Bright white, full brightness |
| Lunch | 11:00 AM -- 2:00 PM | Warm white, 80% brightness |
| Afternoon | 2:00 PM -- 5:00 PM | Warm white, 70% brightness |
| Dinner | 5:00 PM -- 9:00 PM | Amber accent, 60% brightness |
| Close | 9:00 PM -- 10:00 PM | Dim warm, 30% brightness |
| Overnight | 10:00 PM -- 6:00 AM | Security lights only |

Day parts coexist with manual schedules. Manual overrides take priority, and the next day part resumes the automatic program.

<div class="tip">
<strong>Tip:</strong> Day parts are ideal for businesses with consistent daily routines. Combine them with seasonal schedules for holidays and special events -- the manual schedule takes precedence during the event, and day parts resume afterward.
</div>

---

## 8. Explore -- The Pattern Library

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

## 9. White Presets

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

## 10. My Properties

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

## 11. Remote Access

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

## 12. Roles and Permissions

Commercial accounts use a 4-tier role system to control access across your organization.

### Role Overview

| Role | Description |
|------|------------|
| **Store Staff** | View-only access to their assigned location |
| **Store Manager** | Full control of their location -- schedules, overrides, and patterns |
| **Regional Manager** | Manage multiple locations, push settings to a region, manage users |
| **Corporate Admin** | Full access to everything -- brand colors, corporate lock, push to all locations |

### Permission Matrix

| Permission | Store Staff | Store Manager | Regional Manager | Corporate Admin |
|-----------|:-----------:|:-------------:|:-----------------:|:---------------:|
| View own location | Yes | Yes | Yes | Yes |
| Edit schedules | -- | Yes | Yes | Yes |
| Override now (manual control) | -- | Yes | Yes | Yes |
| View all locations | -- | -- | Yes | Yes |
| Push to region | -- | -- | Yes | Yes |
| Push to all locations | -- | -- | -- | Yes |
| Apply corporate lock | -- | -- | -- | Yes |
| Manage users | -- | -- | Yes | Yes |
| Edit brand colors | -- | -- | -- | Yes |

### Corporate Lock

When a Corporate Admin applies a lock, local managers cannot override the schedule during the locked period. This is commonly used for brand-wide promotions, holidays, or corporate events.

To apply a corporate lock:

1. Go to **System** tab, then **Corporate Lock**
2. Select the schedule or pattern to lock
3. Set the lock period (start and end date/time)
4. Tap **Apply Lock**
5. All affected locations receive a notification

### Inviting a User

1. Go to **System** tab, then **Manage Users**
2. Tap **Invite User**
3. Enter the person's email address
4. Select their **role** (Store Staff, Store Manager, Regional Manager, or Corporate Admin)
5. If applicable, assign them to specific **locations** or **regions**
6. They receive an invitation to download the Lumina app and create their account
7. Once they accept, they appear in your user list with their assigned role

### Removing a User

1. Go to **System** tab, then **Manage Users**
2. Tap the user you want to remove
3. Tap **Remove User**
4. Their access is revoked immediately

<div class="tip">
<strong>Tip:</strong> Assign the Store Manager role to shift managers or trusted staff so they can adjust lighting as needed without requiring your direct involvement. Use Store Staff for employees who only need to view the system status.
</div>

---

## 13. Fleet Dashboard -- Multi-Location Management

If you manage multiple locations, the Fleet Dashboard gives you a bird's-eye view of your entire operation.

### Accessing the Fleet Dashboard

- If your account has multiple locations, the app automatically loads the Fleet Dashboard
- For single-location accounts, you see the standard dashboard
- You can switch between the Fleet Dashboard and an individual location dashboard at any time

### Fleet Dashboard Features

- **Map View:** See all locations on a map with status indicators (green = online, red = offline)
- **List View:** Scrollable list of all locations with current status, pattern, and brightness
- **Filtering:** Filter locations by region, status, or custom tags
- **Bulk Actions:** Push a pattern, schedule, or setting to multiple locations at once
- **Quick Status:** See at a glance which locations need attention

Tap any location to drill into its individual dashboard for detailed control.

<div class="tip">
<strong>Tip:</strong> Use the Fleet Dashboard's filtering to quickly identify locations that are offline or running unexpected patterns. This is especially useful for Regional Managers overseeing many sites.
</div>

---

## 14. Brand Identity and Corporate Push

Corporate Admins can enforce brand consistency across all locations.

### Setting Brand Colors

1. Go to **System** tab, then **Settings** -- **Brand Identity** (or configure during onboarding Step 2)
2. Define your primary and secondary brand colors
3. These appear as quick presets on every location's dashboard
4. Tap **Save** to apply

### Pushing to Locations

- **Push to Region:** Regional Managers can push a schedule or pattern to all locations in their region
- **Push to All:** Corporate Admins can push to every location company-wide
- Pushed settings override local schedules until the push expires or is removed

To push a setting:

1. Select the pattern, schedule, or setting you want to push
2. Tap **Push to...** and choose **Region** or **All Locations**
3. Optionally set an **expiration date** for the push
4. Confirm the push -- all affected locations receive a notification

### Business Profile

1. Go to **System** tab, then **Settings** -- **Business Profile**
2. Edit your business name, logo, and contact information
3. These details appear on reports and notifications

<div class="warning">
<strong>Note:</strong> Pushing to all locations overrides any local schedule changes. Communicate with your location managers before applying a company-wide push.
</div>

---

## 15. Commercial Notifications

The app sends relevant notifications for commercial operations:

| Notification | When |
|-------------|------|
| **Controller Offline** | A controller at one of your locations stops responding |
| **Holiday Schedule Conflict** | An upcoming holiday may affect your lighting schedule |
| **Game Day Alert** | A followed team is playing -- Game Day mode is available |
| **Corporate Push Received** | Your organization has updated your schedule |
| **Lock Expiring** | A corporate schedule lock expires within 24 hours |

Notifications can be configured in **System** -- **Settings**. You can enable or disable individual notification types and choose whether to receive them as push notifications, in-app alerts, or both.

<div class="tip">
<strong>Tip:</strong> Enable Controller Offline notifications so you are alerted immediately if a location loses connectivity. This helps you address issues before they impact your business.
</div>

---

## 16. Connection Status

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

## 17. Quick Reference Card

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
| Access Fleet Dashboard | Automatic for multi-location accounts, or tap **Fleet** on the dashboard |
| Configure day parts | System -- Settings -- Day Parts |
| Set brand colors | System -- Settings -- Brand Identity |
| Apply corporate lock | System -- Corporate Lock -- select schedule -- Apply Lock |
| Push to all locations | Select pattern or schedule -- Push to... -- All Locations |
| View role permissions | System -- Manage Users -- tap a user to see their role |

---

## Need Help?

- **In-app:** Ask Lumina -- "Help" or "How do I..."
- **Email:** support@nexgenled.com
- **Your installer:** Contact the dealer who installed your system

For troubleshooting, see the separate Lumina Troubleshooting Guide.

---

*Nex-Gen Lumina v2.1 -- Commercial User Guide -- April 2026*
