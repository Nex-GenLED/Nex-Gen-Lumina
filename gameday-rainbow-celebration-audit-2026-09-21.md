# Game Day score celebration renders rainbow, not team colours — forensic audit

**Date:** 2026-09-21 · **Mode:** READ-ONLY audit, nothing fixed · **Audited tip:** `origin/release/store-submission-consolidated` = `73ae375` (fetched and confirmed; detached worktree, scratchpad)
**Applies to builds:** the celebration path is byte-identical in `build-100` (`3df2d24`), `+101` (`9749d91`), `+102` (`a988854`) and `origin/main`. Whichever build was on the phone ran this code.

---

## 1. Verdict

**The celebration sends the wrong WLED effect IDs. It is not a missing team-colour lookup, and it is not (primarily) a missing `pal` field.**

The touchdown sequence sends `fx 2 → fx 9 → fx 63`. The code's own comments call these "Strobe → Wipe → Running". On WLED 0.15.1 they are **Breathe → Rainbow → Pride 2015**:

| Stage | Hold | Comment says | `fx` sent | What 0.15.1 actually runs | Reads team `col`? |
|---|---|---|---|---|---|
| 1 | 2 s | Strobe | 2 | **Breathe** | Yes |
| 2 | 5 s | Wipe | 9 | **Rainbow** | Only if segment palette ≠ 0 |
| 3 | 8 s | Running | 63 | **Pride 2015** | **Never** — hardcoded `CHSV` hue sweep |

13 of the 15 seconds are rainbow. Chiefs red/gold *is* resolved correctly and *is* on the wire in `col` for every stage — it is handed to effects that do not read it.

Hardware-confirmed on the bench (§6): stages 2 and 3 lit all 12 hue buckets evenly. Adding a team palette fixed `fx 9` and did **nothing** for `fx 63`.

Three things in the brief turned out different from the premise — flagging them because they change what the fix pass should touch:

1. **The celebration is not server-dispatched.** No Cloud Function builds a score payload. It is client-side Dart, app-foreground-only.
2. **"Pal-less sender" is the wrong frame for the fix.** Adding `pal:0` to `fx 9` *guarantees* the hue wheel. No `pal` value can rescue `fx 63`.
3. **It is not a regression and not Chiefs-specific.** The wrong IDs are in the original commit from 2026-03-04. It has never rendered team colours for any team.

---

## 2. Step 1 — the actual firing path

### 2.1 There is no server-side celebration

`functions/src/gameDayPlanning.ts:25-33` states it outright:

> "Celebrations are S5b and are NOT built here … unattended firing covers scheduled starts and ends only — not mid-game joins and not celebrations"

A grep of `functions/src/{gameDayPlanning,planGameDayFires,dispatchFireJobs,fireJobs,espnClient,gameDayGate,teardownTeamFires,participationForFire}.ts` for `celebrat|score` finds only that comment, the ESPN scoreboard URL, and an unrelated log string. The server plans a **start** fire (team design) and an **end** fire (`ps:1`/`ps:2`). It never diffs scores.

This matches what was observed: the founder was *watching the app* during the score. The celebration only exists while the app is foregrounded.

### 2.2 The live path, end to end

```
main_scaffold  (keeps provider alive, feeds foreground signal)
 └ foregroundCelebrationControllerProvider            foreground_celebration_providers.dart:167
    └ liveCelebrationTeamsProvider → computeLiveCelebrationTeams   :98 / :129
       (autopilot ∪ ephemeral sessions in liveGame) ∩ (cfg.enabled && cfg.scoreCelebrationEnabled)
    └ ForegroundCelebrationCoordinator.syncLiveTeams  foreground_celebration_coordinator.dart:142
       └ 30 s Timer → ScoreMonitorService.checkScores (ESPN diff; NFL +6/+7/+8 → touchdown)
          └ alertStream → handleAlert → _runCelebration                       :202 / :212
             ├ team  = kTeamColors[event.teamSlug]                            :215   ← colours resolve HERE
             ├ steps = AlertTriggerService.buildAnimationSteps(type, team)    :217   ← NO 3rd argument
             │    └ _legacyAnimationSteps                   alert_trigger_service.dart:365
             │         touchdown: fx 2 → fx 9 → fx 63, col = [primary, secondary, black], no `pal`   :378-398
             ├ captured = delivery.capture()            (GET state)
             ├ delivery.play(steps)                     foreground_celebration_providers.dart:47
             │    └ applyChannelFilter(step.payload, ids, channels)   wled_payload_utils.dart:86
             │    └ wledRepositoryProvider.applyJson    (LAN HTTP, or cloud relay off-LAN)
             └ delivery.revert(captured)
```

