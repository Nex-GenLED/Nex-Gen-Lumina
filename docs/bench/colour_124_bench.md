# Build 124 colour bench — the list for Tyler (written, not run)

Run on the **spare controller only** (the bench rig's spare, WLED 0.15.4; never the home controller), with the
same rules as the colour bench of 2026-11-10:

- First read `/json/info`: it must say 0.15.4, vid 2508020 and arch esp32.
- Before the first write, snapshot `/json/state`, `/cfg.json` and `/presets.json`.
- Use state writes only (`POST /json/state`): no preset saves, timers, cfg writes or power cycles.
- Stop on the first anomaly instead of retrying.
- Restore at the end, then check the three hashes.

The spare's three runs are IO2 = LEDs 0–99, IO14 = 100–199 and IO16 = 200–299. Every step gives the payload
first, then what to look at and what to expect. "Lights at" is the colour after the controller's gamma 2.8, the
number the live view reports.

The old preview tool `bench/bin/team_led_preview.dart` still has the address of the retired spare built in
(`kSpareControllerIp` in `bench/src/team_led_preview_core.dart`). Do not use it against the spare until that
address is changed. The payloads below can be sent with any
state-write tool that follows the rules above.

Unless a step says otherwise, every segment states its whole look: `on:true`, `pal:0`, `grp:1`, `spc:0`,
`bri:255`, `frz:false`, `o1/o2/o3:false`, three colour slots, and master `{"on":true,"tt":0}`.

## 1. Chiefs red at full brightness (master `bri` 255)

Build 124 sends Chiefs red as 255,0,34. On 2026-11-10 it was judged only at brightness 128. At 128 the
controller halves every channel before the LEDs, so its trace of blue (lights at 1) probably arrives as 0. At
255 that 1 is sent as-is, and a trace of blue is what made today's red look pink.

- Payload: master `bri` 255.
  - IO2: solid `[255,0,34,0]` (lights at 255,0,1).
  - IO14: solid `[255,0,0,0]`.
  - IO16: solid `[227,24,55,0]` (today's brand red, lights at 184,0,3, the pink one).
- Look at IO2 against IO14, close up and from across the room.
- **Expected:** IO2 and IO14 look the same red, and IO16 is pinker and dimmer.
  - If IO2 shows any pink next to IO14, change Chiefs red in `lib/data/team_led_colors.dart` to 255,0,0.
  - Then regenerate the mirror (`dart run scripts/gen_team_led_mirror.dart`).
  - Then check the other reds in the table that carry a small blue (`docs/bench/team_led_colors_124_before_after.md`, section 5).

## 2. Representative teams from the before/after list

For each pair: IO2 = the brand value (what controllers got before the table), IO14 = the build-124 LED value,
IO16 = the team's other colour as LED, so the pair is seen together. Master `bri` 128, solids. Expected for every
pair: IO14 reads as the colour a fan would name, and IO2 reads off-colour (too dark, washed out, or the wrong
hue). Note any IO14 that looks wrong.

| # | Team colour | IO2 brand | IO14 LED (build 124) | IO16 partner (LED) | What to judge |
|---|---|---|---|---|---|
| 2a | Vikings purple | 79,38,131 | 163,0,255 | Vikings gold FFC62F → 255,180,0 | purple, not blue |
| 2b | Packers gold (gold-family, moved this build) | 255,182,18 | 255,167,0 | Packers green 203731 → 0,255,31 | gold, not whitish, not orange |
| 2c | Belgium yellow (gold-class yellow, **held unchanged**) | 253,218,36 | 255,218,25 | Belgium red → its LED value | still yellow; or should it move like the golds? |
| 2d | Eagles midnight green | 0,76,84 | 0,255,85 | Eagles silver → its LED value | green, not teal |
| 2e | Browns brown | 49,29,0 | 255,102,13 | Browns orange FF3C00 → 255,60,0 | LEDs cannot show brown; does amber read as Browns, and stay distinct from the orange? |
| 2f | Warm white (every team's FFFFFF slot) | 255,255,255 | 255,240,215 | — | warm white; compare with the 3500 K white of 2026-11-10 |
| 2g | Powder blue (Carolina blue 7BAFD4) | 123,175,212 | 77,181,255 | — | sky/powder blue, not cyan, not white |

Partner values not given above (Belgium red, Eagles silver) are in the before/after list. Vikings gold
255,180,0 is a gold-family entry this build moved (8ee30c8 had 255,194,33).

## 3. The Game Day default looks on the Chiefs pair

- **3a, moving.** IO14: fx 37 Chase 2, `sx` 60, `ix` 128, col `[255,0,34,0],[255,168,0,0],[0,0,0,0]`. IO2 for
  comparison: fx 52 Running Dual, `sx` 160, `ix` 128, same colours. IO16: off.
  - Expected: IO14 shows 9-LED red and gold stripes marching about 4 LEDs a second, half pure red and half gold,
    with no blended LEDs. IO2 reads orange, with little red. This is the 2026-11-10 step 7a.
- **3b, still.** IO14: fx 83 Solid Pattern, `sx` 8, `ix` 8, same colours. IO2 the same reference.
  - Expected: still 9 red / 9 gold stripes (step 7b). This is also the new catalog design 6 "Stripe", which used
    to render the primary alone.

## 4. Chase 2 after a stale white third slot

- First, leave IO14 with a white third slot: solid col `[255,0,34,0],[255,168,0,0],[255,255,255,0]`.
- Then send what Light Up Now puts on the wire for the new default, two colour slots padded by the chokepoint:
  fx 37 `sx` 60 `ix` 128 `pal` 0 col `[255,0,34,0],[255,168,0,0],[0,0,0,0]`, segment `bri` 255.
- Then, as a control, send the same payload with only two colour slots, so the white third slot is kept.
- **Expected:** no white anywhere in either case. Chase 2 never reads the third slot, so the stale white cannot
  show. The padding to black matters for Chase (fx 28) and Glitter. Confirm on the readback that the first send
  set `col[2]` to `[0,0,0,0]`.

## 5. Light Up Now at the new default (phone on the home Wi-Fi)

- In the app, add a team that has no saved design (a new team doc stores `effect_id` 37, `speed` 60,
  `intensity` 128). Press Light Up Now.
- Read `/json/state` on the spare.
- **Expected:** every participating segment reads fx 37, `sx` 60, `ix` 128, `pal` 0, col = the team's LED primary,
  LED secondary and `[0,0,0,0]`, segment `bri` 255, master `bri` = the team's brightness (200 by default). On the
  strip: the step-3a look in the team's colours.

## 6. Twinkle, corrected

- IO2: fx 17 Twinkle, `sx` 200, `ix` 128, col `[255,177,110,0],[77,53,33,0],[0,0,0,0]` (before).
- IO14: same with col `[255,177,110,0],[9,3,1,0],[0,0,0,0]` (build 124: the old 30 % background with the
  controller gamma applied).
- IO16: solid `[77,53,33,0]` (the reference for "what the 30 % was meant to look like", lights at 9,3,1).
- **Expected:** as on 2026-11-10 step 9. IO2's background glows pale warm white. IO14's background is nearly dark
  and matches IO16, with the twinkles standing out.

## 6b. Twinkle on the white chip (the rule extended; NOT benched before)

Build 124 applies the same rule to a sparkle colour that lives in the white channel. The old background
`[0,0,0,77]` becomes `[0,0,0,9]`. This was never shown on the bench, so check it now.

- IO2: fx 17, `sx` 200, `ix` 128, col `[0,0,0,255],[0,0,0,77],[0,0,0,0]` (before).
- IO14: same with col `[0,0,0,255],[0,0,0,9],[0,0,0,0]` (build 124).
- IO16: off.
- **Expected:** IO14's background is nearly dark and its twinkles read clearly. IO2's background is a steady
  white glow that hides them.
  - If IO14 looks too dark (the run reads as off between twinkles), say so: the white chip may need a different
    rule from RGB.

## 7. Glitter, corrected

- IO2: fx 87 Glitter, `sx` 40, `ix` 128, `pal` 5, col `[128,0,128,0],[255,140,0,0],[0,0,0,0]` (before: third
  slot black, so the sparkles are ultra-white).
- IO14: same with col `[128,0,128,0],[255,140,0,0],[255,140,0,0]` (build 124: third slot = the second colour,
  exactly the 2026-11-10 step-10 payload).
- IO16: off.
- **Expected:** as step 10. IO2 shows full-white flashes; IO14 sparkles orange.
  - Note IO14's background: the orange share rose from about 52 % to about 65 % on 2026-11-10. Say whether that
    is acceptable.

## 8. An existing team doc that stores fx 52 still behaves as before

- In the app, use a team whose `game_day_autopilot` doc was written before build 124 and stores `effect_id` 52,
  `speed` 160, `intensity` 128 (no saved design). Press Light Up Now.
- Read `/json/state`.
- **Expected:** fx 52, `sx` 160, `ix` 128, `pal` 0. Build 124 does not migrate stored docs; only the colours change
  (now LED values). A doc that stores no `effect_id` at all is the only kind that takes the new default.

## Restore

- POST the snapshot state.
- If the snapshot had a preset active (`ps` > 0), load exactly that preset with `{"ps":N}`.
- Verify the sha256 of `/json/state`, `/cfg.json` and `/presets.json` against the snapshot, and report any field
  that differs.
