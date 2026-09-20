# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Nex-Gen Lumina** is a premium Flutter mobile app for controlling permanent outdoor pixel LED systems based on WLED. The app is a production launch candidate with local-network and remote (cloud relay) control paths. Originally ported from a Dreamflow prototype.

**Package Name:** `nexgen_command`
**SDK:** Flutter 3.6.0+
**Primary Platforms:** iOS, Android (Web support exists but limited)

## Core Architecture

### State Management: Flutter Riverpod 2.5+

The app uses **Riverpod** for all state management. Key patterns:

- **Notifier/NotifierProvider** for complex stateful logic (e.g., `WledNotifier`, `PropertyAreasNotifier`)
- **StateProvider** for simple mutable state (e.g., `selectedDeviceIpProvider`, `demoModeProvider`)
- **FutureProvider/StreamProvider** for async data (e.g., `authStateProvider`, `areaAnyOnProvider`)
- **Provider** for dependency injection (e.g., `wledRepositoryProvider`, `authManagerProvider`)

When reading state in widgets: `ref.watch()`. When mutating state: `ref.read().notifier`.

### Navigation: GoRouter 16.2+

Declarative routing is defined in [lib/app_router.dart](lib/app_router.dart), with the
redirect/guard logic in [lib/route_guards.dart](lib/route_guards.dart).

> `lib/nav.dart` is **not** the router. It is a four-line barrel that re-exports both of the
> files above, kept so existing `import '.../nav.dart'` lines keep working. Edit
> `app_router.dart` / `route_guards.dart`. The dashboard UI that used to live here moved to
> [lib/features/dashboard/wled_dashboard_page.dart](lib/features/dashboard/wled_dashboard_page.dart).

- Route constants live in `AppRoutes` class (e.g., `AppRoutes.dashboard`, `AppRoutes.settings`)
- Navigate with `context.push()` or `context.go()`
- Path parameters use `:paramName` syntax (e.g., `/explore/:categoryId`)
- Pass extra data via `state.extra` in `pageBuilder`

### WLED Integration (Core Feature)

The app controls WLED devices (permanent LED light controllers) over HTTP and optionally UDP/DDP.

**Key Classes:**
- **WledRepository** ([lib/features/wled/wled_repository.dart](lib/features/wled/wled_repository.dart)): Abstract interface for WLED operations
- **WledService** ([lib/features/wled/wled_service.dart](lib/features/wled/wled_service.dart)): Concrete HTTP implementation communicating with WLED JSON API
- **MockWledRepository** ([lib/features/wled/mock_wled_repository.dart](lib/features/wled/mock_wled_repository.dart)): Demo mode implementation
- **WledNotifier** ([lib/features/wled/wled_providers.dart](lib/features/wled/wled_providers.dart)): Manages polling and state synchronization

**WLED HTTP Endpoints:**
- `GET /json/state` - Current device state (on/off, brightness, segments, colors)
- `POST /json/state` - Update device state
- `POST /json/cfg` - Configuration updates (timers, network settings)
- `GET /json/info` - Device capabilities (RGBW support, etc.)

**Timeout Configuration:**
- HTTP timeouts are **15 seconds** in `WledService` (verified 2026-09-17 —
  every `_wledClientFor(...)` and `req.close().timeout(...)` call site).
- `areaAnyOnProvider` in `lib/features/site/site_providers.dart` is also 15 s.
- This entry previously said 5 s and described the increase as outstanding. It
  was stale: the change is in the code and has been for some time. See
  "Critical Known Issues" below.

### Firebase Integration

**Auth:** Firebase Authentication for user sign-in/sign-up
- Managed by `FirebaseAuthManager` ([lib/auth/auth_manager.dart](lib/auth/auth_manager.dart))
- Current user stream: `authStateProvider`

**Firestore Collections:**
- `/users/{uid}` - User profiles (see `UserModel` in [lib/models/user_model.dart](lib/models/user_model.dart))
- `/users/{uid}/controllers` - User's registered WLED controllers
- `/users/{uid}/properties` - User's properties/locations with linked controller IDs
- `/users/{uid}/schedules` - Scheduled automations

**Initialization:** Firebase is initialized in [lib/main.dart](lib/main.dart) with fallback handling for missing native config files.

### Site Management: Residential vs Commercial Modes

The app supports two deployment modes (see [lib/features/site/site_providers.dart](lib/features/site/site_providers.dart)):

