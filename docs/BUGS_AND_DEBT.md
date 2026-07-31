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

- [x] **P0-5 — D4 BLOCKER: controller migration runs BEFORE the customer user doc exists** — **DONE 2026-07-31** (rules deployed, ruleset `ec8d918f-c279-4925-b8b2-168e96638586`)
  - FIX: claim-based resolution via new `staffMayReach(userId)` in `firestore.rules` — when
    `/users/{userId}` does not exist yet, scope from the CALLER'S OWN `dealerCode` claim
    instead of a `get()` on the absent doc. Ordering-immune, so it cannot regress if the
    wizard's sequence changes. Applied to all 7 vulnerable call sites (pixelMap inline +
    6 × `hasStaffClaim(dealerCodeOf(userId))` on brand_profile / commercial_locations).
  - NOT pure claim-based: `hasStaffClaim(token.dealerCode)` is `x == x`, i.e. always true,
    which would have granted every dealer's installer access to every other dealer's
    customers. Scoping is retained whenever the customer doc exists. See `audit/COMMISSIONING_FIXES.md`.
  - VERIFIED against the LIVE ruleset via the Rules `:test` API — 16/16 incl. cross-dealer
    DENY; plus a 31-path deployed-vs-live regression with 0 behavioral differences.
  - **D4 MUST use `staffMayReach(userId)`**, not `hasStaffClaim(dealerCodeOf(userId))`.
  - Original finding below.
  - Status: was OPEN · Evidence: source-proven (2026-07-30, token-refresh work)
  - `_completeSetup` migrates controllers at `installer_setup_wizard.dart:933` but the
    customer's `/users/{userId}` doc is not written until `:1047`. Any narrowed rule of the
    form `hasStaffClaim(get(/databases/../users/$(userId)).data.dealer_code)` therefore
    evaluates `get()` on a **non-existent document** and DENIES.
  - This is exactly the shape D4 intends to give `/users/{userId}/controllers` create
    (mirroring the `pixelMap` rule at `firestore.rules:414-417`). Deploying it as-is breaks
    controller migration for every install — the driveway failure the D4 sequencing is
    designed to avoid.
  - **Already latent today:** the migration batch also writes
    `/users/{customer}/controllers/{id}/pixelMap/{ch}`, which is *already* governed by that
    `get()`-based rule. When a roofline map was captured (Design Studio Slice 2), that write
    should already be denied — and because the whole batch fails atomically and the error is
    swallowed (see P0-6), the customer silently receives **no controllers at all**. Needs
    bench confirmation on a pixelMap-carrying install.
  - Fix options: (a) move the migration to after the `:1047` user-doc write, (b) write the
    customer user doc (at minimum `dealer_code`) before migrating, or (c) narrow using only
    the caller's own `dealerCode` claim with no cross-doc `get()`.
  - Files: `lib/features/installer/installer_setup_wizard.dart`, `firestore.rules`.

