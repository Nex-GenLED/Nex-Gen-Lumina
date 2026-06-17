# Feature-Completeness Inventory — Overnight Audit 4

**Date:** 2026-06-02 · **Branch:** submission/app-store-v1 · **Method:** READ-ONLY, 7 parallel cluster audits over nav/screens. No code changed.
**Purpose:** Decide v1 ship scope vs "coming soon." Honest status per user-facing feature, with hidden gaps flagged.

Legend: **COMPLETE** / **PARTIAL** / **STUBBED** / **BROKEN**. Citations are `file:line`.

---

## 0. Cross-cutting systemic findings (read first)

1. **Multi-controller fan-out is NOT in the main control path.** `WledNotifier._postUpdate` → `wledRepositoryProvider` targets exactly ONE controller (the `selectedDeviceIpProvider` match, `wled_providers.dart:138-234`). Residential "linked controllers acting as a unified system" is honored only by scattered ad-hoc `WledService('http://$ip')` fan-outs (dashboard power `wled_dashboard_page.dart:949`, `areaAnyOnProvider`, DDP sync, sports alerts). **Those direct-IP fan-outs are LAN-only — they do NOT work off-LAN via cloud relay.** Brightness, color, pattern apply, schedule sync all hit one controller only.

2. **Multi-channel (per-bus) filtering is correct on SOME paths, bypassed on others.** `applyChannelFilter` + `expandForParticipation` run on both transports — but only when the *caller* applies the filter. **Paths that bypass it light bus 0 only** (same root cause as the fixed Game-Day "channel-2 skip"):
   - ✅ Apply correctly: Explore/Colorway selector, Edit Pattern, `applySavedDesign`, Game Day, Sports Alerts test-fire.
   - ❌ Bypass (bus-0 only): **Lumina AI chat apply** (`lumina_ai_screen.dart:258,328`; `lumina_bottom_sheet.dart:598,669`), **Audio Mode**, **Current Colors editor** (`current_colors_provider.dart:296` self-documents "should apply to all segments"), `applyScene`, geofence "party" fallback (`geofence_monitor.dart:282`).

3. **Blocks boundary-blend caveat** (per bench-verified memory): crisp `i`-array + `fx:0` is used ONLY in Edit Pattern's STATIC mode. All other multi-color block paths (Colorway, Edit animated, Design Studio save) use `pal:5`/`fx:83` palette interpolation → smear at boundaries.

4. **Cloud relay degradations:** `getConfig` returns null remotely (`cloud_relay_repository.dart:409`) → Hardware Config can't read off-LAN; LED-map upload + preset fetch unsupported remotely.

5. **Version-string drift:** login shows `v2.2.0` (`login_page.dart:541`), settings shows `1.6.0 / Build 2026.01` (`settings_page.dart:649`), pubspec is `2.3.0+26`. Cosmetic but reviewer-visible.

---

## 1. Consumer-facing core (the v1 decision surface)

