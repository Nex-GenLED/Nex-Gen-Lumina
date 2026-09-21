# Game Day celebration colour fix — implementation report

**Date:** 2026-09-21 · **Branch:** `fix/gameday-celebration-team-colors` (local only — not pushed, not tagged, no version bump)
**Base:** `origin/release/store-submission-consolidated` = `73ae375` (fetched and re-confirmed immediately before branching; unchanged since the audit)
**Implements:** `gameday-rainbow-celebration-audit-2026-09-21.md` §8, Fixes A + B + C. That audit is committed at `60e2b18` on the local-only branch `audit/gameday-rainbow-celebration-2026-09-21`.

---

## 1. Result

A score celebration now renders in team colours on every stage of every event type.

| | Before | After |
|---|---|---|
| Touchdown — seconds spent in team colours | 2 of 15 | **15 of 15** |
| Bench: lit LEDs inside the team's hue range, corrected stages | 22–30 % (chance) | **100 %** on all 7 stages, 3 teams |
| Bench: hue buckets lit (of 12) | 12 | **1–2** |
| Tests | 3175 pass / 14 skip / 0 fail | **3203 pass / 14 skip / 0 fail (+28 = the new guard)** |
| `flutter analyze` | 382 issues, 0 errors | **382 issues, 0 errors — identical issue set** |
| Bench controller after the run | — | **restored, 0 state differences** |

Four files changed. Client-only. No Cloud Function, rules, Firestore, Game Day config or `write_jobs` was touched, and nothing needs deploying.

---

## 2. What changed

### 2.1 `lib/features/sports_alerts/services/alert_trigger_service.dart`

**Fix A — effect IDs.** Exactly the six literals the audit enumerated, in `_legacyAnimationSteps`:

| Event | Stage | Hold | `fx` before | was really | `fx` after | is |
|---|---|---|---|---|---|---|
| touchdown / goal | 2 | 5 s | 9 | Rainbow | **3** | Wipe |
| touchdown / goal | 3 | 8 s | 63 | Pride 2015 | **15** | Running |
| win | 2 | 10 s | 9 | Rainbow | **3** | Wipe |
| win | 3 | 15 s | 63 | Pride 2015 | **15** | Running |
| soccerGoal | 3 | 6 s | 63 | Pride 2015 | **15** | Running |
| run | 1 | 6 s | 5 | Random Colors | **13** | Theater |

touchdown and goal share one `case`, so that is 6 literals covering 8 event-stages. The edit was scripted with pre/post counts as a guard: it would have aborted unless the file held exactly 2 × `fx 9`, 3 × `fx 63`, 1 × `fx 5` and 15 stage literals. After: 0 / 0 / 0.

**Left alone, as instructed:** `fx 2` Breathe (5 stages), `fx 23` Strobe (3 stages), `fx 28` Chase (1 stage). Every `sx`, `ix`, `col`, `bri`, `on`, hold duration and stage count is unchanged.

**Fix B — palette.** `'pal': 0` added to **all 15** stage segments, via a named constant `_kTeamColorPalette` whose doc comment carries the reasoning once. `_applyCelebrationToStage` spreads `...seg`, so a user-chosen celebration and the white contrast fallback inherit it with no further change.

**Comments made truthful.** The `buildAnimationSteps` doc block listed "Strobe fx2 → Wipe fx9 → Running fx63", "Strobe Mega fx23" and "Theater Chase fx5". It now gives the real WLED 0.15.1 names, adds the previously missing `win` row, and records why the IDs matter. This is the same doc block the fix had to edit anyway; no comment outside this file was touched.

### 2.2 Tests re-pinned — three, not four

The audit said four assertions pinned the bug. **It was three; the audit over-counted, and I have not "fixed" the fourth.**

| File | Was | Now |
|---|---|---|
| `test/features/sports_alerts/alert_trigger_channel_targeting_test.dart` — touchdown | `[2, 9, 63]`, titled "Strobe fx2 → Wipe fx9 → Running fx63" | `[2, 3, 15]`, titled "Breathe fx2 → Wipe fx3 → Running fx15" |
| same file — soccerGoal | `[28, 23, 63, 2]` | `[28, 23, 15, 2]` |
| `test/features/game_day/celebration_firing_test.dart` — legacy touchdown | `[2, 9, 63]`, "Strobe/Wipe/Running" | `[2, 3, 15]`, "Breathe/Wipe/Running" |

Found empirically: I applied the fix, ran all six celebration test files, and re-pinned exactly what failed. Each carries a dated comment saying it used to pass *because it matched the bug*.