1. **Residential Mode (`SiteMode.residential`)**:
   - Single property with one or more "linked" controllers acting as a unified system
   - Uses `PropertyArea` model to represent the property
   - Controllers can be linked/unlinked via `linkedControllersProvider`

2. **Commercial Mode (`SiteMode.commercial`)**:
   - Multiple zones with independent control
   - Each `ZoneModel` has a primary controller and optional secondary members
   - Supports DDP/UDP sync for multi-controller zones

**Active Controllers Resolution:**
- `activeAreaControllerIpsProvider` returns the list of controller IPs that should respond to commands
- In Residential mode with linked controllers: uses only linked set
- Otherwise: falls back to all discovered controllers

### Schedule System

Users can create time-based automations (see [lib/features/schedule/](lib/features/schedule/)):

**Key Files:**
- `schedule_models.dart` - `ScheduleItem` data model
- `schedule_providers.dart` - Riverpod providers for schedule CRUD
- `schedule_sync.dart` - `ScheduleSyncService` that converts schedules to WLED timer payloads
- `my_schedule_page.dart` - UI for viewing/editing schedules

**Schedule Sync:**
- Schedules are stored in Firestore AND pushed to WLED device as native timers
- `ScheduleSyncService.syncAll()` builds a `/json/cfg` payload with `tim` array (up to 20 timers)
- Timers support sunrise/sunset offsets via `mode` field (0=clock time, 1=sunrise, 2=sunset)

### Pattern Library

The app includes a library of lighting patterns/effects (see [lib/features/wled/pattern_library_pages.dart](lib/features/wled/pattern_library_pages.dart)):

- Organized by categories and subcategories (see `PatternCategory` in [lib/features/wled/pattern_models.dart](lib/features/wled/pattern_models.dart))
- Patterns are WLED effect presets (effect ID + palette ID + speed/intensity params)
- UI includes browsing, preview, and "apply to device" actions

**Pattern Providers:**
- `publicPatternLibraryProvider` - Exposes the full pattern catalog
- `favoritePatternIdsProvider` - User's favorited patterns

### Device Discovery

Local network discovery via mDNS (see [lib/features/discovery/device_discovery.dart](lib/features/discovery/device_discovery.dart)):

- Scans for `_wled._tcp` service announcements on local network
- Returns list of `DiscoveredDevice` with IP addresses
- Selected device IP is stored in `selectedDeviceIpProvider`

### Property Management

Users can manage multiple properties/locations (see [lib/features/properties/](lib/features/properties/)):

- **Property model** ([lib/features/properties/property_models.dart](lib/features/properties/property_models.dart)): `Property` with name, address, icon, linked controller IDs, geofence config
- **Providers** ([lib/features/properties/properties_providers.dart](lib/features/properties/properties_providers.dart)): `userPropertiesProvider` (stream), `selectedPropertyProvider`, `propertyManagerProvider`
- **UI** ([lib/features/properties/my_properties_screen.dart](lib/features/properties/my_properties_screen.dart)): Property CRUD with controller linking via bottom sheet
- Controllers are linked/unlinked to properties via `PropertyManager.linkController()` / `unlinkController()`
- Firestore path: `/users/{uid}/properties/{propertyId}`

### Address Autocomplete / Geocoding

Address input uses Google Places Autocomplete (New) as primary, with Photon (OSM) as fallback (see [lib/features/schedule/geocoding_service.dart](lib/features/schedule/geocoding_service.dart)):

- **Google Places API (New)** requires `places.googleapis.com` enabled in Google Cloud Console
- API key is pulled from `DefaultFirebaseOptions` (platform-appropriate key)
- Results are returned immediately from autocomplete without detail fetching for speed
- **Photon** (komoot.io) fallback: free, no API key, OSM-based fuzzy matching
- Widget: [lib/widgets/address_autocomplete.dart](lib/widgets/address_autocomplete.dart) — debounced overlay dropdown

### Geofencing

Automated control based on location (see [lib/features/geofence/](lib/features/geofence/)):

- `GeofenceMonitor` tracks user location and triggers actions when entering/leaving defined areas
- Requires location permissions (handled by `welcome_wizard.dart` onboarding flow)
- Uses `geolocator` package for position tracking

### BLE Provisioning

First-time device setup via Bluetooth (see [lib/features/ble/](lib/features/ble/)):

- `ProvisioningService` communicates with WLED controllers over BLE to configure Wi-Fi credentials
- `ControllerSetupWizard` provides a guided setup flow
- Uses `flutter_blue_plus` package