`applyChannelFilter` strips `id/start/stop/on` from the template and re-emits it per channel. It adds no `pal` and changes no `fx`. Nothing downstream rewrites the look.

### 2.3 Exact payload (Step 5, synthetic)

Produced by driving the **real** `ForegroundCelebrationCoordinator` with a synthetic `ScoreAlertEvent(teamSlug:'nfl_chiefs', eventType: touchdown, pointsScored: 7)`, a recording `CelebrationDelivery`, and the real `applyChannelFilter` over the bench's two-bus topology. No network, no device, no Firestore.

```json
// stage 1 — hold 2 s
{"on":true,"bri":255,"seg":[
 {"id":0,"fx":2,"sx":240,"ix":255,"col":[[227,24,55,0],[255,184,28,0],[0,0,0,0]],"on":true},
 {"id":1,"fx":2,"sx":240,"ix":255,"col":[[227,24,55,0],[255,184,28,0],[0,0,0,0]],"on":true}]}
// stage 2 — hold 5 s
{"seg":[{"id":0,"fx":9,"sx":180,"ix":200,"col":[[227,24,55,0],[255,184,28,0],[0,0,0,0]],"on":true},
        {"id":1,"fx":9, …same… }]}
// stage 3 — hold 8 s
{"seg":[{"id":0,"fx":63,"sx":128,"ix":200,"col":[[227,24,55,0],[255,184,28,0],[0,0,0,0]],"on":true},
        {"id":1,"fx":63, …same… }]}
```

`[227,24,55]` = `#E31837` Chiefs red. `[255,184,28]` = `#FFB81C` Chiefs gold. Correct, present, and ignored by stages 2–3.

---

## 3. Step 2 — is this the previously flagged finding?

**Same location, different cause than the flag implied.**

- The Design Studio audit's list named `alert_trigger_service fx 9/63` as a "pal-absent sender". That is this code. So yes — it is the flagged "sports alerts" item, now field-confirmed.
- It is **not** `SmartPattern.toJson`. The celebration path builds raw `Map` literals. `SmartPattern` is not imported or referenced anywhere under `lib/features/sports_alerts/` or in the Game Day autopilot service. The two share a symptom, not code.
- It is **not** shared with any server TypeScript. There is no server counterpart to share with (§2.1).

Where the prior framing misleads: "pal-less rainbow sender" suggests the repair is "send a `pal`". For this path that is wrong twice over:

| Effect | With `pal` absent / `pal:0` | With a team palette (`pal:3`) |
|---|---|---|
| `fx 9` Rainbow | hue wheel — `Segment::color_wheel`, `FX_fcn.cpp:1145-1146`: `if (palette) return color_from_palette(...)`, else the RGB wheel | red↔gold flow (bench-confirmed) |
| `fx 63` Pride 2015 | rainbow | **still rainbow** — `FX.cpp:1870-1906` builds `CHSV(hue8, sat8, bri8)` and never touches `SEGCOLOR` or the palette. Its metadata string is `"Pride 2015@!;;"`: zero colour slots, zero palette slot |

And the Game Day base design explicitly asserts `pal: 0` (`team_design_catalog.dart:210`, `game_day_autopilot_service.dart:873`, `game_day_apply.dart:77`). So during a live game the segment palette is 0, the pal-less `fx 9` inherits 0, and the hue wheel is the deterministic outcome — not a fallback.

**The app's own catalog already knew.** `wled_effects_catalog.dart:366,368` lists `id 9 'Rainbow'` and `id 63 'Pride 2015'`, both `ColorBehavior.generatesOwnColors`, and `rainbowEffectIds` (`:594`) opens with `9`. The celebration table was never cross-checked against it.

---

## 4. Step 3 — where team colours come from, and why they don't land

**Source:** `kTeamColors` — a hardcoded `const Map<String, TeamColors>` in `lib/features/sports_alerts/data/team_colors.dart` (≈450 entries, keyed by slug). `nfl_chiefs` at `:132` = `#E31837` / `#FFB81C`. No Firestore collection, no brand library, no server map is involved or needed.

