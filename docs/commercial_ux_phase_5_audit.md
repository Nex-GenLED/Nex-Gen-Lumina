# Phase 5 Audit — Sub-User Permissions & Commercial-Field Post-Install UI

**Date:** 2026-05-06
**Branch:** `feature/commercial-ux-rework`
**Scope:** Read-only audit of Phase 5 (sub-user invitation/lifecycle, role-based permission model design, Firestore rules implications, UI surface inventory) plus Item #33 expansion (post-install UI for `manager_email`, `channel_roles`, `commercial_teams`, `commercial_permission_level`, day-parts/daylight-suppression configs).
**Status:** Inventory + design recommendation + scope-split proposal. No implementation. Open questions block scope finalization and several specific decisions.

This document is the structural sibling of [`commercial_ux_phase_4a_decisions.md`](commercial_ux_phase_4a_decisions.md) and [`commercial_ux_phase_4b_audit.md`](commercial_ux_phase_4b_audit.md). Phase 4a established Pattern X (Business Tools sub-list); Phase 4b extended it with the existing `SubUsersScreen` reused as-is and surfaced two parallel permission systems plus three "zones" namesakes. **Phase 5 is the phase that pays the deferred bills** — it owns the permission-model unification, the actual sub-user-aware enforcement layer, and the UI for every commercial field that ships in `UserModel` today without an editor.

---

## 1. Architectural Inheritance from Phase 4a / 4b

Phase 5 must respect:

- **Pattern X**: every Phase 5 surface is reachable through the residential settings → Business Tools sub-list, gated by `isCommercialProfileProvider`. The card simply doesn't render for residential.
- **Reuse-first**: existing screens (`SubUsersScreen`, `JoinWithCodeScreen`) are the starting point. Net-new screens land alongside them, not as replacements unless explicitly justified.
- **Residential glass/cyan styling** for any new Phase 5 surfaces.
- **No discovery hint** for residential customers — Phase 5 expansions remain commercial-only.
- **Tier-2 target only** — tier-3 multi-location patterns are forward-compatibility considerations, not scope.
- **`/commercial/...` routes preserved** through Phase 5; retired Phase 6.

Phase 4b's open-question chain that Phase 5 must answer: **Q4** (commercial sub-user role vocabulary), **Q5** (per-feature enforcement of `SubUserPermissions`), **Q6** (invitation delivery mechanism), **Q7** (Profile-tile relabeling).

Phase 4b's structural finding that Phase 5 must resolve: **two parallel permission systems** ([`SubUserPermissions`](../lib/models/sub_user_permissions.dart#L5) 5-bit residential vs [`CommercialRole`](../lib/models/commercial/commercial_role.dart#L1) 4-role / 9-permission commercial) with vocabulary, granularity, persistence, and enforcement mismatches.

---

## 2. Sub-User Lifecycle Audit

This section traces the four lifecycle stages — invite, accept, use, revoke — and inventories what exists today vs what's missing.

### 2.1 Stage 1: Owner invites sub-user