## Development Commands

### Run the App

```bash
flutter run
```

**Target specific platform:**
```bash
flutter run -d chrome        # Web
flutter run -d ios           # iOS Simulator
flutter run -d android       # Android Emulator
```

### Build

**Android SDK levels (verified in `android/app/build.gradle` 2026-09-17):**
`compileSdk = 36`, `targetSdk = 36`, `minSdkVersion = 24`.

> Google Play's deadline for targeting **Android 16 (API 36)** passed on **2026-08-31**, and
> the repo is compliant. Anything you read elsewhere describing API 36 as an upcoming risk,
> or this repo as `targetSdk 35`, is stale.

**Development / quick builds:**
```bash
flutter build apk            # Android APK
flutter build ipa            # iOS (requires macOS + Xcode)
flutter build web            # Web build
```

**Release builds with obfuscation (use these for store submissions):**
```bash
# Android — APK
flutter build apk --release --obfuscate --split-debug-info=build/debug-info/android

# Android — App Bundle (preferred for Play Store)
flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info/android

# iOS
flutter build ios --release --obfuscate --split-debug-info=build/debug-info/ios
```

Or use the named targets in `build.sh`:
```bash
./build.sh build-android-release
./build.sh build-ios-release
./build.sh build-all-release
```

> **Important:** The `build/debug-info/` directory contains symbol files required
> for crash symbolication. Keep these files — never commit them to source control
> and never delete them after a release.

> **Building an Android release from a fresh worktree:** the three git-ignored
> inputs (`android/key.properties`, the release keystore, `android/app/google-services.json`)
> must come from the **main repo**, never from another build worktree. Run
> `bash scripts/signing_inputs.sh install` — do not `cp` them by hand. This is
> enforced: `android/signing-inputs-guard.gradle` refuses any release build whose
> inputs are missing or not byte-identical to the main repo's. There is no skip
> flag. See `docs/BUILD_LEDGER.md`, standing convention 3.

### Code Generation (if needed)

This project doesn't currently use code generation (no build_runner), but if freezed/json_serializable are added later:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Linting

```bash
flutter analyze
```

Lint rules are defined in [analysis_options.yaml](analysis_options.yaml) using `flutter_lints: ^5.0.0`.

### Dependencies

```bash
flutter pub get              # Install dependencies
flutter pub upgrade          # Upgrade packages
flutter pub outdated         # Check for outdated packages
```

### Clean Build

```bash
flutter clean
flutter pub get
flutter run
```

## Critical Known Issues & Fixes

### 1. "System Offline" and "Bad State" Crashes — FIXED, verified 2026-09-17

**Historical problem:** false "System Offline" warnings and state crashes from
aggressive HTTP timeouts and stale notifier references.

**All three fixes are present in the code.** This section used to read "MUST BE
RE-APPLIED TO FRESH EXPORT" and list them as outstanding work; that was stale
and is corrected here. Re-applying them is not a task — verifying them is:

| Fix | State |
|---|---|
| `wled_service.dart` HTTP timeouts at 15 s | Present — all client and `req.close()` call sites |
| `site_providers.dart` `areaAnyOnProvider` at 15 s | Present |
| No cached notifier refs in dashboard handlers | Present — handlers resolve via `ref.read(...)` inline |

**The rule this came from still stands**, and it is the part worth keeping:
never cache a `notifier` reference in a `State` class — resolve it inline with
`ref.read(...).notifier` at the call site, or you reintroduce "Bad state: Trying
to use a Notifier after `dispose` was called". See "Common Gotchas" below.

Note that `lib/nav.dart` is now a four-line barrel re-exporting
`app_router.dart` and `route_guards.dart`; the dashboard lives in
`lib/features/dashboard/wled_dashboard_page.dart`. Older instructions pointing
at `nav.dart` for dashboard code are pointing at the wrong file.

### 2. Remote Access Architecture — SHIPPED

Remote control from off-home networks is implemented via the ESP32 Lumina Bridge and a Firestore command relay. Both transport paths are live:

- **Bridge Mode (default, dealer-installed):** App writes commands to `/users/{uid}/commands/{commandId}`. An ESP32 bridge on the customer's LAN polls Firestore and executes locally. No port forwarding required. Round-trip ~5–10s typical, 30–45s tail.
- **Webhook Mode (DIY):** A Firebase Cloud Function forwards commands to a customer-supplied webhook URL. Requires DDNS + port forward.