**Resolution works.** `_runCelebration` reads `kTeamColors[event.teamSlug]` and returns early if null. `_teamColorArray` builds `[primary, secondary, black]` with `forceZeroWhite`. The colours reach the wire (§2.3).

Against the three hypotheses in the brief:

| Hypothesis | Finding |
|---|---|
| A stored mapping exists that the function should read but doesn't | **No.** It reads the right map and gets the right colours. |
| Unconditionally sends a generic rainbow, by design or oversight | **Oversight.** Commit message, doc comments and the "team-colored LED animations" title all show team colour was the intent. The effect IDs are simply wrong. Team-colour celebration was *implemented* but has never *worked*. Not a regression. |
| An omitted `pal` makes WLED fall back to rainbow | **Partly, for `fx 9` only, and it's the lesser half.** `fx 63` is rainbow under every palette. |

**The mislabelling is systematic, not a one-off typo.** The same file, since the first commit:

| Event | Comment intent | `fx` sent | Actual 0.15.1 effect | Correct ID for the intent |
|---|---|---|---|---|
| touchdown / goal / win — stage 1 | Strobe | 2 | Breathe | 23 |
| touchdown / goal / win — stage 2 | Wipe | 9 | **Rainbow** | 3 |
| touchdown / goal / win — stage 3 | Running | 63 | **Pride 2015** | 15 |
| soccerGoal — stage 3 | Running | 63 | **Pride 2015** | 15 |
| run | Theater Chase | 5 | **Random Colors** (also `color_wheel`) | 13 |
| safety | Strobe Mega | 23 | Strobe | 25 |
| fieldGoal, quarterEndWinning | Breathe | 2 | Breathe | ✓ |
| clutchBasket | Strobe | 23 | Strobe | ✓ |
| soccerGoal — stages 1, 2, 4 | Chase, Strobe, Breathe | 28, 23, 2 | as labelled | ✓ |

IDs verified against `wled00/FX.h` at tag `v0.15.1` (the SOP-pinned version; bench reports `0.15.1`, vid `2507300`).

---

## 5. Step 4 — scope

**Generic. Every team, every sport, since day one.**

- `_legacyAnimationSteps(eventType, team)` uses `team` only to fill `col`. The `fx` literals are constants. No per-team branch exists anywhere in the path.
- `git log -S"'fx': 63"` on the file: introduced in `11830fb` (2026-03-04, *"Add Sports Alerts feature … team-colored LED animations"*), whose comments already read *"Color Wipe — effect ID 9"* and *"Running Lights — effect ID 63"*. Carried unchanged through `fd87ddf`, and copied into the new `win` sequence by `3d79576` (2026-08-25).
- The coordinator's own header (`foreground_celebration_coordinator.dart:5-8`) notes per-score celebrations "have never worked in a shipped build" before the foreground rebuild. So the first time anyone could *see* this table render was recent — which is why a March bug surfaced in September.
- Chiefs is simply the only armed team. Nothing about Chiefs is special.

**What renders rainbow, by event:** touchdown, goal, win (2 of 3 stages), soccerGoal (1 of 4 stages), run (the whole thing — `fx 5` Random Colors, MLB). **What already renders team colours:** fieldGoal, safety, quarterEndWinning, clutchBasket.

**History check:** I did not query Firestore. Foreground celebrations on LAN go straight over HTTP and leave no server record; off-LAN they would appear as relay commands, but those are swept. The code proof above makes a ledger search unnecessary — there is no code path by which any team could have received a correctly coloured touchdown.

---

## 6. Step 5 — verification

### 6.1 Synthetic invocation — done
§2.3. Probe test ran 3/3 green, then was removed from the worktree (`git status` clean). Source preserved in the evidence folder.

### 6.2 Bench render — done, fully restored

Target `192.168.1.150` (WLED 0.15.1, 290 LEDs, two buses). Run at 09:5x CDT Monday — no NFL game live, hours ahead of any possible server start-fire.

**Pre-flight gate:** script aborts before any write unless `on:false`, all segments `on:false`, none frozen. Snapshot was exactly that: `on:false, bri:128, ps:2` (NGL Off).
**Writes:** transient `POST /json/state` only. No `psave`, no `/json/cfg`, no Firestore, no Game Day config, no `write_jobs`.
**Readback:** `/json/live` is not compiled into this build (`{"error":4}`), so frames were read over the WebSocket live-view (`{"lv":true}`), 3 frames per stage, all 290 LEDs. Hue bucketed into 12 × 30° bins.

