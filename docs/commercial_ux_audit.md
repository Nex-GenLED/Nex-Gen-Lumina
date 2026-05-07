# Commercial UX Audit — Lumina

**Date**: 2026-05-06
**Scope**: Full inventory of commercial-mode surfaces, providers, routes, and branching decisions. Synthesizes findings against the architectural target Tyler set: **"commercial = residential + capabilities"** — commercial customers should land on the residential home as their primary experience and reach commercial capabilities through additive surfaces (settings menu, commercial-tools sections), NOT through a parallel commercial dashboard.

**Status**: Read-only audit. Document is uncommitted — pending Tyler review before any phase begins.

**Companion memory items**: [#28 — CommercialOnboardingWizard unreachable](../memory/project_commercial_onboarding_unreachable.md) · [#29 — Commercial onboarding silently broken pre-2026-05-06](../memory/project_commercial_onboarding_silently_broken.md) · [#30 — Commercial UX architectural rework (stub)](../memory/project_commercial_ux_architectural_rework.md)

---

## 1. Executive Summary

**What's broken.** Commercial mode in Lumina is implemented as a **parallel dashboard** rather than an additive overlay. When `profile_type == 'commercial'` AND a `commercial_locations` doc exists, the route guard at [route_guards.dart:266](../lib/route_guards.dart#L266) redirects all `/dashboard` traffic to `/commercial`, where users land on `CommercialHomeScreen` — a separate Scaffold with its own bottom-nav (5 or 6 tabs), its own schedule UI (`CommercialScheduleScreen`), its own profile editor (`BusinessProfileEditScreen`), and its own home dashboard logic. The residential `WledDashboardPage` is unreachable from this state. Settings access (sign-out, account management, residential conveniences) lives on the residential side only, leaving commercial users without a path to standard account operations.

The brand library, sales/events, day-parts, daylight suppression, smart fill, and fleet dashboard are all commercial-only surfaces. Some are correctly capability-gated (corporate push, game day automation). Most are arbitrarily locked to commercial mode for cosmetic reasons (zone management is a one-line `mode == SiteMode.commercial` check; the underlying `zonesProvider` is mode-agnostic).

**What the target is.** Commercial customers should boot into the same `WledDashboardPage` residential customers use. Commercial-specific capabilities — schedule day-parts, brand library, sales/events, fleet view, sub-user team permissions — are reachable from a "Commercial Tools" surface (a settings-menu section, a Pro features card, a tab visible only to commercial users). Account-type identity should drive feature *visibility*, not navigation forks.

**How big the workstream is.** Six phases, sequenced. Audit categorizes 31 distinct surfaces/providers/decisions into A/B/C/D buckets:
- **A (keep as-is)**: 4 items — admin moderation surfaces, corporate push, game day automation
- **B (migrate to additive)**: 12 items — sales/events, brand library customer flow, day-parts, daylight suppression, smart fill, fleet view, sub-user team permissions, manager fields
- **C (fold into residential)**: 6 items — schedule merge, profile editor merge, zone-management gate removal, commercial mode detection collapsing into single home, sub-user base
- **D (remove entirely)**: 4 items — `CommercialHomeScreen` as parallel shell, route-guard `/commercial` redirect, Pro Tier banner, `CommercialOnboardingWizard` as 8-step (replace with short conversion flow)

Plus 5 unexpected findings worth their own consideration (duplicate write paths, missing post-install UIs for existing data models, smoke-test references to UIs that don't exist).

The structural change (Phase 3 — route commercial users to residential home) is the load-bearing piece. Everything else cascades from that decision.

---

## 2. Inventory

### 2.1 Screen inventory

#### Commercial-only screens (parallel-dashboard surfaces)

| File | Class | What it does | Reached from | Residential parallel? |
|---|---|---|---|---|
| [lib/screens/commercial/CommercialHomeScreen.dart](../lib/screens/commercial/CommercialHomeScreen.dart#L35) | `CommercialHomeScreen` | Entry point for commercial mode; conditional shell — single-location (5 tabs: Dashboard / Schedule / Brand / Events / Profile) or multi-location (6 tabs, adds Fleet) | Route guard redirect on `/dashboard` when `profile_type == 'commercial'` AND `commercial_locations` doc exists | ✅ `WledDashboardPage` ([lib/features/dashboard/wled_dashboard_page.dart](../lib/features/dashboard/wled_dashboard_page.dart)) — the residential home, currently unreachable for commercial users |
| [lib/screens/commercial/schedule/CommercialScheduleScreen.dart](../lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L52) | `CommercialScheduleScreen` | 7-day timeline with day-part blocks, quick-actions, corporate-lock banner, holiday conflicts | Tab in `CommercialHomeScreen` | ✅ `MySchedulePage` ([lib/features/schedule/my_schedule_page.dart](../lib/features/schedule/my_schedule_page.dart)) — diverged implementation |
| [lib/screens/commercial/profile/BusinessProfileEditScreen.dart](../lib/screens/commercial/profile/BusinessProfileEditScreen.dart#L14) | `BusinessProfileEditScreen` | Edit business name/address/type, view brand colors (read-only), pre/post buffers, observe holidays. Pro-tier banner | Tab in `CommercialHomeScreen` | ⚠️ Partial — `EditProfileScreen` ([lib/features/site/edit_profile_screen.dart](../lib/features/site/edit_profile_screen.dart)) handles residential profile but the field overlap is only partial |
| [lib/screens/commercial/fleet/FleetDashboardScreen.dart](../lib/screens/commercial/fleet/FleetDashboardScreen.dart#L137) | `FleetDashboardScreen` | Multi-location list/map with status filters, sort modes, corporate-admin push FAB, pro-tier banner | Tab in multi-location `CommercialHomeScreen` shell, gated on `commercial_permission_level` | ❌ None |

#### Commercial onboarding wizard (unreachable today)

| File | Class | What it does | Reached from | Residential parallel? |
|---|---|---|---|---|
| [lib/screens/commercial/onboarding/commercial_onboarding_wizard.dart](../lib/screens/commercial/onboarding/commercial_onboarding_wizard.dart#L19) | `CommercialOnboardingWizard` | 8-step wizard: Business Type → Brand Identity → Hours → Channels → Teams → Day-Parts → Multi-Location → Review | **❌ NOT REACHED** — see [Item #28](../memory/project_commercial_onboarding_unreachable.md). Route registered, no caller | ❌ |
| [.../business_type_screen.dart](../lib/screens/commercial/onboarding/screens/business_type_screen.dart) | `BusinessTypeScreen` | Step 1 | Internal step | ❌ |
| [.../brand_identity_screen.dart](../lib/screens/commercial/onboarding/screens/brand_identity_screen.dart) | `BrandIdentityScreen` | Step 2 (with brand-library search Path 1, manual Path 2) | Internal step | ❌ |
| [.../hours_of_operation_screen.dart](../lib/screens/commercial/onboarding/screens/hours_of_operation_screen.dart) | `HoursOfOperationScreen` | Step 3 | Internal step | ❌ |
| [.../channel_setup_screen.dart](../lib/screens/commercial/onboarding/screens/channel_setup_screen.dart) | `ChannelSetupScreen` | Step 4 (assigns channel roles + daylight suppression) | Internal step | ❌ |
| [.../your_teams_screen.dart](../lib/screens/commercial/onboarding/screens/your_teams_screen.dart) | `YourTeamsScreen` | Step 5 (sports teams, alert config) | Internal step | ❌ |
| [.../day_part_config_screen.dart](../lib/screens/commercial/onboarding/screens/day_part_config_screen.dart) | `DayPartConfigScreen` | Step 6 (day-parts auto-generated, editable) | Internal step | ❌ |
| [.../multi_location_screen.dart](../lib/screens/commercial/onboarding/screens/multi_location_screen.dart) | `MultiLocationScreen` | Step 7 (placeholder; skip-only today) | Internal step | ❌ |
| [.../review_go_live_screen.dart](../lib/screens/commercial/onboarding/screens/review_go_live_screen.dart#L16) | `ReviewGoLiveScreen` | Step 8 — atomic batch write (user doc + commercial_locations/primary + brand_profile), redirects to `/commercial` | Internal step | ❌ |

#### Brand library surfaces

| File | Class | What it does | Reached from | Residential parallel? |
|---|---|---|---|---|
| [lib/features/commercial/brand/brand_search_screen.dart](../lib/features/commercial/brand/brand_search_screen.dart#L27) | `BrandSearchScreen` | Search `/brand_library` by name + industry filter | `CommercialHomeScreen` Brand tab CTA, or `BrandIdentityScreen` Path 1 | ❌ |
| [lib/features/commercial/brand/brand_setup_screen.dart](../lib/features/commercial/brand/brand_setup_screen.dart#L32) | `BrandSetupScreen` | Manually define brand profile or admin-edit a library entry (admin gated) | `CommercialHomeScreen`, `BrandSearchScreen` (pre-selected), onboarding `BrandIdentityScreen`, admin dashboard | ❌ |
| [lib/features/installer/admin/brand_library_admin_screen.dart](../lib/features/installer/admin/brand_library_admin_screen.dart#L35) | `BrandLibraryAdminScreen` | Admin CRUD against `/brand_library` (search + industry filter + per-row edit + custom-design count badge) | Admin dashboard, staff PIN | Admin-only |
| [lib/features/commercial/brand/brand_correction_review_screen.dart](../lib/features/commercial/brand/brand_correction_review_screen.dart#L30) | `BrandCorrectionReviewScreen` | Admin moderation of `/brand_library_corrections` (approve/reject user color fixes) | Admin dashboard | Admin-only |

#### Sales & events

| File | Class | What it does | Reached from | Residential parallel? |
|---|---|---|---|---|
| [lib/features/commercial/events/events_screen.dart](../lib/features/commercial/events/events_screen.dart#L22) | `EventsScreen` | "Sales & Events" tab — active/upcoming/past events, banner with apply/view, FAB | `CommercialHomeScreen` Events tab | ❌ |
| [lib/features/commercial/events/create_event_screen.dart](../lib/features/commercial/events/create_event_screen.dart#L23) | `CreateEventScreen` | 5-step event wizard (name/date → channels → design → review) | `CommercialHomeScreen` quick action, `EventsScreen` FAB | ❌ |

#### Commercial-only embedded UI (not standalone screens)

From `CommercialHomeScreen`: `_DashboardTab`, `_ActiveEventBanner`, `_QuickActionsSection` (2x2 grid: Brand Default / Event Mode / New Event / Lumina AI), `_BrandTab`, `_BrandHeaderCard`, `_BrandColorsRow`, `_BrandDesignCard`, `_BrandSetupCta`, `_NowPlayingSection`, `_ControllerStatusPill`, `_CommercialBottomNav`.
From `CommercialScheduleScreen`: `_CorporateLockBanner`, day-part timeline blocks, holiday-conflict warnings.
From `FleetDashboardScreen`: `_ViewToggle` (list/map), `_FilterSheet` (status filters), `_LocationStatusPill`.

### 2.2 Provider/state inventory

#### Commercial mode detection & switching ([commercial_mode_providers.dart](../lib/screens/commercial/commercial_mode_providers.dart))

| Symbol | Type | What it manages |
|---|---|---|
| [`commercialModeEnabledProvider`](../lib/screens/commercial/commercial_mode_providers.dart#L17) | FutureProvider<bool> | Profile-level commercial check — checks local prefs override, then `profile_type == 'commercial'`, then `commercial_locations` existence |
| [`hasCommercialProfileProvider`](../lib/screens/commercial/commercial_mode_providers.dart#L59) | FutureProvider<bool> | "Has user ever set up a commercial profile?" — used to gate "Switch to Commercial Mode" affordance in Settings |
| [`isMultiLocationProvider`](../lib/screens/commercial/commercial_mode_providers.dart#L77) | FutureProvider<bool> | 2+ commercial_locations docs — drives single-loc vs. fleet-shell branch |
| [`commercialUserRoleProvider`](../lib/screens/commercial/commercial_mode_providers.dart#L93) | FutureProvider<CommercialRole?> | Highest-rank role across locations (storeStaff/storeManager/corporateAdmin/regionalManager) |
| [`commercialOrgProvider`](../lib/screens/commercial/commercial_mode_providers.dart#L127) | FutureProvider<CommercialOrganization?> | User's org doc (multi-location only) |
| [`primaryCommercialLocationProvider`](../lib/screens/commercial/commercial_mode_providers.dart#L151) | FutureProvider<CommercialLocation?> | First/primary location for display |
| [`setCommercialModeOverride()`](../lib/screens/commercial/commercial_mode_providers.dart#L179) | Function | Writes `commercial_mode_override` to SharedPreferences + Firestore |
| [`clearModeOverride()`](../lib/screens/commercial/commercial_mode_providers.dart#L197) | Function | Clears local + remote override |

#### Onboarding draft state

| Symbol | Type | What it manages |
|---|---|---|
| [`commercialOnboardingProvider`](../lib/screens/commercial/onboarding/commercial_onboarding_state.dart#L176) | NotifierProvider | 8-step wizard draft (businessType, businessName, brandColors, weeklySchedule, channelConfigs, teams, dayParts, etc.) — in-memory only |
| [`commercialOnboardingStepProvider`](../lib/screens/commercial/onboarding/commercial_onboarding_state.dart#L181) | StateProvider<int> | Current PageView step index |

#### Home/schedule/fleet local state

| Symbol | Type | Where | What it manages |
|---|---|---|---|
| `_commercialTabProvider` | StateProvider<int> | `CommercialHomeScreen` | Selected tab index |
| `_selectedDayProvider` | StateProvider<DayOfWeek> | `CommercialScheduleScreen` | Day-of-week selector |
| `_workingScheduleProvider` | StateProvider<CommercialSchedule?> | `CommercialScheduleScreen` | Optimistic schedule edits before write-behind |
| `_channelConfigsProvider` | StateProvider<List<ChannelRoleConfig>> | `CommercialScheduleScreen` | Channel configs (read from Firestore) |
| `_businessHoursProvider` | StateProvider<BusinessHours?> | `CommercialScheduleScreen` | Open times, closed days, buffers |
| `_holidayCalendarProvider` | StateProvider<HolidayCalendar?> | `CommercialScheduleScreen` | Holiday cal |
| `_userRoleProvider` | StateProvider<CommercialRole?> | `CommercialScheduleScreen` | Role at this location (edit permission gating) |
| `_quickActionsExpandedProvider` | StateProvider<bool> | `CommercialScheduleScreen` | Collapsed/expanded panel |
| `_fleetViewModeProvider` | StateProvider<_FleetViewMode> | `FleetDashboardScreen` | List vs. map |
| `_sortModeProvider` | StateProvider<_SortMode> | `FleetDashboardScreen` | Sort (alpha / status / region) |
| `_filterProvider` | StateProvider<_StatusFilter> | `FleetDashboardScreen` | Status filter checkboxes |
| `_locationsStreamProvider` | StreamProvider.family | `FleetDashboardScreen` | Locations from `users/{uid}/commercial_locations` |
| `_schedulesStreamProvider` | StreamProvider | `FleetDashboardScreen` | All schedules across org |

#### Brand library & events ([brand_library_providers.dart](../lib/services/commercial/brand_library_providers.dart), [commercial_events_providers.dart](../lib/services/commercial/commercial_events_providers.dart))

| Symbol | Type | What it manages |
|---|---|---|
| [`commercialBrandProfileProvider`](../lib/services/commercial/brand_library_providers.dart#L109) | StreamProvider<CommercialBrandProfile?> | User's `brand_profile/brand` doc |
| [`searchBrandsProvider`](../lib/services/commercial/brand_library_providers.dart#L31) | StreamProvider.family | Filtered library search results |
| [`selectedBrandProvider`](../lib/services/commercial/brand_library_providers.dart#L169) | StateProvider | Currently selected library entry |
| [`allBrandsProvider`](../lib/services/commercial/brand_library_providers.dart#L65) | StreamProvider | Full library list (admin) |
| [`isUserRoleAdminProvider`](../lib/services/commercial/brand_library_providers.dart#L83) | FutureProvider<bool> | Admin gate |
| [`commercialEventsProvider`](../lib/services/commercial/commercial_events_providers.dart#L13) | StreamProvider | All events for user's locations |
| (derived) `activeCommercialEventProvider` / `upcomingCommercialEventsProvider` / `pastCommercialEventsProvider` | (referenced in `events_screen.dart` but not explicitly declared) | Filters of `commercialEventsProvider` |

### 2.3 Route inventory

#### Commercial routes ([app_router.dart](../lib/app_router.dart))

| AppRoutes constant | Path | Screen | Reached? | Entry points |
|---|---|---|---|---|
| `commercialHome` | `/commercial` | `CommercialHomeScreen` | ✅ | Route guard redirect ([route_guards.dart:280](../lib/route_guards.dart#L280)); `ReviewGoLiveScreen` post-onboarding ([line 181](../lib/screens/commercial/onboarding/screens/review_go_live_screen.dart#L181)). No "Switch to Commercial Mode" entry from residential Settings |
| `commercialOnboarding` | `/commercial/onboarding` | `CommercialOnboardingWizard` | **❌** | **No caller** — Item #28. Installer wizard writes data directly, bypassing |
| `commercialBrandSearch` | `/commercial/brand/search` | `BrandSearchScreen` | ✅ | `CommercialHomeScreen` Brand tab CTA, `BrandIdentityScreen` |
| `commercialBrandSetup` | `/commercial/brand/setup` | `BrandSetupScreen` | ✅ | `CommercialHomeScreen`, `BrandSearchScreen`, onboarding, admin dashboard |
| `commercialBrandCorrections` | `/commercial/brand/corrections` | `BrandCorrectionReviewScreen` | ✅ | Admin |
| `commercialEvents` | `/commercial/events` | `EventsScreen` | ✅ | Tab in `CommercialHomeScreen`, banner button |
| `commercialEventsCreate` | `/commercial/events/create` | `CreateEventScreen` | ✅ | Dashboard quick-action, Events FAB, brand-search card tap |

#### Route-guard branching on commercial signals ([route_guards.dart:246-285](../lib/route_guards.dart#L246-L285))

Reads in order: SharedPreferences `commercial_mode_override` → Firestore `profile_type == 'commercial'` → `commercial_locations` existence. If all pass, redirect `/dashboard` → `/commercial`.

This is the **load-bearing architectural decision**. Removing or rewriting this branch is the central act of Phase 3.

### 2.4 `profile_type` / `siteMode` read inventory

#### "Core experience" decisions (architectural — should unify to residential)

| File:line | Branch | What it does |
|---|---|---|
| [route_guards.dart:266](../lib/route_guards.dart#L266) | `profile_type == 'commercial'` | Redirects `/dashboard` to `/commercial` (parallel dashboard fork) |
| [commercial_mode_providers.dart:41](../lib/screens/commercial/commercial_mode_providers.dart#L41) | `profile_type == 'commercial'` | Drives `commercialModeEnabledProvider` — gates which home shell renders |
| [installer_setup_wizard.dart:679 (post-fix)](../lib/features/installer/installer_setup_wizard.dart#L679) | `siteMode == SiteMode.commercial ? 'commercial' : 'residential'` | Resolves account type at install time |

#### "Capability" decisions (legitimate forks for additional features)

| File:line | Branch | What it does |
|---|---|---|
| [installer_setup_wizard.dart:701](../lib/features/installer/installer_setup_wizard.dart#L701) | `siteMode == SiteMode.commercial ? 20 : 5` | Sub-user limit cap |
| [handoff_screen.dart:111](../lib/features/installer/handoff_screen.dart#L111) | `_profileType == 'commercial'` | Show manager-email field |
| [installer_setup_wizard.dart:683](../lib/features/installer/installer_setup_wizard.dart#L683) | `siteMode == SiteMode.residential` vs. commercial | Branches `system_config` schema (linkedControllerIds vs. zones) |
| [commercial_mode_providers.dart:179-192](../lib/screens/commercial/commercial_mode_providers.dart#L179-L192) | `setCommercialModeOverride(bool)` | Mode-switch write surface (commercial-only function) |

#### Cosmetic/dual-signal decisions (broken — should be unified)

| File:line | Branch | What's wrong |
|---|---|---|
| [zone_configuration_screen.dart:28, 64, 75, 86, 96](../lib/features/installer/screens/zone_configuration_screen.dart#L96) | `siteMode` toggle in zone-config screen | **Signal A** in the Item #30 dual-signal pattern |
| [handoff_screen.dart:27, 409, 598](../lib/features/installer/handoff_screen.dart#L27) | `_profileType` card selection in handoff | **Signal B** in the Item #30 dual-signal pattern. Tactical fix in commit `62ff50d` reconciles at write boundary; UI consolidation pending |
| [settings_page.dart:91-94](../lib/features/site/settings_page.dart#L91-L94) | `mode == SiteMode.commercial` | Hides Zones card from residential users — but the underlying providers and code paths are mode-agnostic. Cosmetic gate |

### 2.5 Feature inventory

| Feature | Files | Status |
|---|---|---|
| **Sales & Events** | [events_screen.dart](../lib/features/commercial/events/events_screen.dart), [create_event_screen.dart](../lib/features/commercial/events/create_event_screen.dart), [commercial_events_providers.dart](../lib/services/commercial/commercial_events_providers.dart) | Commercial-only tab + 5-step wizard. Stores to `commercial_events/{locationId}/{eventId}` |
| **Brand Library (customer)** | [brand_search_screen.dart](../lib/features/commercial/brand/brand_search_screen.dart), [brand_setup_screen.dart](../lib/features/commercial/brand/brand_setup_screen.dart), [brand_design_generator.dart](../lib/features/commercial/brand/brand_design_generator.dart) | Search global library + manual setup + auto-generate 5 canonical designs |
| **Brand Library (admin)** | [brand_library_admin_screen.dart](../lib/features/installer/admin/brand_library_admin_screen.dart), [brand_correction_review_screen.dart](../lib/features/commercial/brand/brand_correction_review_screen.dart) | Admin CRUD + correction moderation |
| **Zone Management** | `_buildZonesSection` in [settings_page.dart:91-94](../lib/features/site/settings_page.dart#L91-L94), [site_providers.dart](../lib/features/site/site_providers.dart) | Card visibility gated on commercial; underlying logic mode-agnostic |
| **Sub-User Management** | [sub_users_screen.dart](../lib/features/users/sub_users_screen.dart), `commercial_teams` / `channel_roles` / `commercial_permission_level` fields on user doc | Residential and commercial share invite UI; commercial team-permission UI is **missing** despite data model existing |
| **Manager-specific fields** | `manager_email`, `commercial_permission_level`, `commercial_teams`, `channel_roles` on user doc | Written at install (handoff) or onboarding; **no post-install UI** to edit |
| **Day-Parts** | [day_part_scheduler_service.dart](../lib/services/commercial/day_part_scheduler_service.dart), [day_part.dart](../lib/models/commercial/day_part.dart), `DayPartConfigScreen` (onboarding), `CommercialScheduleScreen` (timeline) | Time-window subdivisions auto-generated from hours; commercial-only |
| **Daylight Suppression** | [daylight_suppression_service.dart](../lib/services/commercial/daylight_suppression_service.dart), [daylight_brightness_modifier.dart](../lib/services/commercial/daylight_brightness_modifier.dart), `ChannelSetupScreen` (onboarding) | Outdoor channels auto-dim during daylight; no post-install UI to adjust |
| **Game Day Mode** | [game_day_service.dart](../lib/services/commercial/game_day_service.dart), [commercial_espn_service.dart](../lib/services/commercial/commercial_espn_service.dart), [commercial_team.dart](../lib/models/commercial/commercial_team.dart) | Service exists and polls ESPN; **UI integration incomplete** (no game-day badge surfaced in screens despite smoke test referencing one) |
| **Corporate Push** | [corporate_push_service.dart](../lib/services/commercial/corporate_push_service.dart) | Service exists; **no UI** (smoke test references "Push FAB" and "Manage Locks" that don't exist in code) |
| **Pro Tier Banner** | [commercial_pro_banner.dart](../lib/widgets/commercial/commercial_pro_banner.dart) | Inconsistent visibility rules across screens; no monetization tier exists |
| **Smart Fill** | [CommercialScheduleScreen.dart](../lib/screens/commercial/schedule/CommercialScheduleScreen.dart), `smartFillPolicy` field | Schedule gap auto-fill; commercial-only |

---

## 3. Decision matrix

Every surface, provider, feature, and branching decision categorized:
- **(A) Keep as-is** — correctly commercial-only; doesn't need restructuring
- **(B) Migrate to additive** — should be reachable from settings menu / commercial-tools section overlaid on residential UI
- **(C) Fold into residential UI** — should just BE the residential equivalent (or the residential equivalent extended)
- **(D) Remove entirely** — built but redundant or misguided

### 3.1 Screens

| Item | Bucket | Rationale |
|---|---|---|
| `CommercialHomeScreen` | **D** | Parallel dashboard, not an overlay. The architectural error in concrete form. Replace by routing to `WledDashboardPage` with conditional commercial overlays |
| `CommercialScheduleScreen` | **C** | Schedule is core experience; merge into `MySchedulePage` with day-part complexity hidden by default (opt-in advanced UI) |
| `BusinessProfileEditScreen` | **C** | Profile editing exists in both worlds; merge into single editor with conditional commercial fields (business type, manager email) |
| `FleetDashboardScreen` | **B** | Multi-location view is genuinely useful; should live as a "Locations" tab/section accessible from residential dashboard for users with multiple locations |
| `BrandSearchScreen` | **B** | Brand library customer flow should be reachable from residential Settings as a Pro feature, not locked behind commercial home |
| `BrandSetupScreen` | **B** | Same |
| `BrandLibraryAdminScreen` | **A** | Admin-only, correctly separate |
| `BrandCorrectionReviewScreen` | **A** | Admin-only, correctly separate |
| `EventsScreen` | **B** | Sales/events as Pro feature card on residential dashboard |
| `CreateEventScreen` | **B** | Same |
| `CommercialOnboardingWizard` (8-step) | **D** (then rebuild) | Currently unreachable. Replace with short "Switch to Commercial Mode" flow in Settings (name + address + type + commercial_locations stub). Keep 8-step as optional advanced setup if needed |

### 3.2 Providers

| Item | Bucket | Rationale |
|---|---|---|
| `commercialModeEnabledProvider` | **C** (repurpose) | Keep the provider; stop using it to fork between two home shells. Use it for feature-visibility gating inside one shell |
| `hasCommercialProfileProvider` | **B** | Useful for "Switch to Commercial Mode" affordance |
| `isMultiLocationProvider` | **B** | Repurpose to gate Fleet tab visibility within residential dashboard |
| `commercialUserRoleProvider` | **C** | Unify into single permission system spanning residential and commercial |
| `primaryCommercialLocationProvider` | **A** | Data-layer provider; keep |
| `commercialOrgProvider` | **A** | Data-layer provider; keep |
| `commercialBrandProfileProvider`, `commercialEventsProvider` | **A** | Pure data providers; keep but make accessible from residential UI |
| Onboarding state (`commercialOnboardingProvider`, `commercialOnboardingStepProvider`) | **D** (with wizard) | Tied to the 8-step wizard. If wizard is replaced with short flow, these go too |

### 3.3 Routes

| Item | Bucket | Rationale |
|---|---|---|
| `/commercial` (`CommercialHomeScreen`) | **D** | Remove parallel dashboard; route guard sends commercial users to `/dashboard` like everyone else |
| `/commercial/onboarding` | **D** | Unreachable. Remove or rewire to short flow |
| `/commercial/brand/search`, `/commercial/brand/setup` | **B** | Keep routes; just make them reachable from residential Settings instead of (only) commercial home |
| `/commercial/brand/corrections` | **A** | Admin |
| `/commercial/events`, `/commercial/events/create` | **B** | Keep routes; reach from residential dashboard's "Pro Tools" section |
| Route guard `profile_type == 'commercial'` redirect | **D** | The architectural error itself. Remove the redirect; treat `profile_type` as feature-visibility flag instead of routing key |

### 3.4 Features

| Item | Bucket | Rationale |
|---|---|---|
| Sales & Events | **B** | Pro feature surface accessible from residential |
| Brand Library (customer) | **B** | Brand profile setup as Pro feature |
| Brand Library (admin) | **A** | Admin |
| Zone Management | **C** | Remove `mode == SiteMode.commercial` cosmetic gate; show always |
| Sub-User Management (base) | **C** | Already shared between modes; commercial team-permission UI is **B** (additive) on top |
| Day-Parts | **B** | Optional residential schedule advanced feature |
| Daylight Suppression | **B** | Optional residential channel config |
| Game Day Mode | **A** | Commercial-specific automation (incomplete UI; flag separately) |
| Corporate Push | **A** | Multi-location admin feature (incomplete UI; flag separately) |
| Pro Tier Banner | **D** | No monetization tier exists; remove or rebuild data-driven |
| Smart Fill | **B** | Useful in residential schedule |

### 3.5 Branching decisions

| Item | Bucket | Rationale |
|---|---|---|
| `profile_type == 'commercial'` route-guard fork | **D** | Remove; use as visibility flag |
| `siteMode` / `_profileType` dual-signal in installer wizard | **C** (consolidate) | Item #30 strategic fix — collapse to one decision point |
| `mode == SiteMode.commercial` zone-section gate | **C** | Remove gate |
| `isMultiLoc && role == corporateAdmin/regionalManager` for Fleet | **B** | Move to residential dashboard tab visibility gate |

### 3.6 Bucket totals

| Bucket | Count | Items |
|---|---|---|
| **A — Keep as-is** | 7 | Admin brand library, admin corrections, primary location provider, org provider, brand/events data providers, game day, corporate push |
| **B — Migrate to additive** | 12 | Fleet, brand search, brand setup, sales/events screens, sales/events feature, brand library customer feature, day-parts, daylight suppression, smart fill, hasCommercialProfileProvider, isMultiLocationProvider, sub-user team-permission UI, brand routes, events routes |
| **C — Fold into residential** | 8 | Schedule merge, profile editor merge, zone-section gate removal, sub-user base, commercialModeEnabledProvider repurpose, commercialUserRoleProvider unification, dual-signal consolidation |
| **D — Remove entirely** | 7 | CommercialHomeScreen shell, CommercialOnboardingWizard 8-step, route-guard `/commercial` redirect, Pro Tier banner, onboarding state providers, `/commercial/onboarding` route, `/commercial` route + dashboard fork |

---

## 4. Phase plan (audit-grounded)

Tyler's six-phase outline, with audit findings mapped per phase and re-scoping where the audit surfaces additional work.

### Phase 1 — Audit (this document)

Done. Output is this file.

### Phase 2 — Settings access for commercial users

**Original scope**: sign-out, profile management, etc.

**Audit-grounded scope**:
- Add "Switch to Commercial Mode" affordance in residential Settings — gated on `hasCommercialProfileProvider == false || profile_type != 'commercial'`. Triggers a short conversion flow (writes `profile_type`, `commercial_mode_override`, stub `commercial_locations/primary`) — NOT the 8-step wizard.
- Add "Switch to Residential Mode" affordance in commercial Settings — calls `clearModeOverride()` + `setCommercialModeOverride(false)`.
- Verify residential Settings (sign-out, edit profile, manage family members, system management) is reachable from commercial users — currently `BusinessProfileEditScreen` is the only profile surface they have.

**Audit re-scoping**: Phase 2 is small and unblocks Phase 3. Do it first, even before deciding on the full Phase 3 architecture, because exposing settings to commercial users is correct regardless of what happens to `CommercialHomeScreen`.

### Phase 3 — Route commercial customers to residential home as primary

**Original scope**: commercial dashboard becomes accessible-but-secondary.

**Audit-grounded scope**:
- Remove or refactor [route_guards.dart:266-281](../lib/route_guards.dart#L266-L281) so `profile_type == 'commercial'` no longer redirects to `/commercial`. Both modes land on `/dashboard` (`WledDashboardPage`).
- Add commercial-aware overlays on `WledDashboardPage`:
  - "Pro Tools" or "Commercial" section in the home dashboard (event banner if active, brand-default quick action, etc.).
  - Optional: keep `/commercial` route reachable as a secondary "Commercial Dashboard" view from a settings menu link (defer or remove).
- This is the load-bearing change. Everything else cascades from this decision.

**Audit re-scoping**: Phase 3 is the single biggest piece of work. Should be split into 3a (route guard removal + verify residential home loads for commercial users) and 3b (overlay surfaces — event banner, brand-default action). 3a is small and high-leverage; 3b is iterative.

### Phase 4 — Migrate commercial-only features to additive surfaces

**Original scope**: Sales & Events, Brand Library access, Zones, Sub-users into settings/menu surfaces.

**Audit-grounded scope (per feature)**:
- **Sales & Events**: Add "Events" tab or card to residential dashboard for commercial users. `EventsScreen` reachable from there.
- **Brand Library**: Add "Brand Profile" entry in residential Settings (gated on commercial). `BrandSearchScreen` and `BrandSetupScreen` reachable from there.
- **Zone Management**: Remove the `mode == SiteMode.commercial` gate on `_buildZonesSection`. Always show.
- **Sub-Users**: Existing `SubUsersScreen` already shared. Add commercial team-permission UI as an additive section (see Phase 5).
- **Day-Parts, Daylight Suppression, Smart Fill**: Surface in `MySchedulePage` and `SystemManagementScreen` as advanced/opt-in toggles. May require schedule-model changes (optional `dayParts` field).
- **Fleet Dashboard**: Add as a "Locations" tab visible to multi-location commercial users.

**Audit re-scoping**: Phase 4 is broader than expected. Worth splitting into 4a (Brand + Events — single-screen migrations), 4b (Zone gate removal + sub-user team UI), 4c (schedule advanced features — day-parts, smart fill), 4d (channel config advanced features — daylight suppression). Each can be its own commit.

### Phase 5 — Sub-user permissions implementation

**Original scope**: Item #23 from open items.

**Audit-grounded scope**:
- Build the missing post-install UI for `commercial_teams` and `channel_roles` (data model exists, no UI to add/edit teams or channel roles after onboarding).
- Add team-permission gating in `SubUsersScreen` for commercial users — assign sub-users to specific channels, set roles per channel.
- Verify Firestore rules permit commercial users to read/write team docs.

**Audit re-scoping**: Phase 5 is more than just sub-user permissions — it's "build the missing UI for data models that already ship in commercial accounts." Includes channel-role management and team management as well.

### Phase 6 — Cleanup and deprecation

**Original scope**: cleanup of unused commercial UI.

**Audit-grounded scope**:
- Delete `CommercialHomeScreen` (after Phase 3 is stable and no callers remain).
- Delete `CommercialScheduleScreen` after merge with `MySchedulePage`.
- Delete `BusinessProfileEditScreen` after merge with `EditProfileScreen`.
- Delete unused commercial routes (`/commercial`, `/commercial/onboarding` if not rewired).
- Remove Pro Tier Banner.
- Defer until Phases 1–5 are stable. Cleanup is the last act, not the first.

**Audit re-scoping**: This phase should explicitly include "consolidate the two atomic-batch write paths" — the canonical `ReviewGoLiveScreen._goLive()` and the installer-wizard commercial branch both write the same shape. Extract into a shared `CommercialAccountService.activateCommercialMode()` to avoid divergence.

---

## 5. Risk assessment

### Phase 2 (Settings access)

- **Test surface**: Residential settings page must remain stable. Adding "Switch to Commercial Mode" entry adds one menu item — low regression risk.
- **Data model**: None.
- **Firestore rules**: None.
- **Customer-facing**: Commercial users gain access to standard settings (sign-out, edit profile). No removal of existing affordances. Pure additive.

### Phase 3 (Route to residential home)

- **Test surface**: The biggest regression risk in the workstream. Every commercial-only surface that lived behind `CommercialHomeScreen` must continue to function when accessed via the additive surfaces in Phase 4. Until Phase 4 lands, commercial users would lose access to brand setup, events, fleet view if Phase 3 ships alone.
- **Data model**: None directly. But: `commercial_mode_override` flag becomes less load-bearing — verify it still works as a manual override.
- **Firestore rules**: None. The route-guard change is client-side only.
- **Customer-facing**: Big change. No commercial customers in production yet, so this is hypothetical. Onboarding flow (CommercialOnboardingWizard ReviewGoLiveScreen) currently calls `context.go('/commercial')` — must be rewired to `/dashboard` or to the new commercial-tools section.

### Phase 4 (Migrate features to additive)

- **Test surface**: Residential home dashboard must not break when new commercial-aware tabs/cards are added. Settings page must accommodate new entries without overflow. Schedule page must not regress when day-part UI is overlaid.
- **Data model**:
  - User model: `commercial_profile`, `manager_email`, `channel_roles`, `commercial_teams`, `commercial_permission_level` already exist. No new fields.
  - Schedule model: Residential schedules don't currently have day-parts. Optional `dayParts` field needed to support day-parts in residential context (null = no day-parts, default residential behavior).
- **Firestore rules**: Need to verify residential users with `commercial_mode_override` can read/write commercial-feature docs (events, brand_profile). May need rule extension if currently gated on `profile_type == 'commercial'` strictly.
- **Customer-facing**: Residential users (current production users) start seeing "Pro Feature" cards / sections they haven't seen before. UI gate: only render if `hasCommercialProfileProvider == true` to avoid noise for pure-residential users.

### Phase 5 (Sub-user permissions)

- **Test surface**: `SubUsersScreen` must continue to work for residential. Adding commercial team-permission UI shouldn't regress invite flow.
- **Data model**: `commercial_teams`, `channel_roles` already exist on user doc. Verify rules permit reads/writes.
- **Firestore rules**: Likely need rule additions for sub-user team assignments. Verify against Item #29 pattern (atomic batch + missing rule = silent rollback).
- **Customer-facing**: New UI for an existing feature. Commercial customers gain self-service control.

### Phase 6 (Cleanup)

- **Test surface**: Highest. Deleting code paths that may still be referenced. Need full smoke-test pass before each deletion.
- **Data model**: None directly.
- **Firestore rules**: None.
- **Customer-facing**: Theoretical. By Phase 6, no commercial users should be on `CommercialHomeScreen` shell.

---

## 6. Recommended sequencing

**Recommended order**: Phase 2 → Phase 3a (route-guard removal) → Phase 4a (Brand + Events migration as additive) → Phase 3b (commercial overlays on residential home) → Phase 4b (zones + sub-user UI) → Phase 5 (sub-user team permissions) → Phase 4c+4d (advanced schedule + channel features) → Phase 6 (cleanup).

**Rationale**:
- **Phase 2 first** because it's small, safe, and lets commercial users (Steve, Diamond Family in 2 weeks) reach standard settings even if the rest of the work is months out.
- **Phase 3a before Phase 4a** because removing the route-guard fork forces the broken state visible — commercial users land on residential home, see their brand/events are missing, and we know exactly what Phase 4 must fix. If we stage Phase 4 first, it's harder to know which migrations actually matter.
- **Phase 3b interleaved** with Phase 4 because the overlays on residential home (event banner, brand-default quick action) are exactly the surfaces being migrated.
- **Phase 5 after** the structural changes settle. Building UI for missing data models is independent of the architectural question, but easier on stable ground.
- **Phase 6 last** — cleanup is bookkeeping. Defer until at least one commercial customer has lived on the new architecture.

**Alternative (more conservative)**: Tyler's original 2 → 3 → 4 → 5 → 6 ordering is also defensible. The trade-off: doing Phase 4 fully before Phase 3 means commercial users never lose access (since CommercialHomeScreen is still the home), but we end up duplicating UI for a longer window. Doing Phase 3 first means a brief gap where commercial users have reduced functionality, but the gap forces Phase 4 to be precise.

---

## 7. Open questions for Tyler

Before Phase 2 begins, the following decisions need resolution:

### Q1 — `CommercialOnboardingWizard` fate

Three options:
1. **Keep as-is**, add an entry point in residential Settings ("Switch to Commercial Mode" → 8-step wizard). High UX cost (8 steps for a setting toggle).
2. **Replace with short flow** in residential Settings (name + address + type + minimum data), keep 8-step wizard available for installer flow only or remove entirely. Lower UX cost; matches "additive overlay" architecture.
3. **Remove entirely**, rely on installer-driven setup (commit `62ff50d` already writes everything needed). Lowest code surface; assumes installers handle 100% of commercial conversions.

**Audit recommendation**: Option 2 (short flow). The 8-step wizard captures business hours, channel configs, teams, day-parts — all of which can be configured post-install via the additive surfaces in Phase 4. Front-loading them in a wizard is friction.

### Q2 — Pro Tier banner / monetization

The Pro Tier banner appears on `FleetDashboardScreen`, `CommercialScheduleScreen`, `BusinessProfileEditScreen`, and `ReviewGoLiveScreen` with inconsistent dismiss rules. Smoke test references it as a real feature. But no monetization tier exists.

**Question**: Is monetization planned in the near term (within this re-architecture window)? If yes, banner should be data-driven (read tier from user doc, conditionally show). If no, banner should be removed.

**Audit recommendation**: Remove. Re-introduce data-driven if/when tiers ship.

### Q3 — Multi-location commercial customers (Fleet Dashboard)

`FleetDashboardScreen` is gated on `isMultiLocationProvider && commercialUserRoleProvider in [corporateAdmin, regionalManager]`. The audit categorizes it as **B (migrate to additive)** — surface as a "Locations" tab on residential dashboard for multi-location users.

**Question**: Are multi-location customers a near-term priority? If yes, Phase 4 should prioritize Fleet migration. If no (single-location dominant for the foreseeable customer pipeline), defer Fleet work to Phase 6+ and remove `FleetDashboardScreen` from the migration scope until needed.

**Audit recommendation**: Defer Fleet migration until first multi-location customer is in the pipeline. None today (Steve, Diamond Family are both single-location).

---

## 8. Unexpected findings (potential new memory items)

The audit surfaced 5+ items that don't fit the inventory/decision-matrix structure but are worth surfacing as standalone follow-ups.

### F1 — Two atomic-batch write paths can create commercial accounts

[`ReviewGoLiveScreen._goLive()`](../lib/screens/commercial/onboarding/screens/review_go_live_screen.dart#L113-L124) (canonical wizard) and the installer wizard's commercial branch (commit `62ff50d`, [installer_setup_wizard.dart:819-871](../lib/features/installer/installer_setup_wizard.dart#L819-L871)) both write the same shape: user doc with `profile_type`, `commercial_mode_enabled`, `commercial_mode_override` + `commercial_locations/primary` doc + brand profile. **Risk of divergence** if one is updated without the other.

**Suggested**: Extract into `CommercialAccountService.activateCommercialMode(userId, ...)` shared between paths. Makes Phase 6 cleanup easier and reduces drift risk. **Suggested as Item #31**.

### F2 — Missing post-install UIs for shipped data models

The user doc carries `commercial_teams`, `channel_roles`, `commercial_permission_level`, `manager_email`, plus daylight-suppression config on channels. **None of these are editable post-install** — they're set during onboarding (or via installer handoff for `manager_email`) and then frozen. A commercial user who wants to add a team, change a channel role, or update their digest email has no in-app path.

**Suggested**: Phase 5 expands beyond sub-user permissions to "build post-install UIs for all commercial data models that ship today." **Suggested as Item #32**.

### F3 — Smoke test references UI that doesn't exist

[docs/commercial_mode_smoke_test.md](commercial_mode_smoke_test.md) sections 6–9 walk through Game Day badge, scoring alerts, Corporate Push FAB, lock enforcement, and "Manage Locks" overflow menu. Code search found the **service layer** ([game_day_service.dart](../lib/services/commercial/game_day_service.dart), [corporate_push_service.dart](../lib/services/commercial/corporate_push_service.dart)) but **no corresponding UI**. Either the smoke test is aspirational, or feature work was started and abandoned mid-flight.

**Suggested**: Reconcile smoke test with code. Either remove un-built sections from smoke test, or schedule UI work to fill the gaps. **Suggested as Item #33**.

### F4 — Brand profile is on user doc, not location doc

`brand_profile/brand` lives at `/users/{uid}/brand_profile/brand`, not on each location. Correct for single-brand multi-location (one company, multiple locations, same brand), but doesn't support per-location brand variation (franchisee with location-specific colors). Note for future architectural reference; not actionable today.

### F5 — Derived providers are referenced but not defined

[events_screen.dart](../lib/features/commercial/events/events_screen.dart) watches `activeCommercialEventProvider`, `upcomingCommercialEventsProvider`, `pastCommercialEventsProvider` — none defined in [commercial_events_providers.dart](../lib/services/commercial/commercial_events_providers.dart). They're presumably computed inline in the screen. Defining them explicitly makes the filtering logic discoverable and testable. Minor cleanup, no blocking impact.

### F6 — Items #11, #17, #26 referenced but not in memory

Tyler's prompt mentioned these as audit-relevant. None exist as memory files in `C:/Users/honey/.claude/projects/c--Flutter-Projects-Lumina-V-1-6/memory/`. Either they're documented elsewhere, exist in another session's memory not synced here, or the numbers were placeholder. Worth confirming before Phase 2.

---

## Appendix — Inventory totals

- Commercial-specific screens: **18** (4 parallel-dashboard + 9 onboarding sub-steps + 4 brand surfaces + 1 events + 2 admin)
- Commercial-only embedded UI components: **~14** (cards, sections, sheets in CommercialHomeScreen / CommercialScheduleScreen / FleetDashboardScreen)
- Riverpod providers (commercial-named): **~18**
- Routes under `/commercial`: **7**
- profile_type / siteMode reads outside model serialization: **~13**
- Commercial-only feature areas: **12** (Sales/Events, Brand Library customer, Brand Library admin, Zones, Sub-Users, Manager fields, Day-Parts, Daylight, Game Day, Corporate Push, Pro Banner, Smart Fill)
- Distinct decision-matrix items: **31** (categorized A/B/C/D above)

**Bucket totals**:
- A: 7
- B: 12
- C: 8
- D: 7