- [x] **P0-6 — `migrateInstallerControllersToCustomer` swallowed every failure** — **DONE 2026-07-31**
  - **DONE 2026-07-31** — see `audit/P0-6_FIX.md`. The swallow is removed:
    `migrateInstallerControllersToCustomer` now THROWS on failure and returns a
    `ControllerMigrationResult` on success. `_migrateControllersWithRetry` logs the cause,
    records it to the `/demo_analytics` telemetry sink
    (`event_type: installer_commissioning_failure`), and shows a blocking Retry/Stop dialog
    naming the cause — the same shape as `_restoreInstallerAuthWithRetry`, not a second UX.
    **Stop rethrows**; the migration is pre-`installCommitted`, so `classifyInstallError`
    yields `reportFailure` and the wizard reports the install as FAILED rather than handing
    over an account with no controllers.
  - RETRY IS SAFE — confirmed by test, not assumed: `WriteBatch.commit()` is atomic, so a
    failed commit leaves the source intact and the destination empty ("delete succeeded but
    set did not" cannot occur). A retry after a commit that *did* land finds the source
    drained and returns `skipReason: 'source-empty'` — a no-op, not an error.
  - Tests: `test/features/installer/controller_migration_failure_test.dart` (7).
    Full suite 1857/3/1 (only the pre-existing P1-8 AI-normalize failure).
  - GAP: the dialog itself is not widget-tested — `_completeSetup` calls
    `FirebaseAuth.instance.createUserWithEmailAndPassword` directly and the project has no
    auth-mocking dependency. The mechanism is pinned in two composing halves (it throws; a
    pre-commit throw classifies as `reportFailure`). Same gap as
    `_restoreInstallerAuthWithRetry`. Closing it means putting the auth call behind an
    injectable seam — worth doing, out of scope for an RC.
  - Was: `installer_setup_wizard.dart:207-209` caught and `debugPrint`ed any migration failure
    so "handoff still completes". A permission denial, a partial batch, or an offline device
    all rendered as a successful install whose customer has zero controllers on first login.
    This is what would have made the P0-5 denial invisible.
  - Files: `lib/features/installer/installer_setup_wizard.dart`,
    `lib/features/installer/staff_auth_telemetry.dart`.

- [x] **P0-7 — Roofline pixel-map save failure was silent; wizard advanced anyway** — **DONE 2026-07-31**
  - ⚠ **NAMING:** this was handed to me labelled "F-5", but **F-5 in
    `audit/COMPLIANCE_AND_SECURITY.md` is ACCOUNT DELETION** (F-5a/F-5b). They are unrelated.
    **F-5a/F-5b remain OPEN.** Tracked here as P0-7 so the ledger cannot conflate them.
  - `map_roofline_step.dart:417` was `catch (_) { return false; }` — cause destroyed — and
    `_onContinue()` discarded the bool and called `widget.onNext()` unconditionally. A pixel
    walk that failed to persist looked identical to one that succeeded; the installer
    finished the job and left. This was the **6th** silent-success instance (after F-5, F-8,
    the off-LAN lease, `_writeZeroedSlot`, `migrateInstallerControllersToCustomer`).
  - FIX: `_onContinue()` gates on the result and loops on a blocking Retry dialog; the
    exception is logged with uid/controller; "nothing captured" short-circuits to success so
    an installer who mapped nothing is never trapped. **No "save offline and continue"** — a
    queued write would be migrated-from-cache and deleted at handoff, relocating the silent
    failure somewhere unobservable.
  - Regression test: `test/features/installer/map_roofline_save_gate_test.dart` (5 tests)
    pins "onNext only on genuine success", incl. the decline-to-retry path so the fix cannot
    become a 7th instance.

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
  - NEIGHBORHOOD-AUDIT NOTE 2026-07-24: gamma `no-gc:false` (realtime/DDP gamma NOT bypassed) is
    re-asserted on EVERY connect by the LAN-only watchdog/healer
    ([controller_defaults_healer.dart:615-709](lib/features/wled/controller_defaults_healer.dart#L615),
    readback-gated `pushGammaConfig`) — but LAN-ONLY: a fleet member controlled only via the remote
    relay never gets the heal, so it could carry stale `no-gc:true` from a pre-fix provision.
    Bench 192.168.1.150 verified `if.live.no-gc:false`, `light.gc {bri:1,col:2.8,val:2.8}` (correct).
    Fleet-wide parity is unverifiable remotely — needs a per-controller LAN read.
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

- [ ] **P1-44 — Neighborhood Sync server-fanout path is DORMANT in production (config/sync_fanout unreadable)**
  - Status: OPEN · DECISION: **keep the fanout code, mark DORMANT** pending a Neighborhood Sync
    launch decision — DO NOT delete. Evidence: verified-by-deployed-state (2026-07-24, project
    `icrt6menwsv2d8all8oijs021b06s5`)
  - The foreground crew-fanout path (`NeighborhoodService.fanoutAdHocSync`
    [neighborhood_service.dart:472] → CF `applySyncPattern`) is gated on
    `config/sync_fanout.enabled` ([sync_fanout_feature_flag.dart]). DEPLOYED-STATE CHECK: (1) there
    is **no `match /config/sync_fanout`** rule in the deployed ruleset OR the repo — default-deny;
    (2) the **doc does not exist** (Firestore REST → 404). So the flag reader (client AND the CF's
    own `readSyncFanoutEnabled`) always falls back to `false` → the fanout branch is unreachable.
  - **DOUBLE-DEAD finding (2026-07-24):** `bootstrapSyncFanoutFlagDoc()`
    [sync_fanout_feature_flag.dart:71] is DEFINED but **NEVER CALLED** anywhere. So the doc is
    double-dead: nothing creates it, and even if bootstrap ran, the missing rule would default-deny
    the client create anyway. That is why it is 404.
  - **ACTIVATION STEPS (future session, when a launch decision is made — deliberate, not accidental):**
    (a) create `config/sync_fanout` with `enabled:false` — via a `bootstrapSyncFanoutFlagDoc()` call
    at launch OR the console (needs a create-allowing rule first: mirror
    `config/schedules_subcollection` [firestore.rules:1471], which allows create when
    `enabled==false`); (b) verify the anti-strobe rate limiter `reserveFanoutSlot` is live
    [applySyncPattern.ts:166]; (c) flip `enabled:true` in the console ONLY after (b) and a real-crew
    test. NOTE: a READ-ONLY rule was added separately (see below) to stop the per-launch
    permission-denied; that does NOT activate fanout (no doc, no create rule → flag stays false).
  - **Five never-executed-in-production code paths (dormant, keep):**
    1. Foreground fanout branch `broadcastSync` — [neighborhood_providers.dart:336-346]
    2. `NeighborhoodService.fanoutAdHocSync` (HTTP POST, `fanout:true`) — [neighborhood_service.dart:472]
    3. CF flag-gated fanout block — [applySyncPattern.ts:159-190]
    4. `reserveFanoutSlot` (rate limit) + `fanoutToCrew` — [applySyncPattern.ts:166,180]
    5. `bootstrapSyncFanoutFlagDoc()` (never called) — [sync_fanout_feature_flag.dart:71]
  - **DONE (partial):** read-only `match /config/sync_fanout` rule added to `firestore.rules`
    (hygiene — stops the fleet-wide per-launch permission-denied on the flag listen; flag stays
    absent/false). NOT deployed (rules deploy authorized separately).
  - Files: `firestore.rules` (read-only sync_fanout block added; create/flip still absent by design),
    `lib/features/neighborhood/sync_fanout_feature_flag.dart`, `neighborhood_service.dart:472`,
    `functions/src/applySyncPattern.ts:159-190,312-325`.

- [ ] **P1-46 — MAIN suite is RED (2 pre-existing failures) — masks regressions (green-main gate)**
  - Status: OPEN · Evidence: reported (verified on main + every build branch, 2026-07-24)
  - `main` (and every branch off it) fails exactly 2 tests: `cloud_ai_processor_normalize`
    ('Sunset') and `schedule_sync_time_parse` (solar). Because the suite is ALWAYS red, a NEW
    regression is invisible — you can't tell "2 failing" (known) from "3 failing" (a fresh break)
    at a glance, and any green-gate on PRs is unusable. Fix = repair or explicitly quarantine
    (skip-with-reason) the 2 so `main` goes GREEN; thereafter red==real regression and the suite
    can gate merges. This is the release-gate/trust framing of the SAME two tests tracked by
    **P1-8** (fix-or-delete the stale tests) — resolve together; P1-8 is the mechanism, P1-46 is
    the "keep main green" outcome + gate.
  - Files: `test/…/cloud_ai_processor_normalize*`, `test/…/schedule_sync_time_parse*` (see P1-8).

- [ ] **P1-47 — Single-channel "on" briefly lit ALL channels (RESOLVED/INTERMITTENT — WATCH)**
  - Status: WATCH (self-corrected in-session; root cause NOT confirmed) · Evidence: reported
    (observed in-app, not isolated — no readback captured)
  - With only ch1 selected, an "on" lit **all** channels. Corrected by deselecting/reselecting
    channels; subsequent single-channel commands targeted correctly. No code change made.
  - Hypothesis (unconfirmed): stale selection-vs-command-target state — the channel selection the
    UI showed was not the selection the command path read. NOT a confirmed regression of P1-43
    (which is bench-proven for the fresh-selection cases); the failing shape here is the
    additive/stale-selection case P1-43's bench matrix did not cover.
  - **REPRO CAPTURE (do this BEFORE correcting, if it recurs):** exact screen, controller IP,
    whether the selection was **fresh** (app-launch/first pick) or **additive** (toggled after a
    prior selection), and a `curl /json/state` readback taken while the wrong channels are lit.
    Without that, the selection→command path cannot be audited from a live repro.
  - Suspect files (unaudited): `lib/features/dashboard/widgets/channel_selector_bar.dart`
    (selection state), `lib/features/wled/wled_providers.dart` (`setChannelPower` /
    `applyChannelFilter`), `lib/features/wled/channel_power_payload.dart`
    (`buildChannelPowerPayload`).

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

- [ ] **P2-45 — Controller-native sync/realtime config is UNMANAGED (fleet-drift risk) + DDP/Zone scaffolding untested**
  - Status: OPEN · Evidence: verified-by-source + verified-by-bench (2026-07-24)
  - Neighborhood Sync does NOT use controller-native sync — it broadcasts via Firestore and each
    member self-applies over HTTP `applyJson` (`neighborhood_sync_engine.dart:625-734`). So
    `if.sync.*` / `if.live` / `udpn` are never touched by neighborhood code. Install disables native
    UDP (`wled_config_pusher.dart:231` writes `udpn:{send:false,recv:false}`); the ONLY code that
    ENABLES `udpn`/`ddp` is the SEPARATE Site/Zone DDP feature
    (`DDPSyncController.applyZoneSync` [site_providers.dart:109], `WledService.configureSyncSender/Receiver`
    [wled_service.dart:788-821], `DdpService` RawDatagramSocket:4048 [ddp_service.dart:20-63, has a
    `DDP(sim)` simulate branch]), reachable ONLY from Site settings [settings_page.dart:215] and
    UNTESTED (no DDP-transport test exists). Bench 192.168.1.150 live: `if.sync.send.en:false`,
    `if.sync.recv` flags on (bri/col/fx/pal), `if.live.en:true` (realtime IN on, port 5568),
    ports 21324/65506 (WLED defaults) — none of this is app-asserted, so it's whatever each
    controller happens to carry (drift risk if any future path relies on it). WLED UDP-notifier
    sync + E1.31 are not used by either feature.
  - Decision: either (a) formally OWN a leader/member controller-sync policy (assert `if.sync`/
    `udpn`/`if.live` per role on connect) if native sync is ever put on the Neighborhood path, or
    (b) document that Neighborhood Sync is Firestore-only and treat the DDP/Zone feature as a
    separate, test-owed surface. Today there is NO leader election (creator=admin, `isParticipating`
    =per-member runtime gate) — every member self-applies.
  - Files: `lib/features/site/site_providers.dart`, `lib/features/wled/ddp_service.dart`,
    `lib/features/wled/wled_service.dart` (configureSync*), `lib/services/wled_config_pusher.dart`.

- [ ] **P2-46 — Remove vestigial Sports Alerts settings surface (orphaned pre-Game-Day UI)**
  - Status: OPEN · Evidence: verified-by-source (audit 2026-07-24) · **Execute AFTER P0-3 lands — not now**
  - Sports Alerts (System → Settings) is the superseded predecessor of Game Day score celebrations.
    Its toggle reads/writes a SharedPreferences flag (`sports_alert_configs`, `ScoreAlertConfig.isEnabled`)
    whose ONLY runtime reader is the **kill-switched** background service
    (`kSportsBackgroundServiceEnabled=false` [sports_background_service.dart:29], "was already inert —
    updateControllerIps never wired up"). The LIVE celebration path derives teams from
    `game_day_autopilot` ∩ per-team `scoreCelebrationEnabled` and explicitly ignores this flag
    ([foreground_celebration_providers.dart:98-105]; header :5-7 "NOT the dead direct-IP path"). It
    does not share state with My Teams (Firestore `game_day_autopilot` + profile `sports_teams`) — the
    only bridge is one-way and unrelated to the toggle ([live_scoring_prompt.dart:94-104]). This is the
    remove-vs-wire "(a) dead UI" verdict.
  - **DELETE set:** `lib/features/sports_alerts/ui/sports_alerts_screen.dart`, `.../ui/team_picker_screen.dart`,
    `.../ui/zone_assignment_screen.dart`, `.../providers/sports_alert_providers.dart`,
    `.../providers/sports_alert_notifier.dart`, `_SportsAlertsCard` + route in
    `lib/features/site/settings_page.dart` (:1002-1007), `.../services/sports_background_service.dart`
    + its `lib/services/autopilot_scheduler.dart:480` `startSportsService()` call, and the
    `lib/features/game_day/live_scoring_prompt.dart:94-104` prefs write.
  - **MUST-KEEP (reused by the LIVE foreground path — deleting breaks working celebrations):**
    `lib/features/sports_alerts/models/score_alert_config.dart` (`ScoreAlertConfig`),
    `.../services/score_monitor_service.dart`, `.../services/foreground_celebration_coordinator.dart`
    (incl. `CelebrationTeam.toAlertConfig()` :67), `.../services/foreground_celebration_providers.dart`.
  - **Coordinate with P2-17** (`_controllerIps` / `alert_trigger_service` — same dead pipeline).
  - **(b) alternative — NOT this item:** if app-closed score celebrations are ever wanted, that is a
    SEPARATE feature (re-enable the service + repoint it at `game_day_autopilot` instead of the prefs
    store + wire `controllerIps` + Play FGS declaration), NOT a revival of this toggle.

- [ ] **P2-48 — `functions/lib/` is TRACKED despite `.gitignore` listing it (inert rule → chronic dirty tree)**
  - Status: OPEN (tech debt — dedicated task, NOT bundled into a feature fix) · Evidence:
    verified-by-repo-state (2026-07-27)
  - `.gitignore:225` lists `functions/lib/`, but all **81 files** under it are committed and tracked
    in HEAD (`applySyncPattern`, `staffAuth`, `createCustomerAccount`, …). **A `.gitignore` rule has
    no effect on already-tracked files** — the entry was added after the files were committed, so git
    keeps tracking them and the rule is inert. Confirmed: `git check-ignore -v` on
    `functions/lib/applySyncPattern.{js,d.ts,js.map}` matches **no rule**, while
    `git ls-tree --name-only HEAD functions/lib/` lists all 81.
  - **Symptom:** chronic dirty-tree churn. Any `tsc`/`npm run build` rewrites the compiled output,
    which git then reports as modified. Because the files are tracked, the modifications **follow
    every branch switch** — observed 2026-07-27 carrying `applySyncPattern.*` from
    `feat/dealer-team-empty-state` → `main` → `fix/neighborhood-join-membership` untouched. It also
    means a routine `git add -A` can silently commit stale build output.
  - **Doc drift:** the SYNC-1 commit (`76324ce`) states *"functions/lib/ is gitignored build output —
    deploy/test:unit rebuild it; compiled output intentionally not committed."* That is **false** for
    this repo as it stands — it IS committed. Fix the claim or fix the repo; right now they disagree.
  - **FIX (separate dedicated task — do NOT fold into an unrelated branch):** decide which model is
    intended, then make the repo match.
    - (a) **Generated** — `git rm --cached -r functions/lib` + commit; the existing `.gitignore:225`
      rule then takes effect and the churn stops permanently.
    - (b) **Build-committed** — remove `functions/lib/` from `.gitignore` so the tracked state is
      honest, and accept that compiled output is reviewed in diffs.
  - **BLOCKER on (a) — must confirm BEFORE untracking:** that every deploy path rebuilds `lib/`
    from source. Check `functions/package.json` (`predeploy`/`build` scripts), `firebase.json`
    (`functions.predeploy` hooks), and any CI/Codemagic step that runs `firebase deploy --only
    functions`. If any path ships `lib/` as-is from the checkout, untracking it **breaks deploys**.
    Removing 81 files from the repo is not reversible-by-accident — verify first.

- [ ] **P2-49 — Sunrise-off toggle arms only the ACTIVE controller (no fan-out to a user's others)**
  - Status: OPEN (known limitation — ledger only, NOT a regression) · Evidence: verified-by-code
    (2026-07-29, `f8ce483` on `feat/sunrise-off-toggle`)
  - The global "Turn lights off at sunrise daily" toggle arms/disarms via
    `SunriseOffService._write`, which resolves a single repo from `wledRepositoryProvider` and writes
    the reserved sunrise slot to **that controller only**. This is the **same scope as
    `ScheduleSyncService.syncAll`** (which also reads one `wledRepositoryProvider`), so it is
    consistent with existing per-controller behavior — **not a regression**, and not a defect
    introduced by the sunrise-off feature.
  - **Fine for residential**, the shipping case: a single controller, or a linked set fronted by one
    active repo.
  - **KNOWN LIMITATION for multi-controller / commercial multi-zone properties:** toggling on arms
    only the active controller. **The user's other controllers stay ON at sunrise**, with no UI
    signal that the toggle only covered one of them — the settings switch reads as account-wide.
  - **FIX (only if commercial multi-zone adoption happens — do NOT pre-build):** extend arm/disarm to
    fan out across all of the user's controllers, then aggregate the per-controller results so a
    partial success is reported as partial (the existing `SunriseOffWriteResult` is single-valued and
    would otherwise report the first/last controller's outcome as if it were the whole account).
    Natural source for the controller set is `activeAreaControllerIpsProvider`
    (`lib/features/site/site_providers.dart`).
  - **Coordinate with schedule sync.** `syncAll` has the identical single-repo scope, so a fan-out
    that covers only the sunrise-off would leave the two paths inconsistent (sunrise-off on every
    controller, schedules on one). Either fan out both or neither — this is one decision, not two.

---

## P3 — debt (no launch relevance)

> Added 2026-07-30 from the pre-submission audit (`audit/LAUNCH_PLAN.md`, consolidating
> `audit/FEATURE_STATUS_MATRIX.md` + `audit/RELEASE_READINESS.md`). None of these block
> submission; none are customer-visible.

- [ ] **P3-60 — `kStaffAuthTelemetryAppVersion` is a hand-bumped constant (drift risk)**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30)
  - `lib/features/installer/staff_auth_telemetry.dart` stamps a hardcoded app version onto
    every fallback row because the project has no `package_info_plus` (adding a plugin to a
    release candidate was judged riskier than a constant). A stale value defeats the S-5
    metric, whose entire job is telling adopted builds from stale ones.
  - Fix: add `package_info_plus` post-submission and read the real version, or add the bump
    to the release checklist next to the `versionCode` bump.

- [ ] **P3-61 — Aborting the wizard after customer-account creation is unrecoverable in-app**
  - Status: OPEN · Evidence: source-proven (2026-07-30)
  - If the installer taps **Stop** on the new staff-auth retry dialog (or any post-`:822`
    failure aborts), the customer's Firebase Auth account exists but `/users/{userId}` was
    never written. Re-running with the same email hits `email-already-in-use`, whose recovery
    path queries `/users` by `dealer_code` + `email`, finds nothing, and dead-ends on
    "No existing customer matches this email under your dealer code."
  - Pre-existing (any post-creation abort does this); the retry dialog just makes the branch
    reachable on purpose. Mitigated by the pre-flight refresh making Stop very unlikely, and
    the dialog copy tells the installer not to restart with the same email.
  - Fix: recover by uid instead of by query when the account exists but the user doc does not.

- [ ] **P3-62 — Stale line-number cross-references around the installer auth path**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30)
  - `firestore.rules:405` cites `installer_providers.dart:192` for the `signInWithCustomToken`
    call; it is at `:291`. `staff_pin_screen.dart:75-78` cites wizard lines `506`/`512` for
    `createUserWithEmailAndPassword` / `signInAnonymously`; they are at `:822` and inside
    `_fallBackToAnonymous`. The `staff_pin_screen` note also now misdescribes the wizard,
    which re-mints rather than falling back.
  - Also: `installer_setup_wizard.dart`'s `installerAnonymousUid` local is a misnomer — post-PIN
    it holds the **staff** uid (`staff_installer_<pin>`), not an anonymous one. That name is
    what made the "does the staff uid equal `fromUid`?" question look open. Rename it.

- [ ] **P3-50 — `buildTimerEntry` still carries the known-wrong solar 24/25 encoding (dead, but loaded)**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30, `393af46`)
  - `lib/features/schedule/cfg_payload_builder.dart:100-108` emits `hour: 24` (sunrise) /
    `hour: 25` (sunset) — the encoding proven wrong for WLED (24 = hourly, 25 = invalid).
  - **Currently unreachable**: `buildCfgPayload` skips every solar label before it can be
    called with one (`:155-165`), and the real solar path is
    `ScheduleSyncService.buildSolarTimerEntry` (`hour: 255` marker, `schedule_sync.dart:414-428`).
    So this is dead code, not a live defect.
  - **Why it is still worth closing:** it is a correct-*looking* helper in a shared builder. The
    next author who needs a solar timer will reasonably call it and silently reintroduce the bug.
  - Fix: delete the solar branch, or `assert(false)` it. ~0.5h.

- [ ] **P3-51 — 108 silent empty catch blocks in `lib/`**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30) — `grep -rn "catch (_) {}" lib/`
  - Most are defensible best-effort paths. But the class hid a real data-loss bug: the pixel-walk
    save swallows its exception at `map_roofline_step.dart:417` and the caller discards the
    `false` return (`:426-428`), so a failed Firestore write advances the wizard silently.
    That specific instance is tracked separately as a P1 in the launch plan (T-5).
  - Not worth a blanket sweep. Worth a rule: **catches on WRITE paths must surface or log.**
  - Fix: lint rule + targeted audit of write paths. ~4h.

- [ ] **P3-52 — `CLAUDE.md` carries three claims that contradict the code**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30)
  - `kSimulationMode` documented as hardcoded `true`; it is `false` (`app_providers.dart:17`).
  - HTTP timeouts documented as an outstanding 5s KNOWN ISSUE requiring a 15s fix; that work shipped.
  - "No automated tests currently exist" — there are ~170 files under `test/` plus emulator
    suites in `functions/test/`.
  - Also stale in project memory: the schedules array→subcollection migration is recorded as
    "PLAN ONLY"; it is fully implemented (client lazy migrator + server backfill + bidirectional
    dual-write). All four misled the pre-submission audit and will mislead the next session.
  - Fix: correct the four claims. ~0.5h.

