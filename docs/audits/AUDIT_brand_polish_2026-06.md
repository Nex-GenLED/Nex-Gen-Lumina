# AUDIT 6 — Brand & UI Polish Sweep

**Date:** 2026-06-02
**Branch:** submission/app-store-v1
**Scope:** Read-only sweep of the whole app against the Nex-Gen / Lumina brand system.
**Brand system reference:** VOID `#07091A`, LUMINA `#00D4FF`, PULSE `#6E2FFF`, CARBON `#111527`, FROST `#DCF0FF`; Exo 2 headers, DM Sans body; Pulse→Lumina 135° gradient; voice "Beyond the Light." / "The System Is the Difference."

**Method:** Four parallel exploration sweeps (version/placeholder, false-promise copy, terminology/voice, state/brand-token). Flagship findings (version strings, geofence, neighborhood, voice, Ref ID) were **read-verified** against source before publishing — verified line numbers are used below and noted where a sweep's line numbers drifted.

> **No code changed. No commits. This is an inventory only.**

---

## Severity legend

- **TRUST-DAMAGING** — a customer or App Store reviewer would feel actively misled. Fix before review.
- **UNPROFESSIONAL** — visibly breaks the premium positioning (dev-speak, drift, inconsistency). Fix before/soon after launch.
- **COSMETIC** — internal inconsistency, low user visibility. Backlog.

---

## PRIORITY 1 — VERSION / STRING DRIFT (reviewer-visible)

Canonical source of truth is `pubspec.yaml` → **`2.3.0+26`**. Three different version strings ship to users, none of which match it. **VERIFIED.**

