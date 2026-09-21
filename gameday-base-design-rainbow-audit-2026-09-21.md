# Game Day base design — fx 63 "Twinkle" is Pride 2015 (rainbow)

**Audit only. No code changed, nothing deployed, nothing pushed.**
Date: 2026-09-21 · Base: `origin/release/store-submission-consolidated` @ `73ae375` (fetched and confirmed at start) · Branch: `audit/gameday-base-design-rainbow-2026-09-21` (local, no upstream) · Firmware reference: WLED **v0.15.1** source (the SOP-pinned version), fetched at the tag.

---

## Summary

The bug is real: two places send `fx 63` labelled "Twinkle". On WLED 0.15.1, `fx 63` is **Pride 2015**, which reads neither `col` nor the palette. Real Twinkle is `fx 17`.

Three things in the brief turned out different from what was assumed. They change the priority and the shape of the fix.

1. **"About 1 game in 6 renders rainbow all game" does not happen in any shipped build.** The catalog's payload reaches hardware through exactly one consumer, the background worker, and that worker is compiled off (`kSportsBackgroundServiceEnabled = false`). The catalog's only live use writes a *name* ("Chiefs Twinkle") into a calendar entry. The lease manager then fires that entry as `fx 0` solid primary.
2. **The live site is the other one, `game_day_autopilot_service.dart:443`, and it is not 1-in-6.** It is deterministic per user: every game, for any user whose profile `preferred_effect_styles` is dynamic-dominant and who has no saved design, when the foreground app activates pre-game. **Today that is 0 of 51 users.**
3. **No server-side fix is needed for fx 63.** The server has no copy of the wrong ID. It sends the config's stored `effect_id` verbatim, and production holds zero stored 63s (49 configs, 5 saved payloads, 21 historical fire jobs checked).

So current real-world exposure is **zero accounts**, but the defect is one settings change away for any customer (Edit Profile → Preferred Effect Styles → select *Twinkle* and *Rainbow*). It should be fixed before it is reached, not because it is firing now.

**The hardware bench comparison in Step 3 was NOT performed.** This machine was on a phone-hotspot subnet (`172.20.10.5`), not the home LAN; `.150` and the bridge `.96` both timed out. Step 3 below is built from the pinned firmware source, two prior hardware measurements of these exact effects, and a source-port simulation. The live side-by-side is still owed before parameters are chosen. Details in Step 3.

---

## Step 1 — Current armed scope (Firestore, read-only)

Read with Application Default Credentials, `.get()` calls only, no `orderBy`. UIDs are truncated here because this repository is public.

### Server path (`planGameDayFires`) — unchanged from the 2026-09-14 record