- [ ] **P3-53 — `functions/lib` (compiled output) is committed to VCS**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30) — 78 tracked files, no `functions/.gitignore`
  - Structural cause of the deploy-parity drift tracked in the launch plan (T-4): `src` and `lib`
    diverge silently, and a bare `firebase deploy --only functions` from repo root ships whichever
    `lib` is on disk without building. `npm run deploy` chains the build; the bare form does not.
  - Fix: gitignore `functions/lib`, rely on the predeploy build hook. ~1h. Removes the failure
    mode entirely rather than re-fixing the artifact each time.

- [ ] **P3-54 — `minifyEnabled = false` in the release buildType → 65 MB AAB**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30) — `android/app/build.gradle:60-61`
  - Both minification and resource shrinking are disabled for **release**. Well under Play's
    limit and harmless; enabling R8 would cut download size materially.
  - Needs a keep-rules pass against the reflection-using plugins (Firebase, flutter_blue_plus,
    speech_to_text) — which is why it is debt and not a quick win. ~2h + regression testing.

- [ ] **P3-55 — Orphaned-route safety rests on the ABSENCE of deep-link config — needs a regression guard**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30, Window B `audit/COMPLIANCE_AND_SECURITY.md`
    §2.6(b) Q2d; corrects an earlier Window A claim)
  - Seven routes are registered in `app_router.dart` with **zero** navigation from anywhere in
    `lib/` (`/commercial/onboarding`, `/settings/current-colors`, `/dealer/payouts`,
    `/autopilot/first-week`, `/media`, `/system-deactivated`, `/installer/zone-setup`). Several
    host stub controls that report false success (`CommercialScheduleScreen.dart:1819,1850,2064`).
  - **They are currently unreachable — but only by accident of configuration, not by design:**
    - `deep_link_service.dart:59-90` is a closed allow-list (`power`, `brightness`, `scene`, …);
      an unmatched first path segment returns `null` and never reaches GoRouter.
    - `flutter_deeplinking_enabled` is **absent** from `AndroidManifest.xml` and
      `FlutterDeepLinkingEnabled` is **absent** from `Info.plist`, so Flutter's automatic
      URI→route mechanism is off.
    - `autoVerify="true"` at `AndroidManifest.xml:107` is inert — it applies to `http`/`https`
      App Links only, not to the custom `lumina` scheme.
  - **The hazard:** compliance row 1.1 PASSes *because of these absences*. Adding
    `flutter_deeplinking_enabled` in any future release — a one-line, innocuous-looking change
    someone will eventually make for App Links or marketing attribution — **re-opens the entire
    orphaned-route class at once**, making every stub screen externally addressable.
  - Guard (pick one, cheapest first): a widget/unit test asserting neither flag is present in the
    built manifest/plist; **or** land the route-guard class fix (deny-by-default for unknown
    prefixes, `route_guards.dart:54,294-296`, ~4h) so reachability stops depending on the absence
    of a config key. The class fix is the durable answer — the test only detects the regression.
  - Related: the `/commercial` deletion (~1h) removes the worst instance regardless.

