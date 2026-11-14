# Build 129 candidate — brightness patterns that work, per-pixel brightness in Design Studio

Branch `feat/129-brightness-patterns`, from `feat/126-candidate` at `bd29c38`. No tag, no deploy, no
merge, version unchanged (2.5.10+126 — the integration step bumps it). Bench and decision:
[docs/bench/brightness_patterns_129_bench_2026-11-14.md](../bench/brightness_patterns_129_bench_2026-11-14.md).

## What was wrong (confirmed against source at bd29c38)

- Explore › Architectural Downlighting › each Kelvin style › **Brightness Gradients** (shipped in
  `9c48001`, 2026-03-17) sent fx 83 Solid Pattern with `sx 0`; the chokepoint filled `ix 128` and
  `pal 5`, so the controller showed one lit pixel and then 129 pixels of the second step — a
  uniform dim run, while the card's dot preview drew a per-bulb cycle. Step values scaled the colour
  value, not the light: "Deep 100/60/30" lit at 100/24/3.4 % under the controller's gamma 2.8. Soft
  Pulse had four steps for three colour slots. Saving a card dropped its metadata.
- fx 65 Palette rendered one still colour because `completeEffectSegment` stated `c1 128` (the
  segment's born-with value); the effect's own default is `c1 0` and 128 turns its gradient 90°.
- Design Studio's pixel was an RGBW list with no brightness.

## Bench (2026-11-14, spare 0.15.4 and home 0.15.1, state writes only, both restored)

Size (`ix`) maps to the cycle exactly (`N ≈ 16.06·(len−1)/(ix−112)`), so a 6-pixel cycle needs
`ix > 255` on every bus of both controllers; an 18-pixel cycle is within 3 pp only with slot 0 at
95–96 % light, only on 100/128-LED buses, and only with a per-bus Size (the app sends one `ix` to
every bus). **Decision per the brief's rule: per-pixel data.**

## What this build does

1. **Brightness patterns are per-pixel tiles** (`lib/features/wled/brightness_tile.dart`): a
   repeating sequence of light levels, gamma-compensated (a "40 %" pixel is sent at 184 so it
   lights at 40 %), painted through the Design Studio spine (solid base + `i` chunks) to every
   channel. The six shipped presets now render as their cards always previewed. Two new presets:
   **Wave · 6 lights** (100/80/60/40/60/80 — T1) and **Wave · 18 lights** (T2).
2. **Where they live.** A new Explore root **Brightness Patterns (White)** holds all eight in warm
   white (3000K), one tap from Explore. Each Kelvin folder keeps its six-card folder (renamed
   "Brightness Patterns"; its node count is pinned by `library_tree_coherence_test`, so the Wave
   cards are not added there). No Breathing variant: a per-pixel frame freezes the segment.
3. **Adjustable (T3).** Every brightness card shows an **Adjust** link (and the post-apply snackbar
   action) opening the adjustment sheet with `BrightnessTileControls`: presets, shape (Wave / Ramp /
   Steps / Custom), brightest, dimmest, lights per cycle, lights per step, start offset, a custom
   tile (tap a light to step its level, hold to type), and the white (every Kelvin step). The sheet
   says the pattern is sent light by light and that scheduling a saved one follows the
   painted-design rules.
4. **Saving / scheduling.** The pattern tuner (reached from the schedule and Game Day pickers)
   refuses to hand a brightness pattern back, with the per-pixel wording every picker uses, and
   offers **Save to My Designs** in apply mode: the pattern becomes a painted `CustomDesign`
   (`perPixel: true`, stamped), so My Designs, Favorites and the schedule picker treat it as any
   painted design — scheduling is gated to 0.15.4 + esp32, ≤ 1,700 elements, ≤ 4 per account, as
   before.
5. **fx 65 gets `c1 0`** (`kWledEffectOptionDefaults`); every other effect keeps its fill — the
   table test over the whole pool (`brightness_patterns_129_test.dart`) pins it.
6. **Per-pixel brightness in Design Studio.** `LedColorGroup.bri` (0–255, absent = full, omitted
   when full — old designs read unchanged, an older build ignores it); a brightness layer in
   `PixelDesignDocument` kept apart from colour (`litColorAt` is what the lights and the preview
   get; runs split on brightness too); `positionalSpans()` sends the lit colour, so apply, the
   scheduled API body and favourites honour it. Editor: a **Pixel brightness** slider with **Dim
   to N %** / **Full** for the selection and a **Ramp…** dialog (start, end, mirror) across the
   selection in LED order. Undo/redo cover it.

## Looks whose appearance changes with `c1 0` on fx 65

The team pool (`kTeamSuggestedEffects`) is `[37, 28, 0]` at bd29c38 — it has had no fx 65 entry
since build 124. fx 65 still reaches the wire from:

| Where | Before (c1 128) | After (c1 0) |
|---|---|---|
| `autopilot_schedule_generator.dart:273` — Game Day autopilot event, `effectId: 65` (commented "Breathe") with the team colour under the derived `pal 4` | one still team colour per run | a still bright→dim→bright gradient of the team colour along each run |
| `sports_alert_service.dart:251` — pre-game "colorloop", `fx 65`, `pal 0` | one still hue of the rainbow wheel | the whole hue wheel laid along each run |
| `lumina_smart_scheduler.dart:150` — the AI rotation offers 65 | one still colour | palette gradient along the run |
| `neighborhood/widgets/sync_event_setup_screen.dart:860` — the sync effect picker offers "Palette" | one still colour | palette gradient along the run |
| Customer favourites / designs / schedules that store `fx 65` | one still colour | gradient along the run |

The stored customer payloads cannot be counted from the app (no Firestore read in this build).

## Not in this build (follow-ups)

- **Recent Patterns** rebuilds a card from effect id + colours (`GradientPattern` carries no
  payload), so a brightness tile would re-apply as a plain solid; tile applies are therefore not
  logged as usage events. Carrying the tile through the usage model is a follow-up.
- The hero house preview in the tuner shows the tile's base white as a solid; the dot preview and
  the controls row show the tile.
- The palette path (fx 65, per-bus Size, slot 0 at 92.5–96 %) is documented in the bench as a later
  option for cycles ≥ ~16·(len−1)/143 pixels; nothing in the app uses it.
- `Breathing` is gone from the brightness folders (see 2).

## Tests

- `test/helpers/wled_strip_simulator.dart` — a model of what the controller renders (fx 0/2/65/83/
  84, pal 0/2–5, per-pixel `i`, gamma 2.8), anchored to the bench frames.
- `test/features/wled/brightness_patterns_129_test.dart` — written first, 5 pass / 13 fail at
  bd29c38 (`scratchpad bench-129/step2_failing_at_bd29c38.log`); all pass after the fix.
- `test/features/design/pixel_brightness_129_test.dart` — the brightness layer, JSON compatibility,
  lit spans, frame, ramp.
- `test/helpers/recording_wled_repository.dart` now implements `PerPixelWriter` (records every
  chunk in `applied`), so a test can render everything the app wrote onto a simulated strip.