| Feature | Status | What works / what's missing |
|---|---|---|
| **Home Dashboard** | COMPLETE | Power, debounced brightness, presets, favorites, smart suggestions, hero, Game Day button all real. ⚠️ Audio tile release-gated (`kDebugMode` only, `wled_dashboard_page.dart:466`). Power fan-out is LAN-only + double-sends to selected controller. Favorites silently skip if participation set empty. |
| **Schedule** | COMPLETE | Create/edit/delete + WLED timer cfg push + sunrise/sunset real. ⚠️ Hard cap **8 timers** (`schedule_sync.dart:62`), not 20 as CLAUDE.md claims (~4 schedules w/ off-times). Single-controller only. #TD-1 clobber race pending. |
| **Current Colors editor** | COMPLETE* | Swatches/HSV/apply/save real. ❌ **Hidden gap:** writes single `id:0` seg only (`current_colors_provider.dart:296`) — ignores channel selector on multi-bus installs. |
| **Manage Controllers** | COMPLETE | List/add/rename/delete/set-active + re-sync config. No stubs. |
| **Hardware Config + System Mgmt** | COMPLETE | 8-port editor, structural-vs-count detection, manual fallback. ❌ `getConfig` null over relay → degraded off-LAN. |
| **Zone Configuration** | PARTIAL | Actually a *segment* editor mislabeled "Zones." Commercial multi-controller zone targeting **unwired** (`site_providers.dart:168` "until a Zone selector exists… fallback to all controllers"). |
| **Preferred Whites** | COMPLETE | Onboarding + settings, live preview, custom RGBW. Single-controller. |
| **Explore / Pattern Library** | COMPLETE | Browse/search/preview/apply real, multi-channel filtered. Boundary-blend caveat (pal:5 path). |
| **Edit Pattern** | COMPLETE | Live preview + save-as-WLED-preset real. STATIC mode uses crisp i-array; animated path uses pal:5. |
| **Scenes** | PARTIAL | Full CRUD service exists but **no routed UI** — only surfaces via My Designs/AI/voice. `applyScene` skips channel filter. |
| **AI Design Studio** | PARTIAL | Compose + **Save to My Designs** real (apply-from-designs works). ❌ **"Apply to Lights" hard-disabled "coming soon"** (`ai_design_studio_screen.dart:309`, firmware-gated). ❌ **Misleading "Live preview / Preview on lights: ON" toggle has zero device side-effects** (`design_studio_providers.dart:54`). Two divergent payload builders, both flawed (single-seg, RGB-only / fx:83 substitution). |
| **Lumina AI chat** | PARTIAL | Rich 2-tier router; power/brightness/color/effect/scene/team/holiday/schedule commands reach device. ❌ **Apply bypasses channel filter → bus-0 only** on multi-bus sites. |
| **Audio Reactive** | COMPLETE* | Control surface real (capability-gated, effect select, sensitivity). Reactivity is WLED-hardware-side (on-screen bars decorative). Release-gated on dashboard. Bus-0 only. Orphan dup file `audio/screens/audio_reactive_screen.dart`. |
| **Game Day** | COMPLETE | Team CRUD, multi-channel fixed (channel-2 skip resolved via `game_day_apply.dart:88`), background autopilot via Cloud Function (works off-WiFi). ⚠️ **"Leave Crew" is a no-op** (`game_day_screen.dart:1254` — `leaveCrew()` never called). `hostDisplayName` hardcoded "My House". Motion-style slider storage-only (TODO v1.0.1). |
| **Sports Alerts** | PARTIAL/BROKEN | UI + **Test Alert work** (multi-channel/multi-controller). ❌ **Real app-closed score celebration is INERT:** `updateControllerIps()` has zero callers → background isolate iterates empty IP list (`sports_background_service.dart:101,177`); iOS path explicitly `const []`. Only the notification fires, no LEDs. |
| **Neighborhood Sync** | COMPLETE* | Live-propagation fix wired app-level (`main.dart:298-320`), teardown priority real. ⚠️ **Both homes must run new build**; Tyler+Ellie device-verify pending. Legacy `_applyPostEventBehavior` stub (debugPrint-only) — confirm unreachable. Pixel-count from manual `rooflineMeters` default. |
| **Autopilot** | PARTIAL | Scheduler/calendar/reveal/suggestions real. ❌ **Weekly-preview "Looks good" bulk-approve is a dead stub** (`autopilot_weekly_preview.dart:252` `_approveItem` debugPrint-only). Weather input placeholder (`autopilot_schedule_generator.dart:237`). |
| **Geofence** | COMPLETE* | Setup/monitor/enter-trigger real. ⚠️ **No native background geofence** — uses position stream, only fires while app alive (dialog copy over-promises "even when closed"). Local-WiFi only. Single-channel party fallback. |

---

## 2. Account / onboarding / settings / remote

| Feature | Status | Notes |
|---|---|---|
| **Auth** (login/signup/forgot/forced-reset/join-code/link/staff-PIN) | COMPLETE | All real Firebase. ⚠️ Requires **Anonymous Auth enabled in Console** (staff PIN + installer account creation depend on it). |
| **Onboarding / first-run** | COMPLETE | Two parallel flows (welcome wizard + first-run) — redundant but functional. mDNS + subnet-scan real (fabricated under `kSimulationMode=true`). |
| **BLE device setup / provisioning** | COMPLETE | Real Improv-over-BLE; fabricates IP under simulation/web — real path release-on-device only. |
| **Profile / Security / Help** | COMPLETE | Reauth-gated password change + account deletion real. |
| **Lumina Studio** | COMPLETE | Lead-gen quote builder (writes `studio_requests` + mailto), not e-commerce despite "Store" label. |
| **Remote Diagnostics (Pro)** | STUBBED | `settings_page.dart:419` — fake spinner returns hardcoded "Success. Ref ID: #8821." No upload. **Hide for v1.** |
| **Sub-Users** | PARTIAL | Invite/revoke/resend real. ❌ **Granular permissions non-functional** — every invitee hardcoded `SubUserPermissions.full` (enforcement layer never built, `sub_users_screen.dart:276`). |
| **Properties (multi-home)** | COMPLETE | Full CRUD, controller link/unlink, primary enforcement. Genuinely multi-property. |
| **Remote Access + Bridge** | COMPLETE | Bridge + webhook modes, 3-step pair wizard, health checks, hijack protection — robust. |
| **Voice Assistants** | STUBBED | ⚠️ **Looks complete (badges, Link buttons) but no fulfillment backend.** Google Home config is literal placeholder (`google_home_service.dart:32` `…/000000YOUR_PROJECT_ID`), action package stale. No OAuth/directive handler/Cloud Function exists. "Linked" unreachable; no command would route. Siri (native shortcuts) is the only working part. **Mark Alexa/Google "coming soon."** |
| **Referrals** | COMPLETE | Code assignment, tiers, tracking, payouts, SMS share — real. |

---

## 3. Staff / back-office (PIN-gated — NOT consumer-v1; can ship behind staff PIN or hide)

