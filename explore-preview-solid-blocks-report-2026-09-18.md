# Explore Patterns preview ≠ device: Solid + multi-colour palette

**Date:** 2026-09-18 · **Branch:** `fix/explore-preview-solid-blocks` off `origin/main` @ `699a498` · **Not pushed.**

## What the audit found (Step 1)

The brief's device claim is correct, and the audit pinned *why* — against the pinned firmware
source, not the preview code. It also found the brief's *location* claim is only half right,
which changed what got fixed.

### The device side — traced through WLED v0.15.1 source (the fleet's pinned firmware)

Fetched `wled00/FX.cpp` and `wled00/FX_fcn.cpp` at tag `v0.15.1` and read the actual functions:

| Fact | Where | What it says |
|---|---|---|
| Solid (fx 0) shows one colour | `color_from_palette`, FX_fcn.cpp:1173 | `palette == 0` → returns `SEGCOLOR(mcol)`; fx 0 is `col[0]` only |
| So every app path substitutes **fx 83** for Solid + a multi-colour palette, with **`pal:5`** | `_effectiveEffectId` (colorway_effect_selector.dart:582), `WledEffectsCatalog.paletteForEffect(83) == 5`, `_preparePayload` (pattern_grid_widgets.dart:1510-1526), `design_models.dart:262` | 0 → 83 when colours > 1 |
| **`pal:5` is built from the colour slots IN ORDER, as blocks** | `loadPalette` case 5, FX_fcn.cpp:229-238 | 3 colours: `[c0×5, c1×5, c2×5, c0×1]` · 2 colours: `[c0×8, c1×8]` |
| **fx 83 maps that palette by pixel POSITION along the segment** | `mode_static_pattern`, FX.cpp:2849-2865 → `color_from_palette(i, mapping: true, …)`, FX_fcn.cpp:1176 | `paletteIndex = (i*255)/(virtualLength()-1)` |
| The wrap entry is cut off at the default blend mode | FX_fcn.cpp:1178 | `scale8(idx, 240)` → three colours land at exact thirds, not 5/5/6 |

**Result: fx 83 + pal 5 divides the segment into N contiguous blocks, one per colour, in `col[]` order** — thirds for three colours, halves for two. This is exactly what the bench captured on 2026-06-01 (`fx:83 pal:5 grp:1`, 128-LED segment, red/green/white thirds with blended boundaries, `memory/project_blocks_boundary_blend_fix`). "Thirds" is not a `grp` effect (grp was 1) and not an fx-band effect — it is the palette's positional mapping. **N generalises by construction: it is the number of colours, capped at WLED's three slots (`take(3)` everywhere).** Four-colour palettes cannot reach the device.

### The app side — where the alternating preview actually lives

The "Any Color" / "All" chips named in the brief exist on exactly one screen: **`ColorwayEffectSelectorPage`** (`colorway_effect_selector.dart:1540, 1568`) — the Explore flow of *palette → effect list*. That page had **two** previews for the Solid + palette case, both wrong in different directions:

1. **`_buildColorLayoutPreview`** (the 18-dot "LEDs per color" row, `:1808`) — `colorIndex = (i ~/ colorGroup) % colors.length` → **r, w, b, r, w, b …** per dot. This is the bulb-by-bulb alternation in the report.
2. **The effect tile's mini preview** (`:1688`) — passed the *catalog* id `0` to `EffectPreviewWidget`, whose `solid` branch painted **one flat colour** (`col[0]`), while tapping that tile sends fx 83 + pal 5 → blocks.

### What the brief got wrong, and why it matters

The Explore *grid* card (`PatternCard`, `pattern_grid_widgets.dart`) was **not** the mismatch. Its apply path sends **fx 84 "Solid Pattern Tri"** for three colours (`:1519-1522`), and fx 84 (`mode_tri_static_pattern`, FX.cpp:2870-2890) reads `SEGCOLOR(0..2)` directly in repeating bands of `(ix>>5)+1` LEDs — no palette, no positional mapping. With the card's default `_ledsPerColor = 1` the **device genuinely alternates per bulb** on that path, and the card's `_GradientDotPreview` already mirrors that (its own comment says so). **Changing that preview to thirds would have created a mismatch where none exists.** It was left alone, and a test pins that nothing outside fx 83 changed.

## The fix (Step 2) — one shared rule, two surfaces

**New:** `lib/features/wled/solid_palette_blocks.dart` — pure Dart, no Flutter:
- `isSolidPaletteSubstitution({effectId, colorCount, isArchitectural})` — the decision.
- `effectiveSolidEffectId(...)` — 83 or the id as-is.
- `solidPaletteBlockIndex(index, pixelCount, colorCount)` — the partition: `(i·N) ~/ count`, N clamped to 3. Equivalent to the firmware's positional lookup with the wrap entry cut off.

**Changed:** `lib/features/wled/colorway_effect_selector.dart` (+36/−5)
- `_effectiveEffectId` now delegates to `effectiveSolidEffectId` — **the apply path and the previews share one decision, so they cannot drift again.** Behaviour-preserving (test pins the architectural exclusion and the 1-colour case).
- The effect tile previews `_effectiveEffectId(effect.id)` instead of the raw catalog id.
- `_buildColorLayoutPreview` renders `solidPaletteBlockIndex` blocks when the substitution applies; every other effect keeps its real `grp`-band rendering (that banding *is* real WLED grouping for effects that keep their fx). `spc` gaps are preserved inside blocks.

