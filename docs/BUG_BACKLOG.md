# Lumina — Bug & Work Backlog

**Last updated:** 2026-05-28
**Branch context:** `submission/app-store-v1`
**Firestore project (source of truth):** `icrt6menwsv2d8all8oijs021b06s5`
> ⚠️ NOT `nex-gen-lumina-22751` — a stale CLI override pointed there on 2026-05-27 and nearly caused a wrong-project rules deploy. Always run `firebase use icrt6menwsv2d8all8oijs021b06s5` and confirm before any `firebase deploy`.

---

## How to use this file
- Items carry IDs continuing Tyler's existing numbered scheme (#50+).
- Status: **OPEN** / **IN BUILD** (code committed, awaiting on-device verify) / **BLOCKED** / **DEPLOYED-LIVE** / **CLOSED**.
- Rules changes follow the standing discipline: confirm project target → `--dry-run` → Playground (own ALLOW / cross-user DENY / unauth DENY) → diff review → explicit approval → deploy → verify in-app → commit `firestore.rules`.
- Firmware changes only for: safety, bricking risk, network regression, security, data corruption. Every Claude Code prompt carries a `FIRMWARE IMPACT:` line.

---

## 🔴 HIGH PRIORITY — OPEN

### #61 — iOS "Detect Home Network" SSID — verify the profile fix landed
**Status:** IN BUILD (fixed at source, awaiting on-device confirmation)
**Root cause (confirmed 2026-05-28):** Two App Store provisioning profiles existed for `com.nexgenled.command`. Codemagic's `fetch-signing-files --create` was building with `Lumina ios_app_store 1778537934`, which was **missing** the "Access Wi-Fi Information" capability. The hand-made `Lumina AppStore 2` had it, but wasn't the one in use. App returned `getwifiname_null` despite a fully-correct entitlement chain (entitlements file ✅, all build configs wire to it ✅, App ID capability ✅, Info.plist strings ✅, Core Location awake ✅).
**Action taken:** Deleted the stale `1778537934` profile. Next Codemagic build will regenerate a fresh profile (or fall back to `Lumina AppStore 2`) — either carries the capability since the App ID has it enabled.
**Remaining:** On the next build, watch the "Fetch signing files" step (must succeed — flag if API key lacks create-profile permission). After install, tap Detect Home Network → expect GREEN "Home network saved." If still failing, the instrumentation (`e8d3bf7`) now surfaces the specific reason in-app — read the new red-bar string; a *different* reason means a second layer (plugin/iOS-version). The diagnostic path already ruled OUT Core Location.
**Files:** `lib/services/connectivity_service.dart` (instrumentation only), iOS signing (portal-side fix, no code).

### #62 — My Designs unification (Tier 2) — DECISION LOCKED: Option A3
**Status:** OPEN (fresh-session feature work; prerequisite `/designs/` rule now DEPLOYED-LIVE)
**Decision:** A3 — dual collections, unified read. Catalog stays pristine; all user-created/edited designs surface in the My Designs folder.
**Why not a simple migration:** `EditablePattern` (flat, channel-agnostic) and `CustomDesign` (per-channel) model fundamentally different things; translation is lossy both ways. So: keep `EditablePattern` in `/patterns/`, keep `CustomDesign` in `/designs/`, and have `MyDesignsScreen` read BOTH, merge, sort by `updatedAt`, render two card variants.
**Three creation surfaces must all feed My Designs:**
1. **EditPatternScreen** → `/patterns/` → writes today (post rule), but: (a) reuses the catalog slug as doc id → re-editing the same catalog pattern OVERWRITES the prior save; needs a fresh unique id + `sourcePatternId` provenance field; (b) no `createdAt`/`updatedAt` timestamps → can't sort.
2. **AI Design Studio** `_handleSaveDesign` → **TODO STUB, writes nothing** (toast only). Needs BUILDING, not migrating. `ComposedPattern → CustomDesign` adapter is ~20 lines (both channel-shaped) → writes `/designs/`. `_handleApplyToLights` is also a TODO stub.
3. **SaveCustomPatternDialog** (3 paths: "Save As", "Save unsaved custom", duplicate) → `/designs/` → already correctly wired; unblocked by the `/designs/` rule deployed 2026-05-28.
**Scope:** ~3–5 dev-hours. Files: `editable_pattern_model.dart` (add fields + extend copyWith/toJson/fromJson), `edit_pattern_screen.dart` (fresh id, timestamps, sourcePatternId), `colorway_effect_selector.dart:~443` (stop passing slug as id), `my_designs_screen.dart` (second stream + EditablePattern card variant + route its edit-tap to EditPatternScreen, not Design Studio).
**Keep:** static `_ColorPreview` swatch for v1 (per-card `AnimatedRooflineOverlay` deferred — battery cost).
**DO NOT TOUCH:** catalog source/read path, `AnimatedRooflineOverlay`/`RooflineLightPainter`.

