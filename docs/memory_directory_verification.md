# Memory Directory Verification — 2026-05-06

Read-only audit of `C:\Users\honey\.claude\projects\c--Flutter-Projects-Lumina-V-1-6\memory\` to determine the actual state of project-wide Items #1-#37 referenced across audit prompts.

**Output rails:** This document is the deliverable. **No memory files were created, modified, or deleted.** All recommendations are for Tyler to act on in the morning.

---

## 1. Memory File Inventory

Total: **23 markdown files** + **1 index** + **1 subdirectory** (`audit_logs/`).

### Project files (item-tagged or chapter)

| # | File | Size | Last modified | One-line description |
|---|------|------|---------------|----------------------|
| 1 | `MEMORY.md` | 7.9 KB | May 6 22:46 | Top-level index — Open Items list, infrastructure notes, conventions, hardware, network devices |
| 2 | `project_staff_auth_open_items.md` | 25.5 KB | May 5 17:15 | **Multi-item chapter file**: 17 internal subsections covering the mintStaffToken / staff custom claim chapter (dealer.isActive gating, App Check, corporate-mode migration, payouts, etc.) |
| 3 | `project_install_flow_partial_success.md` | 2.5 KB | May 6 11:41 | Item #22: createCustomerAccount returns "use existing password" but doesn't link controllers |
| 4 | `project_parallel_session_coordination.md` | 1.6 KB | May 6 13:36 | Item #24: multiple Claude Code windows, check recent commits before generating prompts |
| 5 | `project_schema_drift_prompts.md` | 1.9 KB | May 6 13:36 | Item #25: verify field-level data shapes against consuming code before generating data |
| 6 | `project_commercial_onboarding_unreachable.md` | 2.8 KB | May 6 15:27 | Item #28: AppRoutes.commercialOnboarding registered but no client navigates to it |
| 7 | `project_commercial_onboarding_silently_broken.md` | 2.9 KB | May 6 15:07 | Item #29: missing /users/{uid}/commercial_locations rule caused atomic batch rollback |
| 8 | `project_commercial_ux_architectural_rework.md` | 2.3 KB | May 6 15:28 | Item #30: STUB pending Tyler's verbatim — install wizard's two signals need UI consolidation |
| 9 | `project_brand_preseed_silent_fail.md` | 1.4 KB | May 6 15:38 | Item #31: installer-driven brand_profile write was rule-denied; fixed 2026-05-06 |
| 10 | `project_commercial_activation_dual_paths.md` | 2.1 KB | May 6 20:32 | Item #32: canonical wizard + installer wizard both write commercial-activation batch |
| 11 | `project_commercial_fields_no_post_install_ui.md` | 2.1 KB | May 6 20:32 | Item #33: commercial_teams, channel_roles, manager_email, daylight configs ship without UI |
| 12 | `project_commercial_smoke_test_drift.md` | 2.6 KB | May 6 20:33 | Item #34: smoke test references Game Day badge / Corporate Push FAB / Manage Locks UIs not in code |
| 13 | `project_commercial_profile_tab_misnamed.md` | 3.1 KB | May 6 21:38 | Item #35: BusinessProfileEditScreen labeled "Profile" but contains only business fields |
| 14 | `project_commercial_route_retirement_phase6.md` | 4.7 KB | May 6 22:46 | Item #37: /commercial route retirement scheduled for Phase 6 |
| 15 | `project_brand_seeds_2026_05_06.md` | 2.0 KB | May 6 13:36 | Diamond Family Jewelers + Blue Line Bar brand seeds (no Item #) |
| 16 | `project_firestore_rules_deploy.md` | 1.4 KB | Apr 23 12:06 | Rules are NOT auto-deployed; manual deploy required (no Item #, pre-numbering) |

### Feedback files (no Item #)

| # | File | Size | Last modified | Description |
|---|------|------|---------------|-------------|
| 17 | `feedback_connectivity_defaults.md` | 1.1 KB | Apr 3 11:58 | SSID-null defaults to local, not remote |
| 18 | `feedback_field_context.md` | 1.3 KB | May 1 15:00 | Network devices apply to home network only — do NOT assume in field |
| 19 | `feedback_model_serialization.md` | 1.2 KB | Apr 7 17:15 | Always toJson/fromJson + snake_case + Timestamp; never toMap/fromMap |
| 20 | `feedback_sales_pipeline.md` | 2.3 KB | Apr 7 17:25 | Extend lib/features/sales/ (SalesJob, sales_jobs); never build parallel Prospect models |

### Reference / operational files (no Item #)

| # | File | Size | Last modified | Description |
|---|------|------|---------------|-------------|
| 21 | `esp32_bridge_flashing.md` | 2.1 KB | May 4 10:38 | PlatformIO paths, COM ports, board quirks for ESP32 bridge |
| 22 | `remote_access_architecture.md` | 1.7 KB | Apr 3 11:57 | Cloud relay via ESP32 Firestore bridge, connectivity detection |
| 23 | `wipe_operations.md` | 1.8 KB | May 6 11:41 | Chronological log of customer-data wipe operations |
| 24 | `audit_logs/` | (dir) | May 6 11:41 | Subdirectory for wipe operation audit logs |

---

## 2. Item Number → File Map

| Item # | File | Status |
|--------|------|--------|
| #1 – #21 | (none) | **Never existed as project-wide items** — see §3.1 |
| #22 | `project_install_flow_partial_success.md` | ✅ |
| #23 | (none) | **Missing** — see §3.2 |
| #24 | `project_parallel_session_coordination.md` | ✅ |
| #25 | `project_schema_drift_prompts.md` | ✅ |
| #26 | (none) | **Missing** — see §3.2 |
| #27 | (none) | **Missing** — see §3.2 |
| #28 | `project_commercial_onboarding_unreachable.md` | ✅ |
| #29 | `project_commercial_onboarding_silently_broken.md` | ✅ |
| #30 | `project_commercial_ux_architectural_rework.md` | ✅ |
| #31 | `project_brand_preseed_silent_fail.md` | ✅ |
| #32 | `project_commercial_activation_dual_paths.md` | ✅ |
| #33 | `project_commercial_fields_no_post_install_ui.md` | ✅ |
| #34 | `project_commercial_smoke_test_drift.md` | ✅ |
| #35 | `project_commercial_profile_tab_misnamed.md` | ✅ |
| #36 | (none, but referenced in #37 file and Phase 4a doc) | **Embedded / missing standalone** — see §3.3 |
| #37 | `project_commercial_route_retirement_phase6.md` | ✅ |

**Coverage: 11 of 37 possible item numbers have standalone files** (#22, #24-#25, #28-#35, #37). Items #36 has narrative references but no standalone file. Items #1-#21, #23, #26, #27 have no observable existence in the memory directory.

---

## 3. Gap Analysis

### 3.1 Items #1 – #21: most likely never existed as project-wide items

**Hypothesis:** Project-wide item numbering began at #22, not #1. The `project_install_flow_partial_success.md` ("Item #22") is the lowest numbered item-tagged file; its description treats #22 as the first project-wide item ("createCustomerAccount returns 'use existing password' but doesn't link controllers — wipes mask the bug"). No earlier project-tagged files exist on disk.

**Internal-numbering false positive:** `project_staff_auth_open_items.md` contains internal subsections numbered 1-17 (Server-side dealer.isActive gating; App Check on mintStaffToken; Audit log gap on createCustomToken failure; Migrate corporate mode; etc.). **These are NOT project-wide Items #1-#17** — they are chapter-internal subsection numbers, scoped to the staff-auth file only. References across audit prompts to "Item #4" etc. could be ambiguous depending on context (project-wide or staff-auth-internal).

**Recommendation:** Mark Items #1-#21 as **Skipped** (never used as project-wide numbers). If audit prompts reference these numbers, the prompt is likely confusing staff-auth-internal subsections with project-wide items. **Tyler must verify** by checking session transcripts where these numbers appeared.

### 3.2 Items #23, #26, #27: genuinely missing from disk

These three numbers fall inside the otherwise-contiguous #22 → #35 + #37 sequence. The gap pattern (one number missing between consecutive files) suggests these *were* discussed and assigned numbers but never had memory files created.

**Possible explanations (need Tyler confirmation):**

- **#23**: Likely created and resolved before being memorialized. Could relate to a wipe/rebuild action, a quick fix, or a topic that was rolled into another item.
- **#26 / #27**: Two consecutive gaps between #25 (Schema Drift in Prompts, May 6 13:36) and #28 (CommercialOnboardingWizard Unreachable, May 6 15:27) — a ~2-hour window on the same day. Could represent two items discussed but rolled into the bigger commercial-UX rework chapter that started with #28-#30.

**Recommendation:** Mark as **Missing** with status TBD pending Tyler's review. Reconstruct from session transcripts if available, or formally retire the numbers in MEMORY.md.

### 3.3 Item #36: referenced but no standalone file

Item #36 is referenced in the description text of Item #37 in MEMORY.md ("per Item #36, three-tier customer segmentation") and is referenced in `docs/commercial_ux_phase_4a_decisions.md` ("Customer Segmentation (from Item #36) — Tier 1: Residential / Tier 2: Single-business commercial / Tier 3: Multi-unit / enterprise commercial").

The substance of Item #36 is currently captured in the Phase 4a planning doc, not in a memory file.

**Recommendation:** Mark as **Embedded**. Tyler should decide whether to:
- (a) Create `project_customer_tier_segmentation.md` from the Phase 4a doc's segmentation section (recommended — three-tier model is referenced from multiple downstream phases and deserves its own pointer)
- (b) Leave as-is (Phase 4a planning doc serves as the canonical source)

---

## 4. MEMORY.md Index Integrity

### 4.1 All file links in MEMORY.md exist on disk

Verified each link target exists:

- `feedback_field_context.md` ✅
- `remote_access_architecture.md` ✅
- `feedback_connectivity_defaults.md` ✅
- `esp32_bridge_flashing.md` ✅
- `feedback_model_serialization.md` ✅
- `feedback_sales_pipeline.md` ✅
- `project_firestore_rules_deploy.md` ✅
- `project_staff_auth_open_items.md` ✅
- `project_install_flow_partial_success.md` ✅
- `project_parallel_session_coordination.md` ✅
- `project_schema_drift_prompts.md` ✅
- `project_commercial_onboarding_unreachable.md` ✅
- `project_commercial_onboarding_silently_broken.md` ✅
- `project_commercial_ux_architectural_rework.md` ✅
- `project_brand_preseed_silent_fail.md` ✅
- `project_commercial_activation_dual_paths.md` ✅
- `project_commercial_fields_no_post_install_ui.md` ✅
- `project_commercial_smoke_test_drift.md` ✅
- `project_commercial_profile_tab_misnamed.md` ✅
- `project_commercial_route_retirement_phase6.md` ✅
- `project_brand_seeds_2026_05_06.md` ✅
- `wipe_operations.md` ✅

**No broken links.** Index integrity is clean.

### 4.2 All on-disk files referenced in MEMORY.md

Every memory file present on disk is reachable from MEMORY.md, either via explicit Open-Items entry or via narrative reference (e.g., `feedback_field_context.md` is referenced in the Network Devices header warning, not in a "Files" section).

**No orphan files.** Conversely, `audit_logs/` subdirectory is referenced obliquely via `wipe_operations.md`'s description ("audit logs in memory/audit_logs/") rather than directly in MEMORY.md — this is fine since MEMORY.md indexes the operational doc, which then points to the subdirectory.

### 4.3 Description accuracy spot-check

Spot-checked five MEMORY.md descriptions against actual file contents:

- **#22 (install flow):** description matches file body ✅
- **#28 (commercial onboarding unreachable):** description matches file body ✅
- **#30 (commercial UX rework):** MEMORY.md says "STUB pending Tyler's verbatim" — file body confirms it is in fact a stub awaiting Tyler's substantive content. ✅ Description accurate.
- **#32 (dual atomic-batch paths):** description matches ✅
- **#37 (commercial route retirement):** description matches ✅

All spot-checked descriptions accurate. No drift between MEMORY.md and file bodies.

### 4.4 Item #37 wording note (no action — informational)

Item #37's MEMORY.md entry references Item #36 inline ("per Item #36"). This is the only place in MEMORY.md where #36 is mentioned, but #36 has no standalone entry of its own in the Open Items list. This is consistent with §3.3's "embedded" finding.

---

## 5. Recommendations Summary

### 5.1 Create new standalone files

| Recommendation | Item # | Reason |
|---------------|--------|--------|
| Create `project_customer_tier_segmentation.md` | #36 | Three-tier model is referenced from Phase 4a/4b/5/6 planning docs and downstream items; deserves a stable pointer rather than living embedded in a planning doc |

### 5.2 Investigate further (Tyler must answer)

| Recommendation | Item # | What to check |
|---------------|--------|---------------|
| Reconstruct or formally retire | #23 | Was this a real item between #22 (install flow, May 6 morning) and #24 (parallel sessions, May 6 13:36)? Check session transcripts |
| Reconstruct or formally retire | #26 | Was this a real item in the May 6 13:36-15:07 window between #25 and #28? |
| Reconstruct or formally retire | #27 | Same window as #26 — likely co-discussed |
| Verify references in audit prompts | #1-#21 | Confirm prompts referencing Items #1-#21 are not confusing staff-auth-internal subsections (1-17 inside `project_staff_auth_open_items.md`) with project-wide item numbers |

### 5.3 Mark as Skipped (likely never existed)

Items #1-#21 — recommend formally retiring this number range in any audit prompts. Project-wide item numbering began at #22.

### 5.4 No action required

- MEMORY.md index is clean (no broken links, no orphans).
- All existing item-tagged files are properly cross-referenced from MEMORY.md.
- Descriptions are accurate for spot-checked items.

---

## 6. Cross-Reference With Session Conversation

Session transcripts were **NOT** accessible during this audit. The user prompt noted this might be the case ("If the audit is run with access to session transcripts (it may not be — note if not)").

**What this means:** Items #11, #17, #23, #26 referenced in audit prompts cannot be validated against original conversation context. Tyler must validate these in the morning by:

1. Reviewing recent session transcripts (or the Claude Code session list) to find where Items #11, #17, #23, #26 were discussed
2. Confirming whether the references were to project-wide items (which gap-analysis above shows are missing) or to staff-auth-internal subsections (which exist in `project_staff_auth_open_items.md` as subsections 11 and 17)

If references in prompts to "Item #11" or "Item #17" actually mean staff-auth-internal subsections, those are findable:
- **Subsection 11** (referral_payouts trust-boundary follow-ups): [project_staff_auth_open_items.md:271](file://C:/Users/honey/.claude/projects/c--Flutter-Projects-Lumina-V-1-6/memory/project_staff_auth_open_items.md)
- **Subsection 17** (Commercial-mode zone editor reachable without PIN gate): [project_staff_auth_open_items.md:463](file://C:/Users/honey/.claude/projects/c--Flutter-Projects-Lumina-V-1-6/memory/project_staff_auth_open_items.md)

**Naming convention recommendation:** Future audit prompts should disambiguate by writing "staff-auth subsection 11" vs "project Item #11" to avoid this ambiguity. Numbering collisions between two sequences in the same memory directory are a known source of confusion.

---

## 7. Final Summary

- **Total memory files:** 23 markdown + 1 index + 1 subdirectory
- **Total project-wide items represented:** 11 standalone (#22, #24, #25, #28-#35, #37) + 1 embedded (#36)
- **Project-wide items missing:** 25 (#1-#21, #23, #26, #27, #36-as-standalone)
  - Of those, 21 (#1-#21) are likely **never assigned** as project-wide numbers — numbering started at #22
  - 3 (#23, #26, #27) are gaps in the otherwise-contiguous #22-#37 sequence; need Tyler verification
  - 1 (#36) exists embedded in Phase 4a planning doc but lacks a standalone memory file
- **MEMORY.md / file mismatch:** None observed
- **Recommendations summary:**
  - Create new file: 1 (Item #36 standalone)
  - Investigate further: 4 (Items #23, #26, #27, plus disambiguation of #1-#21 references)
  - Mark as skipped: 21 (#1-#21 — never existed)
  - No action: MEMORY.md index integrity is clean

**Overall health:** memory directory is well-organized with no broken indexes, no orphan files, accurate descriptions, and a clearly identified gap pattern. The primary risk is the staff-auth-internal vs project-wide numbering collision; future prompts should disambiguate by writing "staff-auth subsection N" vs "project Item #N".
