# Phase 4a Decision Lock — 2026-05-06

This document records foundational decisions for Phase 4a of the commercial UX rework. These decisions constrain Phases 4b, 4c, 4d, 5, and 6. Changing any of them post-Phase 4a requires explicit reconsideration of downstream phases.

## Branch Strategy

- All Phase 4 work (4a, 4b, 4c, 4d), Phase 5, and Phase 6 lands on `feature/commercial-ux-rework` branch
- Critical bug fixes to `submission/app-store-v1` cherry-picked into feature branch as needed
- Branch merges back to `submission/app-store-v1` when Phase 6 completes and full rework is verified end-to-end
- TestFlight builds from `submission/app-store-v1` reflect production-stable state during rework

## Architectural Principle (from Item #30)

**Commercial = residential + capabilities.** Commercial customers experience the polished residential UI, with commercial-specific features layered as additive surfaces accessible from settings.

## Customer Segmentation (from Item #36)

- Tier 1: Residential — single home, family
- Tier 2: Single-business commercial — Steve's Blue Line Bar, Diamond Family Jewelers (current commercial customers fall here)
- Tier 3: Multi-unit / enterprise commercial — future, deferred until first multi-unit customer enters pipeline

Phase 4a targets tier 2. Phase 4-6 work uses `isCommercialProfileProvider` (true for any `profile_type == 'commercial'`) which currently maps to tier 2. When tier 3 customers exist, segmentation refines.

## Phase 4a Decisions

### Q1 — Entry pattern: Pattern X (single Business Tools card → sub-list)

A single "Business Tools" card on the residential settings page, gated by `isCommercialProfileProvider`. Tapping it opens a sub-list screen containing Brand library and Events entries (plus future commercial features added in 4b/4c/4d/5).

**Rationale:** forward-compatible for sub-list growth, zero residential UX risk (gated card), aligns with Item #37's `/commercial` retirement direction (all commercial features eventually route through residential settings).

**Rejected alternatives:**
- Pattern Y (multiple top-level cards) — settings page bloats to 10+ cards as commercial features grow
- Pattern Z (AppBar/bottom-nav addition) — modifies shared scaffold, residential UX regression risk

### Q2 — Card label: "Business Tools"

Functional, unambiguous, formal-but-friendly. Used consistently across all downstream phases for menu, navigation, route paths, breadcrumbs, internal references.

**Rejected alternatives:** "Commercial Features" (sales-pitch tone), branded ("[CompanyName] Tools" — awkward with longer business names), "For Your Business" (too informal for settings).

### Q3 — Sub-list screen styling: residential glass/cyan (NexGen palette)

Sub-list screen and all downstream commercial-tool surfaces use residential's glass/cyan styling consistent with NexGen palette. NOT the existing commercial dashboard's styling.

**Rationale:** visual consistency is part of the "commercial = residential + capabilities" promise. Importing parallel-UX styling would defeat Phase 3a's architectural shift.

### Q4 — Discovery hint for residential customers: fully hidden

Residential customers see no "Business Tools" card, no "available with commercial upgrade" affordance, no preview. The card simply doesn't render for `profile_type != 'commercial'`.

**Rationale:** Lumina's positioning isn't enterprise-software-style upselling. Residential customers who need commercial features convert their account via the eventual short conversion flow (deferred Item #28).

### Q5 — Tier-3 (enterprise) inclusion: same gate for now

Card appears for any `profile_type == 'commercial'`. When tier-3 customers enter the pipeline (per Item #36), introduce a third profile_type value and reconsider what appears in the Business Tools sub-list for tier-3 vs tier-2.

**Rationale:** premature segmentation now is wasted scaffolding. No tier-3 customers exist; speculative tier-3 design decisions risk being wrong when real tier-3 customers articulate needs.

## Foundational Decisions for Phases 4b/4c/4d/5

### Sub-list screen location and naming
- File: `lib/features/site/business_tools_screen.dart` (new)
- Class: `BusinessToolsScreen`
- Located alongside `settings_page.dart` to reflect its semantic role as a settings sub-section

### Route convention
- Card route: `/settings/business-tools`
- Brand library entry: `/settings/business-tools/brand` (or reuse existing `/commercial/brand/search` — TBD during 4a implementation based on whether existing routes can be sub-pathed)
- Events entry: `/settings/business-tools/events` (or reuse existing routes — same TBD)

### Visual pattern
- Sub-list uses settings-style card components (consistent with `settings_page.dart`'s 8 universal cards)
- Each entry is a card with icon, title, subtitle, chevron-right
- Card subtitles describe what the feature does in plain language (matches `settings_page.dart` card pattern)

### Provider gating
- All Business Tools surfaces gate visibility via `isCommercialProfileProvider`
- Riverpod providers consumed (`commercialBrandProfileProvider`, `commercialEventsProvider`, etc.) require no re-architecture — they're plain StreamProviders that activate from any context

### Reuse-first principle
- BrandSearchScreen, BrandSetupScreen (customer-edit mode), EventsScreen, CreateEventScreen are reused AS-IS
- No restyling of existing commercial-feature screens unless they're genuinely broken
- Visual consistency comes from the sub-list screen and how it presents the entries, not from rebuilding what's already inside

### Discovery
- Sub-list reachable only from Settings → Business Tools card
- No quick-action shortcuts on residential home (per audit Q3 logic — keeps the menu canonical)
- Future quick-actions (if needed) added in Phase 4b/4c/4d as features warrant

## Phase 4a Implementation Scope (estimated)

- Files modified: 2-3 (`settings_page.dart`, possibly `app_router.dart`, planning doc)
- Files created: 1-2 (`business_tools_screen.dart`, possibly extracted card widget)
- Lines of new code: ~150-250
- Sessions: 1
- Smoke test: card visibility (commercial vs residential), sub-list navigation, Brand/Events entries reach correct screens, back-nav returns to settings, residential regression check

## Branch Lifecycle

- Created: 2026-05-06 evening, off `submission/app-store-v1` at commit 3c8cfdb
- Active phases: 4a (this), 4b, 4c, 4d, 5, 6
- Critical bug fixes to submission branch: cherry-pick into feature branch
- Merge target: `submission/app-store-v1` after Phase 6 completes and end-to-end testing is clean
- Merge style: TBD (squash vs merge commit) based on repo's existing convention

## Open Items Cross-References

- Item #28: CommercialOnboardingWizard unreachable — fate decided as "replace with short conversion flow in residential Settings" (Phase 5 territory)
- Item #29: Commercial onboarding silently broken — root cause resolved by `firestore.rules` deploy (commit 156ec67)
- Item #30: Commercial UX architecturally wrong — being addressed by Phases 2-6
- Item #31: Brand pre-seed silent-fail — fixed via rule update (commit 594bfdf)
- Item #32: Dual atomic-batch write paths for commercial activation — extract to `CommercialAccountService` in Phase 6
- Item #33: Commercial fields without post-install UI — Phase 5 expanded to cover these
- Item #34: Smoke test references nonexistent UI — Phase 6 reconciliation
- Item #35: Commercial Profile tab misnamed — Phase 4 cleanup
- Item #36: Three-tier customer segmentation — informs all future commercial UX work
- Item #37: `/commercial` route retirement scheduled for Phase 6