**The fourth — `commercial_celebration_parity_test.dart:113`, `'fx': 9` — is not a pin.** It is a `capturedState` fixture for the contrast check ("the house is currently showing fx 9; the chosen fx 79 is distinct, so it passes through"). It describes the look *underneath* a celebration, not the celebration. It still passes, and changing it would alter what that test tests. Likewise `celebration_firing_test.dart:47` (`effectId: 9`) is a base-*design* fixture. Both untouched.

### 2.3 New guard — `test/features/sports_alerts/celebration_team_color_guard_test.dart` (28 tests)

The app's own `WledEffectsCatalog` had `fx 9` and `fx 63` marked `generatesOwnColors` the whole time. This test makes the catalog the enforcement:

| Group | What fails it |
|---|---|
| each stage uses a colour-reading effect (×10 event types) | a stage whose `fx` is missing from the catalog, or whose `usesUserColors` is false |
| each stage **is** the effect its label says (×10) | label/ID drift — the actual failure mode. An expected-*name* table is resolved through the catalog, so "Wipe" can never again silently mean Rainbow |
| every event type has an expected-name entry | adding an `AlertEventType` without deciding its look |
| every stage asserts `pal: 0` — legacy table; chosen + fallback; after `applyChannelFilter` | a stage that forgets the palette, or a filter change that strips it before the wire |
| slot 0 of every stage is the team primary, W zeroed | colours not reaching the payload |
| **meta:** `fx 9 / 63 / 5` are catalogued as *not* colour-reading | someone making the guard pass by editing the **catalog** instead of the table |
| **meta:** no stage uses a `rainbowEffectIds` member | — |
| **meta:** the contrast fallback (`fx 23`) reads colour | it floods white by overriding `col`; that only works if the effect reads `col` |

**The guard was mutation-tested, not just run green.** I temporarily put the shipped bug back, confirmed the guard caught it, and restored the file byte-identically (SHA-256 `d1a15a0e4abe65a1` before and after):

| Mutation | Guard result |
|---|---|
| touchdown stage 3 back to `fx 63` | **6 tests fail** (colour-reading ×2, label ×2, wire-level, rainbow-family) |
| `pal` removed from the `run` stage | **2 tests fail** |

---

## 3. Bench verification

Target `192.168.1.150` — WLED 0.15.1, 290 LEDs, two buses. Run 10:39 CDT Monday: controller idle, no game window. Same discipline as the audit.

**Payload source.** Not hand-written. A probe drove the **real `ForegroundCelebrationCoordinator`** on the fixed code with a synthetic `ScoreAlertEvent(nfl_chiefs, touchdown, 7)`, a recording delivery, and the real `applyChannelFilter` over the bench topology, then wrote the wire payloads to JSON. The bench script played that file. The other corrected stages came from the real builder, deliberately using **three teams** so the result is not Chiefs-specific: Chiefs (red/gold), Royals (blue/gold), Sporting KC (navy/light blue).

**Pre-flight gate.** Aborts before any write unless `on:false`, every segment `on:false`, none frozen. Snapshot: `on:false, bri:128, ps:2` — byte-for-byte the audit's starting state.
**Writes.** Transient `POST /json/state` only. No `psave`, no `/json/cfg` POST, no Firestore.
**Readback.** WebSocket live-view, 4 frames per stage, all 290 LEDs.

