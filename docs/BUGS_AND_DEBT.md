# BUGS_AND_DEBT — canonical tracking ledger

**As of 2026-07-22 (post schedule-stack saga).** This is the working checklist for all known
bugs, tech debt, and promised features. Not documentation prose — keep it terse.

## Conventions
- **Never delete an item.** When fixed, check it off (`[x]`) and append the fixing commit SHA.
- **Every fix that claims bench verification MUST cite the readback** (curl `/json/state` or
  `/json/cfg` output, or a saved dump path). "Bench-verified" with no readback is not verified.
- **Evidence tags** — `bench-proven` (reproduced on hardware w/ readback) · `reported`
  (observed in-app, not isolated) · `suspected` (inferred, unconfirmed).
- **WLED behavior-claim rule:** every claim about WLED behavior must be tagged
  `verified-by-bench` / `verified-by-source` / `assumption`. Only the first two may appear in
  a fix prompt. Assumptions get bench-checked (see #21) before they gate code.
- Status values: `OPEN` · `IN-PROGRESS` · `BLOCKED` · `DONE <sha>`.
- **This is the ONE home for items.** `docs/BUG_BACKLOG.md` was folded in here on 2026-07-22
  (items #61–#85, #TD-1..3). That file is now a pointer — do not add items there.
- **Firestore project (source of truth):** `icrt6menwsv2d8all8oijs021b06s5`. NOT
  `nex-gen-lumina-22751`. Always `firebase use icrt6menwsv2d8all8oijs021b06s5` and confirm
  before any `firebase deploy`.

---

## P0 — customer-visible, blocks "sell with certainty"

- [ ] **P0-1 — AI intent applies scheduled commands IMMEDIATELY (Symptom B)**
  - Status: OPEN · Evidence: bench-proven
  - "warm white 2:25–2:30" changed lights instantly and wrote **zero** timers. The AI
    text/voice path bypasses the hardened schedule-sync entirely.
  - Files: `lib/features/ai/scheduling_intent_handler.dart`,
    `lib/features/ai/scheduling_intent.dart`, `lib/features/ai/lumina_smart_scheduler.dart`,
    `lib/features/ai/cloud_ai_processor.dart`, `lib/features/ai/local_command_parser.dart`,
    `lib/features/ai/lumina_command_router.dart` → must route to
    `lib/features/schedule/schedule_sync.dart`.
  - Blocks: P0-2, P1-5, P1-11.

- [ ] **P0-2 — Remove "Generate week" button; port to text/voice intent handling**
  - Status: BLOCKED (by P0-1) · Evidence: reported (product decision made)
  - Don't consolidate the door onto a broken sync path. Land P0-1 first.
  - Files: `lib/features/schedule/my_schedule_page.dart` (generate-week UI),
    `lib/features/schedule/schedule_plan_controller.dart`; target = AI scheduling intent path.

- [ ] **P0-3 — Lease-writer unification (last fire-and-forget cfg writer)**
  - Status: OPEN · Evidence: reported
  - `calendar_entry_lease_manager` `_writeLeaseToWled` / `_writeZeroedSlot` write cfg with no
    verify, no readback, no guard. Route through the hardened cfg path (timeout+retry+readback+
    settle) used by `schedule_sync.dart`.
  - Files: `lib/features/schedule/calendar_entry_lease_manager.dart`.

- [ ] **P0-4 — System presets 1/3/4/5 ib-heal check**
  - Status: OPEN · Evidence: suspected (bench-verify pending)
  - Name-based skip in the psave path may prevent re-saving presets with `ib:true`; if stale,
    "NGL On / Dim / Low / Medium" won't assert master power when fired. Bench-verify AFTER a
    +51 Sync (curl presets.json); fix the skip trigger if the ib flag is absent.
  - Files: `lib/features/schedule/schedule_sync.dart` (`_scheduleDesignMatches` / psave skip).

---

## P1 — correctness & trust

- [ ] **P1-5 — Gamma drift root cause (Symptom C)**
  - Status: OPEN · Evidence: bench-proven (symptom) / suspected (cause)
  - `gc.col` flipped 2.8→1 during the AI-command window; self-healed by the pusher on-connect.
    Source never found. Fold into the P0-1/P0-2 AI-path diagnostic.
  - NEW EVIDENCE 2026-07-24: `gc.col` observed 2.8 at ~10:40 and 1 at ~10:47. Only actions in the
    window: P1-43 channel-power taps (`/json/state` only — CANNOT write cfg, so exonerated), app
    connects (pusher ASSERTS 2.8 — the medic, not the culprit), and throwaway schedule CREATION
    with a pattern + Sync. Sync itself was previously exonerated (gamma unchanged across multiple
    syncs 2026-07-21) → prime suspect NARROWS to the **design/pattern-apply path** — consistent
    with Symptom C's original AI-command window, which also applied a design. The caught-in-the-act
    diagnostic should instrument pattern/design applies FIRST.
  - Files: AI apply path (see P0-1) + design/pattern-apply path + `light.gc` writer (gamma push on connect).

- [ ] **P1-6 — Unexplained en:1 evidence row (git archaeology)**
  - Status: OPEN · Evidence: reported (contradicts curl truth table)
  - An f53eec7-era dump showed `en:1` from a reportedly-bool builder, contradicting the curl
    truth table (en must be INT). Pull the actual `f53eec7` blob, settle provenance, and record
    the answer in the en-int comment if it changes anything.
  - Files: `lib/features/schedule/schedule_sync.dart` (en-int comment); git `f53eec7`.

- [ ] **P1-7 — Orange "synced with 1 warning" identity**
  - Status: OPEN · Evidence: suspected (slot exhaustion at 8/8)
  - Never confirmed which warning fired. Answer from logs; ensure warning copy is
    user-interpretable.
  - Files: `lib/features/schedule/schedule_sync.dart` (sync result/warning),
    `lib/features/schedule/schedule_overload_banner.dart`.

- [ ] **P1-8 — Two stale tests mask real failures**
  - Status: OPEN · Evidence: reported (2 pre-existing suite failures)
  - `schedule_sync_time_parse` (asserts flag-disabled solar behavior) and
    `cloud_ai_processor_normalize` ('Sunset'). Fix or delete.
  - Files: `test/…/schedule_sync_time_parse*`, `test/…/cloud_ai_processor_normalize*`.

- [ ] **P1-9 — Roofline widget tests flaky under full-suite load**
  - Status: OPEN · Evidence: reported (pass in isolation, flake in suite)
  - Stabilize or quarantine explicitly (tagged skip w/ reason, not silent).
  - Files: `test/…/roofline*`.

- [ ] **P1-10 — Design-name attribution: schedule fires**
  - Status: OPEN · Evidence: bench-proven (2026-07-23 12:56 OFF fire: `ps:-1` after timer-fired preset load)
  - After a timer fires, app shows raw WLED effect names ("Solid", "Running") instead of the
    design name. **Diagnostic ANSWERED (was "curl /json/state, is ps the slot?"):** firmware
    does NOT leave `ps` pointing at the fired preset — `ps:-1` confirmed on the 12:56 fire. So
    this CANNOT be solved by a `ps → app-owned slot → design name` lookup; it requires the same
    "last applied design" record as P1-11.
  - Files: `lib/features/ai/pattern_label_resolver.dart`, dashboard state display in
    `lib/nav.dart`, + the persisted last-applied record shared with P1-11.

- [ ] **P1-11 — Design-name attribution: Game Day / live applies (ps:-1)**
  - Status: OPEN · Evidence: reported; `ps:-1` now bench-proven (2026-07-23) for timer fires too
  - Non-preset applies report `ps:-1` — and, per the 12:56 bench finding, so do timer-fired
    *preset* loads. So a "last applied design" record written at apply time is now REQUIRED for
    BOTH the live-apply case AND the schedule-fire case (P1-10); neither can lean on `ps`.
    **Rides with** the P0-1..P0-3 consolidation — instrument the surviving write paths, not the
    doomed ones.
  - Files: surviving apply paths (post-consolidation) + a persisted last-applied record.

- [ ] **P1-22 — My Designs apply + Now-Playing label (ex-#62/#81)**
  - Status: OPEN (code shipped `b7f335a`, on-device verify never recorded) · Evidence: reported
  - My Designs unified to an Explore category applying through the 6-step canonical apply
    (`applySavedDesign`); #81's stale-preview + wrong-label fall-through fixed as a consequence.
    Verify owed: apply saved all-blue design → preview only blue + Now Playing = design name
    (not "Solid"/"Halloween Eyes"); survives cold-start. Related to P1-10/P1-11 (attribution
    still broken elsewhere — this surface may share the fix).
  - Files: `lib/features/design/apply_saved_design.dart`, My Designs Explore category.

- [ ] **P1-23 — Game Day team cluster E1/E3/E5 (ex-#63)**
  - Status: OPEN (E1 shared service exists; E3/E5 unverified) · Evidence: reported (Ellie 2026-05-27)
  - Writer≠reader. E1: installer must route through `TeamRegistrationService.addTeam` (writes
    BOTH `/game_day_autopilot/` + profile `sports_teams`/`sports_team_priority`) —
    service now exists, confirm installer uses it. E3: `updateMyTeams()`/`clearMyTeams()` had
    zero call sites → Explore "My Teams" never populates; wire `patternRepositoryProvider` to
    `currentUserProfileProvider`. E5 (product-locked): autopilot toggle ON populates season
    calendar force-bypassing 7-day gate + tags entries by source; OFF tears down tagged entries.
  - Files: `lib/features/sports_alerts/services/team_registration_service.dart`,
    `patternRepositoryProvider`, Game Day picker, `calendar_entry_lease_manager.dart`.

- [ ] **P1-24 — Cold-start preview/label leak: verify across all writer paths (ex-#77)**
  - Status: OPEN (code shipped `e222dde` + `7ddb8cc`, formal on-device verify owed) · Evidence: bench-proven (symptom)
  - Bug B `normalizeWledPayload` col[]-pad chokepoint was bypassed by 4 sibling writers
    (`WledService.setState`/`.savePreset`, `CloudRelayRepository.setState`/`.savePreset`); all
    routed through `applyJson` + solid-mode read guard added. Run the 6-step on-device sequence
    (3-color→solid→cold-start→lease/savePreset→slider→remote-mode repeat) and document.
    Subsumes ex-#74 (Bug B `e556251` formal verify).
  - Files: `lib/features/wled/wled_service.dart`, `lib/features/wled/cloud_relay_repository.dart`.

- [ ] **P1-25 — Cloud Function WLED payload normalize parity (ex-#78)**
  - Status: OPEN · Evidence: suspected (surfaced by #77 writer sweep)
  - Background workers POST to `applySyncPattern` etc.; if Cloud Functions build WLED payloads
    without an equivalent `normalizeWledPayload` step, the col[] stale-slot leak re-poisons
    devices server-side on autopilot/sync fires regardless of client fixes. Audit
    `functions/src/` for WLED payload construction; ensure chokepoint parity.
  - Files: `functions/src/` (WLED payload builders), callers
    `game_day_autopilot_background_worker.dart`, `sync_event_background_worker.dart`.

- [ ] **P1-42 — LED layout change staleness: presets render wrong until next Sync**
  - Status: OPEN · Evidence: bench-proven (2026-07-23: channel-2 `hw.led` 30→73)
  - Resizing a channel's pixel count (`hw.led`) leaves ALL stored presets rendering wrong on the
    changed segments until the next Sync re-psaves them — presets bake segment geometry, so a
    layout change silently orphans them. Fix: detect layout drift in the sync (compare
    `hw.led.ins` against last-known) OR hook the layout-save flow to force a full preset re-save
    + user notice. **Workaround until fixed: Sync after any layout change** — surface this to users.
  - Files: `lib/features/schedule/schedule_sync.dart` (drift detect + re-psave), the
    channel/segment layout-save flow, `lib/features/schedule/calendar_entry_lease_manager.dart`
    (shares the psave path).

- [x] **P1-43 — Per-channel power is master-global (both channels toggle together)** — DONE `cdc436b`
  - Status: DONE `cdc436b` (merged to main `ad6ae98`, tag `v2.5.10+53`) · Evidence: bench-proven
  - BENCH-VERIFIED 2026-07-24 (192.168.1.150, build cdc436b/+53, 290 LEDs ch1=128/ch2=162): case 3
    (critical) from master-off, front on → ONLY front lit, one POST — PASS; case 4 back on while
    master on → seg-only, front undisturbed — PASS; case 1 front off → only front dies — PASS;
    case 2 last lit channel off → master reads off — PASS. Two-boundary throwaway also passed
    (curl /json/cfg 10:50 macro:10 / 10:55 macro:2, both en:1, dow:16; ON 10:50, OFF 10:55 fully
    dark). Fix: additive `setChannelPower` (live getState + fresh-bounds cfg refresh, id-only
    fallback) → `buildChannelPowerPayload` 4 shapes; per-chip power icon; `togglePower` + 5 master
    callers untouched; `/json/state` only.
  - Original diagnosis (bench-proven 2026-07-23: curl seg-scoped on:false darkened ch1 only; app
    power toggled both):
  - Firmware segment independence is confirmed
    (`{"seg":[{"id":0,"on":false},{"id":1,"on":true}]}` darkens ch1, leaves ch2 lit). The app's
    power path writes **top-level master `{"on":bool}`** regardless of the channel selector, so a
    per-channel off hits the whole device. There is NO seg-scoped OFF primitive anywhere:
    `applyChannelFilter` and `buildParticipatingSegArray` both force `on:true`; off is master-only
    by construction.
  - Wrong payload: `_postUpdate` sets `payload['on'] = on` top-level —
    [wled_providers.dart:1530](lib/features/wled/wled_providers.dart#L1530) (`on` deliberately
    excluded from `needsChannels` at :1494; never enters seg[] at :1547). Entry:
    dashboard power circle [wled_dashboard_page.dart:956](lib/features/dashboard/wled_dashboard_page.dart#L956)
    → `togglePower` [wled_providers.dart:1073](lib/features/wled/wled_providers.dart#L1073) → `_postUpdate(on:)`.
  - Mapping (sound): channel id = bus index, `start/stop` from `hw.led.ins[]` via
    `deviceChannelsFromConfig` [zone_providers.dart:83](lib/features/wled/zone_providers.dart#L83).
    Staleness risk (see P1-42): `deviceHardwareConfigProvider` caches `/json/cfg`, invalidated only
    at [system_management_screen.dart:238](lib/features/site/system_management_screen.dart#L238) or
    app restart — so a seg-scoped off with stale bounds (ch2 73 vs 160) could leave the new pixels lit.
  - Fix (additive, minimal): a seg-scoped per-channel power write
    `{"seg":[{"id,start,stop,on:false"}]}` with NO top-level `on`, routed through `applyJson`, used
    when a channel filter is active; force-refresh device config first (P1-43 depends on P1-42).
    Add a seg-off primitive (both filter builders currently hardcode `on:true`).
  - Master policy DECISION NEEDED: single-channel off must NOT write master; when the LAST lit
    channel goes off, should master follow (`{"on":false}`) or stay on with all segs dark? (Confirm
    with Tyler.) "All Channels On" recovery already exists
    [channel_selector_bar.dart:272](lib/features/dashboard/widgets/channel_selector_bar.dart#L272).
  - Blast radius — `togglePower` callers that legitimately want MASTER and must NOT change: dashboard
    circle, voice ([voice_providers.dart:255](lib/features/voice/voice_providers.dart#L255)/:276,
    [dashboard_voice_control.dart:126](lib/features/voice/dashboard_voice_control.dart#L126)/:137),
    Game Day resume [game_day_autopilot_providers.dart:84](lib/features/autopilot/game_day_autopilot_providers.dart#L84),
    Neighborhood resume. Fix must add a new seg-scoped action, not repoint `togglePower`.

---

## P2 — hardening & platform

- [ ] **P2-12 — Slot-cap guard (WLED preset max 250)**
  - Status: OPEN · Evidence: bench-proven (251+ silently no-ops)
  - Guard the app's slot allocation against the 250 ceiling.
  - Files: `lib/features/schedule/schedule_sync.dart` (slot allocation),
    `lib/features/schedule/calendar_entry_lease_manager.dart`.

- [ ] **P2-13 — Empty-armed guard verification**
  - Status: OPEN · Evidence: reported (mislabeled in +51 report)
  - +51 report mislabeled it (`splitByTimerCapacity`); grep to confirm the real guard
    (armed-but-zero-armable → loud fail) survived the merges.
  - Files: `lib/features/schedule/schedule_sync.dart`.

- [ ] **P2-14 — Firmware stall on cfg flash-save (vid 2507300)**
  - Status: OPEN · Evidence: bench-proven
  - cfg flash-saves black out controller network for minutes. App tolerates; nothing fixes.
    Evaluate WLED version-pin (0.15.1, see SOP §2.0) before fleet scale.
  - Files: firmware/version-pin policy (no app fix).

- [ ] **P2-15 — Codemagic build-number override**
  - Status: OPEN · Evidence: reported
  - Phone reports CM's counter, not pubspec `+N`; SHA is the only reliable identity. Let
    pubspec drive it, or stamp the git SHA into the About screen.
  - Files: `codemagic.yaml`, About/settings screen (`lib/features/site/`).

- [ ] **P2-16 — Node 20→22 Cloud Functions upgrade**
  - Status: OPEN · Evidence: reported (deadline before Oct 2026 decommission)
  - Files: `functions/package.json` (engines), `functions/` runtime config.

- [ ] **P2-17 — Dead `_controllerIps` plumbing**
  - Status: OPEN · Evidence: suspected (gated on prod confirmation)
  - Remove once `applySyncPattern` confirmed in production. Currently 1 live lib site +
    audit/backlog docs.
  - Files: `lib/features/sports_alerts/services/alert_trigger_service.dart` (+ referenced in
    `docs/audits/AUDIT_assumption_gaps_2026-06.md`, `docs/BUG_BACKLOG.md`).
  - (Was `#TD-2` in BUG_BACKLOG.)

- [ ] **P2-26 — iOS "Detect Home Network" SSID signing lockdown (ex-#61)**
  - Status: OPEN (lockdown shipped `021dcc2`, loop-broken build + on-device GREEN owed) · Evidence: reported
  - Junk team-id-suffixed App ID `6MWGH4KKC4` was recreated every build by two engines
    (fetch-signing-files prefix match + `signingStyle: automatic`). Fixed via
    `--strict-match-identifier` + manual export pinning `com.nexgenled.command` → `Lumina
    AppStore 2`. Verify: next build shows exactly ONE bundle id / ONE profile, no
    "Creating new Profile"; on device Detect Home Network = GREEN; THEN delete junk App ID.
  - Files: `codemagic.yaml`, `ios/ExportOptions.plist`, `lib/services/connectivity_service.dart`
    (instrumentation only).

- [ ] **P2-27 — Game Day team add is single-select only (ex-#64)**
  - Status: OPEN · Evidence: reported (Ellie E2)
  - One team at a time; needs multi-select in one pass.
  - Files: `_TeamPickerSheet` in `game_day_screen.dart` (+ sibling pickers).

- [ ] **P2-28 — Calendar can't show Game Day + regular schedule for a date (ex-#65)**
  - Status: OPEN · Evidence: reported (Ellie E4) — feature gap
  - No way to tap a date and see both autopilot entries and regular schedules. Connects to the
    parked Game Day phase-machine work.
  - Files: calendar/schedule day view (`my_schedule_page.dart`, Game Day calendar surfaces).

- [ ] **P2-29 — Orphan UID `BTAmiOGW…` + bridge `D4E9F4FA8E78` (ex-#67)**
  - Status: OPEN (parked, not actively harmful) · Evidence: reported
  - Third orphan UID; bridge paired to a deleted UID, status `paired`, not caught by the
    current hardcoded rule. Closed automatically by P2-30 if that lands.
  - Files: `bridge_registry` data; `firestore.rules`.

- [ ] **P2-30 — Generalize orphan-bridge rule to existence check (ex-#68)**
  - Status: OPEN · Evidence: verified-by-source (rule still hardcoded — confirmed 2026-07-22)
  - `isNotBlockedDeletedUid()` still lists only `xBnFxkN6`/`ASeUR5n`. Replace with a
    `pairedUid` existence check (Firestore `exists()` per `bridge_registry` write), closing ALL
    orphans incl. P2-29 without list maintenance; then remove the hardcoded entries.
  - Files: `firestore.rules` (`isNotBlockedDeletedUid`, lines ~668-673).

- [ ] **P2-31 — Pre-wipe orphan scan in `clear_account_state.js` (ex-#69)**
  - Status: OPEN · Evidence: reported — procedural
  - Before a user wipe, query `bridge_registry` `pairedUid` values, check each against Auth,
    surface/handle orphans BEFORE deleting.
  - Files: `scripts/clear_account_state.js`.

- [ ] **P2-32 — Roofline trace zoom / magnifier loupe (ex-#70)**
  - Status: OPEN · Evidence: reported — polish
  - Point-placement accuracy during roofline tracing; magnifier-loupe first, normalized 0–1
    coords cooperate.
  - Files: roofline tracing widget.

- [ ] **P2-33 — connectivity_service Crashlytics non-fatal for null SSID (ex-#71)**
  - Status: OPEN · Evidence: reported
  - Log a non-fatal when SSID read returns null so future occurrences are visible without Xcode.
  - Files: `lib/services/connectivity_service.dart`.

- [ ] **P2-34 — Automate Firestore rules tests (ex-#72)**
  - Status: OPEN · Evidence: reported
  - Grant the service account `firebaserules.rulesets.test` (for `scripts/_test_rules_block.js`)
    OR stand up the Firestore emulator + `@firebase/rules-unit-testing`. Currently manual via
    Console Playground.
  - Files: `scripts/_test_rules_block.js`, CI rules-test config.

- [ ] **P2-35 — On-device verify channel-2 participation reconciler (ex-#73)**
  - Status: OPEN (committed `cc62c39` + unit-tested, hardware verify owed) · Evidence: reported
  - Open dashboard with a deliberately-stale participation cache → channels self-correct
    (Ellie's channel-2 greyed-out bug).
  - Files: channel participation reconciler (`isParticipationCacheStale()` + foreground reconciler).

- [ ] **P2-36 — CloudRelayRepository wire-level test coverage (ex-#79)**
  - Status: OPEN (deferred from #77) · Evidence: reported
  - 4 bypass sites fixed; wire tests cover only the 2 WledService sites. Add direct
    `setState`/`savePreset` wire assertions (needs `fake_cloud_firestore` + Firebase init scaffold).
  - Files: `test/…/cloud_relay_repository*`, `lib/features/wled/cloud_relay_repository.dart`.

- [ ] **P2-37 — Lost-save finish A3: EditablePattern→LibraryNode adapter (ex-#85)**
  - Status: OPEN (W2 resolved; A3 unwired — `patternsStreamProvider`/`isSavedPattern` have zero
    lib call sites, confirmed 2026-07-22) · Evidence: reported
  - Adjustment-panel "Save As Custom Pattern" writes `/favorites/` but doesn't surface in My
    Designs. W2 removed the dead `/patterns/` write + relabeled the editor button "SAVE TO
    DEVICE". Finish A3: `EditablePattern → LibraryNode` adapter (`pattern_` prefix,
    `isSavedPattern` flag), wire `patternsStreamProvider` into the 3 injection sites, or
    consolidate the `/favorites/` writer onto `saveCurrentAsDesignProvider` (`/designs/`).
  - Files: `edit_pattern_screen.dart`, `patternCategoriesProvider`, `childNodes`,
    `libraryNodeByIdProvider`, `pattern_theme_selection.dart`, `saveCurrentAsDesignProvider`.

- [ ] **P2-38 — Migrate schedules off the user-doc array field (ex-#TD-1)**
  - Status: OPEN (plan only) · Evidence: reported — tech debt, HIGH before ~100 active users
  - Move array field → `/users/{uid}/schedules/{scheduleId}` subcollection. Also fixes the live
    whole-array clobber race (non-transactional remove/update, blind `saveSchedules` overwrite).
    Plan: `docs/audits/SCHEDULES_SUBCOLLECTION_MIGRATION_PLAN_2026-06.md`. Ordering:
    rules → backfill → dual-write.
  - Files: `schedule_providers.dart`, `user_model.dart`, `firestore.rules`, all schedule R/W;
    flag `schedules_subcollection_feature_flag.dart`.

---

## Features promised (post-cleanup)

- [ ] **F-18 — One-shot date-specific schedules**
  - Status: OPEN · Evidence: bench-proven (controller supports start/end month/day blocks)
  - Include a slot-cleanup story — one-shots must not eat slots forever.
  - Files: `schedule_models.dart`, `schedule_sync.dart`, `my_schedule_page.dart`,
    `solar_schedule_cleanup.dart` (cleanup pattern).

- [ ] **F-19 — "Run Now" on a scheduled event**
  - Status: OPEN · Evidence: reported
  - `/json/state` only. **NO new cfg writers, ever.**
  - Files: `my_schedule_page.dart` + `schedule_day_row.dart`; apply via WledRepository state.

- [ ] **F-20 — Warning copy when syncing a fully-disabled schedule**
  - Status: OPEN · Evidence: reported
  - Green is true but useless; add a nudge when a synced schedule has nothing armable.
  - Files: `schedule_sync.dart` (result), `schedule_off_warning.dart` / overload banner.

---

## Multiplier — do FIRST after main merge

- [ ] **M-21 — `bench/` CLI harness**
  - Status: OPEN · Evidence: n/a (tooling)
  - Seed / sync-sim / verify / probe against the bench controller (`192.168.1.150`). Extract
    from this week's proven curl loops: cfg write + readback assert, en truth-table check,
    preset shape verify, timer-fire test, presets.json diff. Nearly every item above needs
    bench verification; this makes each one cheaper.
  - Files: new `bench/` dir (CLI scripts).

---

## Attack order

```
main merge
  → branch cleanup
  → M-21 (harness)
  → P0-1 + P0-2 + P1-5 + P1-11  (one AI-path cycle)
  → P0-3
  → P0-4
  → P1-10
  → P1 archaeology batch (P1-6, P1-7, P2-13)
  → P2 batch (incl. migrated #61/#63/#64/#65/#67-#73/#77-#79/#85/#TD-1)
  → features (F-18, F-19, F-20)
```

The migrated ex-backlog items are non-schedule surfaces (iOS signing, Game Day, orphan
bridges, design apply/label, tech debt). Slot them by priority into the batches above; the
schedule stack still leads because it gates "sell with certainty."

---

## Resolved / closed (migrated from BUG_BACKLOG.md — kept, not dropped)

- [x] **R-39 — kEffectNames off-by-one (ex-#82)** — DONE `c8ed60a`
  - Hand-maintained `kEffectNames` had drifted from firmware order ~id 37 ("Halloween Eyes" vs
    "Solid Pattern" at 83). Map deleted; 5 call sites switched to `WledEffectsCatalog.getName`;
    parity test locks 12 indices. Verified-by-source: `kEffectNames` now absent from lib
    (only in `test/features/wled/effects_catalog_device_parity_test.dart`). Display-only; no
    data migration. Cold-start eyeball verify was owed but the fix is complete.

- [x] **R-40 — Design Studio Tier 2 save/apply stubs (ex-#66)** — DONE (implemented in current source; SHA not pinned)
  - `_handleSaveDesign` → `saveComposedDesignProvider` (real `/designs/` write) and
    `_handleApplyToLights` → `applyCustomDesignToLights` (real per-pixel apply) are both fully
    wired in `lib/features/design/screens/ai_design_studio_screen.dart` — no longer toast-only.

- [x] **R-41 — CRASH on Save Design: global error sink (ex-#84)** — DONE (crash-death mechanism closed)
  - `main.dart` now installs `FlutterError.onError` + `PlatformDispatcher.onError` (candidate #1,
    the missing global sink → uncaught-async SIGABRT). Caveat: the exact save-path root cause
    was never isolated from a stack trace; if a save silently *fails* (vs crashes) reopen. The
    separate nested-array (`col:[[…]]`) crash class tracked in project memory is distinct.

> Also folded: ex-#74 (Bug B `e556251` formal verify) → subsumed by **P1-24**. ex-#TD-2 →
> **P2-17**. ex-#TD-3 → **P2-16**.

---

## Historical context (from BUG_BACKLOG.md — reference only, not tracked)

**Closed 2026-05-27 → 05-28:** orphan-bridge cleanup (3 UIDs wiped, rule deployed);
`/patterns/` + `/designs/` Firestore rules added (were default-deny); Design Studio nav-bar
occlusion / clarification no-op / async error handling; Game Day team-picker occlusion;
Neighborhood Sync side-by-side buttons (`b77b5ca`); channel-2 reconciler landed (`cc62c39`,
verify → P2-35); Bug B preview parity confirmed live (`e556251`, verify → P1-24); iOS SSID
stale profile root-caused (→ P2-26).

**Recurring theme — Writer ≠ Reader:** features write user content to their own
collection/location while the display surface reads elsewhere (Patterns, Designs, Teams;
also participation-cache and orphan-bridge). A "unified user-content read layer" audit may
eventually beat fixing each surface individually. Strategic, not immediate.

**Recurring gotchas:** bottom-of-screen unreachable = glass-dock occlusion, fix with
`navBarTotalHeight(context)`; rules dry-run printing "enabling API / creating database" =
wrong-project alarm, confirm `firebase use` first; "looks fixed / tests pass" ≠ verified,
check runtime/on-device; map all writers before fixing a reader.