- [ ] **P3-56 — ON-preset definitions exist in TWO places (drift risk from the master-power fix)**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30, master-power fix)
  - `ScheduleSyncService.kOnPresetSpecs` (slot → name+bri) was added so the on-connect defaults
    healer can repair presets 1/3/4/5 without re-deriving them. The four `psaveIfChanged` calls
    in `syncAll` still carry their literals inline (`{'on': true, 'bri': 200, 'ib': true}` etc.).
  - **Left deliberately.** Rewriting the shipping sync path to consume the map is a refactor, and
    that fix was scoped to the master-power defect on a release candidate. Zero behavioural risk
    was the priority.
  - **The risk:** change a brightness in one place and the healer and the sync will write
    different definitions, so every connect and every sync will fight each other — each seeing
    the other's value as "unsatisfied" and re-saving. A psave APPLIES live, so that presents as
    the strip flashing on every connect.
  - Fix: have the four calls consume `kOnPresetSpecs` + `onPresetHealState`. ~0.5h. Add a unit
    test asserting the sync's emitted state equals `onPresetHealState(spec.bri)` for each slot.

- [ ] **P3-57 — `schedule_sync_idempotent_test.dart` fixtures encode the pre-fix preset shape**
  - Status: OPEN · Evidence: verified-by-test (2026-07-30) — 2 failures after the master-power fix
  - Presets 1/3/4/5 are fixtured as `{'n': 'NGL On', 'seg': [{'on': true}]}` — name + segment-on,
    **no root `on`** — which is exactly the broken on-device shape. Preset 2's fixture carries
    `'on': false` with the comment *"Already healed…so the OFF-preset self-heal skips it"*, so the
    author had the right model for 2 and not for 1/3/4/5.
  - Two tests now fail **because the fix works**:
    - *"Option A: pattern preset ALWAYS re-saved…; system presets skip"* — `Expected: [10]`,
      `Actual: [1, 3, 4, 5, 10]`
    - *"preset 2 named NGL Off but left ON is repaired"* — `Expected: [2]`, `Actual: [1,2,3,4,5]`
  - **NOT rewritten** — reported rather than silently changed, since a fixture that encodes broken
    behaviour is exactly what made the original defect survive review. Deciding what these tests
    *should* assert is a judgement call, not a mechanical edit.
  - Fix: add root `'on': true` to the 1/3/4/5 fixtures (making them healthy, so the skip
    expectation becomes correct) **and** add a sibling test with the no-root-`on` shape asserting
    that those slots ARE re-saved. ~1h.

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

