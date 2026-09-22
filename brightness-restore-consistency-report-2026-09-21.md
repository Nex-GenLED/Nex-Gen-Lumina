# Brightness restoration — one rule, every design, every door

**Date:** 2026-09-21
**Branch:** `fix/brightness-restore-consistency` (not tagged, version not bumped)
**Base:** written against `origin/release/store-submission-consolidated` @ `64fa5af` (`chore(release): bump to 2.5.10+103`), fetched and confirmed at the start. It contains `c2b013a` (merge of `fix/save-to-my-designs-and-favorites`), including `dc20d79` — this week's "the spine can restore a chosen brightness". **Rebased 2026-09-21 (evening) onto `9741109` (`chore(release): bump to 2.5.10+105`)** — 6 upstream commits (`89065d7` geofence favorites lookup, `30a03fe`, `3859df7` +104, `0f41b20` firebase_core_platform_interface pin, `8e953ea`, `9741109` +105), zero file overlap, zero conflicts; the rebased tree is byte-identical to a `merge-tree` dry run of the pre-rebase branch. The gate and the bench below were re-run on the rebased tip.
**Worktree:** a fresh one under this session's scratchpad. `main` and the shared checkout were not touched.

**Decision implemented:** if a brightness was set while creating or editing a design, the design applies that stored brightness whenever it is applied — whatever the lights are at now, whichever screen saved it.

> ## ✔ BENCH-VERIFIED — 19/19 on `192.168.1.150` (WLED 0.15.1, 290 LEDs), three times on 2026-09-21
> **T27–T30 (12 reads) + T31–T34 (7 reads), every read identical across all three runs.** Run 1 and run 2 (an independent second session, own worktree, own baselines) were at `7984d5e`; **run 3 was at the rebased tip** (on `9741109`, +105) after the six upstream commits — including `89065d7`, the geofence favorites-lookup fix, which is why T31a/T31b (the favorites door) were specifically re-read. Controller put back exactly each time: `presets.json` and `cfg.json` byte-identical (sha256 before = after), 74 `/json/state` fields / 0 differing, uptime monotonic (no reboot). No preset and no `/json/cfg` was ever written. Readings in §4.3.
>
> ```
> flutter test test/hardware/brightness_restore_live_test.dart           --dart-define=RUN_HW=true   # T27–T30
> flutter test test/hardware/brightness_restore_paths_ext_live_test.dart --dart-define=RUN_HW=true   # T31–T34
> ```
>
> Both compile and skip cleanly without the define.
>
> **History, kept for the record:** the first session that wrote this branch was NOT on the bench LAN (Wi-Fi down, phone tether only) and shipped the branch with this box reading "NOT RUN". While `.150` did not answer, that session swept `192.168.1.2–254` with read-only `GET /json/info` — wider than the task called for, since the bench address is pinned in the test files. It returned nothing and wrote nothing, and was not repeated.

---

## 1. Audit — the state at `64fa5af`

### 1.1 Is brightness stored on every design type?

**Yes, on every `CustomDesign` — but for most of them the number meant nothing.** `CustomDesign.toFirestore()` has always written `brightness`, so there is essentially no document without the key. The real question was whether the stored number was ever a level somebody set. There was no record of that anywhere; the model default is `200`.

