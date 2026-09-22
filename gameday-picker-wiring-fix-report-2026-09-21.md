# Game Day celebration picker — wiring fix report

**Date:** 2026-09-21
**Branch:** `fix/gameday-celebration-picker-wiring` (local only — not pushed, not tagged, no version bump)
**Base:** `origin/release/store-submission-consolidated` @ `73ae375` (fetched and confirmed before branching)
**Worktree:** fresh, in this session's scratchpad. `main` and the shared checkout were not touched.
**Scope:** client-only Dart. No Cloud Function, rules, Firestore, or schema change. No deploy.

---

## 0. Read this first

| | |
|---|---|
| **The fix** | Done. The picker's choice now reaches `buildAnimationSteps` on the residential foreground path. 2 source files, +89 / −5 lines, of which 41 are code and the rest comments. Commit `615ccec`. |
| **Tests** | `flutter test`: **3187 passed / 14 skipped / 0 failed** (base `73ae375`: 3175 / 14 / 0). +12 = the new tests. Mutation-tested: 4 deliberate regressions, all caught (§4.2). |
| **Analyze** | `flutter analyze`: **382 issues — the identical issue set to base** (diffed with line numbers stripped). 0 issues in the touched files. |
| **Bench (Step 5)** | **NOT PERFORMED. The bench was unreachable from this machine** — see §6. Nothing in this report is a hardware result. The bench run is prepared, dry-run-checked, and is one command from the home LAN. |
| **Step 4** | **Flagged, not handled.** No picker option was removed, relabelled, or filtered. A decision is owed — §5. It is bigger than the six: **the picker previews a different palette from the one the celebration fires, for all 17 effects** (§5.1). |
| **A premise that did not hold** | Commercial's wiring is correct *code*, but nothing calls it. No shipped build renders a chosen celebration on commercial today — §1.3. |

---

## 1. Step 1 — commercial's implementation, as the reference pattern

### 1.1 How the choice travels

```
CommercialTeamProfile.celebrationEffectId / Speed / Intensity
  └─ GameDayService.handleScoringAlert            game_day_service.dart:158
       copies the three fields onto a ScoreAlertConfig        :189-191
       └─ AlertTriggerService.handleAlertEvent(event, config) alert_trigger_service.dart:90
            per controller:
            1. _resolveChannels                                :126
            2. previousState = _captureZoneState(svc)          :136   ← CAPTURE
            3. resolveCelebration(chosen…, capturedState)      :147   ← RESOLVE
            4. _applyAlertAnimation(…, resolution)             :158
                 └─ buildAnimationSteps(type, team, resolution):279   ← BUILD
                      └─ _applyCelebrationToStage — fx/sx/ix replaced per stage,
                         stage count + holds + on/bri kept     :302
            5. _restoreZoneState(svc, previousState)           :162
```

The pattern is: **the three fields ride on the one object the firing path receives**, and `null` effect id means "nothing chosen → legacy sequence verbatim". `monitoringConfigFor` (`unified_monitoring.dart:74-79`) does the same for the background path and says why in a comment: *"the trigger service receives ONLY this object, so a celebration choice that stops here would never reach the animation."* That sentence is the residential bug, described in advance, one file over.

### 1.2 Why capture/build ordering is not a problem there

`handleAlertEvent` was written **capture-first from the start**. It needs the capture for its restore, so the capture already sat above the animation call; the step build lives *inside* `_applyAlertAnimation`, below it. When the contrast check arrived (Phase B) it slotted between two things that were already in the right order. Nothing had to move.

It also has **no early-out that depends on the built steps**. A `turnover` (empty step list) still resolves channels, captures, plays nothing, and restores. That is wasted I/O, but it is direct-IP LAN HTTP — milliseconds — so nobody noticed or needed to.

### 1.3 Finding: commercial's path is not reachable in a shipped build