**Key code paths:**
- [lib/features/wled/cloud_relay_repository.dart](lib/features/wled/cloud_relay_repository.dart) — `CloudRelayRepository` implements `WledRepository` for off-LAN control
- [lib/services/bridge_api_client.dart](lib/services/bridge_api_client.dart), [bridge_health_service.dart](lib/services/bridge_health_service.dart), [bridge_discovery_service.dart](lib/services/bridge_discovery_service.dart) — bridge integration
- [lib/features/site/remote_access_screen.dart](lib/features/site/remote_access_screen.dart) — user-facing setup UI
- [esp32-bridge/](esp32-bridge/) — bridge firmware (PlatformIO)

Routing matrix + per-command details: [docs/bridge_command_routing_context_2026-05-11.md](docs/bridge_command_routing_context_2026-05-11.md). User-facing setup: [docs/ESP32_Bridge_Setup_Guide.md](docs/ESP32_Bridge_Setup_Guide.md), [docs/Dealer_Installer_Setup_Guide.md](docs/Dealer_Installer_Setup_Guide.md) §9.

## Project Structure

```
lib/
├── main.dart                   # Entry point, Firebase init
├── app_providers.dart          # Global providers (demoMode, auth)
├── nav.dart                    # Barrel only — re-exports app_router.dart + route_guards.dart
├── app_router.dart             # GoRouter config + AppRoutes constants
├── route_guards.dart           # appRedirect / role + link-state gating
├── app_version.dart            # Single source of truth for the version string
├── theme.dart                  # Material 3 theme (NexGenPalette)
├── auth/
│   └── auth_manager.dart       # Firebase Auth abstraction
├── features/
│   ├── ai/                     # Lumina AI chat integration
│   ├── audio/                  # Audio-reactive mode (interface IN-PROGRESS; WLED hardware mic backend)
│   ├── auth/                   # Login/signup screens
│   ├── autopilot/              # Calendar-driven automation (Game Day, etc.)
│   ├── ble/                    # BLE provisioning for new devices
│   ├── commercial/             # Commercial-mode features
│   ├── dashboard/              # Main dashboard surfaces
│   ├── dealer/                 # Dealer-facing tools
│   ├── design/                 # Design Studio
│   ├── discovery/              # mDNS device discovery
│   ├── geofence/               # Location-based automation
│   ├── neighborhood/           # Neighborhood Sync engine
│   ├── patterns/               # Pattern generation utilities
│   ├── permissions/            # Welcome wizard (onboarding)
│   ├── sales/                  # Sales pipeline (SalesJob)
│   ├── scenes/                 # Scene model + management
│   ├── schedule/               # Schedule CRUD + sync to WLED
│   ├── site/                   # Property/zone management, settings, remote access UI
│   ├── voice/                  # Alexa/Google/Siri integrations (ARCHITECTED — not yet verified end-to-end)
│   └── wled/                   # WLED API integration (core) — incl. cloud_relay_repository.dart
├── models/                     # Shared data models
├── services/                   # Bridge client/health/discovery, user service, notifications
├── utils/                      # Sun time calculations
└── widgets/                    # Reusable UI components
```

## UI/UX Architecture

**Theme:** Premium dark theme with glassmorphic effects
- Palette: `NexGenPalette` in [lib/theme.dart](lib/theme.dart)
- Primary accent: Cyan (`#00E5FF`)
- Glass effects: `BackdropFilter` with blur + semi-transparent overlays

**Bottom Navigation:** 5-tab glass dock (see `GlassDockNavBar` in [lib/widgets/navigation/glass_dock_nav_bar.dart](lib/widgets/navigation/glass_dock_nav_bar.dart), mounted by [lib/features/dashboard/main_scaffold.dart](lib/features/dashboard/main_scaffold.dart))
1. Home - Main dashboard with hero image + quick controls
2. Schedule - Weekly schedule view
3. Lumina (center) - AI chat assistant
4. Explore - Pattern library browser
5. System - Settings and configuration