| Payload | Hue buckets lit (of 12) | Sample LEDs | Reads as |
|---|---|---|---|
| **Exact stage 1** `fx 2` | **1** | `be0902`, `f55901` | Chiefs red breathing toward gold ✓ (built-in control) |
| **Exact stage 2** `fx 9` | **12**, evenly spread | `bd4200 2400db 00fc03 e4001b 003cc3` | **Full rainbow** |
| **Exact stage 3** `fx 63` | **12**, evenly spread | `445300 640014 010b69 315800` | **Full rainbow** |
| Diagnostic `fx 9` + `pal:3` | **2** (red, orange-gold) | `b80002 ff6600 e64200` | Team colours |
| Diagnostic `fx 63` + `pal:3` | **12** | `0f4200 23000b 0b0026 002531` | **Still rainbow** |

*Disclosure:* the two diagnostic rows go one step beyond "the exact payload". They are the same stage-2/3 payloads with `pal:3` added — same transient class of write, same snapshot/restore. I ran them because they settle the brief's third Step-3 question on hardware, and because "just add a `pal`" is the most likely wrong fix.

**Restore:** full segment look fields re-posted from the snapshot, then `{"ps":2}` re-asserted.

| Check | Result |
|---|---|
| Deep diff of `/json/state`, before vs after (every key) | **0 differences** |
| `presets.json` SHA-256 (16) | `3a964a3be99cca60` → `3a964a3be99cca60` |
| `/json/cfg` SHA-256 (16) | `e1feef2eb74dc2b3` → `e1feef2eb74dc2b3` |
| Independent re-read a minute later | `on:false, bri:128, ps:2`, both segs `on:false fx:0 pal:0 frz:false`, original `col` |

Lights were lit for roughly 25 seconds in daylight. No persistent state changed.

Evidence (snapshot, after-state, full frame log, bench script, probe test): `…/scratchpad/evidence/` under this session's scratchpad.

---

## 7. Second, separate defect found on the way

**The Game Day celebration picker has no effect on the only live path.**

`cf09040` (*"fire the user's chosen celebration, keep the timing table"*) threaded `celebrationEffectId` into `AlertTriggerService.handleAlertEvent`. But the foreground coordinator does not call `handleAlertEvent` — it calls `buildAnimationSteps(event.eventType, team)` with **no third argument** (`:217`), and `CelebrationTeam` has no celebration fields to carry one. `resolveMonitoring`, which does carry the choice, is consumed only by `sports_background_service` (`kSportsBackgroundServiceEnabled = false`) and the lazy migrator.

So on residential, a user can pick a celebration on the Game Day screen, preview it, save it — and the legacy rainbow table fires anyway. The contrast check (`resolveCelebration`) is likewise never reached. Commercial (`game_day_service.dart:194`) does go through `handleAlertEvent`.

This is independent of the rainbow bug. It matters for the fix because it removes a tempting shortcut: "tell users to pick a celebration" would not work.

---

## 8. Proposed fix — described, not implemented

Principle: smallest change that makes the colours right, touching nothing in Game Day's gating, timing, phase machines, or server code. **Client-only. No Cloud Function, rules, or Firestore change. No redeploy.**

### Fix A — correct the colour-ignoring effect IDs *(the actual bug; recommended as its own commit)*

In `_legacyAnimationSteps` only:

| Where | Change | Why |
|---|---|---|
| touchdown / goal / win, stage 2 | `fx 9` → `fx 3` (Wipe) | matches the documented intent; `"Wipe@!,!;!,!;!"` reads col 1/2 |
| touchdown / goal / win, stage 3 | `fx 63` → `fx 15` (Running) | `"Running@!,Wave width;!,!;!"`; blends `SEGCOLOR(1)` with col 0 |
| soccerGoal, stage 3 | `fx 63` → `fx 15` | same |
| run | `fx 5` → `fx 13` (Theater) | matches "Theater Chase"; `"Theater@!,Gap size;!,!;!"` |

Leave `sx`/`ix`, holds, stage counts, `on`/`bri` and the `col` array exactly as they are.

**Deliberately *not* in Fix A — needs Tyler's call:** stage 1 sends `fx 2` (Breathe) where the comment says Strobe (`23`), and safety sends `23` (Strobe) where the comment says Strobe Mega (`25`). Both already render team colours. Changing them alters a look that works today, which is a product decision, not a bug fix. Note `sx` means something different per effect — `fx 15` at `sx:128` and `fx 3` at `sx:180` should be eyeballed on the bench before the values are trusted.