The task brief (and §5.1 of this week's colour-fix report) says commercial *"already renders the chosen celebration."* The code is right. Nothing runs it:

- `GameDayService.handleScoringAlert` has **zero callers** in `lib/` or `test/` (`grep -rn handleScoringAlert` → the definition only).
- `gameDayServiceProvider` (`commercial_providers.dart:49`) has **zero consumers**.
- `AlertTriggerService.handleAlertEvent` has exactly two callers, both in `sports_background_service.dart` (`:242` inside `_onStart`, `:341` inside `_onIosBackground`). Those are background-service entry points, and `initialiseSportsBackgroundService` / `startSportsService` both `return` on line one because `kSportsBackgroundServiceEnabled = false` (`:39`).
- `commercial_celebration_parity_test.dart` passes because it calls `buildAnimationSteps` directly.

So commercial is a sound **reference for the pattern** and I used it as one. It is not evidence that a chosen celebration has ever rendered on hardware for anyone. The colour-fix report's line *"A venue that picks 'Chase Random' today gets random colours"* should be read as *"would, if the path were live."* I changed nothing on the commercial side.

---

## 2. Step 2 — what "reorders capture and build" actually means on residential

The residential path before this change (`foreground_celebration_coordinator.dart`, `_runCelebration`):

```
1. team = kTeamColors[slug]            → return if unknown
2. steps = buildAnimationSteps(type, team)          ← BUILD   (pure, no I/O)
3. if (steps.isEmpty) return                        ← GATE    (turnover exits here)
4. captured = await delivery.capture()              ← CAPTURE (device / relay read)
5. await delivery.play(steps)
6. await delivery.revert(captured)
```

The contrast check needs the captured state, and the build needs the contrast check's answer. So build **must** move below capture: `capture → resolve → build → play`. That is the reordering. Traced carefully, moving it naively breaks three things — two of them silently.

### 2.1 The build was doing a second job: it was the no-animation gate

Line 3 is an early-out that sits *above* all device I/O. Build is pure, so today a `turnover` costs nothing. Move the build below the capture and the gate moves with it: a no-animation event now pays for `capture()`.

On residential that is not the cheap LAN read commercial gets away with. `WledCelebrationDelivery.capture()` goes through `wledRepositoryProvider`; off-LAN that is `CloudRelayRepository.getState()` → a Firestore command round trip to the bridge (**~5–10 s typical, 30–45 s tail**, per CLAUDE.md). And `_celebrating` is already `true` for that whole wait, so **a real touchdown arriving in the window is coalesced and queued behind an event that was never going to light anything.**

**Adaptation:** whether an event type animates is a property of the timing table alone — `_applyCelebrationToStage` maps 1:1 over legacy stages and cannot add or remove one. So the gate is decided from the pure builder *before* capture, and the final steps are built *after* it. The builder is called twice; it is a `switch` over an enum.

### 2.2 The choice has to come from somewhere, and the obvious place is wrong

The coordinator "owns NO device/Riverpod knowledge" and a `ScoreAlertEvent` carries only a slug. The naive move is to look the team up in `_liveTeams` at fire time. That fails in the one case that matters most:

- The **WIN** is emitted on the transition into `final` (`score_monitor_service.dart:~165`) — at about the moment the phase machine (a separate poller watching the same scoreboard) drops the team out of `liveGame`, which empties `_liveTeams`. It is the 30-second celebration, "the moment the whole feature exists for."
- A **coalesced** score runs up to a whole celebration (15–30 s) after it was detected.

With a `firstWhere` lookup the miss **throws**, the `catch` swallows it, and the celebration never plays at all — not "plays the legacy one": *nothing*. I verified this rather than reasoning about it: mutation M3 (§4.2) makes the naive lookup and fails four tests, three of them pre-existing delivery tests.

**Adaptation:** the coordinator keeps `_knownTeams`, a last-known entry per slug, upserted by `syncLiveTeams` and deliberately *not* pruned when a team leaves the live set. Bounded by the number of teams a user follows; cleared on `dispose`.

### 2.3 It switches the white-strobe fallback on, in production, for the first time

This is the behavioural surface the original deferral was worried about, and it is real. `resolveCelebration` has never executed on a live path (§1.3). After this change, if the pick is "too similar" to what the house is showing — same effect id, both `Strobe` category, or both `MotionType.pulse` — the user gets a **full-white strobe** instead of their pick.

I measured how often that can happen against Game Day's *own* base designs (the look most likely to be under a score), by firing every one of the 17 picks through the real coordinator over each base effect in `TeamDesignCatalog` (fx 0, 2, 28, 52, 63):

| Pick | over fx 0 | fx 2 | fx 28 | fx 52 | fx 63 |
|---|---|---|---|---|---|
| **28 Chase** | as picked | as picked | **→ white strobe** | as picked | as picked |
| the other 16 | as picked | as picked | as picked | as picked | as picked |

**One cell in 85.** But it is not an obscure one: **Chase is the first entry in the picker and its seed default, and fx 28 is base design #3 of 6.** A user who takes the default celebration, on a game whose base design is the Chase design, gets white strobes for that game. That is Phase B working exactly as Tyler specified it — I am reporting it, not proposing to change it — but it is the first time anyone will see it, so it should not be a surprise. (Over a *non*-Game-Day look — an Explore pattern, a schedule — more cells can light up; the matrix above covers only Game Day's catalog.)

Two edges of the same thing, both pre-existing hazards that the contrast check now also reads:
- If a **revert fails** (relay timeout), the next celebration captures the *previous celebration's* last stage. Previously that only meant a bad restore target; now it also means `effectsTooSimilar(pick, pick)` → white strobe. On LAN the revert is an awaited POST and there is a 2 s `minGap`, so this needs a genuine relay failure.
- If a score lands while the user has the **picker open mid-game**, the capture is the picker's live preview.

Neither is changed here. Both are noted so a white strobe in a field report has somewhere to be looked up.

### 2.4 What the reorder does *not* break (checked, not assumed)

- **Device call order is unchanged:** still `capture → play → revert`; the pre-existing test asserting `['capture','play(3)','revert']` passes untouched. Only the *pure* build moved.
- **No-pick configs are byte-identical.** `resolveCelebration` returns `null` on a null effect id before it looks at anything, and `buildAnimationSteps(…, null)` returns the legacy list by reference. Locked by a test that compares payloads whole.
- **Null capture still plays.** Unreadable state → `resolveCelebration` fails open → the pick fires as chosen → revert skipped. Same posture as `handleAlertEvent`.
- **A mid-game picker change does not re-baseline.** The Firestore stream → `liveCelebrationTeamsProvider` → `syncLiveTeams` → `_reconcile`, which is a no-op while the poll timer runs. No `monitor.reset()`, no extra poll, so no replayed or swallowed score. Locked by a test.

---

## 3. Step 3 — the fix

**`foreground_celebration_coordinator.dart`**
- `CelebrationTeam` gains `celebrationEffectId` (nullable), `celebrationSpeed`, `celebrationIntensity` — same names, defaults (240/240) and null semantics as `ScoreAlertConfig`. They join `==`/`hashCode` and are carried by `toAlertConfig()`, as commercial and `monitoringConfigFor` do.
- `_knownTeams` (§2.2), upserted in `syncLiveTeams`, cleared in `dispose`.
- `_runCelebration` becomes: **gate (pure build) → capture → read choice → `resolveCelebration` → build with resolution → play → revert.** The choice is read *after* the capture so a pick saved during a slow relay read still counts. A fallback logs one `debugPrint`, mirroring `handleAlertEvent`.

**`foreground_celebration_providers.dart`**
- `computeLiveCelebrationTeams` copies the three fields from `GameDayAutopilotConfig` onto `CelebrationTeam`. `gameDayAutopilotConfigsProvider` is a live Firestore stream and `fromJson` already reads the fields, so a save in the picker reaches the coordinator with no further plumbing.

**Not touched:** `alert_trigger_service.dart` (the builder already took the third argument — this was only ever a missing call-site argument plus the plumbing to have something to pass), `celebration_contrast.dart`, `game_day_screen.dart`, `colorway_effect_selector.dart`, `wled_effects_catalog.dart`, anything commercial, anything server-side.

### 3.1 Convergence

This branch is off `73ae375`, which does **not** contain this week's colour fix (`60282a3`). The two are designed to compose, and I checked that they do rather than asserting it:

- The working diff was applied with `git apply --check` onto **`release/store-submission-103` @ `c2b013a`** (the in-progress convergence, which already merges the colour fix, the Firestore transaction fix and Save-to-My-Designs) in a throwaway detached worktree: **applied cleanly, no file overlap.**
- There, `test/features/sports_alerts/` + `test/features/game_day/` + a throwaway probe: **284 passed, 0 failed** — including the colour fix's 28-test catalog guard and a probe asserting that **every chosen stage carries `pal: 0` after convergence** (the colour fix puts `pal:0` on each legacy stage; `_applyCelebrationToStage` spreads `...seg`, so a pick inherits it for free). The throwaway worktree was removed; nothing from it was committed.
- **On this branch alone a chosen stage carries no `pal`**, exactly like the legacy stages on this base. Fired over a look on a real palette it would render that palette. This is the same latent defect the colour fix's "Fix B" closes, and it closes it for picks too — but only once the two are merged. **Do not ship this branch without `60282a3`.** A test here pins the invariant that survives the merge in both directions: *a pick's `pal` equals the legacy stage's `pal`, whatever that is.*

---

## 4. Tests

### 4.1 Added — `test/features/sports_alerts/foreground_celebration_test.dart` (+12)

`_FakeDelivery` now records the steps it was asked to play and can return a sequence of captures. New group *"celebration picker — the chosen effect reaches the lights"*:

1. no pick → the legacy sequence, byte for byte
2. a pick replaces `fx`/`sx`/`ix` on **every** stage; holds, colours and `pal` unchanged; still capture → play → revert with the revert receiving the capture
3. four different picks → four different effects on the wire
4. pick == what the house is showing → white-strobe fallback, white `col`, revert still gets the capture
5. the pick is resolved against **this** celebration's capture, not a stale one (two celebrations, house changes between them)
6. unreadable state → fail-open, pick fires, no revert
7. a no-animation event never touches the device, with or without a pick
8. a **WIN** still honours the pick after the team has left the live set
9. a pick changed mid-game applies to the next (coalesced) celebration and does not restart polling
10. `CelebrationTeam` identity and `toAlertConfig()` carry the pick

Plus two in the existing `computeLiveCelebrationTeams` group: the pick rides along from **either** phase machine (autopilot and ephemeral); no pick stays `null`.

### 4.2 Mutation-tested — the tests fail when they should

Each mutation applied to a copy, test file run, source restored and byte-compared to the pre-mutation file.

| | Mutation | Result |
|---|---|---|
| **M1** | the original bug — third argument dropped | **7 fail** |
| **M2** | the naive reorder — gate moved below capture (§2.1) | **1 fails** (test 7) |
| **M3** | the naive lookup — choice read from `_liveTeams` (§2.2) | **4 fail** — test 8, *and three pre-existing delivery tests*, because the miss throws and the celebration is swallowed whole |
| **M4** | provider stops carrying the pick | **1 fails** |

### 4.3 Full results

| | Base `73ae375` | This branch |
|---|---|---|
| `flutter test` | 3175 passed / 14 skipped / 0 failed | **3187 passed / 14 skipped / 0 failed**, exit 0, 11m06s |
| `flutter analyze` | 382 issues | **382 issues — identical set**, 0 in touched files |

- **+12 tests**, all in `foreground_celebration_test.dart` (14 → 26). No existing test was modified, re-pinned, skipped or deleted; the only edit to existing test code is the fake delivery gaining two recording fields.
- The 14 skips are the base's 14. (`flutter analyze` exits 1 on both base and branch because the 382 pre-existing infos/warnings are non-zero; that is the base's state, not a regression.)
- **Base test figure provenance:** the base suite was not re-run in this session. 3175 / 14 / 0 is this week's colour-fix session's recorded run of the *same commit* (`73ae375`, `evidence/gameday-rainbow-fix-2026-09-21/baseline_test.txt` on `fix/gameday-celebration-team-colors`). 3175 + 12 = 3187 reconciles exactly. The base **analyze** *was* re-run here, in this worktree, before any edit (`baseline_analyze.txt`).
- **Housekeeping, stated rather than hidden:** the first post-fix analyze was discarded — I started a second analyze while a background one was still writing the same file. Both reported 382, but I did not keep evidence written by two concurrent writers; `fix_analyze.txt` is from a clean third run.
- Toolchain: Flutter 3.41.2 stable.
- On the convergence tree (`c2b013a` + this diff): `test/features/sports_alerts/` + `test/features/game_day/` + the throwaway `pal:0` probe → **284 passed / 0 failed** (§3.1). The full suite was not run there.

