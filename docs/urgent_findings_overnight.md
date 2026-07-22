# Urgent Findings — Overnight Audit Batch

**Date:** 2026-05-06
**Source:** Overnight audit batch (Phases 4b, 5, and pending audit 3)
**Action requested:** Tyler review — do NOT auto-act on these findings.

This file is append-only. Each finding is dated and sourced to the audit that produced it.

---

## Finding 1 — Sub-user permissions are inert (Phase 5 audit, 2026-05-06)

**Source:** [`commercial_ux_phase_5_audit.md`](commercial_ux_phase_5_audit.md) §2.3, §2.5, §10

**Severity:** Pre-launch security/integrity gap.

**Summary:** The 5-bit `SubUserPermissions` model ([`sub_user_permissions.dart:5`](../lib/models/sub_user_permissions.dart#L5)) is stored on invitations, on `users/{uid}.sub_user_permissions`, and on `installations/{id}/subUsers/{uid}.permissions`. **No widget anywhere reads these fields to gate UI.** **No Firestore rule consults them.** Confirmed via Grep across `lib/`: the only files that reference `canEditSchedules`/`canChangePatterns`/`canControl`/`canInvite`/`canAccessSettings` are the model itself, the invite/join screens, the `InvitationService`, and the user model.

**Concrete consequence:** A customer who invites a "View Only" family member today gets a sub-user who can:
- Toggle WLED state (HTTP, no Firestore guard)
- Edit schedules in Firestore (rules let any installation member write)
- Apply patterns (controller HTTP, no guard)
- Possibly modify properties/controllers on the primary's user doc

The `viewOnly` preset on the invitation UI creates a customer expectation the system does not honor.

**Why this matters now:**
- Phase 5b is the planned fix — rules tightening + widget gating across schedule/brand/pattern surfaces.
- Phase 5b is multi-session work. If Phase 5 slips past tier-2 launch (Steve's Blue Line Bar, Diamond Family Jewelers), commercial owners may invite sub-users expecting role-based limits and not get them.
- The fastest pre-launch mitigation that doesn't require rules work: remove the `viewOnly` preset and the per-bit toggles from the invite dialog UI, leaving only "send invitation" with no permission knobs. This makes the lack-of-enforcement honest rather than misleading.

**Recommended next step:** decision on Phase 5 timeline relative to launch — does Phase 5 ship before tier-2 first-customer onboarding, or does the invite UI degrade in the interim?

**Not yet acted on.** Read-only audit. No code changed.

---
