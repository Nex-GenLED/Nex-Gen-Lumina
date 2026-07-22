# Lumina — App Store & Google Play Pre-Submission Audit

**Branch:** `submission/app-store-v1`
**Audit date:** 2026-04-21
**Bundle / Application ID:** `com.nexgenled.command` (iOS + Android match ✅)
**Version:** `2.2.0+6` (from [pubspec.yaml:5](pubspec.yaml#L5))
**Firebase project:** icrt6menwsv2d8all8oijs021b06s5

Legend: 🔴 BLOCKER · 🟡 WARNING · 🟢 CLEAN

---

## 1. iOS — `ios/Runner/Info.plist`

### 🔴 BLOCKERS

| Key | Status | Note |
|---|---|---|
| `NSBluetoothPeripheralUsageDescription` | **MISSING** | Required for iOS 12 and older. App declares `flutter_blue_plus` and BLE provisioning. Add even if min iOS is 13+ — App Review has rejected for missing. |
| `ITSAppUsesNonExemptEncryption` | **MISSING** | Not declaring this forces an export-compliance questionnaire on every TestFlight/App Store build. For standard HTTPS/TLS use, set `<false/>`. |
| `NSBonjourServices` — `_http._tcp` entry | **MISSING** | Current value only declares `<string>_wled._tcp</string>` at [Info.plist:49-51](ios/Runner/Info.plist#L49-L51). Some WLED firmware advertises over `_http._tcp`; without it, discovery may silently fail on iOS 14+ when Local Network requires per-service declaration. |
| iOS ATS / cleartext HTTP to WLED | **MISSING** | No `NSAppTransportSecurity` block. Android sets `android:usesCleartextTraffic="true"` ([AndroidManifest.xml:31](android/app/src/main/AndroidManifest.xml#L31)) but iOS has no equivalent. All `http://192.168.x.x` WLED calls in [wled_service.dart](lib/features/wled/wled_service.dart) will be blocked by ATS on release builds. Add `NSAppTransportSecurity` → `NSAllowsLocalNetworking` = true (preferred) or `NSAllowsArbitraryLoads` = true. |

### 🟡 WARNINGS

| Key | Status | Note |
|---|---|---|
| `NSUserTrackingUsageDescription` | Not present | Fine **only if** no ATT prompt is shown anywhere and no analytics/ads SDK requires it. Verify no third-party SDK (AdMob, Facebook, etc.) is pulling it in transitively. |
| `NSUserNotificationsUsageDescription` | Not present | This is not an iOS key (macOS only). `flutter_local_notifications` + APNS do not require an Info.plist string. Ignore this audit item — it's a false requirement. Noted here for completeness. |
| Key name — `NSPhotoLibraryAddOnlyUsageDescription` vs spec `NSPhotoLibraryAddUsageDescription` | Present at [Info.plist:79](ios/Runner/Info.plist#L79) | The `*AddOnly*` form is Apple's current (iOS 11+) spelling — valid. Audit spec lists the older name; no action needed. |

### 🟢 CLEAN

| Key | Location | Purpose String |
|---|---|---|
| `NSBluetoothAlwaysUsageDescription` | [Info.plist:81-82](ios/Runner/Info.plist#L81-L82) | "Nex-Gen uses Bluetooth to find and setup your lighting controller." |
| `NSLocalNetworkUsageDescription` | [Info.plist:52-53](ios/Runner/Info.plist#L52-L53) | "Nex-Gen needs this to find your lights" |
| `NSCameraUsageDescription` | [Info.plist:73-74](ios/Runner/Info.plist#L73-L74) | "Camera access is required for AR spatial mapping of your lights." |
| `NSPhotoLibraryUsageDescription` | [Info.plist:77-78](ios/Runner/Info.plist#L77-L78) | "Lumina needs access to your photo library to select a photo of your home for your lighting dashboard." |
| `NSPhotoLibraryAddOnlyUsageDescription` | [Info.plist:79-80](ios/Runner/Info.plist#L79-L80) | "Lumina needs permission to save lighting design photos to your library." |
| `NSLocationWhenInUseUsageDescription` | [Info.plist:55-56](ios/Runner/Info.plist#L55-L56) | "We use your location to configure the Welcome Home geofence." |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | [Info.plist:57-58](ios/Runner/Info.plist#L57-L58) | "Always Allow enables reliable geofence triggers even when the app is closed." |
| `NSLocationAlwaysUsageDescription` | [Info.plist:59-60](ios/Runner/Info.plist#L59-L60) | "Your location is used to detect when you arrive home so we can welcome you with lights." |
| `NSMicrophoneUsageDescription` | [Info.plist:75-76](ios/Runner/Info.plist#L75-L76) | "Microphone access is needed for voice-to-text control with Lumina." |
| `UIBackgroundModes` | [Info.plist:61-67](ios/Runner/Info.plist#L61-L67) | `location`, `fetch`, `processing`, `remote-notification` — all justifiable by geofence + sports alerts + schedule |
| `BGTaskSchedulerPermittedIdentifiers` | [Info.plist:68-72](ios/Runner/Info.plist#L68-L72) | `com.nexgenled.lumina.sportscheck`, `com.nexgenled.lumina.syncEventCheck` |
| `CFBundleURLTypes` — `lumina://` scheme | [Info.plist:84-94](ios/Runner/Info.plist#L84-L94) | Deep linking for Siri Shortcuts |

**Review note:** Microphone string says "voice-to-text" — the audit asked whether audio reactivity uses mic. [audio_mode_page.dart](lib/features/audio/audio_mode_page.dart) and [audio_reactive_screen.dart](lib/features/audio/screens/audio_reactive_screen.dart) exist. If audio reactivity uses the phone mic, the purpose string should also mention "audio-reactive lighting" — reviewers flag mismatched purpose strings.

---

## 2. Android — Manifest & Build

### Build config ([android/app/build.gradle](android/app/build.gradle))

| Field | Value | Status |
|---|---|---|
| `compileSdk` | `35` | 🟢 meets Play target |
| `targetSdk` | `35` | 🟢 meets Play target |
| `minSdk` | `flutter.minSdkVersion` (inherited — Flutter 3.6 default = 21) | 🟡 report — should be pinned explicitly for release. Firebase Auth + flutter_blue_plus effectively require 21+; consider pinning `minSdk = 23` to reduce legacy crash surface. |
| `versionCode` / `versionName` | pulled from pubspec → `6` / `2.2.0` | 🟢 |
| `applicationId` | `com.nexgenled.command` ([build.gradle:44](android/app/build.gradle#L44)) | 🟢 matches iOS |
| `namespace` | `com.nexgenled.command` ([build.gradle:19](android/app/build.gradle#L19)) | 🟢 |
| Signing — release | Uses debug keys when `key.properties` absent ([build.gradle:57](android/app/build.gradle#L57)) | 🟡 CI/release must ensure `key.properties` is present — silent fallback to debug signing would fail Play Console upload but produce a "release" APK locally. |
| `dependenciesInfo.includeInBundle = false` | [build.gradle:63](android/app/build.gradle#L63) | 🔴 **BLOCKER** — Play Console **requires** dependency metadata in App Bundle uploads. Set both `includeInApk` and `includeInBundle` to `true` (or remove the block entirely — defaults are `true`). Upload will be rejected otherwise. |

### `<uses-permission>` cross-reference

| Permission | Declared | Used in code | Status |
|---|---|---|---|
| `INTERNET` | ✅ | everywhere | 🟢 |
| `ACCESS_NETWORK_STATE` | ✅ | `connectivity_plus` in [connectivity_service.dart](lib/services/connectivity_service.dart) | 🟢 |
| `ACCESS_WIFI_STATE` | ✅ | `network_info_plus` for SSID detection | 🟢 |
| `CHANGE_WIFI_MULTICAST_STATE` | ✅ | mDNS discovery in [device_discovery.dart](lib/features/discovery/device_discovery.dart) | 🟢 |
| `ACCESS_FINE_LOCATION` | ✅ | `geolocator` in [geofence_monitor.dart](lib/features/geofence/geofence_monitor.dart) | 🟢 |
| `ACCESS_COARSE_LOCATION` | ✅ | geofence | 🟢 |
| `ACCESS_BACKGROUND_LOCATION` | ✅ | geofence background | 🟢 |
| `FOREGROUND_SERVICE` | ✅ | flutter_background_service | 🟢 |
| `FOREGROUND_SERVICE_LOCATION` | ✅ (Android 14+ type) | matches `geolocator` foreground service | 🟢 |
| `FOREGROUND_SERVICE_DATA_SYNC` | ✅ (Android 14+ type) | matches sports polling `BackgroundService` at [AndroidManifest.xml:76-79](android/app/src/main/AndroidManifest.xml#L76-L79) | 🟢 |
| `RECEIVE_BOOT_COMPLETED` | ✅ | used by sports background service to re-arm after reboot | 🟢 |
| `NEARBY_WIFI_DEVICES` | ✅ | Android 13+ discovery | 🟢 |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` (legacy, maxSdk=30) | ✅ | BLE provisioning | 🟢 |
| `BLUETOOTH_SCAN` (neverForLocation) | ✅ | [provisioning_service.dart](lib/features/ble/provisioning_service.dart) | 🟢 |
| `BLUETOOTH_CONNECT` | ✅ | BLE provisioning | 🟢 |
| `CAMERA` | ✅ | [controller_setup_screen.dart](lib/features/installer/screens/controller_setup_screen.dart), [image_upload_service.dart](lib/services/image_upload_service.dart) | 🟢 |
| `RECORD_AUDIO` | ✅ | voice input + audio reactivity | 🟢 |

### 🔴 BLOCKERS

- **`POST_NOTIFICATIONS` missing.** App uses `flutter_local_notifications` + FCM in [notifications_service.dart](lib/services/notifications_service.dart), [autopilot_notification_service.dart](lib/services/autopilot_notification_service.dart), [sync_notification_service.dart](lib/features/neighborhood/services/sync_notification_service.dart), [alert_trigger_service.dart](lib/features/sports_alerts/services/alert_trigger_service.dart). Android 13+ (API 33) **requires** `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` — without it, the runtime prompt never fires and notifications silently drop. With `targetSdk=35`, this is guaranteed broken on any Android 13+ device.
- **`dependenciesInfo.includeInBundle = false`** (see above).

### 🟡 WARNINGS

- **BLE foreground service type not declared.** If any BLE scanning extends into a foreground service on Android 14+, `FOREGROUND_SERVICE_CONNECTED_DEVICE` is required. Current BLE flow appears to be foreground-UI-only (provisioning wizard) so likely fine — verify.
- **`android:usesCleartextTraffic="true"`** ([AndroidManifest.xml:31](android/app/src/main/AndroidManifest.xml#L31)) is broad. Prefer a Network Security Config that whitelists only LAN subnets (`10.*`, `192.168.*`, `172.16–31.*`). Play Store does not reject but it's a security-review yellow flag.
- **Deep-link `<intent-filter android:autoVerify="true">`** at [AndroidManifest.xml:54-59](android/app/src/main/AndroidManifest.xml#L54-L59) uses `scheme="lumina"` (custom scheme, not http/https). `autoVerify` has no effect on custom schemes — no harm, but dead attribute; consider removing.

### 🟢 CLEAN

- MainActivity `android:exported="true"` explicitly set ([AndroidManifest.xml:34](android/app/src/main/AndroidManifest.xml#L34)) — Android 12+ requirement met.
- All services `android:exported="false"`.
- No test/debug intent filters.

---

## 3. App Icons

### iOS — `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

All 20 required sizes present, including:

- 🟢 `Icon-App-1024x1024@1x.png` (259,903 bytes — branded, not default) — **App Store marketing icon present.**
- 🟢 All iPhone sizes: 20@2x, 20@3x, 29@2x, 29@3x, 40@2x, 40@3x, 60@2x, 60@3x
- 🟢 All iPad sizes: 20@1x, 20@2x, 29@1x, 29@2x, 40@1x, 40@2x, 76@1x, 76@2x, 83.5@2x
- 🟢 Legacy: 50x50, 57x57, 72x72

No default Flutter "F" icon detected (1024 size is 259 KB — consistent with a branded icon).

### Android — `android/app/src/main/res/`

| Density | File | Size | Status |
|---|---|---|---|
| mdpi | `mipmap-mdpi/ic_launcher.png` | 2,072 B | 🟢 |
| hdpi | `mipmap-hdpi/ic_launcher.png` | present | 🟢 |
| xhdpi | `mipmap-xhdpi/ic_launcher.png` | present | 🟢 |
| xxhdpi | `mipmap-xxhdpi/ic_launcher.png` | present | 🟢 |
| xxxhdpi | `mipmap-xxxhdpi/ic_launcher.png` | 24,375 B | 🟢 |

### 🔴 BLOCKER

- **`mipmap-anydpi-v26/` directory missing.** Android 8.0+ requires an adaptive icon (`ic_launcher.xml` with `<adaptive-icon>` + `ic_launcher_foreground.png` + `ic_launcher_background.png` or color). Without it, icon shows as a square on modern launchers instead of the themed mask. This is a required Play Store asset for apps targeting API 26+ (you target 35). Play Console may accept the upload but the app will look unprofessional on every device since Android 8.

---

## 4. Launch / Splash Screens

### 🟡 WARNING — iOS `LaunchScreen.storyboard`

[ios/Runner/Base.lproj/LaunchScreen.storyboard](ios/Runner/Base.lproj/LaunchScreen.storyboard) still uses the default Flutter `LaunchImage` asset on a plain white background. Since `pubspec.yaml` includes `flutter_native_splash: ^2.0.0` but no configuration block is present, the launch screen is **default Flutter**. This won't get rejected but contradicts the "premium" brand — reviewers have flagged it as unpolished. Not a blocker.

### 🟡 WARNING — Android `launch_background.xml`

[android/app/src/main/res/drawable/launch_background.xml](android/app/src/main/res/drawable/launch_background.xml) is the **default white Flutter launch** (single `<item android:drawable="@android:color/white" />` with commented-out bitmap placeholder). Same verdict — not a blocker, but amateur-looking.

Recommendation: configure `flutter_native_splash` in pubspec to generate branded splash assets, or manually replace the drawable.

---

## 5. Bundle ID / Application ID

| Platform | Value | Source |
|---|---|---|
| iOS | `com.nexgenled.command` | [project.pbxproj:492, 682, 708](ios/Runner.xcodeproj/project.pbxproj#L492) |
| iOS tests | `com.nexgenled.command.RunnerTests` | project.pbxproj:509, 527, 543 |
| Android | `com.nexgenled.command` | [build.gradle:44](android/app/build.gradle#L44) |

🟢 **CLEAN — both match `com.nexgenled.*` and match each other.**

---

## 6. Release-Mode Code Quality

Scanned `lib/`. Counts:

| Pattern | Total | Files |
|---|---|---|
| `print(` | **22** | 3 |
| `debugPrint(` | **1,350** | 178 |
| `TODO` / `FIXME` / `HACK` / `XXX` | **42** | 23 |
| `192.168.*` / `10.0.*` / `localhost` literals | **~14** | 9 |
| `kDebugMode ? X : Y` ternaries that ship debug behavior | **0** | — |

### 🔴 BLOCKER — `print()` in production code paths

All 22 are in the demo/reviewer flow — exactly what App Review will exercise first.

| File:Line | Snippet |
|---|---|
| [lib/services/demo_code_service.dart:25](lib/services/demo_code_service.dart#L25) | `print('🔍 DEMO: Validating code: "$normalized"');` |
| [lib/services/demo_code_service.dart:34](lib/services/demo_code_service.dart#L34) | `print('🔍 DEMO: Query returned ${snap.docs.length} docs');` |
| [lib/services/demo_code_service.dart:37](lib/services/demo_code_service.dart#L37) | `print('🔍 DEMO: No matching documents found');` |
| [lib/services/demo_code_service.dart:42](lib/services/demo_code_service.dart#L42) | `print('🔍 DEMO: Found doc: $data');` |
| [lib/services/demo_code_service.dart:47](lib/services/demo_code_service.dart#L47) | `print('🔍 DEMO: Parsed OK — market="${demoCode.market}"');` |
| [lib/services/demo_code_service.dart:49-50](lib/services/demo_code_service.dart#L49) | `print('🔍 DEMO: fromJson FAILED: $e');` + stack print |
| [lib/services/demo_code_service.dart:57](lib/services/demo_code_service.dart#L57) | `print('🔍 DEMO: Code expired');` |
| [lib/services/demo_code_service.dart:64](lib/services/demo_code_service.dart#L64) | `print('🔍 DEMO: Usage limit reached');` |
| [lib/services/demo_code_service.dart:68](lib/services/demo_code_service.dart#L68) | `print('🔍 DEMO: Code valid — returning DealerDemoCode');` |
| [lib/features/demo/demo_code_screen.dart:79-81](lib/features/demo/demo_code_screen.dart#L79) | `print('🔍 DEMO: Exception during validation: $e');` + stack |
| [lib/features/demo/demo_lead_service.dart:47, 53, 65, 81, 101, 105, 119, 147, 178, 203](lib/features/demo/demo_lead_service.dart#L47) | 10× `print('DemoLeadService: …');` |

**Action:** replace with `debugPrint()` guarded by `kDebugMode`, or strip entirely.

### 🟡 WARNING — `debugPrint()` volume (1,350 occurrences / 178 files)

Not a rejection issue (debugPrint is gated in release), but top offenders worth pruning:

| Count | File |
|---|---|
| 49 | [lib/services/user_service.dart](lib/services/user_service.dart) |
| 49 | [lib/features/wled/wled_service.dart](lib/features/wled/wled_service.dart) |
| 40 | [lib/features/neighborhood/neighborhood_service.dart](lib/features/neighborhood/neighborhood_service.dart) |
| 34 | [lib/features/wled/wled_providers.dart](lib/features/wled/wled_providers.dart) |
| 30 | [lib/features/neighborhood/services/sync_event_background_worker.dart](lib/features/neighborhood/services/sync_event_background_worker.dart) |
| 30 | [lib/features/autopilot/background_learning_service.dart](lib/features/autopilot/background_learning_service.dart) |
| 26 | [lib/services/autopilot_scheduler.dart](lib/services/autopilot_scheduler.dart) |
| 26 | [lib/features/properties/properties_providers.dart](lib/features/properties/properties_providers.dart) |
| 24 | [lib/features/neighborhood/neighborhood_sync_engine.dart](lib/features/neighborhood/neighborhood_sync_engine.dart) |
| 22 | [lib/features/schedule/schedule_providers.dart](lib/features/schedule/schedule_providers.dart) |

### 🟡 WARNING — `TODO/FIXME` (42 occurrences / 23 files)

Top offenders:

| Count | File |
|---|---|
| 8 | [lib/features/sales/models/sales_models.dart](lib/features/sales/models/sales_models.dart) |
| 6 | [lib/screens/commercial/schedule/CommercialScheduleScreen.dart](lib/screens/commercial/schedule/CommercialScheduleScreen.dart) |
| 3 | [lib/features/design/screens/ai_design_studio_screen.dart](lib/features/design/screens/ai_design_studio_screen.dart) |
| 2 | [lib/screens/commercial/fleet/FleetDashboardScreen.dart](lib/screens/commercial/fleet/FleetDashboardScreen.dart) |
| 2 | [lib/features/wled/effect_speed_profiles.dart](lib/features/wled/effect_speed_profiles.dart) |
| 2 | [lib/features/site/referral_program_screen.dart](lib/features/site/referral_program_screen.dart) |
| 2 | [lib/features/sales/services/sales_job_service.dart](lib/features/sales/services/sales_job_service.dart) |
| 2 | [lib/features/sales/screens/day2_wrap_up_screen.dart](lib/features/sales/screens/day2_wrap_up_screen.dart) |

### 🟡 WARNING — Hardcoded IPs

All are either (a) hint text in form fields or (b) defensive fallbacks, not live endpoints. None are test/prod credentials — the Firebase project is loaded from `firebase_options.dart`.

| Location | Purpose |
|---|---|
| [lib/services/lumina_backend_service.dart:13-14](lib/services/lumina_backend_service.dart#L13) | `_defaultBaseUrl = 'http://localhost:3000'` — dev default. **Verify this is overridden for release builds** or change to a real prod URL fallback. 🟡 |
| [lib/features/ble/device_setup_page.dart:352](lib/features/ble/device_setup_page.dart#L352) | `final ip = '192.168.1.123';` — stubbed BLE result. 🟡 |
| [lib/features/ble/provisioning_service.dart:52, 256](lib/features/ble/provisioning_service.dart#L52) | Same stub. 🟡 |
| [lib/features/site/bridge_setup_screen.dart:121, 479](lib/features/site/bridge_setup_screen.dart#L121) | `?? '192.168.50.91'` — dev controller fallback. 🟡 confirm OK to ship — this is Tyler's home controller IP per memory. |
| [lib/features/installer/screens/controller_setup_screen.dart:454](lib/features/installer/screens/controller_setup_screen.dart#L454), [lib/features/ble/wled_manual_setup.dart:411](lib/features/ble/wled_manual_setup.dart#L411), [lib/features/site/bridge_setup_screen.dart:455](lib/features/site/bridge_setup_screen.dart#L455), [lib/features/site/settings_page.dart:199](lib/features/site/settings_page.dart#L199) | `hintText: '192.168.1.100'` — harmless UI placeholder. 🟢 |
| [lib/features/audio/services/audio_capability_detector.dart:168](lib/features/audio/services/audio_capability_detector.dart#L168) | In a doc comment. 🟢 |
| [lib/features/wled/wled_service.dart:136, 151](lib/features/wled/wled_service.dart#L136) | Comment + mock-host detection. 🟢 |

### 🟢 CLEAN

- No `kDebugMode ? X : Y` ternaries shipping debug behavior in release.
- No hardcoded test Firebase project IDs, API keys, or test credentials in `lib/`.

---

## 7. Reviewer Path

### 🟢 CLEAN

- **[lib/services/reviewer_seed_service.dart](lib/services/reviewer_seed_service.dart) exists.** Creates `users/reviewer-demo-account-001` Firestore document with `reviewer@nexgenled.com` ([reviewer_seed_service.dart:12](lib/services/reviewer_seed_service.dart#L12)).
- **5-tap logo gesture wired.** [login_page.dart:73-85](lib/features/auth/login_page.dart#L73-L85) — `_onLogoTap()` counts to 5 within 3-second window, navigates to staff PIN entry.
- **Separate 5-tap subtitle gesture reveals App Store reviewer button.** [login_page.dart:88-101](lib/features/auth/login_page.dart#L88-L101) — no time window, sets `_showReviewerButton = true`. Button at [login_page.dart:500-520](lib/features/auth/login_page.dart#L500-L520) autofills reviewer email and shows "Review credentials applied" snackbar.
- **Demo code entry reachable from login.** Visible "Experience Nex-Gen Demo" button at [login_page.dart:481](lib/features/auth/login_page.dart#L481) pushes `AppRoutes.demoCode` → [demo_code_screen.dart](lib/features/demo/demo_code_screen.dart).
- No uncommitted WIP in any of these files (working tree clean per `git status`).

### 🟡 Review notes

- Reviewer button only autofills **email** — password field stays empty. Reviewer must still type a password. Confirm the reviewer submission notes in App Store Connect include the password, or autofill both fields.
- The reviewer flow uses the Firebase Auth path against the **live** Firebase project (`icrt6menwsv2d8all8oijs021b06s5`). Ensure `reviewer@nexgenled.com` actually exists as a Firebase Auth user with a known password — the `ReviewerSeedService` creates only the Firestore profile doc, **not** the Auth user. If the Auth user is missing, the reviewer login silently fails. 🔴 verify this before submission.

---

## 8. Version

[pubspec.yaml:5](pubspec.yaml#L5) → `version: 2.2.0+6`

- iOS Info.plist uses `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` — pulls from pubspec ✅
- Android build.gradle uses `flutter.versionCode` / `flutter.versionName` — pulls from pubspec ✅

**Recommendation:** Audit asks whether to use `1.0.0+1` for a new App Store Connect listing or keep `2.2.0+6` for an existing one. **Decide based on whether an App Store Connect record already exists for `com.nexgenled.command`.** If yes → keep `2.2.0+6`. If no → reset to `1.0.0+1` — App Store will reject first submissions where the marketing version implies a history that doesn't exist in Connect.

---

## Summary — What must happen before submission

### 🔴 Must fix (will cause rejection or runtime breakage)

1. **iOS ATS for cleartext LAN HTTP** — add `NSAppTransportSecurity` → `NSAllowsLocalNetworking` in Info.plist, else WLED control broken on iOS release.
2. **iOS `NSBluetoothPeripheralUsageDescription`** — add (BLE provisioning active).
3. **iOS `ITSAppUsesNonExemptEncryption = <false/>`** — add to avoid export-compliance blocker on every upload.
4. **iOS `NSBonjourServices` add `_http._tcp.`** — required for full WLED discovery on iOS 14+.
5. **Android `POST_NOTIFICATIONS` permission** — add, else notifications silently dropped on Android 13+.
6. **Android `dependenciesInfo.includeInBundle = true`** — flip to `true` (currently `false`), else Play Console bundle upload rejected.
7. **Android adaptive icon (`mipmap-anydpi-v26/`)** — create `ic_launcher.xml` + foreground/background layers.
8. **Strip `print(` calls** — 22 in reviewer/demo path, visible to App Review if they attach Xcode logs.
9. **Verify `reviewer@nexgenled.com` exists in Firebase Auth** — Firestore seed alone is not enough.

### 🟡 Should fix (polish / secondary risk)

- Replace default iOS LaunchScreen and default Android launch_background with branded splash.
- Pin Android `minSdk` explicitly (suggest 23).
- Replace microphone purpose string to cover audio-reactive lighting too if mic is used there.
- Scope `usesCleartextTraffic` to LAN-only via a Network Security Config.
- Sanity-check `lumina_backend_service.dart` default `http://localhost:3000` — ensure overridden in release.
- Prune top debugPrint offenders (wled_service, user_service, neighborhood_service).

### 🟢 Already correct

- Bundle ID / Application ID alignment.
- `compileSdk`/`targetSdk` = 35.
- iOS Background modes + BGTaskSchedulerPermittedIdentifiers.
- Android foreground service types declared for location + data sync.
- All iOS icon sizes including 1024×1024 marketing.
- 5-tap reviewer gesture wiring + seed service.
- Version numbering is consistent across platforms.