Evidence: `evidence/gameday-picker-wiring-2026-09-21/` — `baseline_analyze.txt`, `fix_analyze.txt`, `fix_test_summary.txt` (the full 1.3 MB log was not committed), `mutation_results.txt`, `gd_picker_probe_test.dart`, `picker_payloads.json`, `bench_gd_picker_verify.mjs`, `bench_picker_dryrun.txt`.

---

## 5. Step 4 — the six non-colour-reading effects. **DECISION OWED. Nothing was filtered.**

The picker offers 17 effects (`WledEffectsCatalog.celebrationPickIds`). The catalog marks six as not colour-reading. Until today that was academic, because the pick was discarded. **With this fix it is live: choose one of these and the celebration can render off-team colours — the original rainbow bug, by user choice.**

I did not remove, reorder, relabel or disable any of them, and I did not change what palette a chosen stage sends. `colorway_effect_selector.dart`, `wled_effects_catalog.dart`, `alert_trigger_service.dart` and `celebration_picker_test.dart` are unmodified. The picker still shows all 17.

### 5.1 The finding that matters most: the picker does not preview what fires

Tracing the six turned up something larger than the six. **The picker's live preview and the celebration send different palettes — for all 17 effects.**

- **Preview.** Every tap in celebration mode goes through `_sendToWled()` (`colorway_effect_selector.dart:625`, called at `:1413`/`:1425`) → `buildSelectorPayload`, which sets `pal` from `WledEffectsCatalog.paletteForEffect(fx)` = **`overridesUserColors(fx) ? 4 : 5`**. That method's own doc calls itself *"the SINGLE SOURCE OF TRUTH for how an effect applies the user's colors — every apply path should use this instead of hardcoding a palette"*, states the product rule *"the user's chosen `col[]` colors are ALWAYS honored"*, and records a bench result (192.168.1.250, fw 0.15.1): **`pal:4` → 0 % foreign hues; `pal:0` → 89 % foreign (rainbow).**
- **Celebration.** A chosen stage sends whatever the legacy stage sends: **no `pal`** on this branch, **`pal:0`** after convergence with the colour fix.