### #63 — Ellie field bugs: Game Day team propagation cluster (E1/E3/E5)
**Status:** OPEN (likely ONE root cause)
**Reported:** Ellie Cochran, 2026-05-27.
- **E1:** Installer-added favorite teams don't transfer to the end user in Game Day.
- **E3:** Explore tab "My Teams" shows no teams even after adding them in Game Day.
- **E5:** Adding teams to "My Teams" + "sync schedule" doesn't add them to that day's schedule.
**Claude's read:** Same architectural pattern as the My Designs orphan and the participation-cache bug — **a feature writes teams to one location; the surfaces that should display them read from a different location.** Debug approach: map ALL team writers vs. ALL team readers (installer flow, end-user view, Explore "My Teams", schedule-sync). The write target is almost certainly orphaned from the read surfaces.

---

## 🟡 MEDIUM PRIORITY — OPEN

### #64 — Ellie E2: Game Day team add is single-select only
**Status:** OPEN
Adding teams is one-at-a-time (select → menu closes → reopen for next). Needs multi-select in one pass. Contained to the team-picker widget (`_TeamPickerSheet` in `game_day_screen.dart`, or the sibling pickers).

### #65 — Ellie E4: Calendar can't show Game Day + regular schedule for a selected date
**Status:** OPEN
No way to tap a date and see both the Game Day autopilot entries and regular schedules for that day. Feature gap. Connects to the parked Game Day phase-machine work.