| Item | Value |
|---|---|
| `config/gameday_planner.write_jobs` | `true` |
| `uid_allowlist` | **1 uid** — `wrQRUUKy…` (the founder's app account) |
| `armed_note` | the 2026-09-14 "minimal re-arm, bench only" note, unmodified |
| Founder's enabled teams | **1** — `nfl_chiefs` |
| Founder's gate | `gameday_gate_blocking: []` (clear) |
| Founder's config | `design_mode: saved`, "Kansas City Chiefs - Solid", saved payload `fx 83` on both segments, updated 2026-09-21T00:43Z |

Server scope has not widened: one account, one team.

The founder's own config is **immune on every path**. A saved design wins in `selectDesign` (client), in `buildGameDayPayload` (server), and in `game_day_apply` (Light Up Now / mid-game join). The founder cannot reproduce this bug on their own account without first clearing the saved design.

Recent server start fires for the founder carried `fx 52` (2026-09-14) and `fx 15` (2026-09-20). Across all 21 historical fire jobs the histogram is `{0: 5, 15: 2, 52: 6}`. **No fire job has ever carried fx 63.**

### Client path — the "founder only" assumption does not apply here

The server allowlist gates the server and nothing else. The foreground loop (`GameDayAutopilotNotifier`, a 1-minute `Timer.periodic` → `evaluateConfigs`) has no flag and no allowlist. It runs for any signed-in user with an enabled config while the app is open.

| Item | Value |
|---|---|
| `game_day_autopilot` docs fleet-wide | 49, across 19 accounts |
| Enabled | **20 docs across 12 accounts** |
| `design_variety` | `rotating` on all 49 (the default) |
| `design_mode` | `fallback` 42 · `saved` 5 · `autoSelected` 2 |
| `config/calendar_leases.liveWritesEnabled` | `true` |

So client-side Game Day is live for 12 accounts, not 1. What decides whether any of them sees rainbow is the next table.

### Exposure to fx 63 specifically

| Check | Result |
|---|---|
| Stored `effect_id == 63` | **0** of 49 |
| Saved payload containing `fx 63` | **0** of 5 |
| Users whose `preferred_effect_styles` categorises as *dynamic* | **0** of 51 (26 have the field; every one is exactly `[static, animated]`) |

Nobody has ever changed that preference off its default, so nobody can currently reach `:443`'s dynamic branch.

---

## Step 2 — Is fx 63 stored anywhere, and does the server send it?

### Every path that can put a Game Day base look on the wire

| # | Path | Live in a shipped build? | Where `fx` comes from | Can it send 63? |
|---|---|---|---|---|
| 1 | Foreground autopilot — `_activatePreGame` → `selectDesign` (`service.dart:401-484`) | **Yes**, app open, all users | saved payload → else style category `(0 / 28 / 63)` → else Solid | **YES** — `:443`, when styles are dynamic-dominant and no saved design |
| 2 | Server — `planGameDayFires.buildGameDayPayload` (`planGameDayFires.ts:198-273`) | Yes, allowlist of 1 | saved payload verbatim → else `config.effect_id` (default 52) | Only if 63 were **stored**. It is not. |
| 3 | Light Up Now / mid-game join — `game_day_apply.dart:74` | Yes | saved payload → else `config.effectId` | Same as #2 |
| 4 | Calendar lease — `_synthesizeWledPayload` (`calendar_entry_lease_manager.dart:1065`) | Yes (`liveWritesEnabled: true`) | **always `fx 0`** solid in the entry's colour | No |
| 5 | Background worker — `buildBasePayloadForTest` → `TeamDesignCatalog` (`background_worker.dart:551-582`) | **NO** — `kSportsBackgroundServiceEnabled = false` (`sports_background_service.dart:39`) | catalog, rotating / random | Would, if ever enabled |
| 6 | `populateCalendarForTeam` → `TeamDesignCatalog` (`service.dart:311,355`) | Yes | **name only** — `patternName: design.name` | No `fx` is stored; see below |

### What this means for the two reported sites

**`team_design_catalog.dart:115-128` (design 5 of 6).** The wrong ID is in the payload, but no live code sends that payload.

- Its one hardware-reaching consumer (#5) is dead code in every shipped build. `gameDayPlanning.ts:11` says the same independently: *"INERT, never ran in a shipped build."*
- Its live consumer (#6) keeps only `design.name`. `CalendarEntry` has no effect field. Any entry labelled "&lt;Team&gt; Twinkle" on the schedule is fired by path #4 as **solid primary colour**.
- Even the label is rarer than 1 in 6. `gameIndex` restarts at 0 on every populate call and the window is 7 days, so the "Twinkle" name needs a team's **fifth game inside one week**. An NFL team plays once a week and is always index 0 ("&lt;Team&gt; Colors"). Only daily sports (MLB, sometimes NBA/NHL) reach index 4.
- So the customer-visible defect from the catalog today is a *label that promises Twinkle and delivers Solid*, not a rainbow. All six catalog designs have this problem, not just design 5: whatever the rotation picks, the lease fires Solid.
- One more hazard if #5 is ever switched on: its `random` branch seeds with `DateTime.now().millisecondsSinceEpoch ~/ 1000`. That is not stable per game, despite `selectForRandom`'s doc comment ("same seed → same design"). The 15-second post-celebration revert would re-roll the design. Separately, `AutopilotVarietyMode` has no `random` member, so that branch is unreachable from any stored config.

**`game_day_autopilot_service.dart:443`.** This is the live one. `_categorizeStyles` returns `dynamic` only when the dynamic score *strictly* exceeds both others. The selectable chips (`edit_profile_screen.dart:1257`) are `static, animated, chase, twinkle, rainbow`. Starting from the default `[static, animated]`:

| User selects | static / motion / dynamic | Result |
|---|---|---|
| default | 2 / 2 / 0 | Solid (`fx 0`) |
| + twinkle | 2 / 2 / 2 | Solid — a tie is not enough |
| + twinkle + rainbow | 2 / 2 / 4 | **`fx 63` — rainbow, every game** |
| only twinkle | 0 / 0 / 2 | **`fx 63` — rainbow, every game** |

When it triggers, the on-screen design name is "Twinkle in &lt;Team&gt; Colors", over a payload that contains no team colour the effect will read.

### Is 63 ever written to a stored document?

**No.** `effect_id` has exactly two writers:

- `GameDayAutopilotConfig.toFirestore()` (`config.dart:367`), used by `addTeam`; constructor default `52`.
- `GameDayAutopilotNotifier.saveDesign()` (`providers.dart:1283`), which takes `fx` from the library pattern the user picked (three picker call sites). The user's own choice, not the catalog.

`DesignSelection` (the output of `selectDesign`) and `TeamDesign` (the catalog output) are never persisted. They go to `onApplyPayload` or to `patternName`, and nowhere else. Production data agrees: zero 63s.

### Server-side verdict

**No server fix is required for this bug.** `functions/src/` contains no literal 63 and performs no catalog or style selection. It will send a 63 only if one is stored, and none is.

### One loose end that was not resolved

The reviewer demo account's two configs carry `design_mode: "autoSelected"`, `effect_id: 28`, `speed: 180`, `intensity: 180`. That is byte-for-byte `selectDesign`'s *motion* branch output. Written 2026-08-07 19:44–19:46Z.

This matters because a code path that persists an auto-selected design would also persist 63 for a dynamic-style user. The server and path #3 would then send it, unattended.

- No such path exists on any ref. A `git log --all -S` pickaxe for `autoSelected`, `design.effectId`, `selection.effectId` and `designMode: design.mode` finds only the enum's introducing commit (`58f4e73`). No seed script on disk writes it.
- The most consistent explanation is a hand-seeded demo account. That is an inference, not a finding. It is `fx 28` and harmless either way. Its provenance is **unknown**.

---

## Step 3 — What the corrected look would actually render

### The bench comparison was not run

- **Why.** The audit machine was at `172.20.10.5` (iPhone Personal Hotspot range). `GET /json/info` to `192.168.1.150` and `GET /api/status` to `192.168.1.96` both timed out at TCP connect, with no ARP entries.
- **Why the cloud relay was not used instead.** It would mean writing command documents into the founder's production queue to flash an unattended house over a 5–45 s round trip, with restore travelling the same slow path. The relay also carries discrete commands only. It cannot stream pixel frames, so it would not have produced the visual evidence this step exists for.
- **Bench state touched: none.** Two HTTP GETs were attempted and neither connected. Zero bytes reached the controller or the bridge. No `/json/state` POST, no `psave`, no `/json/cfg`. **There is nothing to restore.**
- **Firestore:** reads only. Both scripts are in the session scratchpad, contain no `set` / `update` / `delete`, and are not in this repo.

What follows rests on four sources, each labelled where it is used:

- **[SRC]** WLED v0.15.1 `FX.cpp` / `FX_fcn.cpp` / `FX.h`, read at the tag.
- **[HW-0921]** The celebration-fix bench log: `fx 63` driven on `.150` with Chiefs colours, 2026-09-21. Evidence commit `7963e0c`, local-only.
- **[HW-0919]** The Twinkle `col[1]` bench on `.150`, 2026-09-19, a roughly 133-frame series.
- **[SIM]** A line-for-line JavaScript port of `mode_twinkle` + `fade_out`, run for this audit. It models structure (coverage, cadence). It does **not** model gamma or RGBW white extraction, so it says nothing about exact on-strip hue.

### fx 63 — Pride 2015: what customers get today if they reach `:443`

- **[SRC]** Metadata `"Pride 2015@!;;"`: one slider (speed), **no colour slots, no palette**. Every pixel is `CHSV(hue8, sat8, bri8)` with `hue16 += hueinc16` along the strip. `col`, `pal` and `ix` are all ignored.
- **[HW-0921]** With Chiefs red/gold on the wire, all **12 of 12** 30° hue buckets were populated in every sampled frame. **70–72 % of lit LEDs were off the team's hue arc.** 160+ distinct colours per frame, all 290 LEDs lit.

Plainly: a slow, soft, full-spectrum rainbow drifting along the whole roofline. It has no relationship to the team, for the entire game. The team colours are in the payload and the effect never looks at them.

### fx 17 — real Twinkle: not what the word suggests

**[SRC]**, confirmed by **[SIM]**:

- **`col[1]` is the whole-strip field.** `fade_out(224)` pulls every pixel toward `SEGCOLOR(1)` each frame. At `pal: 0`, every sparkle is exactly `col[0]` (`color_from_palette` short-circuits on palette 0). So `col: [primary, secondary]` means *primary dots on a full-brightness secondary house*.
- **It is an accumulator, not independent twinkling.** A replayed PRNG re-draws the same lit set every frame, so dots stay solidly on. One more dot is added each `20 + (255−sx)×5` ms until `maxOn = map(ix, 0,255, 1,SEGLEN)`. Then **every dot releases at once**, fades out in about half a second, and the fill restarts with a new seed.
- **[HW-0919]** confirmed the field behaviour on this controller: with two near-identical colours, 97 of 97 lit LEDs were constant in every frame ("Twinkle shows solid").

**[SIM]**, Chiefs colours, 128-LED segment, 180 s. The 162-LED segment scales proportionally.

| Candidate | New dot every | Fill → wipe period | Avg / peak % of LEDs in sparkle colour | Avg % in field colour |
|---|---|---|---|---|
| **A. Bare ID swap** — `fx17 sx150 ix200 col[p,s]` | 545 ms | **54.5 s** | 30 / 57 | 69 |
| B. Same, `sx200` | 295 ms | 29.5 s | 30 / 59 | 67 |
| C. `sx200 ix128 col[p, 30 %·s]` | 295 ms | 18.9 s | 21 / 43 | 76 (dim) |
| D. `sx200 ix128 col[p, black]` | 295 ms | 18.9 s | 21 / 43 | 75 (dark) |

Plainly, candidate A (just changing 63 to 17) on a Chiefs house: a solid **gold** roofline with a red dot added every half second. It is about half red after a minute, then every red dot vanishes together and it starts over. It is on-brand in colour. It does not twinkle, and the design's "celebratory sparkle" intent is not met.

### A bare ID swap is unsafe across the team table

Census of all 449 `kTeamColors` entries, reading `col[1]` as the field:

| Colour class | Teams | What a bare `63 → 17` swap renders |
|---|---|---|
| Secondary ≈ white | **94** (Jets, Red Wings, Maple Leafs, …) | A **white house** with team-coloured flecks |
| Secondary ≈ black | 63 (Steelers, Saints, Bulls, …) | Classic twinkle on a dark field — the good case |
| Primary ≈ black | **18** (Raiders, Nets, White Sox, LAFC, …) | **Black "sparkles"** — holes punched in a lit field |
| Pair distance &lt; 120 | 13 (Mariners, Blue Jays, Mavericks, …) | Reads as a **solid** ([HW-0919] failure mode) |

`sparkle_background.dart` (the +101 fix for that solid-field failure) is **not on the Game Day path**. Its only consumers are `selector_payload.dart` and `pattern_repository.dart`. Neither builder in this audit, nor the server, goes through it.

### fx 80 — Twinklefox: closer to what "Twinkle" was meant to be

**[SRC]** only. It has never been benched with team colours in this project.

- Every pixel runs its **own** clock and fades in and out independently. This is the look most people mean by "twinkle".
- Sparkle colours come from the **palette** (`ColorFromPalette(SEGPALETTE, …, NOBLEND)`).
- The **firmware dims the field itself**: `col[1]` is scaled to 1/16 if bright, 1/4 if medium, 1/3 if dim. So `col: [primary, secondary]` can be sent as-is, and a white or gold secondary becomes a faint wash instead of a lit house.
- `pal: 5` ("* Colors Only") with an empty third slot builds 8 × primary + 8 × secondary with no blends. `pal: 3` ("* Colors 1&2") inserts a primary→secondary gradient, so red/gold twinkles through orange and blue/white through pale blue.
- It handles all four census classes without client colour surgery. Black-primary teams get secondary twinkles on a dark field. Near-identical pairs still twinkle.
- **Trap: `pal: 0` on fx 80 is Party Colors, a rainbow.** Both builders hard-code `'pal': 0`. Swapping the ID to 80 without changing the palette would **reintroduce this exact bug** through a different effect.
- Caveat: with the "Cool" checkbox off (the default, `o1`), fading twinkles are tinted toward red, incandescent-style. That is invisible on red/gold and possibly visible on blue/green teams. Bench both settings.

---

## Step 4 — Proposed fix (not implemented)

### Recommendation

Replace `fx 63` at **both** sites with **`fx 80` Twinklefox, `pal: 5`, `col: [primary, secondary, black]`**, starting from `sx ≈ 128`, `ix ≈ 160–200`. The exact `sx` / `ix` / `o1` values are to be picked on the bench.

Reasons, in order of weight:

1. It is the only candidate that renders the *intent* (independent sparkle, both team colours) rather than only fixing the ID.
2. It degrades gracefully across all 449 teams with no per-team colour logic. `fx 17` needs special handling for 125 of them (94 + 18 + 13).
3. The firmware owns the field dimming. That matches the project's standing rule of letting WLED own correction rather than re-deriving it in the client.

If the bench says Twinklefox reads wrong on the house, the fallback is **`fx 17` with explicit colour roles**, not a bare swap:

- sparkle = primary (or secondary when primary is ≈ black);
- field = 30 % of secondary (black stays black); for near-identical pairs, field = 30 % of the sparkle colour — reuse `kSparkleFieldDimFactor` / `readableSparkleColors` rather than forking the constants;
- `pal: 0` explicit, `sx ≥ 200`, `ix ≈ 128`;
- accept that the look is "fill, then wipe every ~19 s".

**Do not ship candidate A** (the bare `63 → 17` swap with the existing `sx150 / ix200 / col[p,s]`). It trades a rainbow for a white house on 94 teams.

### Server side

**No server change is needed for fx 63.** Step 2 found no stored 63 and no server-side source of one.

Two adjacent server facts to keep in view when the client fix lands. Neither blocks it.

- `buildParticipatingSegArray` and `buildFullPartitionSegArray` send **no `pal`** (and no `grp` / `spc`). That is harmless for the `effect_id: 52` default. If a palette-driven effect is ever stored as a bare `effect_id` (not as a saved payload), the server will inherit whatever palette the segment last held. That is the same class as the celebration bug. This fix does not create that case, because it stores nothing. It is worth a guard before anything else does.
- The server ignores `design_variety` and preferred styles entirely. "Rotating" and style auto-select are client-only behaviours.

### What a fix PR needs beyond the two literals

- **Both builders need a palette parameter.** `TeamDesignCatalog._buildPayload` and `GameDayAutopilotService._buildWledPayload` hard-code `'pal': 0`. That is correct for the other five designs and wrong for any palette-driven replacement.
- **Add a guard test. No test protects this path today.** Nothing pins `fx 63` on the base-design path, which is how it survived. Mirror the celebration guard on `fix/gameday-celebration-team-colors` (that test is not on this tip). For every catalog design and every `_StyleCategory` arm: the ID must be the effect its label names (expected-*name* table against `WledEffectsCatalog`), it must not be `generatesOwnColors`, and a palette-driven effect must not carry `pal: 0`. The other five catalog IDs were checked against `FX.h` v0.15.1 for this audit and are correct (0 Solid, 2 Breathe, 28 Chase, 52 Running Dual). `game_day_saved_design_firestore_test.dart:51` already writes `'fx': 17, // Twinkle`, so the right ID is already known elsewhere in the same directory.
- **Bench protocol for the owed comparison.** Use a synthetic `/json/state` POST only: no `psave`, no `/json/cfg`, no `i` arrays (frozen-segment hazard). Snapshot state and raw-byte-hash `presets.json` before and after. Capture a WebSocket `{"lv":true}` frame **series**, not a snapshot. Drive at least Chiefs (red/gold), one white-secondary team, one black-primary team and one near-identical pair, for fx 80 (`o1` on and off) and fx 17 candidate C. Run with the founder's app closed and outside any game window.

### Related defects found on the way (not part of this fix; listed so they are not lost)

1. **The schedule label never matches the fire.** Every Game Day calendar entry fires as Solid regardless of the catalog design named on it (paths #6 → #4). "Rotating variety" is visible only as text.
2. **Four paths give four different answers for one default config.** Foreground autopilot → Solid (default styles categorise as *static*). Server → Running Dual (`effect_id` 52). Light Up Now → Running Dual. Calendar lease → Solid. Which look a customer sees depends on which path wins the race.
3. **More name tables mislabel fx 63.** `'Candle'` in `lumina_brain.dart:919` and `lumina_smart_scheduler.dart:152,608`; `'Palette'` in `pattern_theme_selection.dart:655`. Same class (label/ID drift). Not traced to a sender in this audit.
4. **`EffectSpeedProfile(effectId: 63, … label: 'Wave speed')`** (`effect_speed_profiles.dart:373`) is consistent with Pride 2015, so that table is right. It is further evidence that the catalog comment was simply wrong.

---

## Verification log

| Claim | How it was checked |
|---|---|
| Branch tip | `git fetch origin` → `origin/release/store-submission-consolidated` = `73ae375c0ecb…` |
| Worktree isolation | New worktree in the session scratchpad on a new local branch; upstream unset; `main`, the shared checkout and all other worktrees untouched |
| fx IDs and effect behaviour | WLED `v0.15.1` `FX.h`, `FX.cpp` (`mode_twinkle`, `mode_pride_2015`, `twinklefox_base`), `FX_fcn.cpp` (`fade_out`, `color_from_palette`, palette cases 0–5) |
| Armed scope and persistence | Firestore read-only: `config/gameday_planner`, `config/calendar_leases`, `collectionGroup('game_day_autopilot')`, `/users` (51), founder's `fire_jobs` (21) |
| No persisting code path | `grep` across `lib/`, `functions/src/`, `scripts/`; `git log --all -S` pickaxe |
| Bench | **Not run** — LAN unreachable; zero writes to any device |
| Tests / analyze | Not run; no source file was modified |