| | Preview sends | Celebration sends (converged) | Consequence |
|---|---|---|---|
| the **six** (32, 29, 64, 42, 90, 89) | `pal:4` — a gradient of the team's colours | `pal:0` | The user is **shown team colours and gets rainbow/random at the game.** The preview is not truthful. |
| the other **eleven** | `pal:5` — the team's colours, discrete | `pal:0` | Team colours both ways; the *look* may differ (palette-mapped vs `col[]` slots). Unmeasured. |

`_applyCelebrationToStage`'s doc comment justifies taking `sx`/`ix` from the pick with: *"that is the look they approved, so honouring it is what makes the picker truthful."* The same argument applies to `pal`, and it was not carried. That is the root of the Step 4 problem: **not that six effects ignore colour, but that the celebration path hardcodes a palette the rest of the app derives.**

### 5.2 What each of the six does under `pal:0` — from WLED 0.15.1 source, **not from hardware**

Since the bench was unavailable I read the pinned firmware's source (`wled/WLED` tag `v0.15.1`, `FX.cpp` / `FX_fcn.cpp`). The mechanism: `color_from_palette()` returns the segment's own `col[]` when `palette == 0`; `color_wheel()` is a hard-coded rainbow when `palette == 0` but **draws from the palette when `palette != 0`**; palettes 2–5 are *built from the segment's colours*.

| fx | Picker name | Catalog | Under `pal:0` (what fires after convergence) |
|---|---|---|---|
| **32** | Chase Flash Rnd | `generatesOwnColors` | **Off-team.** Body is `color_wheel(aux0)` = random rainbow hue; only the 2-LED flash is `col[0]`/`col[1]` |
| **29** | Chase Random | `generatesOwnColors` | **Off-team.** Background + trail are `color_wheel(random)`; only the chase head is `col[0]` |
| **64** | Juggle | `usesPalette` | **Off-team.** Explicit branch: `palette==0 ? CHSV(dothue,220,255)` — eight rainbow dots |
| **89** | Fireworks Starburst | `usesPalette` | **Off-team stars** (`color_wheel(random8())`) over a background filled with `col[1]` |
| **42** | Fireworks | `usesPalette` | **Team colour.** `color_from_palette(random8(), false, false, 0)` → `col[0]` at `pal:0` |
| **90** | Fireworks 1D | `usesPalette` | **Team colour.** `palette ? color_wheel(…) : SEGCOLOR(0)` → primary sparks with a white-hot flash, `col[1]` background |