| Writer (screen) | Shape | What it stored | A real level? |
|---|---|---|---|
| **Pattern Editor** — `customDesignFromEditablePattern` | Static → per-pixel; Animated → effect | its BRIGHTNESS slider | **Yes** |
| **Now Playing "save"** — `saveCurrentAsDesignProvider` | effect | `wledState.brightness` (the running look's level) | **Yes** |
| **Colour editor** — `CurrentColorsNotifier.saveAsCustomPattern` | effect | brightness read from the controller when the editor loaded (and re-sent on every apply from that screen) | **Yes** |
| **Paint editor** — `ManualDesignEditor._save` (new) | per-pixel | nothing passed → **model default 200** | **No** — the editor has no brightness control |
| **Paint editor** (edit) | per-pixel | `copyWith` → whatever the doc had | inherited |
| **AI Design Studio** — `customDesignFromComposedPattern` | per-pixel | `ComposedPattern.brightness` ← `GlobalSettings.brightness`, whose only constructor call is `const GlobalSettings()` → **constant 200** | **No** — nothing in the app ever sets it |
| **Colourway tuner "Save to design"** | effect | `copyWith` → unchanged (the tuner has no brightness control) | inherited |
| Legacy Design Studio — `CurrentDesignNotifier` / `applyDesignProvider` / `saveDesignProvider` | — | 200 | **Dead code**: `widgets/effect_selector.dart` has no importers and neither provider has a caller. Not touched. |

Other "design-like" types, for completeness:

* **Game Day base design** (`GameDayAutopilotConfig.brightness`) — stored, and applied consistently as `'bri': config.brightness` on every Game Day path. Already consistent; **not touched** (other sessions are active in that area).
* **Favorites** — no brightness column; the favorite *is* a jsonEncoded payload, and whatever top-level `bri` it has is stored and applied verbatim (dashboard grid, geofence). The heart in the Pattern Editor stores the slider value. "Save to Favorites" on the pattern-category screen stores **no** `bri` (`SmartPattern.toJson` has none, and that screen has no brightness control), so those apply at the current level — which is the correct behaviour for "no brightness was set". **Already consistent; not touched.**
* **Scenes** — `library` / `system` / `snapshot` scenes state their own `bri` in their payload and `Scene.brightness` matches it (checked for all four system scenes and the snapshot capture). Design-backed scenes are covered below.

### 1.2 Where it IS stored, is it applied on every path?

**No. There were four different rules, so the same design came back at a different brightness depending on which button applied it.**

| Apply path | Effect design | Per-pixel design |
|---|---|---|
| **My Designs → Apply** (`applySavedDesign`; also the row menu in `pattern_theme_selection`) | `toWledPayload()` → `bri` **always sent** | spine → `bri` sent **only if** tagged `pattern-editor` (this week's fix) |
| **Scene apply** (`applySceneProvider`; voice uses this) | payload `bri`, **then a second device write** `setBrightness(scene.brightness)` | spine (tag rule), **then `setBrightness(design.brightness)` regardless** |
| **Lumina AI router** (`scene.toWledPayload()` → `applyToDevice`) | `bri` always sent | `_positionalPayload()` → `bri: 200` **always sent** |
| **Schedule** (picker → `toWledPayload()` → preset with `ib:true`) | `bri` carried into the preset and fires with it | cannot be scheduled (refused in the picker) |
| **Paint editor Apply / live preview** | — | never sent, **even when editing a design that stores one** |
| **Colourway tuner, design-edit live preview** | **forced `bri: 255`** — `buildSelectorPayload` always states `bri` and the preview never passed the design's | — |
| **Pattern Editor live apply** | slider | slider |
| **AI Studio "Apply to Lights"** | — | never sent |

The concrete defects:

1. **Scene apply contradicted the spine.** For a painted design the spine deliberately sent no `bri` ("the 200 is a default nobody chose") — and then `scene_providers.dart` issued a *second* POST stamping exactly that 200. Same design, My Designs vs. a scene / a voice command: different brightness. `setBrightness` is a real device write (`_postUpdate` → `applyJson({on, bri})`), not a local mirror.
2. **The per-pixel payload disagreed with the per-pixel spine.** `_positionalPayload()` sent `bri: 200` for the same design the spine applied with none — so the AI router's apply differed from My Designs'.
3. **The tuner's design-edit preview drove the lights to 255** the moment any control was touched, whatever the design stored. "Save to design" then kept the stored level, leaving the house showing a look the design would not come back as.
4. **The paint editor ignored a stored brightness** when editing a design that had one (e.g. a Pattern Editor Static design reopened in the paint editor): preview and Apply left the level wherever it was.
5. **This week's fix was keyed on a provenance tag**, so it could not generalise: a paint-editor or AI design had no way to say "this brightness is real".
6. **Minor, same class:** the effect payload sent a stored `0` as `bri: 0` (WLED reads that as off, next to `on: true`) while the spine clamped to 1; and `fromFirestoreData` did `data['brightness'] as int?`, which throws on a double and takes the whole document with it.

### 1.3 Where it's NOT stored, what happened on apply?

Literally-absent `brightness` is near-hypothetical (every writer has always written the key), but the *meaningless* 200 is common — every paint-editor and AI-studio design. Today that 200 was: ignored by My Designs, **stamped by scene apply / voice**, **stamped by the AI router**. A document with no key at all was handed the default 200 by the parser and treated identically.

No shared layer interferes: `applyChannelFilter`, `normalizeWledPayload`, `expandForParticipation`, `pinNoGeometryOnWire`, `WledService.applyJson`, `CloudRelayRepository.applyJson` all work inside `seg[]` only and pass a top-level `bri` through untouched. There is no global cap, night-dim, or poll loop re-asserting the slider. (`HoaComplianceService.getCompliantPattern` does cap `bri` — and has zero callers.) `applyPreviewSync(brightness:)` is local UI state only.

---

## 2. Changes

### 2.1 The model — one rule, one place (`design_models.dart`)

* **New field `brightnessStated` (`bool?`, stored as `brightness_stated`).** `true` = a level somebody set; `false` = the writer had none to record; `null` = **not recorded** (every document saved before today). It is written only when non-null, so re-saving an older design through a writer that does not own brightness (rename, the tuner) records nothing it does not know. The `designs` rule has no field-shape assertions (`firestore.rules:1057`), so **no rules deploy is needed**.
* **`statesBrightness`** is now `brightnessStated ?? (tagged pattern-editor || !isPositional)`. The right-hand side is the no-backfill handling of older documents, by what each shape is *known* to hold: effect designs always captured a real level and were always applied (**unchanged**); Pattern Editor designs restore their slider (**unchanged from `dc20d79`**); any other per-pixel design holds the unchosen 200 and is left alone (**unchanged for My Designs; this is the fix for scenes and the AI router**).
* **`appliedBrightness` (`int?`)** — the `bri` to send, or null to leave the controller alone; floored at 1. **Every apply path reads this and nothing else.**
* `toWledPayload()` and `_positionalPayload()` emit `bri` only when `appliedBrightness != null`.
* **The absent case:** a document with no usable `brightness` parses as `brightnessStated: false` → states none → nothing is sent. `brightness` still reads 200 for display. Nothing is written back. A double is tolerated.
* `liveBrightnessToStore(connected:, brightness:)` — the level the lights are at, or null when no controller is actually answering (a stale/default number is not something the user saw).

### 2.2 Apply paths

| Path | Change |
|---|---|
| Per-pixel spine (`applyPositionalDesignWith`) — My Designs, scenes, AI Studio | `brightness: design.appliedBrightness` (was: tag check) |
| My Designs (`applySavedDesign`) | inherits the above + the payload change; the dashboard mirror now shows `appliedBrightness ?? the current level` instead of the unchosen 200 |
| Scene apply (`applySceneProvider`) — and therefore voice | design-backed scenes follow `design.appliedBrightness`. A design that states none gets **no brightness write** — but still records the manual override and auto-pauses Neighborhood Sync (`_recordManualApply`), because `setBrightness` was also what did those and dropping them would let schedule enforcement re-assert over the scene. Non-design scenes are byte-identical. |
| Lumina AI router, schedule picker | inherit the payload change (no code of their own) |
| Paint editor Apply + live preview | state the edited design's `appliedBrightness`; a new painting states none |
| Colourway tuner design-edit preview | `designEditPreviewPayload` restates `bri` from the design (or removes it). Catalog mode returns the same map instance — untouched. |
| Design detail screen "Brightness" row | shows what Apply will do: `180 (71%)`, or **"Keeps current"** — it used to print a 200 that nothing would apply |

### 2.3 Writers — every design type states its brightness at save

| Writer | Now stores |
|---|---|
| Pattern Editor (Static + Animated) | slider, `brightnessStated: true` |
| Now Playing save | live level, `true` |
| Colour editor | the level it loaded and re-sends, `true` |
| **Paint editor — new** | **the level the lights are at** (`true`); `false` with no controller answering |
| **Paint editor — edit** | keeps a stated level (and makes it explicit); an older unchosen-200 design records the live level at this save |
| **AI Design Studio save** | the live level (`true`); `false` offline. The in-memory build behind "Apply to Lights" states none, as before. |
| Tuner "Save to design", rename, duplicate | `copyWith` carries the field |

**A judgement call you should look at.** The paint editor and the AI studio have no brightness control, so "its set brightness" had to mean something. I used **the live level at save** — the user builds those looks while watching the lights at that level, it is what Now Playing capture and the colour editor already do, and it needs no new UI on a release line. The consequence: a design painted while the house was dimmed comes back dimmed, and the paint editor itself offers no way to change that (the detail screen now at least shows the number). The alternative is a brightness slider in those two editors. If you want that instead, it is additive — `brightnessStated` and `appliedBrightness` do not change.

### 2.4 Deliberately not changed

* **`schedule_sync.dart`.** Effect designs already carry `bri` into the preset (`ib:true`), so the decision already holds for schedules. One residual: a design that states *no* brightness, if scheduled, gets the schedule layer's existing `?? 255`. No current writer can produce a schedulable (effect-shaped) design in that state — only a hand-made document with no `brightness` key — and that file is not one to touch in passing.
* **Voice "run my schedule"** ignores the scheduled payload for a saved design and applies a hardcoded `bri: 200` solid (`voice_providers.dart:344`). That loses the whole design, not just its brightness — a separate bug, reported here, not fixed.
* **Catalog applies** (`buildSelectorPayload`) still commit at `bri: 255`. Not a saved design with a set brightness; out of scope. Worth its own decision.
* Game Day, favorites, non-design scenes — already consistent (§1.1).
* **No production document was read or written.** No backfill.

---

## 3. Files

```
lib/features/design/design_models.dart                       the rule
lib/features/design/manual_editor/design_apply.dart          spine reads it
lib/features/design/apply_saved_design.dart                  dashboard mirror
lib/features/scenes/scene_providers.dart                     scene apply
lib/features/design/manual_editor/manual_design_editor.dart  paint editor: save + apply
lib/features/design/design_providers.dart                    Now Playing + AI Studio save
lib/features/design/editable_pattern_design.dart             Pattern Editor save
lib/features/wled/current_colors_provider.dart               colour editor save
lib/features/wled/colorway_effect_selector.dart              tuner design-edit preview
lib/features/design/screens/design_detail_screen.dart        honest Brightness row
test/features/design/brightness_restore_consistency_test.dart   NEW
test/features/design/manual_editor_brightness_save_test.dart    NEW
test/features/design/positional_design_apply_test.dart          comment only
test/hardware/brightness_restore_live_test.dart                 NEW — bench T27–T30 (My Designs · editor · scene)
test/hardware/brightness_restore_paths_ext_live_test.dart       NEW — bench T31–T34 (favorites · schedule, two halves)
```

---

## 4. Verification

### 4.1 `flutter analyze`

| | Issues |
|---|---|
| Baseline at `64fa5af`, before any change | **382** |
| After | **382** |
| After the rebase onto `9741109` (+105 baseline: 0 errors / 12 warnings / 370 infos = 382) | **382** — 0 / 12 / 370, same split |

No new issue. The new test files and the bench test are clean. The issues the analyzer lists inside files this branch touches are all on lines it did not write (`deprecated_member_use` in `design_models.dart:726` / `design_providers.dart:321`, and an unused `dart:ui` import at `scene_providers.dart:1` — present at `HEAD`, confirmed: the only `Color` in that file is the import itself, before and after).

### 4.2 `flutter test` — full suite, run twice

| Run | Passed | Skipped | Failed |
|---|---|---|---|
| 1 — after the implementation | 3280 | 19 | **2 — both caused by this branch** |
| 2 — final | **3283** | 23 | **1 — a flake unrelated to this branch** |
| 3 — after the rebase onto `9741109` | **3301** | 27 | **0** (exit 0; the run-2 flake did not recur) |

Run 3 reconciles against the +105 baseline (3270 pass / 19 skip) exactly: +31 new passing tests, +8 skipped bench tests (T27–T30 and T31–T34).

**Run 1's two failures were mine, and are fixed.** Both in `design_studio_save_composed_test.dart`: `saveComposedDesignProvider` now asks for `wledRepositoryProvider` (to record the live level), and the real provider calls `ReviewerSeedService.isReviewer(user)`, which reads `user.email` — a getter that test's `_StubUser` does not implement. A real `User` has it; this was a limit of the fake, not a product defect. The harness now overrides the repository provider, and I used that to add two end-to-end cases against `FakeFirebaseFirestore`: an offline save writes `brightness_stated: false`; a save with the lights answering at 64 writes `brightness: 64, brightness_stated: true` (it was the constant 200) and reads back as `appliedBrightness == 64`.

**Run 2's one failure is a timing flake, not a regression — but it is a real red test and I did not fix it.** `test/features/game_day/live_score_badge_refresh_test.dart` › *"UPDATES on a score change while live (0 → 1)"*. It passed in run 1; it passed **3 of 3** re-runs in isolation (8/8 each); it imports nothing this branch touches; and it is built on real wall-clock waits (a 5 ms poll interval checked after `Future.delayed(60 ms)`), which lose under a ten-minute loaded run. It is Game Day code, where other sessions are active, so it is reported rather than touched.

The counts reconcile: 3280 + 2 fixed + 2 new − 1 flake = 3283; skips 19 → 23 are exactly the four new bench tests. The known-red #64 midnight-wrap lease test did not fail in either run.

**New tests: 31 passing + 4 bench (skipped without hardware).**

| File | Tests | Covers |
|---|---|---|
| `brightness_restore_consistency_test.dart` | 21 | the rule's truth table (stated / none / not-recorded × shape × tag); floor at 1; Firestore round trip, the marker never written while null, **the absent-key case**, double tolerance; both payload shapes; `Scene.fromDesign`; the spine; **scene apply sends no second brightness write for an unstated design, and exactly the stored level for a stated one**; each writer; the tuner preview (incl. catalog mode returning the same instance) |
| `manual_editor_brightness_save_test.dart` | 8 | paint editor through the real widget: new → live level; no controller → `false`; controller not answering → `false`; edit keeps a stated level; a legacy Pattern Editor design keeps its slider and becomes explicit; an older unchosen-200 design records the live level; Apply sends the edited design's level; a new painting sends none |
| `design_studio_save_composed_test.dart` | +2 | AI Studio save end-to-end (above) |

The scene test's log also shows the side effects survived the removed write — `ScheduleEnforcement: Manual override recorded` and the Neighborhood Sync auto-pause attempt both fire for the unstated design.

### 4.3 Bench — 19/19 PASS, three runs (see the box at the top)

`test/hardware/brightness_restore_live_test.dart`, same discipline as this week's T22–T26: capture prior state, drive the controller to a **different** live brightness (60) and *read it back* so the "before" is real, apply, read the device's `bri` from `/json/state` (the live-view frame buffer is pre-brightness and cannot show it), restore look + brightness + `ps` at teardown. It never writes presets or `/json/cfg`. The three stored levels (180 / 96 / 140), the live level (60) and the model default (200) all differ, so no reading can be a coincidence.

| Test | Design | Paths | Expect | **Read (all three runs)** |
|---|---|---|---|---|
| **T27** | Pattern Editor **Static**, saved at 180 | My Designs (spine) · paint editor Apply · scene | 60 → **180** ×3 | **180 · 180 · 180** |
| **T28** | Pattern Editor **Animated** (fx 15), saved at 96 | My Designs (payload) · tuner design-edit preview · scene | 60 → **96** ×3 | **96 · 96 · 96** |
| **T29** | **Paint-editor** design stating 140, **no** `pattern-editor` tag — the generalisation | same three | 60 → **140** ×3 | **140 · 140 · 140** |
| **T30** | painted design that predates the field (unchosen 200) | same three | 60 → **stays 60** ×3 — the scene path used to go to 200 | **60 · 60 · 60** |

T27 and T28 are the two you asked for, each from the editor and from My Designs, plus the scene path as a third. T28's editor path also asserts that the tuner's raw preview payload says 255 before design-edit mode restates it — i.e. it reproduces the old defect on the way to showing the fix.

`test/hardware/brightness_restore_paths_ext_live_test.dart` covers the two doors above do not: **favorites** and **schedule sync**. Because the bench controller's `presets.json` has on-device flash corruption (found 2026-09-21), the schedule door is proven in two halves rather than one stored-preset round trip — this file also writes no preset and no `/json/cfg`.

| Test | Door | Expect | **Read (all three runs)** |
|---|---|---|---|
| **T31a** | favorite saved from a design stating 96 — `buildFavoriteCreateData` → `decodeFavoritePayload` → `applyChannelFilter` → `applyJson` (the dashboard grid's apply) | 60 → **96** | **96** |
| **T31b** | favorite with no top-level `bri` (the pattern-category "Save to Favorites" shape) | **stays 60** | **60** |
| **T32** | schedule, **app half** — the exact body `syncAll` psaves, applied live *without* `psave`, from lit AND from master-off | 60 → **96**, `on` → true, both | **96 / on** from lit · **96 / on** from master-off |
| **T33** | schedule, **firmware half** — an EXISTING stored preset fires at its STORED `bri` (flash read only; slots 5 and 3) | **153** · **51** | **153** · **51** |
| **T34** | LATENT — an effect design with `brightnessStated:false` omits `bri`; the schedule layer's `?? 255` fires | **255** | **255** |

**What it cannot prove:** the designs cross the Firestore *codec* in-process (`toFirestore` → `sanitizeForFirestore` → `fromFirestoreData`), not a real Firestore round trip with a client credential. The real leg for this document shape was proven by T25/T26 this week; the only new key is one bool, and the `designs` rule asserts no field shape. It also drives the same functions the screens call, not the screens themselves — there is no test device. And a real `psave` + `ib:true` round trip of the design's `bri` was deliberately not run (flash corruption above); that leg is untouched by this branch (`schedule_sync.dart` is unchanged).

**A finding these tests do not catch, because they assert `bri` only and WLED keeps reporting `bri` while the master is off.** The independent second run also ran a probe copy that read `on`: a **painted (positional) design that states a brightness, applied via the SCENE path, ends `on=false`** — T27 via scene → `on=false bri=180`, T29 via scene → `on=false bri=140`; every other path ends `on=true`. Mechanism, confirmed by reading the rebased code: `applyScene` writes `on:true` through the spine, then calls `wledStateProvider.notifier.setBrightness(appliedBrightness)` (`scene_providers.dart:222`), and `WledNotifier.setBrightness` sends `on: state.isOn` — the notifier's *cached* power, which nothing in `applyScene` syncs first. If the app believes the lights are off (the harness default; in the real app, applying a scene while the lights are off — including by voice, which uses this path) the last write is `{on:false, bri:N}`: brightness restored, lights switched off. **Pre-existing** — consolidated has the same unconditional call — and this branch *narrows* it (unstated designs now skip `setBrightness`) but does not fix it. Not fixed here; see §5. Fix shape: send `bri` alone from the scene path, or sync `isOn:true` on the notifier before `setBrightness`. Any future hardware test that checks brightness should also read `on`.

---

## 5. Open items

1. ~~Run the bench test (T27–T30) from a machine on the bench LAN.~~ **Done** — 19/19 (T27–T34), three runs, last one on the rebased tip (§4.3).
2. **Decide: live-level capture vs. a brightness slider** in the paint editor and AI studio (§2.3).
7. **Pre-existing, not fixed:** a stated-brightness *painted* design applied via the scene path while the app believes the lights are off ends `on=false` — the scene's `setBrightness` carries the notifier's cached `on` (§4.3, last paragraph). Voice uses this path. This branch narrows the exposure (unstated designs no longer take that write) but leaves the mechanism in place.
3. `live_score_badge_refresh_test.dart` is timing-flaky under full-suite load (§4.2).
4. Voice "run my schedule" drops a scheduled saved design for a hardcoded `bri: 200` solid (§2.4).
5. Catalog applies commit at `bri: 255` — whether Explore should touch master brightness at all is its own decision (§2.4).
6. A design that states no brightness, if it were ever schedulable, would fire at the schedule layer's `?? 255` (§2.4). No writer can produce one today.