**Metric — one refinement over the audit.** 30° hue buckets alone are not a fair pass test for a *blending* effect, and live-view values are post-gamma (the audit's gold read back as `ff6600`, not `ffb81c`). So each frame also reports **the share of lit LEDs whose hue lies on the arc between the team's two colours**, computed from the payload's own `col` after the controller's gamma (2.8, read from `/json/cfg`), padded ±20°. A rainbow scores roughly the arc's share of the wheel; team colours score 100 %.

### 3.1 After — the fixed code

| Payload | `fx` | Hue buckets | In team range | Off-team | Sample LEDs |
|---|---|---|---|---|---|
| Chiefs touchdown stage 1 *(coordinator)* | 2 Breathe | 1 | **100 %** | 0 % | `b80102` |
| Chiefs touchdown stage 2 *(coordinator)* | **3 Wipe** | 2 | **100 %** | 0 % | `ff6601 b80003` |
| Chiefs touchdown stage 3 *(coordinator)* | **15 Running** | 2 | **100 %** | 0 % | `eb4b01 b80102 f95e01 d12602` |
| Royals run | **13 Theater** | 2 | **100 %** | 0 % | `733e0e 00072b` — exactly 2 distinct colours |
| Sporting KC soccerGoal stage 3 | **15 Running** | 1 | **100 %** | 0 % | `375487 4b71b0 24385f` |
| Chiefs win stage 2 | **3 Wipe** | 2 | **100 %** | 0 % | `ff6601 b80003` |
| Chiefs win stage 3 | **15 Running** | 2 | **100 %** | 0 % | `bc0702 fd6401 c81802` |

All 290 LEDs lit on both buses in every frame. Min and max across the 4 frames were identical for every row — no frame dipped.

### 3.2 Before — same session, same method

The shipped payloads, reconstructed from the fixed ones (old `fx`, `pal` removed) and played under identical conditions, so the comparison is not across two different measurement setups.

| Payload | Hue buckets | In team range | Off-team | Sample LEDs |
|---|---|---|---|---|
| Chiefs touchdown stage 2 — `fx 9` Rainbow | **12** | 22–23 % | **77–78 %** | `00ea15 960069 4500ba d2002d` |
| Chiefs touchdown stage 3 — `fx 63` Pride 2015 | **12** | 28–30 % | **70–72 %** | `02620e 01145c 2a0046 1f6200` |

Matches the audit's own run (12 buckets on both).

### 3.3 Fix B proven on hardware

Base look forced onto a **non-zero palette** (`pal 11`, Rainbow), then the corrected stage fired with and without `pal: 0`. This isolates Fix B from Fix A — both rows use the *corrected* effect ID.

| Stage, over a `pal 11` base | `pal` on segment after | Hue buckets | In team range | Off-team |
|---|---|---|---|---|
| `fx 15` Running, `pal` **omitted** (Fix A only) | 11 — inherited | **12** | 61–62 % | **37–39 %** |
| `fx 15` Running, `pal: 0` (as shipped in this branch) | 0 | 2 | **100 %** | 0 % |
| `fx 3` Wipe, `pal` **omitted** (Fix A only) | 11 — inherited | **10–12** | 24–42 % | **58–76 %** |
| `fx 3` Wipe, `pal: 0` (as shipped in this branch) | 0 | 2 | **100 %** | 0 % |

So Fix A alone would have been correct during a Game Day (whose base asserts `pal:0`) and wrong over any look using a real palette. The audit called this latent; the bench shows it is real.

### 3.4 Restoration

| Check | Result |
|---|---|
| Deep diff of `/json/state`, before vs after, every key | **0 differences** |
| `presets.json` SHA-256 (16) | `3a964a3be99cca60` → `3a964a3be99cca60` |
| `/json/cfg` SHA-256 (16) | `e1feef2eb74dc2b3` → `e1feef2eb74dc2b3` |
| Independent re-read ~20 s after restore | `on:false, bri:128, ps:2`; both segs `on:false fx:0 pal:0 frz:false`, original `col` |
| Second independent re-read 10 min later (10:50 CDT), deep-diffed against the pre-run snapshot | **0 differences**; `cfg` hash unchanged; `presets.json` hash unchanged |

Both hashes also equal the audit's, so nothing persistent has moved on the controller across either session. Lights were lit for about 65 seconds in daylight.

*A caveat on the `presets.json` hash, found while double-checking it.* The bench's `presets.json` contains raw `0xFF` bytes (first at offset 3868), so it is not valid UTF-8. Both my scripts hash the fetch-**decoded text**, where each bad byte becomes U+FFFD; that hash is `3a964a3be99cca60` before, after, and in the audit. Hashing the **raw bytes** gives a different value, `8c53e9fe88f65c3c` (16 585 bytes) — a method difference, not a change. I have no raw-byte "before" to compare, so strictly the text hash could not see one bad byte turning into another. That is not a realistic concern: only `psave`/`pdel` write that file and neither was issued. Future bench scripts should hash raw bytes; the value above is the reference. The `0xFF` bytes themselves pre-date this work and are outside it — noted only because a strict JSON/UTF-8 reader would trip on them.

### 3.5 What the bench does not tell you

It proves **colour**. It does not judge **look**. `sx`/`ix` were kept verbatim as instructed, but those numbers mean different things to different effects, and I cannot see the strip:

- **Wipe at `sx 180`** has a 12 s cycle (`750 + (255−sx)·150` ms) and its phase comes from the controller clock, not from when the stage starts. In a 5 s stage you see part of one red↔gold sweep, starting wherever the clock happens to be.
- **Theater at `ix 200`** gives a gap of `3 + (ix>>4)` = 15: one primary-colour pixel in every 15, the rest secondary. For the Royals that is mostly gold with sparse blue dots. Team colours, but secondary-dominant.

Neither is a defect against this brief. Both are worth one look at the actual roofline before release; if either reads wrong it is a one-number tweak.

---

## 4. Full verification

Baseline = the untouched tip `73ae375`, run in a separate worktree **before** any edit.

| | Baseline `73ae375` | This branch | Delta |
|---|---|---|---|
| `flutter test` — passed | 3175 | **3203** | **+28** — exactly the 28 tests in the new guard file |
| `flutter test` — skipped | 14 | 14 | 0 |
| `flutter test` — failed | 0 | **0** | 0 |
| `flutter analyze` — total | 382 | 382 | 0 |
| — errors / warnings / info | 0 / 12 / 370 | 0 / 12 / 370 | |
| — issues in the four touched files | 0 | 0 | |

Both runs are complete, unfiltered `flutter test` / `flutter analyze` over the whole package. Exit code 0 for both test runs; `flutter analyze` exits 1 on both because of the 382 pre-existing issues.

**The analyzer issue sets are identical, not merely equal in count.** I normalised and diffed the 382 lines from each run: no line added, none removed. None of the 382 is in a file this change touches.

**The +28 is accounted for exactly.** Run alone on the final tree: guard file 28/28, `alert_trigger_channel_targeting_test.dart` 9/9, `celebration_firing_test.dart` 32/32. All seven celebration test files together: 121/121. No test was deleted, skipped or weakened; three expectations were corrected and one file added.

The project note that the suite is "red only on the midnight-wrap lease test" did not reproduce: the baseline was fully green at 10:3x CDT. That test is time-of-day dependent, so a run near midnight may still show it. It is unrelated to this change.

`dart format` was **not** applied. The three pre-existing files are not format-clean at baseline, so the repo does not enforce it; formatting them would have buried a 15-line fix in unrelated churn.

**Isolation.** The branch contains only this work: one code commit (`60282a3`, 4 files) plus this report on top of `73ae375`. No other fix branch's changes are present. The branch's upstream was deliberately **unset** — `git worktree add -b` had pointed it at `origin/release/store-submission-consolidated`, where a stray `git push` would have landed on the release line.

---

## 5. Explicitly deferred — not touched, not forgotten

Verified by `git diff 73ae375` reporting **no difference** in every file below.

### 5.1 Celebration picker is not wired into the foreground path
`foreground_celebration_coordinator.dart:217` still calls `buildAnimationSteps(type, team)` with no third argument, so on residential the Game Day screen's picker remains a no-op and `resolveCelebration` (the contrast check) is never reached. Unchanged: `foreground_celebration_coordinator.dart`, `foreground_celebration_providers.dart`, `celebration_contrast.dart`, `game_day_screen.dart`.

Three things that pass should know, all new since the audit:
- **The groundwork is laid.** Because `pal:0` now sits on the stage template and `_applyCelebrationToStage` spreads it, a chosen celebration will inherit the right palette the day it is wired in. The guard already asserts this.
- **The picker's own list contains colour-ignoring effects.** `celebrationMode` renders a curated list, `WledEffectsCatalog.celebrationPickIds` (17 effects). The catalog marks **6 of the 17** as not colour-reading: Chase Flash Rnd (32) and Chase Random (29) are `generatesOwnColors`; Juggle (64), Fireworks (42), Fireworks 1D (90) and Fireworks Starburst (89) are `usesPalette`. Once the picker is live, choosing one of those brings this bug back by user choice. This is a catalog-level reading, not bench-verified — the wiring pass should bench those six, then either drop them from the list or extend this guard to cover `celebrationPickIds`.
- **This is already reachable on commercial.** `game_day_service.dart:194` goes through `handleAlertEvent`, which *does* honour the chosen effect. A venue that picks "Chase Random" today gets random colours. Out of scope here and untouched, but it means the picker list matters before the residential wiring lands, not only after.

### 5.2 Sibling mislabelled effect comments
Unchanged: `sync_celebration_service.dart` (`88 // Fireworks` is Candle; `11 // Rainbow` is Dual Scan), `game_day_autopilot_background_worker.dart` (`11` called "Sparkle" is Dual Scan; that worker is inert).

One caution for whoever takes this on: extending the catalog guard to `sync_celebration_service` would **fail on `fx 88`**, because the catalog marks Candle `generatesOwnColors` while WLED's Candle (`"Candle@!,!;!,!;!;01"`) does read `col`. That is a catalog question as much as a comment question, which is a good reason it is its own pass.

### 5.3 Also unchanged
`fx 2` is labelled "Strobe" in the original intent but is Breathe, and `fx 23` "Strobe Mega" is Strobe. Both render team colours; both were left as instructed. The doc comment now names them correctly, so the label no longer lies — whether the *look* should become a true strobe is a product call.
Server start-fire omitting `pal` (`gameDayPlanning.ts` `buildParticipatingSegArray`): `functions/` is byte-identical to `73ae375`.

---

## 6. NEW finding — same class, deliberately NOT fixed here

**The Game Day *base design* catalog has the same bug. One team design in six is a rainbow for the whole game.**

Found by a "fix the class" sweep of `lib/` for other team-colour senders using these literals. The audit missed it — it searched the celebration path, not the base-design path.

| Site | Code | Reality on WLED 0.15.1 |
|---|---|---|
| `lib/features/autopilot/team_design_catalog.dart:115-128` — design 5 of 6 | `// 5. Twinkle (WLED fx 63 = Twinkle)` → `effectId: 63`, `pal: 0`, `col: [p, s]` | `fx 63` is **Pride 2015**. Twinkle is `fx 17`. |
| `lib/features/autopilot/game_day_autopilot_service.dart:443` | `_StyleCategory.dynamic => (63, 'Twinkle', 150)` | same |

**Reachable in the shipping app.** `game_day_autopilot_service.dart:311/355/723` builds that catalog and, under `rotating` or `random` variety, selects across all six — so about one game in six gets "{Team} Twinkle". The second site hands `fx 63` to any user whose learned style preference is "dynamic".

**Already proven on hardware.** The wire shape is `fx 63` + `pal 0` + team `col` — which is exactly §3.2's "before" row: 12 hue buckets, 70–72 % off-team. No new bench work was needed to know what it renders.

**Why I stopped instead of fixing it**, despite the instruction to fix the class. Unlike the celebration table, this is not a literal swap:

1. **I have not traced whether `63` ever gets stored — and that decides the size of the fix.** At the one call site I read (`game_day_autopilot_service.dart:577`) the selected design is applied directly via `_applyDesign`, not written back to the config. I did **not** trace whether any other path (team setup, a "suggested design", a saved payload) writes one of these IDs into a stored `effect_id`. If one does, customers may already hold `63` in Firestore, the unattended server start-fire would send it too, and the fix stops being client-only. If none does, this is a contained two-site change. I would rather say "untraced" than guess either way.
2. **I have already been wrong once about this path today.** My first draft of this section asserted persistence as fact; checking disproved it. That is a good reason not to edit a subsystem I have only skimmed.
3. **The right replacement needs a look decision.** On `fx 17`, `col[1]` is the *field*, not a second colour (`sparkle_background.dart`, bench-established 2026-09-19). A mechanical `63 → 17` yields "primary twinkles on a secondary-coloured house". That may well be right — but it is a choice, and the near-identical-colours rule in that file probably needs applying here too.
4. **It is the base design, not a 15-second flash.** It runs for three hours on the feature you have asked be treated as fragile and audited before it is touched.

Your own exclusion test in this brief was "doesn't currently cause a functional bug". This one does, so it is **not** in the deferred-as-cosmetic bucket — it is a real, open defect that needs its own audit → fix cycle. Questions that audit should answer: whether any path stores these IDs, and if so how many configs hold `effect_id: 63` and whether the server should refuse or remap it; and what "Twinkle" should look like in two team colours.

When it is fixed, the guard added here extends naturally: the same `usesUserColors` + expected-name check over `TeamDesignCatalog.build(...)`.

*Adjacent, cosmetic only:* `autopilot_schedule_generator.dart:309` sends `11 // "Twinkle Up"`. `fx 11` is Dual Scan (Twinkleup is 106). It reads colour, so the colours are right; only the motion is not what the comment claims. Untouched.

---

## 7. What was and wasn't touched

| | |
|---|---|
| `main`, the shared checkout, any tag, `pubspec.yaml` version | untouched |
| `fix/firestore-transaction-crash`, `fix/save-to-my-designs-and-favorites`, every other branch and worktree | untouched |
| Remote | `git fetch` only. **Nothing pushed.** |
| Firestore, Cloud Functions, rules, Game Day configs, `write_jobs` | not read, not written, not deployed |
| Bench `.150` | ~65 s of transient state writes; **restored and verified** |
| Audit worktree | one local-only commit (`60e2b18`) adding the audit report, as instructed |
| Temporary probe test | removed from the worktree before the full suite ran; preserved with the bench script, payload JSON, frame logs and baseline/after outputs under `…/scratchpad/fix-evidence/` |