**Changed:** `lib/features/wled/effect_preview_widget.dart` (+45/−0)
- `solid` branch: `effectId == 83 && colors.length >= 2` → new `_SolidBlocksPreview` (a `Row` of `Expanded` blocks in slot order, each block tied to the shared partition by sampling its midpoint). Plain fx 0 still previews as one flat colour — **which is what fx 0 renders**. fx 84/85/98 untouched.
- Call-site check: `EffectPreviewWidget` has two consumers. The Explore grid never routes fx 0 with ≥2 colours here (intercepted by `usePreparedBandPreview`, `:1571`), and no grid `PatternItem` reaches it with fx 83 (the only fx-83 catalog item is a `_gradientMeta` item, which takes the `_GradientDotPreview` branch). The colorway tile is the only path that lands in the new branch.

## Confirmation it matches the device, not just "looks like thirds"

- **Order:** col[0] → col[1] → col[2], from `loadPalette` case 5's slot order and the bench's "white→red wrap" (the last block is white = col[2], wrapping to red = col[0]).
- **Partition:** equal contiguous blocks, from `paletteIndex = (i·255)/(len−1)` + `scale8(…,240)` over 15 visible entries (5/5/5). Test: a 290-LED channel splits at 96/97 and 193/194.
- **Two colours → halves** (`[c0×8, c1×8]`), tested. **One colour → no substitution**, tested.
- Two second-order terms the preview does not model, deliberately, documented in the helper's header: `LINEARBLEND` smears ~1/15 of the strip at each internal boundary; and fx 83's lit/unlit banding (`lit = 1+sx`, `unlit = 1+ix` of `col[1]`) — with the tuner's defaults (sx = ix = 128) any segment ≤129 LEDs is entirely lit and the blocks are exactly equal, while a longer segment grows the middle block. Still contiguous, still in order, never alternating. Not hardware-verified on a >129-LED segment (no device on the bench); flagged, not guessed.

## Rainbow scoping bug (Step 3) — not touched, not worsened

`git diff -U0 | grep -i 'rainbow\|pal\|paletteForEffect\|normalizeWledPayload\|_preparePayload\|getPreviewType\|overridesUserColors'` returns **nothing**. The change adds a branch inside `EffectPreviewWidget`'s `solid` case and a helper file; the `rainbow` case, `_RainbowPainter`, `getPreviewType`, the effect catalog, and every `pal` decision (`paletteForEffect`, the `pal:5→4` rewrite in `normalizeWledPayload`, `_preparePayload`'s forced `pal:5`) are byte-identical. The two issues share `EffectPreviewWidget` as a file but not a code path, so this did not require expanding scope. The existing `preview_effect_category_unification_test.dart` (which pins id 9 "Rainbow" → rainbow preview) still passes.

## Verification (Step 4)

- **New tests** — `test/features/wled/solid_palette_blocks_test.dart`, **16/16**: thirds, halves, single colour, monotonic-never-alternates across 3/18/100/290 px, the 290-LED split points, the old `i % N` formula explicitly rejected, the midpoint property the painter relies on, slot clamping; the shared decision (substituted / 1-colour / architectural / chase untouched); and **widget tests** that fx 83 + 3 colours lays out three ordered 30-px blocks in a 90-px tile, fx 83 + 2 colours lays out 45-px halves, fx 0 still paints one flat `col[0]`, and a chase (fx 28) builds no flat blocks at all.
- One of those tests **caught a real bug in my first cut** (block k sampled at `k/N` truncates into slot k−1 at k=2, N=3); fixed by sampling midpoints, and the property is now pinned.
- **Existing suites that import the changed files** — `preview_effect_category_unification_test.dart` and `design_edit_tuner_test.dart`: pass unchanged.
- `flutter analyze` on the four touched files: **No issues found.**
- Repo-wide `flutter analyze`: **385 issues, 0 errors**, none in the four touched files (the same pre-existing infos/warnings as `origin/main`; the direct 4-file analyze reports "No issues found").
- Full `flutter test`: **2996 passed, 0 failed**, 4 skipped (the `skip: !kRunHw` bench-rig cases in `test/hardware/`), exit 0.
- A "genuinely alternating" effect still alternates: the block branch is gated on fx 83 only; `_GradientDotPreview` (fx 84 bands), the chase/theater/running painters, and the dot row's `grp`-band rendering for non-substituted effects are unchanged and covered by the chase assertions above.

## Left open, on purpose

- **Explore grid, Solid + exactly two colours** (`_preparePayload` → fx 83 with `sx = ix = ledsPerColor−1`, default 0): the firmware then interleaves 1 lit (positional) + 1 unlit (`col[1]`) pixel, so the device shows `c0,c1,c0,c1…` over the first half and solid `c1` over the second. The card previews alternation throughout. Same root cause, different shape; it needs a bench look before a preview is written for it.
- **Brightness-gradient presets** on the same tuner (`_buildGradientDotPreview`, fx 83 + pal 5 with the gradient steps as `col[]`) are the same positional-blocks class and still preview as repeating bands. Product-facing ("band width" is offered as a control that does not do what it says), so not silently changed.
- The report says this was "tracked as open technical debt" — no entry was found in `docs/BUGS_AND_DEBT.md` under any of the wordings tried (preview/alternat/bulb/thirds/83/84/Solid Pattern). Nothing was added there; that is a tracker hygiene call for Tyler.