**Dashboard Layout (WledDashboardPage):**
- Hero image (user's house photo or default)
- Overlaid controls (power button, brightness slider)
- Quick preset buttons (Run Schedule, Warm White, etc.)
- Weekly schedule preview
- Lumina AI chat bar at bottom

## Testing Strategy

**No automated tests currently exist.** When adding tests:

- Unit tests: Test providers, models, services in isolation
- Widget tests: Test UI components with `WidgetTester`
- Integration tests: Test full flows (discovery → connect → control)

**Recommended test structure:**
```
test/
├── unit/
│   ├── providers/
│   ├── services/
│   └── models/
├── widget/
│   └── features/
└── integration/
```

## Special Considerations

### Demo Mode

`demoModeProvider` toggles between real and mock implementations:
- When `true`: uses `MockWledRepository`, bypasses network calls
- When `false`: uses `WledService` with real HTTP requests
- Useful for UI development without physical hardware

### Simulation Mode

`kSimulationMode` constant in [lib/app_providers.dart:17](lib/app_providers.dart#L17):
- **Hardcoded to `false`.** (This entry previously said `true`, which was wrong
  and had been wrong for some time — worth knowing, because a reader who
  believed it would conclude that release builds bypass permission prompts and
  talk to virtual devices, and would misread every discovery, BLE and DDP code
  path as simulated.)
- When `true` it bypasses permission prompts and network/BLE scanning and
  substitutes a virtual device. With the shipping value of `false`, every one of
  those paths is the real-hardware path.
- Read at eight sites: `lib/services/bridge_discovery_service.dart`,
  `lib/features/discovery/device_discovery.dart`,
  `lib/features/ble/provisioning_service.dart`,
  `lib/features/ble/device_setup_page.dart`,
  `lib/features/permissions/welcome_wizard.dart`,
  `lib/features/wled/ddp_service.dart`.
- It is a compile-time `const`, so the simulated branches are tree-shaken out of
  release builds rather than merely unreached.
- Still worth tying to `kDebugMode` or a build flag rather than hand-editing, so
  that flipping it for local work cannot be committed by accident.

### Connection Resilience

`WledNotifier` implements automatic reconnection:
- Polls device state every 1.5s
- On connection loss, starts a 10s retry timer
- Manual reconnect button available in UI

### Multi-Controller Coordination

For zones with multiple controllers (Commercial mode):
- Primary controller sends UDP/DDP packets to secondaries
- Configuration via `DDPSyncController.applyZoneSync()`
- All devices stay in sync via broadcast protocol

## Common Gotchas

1. **Riverpod Dispose Errors:** Never cache `notifier` references in State classes. Always use `ref.read().notifier` inline to avoid "Bad state" errors after widget disposal.

   **The rule stands; the hazard is currently clean.** Swept 2026-09-17: **zero**
   cached `*Notifier` fields anywhere in `lib/`, and exactly **two** uses of
   `ref.` inside a `dispose()` body, both deliberate and commented —
   [installer_setup_wizard.dart:320](lib/features/installer/installer_setup_wizard.dart#L320)
   (synchronous, runs before the ref is torn down) and
   [pattern_theme_selection.dart:218](lib/features/wled/pattern_theme_selection.dart#L218)
   (captures the notifier *before* its `Future.microtask`, naming the
   `debug_errors` doc it fixes). Read this as a convention to preserve, not as
   an outstanding defect to go hunting for.

2. **WLED JSON API Variability:** The `seg` field in `/json/state` can be either a List or a Map depending on WLED firmware version. Always check type before accessing.

3. **Firestore Offline Persistence:** Firebase Firestore caching can cause stale data. Use `.get(GetOptions(source: Source.server))` to force fresh fetches if needed.

4. **Asset Loading:** All images must be declared in `pubspec.yaml` under `assets:`. Missing declarations cause runtime errors.

5. **Platform Permissions:** iOS and Android require different permission configurations:
   - iOS: Update `Info.plist` for location, Bluetooth, local network
   - Android: Update `AndroidManifest.xml` for location, Bluetooth, internet

## Migration Notes for Dreamflow → Production

When porting features from the Dreamflow prototype:

1. **Re-apply Stability Fixes:** Always increase HTTP timeouts to 15s and remove stale notifier references
2. **Firebase Config:** Ensure `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) are up to date
3. **Remote Access:** Cloud relay is shipped (ESP32 Bridge + Firestore command queue). When porting future Dreamflow features, route any new write paths through `WledRepository` so they work in both local and remote modes.
4. **Error Handling:** Add user-friendly error messages and retry logic for all network operations
5. **Logging:** Remove debug prints before production release (use `kDebugMode` guards if needed)

## External Resources

- **WLED Documentation:** https://kno.wled.ge/
- **WLED JSON API:** https://kno.wled.ge/interfaces/json-api/
- **Flutter Riverpod:** https://riverpod.dev/
- **GoRouter:** https://pub.dev/packages/go_router
- **Firebase Flutter:** https://firebase.flutter.dev/
