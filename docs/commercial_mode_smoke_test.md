# Lumina Commercial Mode — Smoke Test Checklist

Manual verification checklist for the commercial mode feature set.
Run before each release candidate. Owned by Nex-Gen LED LLC engineering.

---

## 1. Single-Location Onboarding (Bar/Nightclub)

- [ ] Launch app with a fresh account (no commercial profile)
- [ ] Navigate to Settings > Switch to Commercial Mode
- [ ] Verify CommercialOnboardingWizard launches
- [ ] **Screen 1 — Business Type**: Select "Bar / Nightclub", tap Next
- [ ] **Screen 2 — Brand Identity**: Add 2 brand colors with names, toggle "Use in designs", tap Next
- [ ] **Screen 3 — Hours of Operation**: Set M-F 16:00-02:00, Sat 14:00-02:00, Sun closed; set pre-open buffer 30 min; tap Next
- [ ] **Screen 4 — Channel Setup**: Assign at least 2 channels (e.g., Interior + Outdoor Facade), tap Next
- [ ] **Screen 5 — Your Teams**: Add at least 1 local team (auto-suggested by geo), tap Next
- [ ] **Screen 6 — Day-Part Config**: Verify auto-generated day-parts (Pre-Open, Happy Hour, Peak, Late Night) match hours; adjust one time, tap Next
- [ ] **Screen 7 — Multi-Location**: Skip (single location), tap Next
- [ ] **Screen 8 — Review & Go Live**: Verify summary matches inputs; confirm Pro Tier banner is visible; tap "Activate Commercial Mode"
- [ ] Verify redirect to CommercialHomeScreen with 4-tab bottom nav (Schedule, Teams, Channels, Profile)
- [ ] Verify `profileType` in Firestore is now `'commercial'`

## 2. Multi-Location Onboarding (Chain)

- [ ] Launch wizard with a user that has `organizationId` set and 3+ `commercial_locations`
- [ ] Complete wizard through Screen 7 — Multi-Location: verify all locations listed
- [ ] On Go Live, verify redirect to CommercialHomeScreen with 5-tab nav (Fleet first)
- [ ] Verify FleetDashboardScreen loads with all locations in list view
- [ ] Switch to Map View — verify all pins appear at correct coordinates
- [ ] Tap a pin — verify bottom sheet shows location name, status, channel summary

## 3. Day-Part Schedule Transitions

- [ ] In CommercialScheduleScreen, create a day-part starting in 2 minutes
- [ ] Wait for the start time to pass
- [ ] Verify the active day-part indicator updates in the timeline
- [ ] Verify the controller receives the assigned design (check the controller HTTP endpoint or logs)

## 4. Smart Fill Gap Coverage

- [ ] Set coverage policy to "Smart Fill" on the schedule
- [ ] Create a gap between two day-parts (no assignment)
- [ ] Verify Smart Fill hatched block appears in the timeline gap
- [ ] Verify the `defaultAmbientDesignId` is pushed to the controller during the gap window

## 5. Daylight Suppression

- [ ] Configure an outdoor channel (e.g., Outdoor Facade) with `daylightSuppression: true`, `daylightMode: softDim`
- [ ] During daylight hours: verify brightness multiplier reduces to ~0.20 (check via controller `/json/state` brightness value)
- [ ] At sunset: verify brightness ramps back to 1.0 over ~10 minutes
- [ ] At sunrise: verify brightness dims to 0.20 over ~10 minutes
- [ ] Configure `daylightMode: hardOff` — verify outdoor channel turns fully off during daylight

## 6. Sports Scoring Alert

- [ ] Configure a team with `alertIntensity: full` and `alertChannelScope: allChannels`
- [ ] Trigger a scoring alert (or mock one via Firestore write)
- [ ] Verify all channels flash the team colors
- [ ] Reconfigure `alertChannelScope: indoorOnly` — verify only indoor channels react
- [ ] Reconfigure `alertChannelScope: selectedChannels` with 1 channel selected — verify only that channel reacts
- [ ] Repeat with a WNBA team and an NWSL team — verify league parity (scoring triggers, no exhaustiveness crashes)

## 7. Game Day Mode Activation

- [ ] Configure a priority-1 team with `gameDayLeadTimeMinutes: 120`
- [ ] Set up a game starting in 1 hour (within lead time)
- [ ] Verify Game Day mode activates: gold border badge in FleetDashboard, sport icon in schedule
- [ ] Verify team colors are pushed to channels per scope config
- [ ] After game ends: verify Game Day mode deactivates and normal schedule resumes
- [ ] Verify Game Day notification fires: "[Team] game today at [time]"

## 8. Corporate Push

- [ ] Log in as CORPORATE_ADMIN user
- [ ] Open FleetDashboardScreen — verify Push FAB is visible
- [ ] Tap Push > Push Schedule
- [ ] Step 1: Select a schedule
- [ ] Step 2: Select "All Locations"
- [ ] Step 3: Select "Locked" with expiry date 7 days from now
- [ ] Step 4: Verify impact summary lists all locations with "Will be locked"
- [ ] Step 5: Confirm push
- [ ] Verify all target locations' `commercial_schedule` docs updated in Firestore
- [ ] Verify `is_locked_by_corporate: true` and `lock_expiry_date` set on each

## 9. Corporate Lock Enforcement

- [ ] Log in as STORE_MANAGER at a locked location
- [ ] Open CommercialScheduleScreen — verify amber lock banner: "This schedule is managed by [Org]"
- [ ] Verify all edit interactions are disabled (tap block shows info only, no edit/delete buttons)
- [ ] Verify Quick Actions panel hides Override/Pause/Copy when locked
- [ ] Log in as CORPORATE_ADMIN — open Manage Locks from overflow menu
- [ ] Verify locked location appears with expiry date
- [ ] Tap Unlock — verify lock removed, store manager can now edit

## 10. Pro Tier Banner

- [ ] **FleetDashboardScreen**: Verify banner appears on first launch only
- [ ] Dismiss banner — reopen screen — verify it does not reappear
- [ ] **ReviewGoLiveScreen**: Verify banner always appears (cannot be dismissed permanently)
- [ ] **BusinessProfileEditScreen**: Verify banner appears for first 3 opens, then auto-hides on 4th

## 11. Mode Switching

- [ ] From CommercialHomeScreen: Navigate to Settings > Switch to Residential Mode
- [ ] Verify app routes to residential dashboard (WledDashboardPage)
- [ ] Verify all residential features work normally (controller control, patterns, schedule)
- [ ] From residential Settings: tap Switch to Commercial Mode
- [ ] Verify app routes back to CommercialHomeScreen
- [ ] Verify commercial schedule and location data are intact (no data loss)
- [ ] Kill app and relaunch — verify mode persists across cold start

## 12. Notification Deep-Links

- [ ] Trigger each commercial notification type and verify tap navigates to `/commercial`:
  - [ ] Controller Offline
  - [ ] Holiday Conflict
  - [ ] Game Day Alert
  - [ ] Corporate Push Received
  - [ ] Lock Expiring

## 13. Error Resilience

- [ ] Disable network — open CommercialHomeScreen — verify graceful loading/error state
- [ ] Disable network — attempt schedule save — verify error snackbar and local state revert
- [ ] Create a location with no channel configs — verify empty state message in timeline
- [ ] Create a location with no business hours — verify "Closed" state on all days

---

**Last updated**: 2026-04-27
**Version**: v2.2.0 Commercial Mode
**Owner**: Nex-Gen LED LLC — engineering