### #66 — Design Studio Tier 2: implement the save/apply stubs
**Status:** OPEN (part of / adjacent to #62)
`_handleSaveDesign` and `_handleApplyToLights` in `ai_design_studio_screen.dart` are TODO stubs (toast only, no Firestore write, no `applyJson`). The orchestrator pipeline (NLU/ConstraintSolver/ClarificationService/PatternComposer) WORKS — only the terminal actions are unwired. Implement save → `/designs/` via `DesignService` (same as the working SaveCustomPattern paths); implement apply → the real `applyJson` path.

### #67 — `BTAmiOGW...` orphan UID + bridge `D4E9F4FA8E78`
**Status:** OPEN (parked, not actively harmful)
Third orphan UID discovered during the 2026-05-27 cleanup; bridge paired to a deleted UID, status `paired`, NOT blocked by the current rule (only `xBnFxkN6` and `ASeUR5n` are listed). Closed automatically by #68 if/when that lands.

### #68 — Generalize orphan-bridge rule to "deny if pairedUid doesn't resolve to an existing user"
**Status:** OPEN (architectural fix)
Replaces the hardcoded blocked-UID list in `isNotBlockedDeletedUid()` with an existence check, closing ALL orphan bridges (incl. #67) without manual list maintenance. Cost: a Firestore `exists()` check on every `bridge_registry` write. Once live, the current hardcoded list entries (`xBnFxkN6`, `ASeUR5n`) can be removed (explicit REMOVE comments are in `firestore.rules`).

### #69 — Pre-wipe orphan scan in `clear_account_state.js`
**Status:** OPEN (procedural fix)
Before a user wipe, query `bridge_registry` for all `pairedUid` values, check each against Auth, and surface/handle orphans BEFORE deleting — so cleanups don't keep discovering live orphan bridges mid-run (the recurring pain of the 2026-05-27 session).

---

## 🟢 LOWER PRIORITY / POLISH — OPEN

### #70 — Roofline trace zoom / magnifier loupe
**Status:** OPEN
For point-placement accuracy during roofline tracing. Magnifier-loupe is the recommended first move; normalized 0–1 coords cooperate.

### #71 — iOS `connectivity_service` Crashlytics non-fatal for null SSID
**Status:** OPEN (secondary rec from the SSID audit)
Log a non-fatal when SSID read returns null, so future occurrences are visible without a Mac/Xcode.

### #72 — Automate Firestore rules tests
**Status:** OPEN
Grant the service account `firebaserules.rulesets.test` (so `scripts/_test_rules_block.js` works) OR set up the Firestore emulator + `@firebase/rules-unit-testing`. Currently rule verification is manual via Console Playground.

### #73 — On-device verification of channel-2 participation reconciler (`cc62c39`)
**Status:** OPEN (committed + unit-tested, never verified on hardware)
On the new build: open dashboard with a deliberately-stale participation cache → channels should self-correct. (Ellie's original channel-2 greyed-out bug.)

### #74 — Formal on-device verification of Bug B preview parity (`e556251`)
**Status:** OPEN (optional — already eyeballed as working)
The commit message's 4-step sequence: 3-color → 1-color → reverse → purple twinkle → white solid. "Previews look better" already confirms it in practice; this is belt-and-suspenders.

---

## 🧱 TECH DEBT

### #TD-1 — Migrate schedules off the user-doc array field
**Severity:** HIGH (before 100 active users)
Move from an array field on the user document to `/users/{uid}/schedules/{scheduleId}` subcollection. Touches `schedule_providers.dart`, `user_model.dart`, Firestore rules, and all schedule read/write paths.

### #TD-2 — Remove dead `_controllerIps` plumbing
**Severity:** MEDIUM
From sync/game-day background workers, after `applySyncPattern` Cloud Function is confirmed in production.

### #TD-3 — Cloud Functions Node 20 → 22
**Severity:** MEDIUM (before Oct 2026 decommission)

---

## 🧩 RECURRING ARCHITECTURAL THEME — worth a strategic look

**Writer ≠ Reader.** Across THREE feature areas, features write user content to their own collection/location while the surface meant to display it reads from somewhere else:
- **Patterns:** EditPatternScreen writes `/patterns/`; My Designs reads `/designs/`. (#62)
- **Designs:** Design Studio doesn't write at all (stub); SaveCustomPattern writes `/designs/` but the rule was missing. (#62/#66)
- **Teams:** Game Day writes teams somewhere the end-user view / Explore / schedule-sync don't read. (#63)

Also the participation-cache bug (data written under one device-state context, read under another) and the orphan-bridge issue (data written under a deleted identity).
**Consideration:** at some point a "unified user-content read layer" audit may be worth more than fixing each surface one at a time. Flagged for strategic, not immediate, attention.

---

## ✅ CLOSED THIS SESSION (2026-05-27 → 2026-05-28)

- **Orphan-bridge cleanup** — 3 UIDs (`xBnFxkN6`, `ASeUR5n`, `68e8MeB`) surgically wiped (Auth + Firestore + cross-refs), zero errors. Rule block (`isNotBlockedDeletedUid`) deployed + committed. Audit archived to `memory/audit_logs/`, `memory/wipe_operations.md` updated.
- **`/patterns/` Firestore rule** — was missing → default-deny since the pattern editor shipped. Added isOwner CRUD, Playground-verified, DEPLOYED-LIVE to the correct project. Pattern save now works.
- **`/designs/` Firestore rule** — same missing-rule class. Added isOwner CRUD, Playground-verified (4/4), DEPLOYED-LIVE. Unblocks SaveCustomPattern "Save As" / "Save unsaved custom" / Duplicate; My Designs now populates.
- **Design Studio — nav-bar occlusion** — clarification dialog Continue/Back buttons (and input/action/quick-ideas) were hidden under the glass dock. Added `navBarTotalHeight(context)` bottom padding (`SafeArea(bottom:false)`), matching the established convention.
- **Design Studio — clarification no-op** — `_handleClarificationsComplete` read `applyClarificationsProvider` (a `FutureProvider`) without triggering it; fixed via `ref.refresh(...future)`.
- **Design Studio — async error handling** — both `_handleSubmit` and `_handleClarificationsComplete` could leave status stuck on `processing` with no user feedback on orchestrator error; now surface a toast + reset to an inputable state. (Consistent across both handlers.)
- **Game Day team picker occlusion** (`_TeamPickerSheet`) — "couldn't scroll" was actually bottom rows rendering under the glass dock. Added `navBarTotalHeight(context)+16` bottom inset, matching sibling pickers.
- **Neighborhood Sync side-by-side buttons** (`b77b5ca`) — made symmetric (equal width/height, centered, bold/15, `Size.fromHeight(52)`), primary/secondary styling preserved.
- **Channel-2 participation reconciler** (`cc62c39`) — stale participation cache (cache `[0]` vs expected `[0,1]`) fixed via `isParticipationCacheStale()` predicate + foreground reconciler; 10 tests pass. (On-device verify still pending — #73.)
- **Bug B preview parity** (`e556251`, shipped 2026-05-23) — confirmed already live; pads WLED `seg.col[]` to 3 slots with `[0,0,0]` in `normalizeWledPayload` so stale color slots clear on apply. Verified-by-eye. (Formal verify optional — #74.)
- **iOS SSID stale provisioning profile** — root-caused and fixed at source (deleted stale `1778537934` profile). Verification pending on next build (#61).

### 📌 RECURRING GOTCHAS (learned this session)
- **"Can't tap/reach something at the bottom of screen X"** — suspect glass-dock occlusion. Fix = `navBarTotalHeight(context)` bottom padding. Hit THREE times this session (Design Studio, Game Day picker, plus the existing convention in my_schedule_page/edit_profile).
- **Rules deploy dry-run printing "enabling API / creating database"** — WRONG-PROJECT alarm, not boilerplate. Confirm `firebase use` target first.
- **"Looks fixed" / "tests pass"** — verify the actual runtime/on-device outcome, not the inference. (The SSID warm-up "fix" survived as a bug; the wrong profile looked correct because we inspected the wrong one.)
- **Map all writers before fixing the reader** — the orphan bridges, patterns, designs, and teams all reinforce this.