So by source the exposure under `pal:0` is **four effects, not six**, and under a colour-derived palette all six draw from the team's colours — which agrees with the `.250` bench note already in the catalog.

I want to be plain about the status of that table: it is a reading of C++, by me, today. **It predicts; it does not measure.** The six-month rainbow bug was a confident label that was wrong. One detail the source cannot settle: the celebration's `col` array is `[primary, secondary, black]`, and `pal:4` is built `(tertiary, secondary, primary)` — so the gradient would run through black, where the preview's two-colour `col` leaves slot 3 as whatever the device last held. The bench script (§6) measures all six under `pal:0` and `pal:4`, and five of the eleven under `pal:0` and `pal:5`.

**Interim exposure on this branch alone** (no `pal` at all, §3.1): every pick inherits whatever palette the look underneath had.

### 5.3 Options

| | Option | Cost | Note |
|---|---|---|---|
| **A** | Ship as is | none | Four picks render rainbow/random. The natural defence — "the user previewed it" — **does not hold**, because the preview showed them team colours (§5.1). |
| **B** | Remove the off-team picks from the list | tiny | **Needs your sign-off — this is the thing you said not to do silently.** Drops 4 (or 6) of Tyler's hand-curated 17, and leaves the preview/celebration mismatch in place for the rest. A config already holding a removed id reopens the picker on the first entry (`_celebrationSeedEffectId`, `colorway_effect_selector.dart:1367`) but would **still fire the stored id** — so B also needs a rule for stored picks. |
| **C** | A chosen stage sends `pal: WledEffectsCatalog.paletteForEffect(fx)` — what the preview sent | small, in `_applyCelebrationToStage`; legacy (no-pick) stages keep `pal:0` | Keeps all 17. Makes the celebration match the preview **by construction**, using the app's existing single source of truth, whose `pal:4` behaviour is already bench-recorded. Changes the fired look of the eleven from `pal:0` to `pal:5`; the colour fix's guard covers legacy stages only, so it is unaffected. Needs the bench pass first. |
| **D** | Keep all 17, label the off-team ones in the picker | small, UI | Honest and non-destructive, but it would label as "own colours" effects whose *preview* shows team colours — confusing unless the preview changes too. |
| **E** | Extend the colour fix's catalog guard to `celebrationPickIds` | tiny, tests | Not a remedy on its own — as written (must be colour-reading, must carry `pal:0`) it would **fail today for six entries**. It is the enforcement to add alongside B, or to re-express for C as *"a chosen stage's `pal` equals `paletteForEffect(fx)`"*. |

**My recommendation: C, with the guard in E re-expressed to match, gated on the bench run.** It is the only option that keeps the curated list, keeps the colour fix's promise ("celebrations render team colours"), *and* closes the preview mismatch that A, B and D all leave open. If the bench shows `pal:4` through black looks wrong for any of the six, the thing to adjust is the `col` array for palette-driven picks, not the list. **I have not implemented any of it** — it is a rendering change I cannot verify on hardware today, and you asked for this as a decision.

---

## 6. Step 5 — bench verification: **NOT PERFORMED**

**The bench controller was unreachable from this machine for the whole session, so I ran nothing against hardware and I am not claiming any hardware result.**

What I found, read-only:

- `192.168.1.150`: HTTP timeout, 100 % ping loss.
- This machine's **Wi-Fi adapter is `disconnected`**; its only live link is `Ethernet` → a phone hotspot (`172.20.10.5/28`). The `192.168.1.66` address on the Wi-Fi interface is stale.
- Two Wi-Fi scans about 50 minutes apart saw **entirely different sets of SSIDs**, and neither set matched **any of the machine's 18 saved profiles**. The machine was away from the home LAN and moving. This is not a setting I could flip.
- Re-checked at the end of the session: still unreachable.

I did not try the alternatives, deliberately:
- **The cloud relay** could deliver payloads to the house, but it cannot read `/json/live`, so there would be no frame buffer — flashing the real house at full brightness, unattended, with no way to measure the colours and only a relayed `getState` to confirm restoration. That is the opposite of the discipline asked for. It would also put synthetic commands in the production command queue.
- I did not change the machine's network configuration.

### 6.1 What is ready

Under `evidence/gameday-picker-wiring-2026-09-21/`:

- **`gd_picker_probe_test.dart`** — drives the **real** coordinator (`syncLiveTeams` → `handleAlert` → `resolveCelebration` → `buildAnimationSteps`) with a synthetic Chiefs touchdown for "no pick" and all 17 picks, at the speed/intensity the picker actually seeds, and writes the channel-filtered wire payloads for the bench topology. **This part ran** — output in `picker_payloads.json`; it is also where the §2.3 matrix comes from.
- **`bench_gd_picker_verify.mjs`** — the colour-fix bench script's snapshot / idle-only pre-flight abort / restore / full-state diff / `presets.json` + `cfg` hash code, **unchanged**, with a new plan and one addition: an **8-frame series** per step with a frame-to-frame *motion* signature, because a still cannot tell Chase from Strobe Mega. `--dry` prints the plan and opens no socket; **the dry run passed (26 steps, ~140 s)** — `bench_picker_dryrun.txt`.