**What exists today** ([`sub_users_screen.dart:247-470`](../lib/features/users/sub_users_screen.dart#L247), [`invitation_service.dart:23-89`](../lib/services/invitation_service.dart#L23)):

- Owner taps FAB on `SubUsersScreen` → `_showInviteDialog` opens.
- Form collects: `inviteeEmail` (required), `inviteeName` (optional), 4 of 5 `SubUserPermissions` toggles (`canControl` is hard-coded `true`/disabled, `canAccessSettings` toggle is **not even in the dialog**).
- `InvitationService.createInvitation()`:
  - Reads `installations/{id}.max_sub_users` (5 residential, 20 commercial — per [`installation_model.dart:55`](../lib/models/installation_model.dart#L55)).
  - Counts current sub-users via `installations/{id}/subUsers` collection group count.
  - Rejects if at cap.
  - Rejects if a `pending` invitation already exists for the email.
  - Generates a 6-character token from a 32-char unambiguous alphabet (no 0/O/1/I/l).
  - Writes `/invitations/{auto-id}` doc with `installation_id`, `primary_user_id`, `invitee_email` (lowercased), `invitee_name`, `token`, `created_at`, `expires_at` (now + 7d), `status: 'pending'`, `permissions` (embedded `SubUserPermissions` map).
- Dialog displays the token with copy-to-clipboard button. **No email send. No deep link. No SMS.**
- Owner manually shares the code via their own channels.

**Firestore rules path** ([`firestore.rules:725-753`](../firestore.rules#L725)):
- `create`: requires `request.auth != null && isPrimaryUser()` AND a fixed shape check on the doc fields. Note: `isPrimaryUser()` checks the user-doc's `installation_role == 'primary'` — there's no `installationId` parameter, so a primary user of installation A could in principle mint an invitation referencing installation B. The rule does enforce `primary_user_id == request.auth.uid`, but doesn't enforce that `installation_id` belongs to that primary. (Latent integrity gap; not customer-visible today because the UI only ever passes the user's own installation id, but worth flagging if invitation creation moves to other paths in Phase 5+.)

**What's missing for tier-2 commercial**:
- No "send via email" button. Steve's Blue Line Bar manager won't have the app yet — they need a clickable email link, not a code Steve has to read aloud.
- No role presets for commercial vocabulary — only the 5-bit grid plus `SubUserPermissions.basic`/`full`/`viewOnly` constants (which the UI doesn't surface as preset chips anyway).
- Dialog hides `canAccessSettings` entirely — sub-users can never be granted settings access through the current invite UI. (Either a deliberate residential decision or an oversight.)
- No "Invite Manager / Invite Staff" affordance.

### 2.2 Stage 2: Invitee accepts

**What exists today** ([`join_with_code_screen.dart:205-306`](../lib/features/auth/join_with_code_screen.dart#L205), [`invitation_service.dart:94-159`](../lib/services/invitation_service.dart#L94)):

- The invitee must already have a Lumina account (any auth method; the screen requires `FirebaseAuth.instance.currentUser != null`).
- Route `/join-with-code` ([`app_router.dart:1205`](../lib/app_router.dart#L1205)) renders `JoinWithCodeScreen` — 6-char input, auto-submits on length 6.
- On submit: queries `invitations` where `token == code AND status == 'pending'`, validates expiration, then in a single transaction:
  - Updates the invitation: `status: 'accepted'`, `accepted_at`, `accepted_by_user_id`.
  - Updates `users/{uid}` with: `installation_role: 'subUser'`, `installation_id`, `primary_user_id`, `invitation_token`, `linked_at`, `sub_user_permissions`.
  - Sets `installations/{installation_id}/subUsers/{uid}` with: `linked_at`, `permissions`, `invited_by`, `invitation_token`, `user_email`, `user_name`.
- Note: `JoinWithCodeScreen._submitCode` does the writes inline (not via `InvitationService.acceptInvitation`). The two paths are semantically equivalent but **not the same code path** — a future change to `acceptInvitation` won't propagate to `JoinWithCodeScreen` automatically. (Drift risk.)

**What's missing**:
- No "you don't have an account yet" path. An invitee with no Lumina account hits the `else` branch in `_submitCode` and sees "You must be signed in to join" with no link to sign-up.
- No deep link pre-population. The token can't be pre-filled by tapping a link in an email.
- No validation that the invitee's email matches `invitation.invitee_email`. The invitation specifies an email, but `acceptInvitation` doesn't compare `userEmail` against `invitation.inviteeEmail` — anyone with the 6-char code can claim it. (Security/integrity gap. The 6-char token from a 32-char alphabet has ~1B combinations; brute force is impractical, but a leaked code lets the wrong person claim the slot.)
- No rejection of "already has an installation" — if the invitee's `users/{uid}` doc already has `installation_id` set (they're a primary or sub-user elsewhere), the acceptance silently overwrites it. Their ownership of the previous installation is lost from their user-doc perspective (the `installations/{previous}` doc stays put, orphaned from their reverse pointer).

### 2.3 Stage 3: Sub-user uses the app

**What exists today**:

- Sub-user signs in normally. Their `users/{uid}` doc has `installation_role: 'subUser'`, `installation_id`, `primary_user_id`, `sub_user_permissions`.
- Route guard ([`route_guards.dart`](../lib/route_guards.dart)) routes them based on `installationRole` and `profile_type`.
- All screens that read installation-scoped data work the same as for the primary user — sub-users see the same dashboard, same patterns, same schedules.
- **No widget reads `subUserPermissions` to gate UI.** Confirmed by Grep: the only files that reference `canEditSchedules`/`canChangePatterns`/`canControl`/`canInvite`/`canAccessSettings` are the model file itself, the invite/join screens, the service, and the user model. **No schedule editor checks `canEditSchedules`. No pattern apply checks `canChangePatterns`.**
- Firestore rules give sub-users **read access to anything `belongsToInstallation`** ([`firestore.rules:697`](../firestore.rules#L697)) and write access to many subcollections (controllers, properties, schedules) under the primary user's `users/{uid}` doc — because those rules check `belongsToInstallation`, not `installation_role`.

**Critical finding**: Today, a sub-user with `viewOnly` permissions can still:
- Toggle WLED state (HTTP calls to controllers, no Firestore guard).
- Edit schedules in Firestore (rules let any installation member write).
- Apply patterns (controller HTTP, no guard).
- Possibly modify properties/controllers on the primary's user doc (rules allow it).

The 5-bit permission map exists as data but is **inert** — neither client UI nor server rules enforce any of it. This is Phase 4b's open question Q5 promoted to "this is the implementation gap Phase 5 must close." See [`docs/urgent_findings_overnight.md`](urgent_findings_overnight.md) for whether this was flagged.

**What's missing**:
- Per-feature UI gating (read `subUserPermissions` in widget builders; hide or disable affordances).
- Server-side enforcement (rules that consult `installation_role` AND `sub_user_permissions` for sensitive writes).
- A "you don't have permission" message pattern.

### 2.4 Stage 4: Owner revokes / sub-user leaves

**What exists today** ([`invitation_service.dart:162-197`](../lib/services/invitation_service.dart#L162)):

- Owner taps the trash icon next to a sub-user → confirm dialog → `revokeAccess()`.
- Transaction: deletes `installations/{id}/subUsers/{uid}` doc AND updates `users/{uid}` to clear `installation_id`, `primary_user_id`, `sub_user_permissions`, `linked_at`, sets `installation_role: 'unlinked'`.
- For pending invitations: `revokeInvitation()` updates the invitation doc's `status: 'revoked'`. Doesn't delete the doc.
- `resendInvitation()`: revokes the old, creates a new one with same details and a new token.

**What's missing**:
- No "leave system" path for the sub-user themselves (only the primary can revoke). A sub-user who wants to disconnect from a system has to ask the owner.
- No audit log of revocations (when/why/by-whom).
- No notification to the revoked sub-user. Their app stops working when they next try to use it (the `users/{uid}` doc no longer says they belong anywhere) — they'll get "no installation found" with no explanation.
- The `users/{uid}` doc retains `invitation_token` after revoke (the transaction doesn't delete it) — minor data hygiene gap.

### 2.5 Lifecycle summary

| Stage | Exists? | Notes |
|-------|---------|-------|
| Owner-creates-invitation | Yes | Code-only delivery; missing email/deep-link |
| Invitee-redemption | Yes | Requires existing Lumina account; no email match check |
| Sub-user runtime | **Inert** | Permissions stored but never read/enforced |
| Owner revoke | Yes | Works; missing audit + notifications |
| Sub-user self-leave | **Missing** | No path for invitee to disconnect |

---

## 3. Permission Model Design Space (Tier-2 Commercial)

### 3.1 Constraints from existing data shapes

Phase 5 cannot ship a permission model that requires destructive schema migration of either:
- `SubUserPermissions` (embedded in invitations, mirrored on user-doc and subUsers-doc) — used by every existing residential customer.
- `commercial_permission_level` (string field on user doc, three values: `'store_staff'`, `'store_manager'`, `'corporate_admin'`) — already on every commercial customer's user doc.

The unification path must accept both as legacy inputs and converge to a single canonical model.

### 3.2 Recommended role set: 4 named roles (tier-2)

Keep the role count low and the names plain. Recommended:

| Role | Plain-English description | Maps from legacy |
|------|---------------------------|------------------|
| **Owner** | The original account holder. Has everything plus billing + account deletion + sub-user mgmt. There is exactly one owner. | `installation_role == 'primary'` (existing) |
| **Manager** | Full operational control — schedules, patterns, brand, events, day-parts. Cannot manage sub-users or delete the account. | `commercial_permission_level == 'store_manager'`; or `SubUserPermissions.full` minus `canInvite` |
| **Staff** | Day-to-day operation — control lights, change patterns, run scheduled events. Cannot edit schedule, brand, or admin. | `commercial_permission_level == 'store_staff'`; or `SubUserPermissions.basic` |
| **View Only** | Sees the dashboard. Cannot make changes. | `SubUserPermissions.viewOnly` (or new) |

Why 4 not 9? Audit 1 surfaced the 4-role enum vs 3-string persistence mismatch (`regionalManager` is unreachable from Firestore data). Tier-2 doesn't need region-level roles. Region-aware roles return in tier-3 (Phase 5+ or later).

### 3.3 Permission matrix

| Capability | Owner | Manager | Staff | View Only |
|------------|-------|---------|-------|-----------|
| View dashboard / status | Yes | Yes | Yes | Yes |
| Power on/off lights | Yes | Yes | Yes | No |
| Change brightness | Yes | Yes | Yes | No |
| Apply pattern from library | Yes | Yes | Yes | No |
| Run a scheduled event | Yes | Yes | Yes | No |
| Edit schedules / day-parts | Yes | Yes | No | No |
| Edit brand profile / colors | Yes | Yes | No | No |
| Create / edit events | Yes | Yes | No | No |
| Manage zones / channels | Yes | Yes | No | No |
| Configure controllers (BLE pair) | Yes | No | No | No |
| Invite / revoke sub-users | Yes | No | No | No |
| Edit business profile (name/hours) | Yes | Yes | No | No |
| Account deletion / billing | Yes | No | No | No |
| Edit other sub-users' roles | Yes | No | No | No |

### 3.4 Enforcement mechanism per row

| Capability | UI gate | Rules gate | Why |
|------------|---------|------------|-----|
| Power / brightness / pattern | UI only (or both) | No | These are HTTP calls to controllers, not Firestore writes. Rules can't gate them. |
| Schedules | Both | Yes (writes to `users/{primaryUid}/schedules` + commercial schedules subcollection) | Authoritative state lives in Firestore + sync to WLED |
| Brand profile / events / day-parts | Both | Yes (subcollection writes) | Same reason |
| Controllers (BLE pair) | UI | No | Local-network operation; Firestore rules don't see it |
| Sub-user mgmt | Both | Yes (existing `isPrimaryUserOfInstallation` rule covers it) | Already gated server-side |
| Billing / account deletion | Both | Yes | Owner-only via `isOwner` |

**Key recommendation**: server-side enforcement is necessary for any state Lumina actually owns (Firestore writes). Client-side UI gating is necessary for HTTP-to-controller actions because the network layer has no auth at all (open WLED HTTP API on the LAN). This means **Phase 5 must build BOTH** — they're not duplicate work, they cover non-overlapping attack surfaces.

### 3.5 Unification path from two systems

Recommended canonical shape on the sub-user doc and `users/{uid}.sub_user_permissions`:

- Store a single `role` string field: `'owner' | 'manager' | 'staff' | 'view_only'`.
- Optionally store a `permissions` map for forward compatibility (tier-3 may need overrides per location).
- For legacy `SubUserPermissions`: a derive-on-read function maps the 5-bit shape to a role (5 bits → 32 combos → choose closest of 4 roles by Hamming distance to the canonical preset's bit pattern). For legacy `commercial_permission_level`: direct string mapping.
- New writes use the role string. Old reads are converted on the way in.

This is one data-model decision and a small one-direction migration helper. It's not a destructive migration.

### 3.6 Reconciling with `CommercialRole`

The 4-role `CommercialRole` enum and its 9-permission map ([`commercial_role.dart`](../lib/models/commercial/commercial_role.dart)) is consumed only by [`commercial_mode_providers.dart:93`](../lib/screens/commercial/commercial_mode_providers.dart#L93) (`commercialUserRoleProvider`) and [`commercial_permissions_service.dart`](../lib/services/commercial/commercial_permissions_service.dart) (which is documented as undeployed pseudo-rules and uses `organizations`/`locations` collection-group queries that don't match the actual `users/{uid}/commercial_locations` data path).

**Recommendation**: deprecate `CommercialRole.regionalManager` (unreachable). Map the remaining three to the new 4-role model: `storeStaff` → `staff`, `storeManager` → `manager`, `corporateAdmin` → `owner` (where relevant) or `manager` (for non-org-owner admins). Retire `commercial_permissions_service.dart`'s collection-group query approach in favor of the simpler "role on sub-user doc" model. The 9-permission map's commercial-flavored capabilities (`canPushToRegion`, `canApplyCorporateLock`) are tier-3 concerns — defer to a later phase.

---

## 4. Firestore Rules Implications

### 4.1 Current rule shape for sub-users

Rules today ([`firestore.rules:712-753`](../firestore.rules#L712)) recognize:
- `belongsToInstallation(installationId)` — checks `users/{auth.uid}.installation_id == installationId`. Used for read.
- `isPrimaryUserOfInstallation(installationId)` — checks `installations/{id}.primary_user_id == auth.uid`. Used for sub-user CRUD.
- `isPrimaryUser()` — caller-only check on `installation_role == 'primary'`. Used for invitation create.

What's NOT in rules today:
- "Is this caller a sub-user of installation X with role Y?" — no helper exists.
- Per-permission gating (`canEditSchedules`, etc.) — no rule reads sub-user permissions.
- Most controller/property/schedule write paths under `users/{primaryUid}/...` don't differentiate primary from sub-user. They just check `belongsToInstallation` or `isOwner(userId)` of the doc-owner field, which (for sub-users) is **someone else's uid** (the primary). Sub-user writes to `users/{primaryUid}/schedules/{scheduleId}` would fail `isOwner` and be allowed only via `belongsToInstallation`-flavored rules.

### 4.2 Lookup approaches considered

**Option A — "Subordinate of" via per-eval read:**
```
function hasInstallationRole(roles) {
  return request.auth != null
    && exists(/databases/$(database)/documents/users/$(request.auth.uid))
    && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.get('sub_user_role', '') in roles;
}
```
- Pros: simple, reuses existing user-doc field.
- Cons: every gated rule eval is one extra `get()` (Firestore charges for it; on hot paths this matters).
- The `users/{uid}` get is **already on the critical path** for many existing rules (`isPrimaryUser`, `belongsToInstallation`, `isAdmin`). Adding a role-string field is amortized — no NEW `get()`.

**Option B — Custom claims via Cloud Function:**
- Cloud Function on sub-user creation sets `auth.token.role = 'staff' | 'manager' | ...`.
- Rule: `request.auth.token.role in ['manager', 'owner']`.
- Pros: zero per-eval reads. Token is already part of every authenticated request.
- Cons: claims are stale until token refresh (~1h default). Permission changes don't take effect immediately. Requires a Cloud Function on every sub-user permission change. Forced sign-out / token refresh pattern needed for UX consistency.
- Lumina already has `mintStaffToken` Cloud Function pattern (per memory item: "App Check / rate-limit before launch, client migration to call the callable"). This shows custom-claim machinery is in use and conceptually fine.

**Recommendation**: Option A as Phase 5 baseline. Reasons:
1. The user-doc `get()` is already happening on most gated paths.
2. Permissions change immediately, no token-refresh dance.
3. Doesn't require a new Cloud Function (Phase 5 stays UI/rules-focused, no functions/* deployment scope).
4. Matches the existing pattern used by `belongsToInstallation`, `isPrimaryUser`, `isAdmin`.

If profiling shows the per-eval read cost is unacceptable later (post-launch, with real traffic), promote to Option B as a perf optimization.

### 4.3 New rule helpers needed

```
function subUserRole() {
  return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.get('sub_user_role', '');
}

function hasMinRole(min, installationId) {
  return belongsToInstallation(installationId) && subUserRole() in roleSet(min);
}
```
Where `roleSet('staff') = ['staff', 'manager', 'owner']`, etc.

**Rule rewrites needed** (estimate):
- `installations/{id}/subUsers/{uid}` writes: already gated by `isPrimaryUserOfInstallation`. Tighten: only `owner` (which is what primary-user-of-installation already means).
- `users/{primaryUid}/schedules/{...}` writes: gate by `hasMinRole('manager', primaryUid's installation)` for non-owners. (Today: open to any installation member.)
- `users/{primaryUid}/brand_profile/{...}`: gate by `hasMinRole('manager', ...)`.
- `users/{primaryUid}/commercial_events/{...}`: gate by `hasMinRole('manager', ...)`.
- `users/{primaryUid}/properties/{...}` and `controllers/{...}`: gate by `hasMinRole('owner', ...)`.

Estimated rule deltas: ~6-10 collection paths get a tightened write rule. Existing read rules largely stay (everyone in the installation can read).

### 4.4 Rules deploy gotcha

Per memory item ([Firestore Rules Deploy](../memory/MEMORY.md)): rules are **NOT auto-deployed**. After editing `firestore.rules`, must run `firebase deploy --only firestore:rules`. Phase 5 commits should include a checkmark in the PR description that this was done, and Phase 5 testing must verify enforcement against deployed rules (not just emulator).

This is the same pattern that bit Items #29 (commercial onboarding silently broken) and #31 (brand pre-seed silent-fail). Phase 5 needs explicit deploy gating in its definition of done.

---

## 5. UI Surfaces Required

For tier-2 sub-user management, here is every screen Phase 5 must consider, marked with whether existing scaffolding helps or it's net-new.

| # | Screen | Status | Notes |
|---|--------|--------|-------|
| 1 | Sub-user list (Manage Team Members) | **Reuse** [`SubUsersScreen`](../lib/features/users/sub_users_screen.dart#L18) with vocabulary changes | Currently labeled "Manage Users" / "Family Members" — relabel to "Manage Team" / "Team Members" when `isCommercialProfileProvider` is true |
| 2 | Active sub-user count + cap chip | **Exists** | Already on `SubUsersScreen`. No change. |
| 3 | Add sub-user dialog (invite) | **Rebuild** | Today: 4 toggles + email. Phase 5: role chip selector ("Manager / Staff / View Only") + email + name. |
| 4 | Invitation code display + copy | **Exists** | Reuse as-is. |
| 5 | "Send via email" button | **Net-new** | Mailto link or Cloud Function-backed transactional email. Mailto is shippable in Phase 5; transactional email is a follow-up. |
| 6 | Edit sub-user role | **Net-new** | Tap a sub-user tile → bottom sheet with role chips + Save. Today there's no edit UI; only revoke. |
| 7 | Revoke sub-user | **Exists** | Reuse confirm dialog. Add audit log write (see #10). |
| 8 | Pending invitations list | **Exists** | Reuse. Maybe add "shared via" indicator (code/email) once #5 lands. |
| 9 | Sub-user's self-profile / "Leave system" | **Net-new** | Today the sub-user has no exit. Phase 5 should add a "Leave [system name]" action under Profile or Settings for non-owners. |
| 10 | Audit log (optional) | **Defer to Phase 5b/c** | "X invited Y on date / Z revoked Y on date" — useful for tier-2 commercial accountability. Not blocking ship. |
| 11 | "You don't have permission" snackbar/sheet | **Net-new pattern** | A reusable widget for the gated write rejections. |
| 12 | Permission-aware UI gating | **Net-new in many widgets** | Read `subUserPermissions` (or new `subUserRole`) and disable buttons / hide tiles accordingly. Touches most screens. |
| 13 | Deep-link / signup-with-token | **Net-new** | Invitee with no Lumina account taps email link → sign-up flow → token consumed. Significant effort; could defer. |

### 5.1 Item #33 expansion — commercial-field UIs

These five fields ship in `UserModel` today but have no post-install editor.

#### 5.1.1 `manager_email` ([`user_model.dart:217`](../lib/models/user_model.dart#L217))
- **What it does**: per-docstring, "manager email for Monday morning digest." Currently set only at install time via [`installer_setup_wizard.dart`](../lib/features/installer/installer_setup_wizard.dart) and [`handoff_screen.dart:599`](../lib/features/installer/handoff_screen.dart#L599) (commercial branch). Read by ... nothing in the app today (no Monday morning digest service ships). Effectively dormant.
- **Customer-editable?** Yes — owners would expect to update the manager email when staff change. Recommend: small text-field tile in Business Tools sub-list ("Weekly digest recipient"). Cheap UI.
- **Alternative**: retire field if no digest service ships in Phase 5. (Probable correct answer pending Tyler.)

#### 5.1.2 `channel_roles` ([`user_model.dart:262`](../lib/models/user_model.dart#L262))
- **What it does**: defines per-channel commercial role + coverage policy + daylight suppression. `ChannelRoleConfig` is a rich model.
- **In code**: serialized in/out of `UserModel`, but **no other file reads or writes the field** (Grep confirms only `user_model.dart` references `channelRoles` / `channel_roles`). The model exists; the field exists; no code path uses either.
- **Customer-editable?** The data shape implies yes (per-channel friendly name, role, coverage, daylight). But with zero readers, it's a dead field today.
- **Recommendation**: **retire from `UserModel`** in Phase 5 as a cleanup, OR build an editor only when a downstream feature actually needs it. Don't build UI for an unused field.

#### 5.1.3 `commercial_teams` ([`user_model.dart:268`](../lib/models/user_model.dart#L268))
- **What it does**: sports teams configured for game-day automation. `CommercialTeam` model has slug/name/sport/priority/intensity/enableGameDayMode.
- **In code**: read by [`game_day_service.dart`](../lib/services/commercial/game_day_service.dart) — actually used. Set during onboarding wizard.
- **Customer-editable?** Yes — sports preferences change. Recommend: editor that mirrors residential's `sportsTeams` editor (multi-select chips), accessible from Business Tools sub-list. Existing residential team editor logic is reusable as a starting point.

#### 5.1.4 `commercial_permission_level` ([`user_model.dart:271`](../lib/models/user_model.dart#L271))
- **What it does**: per-user role string. Three values per persistence layer: `'store_staff' | 'store_manager' | 'corporate_admin'`.
- **In code**: read by [`commercialUserRoleProvider`](../lib/screens/commercial/commercial_mode_providers.dart#L93) to derive `CommercialRole`. Maps to 4-role enum (with `regionalManager` unreachable, see Audit 1).
- **Customer-editable?** This is an **owner-edits-someone-else's** field, not a self-edit. Should be subsumed by Phase 5's new role-on-sub-user-doc model (§3.5). Recommendation: don't ship a direct editor for this field; instead, the Phase 5 sub-user role editor (#6 in §5) writes the new canonical role and mirrors to legacy `commercial_permission_level` for back-compat reads.

#### 5.1.5 Day-parts / daylight-suppression configs ([`user_model.dart:265`](../lib/models/user_model.dart#L265))
- **What it does**: `dayParts` is a list of named time windows ("Happy Hour"). Daylight-suppression lives on `ChannelRoleConfig` (see #5.1.2).
- **In code**: read by [`day_part_scheduler_service.dart`](../lib/services/commercial/day_part_scheduler_service.dart), [`CommercialScheduleScreen.dart`](../lib/screens/commercial/schedule/CommercialScheduleScreen.dart), [`FleetDashboardScreen.dart`](../lib/screens/commercial/fleet/FleetDashboardScreen.dart), [`commercial_schedule.dart`](../lib/models/commercial/commercial_schedule.dart). Set during onboarding via [`day_part_config_screen.dart`](../lib/screens/commercial/onboarding/screens/day_part_config_screen.dart).
- **Customer-editable?** Yes — happy hour times shift, daypart names change. There IS an existing editor (`day_part_config_screen.dart`) reachable only from inside the (broken / unreachable) `CommercialOnboardingWizard`. Reuse that editor as a Business Tools sub-list entry.

### 5.2 Net surface count

Reusing existing screens where possible, Phase 5 lands roughly:
- 1 reused screen (Manage Team — vocabulary tweak)
- 1 rebuilt dialog (invite with role chips)
- 4 net-new screens (edit role, leave system, audit log if not deferred, deep-link signup)
- 1 reused screen retitled (day-part config — was inside onboarding, becomes Business Tools entry)
- 1 small new screen (manager email tile)
- 1 reused screen retitled (sports teams editor)
- 1 net-new pattern (permission-denied snackbar)
- ~15-25 widget edits (UI gating across schedule editor, brand editor, pattern apply, etc.)

---

## 6. Tier-3 Forward Compatibility

Per Item #36, tier-3 customers will need:
- Multi-location organizations.
- Cross-location sub-users (manager Y can manage stores 1-3, not store 4).
- Region-level rollups.

Phase 5 design decisions that risk tier-3 expansion:
1. **Single role per user** (vs role-per-location) — tier-2 customers have one location, so one role is fine. Tier-3 needs role-per-location.
2. **`sub_user_role` as a top-level user-doc field** — same problem.
3. **Invitation embedded in `installations/{id}` only** — no concept of org-level invitations.

### 6.1 Compatibility options

**(a) Build tier-2 cleanly + refactor for tier-3 later.** Rule helpers like `hasMinRole` accept an installation id today; tier-3 adds a location id parameter. The role data shape evolves from `sub_user_role: string` to `sub_user_roles: { [locationId]: string }`. Migration is a one-time map-then-write.

**(b) Build tier-3-aware shape now with tier-2 logic only.** Store as `sub_user_roles: { 'default': 'manager' }` from day one, even for single-location tier-2. Tier-3 just adds more keys.

**(c) Defer entirely.** Don't think about tier-3 at all in Phase 5.

**Recommendation**: **(b) — tier-3-aware shape with tier-2 logic.** The cost of writing `{ 'default': role }` instead of `role` is trivial. The cost of NOT doing it is a future destructive migration. This matches Phase 4a Q5's logic ("avoid speculative segmentation") in spirit but applies it to data shape rather than UX — the data shape is forward-compatible without committing to UI/UX decisions.

Specifically:
- New field on user doc and sub-user doc: `installation_roles: { [installationId]: 'owner' | 'manager' | 'staff' | 'view_only' }`. (Tier-2 has exactly one key.)
- Rule helpers parameterize by installation id but accept "first matching role" for tier-2 single-installation cases.
- UI reads `installation_roles[currentInstallationId]` but tier-2 UX shows it as "your role: Manager" without per-location framing.

---

## 7. Phase 5 Scope Estimate

This is the largest single phase in the plan. Reusing only what's truly reusable, the work is:

- **Sub-user surfaces** (≥4 net-new + 2 rebuilt + 12+ widget gating edits)
- **Rules layer** (~6-10 collection paths tightened, new helpers, deploy + verification)
- **Item #33 fields** (3 new editor tiles, 2 retired/dead-fields cleanup, 1 lifted-from-onboarding editor)
- **Permission unification** (legacy mappers, role write path)
- **Optional but valuable**: deep-link signup, audit log, transactional email

Honest estimate: **3 sessions minimum, 4 likely, 5 if deep-link + email + audit log all land**. Recommend split:

### Phase 5a — Permission core + sub-user role rebuild (1 session)
- New `installation_roles` field on user-doc + subUsers-doc.
- Legacy mapper helpers (`SubUserPermissions` 5-bit → role; `commercial_permission_level` → role).
- Sub-user invite dialog: role chips replace 4 toggles.
- `SubUsersScreen` vocabulary toggle for commercial (Manage Team / Team Members).
- Sub-user role edit bottom sheet (#6 in §5).
- "Leave system" action (#9 in §5).
- No rule changes yet — entirely client-side and additive.
- Smoke: invite with each role; accept; verify role visible on owner side; revoke.

### Phase 5b — Rules layer + UI gating (1 session)
- `firestore.rules` helpers (`subUserRole`, `hasMinRole`, role-set hierarchy).
- Tightened write rules on schedules, brand, events, day-parts, controllers, properties.
- Deploy rules; smoke against deployed rules (not emulator only — per the deploy-gotcha §4.4).
- Widget gating: schedule editor, brand editor, pattern apply, sub-user invite — read role and disable affordances.
- "Permission denied" snackbar pattern.
- Legacy field write (`commercial_permission_level`) mirrored from new role for back-compat reads.
- Smoke: each role tries each gated action; verify both UI gating and rule denial.

### Phase 5c — Commercial-field editors (1 session)
- Day-parts editor lifted from onboarding into Business Tools sub-list.
- Sports teams editor mirroring residential's pattern.
- Manager email tile.
- Cleanup: retire `channel_roles` field if no consumer ships in 5a-5b (or mark explicit-system in `UserModel`).
- Smoke: each editor round-trips through Firestore; persistence verified across reinstall.

### Phase 5d (optional, deferrable) — Deep-link + email + audit (1 session)
- Email-based invitation delivery (mailto first; transactional email if Cloud Function added).
- Deep link → signup-with-pre-filled-token.
- Audit log subcollection: `installations/{id}/audit_log/{eventId}` with role grants/revokes.
- Smoke: end-to-end invite via email, signup, role takes effect.

If Phase 5d slips, the launch-critical work is 5a + 5b + 5c. 5d is polish and trust-builders.

---

## 8. Open Questions for Tyler

These block Phase 5 scope finalization. Listed in dependency order.

**Q1 — Role names (§3.2 tier-2 set).**
Confirm "Owner / Manager / Staff / View Only" — or prefer "Owner / Manager / Staff" with no view-only role (cleaner tier-2; matches what Steve's Blue Line Bar likely needs)? Or industry-y vocabulary like "Operator / Bartender / Viewer"? Phase 4b Q4 deferred this; Phase 5 owns it.

**Q2 — Invitation delivery: code-only, code+mailto, or transactional email?**
Phase 4b Q6. Code-only ships fastest. Code+mailto is small lift (one button, opens email client). Transactional email is a Cloud Function with template. Phase 5a can do code+mailto; Phase 5d does the rest. Confirm which level meets "ready for tier-2 launch."

**Q3 — Should sub-users have separate Firebase Auth accounts, or shared?**
Today: separate accounts (each invitee signs up with their own email). Pros: standard auth, password recovery works per-user, audit trail is real. Cons: Steve's bartender has to create a Lumina account just to use the lights. Alternative: single shared account with PIN-based "sub-user mode" within the app. Phase 5 default = separate accounts (matches existing); confirm.

**Q4 — Are residential sub-users expected to migrate to the new role model?**
Today residential has 0 sub-users in the field per the audit's reading of the codebase (no count is recorded; this is an inference). If residential sub-users exist in production, Phase 5 needs an explicit migration. If not, the legacy `SubUserPermissions` mapper can stay dead-code-path indefinitely. Confirm pre-launch state.

**Q5 — Per-feature enforcement priority order.**
Phase 5b gates many widgets. If sessions get tight, which gates are launch-critical vs nice-to-have? Suggested critical: schedule editor, brand editor, sub-user invite. Suggested deferable: pattern-favorite, hover/long-press affordances. Confirm.

**Q6 — Audit log: ship in Phase 5 or defer?**
Useful for tier-2 trust ("Steve, your manager Linda revoked the bartender at 9pm Tuesday"). Adds complexity. Phase 5d-level. Defer or ship?

**Q7 — Manager email field: live UI or retire?**
The field exists, has zero reading consumers in the app today (no Monday digest service). Build a small editor in 5c, or retire the field as part of 5c cleanup? Confirm whether the digest service is upcoming.

**Q8 — `channel_roles` field: retire?**
Confirmed dead field today (zero readers). Retire from `UserModel` in 5c, or keep for forward use? If keep, document why.

**Q9 — Tier-3 forward shape (§6.1): ship now or defer?**
Confirm option (b) (tier-3-aware shape, tier-2 logic) — the small forward-compat investment. Option (a) (clean tier-2, migrate later) is cheaper now but more painful later.

**Q10 — "Manage Family Members" Profile tile (Phase 4b Q7 carryover).**
For commercial customers, relabel to "Manage Team Members"? Or remove the Profile entry entirely once Business Tools has it (single-source-of-truth)? Confirm.

---

## 9. Final Summary

| Field | Value |
|-------|-------|
| **Total UI surfaces required** | **~9 screens** — 1 reused-as-is (`JoinWithCodeScreen`), 1 reused with vocabulary toggle (`SubUsersScreen`), 1 lifted from onboarding (day-part editor), 1 mirrored from residential (sports teams), and ~5 net-new (invite-with-roles, edit-role, leave-system, manager-email tile, audit-log [optional]). Plus **~15-25 widget gating edits** across schedule/brand/pattern surfaces. |
| **Permission model recommendation** | 4 named roles (**Owner / Manager / Staff / View Only**) stored as `installation_roles: { [installationId]: role }` (tier-3-aware shape) on user-doc and subUsers-doc. Legacy `SubUserPermissions` and `commercial_permission_level` mapped on read; mirrored on write for back-compat. `CommercialRole.regionalManager` deprecated (unreachable today). 9-permission `CommercialRole` map retired in favor of role + capability matrix. |
| **Rules layer change scope** | **Medium** — ~6-10 collection paths get tightened write rules, 1-2 new helper functions (`subUserRole`, `hasMinRole`). Manual deploy required (per Firestore rules deploy memory item) plus deployed-rules smoke test. No new collections; no migrations. |
| **Phase 5 scope** | **Multi-session split** — recommended 5a (permission core + sub-user UI rebuild) → 5b (rules layer + UI gating) → 5c (commercial-field editors + cleanup) → 5d (deep-link + email + audit log, deferrable). Launch-critical = 5a + 5b + 5c. |
| **Top open questions** | **Q1** (role names) — gates UI labels and copy across all 5a surfaces. **Q2** (invitation delivery) — gates 5a vs 5d split. **Q5** (per-feature enforcement priority) — gates 5b widget edits. **Q9** (tier-3 forward shape) — gates the data-model decision in 5a. |
| **Top deferred items** | Deep-link / signup-with-pre-filled-token (Phase 5d). Transactional email send (Phase 5d). Audit log (5b/5d). Tier-3 region-level roles (post-Phase 5, when first tier-3 customer enters pipeline). Tier-2 multi-installation (e.g. owner with 2 separate Lumina systems) — requires the §6.1 (b) shape but no UI work in Phase 5. |
| **Risks approached** | Read-only audit. No code modified, no implementation started. One urgent finding flagged to `docs/urgent_findings_overnight.md` (sub-user permission inertness — see §10). No rail violations. |

---

## 10. Urgent Finding (logged separately)

**Finding**: `SubUserPermissions` is data-only. No widget reads it. No rule reads it. Sub-users today have full operational access despite the data model implying granular permissions. This is a **pre-launch security/integrity gap** for any customer who has invited a `viewOnly` or `basic` family member expecting actual access restrictions.

Logged to [`urgent_findings_overnight.md`](urgent_findings_overnight.md). Phase 5b owns the fix (rules + UI gating). If Phase 5 slips past launch, the fastest mitigation is to remove the `viewOnly` preset from the invite UI so customers can't create a permission expectation the system doesn't honor.

---

## 11. Appendix — Cross-References

- [`commercial_ux_phase_4a_decisions.md`](commercial_ux_phase_4a_decisions.md) — Phase 4a foundational decisions (Pattern X, gating, styling)
- [`commercial_ux_phase_4b_audit.md`](commercial_ux_phase_4b_audit.md) — Audit 1 inventory; finds two parallel permission systems and the 4-role enum vs 3-string persistence latent bug; carries Q4/Q5/Q6/Q7 into Phase 5
- [`commercial_ux_audit.md`](commercial_ux_audit.md) — Phase 1 31-item decision matrix
- Item #28 — CommercialOnboardingWizard unreachable; day-part editor is currently trapped inside the unreachable wizard; Phase 5c lifts it out
- Item #29 — Commercial onboarding silently broken via missing rule deploy; Phase 5b's rule changes need explicit deploy gating to avoid the same class of failure
- Item #31 — Brand pre-seed silent-fail (sibling of #29); same deploy-discipline requirement
- Item #33 — Commercial fields without post-install UI; this audit's §5.1 expansion
- Item #34 — Smoke test references nonexistent UI; Phase 6 reconciliation will re-check after Phase 5 lands actual editors
- Item #35 — Commercial Profile tab misnamed; Phase 4 cleanup (separate phase, not 5)
- Item #36 — Three-tier customer segmentation; Phase 5 targets tier-2; §6 covers tier-3 forward compatibility
- Item #37 — `/commercial` route retirement Phase 6 (Phase 5 surfaces all live under residential settings, so retirement is unblocked once Phase 5 ships)