### Fix B — assert `'pal': 0` on every stage *(latent defect; same commit or the next)*

This is where the "pal-less sender" flag is genuinely right. Wipe / Running / Theater all read colour through `color_from_palette`. With `pal` absent the segment keeps whatever palette the pre-celebration look had. Game Day's base asserts `pal:0`, so it's fine today — but a celebration fired over an Explore pattern or a preset using, say, Party would render Party colours. `pal:0` makes the celebration deterministic regardless of the base. The revert path re-posts the captured `seg` including its original `pal`, so restore is unaffected. `_applyCelebrationToStage` spreads `...seg`, so a chosen celebration inherits it for free.

### Fix C — make the catalog the guard *(tests)*

Four assertions currently **pin the bug** and must change with Fix A:
- `test/features/sports_alerts/alert_trigger_channel_targeting_test.dart:51` — `expect(fx, [2, 9, 63])`
- same file `:68` — `[28, 23, 63, 2]`
- `test/features/game_day/celebration_firing_test.dart:70` — `[2, 9, 63]`
- `test/features/game_day/commercial_celebration_parity_test.dart:113` — `'fx': 9`

Add one new test so this cannot recur: for every `AlertEventType`, every stage's `fx` must resolve in `WledEffectsCatalog` to `usesSelectedColors` or `blendsSelectedColors`, and must carry `pal: 0`. That turns the catalog — which was right all along — into the enforcement.

### Fix D — wire the picker into the foreground path *(§7; separate change, after A–C are bench-verified)*

Carry `celebrationEffectId/Speed/Intensity` on `CelebrationTeam`; in `_runCelebration` move `capture()` **before** step-building, call `resolveCelebration(...)` against the captured state, pass the result as the third argument. Also confirm the picker in `celebrationMode` cannot offer a `generatesOwnColors` effect, or Fix A's bug returns by user choice. Keep it out of the first change: it reorders capture/build and activates the white-strobe fallback for the first time in production, which is a larger behavioural surface than a four-integer fix.

### Verification the fix pass should do
1. New catalog-guard test green; the four re-pinned tests green. (Suite baseline: red only on the known midnight-wrap lease test.)
2. Bench, same discipline as §6.2: fire the corrected touchdown + run + soccerGoal payloads, expect **≤ 2 hue buckets** on every stage. The script in the evidence folder does this unchanged — swap the payloads.
3. Bench a celebration **over a non-zero-palette base** to prove Fix B.
4. No server deploy, no `write_jobs` change, no Game Day config write is required for any of A–D.

---

## 9. Adjacent observations — not investigated further, not part of this fix

1. **Same mislabelling in sibling celebration code.** `sync_celebration_service.dart:336` sends `88 // Fireworks` — on 0.15.1 `88` is **Candle** (Fireworks is `42`); `:340` sends `11 // Rainbow` — `11` is **Dual Scan**. `game_day_autopilot_background_worker.dart:650` falls back to `11` calling it "Sparkle" — Sparkle is `20` (that worker is inert). The pattern suggests these IDs came from a different effect table. A sweep of every commented `'fx': <literal>` against the catalog would be a cheap, high-yield follow-up.
2. **Server start-fire omits `pal`.** `buildParticipatingSegArray` (`gameDayPlanning.ts:116-131`) emits `id/on/fx/sx/ix/col` and no `pal`, while the Dart builders it ports assert `pal:0`. A server-fired base design therefore inherits the segment's prior palette. Not the cause here, and code-only — not verified on hardware. It does cut against that file's own rule that the two paths must render identically.
3. **No tracker entry exists.** `docs/BUGS_AND_DEBT.md` has nothing under pride / fx 63 / rainbow-celebration.

---

## 10. What was and wasn't touched

| | |
|---|---|
| `main`, shared checkout, any tag | untouched |
| Firestore-transaction-crash worktree / branch | untouched |
| Firestore (any document), `write_jobs`, Game Day configs | not read, not written |
| Cloud Functions | read only; nothing built or deployed |
| Bench `.150` | ~25 s of transient state writes; **restored and verified** — 0 state diffs, `presets.json` and `cfg` hashes unchanged |
| Audit worktree | clean except this report (untracked, uncommitted) |
| Network | `git fetch`; three WLED `v0.15.1` source files downloaded from GitHub for reference |
