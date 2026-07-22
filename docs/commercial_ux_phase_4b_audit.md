# Phase 4b Audit — Zone Management & Sub-User UI as Business Tools Entries

**Date:** 2026-05-06
**Branch:** `feature/commercial-ux-rework`
**Scope:** Read-only inventory + decision matrix for Phase 4b (extending the Phase 4a "Business Tools" sub-list with two additional entries: **Zone Management** and **Sub-User Management**)
**Status:** Inventory + recommendation only. No implementation. Open questions block scope finalization.

This document is the structural sibling of [`commercial_ux_phase_4a_decisions.md`](commercial_ux_phase_4a_decisions.md). Phase 4a established the `BusinessToolsScreen` sub-list pattern for Brand library + Events; this audit determines whether and how Zones and Sub-Users join that sub-list, what permission model gaps exist, and whether the sub-list itself needs structural rework as it grows.

---

## 1. Architectural Inheritance from Phase 4a

Phase 4a locked the following constraints that this audit must respect:

- **Pattern X**: single "Business Tools" card on residential `settings_page.dart`, gated by `isCommercialProfileProvider`, opens `BusinessToolsScreen` sub-list.
- **Reuse-first**: existing screens are reused as-is unless genuinely broken; no restyling of internal commercial screens.
- **Residential glass/cyan styling** for the sub-list and any Phase 4-era new surfaces.
- **No discovery hint** for residential customers — card simply doesn't render.
- **`/commercial/...` routes preserved** through Phase 4-5 for diagnostic comparison; retired Phase 6.

Phase 4b cannot violate these. Any tension surfaces as an open question, not a decision.

---

## 2. Zone Management Inventory

Zones in this codebase have two semantically-overlapping but technically-distinct meanings:

