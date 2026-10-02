# Design card — Static setup and grouping controls (audit + fix)

**Filed:** 2026-10-02 · **Branch:** `fix/115-multichannel-and-design-card` off release head `a35e30e`
(build 112) · **Evidence:** verified-by-source + widget tests · **Debt:** #152 (fixed here), #153

## Report

Opening a design card (Explore Patterns → a palette → the tuner, `ColorwayEffectSelectorPage`) shows
the Static setup with **Blocks** or **Alternating**, and the grouping numbers ("LEDs per color").

- **(a)** Under **Blocks** the grouping control was still shown. Blocks ignores it.
- **(b)** Previewing an effect such as Chase or Glitter made the Blocks/Alternating selector and
  the grouping numbers disappear, and the only way to get them back was to close the card and
  reopen it.

## Findings

### F1 — the card's visibility was derived from the SELECTED effect, not from the palette

[lib/features/wled/colorway_effect_selector.dart:1397-1400](../lib/features/wled/colorway_effect_selector.dart#L1397)
(at `a35e30e`):

```dart
final showColorLayout = !_isBrightnessGradient &&
    ((effect?.usesColorLayout ?? false) || (effectId == 0 && hasMultipleColors));
```

and inside the card, the chips at
[colorway_effect_selector.dart:2350](../lib/features/wled/colorway_effect_selector.dart#L2350):

```dart
if (_solidFieldsFor(ref.watch(selectorEffectIdProvider)) != null) ...[   // chips
```

Both read `selectorEffectIdProvider`, which every effect tile tap sets
([:2236](../lib/features/wled/colorway_effect_selector.dart#L2236)). So:

| Previewed effect | `usesColorLayout` | What happened |
|---|---|---|
| Chase (28), Breathe (2), Meteor (76), most tiles | false | the whole card vanished (chips **and** numbers) |
| Glitter (87), Twinkle (17), Spots (85), Gradient (46) | true | the card stayed but the **chips** vanished; only the numbers remained |

This is not controller state: the visibility never read `wledStateProvider`. It is the card's own
*effect* selection, which a preview changes by design. The layout and grouping **values**
(`selectorSolidLayoutProvider`, `selectorColorGroupProvider`) were never touched by a preview, so
the state was intact; only the controls that show it were gone.

### F2 — why "close and reopen" was the only way back

Returning to Static means tapping the **Solid** tile. The tile list is
`topPicks` or, with a motion/colour filter active, `filterEffects(...)`
([:1411-1420](../lib/features/wled/colorway_effect_selector.dart#L1411)). Solid is in the "Basic"
category (`MotionType.solid`), so once the user has tapped the **Chase** (or any other) motion filter
chip to find a chase effect, **the Solid tile is no longer listed**. With the chips gone too, nothing
on the card leads back to Static. Reopening the card re-seeds effect 0 and the chips return
([:453-472](../lib/features/wled/colorway_effect_selector.dart#L453)).

### F3 — the grouping row was unconditional inside the card

[colorway_effect_selector.dart:2380-2420](../lib/features/wled/colorway_effect_selector.dart#L2380):
the "LEDs per color" row rendered whenever the card did, with no layout check. Under Blocks the wire
is `fx 83 + pal 5` and the firmware lays the palette out **positionally** (`color_from_palette(i,
mapping: true)` → `paletteIndex = i·255 / (virtualLength−1)`), so `grp` changes nothing a customer
would call the layout: thirds stay thirds (`grp` only coarsens the boundary to `grp`-pixel steps and
lengthens the lit band, `1 + sx` *virtual* pixels — see the 09-22 note on >129-px segments). The
control was meaningless there, as reported.

### F4 — related tracker items, and whether they share the cause

- **Solid-mode design card: switching to Blocks does not divide the preview** (the 2026-09-22
  audit, `audit/DESIGN_CARD_BLOCKS_LAYOUT_AUDIT_2026-09-22.md`, fixed and merged at `31875ab`,
  memory `project_hero_preview_ignores_solid_layout`). That was the **painter** (hero drew every solid
  look as alternating) and the **model** (`ChannelDesign.solidLayout` did not exist). Different cause;
  it is what made the chip exist in the first place. Its hero rule (`RooflineLightPainter.solidLedColor`
  reads `paletteId`) is untouched here and is what the "live preview matches the control" tests assert
  through `AnimatedRooflineOverlay.previewEffectId / previewPaletteId / colorGroupSize`.
- **#77 / #67** (multi-channel) — unrelated to this card.
- The firmware fact from the 09-22 bench (`fx 83` Blocks at `sx = ix = 128` shows thirds over
  virtual 0–128 and `col[1]` beyond, on a segment longer than 129 LEDs) is **not** fixed here and is
  re-filed as **#153** with the option space; it is a wire-shape decision, not a UI one.

## Fix (this branch)

**One rule, pure Dart, unit-tested:** `staticSetupControls(...)` in
[lib/features/wled/solid_palette_blocks.dart](../lib/features/wled/solid_palette_blocks.dart)
returns a `StaticSetupControls` (`showCard`, `showChips`, `chipsActive`, `showGrouping`,
`groupingReturnsToStatic`, `showSpacingAndPreview`). The card reads it; nothing in the card decides
visibility on its own any more.

- **The Static setup belongs to the palette.** Chips are shown whenever picking Static *would* be
  substituted for this palette (`isSolidPaletteSubstitution(effectId: 0, …)`), whatever effect is
  being previewed. Section label is now **"Static setup"** (was "Layout").
- **Blocks hides grouping; Alternating shows it.** Under Static the row shows only for Alternating.
- **Previewing an effect never removes them.** While another effect plays, the chips stay,
  *unselected*, with a one-line hint (`kStaticSetupReturnHint`: "Applies to Static. Tap Blocks or
  Alternating to switch back."). If Alternating is remembered the grouping row stays too (it is
  Static setup). Tapping a chip, or a grouping number in that state, selects Static in that layout
  through the same `_selectEffect(0)` a tile tap uses — so the way back exists even when a motion
  filter has hidden the Solid tile (F2).
- **Colour-layout effects keep their row.** For Glitter/Twinkle/Spots/… the "LEDs per color" row
  still drives that effect's band width (`grp`), and a tap keeps the effect.
- **Spacing and the dot row describe the selected effect**, so they step aside while a non-layout
  effect (Chase) is previewed over the chips — they were never shown for Chase before either.
- **Returning to Static restores the previous selections** because a preview never writes
  `selectorSolidLayoutProvider` / `selectorColorGroupProvider`; the decider is a pure function of them.
- The wire is unchanged: Blocks still sends `fx 83 pal 5` with the provider's `grp` (byte-identical
  to the 09-22 behaviour for a fresh card, `grp 1`); Alternating still sends `fx 84 ix 0 grp N`
  (3 colours) or `fx 83 pal 0 sx 0 ix 0 grp N` (2 colours). Saved designs and `_saveToDesign` are
  untouched (it still writes the layout only while Static is selected).

Widget keys for tests: `static-setup-blocks`, `static-setup-alternating`, `static-setup-hint`,
`leds-per-color-N`.

## Tests

- `test/features/wled/static_setup_controls_test.dart` — the pure decider for every state:
  Static+Blocks, Static+Alternating (2 and 3 colours), Chase with each layout remembered, Glitter,
  every top pick, return-to-Static invariance, one-colour, architectural, brightness-gradient.
- `test/features/wled/design_card_static_setup_test.dart` — the real card: Blocks hides the row;
  Alternating shows it and each value 1–5 goes out as `grp` on `fx 84 ix 0` with the hero following;
  two-colour Alternating; Alternating@4 → Blocks → Alternating keeps 4; Chase keeps the chips
  (unselected, hint) and tapping Blocks returns to Static; Chase over a remembered Alternating@3 keeps
  the row and a number returns to Static; Glitter keeps the row for Glitter; Solid tile after Glitter
  restores Alternating@3; Meteor then the Alternating chip; a motion filter that hides the Solid tile;
  design-edit seeding (Solid/Alternating@2, Solid/Blocks, Chase/Alternating@3); and the
  accessibility matrix (1.0 / 1.75 / 2.0 with Bold Text) for four states of the card.

## Device walk (bug 2)

View-only on any controller; the tuner previews live, so use **`.173`** (spare, unregistered) or
the test account. Nothing here saves a preset. Steps: open Explore → a three-colour palette → confirm
"Static setup" shows Blocks selected and **no** "LEDs per color" row → tap Alternating → row appears,
pick 3 → roofline shows 3-LED bands → tap Glitter → chips stay (grey) with the hint, row stays →
tap a number: Glitter band width changes, Glitter keeps playing → tap Solid → Alternating selected,
row shows 3, bands return → tap the Chase filter chip, pick Chase → chips + row stay, Solid tile gone →
tap Blocks → thirds return, row gone.