**Installer & Sales modes — largely COMPLETE, real Firestore persistence:**
- Installer landing/PIN, 7-step setup wizard (real account creation + controller migration), handoff (live controller verify), media mode (View-As) — all COMPLETE.
- Sales: landing/visit flow, 5-step estimate wizard (per-channel ChannelRun capture), jobs + service, Day1/Day2 dispatch + blueprints + wrap-up — all COMPLETE.
- Gaps: **`queuePaymentReminder()` writes to `/email_notifications` with no server consumer** (`sales_job_service.dart:144`) — accumulates, never dispatches. Inventory dashboard Sections 2/3/5 are honest `_StubCard` "bridge required" (`inventory_dashboard_screen.dart:78-128`). **Two stale comments** wrongly claim stubs that are actually built (`day1_queue_screen.dart:21`, `day2_wrap_up_screen.dart:46`).

**Corporate / Admin / Inventory / Payouts — COMPLETE & reachable via staff path:**
- Corporate dashboard (5 tabs), admin (dealer/installer mgmt, brand library), corporate inventory (warehouse/PO/receive/catalog), referral payouts — all real with batched Firestore writes + Cloud Functions.
- ❌ **4 orphaned dealer-inventory screens** (`inventory/dealer/*`, confirms memory #41): code-complete but unreachable — push to unregistered routes `/inventory/order`, `/inventory/auto-reorder`; no code constructs them. The reachable dealer surface is the *different* `InventoryDashboardScreen`. Dead-code-pass candidate.
- Non-blocking TODOs: Shippo API (`order_screen.dart:782`), ready-to-ship notifications.

---

## 4. Commercial mode — built ~80%, but DARK in normal flow

**Reachability blocker:** Phase 3a removed the commercial redirect (`route_guards.dart:245`). All users land on `/dashboard`. **The entire commercial shell (Home/Fleet/Schedule/Events) is reachable ONLY by typing `/commercial` directly** — no in-app entry, no "Switch to Commercial" in Settings.

| Feature | Status | Reachable? |
|---|---|---|
| Commercial Home shell | PARTIAL | No (direct URL only) |
| Fleet Dashboard | PARTIAL — **faked lastSync** (`FleetDashboardScreen.dart:320`), naive online heuristic (never pings), 3 TODO mini-actions (schedule/edit/override), **placeholder hardcoded schedule list** in push wizard | No |
| Commercial Schedule | PARTIAL — undo/drag/edit/design-picker are TODOs; gap-assign needs raw Design ID typed | No |
| Onboarding Wizard | COMPLETE code | **No caller** (memory #28). Traps the ONLY channel-role + day-part editors. |
| Brand Search/Setup | COMPLETE | via Home (unreachable) / admin |
| **Brand Corrections** | COMPLETE | **Yes** (via Corporate Admin staff path) |
| Events/Sales | COMPLETE code | No (tab in unreachable Home) |
| Daylight/ESPN services + channel_role model | COMPLETE logic | **Config UI trapped in unreachable wizard** — channel_roles/teams/daylight/manager_email ship with no post-install editor (memory #33). |

**Biggest "looks done but hidden":** commercial mode is mostly functional but gated off entirely. Ship recommendation: **mark Commercial Mode "coming soon"** except Brand Corrections (reachable/complete).

---

## 5. Demo Experience — COMPLETE & reachable (the cleanest cluster)

`lib/features/demo/` — code → welcome → profile → photo → roofline → completion all wired (`login_page.dart:489` entry). Real dealer-code gate, lead capture, Apple-review bypass (`demo_code_screen.dart:89`, guideline 5.1.1), conversion form writing leads. No stubs. Ship.

---

## 6. Recommended v1 ship-scope actions

**Ship as-is:** Home, Schedule, Manage Controllers, Hardware Config, System Mgmt, Preferred Whites, Explore, Edit Pattern, Properties, Remote Access/Bridge, Auth, Onboarding, BLE setup, Referrals, Demo, Brand Corrections.

**Fix before ship (cheap, high-impact):**
- Wire channel filter into Lumina AI apply + Current Colors editor (bus-0-only bug on multi-bus sites).
- Wire `updateControllerIps()` for Sports Alerts background, OR mark real-game celebration "coming soon."
- Wire or hide Game Day "Leave Crew" no-op; wire or hide Autopilot weekly bulk-approve.

**Mark "coming soon" / hide for v1:**
- AI Design Studio "Apply to Lights" (already disabled) + remove/relabel the fake live-preview toggle.
- Voice Assistants (Alexa/Google) — no backend.
- Remote Diagnostics (Pro) — fake upload.
- Sub-user granular permissions (ship all-or-nothing).
- Commercial Mode (except Brand Corrections).
- Audio Mode dashboard tile (already release-gated).

**Set expectations in copy:** Geofence is app-alive-only (not true background); Schedule cap is 8 timers.

**Housekeeping:** reconcile 3 version strings; delete/route the 4 orphaned dealer-inventory screens; fix 2 stale "stub" comments in Day1/Day2; confirm Anonymous Auth enabled in Firebase Console.