- [x] **M-21 — `bench/` CLI harness** — DONE (inaugural all-green 2026-07-24, 21/21)
  - Status: DONE · Evidence: bench-proven (`dart run bench/bin/bench.dart all` → 21/21, exit 0,
    192.168.1.150, 2026-07-24)
  - Pure-Dart CLI (`bench/bin/bench.dart`) with 9 subcommands: probe (+layout-drift vs
    `known_layout.json`, P1-42), snapshot, cfg-truth (en int→1/bool→0, permanent regression
    guard), preset-verify, sync-sim, fire-test, channel-power (P1-43 four shapes), restore, all.
    REUSES the app's REAL builders via extraction to Flutter-free files (re-exported, app
    unchanged): `buildCfgPayload`, `timersInsLanded`/`isRealEnabledTimer` (→ `timer_landing.dart`,
    `cfg_payload_builder.dart`), `buildChannelPowerPayload` (→ `channel_power_payload.dart`),
    `deviceChannelsFromConfig`/`DeviceChannel` (→ `device_channel.dart`),
    `WledLedBus`/`WledHardwareConfig` (→ `wled_hardware_config.dart`). Discipline as code:
    Content-Type + Content-Length on every POST (chunked is rejected by WLED — caught on the
    inaugural run), capture/restore brackets, VERIFIED-BY-BENCH evidence, exit 0/1. Assertion/
    diff logic unit-tested (`test/bench/bench_core_test.dart`, 19 tests). Extraction proven
    behavior-preserving: full suite unchanged at 1746 pass / 2 pre-existing fail, 0 new lint.
  - Files: `bench/` (bin/bench.dart, src/bench_core.dart, src/wled_client.dart, config.json,
    known_layout.json, README.md) + the 5 extracted pure lib files above.

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