1. **Site-level zones** (`ZoneModel` in [`site_models.dart:27`](../lib/features/site/site_models.dart#L27)) — multi-controller groups for **Commercial mode** only, with primary IP, member IPs, DDP sync flag/port. Used by `_buildZonesSection` in settings page.
2. **Bus-level channels** (`DeviceChannel` in [`zone_providers.dart:57`](../lib/features/wled/zone_providers.dart#L57)) — derived from hardware buses on a single controller, used by every customer regardless of mode (channel filter, channel selector bar). Despite the file name "zone_providers.dart", these are **not** what `ZoneModel` describes.
3. **Segment-level zone assignments** (`ZoneAssignment` in [`zone_assignment.dart`](../lib/features/zones/models/zone_assignment.dart)) — fixture-type tagging stored in `SharedPreferences` (not Firestore). Used by `ZoneSetupScreen` for fixture metadata.
4. **Sales-pipeline zones** (`InstallZone` referenced in [`zone_builder_screen.dart`](../lib/features/sales/screens/zone_builder_screen.dart)) — sales/quoting model, not a customer surface.

The Phase 4b "Zone Management" entry must be specific about which of these it surfaces. (See open question Q3.)

### 2.1 Zone surfaces

| #  | File:line | Screen / widget / provider | Purpose | Reachable from | Audience |
|----|-----------|----------------------------|---------|----------------|----------|
| 1  | [`settings_page.dart:91-94, 100-232`](../lib/features/site/settings_page.dart#L91) | `_buildZonesSection` (inline in `_SettingsPageState`) | Inline zone CRUD + member IP entry + DDP sync toggle/port + Apply button | Settings page, conditional on `mode == SiteMode.commercial` | Customer (commercial only) |
| 2  | [`zone_configuration_page.dart:10`](../lib/features/wled/zone_configuration_page.dart#L10) | `ZoneConfigurationPage` | "My Lighting Areas" — segment-list with checkbox selection, rename, Design Studio promo, Hardware config link. Operates on `WledSegment`, not `ZoneModel`. | Route `/wled/zones` (`AppRoutes.wledZones`); registered in System branch ([`app_router.dart:1069`](../lib/app_router.dart#L1069)) | Customer (all modes) |
| 3  | [`zone_setup_screen.dart:11`](../lib/features/zones/screens/zone_setup_screen.dart#L11) | `ZoneSetupScreen` | "Zone & Fixture Setup" — assigns `FixtureType` to each segment (rooflineRail, flushLandscape, etc.), label + persistence to SharedPreferences | Route `AppRoutes.zoneSetup` = `/installer/zone-setup` ([`app_router.dart:389`](../lib/app_router.dart#L389), [`app_router.dart:1229`](../lib/app_router.dart#L1229)) | **Installer** (route lives under `/installer/...`) |
| 4  | [`installer_setup_wizard.dart`](../lib/features/installer/installer_setup_wizard.dart) → [`zone_configuration_screen.dart:10`](../lib/features/installer/screens/zone_configuration_screen.dart#L10) | `ZoneConfigurationScreen` (installer wizard step) | Step 3 of installer wizard — branches on `installerSiteModeProvider`: residential = link controllers, commercial = create zones with primary controller validation | Inside installer wizard only | Installer |
| 5  | [`site_models.dart:27`](../lib/features/site/site_models.dart#L27) | `ZoneModel` | Site-level zone data class: name, primaryIp, members, ddpSyncEnabled, ddpPort | n/a (model) | n/a |
| 6  | [`site_providers.dart:66-103`](../lib/features/site/site_providers.dart#L66) | `ZonesNotifier` + `zonesProvider` | In-memory zone CRUD (NotifierProvider, no persistence to Firestore) | Read by `_buildZonesSection`, installer wizard | n/a |
| 7  | [`site_providers.dart:107-140`](../lib/features/site/site_providers.dart#L107) | `DDPSyncController` + `ddpSyncControllerProvider` | Issues DDP/UDP sync configuration to primary + secondary controllers via WLED HTTP | Settings page Apply button | n/a |
| 8  | [`zone_providers.dart:75-89`](../lib/features/wled/zone_providers.dart#L75) | `deviceChannelsProvider` | Derives `DeviceChannel` list from hardware buses (different concept — bus channels, not commercial zones) | ChannelSelectorBar, channel-filtered commands | All customers |
| 9  | [`zone_providers.dart:96`](../lib/features/wled/zone_providers.dart#L96) | `selectedChannelIdsProvider` | Channel filter state (per CLAUDE.md — different concept) | All channel-filtered surfaces | All customers |
| 10 | [`zone_providers.dart:46`](../lib/features/wled/zone_providers.dart#L46) | `zoneSegmentsProvider` | Polls WLED `/json/state` for segment list | `ZoneConfigurationPage`, `ZoneSetupScreen` | n/a |
| 11 | [`zone_config_service.dart:11`](../lib/features/zones/services/zone_config_service.dart#L11) | `ZoneConfigService` | SharedPreferences-backed `ZoneAssignment` persistence (segment → fixture type) | `ZoneSetupScreen` | Customer |
| 12 | [`zone_assignment.dart`](../lib/features/zones/models/zone_assignment.dart) | `ZoneAssignment` model | Maps `segmentId` → `FixtureType` + locationLabel | n/a | n/a |
| 13 | [`zone_adjustment_card.dart`](../lib/features/ai/zone_adjustment_card.dart) | `ZoneAdjustmentCard` (AI) | Lumina AI card for adjusting zone parameters via chat | AI chat | Customer |
| 14 | [`zone_assignment_screen.dart`](../lib/features/sports_alerts/ui/zone_assignment_screen.dart) | Sports alerts zone-channel mapping | Maps team → channel/zone for sports alerts | Sports alerts feature | Customer |
| 15 | [`local_command_parser.dart:76`](../lib/features/ai/local_command_parser.dart#L76) | AI route hint `'zones': '/wled/zones'` | AI can deep-link to zones config | AI command parser | Customer |
| 16 | [`installer_providers.dart`](../lib/features/installer/installer_providers.dart) | `installerZonesProvider`, `installerSiteModeProvider`, `installerLinkedControllersProvider` | Installer wizard's transient zone draft state | Installer wizard | Installer |
| 17 | [`installation_model.dart:66`](../lib/models/installation_model.dart#L66) | `Installation.systemConfig` (`Map<String, dynamic>?`) | Installer-time zone snapshot stored on installation doc | Read by installation rehydration | Admin/installer |

### 2.2 Zone-related Firestore footprint

- `ZoneModel` is **not currently persisted to Firestore** as a typed document. `ZonesNotifier` is in-memory only. Zone configuration that survives app restart lives inside `installations/{id}.system_config` as opaque map.
- `ZoneAssignment` (fixture metadata) is in **SharedPreferences**, device-local only. No multi-device sync.
- `selectedChannelIdsProvider` (channel filter) is in-memory `StateProvider`, ephemeral.

This means today's "zones" have no persistent customer-facing source of truth that survives reinstall. Phase 4b's "Zone management" entry will surface ephemeral state unless persistence is added — out of scope here, but flagged.

### 2.3 Audience split

- **Customer-facing zone management exists in two places** today: `_buildZonesSection` in `settings_page.dart` (commercial only) and `ZoneConfigurationPage` at `/wled/zones` (all modes — but framed as "My Lighting Areas," not "zones").
- **Installer-facing zone management exists in three places**: `ZoneConfigurationScreen` (wizard step), `ZoneSetupScreen` at `/installer/zone-setup`, and the sales `ZoneBuilderScreen`.
- The customer-installer divide is enforced by route-prefix convention (`/installer/...`) and by gating logic in `installerModeActiveProvider`. Phase 4b must not pull installer surfaces into the customer Business Tools sub-list without re-framing them.

---

## 3. Sub-User Management Inventory

The sub-user system is the most complete piece of inventory in this audit — model, service, screen, route, rules, and an active acceptance flow all exist.

### 3.1 Sub-user surfaces

| #  | File:line | Screen / widget / provider | Purpose | Reachable from | Audience |
|----|-----------|----------------------------|---------|----------------|----------|
| 1  | [`sub_users_screen.dart:18`](../lib/features/users/sub_users_screen.dart#L18) | `SubUsersScreen` (titled "Manage Users") | List sub-users, count vs `max_sub_users`, FAB to invite, pending invites with resend/revoke | Route `/settings/users` ([`app_router.dart:1207`](../lib/app_router.dart#L1207)) registered in System branch ([`app_router.dart:1029-1034`](../lib/app_router.dart#L1029)) | Primary user (residential or commercial) |
| 2  | [`user_profile_screen.dart:53-59`](../lib/features/site/user_profile_screen.dart#L53) | "Manage Family Members" tile | Conditional on `model.installationId != null`; pushes `AppRoutes.subUsers` | Settings → My Profile → tile | Primary user |
| 3  | [`sub_user_permissions.dart:5`](../lib/models/sub_user_permissions.dart#L5) | `SubUserPermissions` model | 5 boolean flags: `canControl`, `canChangePatterns`, `canEditSchedules`, `canInvite`, `canAccessSettings` + presets `basic`/`full`/`viewOnly` | n/a | n/a |
| 4  | [`invitation_model.dart:48`](../lib/models/invitation_model.dart#L48) | `Invitation` model | Token (6-char alphanumeric, no 0/O/1/I/l), `installationId`, `primaryUserId`, `inviteeEmail`, `expiresAt` (default 7d), status enum, embedded `SubUserPermissions` | n/a | n/a |
| 5  | [`invitation_service.dart:13`](../lib/services/invitation_service.dart#L13) | `InvitationService` | createInvitation, acceptInvitation (transactional), revokeAccess, revokeInvitation, resendInvitation, updatePermissions, streams | DI via `invitationServiceProvider` | n/a |
| 6  | [`invitation_service.dart:294`](../lib/services/invitation_service.dart#L294) | `invitationServiceProvider`, [`:299`](../lib/services/invitation_service.dart#L299) `pendingInvitationsProvider`, [`:333`](../lib/services/invitation_service.dart#L333) `subUsersProvider` | Riverpod plumbing | Sub-users screen | n/a |
| 7  | [`invitation_service.dart:305`](../lib/services/invitation_service.dart#L305) | `SubUser` display model | id, email, name, linkedAt, permissions | Sub-users screen | n/a |
| 8  | [`join_with_code_screen.dart:16`](../lib/features/auth/join_with_code_screen.dart#L16) | `JoinWithCodeScreen` | 6-char invitation code entry; calls `acceptInvitation`; sets installation_role='subUser' on user doc | Route `/join-with-code` ([`app_router.dart:1205`](../lib/app_router.dart#L1205)) | Invitee (any signed-in user) |
| 9  | [`installation_model.dart:56`](../lib/models/installation_model.dart#L56) | `Installation.maxSubUsers` (5 residential / 20 commercial per docstring) | Cap | Read at invite time | n/a |
| 10 | [`user_model.dart:226-247`](../lib/models/user_model.dart#L226) | `UserModel.installationId`, `installationRole`, `primaryUserId`, `linkedAt`, `subUserPermissions`, `invitationToken` | Sub-user state on user doc | All screens reading user model | n/a |
| 11 | [`firestore.rules:712-719`](../firestore.rules#L712) | Rules for `/installations/{id}/subUsers/{uid}` | Read: anyone in installation. Write: primary user or admin | n/a | n/a |
| 12 | [`firestore.rules:725-753`](../firestore.rules#L725) | Rules for `/invitations/{id}` | Read: primary user, invitee-by-email, admin. Create: primary user. Update: invitee or primary. Delete: primary | n/a | n/a |

### 3.2 Sub-user Firestore footprint

- `/installations/{installationId}/subUsers/{userId}` — `linked_at`, `permissions`, `invited_by`, `invitation_token`, `user_email`, `user_name`. Created transactionally with user-doc update on accept.
- `/invitations/{invitationId}` — root collection, queryable by token + status. 6-char tokens with day-based expiry. Status: `pending`/`accepted`/`expired`/`revoked`.
- `/users/{uid}` mirror fields: `installation_role`, `installation_id`, `primary_user_id`, `invitation_token`, `linked_at`, `sub_user_permissions`.

The sub-user system is a complete vertical slice. It works today, has an entry point (Profile → Manage Family Members), and has matching Firestore rules.

---

## 4. Permission Model Audit

Two parallel permission systems exist. Phase 4b must clarify which is authoritative for commercial sub-users.

### 4.1 Residential sub-user permissions (`SubUserPermissions`)

- **5 flat booleans**: `canControl`, `canChangePatterns`, `canEditSchedules`, `canInvite`, `canAccessSettings`.
- **3 presets**: `basic` (control + patterns), `full` (everything), `viewOnly` (nothing).
- **Storage**: embedded in invitation, mirrored in `users/{uid}.sub_user_permissions` and `installations/{id}/subUsers/{uid}.permissions`.
- **Enforcement**: rules-level only on the install-doc + invitation flows. Per-feature enforcement at the UI layer is **not visible in this inventory** — i.e. there's no widget gate that reads `canEditSchedules` and hides the schedule editor. (See open question Q5.)

### 4.2 Commercial role permissions (`CommercialRole`)

- **4 roles**: `storeStaff`, `storeManager`, `regionalManager`, `corporateAdmin` ([`commercial_role.dart:1`](../lib/models/commercial/commercial_role.dart#L1)).
- **9 permission keys** per role: `canViewOwnLocation`, `canEditOwnSchedule`, `canOverrideNow`, `canViewAllLocations`, `canPushToRegion`, `canPushToAll`, `canApplyCorporateLock`, `canManageUsers`, `canEditBrandColors`.
- **Storage**: `users/{uid}.commercial_permission_level` (legacy 3-tier values: `'store_staff'` | `'store_manager'` | `'corporate_admin'` per [`commercial_mode_providers.dart:103`](../lib/screens/commercial/commercial_mode_providers.dart#L103)). Note the **mismatch** between the 4-role enum and the 3-string persistence layer — `regionalManager` has no string mapping today.
- **Resolved by**: `commercialUserRoleProvider` ([`commercial_mode_providers.dart:93`](../lib/screens/commercial/commercial_mode_providers.dart#L93)).
- **Enforcement**: pseudo-rules documented as comments in [`commercial_permissions_service.dart:1-80`](../lib/services/commercial/commercial_permissions_service.dart#L1) but **not deployed** to `firestore.rules` (the rules file mentions installations + invitations but not the location/channel hierarchy described in the service comment block). This is a deployment gap distinct from the rule-deploy memory item ([Item #29](../memory/MEMORY.md), #31).

### 4.3 Gap analysis for tier-2 commercial sub-users

If a tier-2 commercial customer (Steve's Blue Line Bar, Diamond Family Jewelers) wants to share access with a bartender, manager, or owner today:

- **Available mechanism**: `SubUserPermissions` via the residential invitation flow.
- **Vocabulary mismatch**: the screen says "Family Members," presets are `basic`/`full`/`viewOnly`, permissions are residential-flavored (patterns, schedules). No "bartender" / "manager" / "owner" presets.
- **Granularity mismatch**: residential permissions are global (`canEditSchedules` is one bit). Commercial roles imply per-zone or per-feature granularity (`canPushToRegion`, `canApplyCorporateLock`).
- **Persistence mismatch**: `commercial_permission_level` is set at user-doc level (single value per user, not per-installation). `SubUserPermissions` is per-installation. A user could have inconsistent values.
- **Enforcement mismatch**: residential `SubUserPermissions` has no UI gating; commercial `CommercialRole.permissions` has documented rules-level enforcement that isn't deployed.
- **The 4-role enum vs 3-string persistence** is a latent bug — `CommercialRole.regionalManager` is unreachable from Firestore data.

**Gap level: substantial.** A tier-2 sub-user UI cannot ship without making at least one of these decisions:
1. Use residential `SubUserPermissions` with renamed presets ("Bartender" = basic, "Manager" = full minus invite, "Owner" = full). Cheapest path. Loses commercial-role granularity.
2. Surface `commercial_permission_level` in the invite flow — but it's a user-doc field, not invitation-embedded. Requires schema work.
3. Build a unified permission model that subsumes both. Foundation work; out of Phase 4b scope.

### 4.4 Firestore rules coverage

- **Sub-users + invitations**: covered, deployed, working ([`firestore.rules:695-753`](../firestore.rules#L695)).
- **Commercial role gating**: documented but undeployed (the comment block in `commercial_permissions_service.dart` describes rules that aren't in `firestore.rules`).
- **Brand library + commercial events** (Phase 4a entries): per Phase 4a audit, already permissive enough.

No new rules needed for Phase 4b's read paths if it reuses the existing sub-user infrastructure. New rules would be needed only if Phase 4b introduces commercial-role-aware writes at the location/channel level.

---

## 5. Phase 4b Decision Matrix

For each candidate Business Tools sub-list entry, four options: **Reuse-as-is** / **Reuse-with-shell** / **Rebuild** / **Defer**.

### 5.1 Zone Management

| Option | What it means | Pros | Cons | Verdict |
|--------|---------------|------|------|---------|
| **Reuse-as-is** (link to `_buildZonesSection`) | Add an entry that scrolls to the existing inline section | Zero new code | Section is buried inside settings page, not extractable as a screen, IP-entry UX is installer-flavored, depends on `mode == SiteMode.commercial` toggle that Phase 3a already destabilized | Reject |
| **Reuse-with-shell** (extract `_buildZonesSection` into a `ZoneManagementScreen`) | Pull the existing widget logic into a standalone screen, route it from sub-list | Code already works; aligns with Pattern X; scopes the IP-entry UX to a dedicated surface | Still surfaces installer-flavored fields (raw IPs, DDP port). Customer self-service may need restyling. The data is in-memory only — survives a session, not a reinstall. | **Recommended (with caveats)** |
| **Rebuild** | New customer-facing zone screen with friendly affordances | Best customer UX | Significant work; redundant with installer-time zone setup; no clear customer-self-service use case articulated yet | Defer |
| **Defer** | No Zone entry in 4b; revisit in Phase 5 once Item #33 fields ship UIs | Smallest scope; lets Phase 4b focus purely on Sub-Users | Leaves a known gap; the inline `_buildZonesSection` is still in `settings_page.dart` cluttering the universal residential settings | Reasonable fallback |

**Recommendation: Reuse-with-shell, conditional on Q1+Q3 answers.** Extract `_buildZonesSection` into `ZoneManagementScreen`, route from Business Tools sub-list. **Remove** the inline section from `settings_page.dart` (it's already commercial-conditional, so removing it doesn't regress residential UX, and consolidates a duplicate surface). If Tyler's answer to Q3 is "this is installer territory, not customer," **Defer** instead.

### 5.2 Sub-User Management

| Option | What it means | Pros | Cons | Verdict |
|--------|---------------|------|------|---------|
| **Reuse-as-is** (link to existing `/settings/users`) | Add a Business Tools entry that pushes the same `SubUsersScreen` already reachable from Profile | Zero rewrite, screen works today, complete data model | Vocabulary is residential-flavored ("Family Members"), permissions are residential presets. May confuse commercial customers. Two entry points for the same screen. | **Recommended for Phase 4b ship-fast path** |
| **Reuse-with-shell** (commercial wrapper that retitles + relabels presets) | Wrap `SubUsersScreen` with a commercial-titled scaffold ("Manage Team Members") and override preset labels | Retains data model, polishes vocabulary | Preset relabeling requires either a constructor parameter or a duplicated screen. Two concepts in one — fragile. | Reasonable |
| **Rebuild** (new commercial team-management screen) | Dedicated commercial flow with bartender/manager/owner roles, per-channel scoping | Best commercial fit | Substantial — requires resolving §4.3 gap (which permission model wins), schema work for role persistence, possibly new Firestore rules. Not Phase 4b scope. | Defer to Phase 5 |
| **Defer** | No Sub-User entry in 4b | Smallest scope | Wastes the existing complete vertical slice; commercial customers already on `/settings/users` via Profile | Reject |

**Recommendation: Reuse-as-is for Phase 4b; rebuild deferred to Phase 5.** Add Business Tools sub-list entry that routes to `/settings/users` (same screen, same providers). Phase 5 owns the role-vocabulary rebuild after permission-model questions are resolved. Document that the Profile entry stays during 4b for residential parity (residential primary users still need it).

---

## 6. Pattern X Sub-list Growth

After Phase 4a: 2 entries (Brand library, Events).
After Phase 4b: 4 entries (Brand library, Events, Zones, Sub-Users).
Anticipated Phase 5 additions (per [Item #33](../memory/MEMORY.md)): manager email, day-parts editor, channel-roles editor, commercial teams editor — potentially 4 more entries.

### 6.1 At what entry count does the sub-list need search/filter?

Industry heuristic: a flat scrollable card list works well to ~7 items, becomes cumbersome at 10+, requires search/filter at 15+.

- **4 entries (post-4b)**: flat list is ideal. No grouping, no search.
- **8 entries (post-Phase-5)**: flat list is borderline. Grouping into 2 sections with headers ("Identity & Branding" / "Operations & Schedule" / "Team & Access") becomes worthwhile.
- **15+ entries**: search/filter required.

### 6.2 Recommendation: stay flat through Phase 4b, group at Phase 5

For 4b, keep the sub-list flat with 4 entries in the order: Brand → Sub-Users → Zones → Events. (Identity-then-operations sequencing.) When Phase 5 adds the Item #33 entries, regroup with section headers without moving any existing entries (additive). At 12+ entries, revisit grouping logic.

### 6.3 Does Pattern X still hold?

Yes. Pattern X is forward-compatible. The sub-list pattern itself accommodates both flat and grouped layouts behind a single `BusinessToolsScreen` widget. Grouping is a render decision, not an architecture change. **No revisit needed.**

The only Pattern X stress point Phase 4b exposes: the **inline `_buildZonesSection` in `settings_page.dart` is a duplicate surface** to whatever the Business Tools entry surfaces. Pattern X intends Business Tools to be the **single canonical** location for commercial-only features. Leaving the inline section means two truths. **Recommendation: remove the inline section as part of Phase 4b** (it's already commercial-gated, so removal doesn't affect residential).

---

## 7. Open Questions for Tyler

These block Phase 4b scope finalization. Listed in dependency order.

**Q1 — Customer-facing zone management: real or installer-only?**
Today, customers can edit zones via `_buildZonesSection` in commercial-mode settings. But the UX (raw IP entry, DDP port number) is installer-flavored. Do tier-2 commercial customers actually need to create/modify zones after installation, or is zone configuration permanently an installer-time concern with customers consuming the result? Answer determines whether Zones is a 4b entry, a 5+ entry, or never a customer entry.

**Q2 — If zones are customer-editable, what's the authoritative model?**
Current state: `ZoneModel` (in-memory `ZonesNotifier`), `Installation.systemConfig` (installer snapshot, opaque map), `ZoneAssignment` (SharedPreferences, segment+fixture metadata). None survives reinstall as a typed entity. Phase 4b can surface ephemeral state, but persistence is a Phase 5+ schema question. Confirm Phase 4b ships ephemeral surfacing, OR defer Zones until persistence design is settled.

**Q3 — "Zone Management" entry naming and audience.**
If the entry surfaces site-level multi-controller zones (`ZoneModel`), call it "Zones" and target tier-2 multi-controller installs. If it surfaces fixture metadata (`ZoneAssignment`), call it "Lighting Areas" and target everyone. The two are different features with overlapping names. Pick one for Phase 4b; the other defers.

**Q4 — Sub-user role vocabulary for commercial customers.**
Residential presets are `basic`/`full`/`viewOnly`. For Steve's Blue Line Bar, are commercial customers' mental model:
- **(a) bartender / manager / owner** (job titles), or
- **(b) Tier-1 / Tier-2 / Tier-3** (abstract levels), or
- **(c) View Only / Operate / Administer** (action verbs)?
Phase 4b reuses residential `SubUserPermissions` either way; vocabulary affects label-only changes. Phase 5 rebuild depends on this choice.

**Q5 — Per-feature enforcement of `SubUserPermissions`.**
Inventory shows the model + invitation flow + Firestore rules exist, but no widget appears to read `canEditSchedules` to gate the schedule editor, or `canChangePatterns` to gate pattern application. Is enforcement intentionally rules-level only (server-side)? If so, sub-users see UI they can't actually use until they tap and get a write rejection. If client-side enforcement is expected, that's a missing implementation that Phase 4b inherits.

**Q6 — Invitation delivery mechanism.**
Today: 6-char code shown to primary user, copy-to-clipboard, share manually. No email send, no deep-link, no SMS. Tier-2 commercial customers may expect "invite via email" — is in-app code-share sufficient for Phase 4b ship, or does this need to grow before commercial sub-user entry surfaces?

**Q7 — Should the Profile → Manage Family Members tile retain its current label for commercial users?**
Today it reads "Manage Family Members" and gates only on `installationId != null`. For commercial users, this label is wrong. Two options: (a) leave both entry points and just add a Business Tools entry (Phase 4b minimal), (b) relabel the Profile tile based on `isCommercialProfileProvider` (per-mode label). Phase 4a Q5 logic ("same gate for now") suggests (a); Item #35 ("Profile tab misnamed") suggests (b). Confirm.

---

## 8. Risk Assessment

### 8.1 Estimated change footprint (Phase 4b minimum scope: Reuse-as-is sub-users + Reuse-with-shell zones + remove inline `_buildZonesSection`)

| Metric | Estimate |
|--------|----------|
| Files modified | 2 (`business_tools_screen.dart` from 4a — add 2 entries; `settings_page.dart` — remove `_buildZonesSection`) |
| Files created | 0–1 (`zone_management_screen.dart` if extraction chosen) |
| LOC delta | +50 (sub-list entries) + 100–150 (extracted zones screen) − 130 (removed inline section) = ~+20 to +70 net |
| Reuse % | ~95% (existing `SubUsersScreen`, existing `ZonesNotifier` + `DDPSyncController`, existing widgets — only the screen-shell wraps need new code) |
| Sessions | 1 (matches Phase 4a sizing) |
| Smoke test | Sub-list shows 4 entries, each opens the right screen, removed inline section verified absent in commercial settings, residential settings unchanged |

### 8.2 Residential regression risk

- **Low for sub-users**: existing screen + route don't change; only a new entry point added. Profile tile unchanged.
- **Low for zones**: removing `_buildZonesSection` is commercial-only-conditional today; residential never sees it.
- **Risk vector**: if `mode` toggle (`siteModeProvider`) is set to commercial on a residential user (legacy data, install-flow bug), the inline section currently shows. Removing it relies on Business Tools card visibility being correctly gated by `isCommercialProfileProvider` (a different signal). Verify the two signals agree before removing.

### 8.3 Data-model impact

- **None for sub-users** in 4b minimum scope (rebuild deferred).
- **None for zones** if extraction is shell-only (same `ZonesNotifier` + same in-memory state).
- **Latent issue exposed but not fixed**: in-memory `ZonesNotifier` doesn't persist to Firestore. Phase 4b makes this visible by promoting Zones to a customer-facing entry. Document in changelog; persistence is Phase 5+ work.

### 8.4 Firestore rules impact

None. Sub-users + invitations rules already in place. Zones don't persist. No new collections.

### 8.5 Dependencies on Phase 4a

- `BusinessToolsScreen` must exist and be wired to the residential settings card. Phase 4b cannot land before 4a's `business_tools_screen.dart` is committed.
- Sub-list visual pattern (card with icon/title/subtitle/chevron) must match 4a's existing 2 entries. Phase 4b inherits the styling.
- Route convention `/settings/business-tools/<entry>` (per Phase 4a TBD) — Phase 4b should resolve this. Recommendation: route **`/settings/users`** stays as canonical sub-user URL (existing route) and Business Tools entry simply pushes it. Don't create a duplicate `/settings/business-tools/users`.

### 8.6 Cross-phase risks

- **Phase 5 conflict**: if Phase 5 rebuilds sub-user UI for commercial vocabulary, the 4b "reuse-as-is" entry will be replaced. That's fine — Pattern X tolerates entry replacement. But the Phase 5 plan must explicitly cover "swap target screen of Sub-Users entry" as a step.
- **Item #33 conflict**: Phase 5 adds entries for `manager_email`, `day_parts`, `channel_roles`, `commercial_teams`. Each of those is a new entry. The sub-list will hit 8 entries by end of Phase 5 — close to where grouping becomes warranted (per §6.1).
- **Item #36 (tier-3) conflict**: tier-3 customers may need entries like "Manage Locations" or "Push to All". Out of Phase 4b scope per Phase 4a Q5 decision. Re-evaluate when first tier-3 customer is in pipeline.

---

## 9. Final Summary

| Field | Value |
|-------|-------|
| **Total zone surfaces** | 17 (4 customer-facing, 5 installer/sales-facing, 8 supporting models/providers) |
| **Total sub-user surfaces** | 12 (1 primary screen, 1 entry tile, 1 join screen, 2 models, 1 service with sub-providers, plus Firestore rules + user-doc fields) |
| **Permission gap level** | **Substantial** — two parallel permission systems (`SubUserPermissions` 5-bit residential + `CommercialRole` 4-role / 9-permission commercial) with vocabulary, granularity, persistence, and enforcement mismatches. The 4-role enum vs 3-string persistence is a latent bug. Commercial-role rules are documented but undeployed. |
| **Recommended Phase 4b scope** | **Combined (1 session, both entries land together)**. Add Sub-Users entry (Reuse-as-is, points to existing `/settings/users`) + Zones entry (Reuse-with-shell, extract `_buildZonesSection` into `ZoneManagementScreen`) + remove the duplicate inline section from `settings_page.dart`. Net result: 4-entry flat sub-list, no schema changes, no rule changes, ~+50 net LOC. |
| **Top 3 open questions** | **Q1** (are zones a customer surface at all post-install?) — gates whether Zones entry exists. **Q4** (commercial sub-user role vocabulary?) — drives Phase 5 rebuild scope. **Q5** (per-feature enforcement of `SubUserPermissions`?) — exposes a possible long-standing implementation gap inherited by 4b. |
| **Top 3 deferred items** | Sub-user UI rebuild for commercial role vocabulary (Phase 5). Zone persistence (Phase 5+ — needs schema design). Item #33 entries (Phase 5 expanded scope). |
| **Risks approached** | None. This audit is read-only inventory + recommendation. No code modified, no implementation started. |

---

## 10. Appendix — Cross-References

- [`commercial_ux_phase_4a_decisions.md`](commercial_ux_phase_4a_decisions.md) — Phase 4a decision lock (Pattern X, sub-list location, gating, styling)
- [`commercial_ux_audit.md`](commercial_ux_audit.md) — Phase 1 audit (full inventory + decision matrix that informs Phases 2-6)
- Item #28 — CommercialOnboardingWizard unreachable; Phase 5 replaces with conversion flow in Settings
- Item #33 — commercial fields without post-install UI; Phase 5 expands sub-list to cover
- Item #34 — smoke test references nonexistent UI; Phase 6 reconciliation
- Item #35 — Profile tab misnamed; relevant to Q7
- Item #36 — three-tier customer segmentation; Phase 4b targets tier 2 only
- Item #37 — `/commercial` route retirement Phase 6