| File:line | Literal | Conflict | Severity |
|---|---|---|---|
| [pubspec.yaml:5](pubspec.yaml#L5) | `version: 2.3.0+26` | Canonical — but no UI surface reads it | — |
| [lib/features/auth/login_page.dart:541](lib/features/auth/login_page.dart#L541) | `'v2.2.0'` | Login screen. ✗ vs pubspec `2.3.0` and settings `1.6.0` | **TRUST-DAMAGING** |
| [lib/features/site/settings_page.dart:649](lib/features/site/settings_page.dart#L649) | `'Version 1.6.0'` | Settings "About". ✗ vs pubspec and login | **TRUST-DAMAGING** |
| [lib/features/site/settings_page.dart:650](lib/features/site/settings_page.dart#L650) | `'Build 2026.01'` | Build label. ✗ vs pubspec build `+26` | **UNPROFESSIONAL** |
| [lib/features/site/settings_page.dart:843](lib/features/site/settings_page.dart#L843) | `'© 2026 Nex-Gen Lighting Systems'` | Hardcoded copyright/company; should be single-sourced | **COSMETIC** |

**Fix direction:** Read version from `PackageInfo.fromPlatform()` (package `package_info_plus`) at both surfaces, or expose a single `kAppVersion`/`kBuildLabel` constant generated from pubspec. Delete the three hardcoded strings. This is the single most reviewer-visible inconsistency in the build — a reviewer who sees `v2.2.0` on login and `1.6.0` in settings reads it as an unfinished build.

**Other should-be-single-sourced values (hardcoded in many places):**

- **App name "Lumina"** — [ios/Runner/Info.plist:7-8,15-16](ios/Runner/Info.plist#L7) (`CFBundleDisplayName`, `CFBundleName`) and [android/app/src/main/AndroidManifest.xml:40](android/app/src/main/AndroidManifest.xml#L40) (`android:label`). Acceptable (platform manifests), noted for rebrand awareness.
- **Package id "com.nexgenled.lumina"** — [android/app/build.gradle:48](android/app/build.gradle#L48) duplicated in [AndroidManifest.xml:3](android/app/src/main/AndroidManifest.xml#L3). Manifest should derive from gradle `applicationId`.
- **"Nex-Gen" brand string** hardcoded in 10+ UI strings (e.g. [lib/auth/link_account_screen.dart:9,63,118,143,216,220,222](lib/auth/link_account_screen.dart#L9), [lib/features/audio/audio_mode_page.dart:214](lib/features/audio/audio_mode_page.dart#L214), [lib/features/corporate/providers/corporate_providers.dart:90](lib/features/corporate/providers/corporate_providers.dart#L90)). **COSMETIC** but a rebrand-hostile pattern — centralize into a `Brand` constants class.
- **Support contact** `info@Nex-GenLED.com` / `Nex-GenLED.com` hardcoded in [lib/auth/link_account_screen.dart:220-222](lib/auth/link_account_screen.dart#L220). Centralize.

---

## PRIORITY 2 — FALSE-PROMISE / OVER-PROMISING COPY (trust — highest priority)

Copy that claims capability the implementation does not deliver. On a premium brand these are the most damaging findings in this audit. All six below were spot-checked against the implementing code.

### 2.1 — Geofence: "detected even when the app is closed" — **FALSE. VERIFIED.**
- **Copy:** [lib/features/geofence/geofence_monitor.dart:97-100](lib/features/geofence/geofence_monitor.dart#L97) — *"To trigger 'Welcome Home' reliably, we need background location access so your arrival is detected **even when the app is closed**."*
- **Reality:** `GeofenceMonitor` is a foreground Riverpod `Notifier`. `start()` subscribes to `Geolocator.getPositionStream()` (foreground-only); `_onPosition()` fires only while that stream is live, i.e. while the app process runs. No native geofence registration (iOS `CLLocationManager.startMonitoring(for:)` / Android Geofencing API), no background isolate, no wake-on-location. Closing the app stops detection immediately.
- **Gap:** The copy specifically promises the one thing the implementation cannot do, and the dialog requests "Always Allow" background permission to back the false claim.
- **Severity:** **TRUST-DAMAGING.** Welcome Home is a headline automation.
- **Fix direction:** Either implement native background geofencing, or rewrite to the truth — e.g. *"Welcome Home triggers while Lumina is running in the background. Keep the app active for reliable arrival detection."* Do not request Always-Allow to prop up a claim the code can't honor (also an App Store rejection risk).

### 2.2 — Neighborhood Sync: "Real-Time Sync — Lights move together instantly" — **OVERSTATED. VERIFIED.**
- **Copy:** [lib/features/neighborhood/widgets/neighborhood_onboarding.dart:161-165](lib/features/neighborhood/widgets/neighborhood_onboarding.dart#L161) — feature chip `'Real-Time Sync'` / `'Lights move together instantly'`.
- **Reality:** Command delivery is a Firestore `snapshots()` listener active only while the app is foregrounded (`neighborhood_sync_engine.dart`). Per-home delays are deliberately *calculated* (`calculateMemberDelays`), and off-LAN members route through the bridge relay (~5–10s typical, 30–45s tail per [BRIDGE_LATENCY_AUDIT_2026-05.md](docs/audits/BRIDGE_LATENCY_AUDIT_2026-05.md)). Not "instant," not real-time.
- **Severity:** **TRUST-DAMAGING** (compounds with 2.3 below).
- **Fix direction:** Drop "instantly"/"Real-Time"; say *"Homes light up together, coordinated across the neighborhood."*

### 2.3 — Neighborhood Sync background: "reliable Sync Event triggers when the app is closed" — **UNVERIFIED / iOS-IMPOSSIBLE.**
- **Copy:** [lib/features/neighborhood/widgets/battery_optimization_prompt.dart:76](lib/features/neighborhood/widgets/battery_optimization_prompt.dart#L76) — *"For reliable Sync Event triggers **when the app is closed**, we recommend disabling battery optimization… This keeps the background service running."*
- **Reality:** Background isolate + SharedPreferences scaffolding exists (`sync_event_providers.dart`, `sync_event_background_worker.dart`) but is not verified end-to-end with live command delivery. iOS suspends Firestore listeners shortly after backgrounding regardless of battery settings — the advice cannot work on iOS.
- **Severity:** **TRUST-DAMAGING** on iOS (instructs the user to change a system setting for a benefit they won't receive).
- **Fix direction:** Gate this copy to Android, or qualify platform limits. Don't promise iOS background behavior the OS forbids.

### 2.4 — Voice (Alexa / Google / Siri): presented as connected and working — **NOT VERIFIED END-TO-END.**
- **Copy (VERIFIED, line numbers corrected from sweep):**
  - [lib/features/voice/voice_assistant_guide_screen.dart:87](lib/features/voice/voice_assistant_guide_screen.dart#L87) — `'Control Your Lights with Voice'`
  - [lib/features/voice/voice_assistant_guide_screen.dart:703](lib/features/voice/voice_assistant_guide_screen.dart#L703) — `'Alexa is connected! Your lights and scenes are ready to control.'`
  - [lib/features/voice/voice_assistant_guide_screen.dart:396](lib/features/voice/voice_assistant_guide_screen.dart#L396) — `'Google Home is connected! Control your lights from any Google Assistant device.'`
- **Reality:** CLAUDE.md classifies `lib/features/voice/` as **"ARCHITECTED — not yet verified end-to-end."** Services manage OAuth/link-state, but the voice→WLED command path is unverified. "is connected!" is asserted unconditionally in the guide copy.
- **Severity:** **TRUST-DAMAGING / potential App Store rejection** — marketing an unverified integration as live.
- **Fix direction:** Move to a "Coming Soon" / "Early Access" surface, or only show "connected" when link-state is genuinely verified and gate the success string behind a real handshake. Soften "instantly" — voice commands also traverse the 5–10s bridge.

### 2.5 — Audio Mode: full UI presented as a standard feature — **INTERFACE IN-PROGRESS.**
- **Copy/UI:** [lib/features/audio/audio_mode_page.dart](lib/features/audio/audio_mode_page.dart) — complete functional UI (`_buildSupported`, ~233+); unsupported-state text [lib/features/audio/audio_mode_page.dart:214](lib/features/audio/audio_mode_page.dart#L214) markets a single SKU (`NGL-CTRL-P1`) as the audio-capable hardware.
- **Reality:** CLAUDE.md: audio interface **IN-PROGRESS**; requires AudioReactive usermod + mic that most installed controllers lack. Typical users hit "Not Available" and may think their controller is defective.
- **Severity:** **UNPROFESSIONAL** (borderline trust on the hardware-defect implication).
- **Fix direction:** Add a "Beta" badge; reword the unsupported state so it doesn't imply the user's hardware is broken (*"Audio Mode needs an AudioReactive-equipped controller. Contact your dealer about audio-ready hardware."*).

### 2.6 — Remote Access: "Control your lights from anywhere" with no latency expectation set
- **Copy:** [lib/features/site/remote_access_screen.dart:620-622](lib/features/site/remote_access_screen.dart#L620) — `'Control your lights from anywhere'`.
- **Reality:** True, but silent on the 5–10s typical / 30–45s tail round-trip. First-tap latency reads as "broken" without expectation-setting.
- **Severity:** **UNPROFESSIONAL** (expectation gap, not a false claim).
- **Fix direction:** Add a one-line latency hint near the toggle (*"Remote commands take a few seconds to reach your lights."*).

---

## PRIORITY 3 — PLACEHOLDER / DEBUG / FAKE TEXT VISIBLE TO USERS

| File:line | Literal | Issue | Severity |
|---|---|---|---|
| [lib/features/site/settings_page.dart:441](lib/features/site/settings_page.dart#L441) | `'Success. Ref ID: #8821.'` | **VERIFIED** — hardcoded fake reference ID in a success dialog; no real ID is generated | **TRUST-DAMAGING** |
| [lib/features/voice/google_home_service.dart:32](lib/features/voice/google_home_service.dart#L32) | URL ending `…/000000YOUR_PROJECT_ID` | `YOUR_PROJECT_ID` template token never substituted; breaks the integration if used raw | **TRUST-DAMAGING** (ties to 2.4) |
| [lib/features/design/screens/ai_design_studio_screen.dart:311](lib/features/design/screens/ai_design_studio_screen.dart#L311) | `'Apply to Lights (coming soon)'` | User-facing "coming soon" on a core action; either ship or hide | **UNPROFESSIONAL** |
| [lib/features/game_day/game_day_screen.dart:1321](lib/features/game_day/game_day_screen.dart#L1321) | `hostDisplayName: 'My House'` | Hardcoded default w/ `// TODO: pull from user profile`; surfaces to crew UI | **UNPROFESSIONAL** |
| [lib/features/demo/demo_profile_screen.dart:161](lib/features/demo/demo_profile_screen.dart#L161) | `'(555) 123-4567'` | Placeholder phone hint (demo — lower risk) | **COSMETIC** |
| [lib/features/installer/screens/customer_info_screen.dart:329](lib/features/installer/screens/customer_info_screen.dart#L329) | `'(555) 123-4567'` | Duplicate placeholder phone in real installer form | **COSMETIC** |
| [lib/services/wled_config_pusher.dart:140](lib/services/wled_config_pusher.dart#L140) | `'xxxx'` | MAC-parse fallback; shows "xxxx" in device discovery if MAC malformed | **COSMETIC** |
| [lib/features/autopilot/autopilot_weekly_preview.dart:252](lib/features/autopilot/autopilot_weekly_preview.dart#L252) | `// TODO: Implement schedule approval workflow` | `_approveItem()` is UI-callable but only debug-prints — non-functional action | **UNPROFESSIONAL** |
| [lib/features/autopilot/game_day_autopilot_config.dart:130](lib/features/autopilot/game_day_autopilot_config.dart#L130) | `// TODO(v1.0.1): wire into …` | `motionStyle` stored/shown but not consumed in selection logic | **COSMETIC** |
| [lib/features/installer/screens/controller_setup_screen.dart:538,606](lib/features/installer/screens/controller_setup_screen.dart#L538) | `// TODO: remove after migration…` | Legacy dual-write path still live; data-only | **COSMETIC** |

**Top fixes:** the `Ref ID: #8821` fake (generate a real id or remove the line) and the `YOUR_PROJECT_ID` template token are the two a reviewer could stumble into.

---

## PRIORITY 4 — TERMINOLOGY INCONSISTENCY

The same concept is named differently across screens. Recommended canonical term in **bold**.

### 4.1 Channels vs Zones vs Segments vs Buses vs "Lighting Areas" → **"Lighting Area"** (consumer UI)
The underlying thing is one hardware bus. It is surfaced as all of: "Channel", "Zone", "Segment", "Lighting Areas".
- "Channel": [lib/features/wled/hardware_config_screen.dart:417](lib/features/wled/hardware_config_screen.dart#L417) (`'Channel Configuration'`), [:535](lib/features/wled/hardware_config_screen.dart#L535), [lib/features/wled/zone_providers.dart:90](lib/features/wled/zone_providers.dart#L90), [lib/features/wled/wled_repository.dart:161](lib/features/wled/wled_repository.dart#L161)
- "Zone": [lib/features/installer/screens/zone_configuration_screen.dart](lib/features/installer/screens/zone_configuration_screen.dart) ("Zone Configuration" — **actually a segment editor**), [lib/features/wled/zone_configuration_page.dart:258](lib/features/wled/zone_configuration_page.dart#L258)
- "Segment": [lib/features/design/segment_setup_screen.dart:82](lib/features/design/segment_setup_screen.dart#L82) (`'Roofline Segments'`), [lib/features/design/roofline_setup_wizard.dart:917](lib/features/design/roofline_setup_wizard.dart#L917)
- "Lighting Areas" (the one consumer-friendly label): [lib/features/wled/zone_configuration_page.dart:25](lib/features/wled/zone_configuration_page.dart#L25) (`'My Lighting Areas'`)
- **Recommendation:** UI everywhere → **"Lighting Area"**. Keep "Zone" strictly for commercial-mode `ZoneModel`; keep "Segment"/"Bus" for advanced/technical screens only. Rename "Zone Configuration" (segment editor) → "Lighting Areas". **Severity: UNPROFESSIONAL.**

### 4.2 Designs vs Patterns vs Presets vs Scenes vs Effects vs Themes vs Colorways → see split below
Heavy semantic overlap across the most-used surfaces.
- "Design"/"Design Studio"/"My Designs"/"Design Library": [lib/features/design/screens/ai_design_studio_screen.dart:120](lib/features/design/screens/ai_design_studio_screen.dart#L120), [lib/features/dashboard/wled_dashboard_page.dart:444](lib/features/dashboard/wled_dashboard_page.dart#L444), [lib/features/wled/pattern_theme_selection.dart:269](lib/features/wled/pattern_theme_selection.dart#L269)
- "Pattern": [lib/features/wled/edit_pattern_screen.dart](lib/features/wled/edit_pattern_screen.dart), [lib/features/schedule/schedule_models.dart:22](lib/features/schedule/schedule_models.dart#L22) (`'Pattern: <name>'`)
- "Preset": [lib/features/wled/wled_models.dart:15](lib/features/wled/wled_models.dart#L15) (`presetId`)
- "Scene": [lib/features/voice/dashboard_voice_control.dart:427](lib/features/voice/dashboard_voice_control.dart#L427), [lib/features/scenes/scene_models.dart:415](lib/features/scenes/scene_models.dart#L415) (returns `'Pattern'` as fallback for a scene type — direct evidence of the conflation)
- "Colorway": [lib/features/wled/colorway_effect_selector.dart](lib/features/wled/colorway_effect_selector.dart)
- **Recommendation:** **"Custom Design"** = user-saved/AI-composed; **"Pattern"** = effect+color combo (keep); retire **"Scene"** from UI unless voice-specific; keep **"Preset"**/**"Effect"** technical-only. **Severity: UNPROFESSIONAL** (this is the most user-visible naming confusion in the app).

### 4.3 Crew vs Group vs Neighborhood vs Team vs Sync → **"Neighborhood Sync"** / **"Group"** (technical only)
- "Neighborhood Sync" (primary, good): [lib/features/neighborhood/neighborhood_sync_screen.dart:109](lib/features/neighborhood/neighborhood_sync_screen.dart#L109)
- "Group" in UI: [lib/features/neighborhood/widgets/sync_event_setup_screen.dart:168](lib/features/neighborhood/widgets/sync_event_setup_screen.dart#L168), [lib/features/neighborhood/widgets/schedule_list.dart:257](lib/features/neighborhood/widgets/schedule_list.dart#L257) (`'Group Schedule'`)
- "Crew" (game day): [lib/features/game_day/game_day_screen.dart:1346](lib/features/game_day/game_day_screen.dart#L1346) (`'Failed to create crew'`), [:1938](lib/features/game_day/game_day_screen.dart#L1938)
- "Team" (sports — distinct, OK): [lib/features/sports_alerts/data/team_colors.dart](lib/features/sports_alerts/data/team_colors.dart)
- **Recommendation:** UI → **"Neighborhood"** / "Neighborhood Sync". Retire "Group" and "Crew" from user copy (keep `groupId` internal). "Team" stays sports-only. **Severity: COSMETIC→UNPROFESSIONAL** (the Game Day "crew" vocabulary is the odd one out).

### 4.4 Property vs Site vs Home vs Location → **"Home"** (consumer), **"Property"** (model)
- "Property": [lib/features/properties/property_models.dart:7](lib/features/properties/property_models.dart#L7), [:85](lib/features/properties/property_models.dart#L85) (`'Unnamed Property'`)
- "Site": entire `lib/features/site/` folder; [lib/features/site/bridge_setup_screen.dart:266](lib/features/site/bridge_setup_screen.dart#L266) (`'Site Setup'`)
- "Home": [lib/features/site/edit_profile_screen.dart:666](lib/features/site/edit_profile_screen.dart#L666) (`'Home Address'`), [lib/features/site/system_management_screen.dart:866](lib/features/site/system_management_screen.dart#L866) (`'Home Network'`)
- **Recommendation:** Consumer copy → **"Home"**; keep `Property` as the model name; stop surfacing "Site" in user text. **Severity: COSMETIC.**

### 4.5 Controller vs Device vs Bridge vs System → **"Controller"** + **"Bridge"** (distinct)
- "Controller" (primary): [lib/features/site/manage_controllers_page.dart:21](lib/features/site/manage_controllers_page.dart#L21)
- "Device" (catch-all): [lib/features/site/settings_page.dart:249](lib/features/site/settings_page.dart#L249) (`'System & Device Management'`)
- "Bridge" (cloud relay): [lib/features/site/bridge_setup_screen.dart:111](lib/features/site/bridge_setup_screen.dart#L111)
- **Recommendation:** **"Controller"** = local WLED hardware; **"Bridge"** = cloud relay; retire ambiguous **"Device"** from labels. **Severity: COSMETIC.**

---

## PRIORITY 5 — TONE / VOICE (dev-speak & inconsistent labels)

The premium voice ("Beyond the Light.") is broken wherever a raw exception or dev-prefix reaches the UI. ~35 SnackBars interpolate the raw exception object `$e`; ~20 prefix user copy with `Error:`.

### 5.1 Raw exception objects shown to users — **UNPROFESSIONAL** (volume makes it brand-wide)
Representative (not exhaustive):
- [lib/features/auth/login_page.dart:124](lib/features/auth/login_page.dart#L124) — `'Sign in failed: $e'`
- [lib/features/dashboard/wled_dashboard_page.dart:141](lib/features/dashboard/wled_dashboard_page.dart#L141) — `'Failed to save "$name": $e'`
- [lib/features/wled/edit_pattern_screen.dart:159](lib/features/wled/edit_pattern_screen.dart#L159) — `'Failed to save: $e'`
- [lib/features/ble/device_setup_page.dart:324](lib/features/ble/device_setup_page.dart#L324) — `'Connection failed: $e'`
- [lib/features/schedule/my_schedule_page.dart:4059](lib/features/schedule/my_schedule_page.dart#L4059) — `'Failed to save schedule: $e'`
- [lib/widgets/house_photo_uploader.dart:125](lib/widgets/house_photo_uploader.dart#L125) — `'Error: ${e.runtimeType}'` (leaks the Dart type name)
- **Fix direction:** Never surface `$e`/`runtimeType`. Log the exception; show an actionable line (*"Sign in unsuccessful. Check your email and password."*). Consider a shared `showBrandError(context, message)` helper to enforce it.

### 5.2 "Error:" dev-prefix in user copy — **UNPROFESSIONAL**
~20 occurrences, concentrated in sales/installer/admin screens: [lib/features/sales/screens/sales_jobs_screen.dart:56](lib/features/sales/screens/sales_jobs_screen.dart#L56), [lib/features/sales/screens/material_checkout_screen.dart:134](lib/features/sales/screens/material_checkout_screen.dart#L134), [lib/features/neighborhood/widgets/sync_control_panel.dart:1821](lib/features/neighborhood/widgets/sync_control_panel.dart#L1821), [lib/features/installer/admin/dealer_management_screen.dart:187](lib/features/installer/admin/dealer_management_screen.dart#L187), and more. **Fix:** drop the `Error:` prefix; use action-oriented copy.

### 5.3 Generic "Something went wrong" + raw toString — **UNPROFESSIONAL**
- [lib/features/design/services/design_studio_orchestrator.dart:113](lib/features/design/services/design_studio_orchestrator.dart#L113), [:370](lib/features/design/services/design_studio_orchestrator.dart#L370) — `'Something went wrong: ${e.toString()}'`
- [lib/features/properties/my_properties_screen.dart:120](lib/features/properties/my_properties_screen.dart#L120) — truncated exception text
- **Fix:** specific, actionable messages per context.

### 5.4 Inconsistent button labels — **COSMETIC**
Mixed confirm verbs: `'Got it'` ([lib/features/neighborhood/widgets/battery_optimization_prompt.dart:125](lib/features/neighborhood/widgets/battery_optimization_prompt.dart#L125), [lib/features/autopilot/autopilot_suggestions_card.dart:399](lib/features/autopilot/autopilot_suggestions_card.dart#L399)) vs `'OK'` ([lib/features/site/settings_page.dart:442](lib/features/site/settings_page.dart#L442), [lib/features/wled/hardware_config_screen.dart:391](lib/features/wled/hardware_config_screen.dart#L391)). Capitalization drifts (Title vs ALL-CAPS). **Fix:** pick one confirm verb ("Got It"), standardize Title Case across all dialog actions.

---

## PRIORITY 6 — STATE COVERAGE (empty / loading / error)

### 6.1 Silent error swallowing — **UNPROFESSIONAL** (ties to silent-failure audit)
`error: (_, __) => const SizedBox.shrink()` hides failures behind blank space, no retry:
- [lib/features/wled/pattern_library_browser.dart:90](lib/features/wled/pattern_library_browser.dart#L90), [:299](lib/features/wled/pattern_library_browser.dart#L299), [:497](lib/features/wled/pattern_library_browser.dart#L497) — My Saved / Recent / Pinned designs
- [lib/features/wled/pattern_theme_selection.dart:323](lib/features/wled/pattern_theme_selection.dart#L323)
- [lib/features/game_day/game_day_screen.dart:307](lib/features/game_day/game_day_screen.dart#L307) — live game status
- [lib/features/corporate/screens/corporate_dashboard_screen.dart:269](lib/features/corporate/screens/corporate_dashboard_screen.dart#L269)
- **Fix:** replace with an on-brand error card (icon + message + retry). **Good template already in-repo:** [lib/features/properties/my_properties_screen.dart:63-90](lib/features/properties/my_properties_screen.dart#L63).

### 6.2 Missing empty states — **UNPROFESSIONAL**
Collections render blank (not a CTA) when empty:
- [lib/features/wled/pattern_library_browser.dart:30](lib/features/wled/pattern_library_browser.dart#L30) — no "Create your first design" CTA
- [lib/features/wled/pattern_category_detail.dart:47](lib/features/wled/pattern_category_detail.dart#L47), [:654](lib/features/wled/pattern_category_detail.dart#L654) (`'No sub-categories yet'`, unstyled)
- Schedule lists in [lib/features/schedule/my_schedule_page.dart](lib/features/schedule/my_schedule_page.dart) — blank when empty
- **Fix:** branded empty states with a clear next action.

### 6.3 Generic / blank loading — **COSMETIC**
~25 bare `CircularProgressIndicator()` with no `color: NexGenPalette.cyan` ([lib/features/audio/screens/audio_reactive_screen.dart:91](lib/features/audio/screens/audio_reactive_screen.dart#L91), [lib/features/site/system_management_screen.dart:119](lib/features/site/system_management_screen.dart#L119), [lib/features/autopilot/autopilot_weekly_preview.dart:678](lib/features/autopilot/autopilot_weekly_preview.dart#L678)); plus `SizedBox.shrink()` blank loaders in the pattern-library/corporate/discovery screens. **Fix:** brand the spinner color; show skeletons where blank-load occurs.

---

## PRIORITY 7 — BRAND TOKEN CONSISTENCY

Token source: `NexGenPalette` in [lib/theme.dart](lib/theme.dart). Two cyan values coexist — `#00D4FF` (brand spec / LUMINA) and `#00E5FF` (CLAUDE.md "Primary accent"). **Decide one** and document it; this audit treats `#00D4FF` as canonical per the brand system, but the discrepancy itself should be resolved.

### 7.1 Cyan / blue drift — **UNPROFESSIONAL**
- `Colors.cyanAccent` (≠ `#00D4FF`) instead of `NexGenPalette.cyan`: [lib/features/auth/login_page.dart:190,197,218](lib/features/auth/login_page.dart#L190), [lib/features/auth/forgot_password_page.dart:93,97,126,128,141](lib/features/auth/forgot_password_page.dart#L93), [lib/features/auth/signup_page.dart:325](lib/features/auth/signup_page.dart#L325)
- `Colors.blueAccent` instead of a brand blue: [lib/features/auth/login_page.dart:218,449](lib/features/auth/login_page.dart#L218), [lib/features/auth/signup_page.dart:325](lib/features/auth/signup_page.dart#L325)
- Hardcoded `Color(0xFF00D4FF)` literal instead of the token: [lib/features/dashboard/wled_dashboard_page.dart:700](lib/features/dashboard/wled_dashboard_page.dart#L700)
- **Fix:** replace `Colors.cyanAccent`/`blueAccent` and raw cyan literals with `NexGenPalette` tokens. The auth flow is the worst offender and is the first screen a reviewer sees.

### 7.2 Undocumented dark colors outside the palette — **COSMETIC**
`Color(0xFF050812)` ([lib/features/dashboard/wled_dashboard_page.dart:806](lib/features/dashboard/wled_dashboard_page.dart#L806)), `Color(0xFF1A1A2E)` / `Color(0xFF080810)` ([lib/features/wled/pattern_explore_screen.dart:145](lib/features/wled/pattern_explore_screen.dart#L145)), sky-theme gradient stack ([lib/features/dashboard/wled_dashboard_page.dart:1429-1436](lib/features/dashboard/wled_dashboard_page.dart#L1429)). **Fix:** promote to named palette tokens or document why they're bespoke.

### 7.3 Material error/success colors instead of brand tokens — **COSMETIC**
`Colors.green` / `Colors.redAccent` for success/error feedback: [lib/features/auth/login_page.dart:235,244](lib/features/auth/login_page.dart#L235), [lib/features/dashboard/wled_dashboard_page.dart:1284](lib/features/dashboard/wled_dashboard_page.dart#L1284), [lib/features/schedule/autopilot_event_detail_sheet.dart:488](lib/features/schedule/autopilot_event_detail_sheet.dart#L488). **Fix:** define brand success/error tokens.

### 7.4 Off-brand fonts — **UNPROFESSIONAL**
`GoogleFonts.montserrat` in the auth flow instead of Exo 2 / DM Sans: [lib/features/auth/login_page.dart:159,174,253,542](lib/features/auth/login_page.dart#L159), [lib/features/auth/forgot_password_page.dart:97,126](lib/features/auth/forgot_password_page.dart#L97). (Note: the `v2.2.0` version string at line 542 is itself rendered in Montserrat.) Baseline app text styles correctly use Exo 2 / DM Sans — the auth screens are the divergence. **Fix:** swap Montserrat → Exo 2 (headers) / DM Sans (body).

### 7.5 White/black literals instead of FROST/VOID — **COSMETIC**
`Colors.white` for text and `Colors.black` for fills/shadows across the dashboard ([lib/features/dashboard/wled_dashboard_page.dart:280,287,764,773](lib/features/dashboard/wled_dashboard_page.dart#L280)) instead of `NexGenPalette.textHigh` (FROST) / `matteBlack` (VOID). **Fix:** token swap; low risk, high consistency payoff.

---

## RECOMMENDED FIX ORDER (before App Store review)

1. **Version drift** (P1) — single-source the version; kill `v2.2.0` / `1.6.0` / `Build 2026.01`. *Reviewer-visible, ~1hr.*
2. **False-promise copy** (P2.1 geofence, P2.3 iOS background, P2.4 voice) — rewrite or gate. *Trust + rejection risk.*
3. **Fake `Ref ID: #8821` + `YOUR_PROJECT_ID`** (P3) — remove/generate.
4. **Neighborhood "instantly" + remote latency hint** (P2.2, P2.6) — copy edits.
5. **Auth-flow brand tokens + fonts** (P7.1, P7.4) — first screen seen.
6. **Silent error swallowing** (P6.1) — apply the `my_properties_screen` error-card template.
7. Terminology canonicalization (P4) and remaining tone/state/token items — fast-follow.

---

*End of audit. Read-only — no code modified, no commits made.*