The plan (26 steps): 1 no-pick control · 5 colour-reading picks (Chase, Meteor, Bouncing Balls, Strobe Mega, Washing Machine), each under `pal:0` (as fired) and `pal:5` (as previewed) · the six, each under `pal:0` (as fired) and `pal:4` (as previewed) · one pick with `pal` omitted vs `pal:0` over a `pal:11` base (the §3.1 dependency).

```bash
# from the home LAN, controller idle (the script aborts, writing nothing, if it is not)
cd evidence/gameday-picker-wiring-2026-09-21
node bench_gd_picker_verify.mjs picker_payloads.json bench_picker_run1
```

**Pass criteria.** (1) the five picks produce pairwise-distinct signatures (`meanLit` / `motionChangedPct`) with `meanOffTeamPct` ≈ 0; (2) the six under `pal:0` confirm or refute §5.2's column; (3) the six under `pal:4` show `meanOffTeamPct` ≈ 0; (4) for the five, `pal:0` vs `pal:5` shows how far the fired look is from the previewed one; (5) `restoreOk: true` — zero state diffs, `presets.json` and `cfg` hashes unchanged.

### 6.2 What was verified without hardware, and what that is worth

The probe proves the claim *one layer short of the lights*: through the real coordinator, **each of the 17 picks puts its own `fx` (with the picker's `sx`/`ix`) on all three stages of the wire payload, and "no pick" puts the legacy `[2, 9, 63]`** (on this base — `[2, 3, 15]` after convergence). Before the fix every row would have read `[2, 9, 63]`.

That establishes that **what the app sends changes with the pick**. It does **not** establish what WLED renders, and it says nothing about restoration. Treat Step 5 as open.

---

## 7. Open items

1. **Run the bench** (§6.1) — blocks a decision on §5 and is the outstanding acceptance step for this branch.
2. **Decide §5** — A / B / C / D, with E alongside. The preview-vs-fired palette mismatch (§5.1) exists for all 17 picks whichever is chosen.
3. **Merge order:** this branch must not ship without `60282a3` (§3.1). Verified to apply cleanly on `c2b013a`.
4. **The white-strobe fallback goes live with this change** (§2.3). Default pick (Chase) × base design #3 (Chase) → white strobes. Working as designed; flagging so it is a known behaviour and not a bug report.
5. **Commercial's celebration path is dead code** (§1.3). Out of scope here; the colour-fix report's statement that it is reachable today should be corrected wherever it has been repeated.

---

## Addendum — 2026-09-21 (late): rebase, bench, and the Bouncing Balls withdrawal

Written after the sections above; nothing above was edited. Where this addendum and the body disagree, this addendum is current.

### A.1 Rebase

The three commits above were rebased onto `7c55c8e` — the tip of `origin/release/store-submission-consolidated`, which carries `60282a3` (§3.1's precondition is met) — as `fix/gameday-celebration-picker-wiring-rebased`. Zero conflicts; `git range-diff` reports every commit `=` and the patch-ids are identical. The original ref stayed where it was because another worktree still had it checked out.

Gate on the rebase: `flutter analyze` 382 issues, the identical set to base (0 errors / 12 warnings / 370 infos, 0 in touched files). `flutter test` 3342 passed / 34 skipped / 0 failed against base `7c55c8e`'s 3330 / 34 / 0 — the +12 are §4.1's tests.

### A.2 Bench, first pass (§6 is no longer open)

Home LAN, controller `192.168.1.150` (WLED 0.15.1, ESP32, 290 LEDs, two segments 0–128 / 128–290). Method: a throwaway test drives the **real** `ForegroundCelebrationCoordinator` → `resolveCelebration` → `buildAnimationSteps` → the **real** `WledCelebrationDelivery` → `applyChannelFilter` → the **real** `WledService` at the bench IP; only the ESPN monitor (event injected), `wledRepositoryProvider` and `deviceChannelsProvider` are substituted. An independent Node reader polls `/json/state` at 4 Hz and reads live-view frames over the WebSocket; it never writes. Snapshot before, hash `presets.json` (raw bytes) and `/json/cfg` before and after, restore after.

| Pick | On the wire (both segments) | Held | Frames | Result |
|---|---|---|---|---|
| **Meteor 76** | fx 76, sx 40, ix 128, pal 0, Chiefs `col` | 15.0 s | 100 % in the team hue arc, motion 17 % | **plays as chosen** — never the base (83), never the legacy 2/3/15, never the fallback 23 |
| **Bouncing Balls 91** | fx 91, sx 55, ix 128, pal 0 | 7.6 s | 100 % in arc, motion 10 % | **controller REBOOTED**: stopped answering at the stage-3 re-POST, uptime reset, came back on cfg `def` (bri 128, orange fx 0) with **one segment 0–290** |

`presets.json` (`8c53e9fe88f65c3c`, raw) and `cfg` (`e1feef2eb74dc2b3`) hashes were unchanged through both runs and the reboot. The controller was restored to its snapshot **including segment bounds** after the reboot, 0 diffs.

**The revert never posts in a debug or test build.** `WledCelebrationDelivery.revert` sends the captured `seg` back, which carries `start`/`stop`/`rev`/`mi`; `pinNoGeometryOnWire` hits its `assert(false)`, the coordinator's `catch` swallows it, and the lights are left on the celebration's last stage. In a release build the assert is stripped and the payload is geometry-stripped and sent (`a356b5f` names this exact case). Pre-existing; this branch does not touch the revert. Every bench run therefore ended with a manual restore.

### A.3 Decision and change — `15e1e2e`

Tyler's call: **withdraw Bouncing Balls (91) from the picker now; do not investigate the WLED-side root cause on this branch.**

- `WledEffectsCatalog.celebrationPickIds`: 91 removed → 16 entries. The picker builds its list from this, so it cannot be chosen.
- `resolveCelebration`: an id not in `celebrationPickIds` resolves to `null`, i.e. "no pick" → the legacy sequence. A config saved with 91 before the withdrawal therefore fires the legacy sequence, and nothing withdrawn can reach the lights through a stale config. This is the one chokepoint both the residential coordinator and commercial `handleAlertEvent` pass through. (The compiled-off background worker, `game_day_autopilot_background_worker.dart:650`, reads the stored id directly and is not covered; it is behind `kSportsBackgroundServiceEnabled = false`.)
- Game Day screen: a withdrawn stored id is labelled "Default", which is what fires. The picker already reseeded such a config on its first entry.
- Tests: the curated-names pin drops the entry; new tests pin the withdrawal (picker), the null resolution (contrast), and a stale 91 firing the legacy sequence through the real coordinator (foreground). The commercial parity test's "distinct effect" was fx 79 — an id the picker never offered — and is now Meteor.

Gate on `15e1e2e`: analyze 382, identical set; `flutter test` **3345 / 34 / 0** (+3).

### A.4 Bench, second pass — on `15e1e2e`

Same method. Between the first pass and this one another writer used the controller for about a minute (a power-off, then a three-colour fx 84 / pal 5 look); a three-minute read-only watch afterwards saw no further writes, and every run below was restored to that look, 0 diffs.

| Run | Stored pick | On the wire | Held | Frames | Result |
|---|---|---|---|---|---|
| A | **91 (stale config)** | **fx 2 → 3 → 15**, legacy sx/ix, pal 0 | 15 s | 100 % in arc | **fx 91 never reached the wire** — the legacy sequence fired |
| B | Meteor 76 | fx 76, sx 40, ix 128 | 14.9 s | 98.7 % in arc (the first two frames still carry the fading base) | plays as chosen; **no reboot** |
| C | Android 27 | fx 27, sx 55, ix 128 | 14.9 s | 100 % in arc, motion 24 % | plays as chosen |
| D | Washing Machine 113 | fx 113, sx 60, ix 128 | 14.8 s | **35 % in arc, 65 % off-team**, 8 hue buckets (blues, violets), 150+ distinct colours | plays as chosen — but **renders off-team under `pal:0`** |

Run D is a new entry for §5: the catalog marks Washing Machine `usesSelectedColors`, the picker previews it with `pal:5` (team colours), and the celebration fires it with `pal:0`, under which WLED 0.15.1 draws it from its default palette. By measurement it belongs with the six. No run rebooted the controller; `presets.json` and `cfg` hashes unchanged throughout; final state = the pre-run look, 0 diffs.

### A.5 What is still owed

- **§5 palette decision** — unchanged, and now seven: 32 Chase Flash Rnd, 29 Chase Random, 64 Juggle, 42 Fireworks, 90 Fireworks 1D, 89 Fireworks Starburst (all `overridesColors` → preview `pal:4`, fire `pal:0`), plus **113 Washing Machine** by measurement (preview `pal:5`, fire `pal:0`). Nothing changed here.
- The debug-only dead revert (A.2) — pre-existing, worth its own fix.
- The WLED-side root cause of the fx 91 reboot — explicitly out of scope.

---

## Addendum 2 — 2026-09-21 (late): the palette decision, resolved for six of seven

Tyler's rule: **nothing in a design card may generate its own palette — a card plays the colours the user picked.** Applied to the six picks flagged in A.5. **Washing Machine (113) is deliberately NOT part of this and stays open.**

### B.1 Withdrawn — Chase Flash Rnd (32), Chase Random (29)

Both colour themselves from a random hue (`color_wheel` on WLED 0.15.1) and no palette makes them read `col[]`. Removed from `celebrationPickIds` (16 → 14) by the same mechanism as Bouncing Balls: `resolveCelebration` returns null for any id not in the list, so a stale stored 32/29 fires the legacy sequence. Bench, through the real path with a Bills design: stale 32 → fx 2 → 3 → 15 on the wire, 0 % foreign hues, fx 32 never seen; stale 29 → the same. New pins: the two ids are absent, and nothing offered is catalogued `generatesOwnColors`.

### B.2 Re-paletted — Juggle (64), Fireworks (42), Fireworks 1D (90), Fireworks Starburst (89)

These are `usesPalette`: under `pal:0` WLED hands them its **default** palette, not `col[]`. The fix sends `WledEffectsCatalog.celebrationPaletteFor(fx)` on every chosen stage: **`pal:5` "Colors Only"** for a palette-reading pick, the legacy `pal:0` for a colour-reading one.

**How 5 was chosen — measured, not recalled.** The controller's own `/json/pal` lists the palettes that sample the segment's colours: 2 "Color 1", 3 "Colors 1&2", 4 "Color Gradient", 5 "Colors Only" (`/json/palx` shows their construction: `c1` / `c1,c1,c2,c2` / `c3,c2,c1` / `c1×5,c2×5,c3×5,c1`; `light.pal-mode` = 0, linear blend). Each was applied to all four effects with a two-colour design (Bills: blue `0,51,141`, red `198,12,48`) **plus the black third slot a celebration always carries**, and every lit pixel of eight full 290-LED frames was classified against the design's post-gamma hues (236° / 359°): *match* (±12° of a set colour), *blend* (on the short arc between the two), *extraneous* (anything else).

| fx | pal 0 (before) | pal 2 | pal 3 | pal 4 | **pal 5** |
|---|---|---|---|---|---|
| 64 Juggle | **53 % extraneous** | primary only (red 0 %) | 0 % extr., 27 % blend | 0 % extr., **blue 0 %** | **0 % extr., blue 36 % / red 58 %, 6 % blend** |
| 42 Fireworks | 4 % (all dim) | 0.8 % | 0 % extr., 49 % blend | 0 % extr., blue 0 % | **0 % extr., 26 % blend** |
| 90 Fireworks 1D | 0 % | 0 % | 0 % | 0 % extr., blue 0 % | **0 % extr., 7 % blend** |
| 89 Starburst | **20 % extraneous** | 0 % extr., 32 % blend | 0 % extr., 17 % blend | 0 % extr., **blue 0 %** | **0 % extr., 15 % blend** |

A first pass without the explicit black third slot was discarded: WLED kept the third colour of the look underneath (pure green), and palettes 4 and 5 both use that slot — a confound, not a result.

**Why not 4.** `paletteForEffect` — the catalog's "single source of truth" — returns 4 for these effects, and so does the picker's live preview. On the bench pal 4 dropped the design's **primary** colour entirely for all four: the gradient is `c3 → c2 → c1`, black → secondary → primary, so the primary is the last stop and is never sampled. Pal 5 puts both colours in as discrete entries; the residual "blend" is the controller's linear interpolation at entry boundaries plus each effect's own fade, never a hue the design does not contain.

**The layer the unit tests could not see.** The first bench run through the real path carried **`pal:4`** on the wire although the builder had set 5: `normalizeWledPayload`'s palette guard — written for sweeps like Rainbow, which `pal:5` collapses into a strobe — rewrites 5 → 4 for every `overridesColors` effect, and the fake delivery in the tests never crosses it. Juggle through the real path under that rewrite: 0 % extraneous, **0 % of the primary**, 14.8 s. Fix: `WledEffectsCatalog.kColorsOnlyVerifiedEffects = {64, 42, 90, 89}` — particle / dot effects bench-measured to render only the segment's colours under 5 — and the guard leaves them alone. `celebration_team_color_guard_test` now requires every palette-reading pick to be in that set (bench before you add), and `foreground_celebration_test` asserts `pal:5` survives `normalizeWledPayload` for each of the four.

### B.3 Bench, through the real path, on the final build (`13e8625`)

Real coordinator → real `WledCelebrationDelivery` → real `WledService` → the controller; independent 4 Hz reader with full-frame classification; Bills design; controller idle across two reads and no other process on this machine before each run.

| Run | Pick | On the wire | Held | Full-frame result (48 frames after the transition) |
|---|---|---|---|---|
| stale 32 | legacy 2 → 3 → 15 | pal 0 | 15 s | 0 % extraneous; **fx 32 never on the wire** |
| stale 29 | legacy 2 → 3 → 15 | pal 0 | 15 s | 0 % extraneous; **fx 29 never on the wire** |
| Juggle 64 | fx 64, sx 55, ix 128, **pal 5** | | 14.8 s | **0 % extraneous**; blue 41.6 % / red 54.8 %; 3.6 % blend |
| Fireworks 42 | fx 42, sx 60, ix 128, **pal 5** | | 14.9 s | **0 % extraneous**; red 55.6 %, blue sparks read as fades over the red background (44 % blend, all between the two set colours) |
| Fireworks 1D 90 | fx 90, sx 60, ix 128, **pal 5** | | 15.0 s | **0 % extraneous**; red 91.4 % / blue 3.6 %; 4.7 % blend |
| Starburst 89 | fx 89, sx 60, ix 128, **pal 5** | | 15.1 s | **0 % extraneous**; red 76.8 % / blue 5.0 %; 16 % blend |

No run rebooted or stalled the controller (uptime continuous, 5,016 s → 6,507 s across the session). `presets.json` (`8c53e9fe88f65c3c`, raw) and `cfg` (`e1feef2eb74dc2b3`) unchanged throughout. Every run restored to the pre-run look, 0 diffs.

Gate on `13e8625`: `flutter analyze` 382, identical set to base; `flutter test` **3350 / 34 skipped / 0 failed**.

### B.4 Still owed

- **Washing Machine (113)** — catalogued `usesSelectedColors`, renders 65 % off-design under `pal:0` (A.4). Not touched, by instruction.
- **Preview ≠ fired for the four**: the picker preview still sends `paletteForEffect` = 4 (primary missing on the bench); the celebration now fires 5. Aligning the preview is a `paletteForEffect` decision with Explore-wide reach — not made here.
- The debug-only dead revert (A.2) — pre-existing.
6. Pre-existing, unchanged, noticed in passing — **by reading, not tested:** the score monitor only polls while a team is in `liveGame`, so a `win` appears to be emitted only if its poll sees `final` before the phase machine's does; and a score already queued still fires if the user switches celebrations off mid-queue.
