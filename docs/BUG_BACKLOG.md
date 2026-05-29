# Lumina — Bug & Work Backlog

**Last updated:** 2026-05-29 (post-closeout: #62/#81 unified + #82 shipped)
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

### #62 / #81 — My Designs unification + canonical apply (#81 stale-preview + wrong-label)
**Status:** IN BUILD (committed b7f335a, awaiting on-device verification)
**Shipped 2026-05-29:** My Designs flipped from a bespoke screen to a synthetic Explore category that renders saved designs as standard catalog cards and applies them through the SAME 6-step canonical apply the catalog uses (`applySavedDesign`). The degraded bespoke apply path (which skipped 5 of the 6 steps) is gone, so #81's stale-preview residual and wrong-label fallback are fixed as a consequence.
**Canonical apply chain (lib/features/design/apply_saved_design.dart):**
1. `SyncWarningDialog.checkAndProceed` (auto-pause Neighborhood Sync)
2. `effectiveChannelIds` U1 gate
3. `applyChannelFilter` (narrow seg[] to selected channels)
4. `repo.applyJson` (Bug B chokepoint — #77)
5. `wledStateProvider.notifier.applyPreviewSync` (kills stale-preview window — was the source of the blue+WHITE residual)
6. `activePresetLabelProvider.setLabelWithFingerprint(design.name, state)` (Now Playing = design's own name — kills the #81 wrong-label fall-through to effect-name lookup)
**Verification owed (on-device, 4-step repro):**
1. Apply Old Glory from Explore (3-color).
2. Open My Designs → apply an all-blue saved design.
3. Preview shows ONLY blue + Now Playing shows the design's name (NOT "Solid" / NOT "Halloween Eyes").
4. Force-quit + cold-start → still correct on relaunch.
Move to CLOSED only after this passes on the new build.

### #82 — kEffectNames off-by-one (Halloween Eyes vs Solid Pattern)
**Status:** IN BUILD (committed c8ed60a, awaiting cold-start label confirmation on device)
**Root cause:** Hand-maintained `kEffectNames` map in `lib/features/wled/wled_models.dart` had drifted from the firmware's actual effect order starting around id 37. id 83 was labeled "Halloween Eyes" when the device renders "Solid Pattern" there — which matters because `design_models.dart:185-187` substitutes fx=83 for multi-color solid designs, and the label fallback chain (#81) was surfacing the wrong name.
**Device-verified:** Pulled `/json/effects` from bench controller 192.168.1.250 (WLED 0.15.1, 187 entries, ending …Wavesins, Rocktaves, Akemi). Diffed every id against `WledEffectsCatalog.allEffects` — **zero name mismatches**. The catalog is authoritative.
**Shipped:**
- Deleted `kEffectNames` map (~120 stale lines).
- Switched 5 call sites to `WledEffectsCatalog.getName(id)` (already exposes device-canonical names + "Effect #N" fallback): `WledSegment.effectName` getter, `pattern_color_effects.dart` picker, `sync_control_panel.dart` (3 label sites).
- Patched catalog: added Rolling Balls (48) and Rotozoomer (114) — real device effects the catalog had miscategorized as retired. True RSVD slots (53, 142, 151, 161, 169, 170, 171) remain firmware placeholders.
- New parity test (`test/features/wled/effects_catalog_device_parity_test.dart`) locks 12 indices against the device array. 193/193 wled tests pass; flutter analyze clean.
**Display-only.** No data migration needed: fx substitution in `design_models.dart:185-187` was always correct (83 IS Solid Pattern on device — multi-color solid designs have been rendering the right effect on hardware). No firmware impact. Fixed `commercial_home_screen_test.dart` fixture that was asserting the old (wrong) label for fx=84.
**Verification owed:** Cold-start after a multi-color solid apply → Now Playing shows "Solid Pattern" (or the design's own name via the #62/#81 path), NOT "Halloween Eyes".

### #63 — Ellie field bugs: Game Day team propagation cluster (E1/E3/E5)
**Status:** OPEN — revised 2026-05-29; three distinct bugs sharing one disease (writer ≠ reader), ready to fix
**Reported:** Ellie Cochran, 2026-05-27. Diagnosed 2026-05-29 via writer/reader sweep.

**E1 — Installer-added favorite teams don't transfer to Game Day:**
Installer writes team data to **profile fields only** (favorite teams array on the user doc). Game Day reader requires team data in BOTH the profile fields AND a `/game_day_autopilot/{teamId}` subcollection entry. Intersection of (profile-has-team) ∩ (subcollection-has-team) = ∅ → Game Day shows nothing.

**E3 — Explore "My Teams" never populates:**
`updateMyTeams()` has **zero call sites** — completely dead wire. Whatever surface was supposed to invoke it (most likely Game Day team add or the team picker) was never connected. Explore's "My Teams" read therefore always sees an empty list, regardless of what the user added in Game Day.

**E5 — Refresh + sync-schedule doesn't pick up newly added teams:**
Team picker writes new teams with `enabled: false`. The sync path reads with an `enabled: true` filter only. Compounding: the Refresh action doesn't force-bypass the 7-day staleness gate, so even after a manual flip to `enabled: true`, sync skips the team if it was touched within the gate window.

**Fix shape (shared service):**
`TeamRegistrationService.addTeam()` — one chokepoint that writes (a) the profile fields, (b) the `/game_day_autopilot/{teamId}` subcollection entry, and (c) invalidates the Explore "My Teams" cache. All three current writers (installer flow, Game Day team add, Explore add) route through it. Closes the E1 ∩-empty bug, kills the E3 dead wire (by deleting `updateMyTeams()` and replacing its intended callers with `addTeam()`), and gives E5 a single place to enforce the enabled-default decision.

**E5 product decision PENDING from Tyler:** When a user adds a team, should autopilot turn ON for that team automatically (enabled: true) or stay OFF until the user explicitly toggles it (enabled: false + the Refresh path needs the gate-bypass)? Both are defensible — affects whether E5's fix is one-line (default true) or two-part (default false + Refresh bypass). Ready to implement either way as soon as Tyler picks.

### #77 — Cold-start preview/label leak — WLED writer paths bypassed Bug B chokepoint
**Status:** IN BUILD (committed e222dde, awaiting on-device verification)
**Surfaced by:** Tyler 2026-05-29 — after a solid-blue apply on Pulla, cold-start showed Now Playing label "Solid" instead of the real pattern name AND dashboard preview rendered 3 colors despite the device being solid blue.
**Root cause:** Bug B (`normalizeWledPayload` col[] padding, commit `e556251` 2026-05-23) was correct but only covered the `applyJson` chokepoint. Four sibling writer paths (`WledService.setState`, `CloudRelayRepository.setState`, `WledService.savePreset`, `CloudRelayRepository.savePreset`) bypassed it. Single-color writes left col[1]/col[2] holding the prior pattern's values on the device; the next poll faithfully read them back. Multi-slot col then poisoned the persisted-label fingerprint, so `reconcileWithDeviceState` dropped the Lumina label and Now Playing fell through to the raw effect name ("Solid" for effectId 0).
**Audit document:** the 2026-05-29 read-before-edit diagnostic refuted the leading "persisted state rendered before first poll" hypothesis (no persistence of `WledStateModel` exists) and identified the device-side stale-col[] leak as the true source. Writer sweep also confirmed background workers post to Cloud Functions, not directly to WLED — see #78.

**Implementation landed 2026-05-29 (commit e222dde):**
- WledService.setState → routed through applyJson (chokepoint pickup)
- CloudRelayRepository.setState → same redirect; bridge firmware confirmed command-name-agnostic (esp32-bridge/src/main.cpp:821-825)
- WledService.savePreset → pre-normalize state (restructured so sim hook captures wire-equivalent state)
- CloudRelayRepository.savePreset → pre-normalize state
- _applyStateData solid-mode (fx=0) guard → parses only col[0] when effectId == 0; retroactively heals already-stuck devices
- 9 new tests (3 normalize + 4 savePreset wire + 4 read-side guard, final test proves end-to-end persisted-label recovery)
- 259/259 tests pass across wled + lease-manager. flutter analyze clean (no new issues).

Follow-up commit 7ddb8cc closed additional coverage gaps per audit spec:
- WledService.setState gets 7 dedicated wire-shape tests via a new `lastSimulatedSetStatePayload` capture hook (payload-build hoisted above the sim branch so the captured shape mirrors the post-normalize wire payload).
- fx=83 (Solid Pattern, multi-color) regression added — confirms the solid-mode guard scopes strictly to fx==0 and does not trim named multi-color effects.
- CloudRelayRepository.setState and savePreset are covered by composition (identical payload-build, same normalize chokepoint as their WledService siblings); direct wire tests deferred pending `fake_cloud_firestore` test infra.

**Verification owed (on-device, formal — not eyeball):**
1. Apply 3-color catalog pattern → device + preview both 3 colors.
2. Apply solid blue (fx=0) → device truly solid blue, preview ONLY blue.
3. Force-quit + cold-start → preview STILL only blue, Now Playing label shows real pattern name (not "Solid").
4. 2-color → 1-color via schedule-lease / savePreset path → both clean.
5. Rapid brightness-slider drag (setState path) → no symptom.
6. Repeat 1-5 in remote mode (CloudRelayRepository path).
Move to CLOSED only after this sequence runs and is documented.

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

### #78 — Audit Cloud Function WLED payload paths for same chokepoint leak
**Status:** OPEN
**Surfaced by:** 2026-05-29 writer sweep during #77 fix.
Background workers (`game_day_autopilot_background_worker.dart:487`, `sync_event_background_worker.dart:483/686/785/999/1072/1114`) POST to `$_functionsBaseUrl/applySyncPattern` and other Cloud Functions, which then dispatch to controllers/bridges server-side. If those Cloud Functions build WLED payloads without an equivalent `normalizeWledPayload` step, the same col[] stale-slot leak exists on the server side and re-poisons devices on autopilot/sync fires regardless of client-side fixes. Audit `functions/src/` for any WLED payload construction; ensure parity with the client's `normalizeWledPayload` chokepoint. Out of scope tonight; required follow-up before the client-side fix can be considered complete across all surfaces.

### #79 — CloudRelayRepository wire-level test coverage gap
**Status:** OPEN (deferred from #77)
**Surfaced by:** #77 implementation (e222dde / 7ddb8cc).
All 4 bypass sites are fixed; wire-level tests cover only the 2 WledService sites. CloudRelayRepository.setState and .savePreset have composition proof (line-by-line mirrors of WledService siblings, same applyJson chokepoint redirect, same pre-normalize approach) but no direct wire assertion. Adding direct coverage requires `fake_cloud_firestore` + Firebase init scaffolding (~30-45 min). Deferred at session close 2026-05-29; composition + on-device Step 6 remote-mode repeat covers the gap for now. Worth closing eventually for explicit symmetry with WledService coverage.

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
**Status:** SUPERSEDED by #77
Verification owed merged into #77's gate; this item closed. The 2026-05-29 audit showed Bug B was correct but incomplete (four bypass sites), so the new on-device sequence in #77 subsumes Bug B's belt-and-suspenders check.

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
