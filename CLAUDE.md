# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Nex-Gen Lumina** is a premium Flutter mobile app for controlling permanent outdoor pixel LED systems based on WLED. The app is transitioning from prototype (Dreamflow) to production launch candidate with local and remote access capabilities.

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

Declarative routing is defined in [lib/nav.dart](lib/nav.dart):
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
- HTTP timeouts are currently set to **5 seconds** in `WledService`
- **KNOWN ISSUE:** Previous versions had "System Offline" false alarms. The fix requires increasing timeouts to **15+ seconds** in both `lib/nav.dart` (dashboard reconnect logic) and `lib/features/wled/wled_service.dart`

### Firebase Integration

**Auth:** Firebase Authentication for user sign-in/sign-up
- Managed by `FirebaseAuthManager` ([lib/auth/auth_manager.dart](lib/auth/auth_manager.dart))
- Current user stream: `authStateProvider`

**Firestore Collections:**
- `/users/{uid}` - User profiles (see `UserModel` in [lib/models/user_model.dart](lib/models/user_model.dart))
- `/users/{uid}/controllers` - User's registered WLED controllers
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

```bash
flutter build apk            # Android APK
flutter build ipa            # iOS (requires macOS + Xcode)
flutter build web            # Web build
```

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

### 1. "System Offline" and "Bad State" Crashes

**Problem:** The app shows false "System Offline" warnings and experiences state crashes due to:
- HTTP timeouts too aggressive (5s insufficient for some networks)
- Stale notifier references in `nav.dart` causing "Bad state: Trying to use a Notifier after `dispose` was called"

**Fix (MUST BE RE-APPLIED TO FRESH EXPORT):**

**In [lib/features/wled/wled_service.dart](lib/features/wled/wled_service.dart):**
- Change all `Duration(seconds: 5)` to `Duration(seconds: 15)` for HTTP client timeouts

**In [lib/nav.dart](lib/nav.dart):**
- In `_WledDashboardPageState`, ensure all button handlers use `ref.read()` dynamically, NOT cached notifier references
- Example: Replace `notifier.togglePower()` with `ref.read(wledStateProvider.notifier).togglePower()` if the notifier was stored in a variable

**In [lib/features/site/site_providers.dart](lib/features/site/site_providers.dart):**
- Increase timeout in `areaAnyOnProvider` from 4s to 15s:
  ```dart
  return await f.timeout(const Duration(seconds: 15));
  ```

### 2. Remote Access Architecture (NOT YET IMPLEMENTED)

**Current Limitation:** App only works on local Wi-Fi using direct IP addresses (e.g., `192.168.1.23`). When user leaves home network, all control fails.

**Planned Solution:**
1. Create a `ConnectivityService` to detect if user is on home Wi-Fi vs remote
2. If local: use existing HTTP calls (current behavior)
3. If remote: implement "Cloud Relay" via Firestore:
   - App writes commands to `/commands` collection in Firestore
   - Physical controller or local bridge device listens to this collection
   - Commands are executed and status written back to Firestore
4. Update `WledRepository` to transparently switch between local/remote modes

**Implementation Location:** Start in [lib/features/wled/wled_service.dart](lib/features/wled/wled_service.dart) or create new `lib/services/connectivity_service.dart`

## Project Structure

```
lib/
├── main.dart                   # Entry point, Firebase init
├── app_providers.dart          # Global providers (demoMode, auth)
├── nav.dart                    # GoRouter config + main dashboard UI
├── theme.dart                  # Material 3 theme (NexGenPalette)
├── auth/
│   └── auth_manager.dart       # Firebase Auth abstraction
├── features/
│   ├── ai/                     # Lumina AI chat integration
│   ├── auth/                   # Login/signup screens
│   ├── ble/                    # BLE provisioning for new devices
│   ├── discovery/              # mDNS device discovery
│   ├── geofence/               # Location-based automation
│   ├── patterns/               # Pattern generation utilities
│   ├── permissions/            # Welcome wizard (onboarding)
│   ├── schedule/               # Schedule CRUD + sync to WLED
│   ├── site/                   # Property/zone management, settings
│   └── wled/                   # WLED API integration (core)
├── models/                     # Shared data models
├── services/                   # User service, notifications
├── utils/                      # Sun time calculations
└── widgets/                    # Reusable UI components
```

## UI/UX Architecture

**Theme:** Premium dark theme with glassmorphic effects
- Palette: `NexGenPalette` in [lib/theme.dart](lib/theme.dart)
- Primary accent: Cyan (`#00E5FF`)
- Glass effects: `BackdropFilter` with blur + semi-transparent overlays

**Bottom Navigation:** 5-tab glass dock (see `_GlassDockNavBar` in [lib/nav.dart](lib/nav.dart))
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

`kSimulationMode` constant in [lib/app_providers.dart](lib/app_providers.dart):
- Currently hardcoded to `true`
- Bypasses permission prompts and uses virtual devices for web preview
- Should be tied to `kDebugMode` or build environment in production

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
3. **Remote Access:** Local-only architecture is insufficient for production. Implement cloud relay before launch.
4. **Error Handling:** Add user-friendly error messages and retry logic for all network operations
5. **Logging:** Remove debug prints before production release (use `kDebugMode` guards if needed)

## External Resources

- **WLED Documentation:** https://kno.wled.ge/
- **WLED JSON API:** https://kno.wled.ge/interfaces/json-api/
- **Flutter Riverpod:** https://riverpod.dev/
- **GoRouter:** https://pub.dev/packages/go_router
- **Firebase Flutter:** https://firebase.flutter.dev/
