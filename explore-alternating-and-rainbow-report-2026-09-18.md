# Explore Patterns: the Alternating layout, and the Rainbow leak

**Date:** 2026-09-18 · **Branch:** `feat/explore-alternating-rainbow` off `origin/main` @ `699a498` · **Not pushed, nothing merged.**

> **Base-branch note (flagged, reversible).** This branch is off `origin/main`, which does **not**
> contain the contiguous-blocks preview fix — that sits unmerged on `fix/explore-preview-solid-blocks`
> (`2f52893`). Part A has to sit *alongside* that option and reuse its helper, so rather than
> duplicate the helper and guarantee a merge conflict, that one commit was **cherry-picked with `-x`**
> as this branch's first commit (`fa851ca`). The source branch was not touched (still `2f52893`).
> If you merge `fix/explore-preview-solid-blocks` first, this branch rebases onto it cleanly; if you
> merge this branch first, the other becomes a no-op.

Every device-behaviour claim below was read from the WLED **v0.15.1** firmware source (the fleet's
pinned version: `wled00/FX.cpp`, `FX_fcn.cpp`, `FX.h` fetched at that tag), not inferred from app code.

---

## PART A — "Alternating" as a real, user-selectable layout

### A1. Where a user picks a colour-rendering style today, and whether "alternating" already existed

The only screen where a user chooses how palette colours are *laid out* is **`ColorwayEffectSelectorPage`**
(`colorway_effect_selector.dart`) — the palette → effect flow with the "All" / "Any Color" chips. Under
"LEDs per color" it shows a 1–5 band-width picker (`selectorColorGroupProvider` → WLED `grp`) and an
18-dot layout row. Choosing **Solid** with ≥2 colours is substituted to fx 83 + `pal:5`, which the
prior fix established renders **contiguous positional blocks** — so "Blocks" was the only Solid layout.

**Alternating did exist under another name, twice, and neither was usable as a layout choice:**

1. **The catalog effect "Solid Pattern Tri" (fx 84).** It is in `WledEffectsCatalog` (`usesColorLayout: true`)
   and appears in the selector's list under "My Colors" / "All". It *is* alternating — but its band width
   comes from the **Intensity slider** (`(ix >> 5) + 1` virtual pixels), not from "LEDs per color", its
   tile previewed as one flat colour, and nothing tells a user this is "alternating". Not a layout choice.
2. **The Explore grid card** (`PatternCard._preparePayload`) sends fx 84 for three colours as a side
   effect of which card you tapped — the behaviour the brief describes. **And it had two real bugs**
   (see A4).

No product copy exists for either layout: `docs/guides-2026-09/` has no term for it, the catalog says
"Solid Pattern" / "Solid Pattern Tri", and the AI composer's enum (`PatternType.alternating`,
`pattern_composer.dart:283`) plus `docs/lumina_design_pipeline_audit.md` ("alternating/block split")
both say *alternating*. **Labels chosen: "Blocks" and "Alternating".** Flagged as new copy — easy to rename.

### A2. The seam, and where the option lives in the UI

There *was* a clean seam, so nothing was restructured. The "LEDs per color" card (`_buildColorLayoutSelector`)
already appears exactly when the substitution applies; a **"Layout: Blocks | Alternating"** chip row now
sits at the top of that card, using the page's existing `_buildFilterChip`, shown only when
`isSolidPaletteSubstitution(...)` is true (Solid, ≥2 colours, non-architectural). State is a new
`selectorSolidLayoutProvider` (default **Blocks** = the pre-existing behaviour, so nothing changes until
a user taps). Tapping re-applies live via `_sendToWled()` like every other control on the page.

### A3. What "Alternating" sends, verified against the firmware — and the shared mapping logic

The fx 84 mapping was **not** reimplemented; it was extracted from the grid card into the shared pure
helper so both surfaces use one definition:

`lib/features/wled/solid_palette_blocks.dart` — `SolidLayout {blocks, alternating}`,
`solidLayoutFields(layout, colorCount, ledsPerColor)`, `alternatingBandIndex(i, ledsPerColor, N)`.

| Colours | Wire form | Firmware behaviour (v0.15.1) |
|---|---|---|
| 3 | **fx 84**, `ix:0`, `grp = ledsPerColor` | `mode_tri_static_pattern` (FX.cpp:2870): writes `SEGCOLOR(0..2)` directly, no palette, in runs of `segSize = (ix>>5)+1` **virtual** pixels → `ix:0` = 1-px runs |
| 2 | **fx 83**, `sx:0`, `ix:0`, **`pal:0`**, `grp = ledsPerColor` | `mode_static_pattern` (FX.cpp:2849): lit run `1+sx` px of `color_from_palette(i,…)`, which at `pal 0` returns `SEGCOLOR(0)` (FX_fcn.cpp:1173) — **no positional mapping**; unlit run `1+ix` px of `SEGCOLOR(1)` |
| width | **`grp`** | every virtual pixel is expanded to `grouping` physical LEDs: `i = i * groupLength()` (FX_fcn.cpp:831), `groupLength() = grouping + spacing` (FX.h:532) |

So the band is exactly `ledsPerColor` LEDs wide, for any width, with no fx-84 cap at 8. `spc` still adds
dark LEDs between groups, as before.

### A4. The Explore grid card — same helper, two bugs fixed as a consequence

`PatternCard._preparePayload` now calls `solidLayoutFields(SolidLayout.alternating, …)`. That fixed:

- **N×N bands.** It sent a band size (`sx`/`ix = ledsPerColor−1`, or `(ledsPerColor−1)·32`) **and**
  `grp = ledsPerColor`. The firmware multiplies them: "3 LEDs per color" produced 9. The preview showed 3.
- **Two-colour "alternating" that wasn't.** It sent fx 83 with `pal:5`, which maps the palette
  *positionally*: the first half of the strip alternated, the second half was solid `col[1]` (the prior
  report's open item). Two-colour alternating needs `pal:0`.

Its `_GradientDotPreview` now mirrors `_ledsPerColor` directly (the `.clamp(1, 8)` mirrored the old
fx-84 cap, which no longer applies).

### A5. Previews — both surfaces, verified

- **Tile** (`EffectPreviewWidget`): new optional `alternatingLedsPerColor`. When the Alternating layout is
  active the selector passes the chosen width and the tile renders `kAlternatingPreviewCells` (12) cells
  coloured by `alternatingBandIndex` — the device's `(i ~/ grp) % N`. Plain fx 84 picked as a catalog
  effect now previews as 1-wide alternating (representative; its real width is `(ix>>5)+1 × grp`, which a
  tile can't know — stated in the code). **fx 83 without a width still previews as blocks — the prior fix
  is unregressed** (tested).
- **Dot row** (`_buildColorLayoutPreview`): positional blocks only when the layout is Blocks; otherwise
  the existing `(i ~/ colorGroup) % N` — which *is* the grp expansion, and is now drawn only for the case
  it is correct for.

---

## PART B — The Rainbow leak and the folder structure

### B1. Folder structure as found

Root categories are built in `PatternRepository._buildRootCategories()` (`pattern_repository.dart:804`),
sorted by `sortOrder`; ids are registered in `LibraryCategoryIds` (`library_hierarchy_models.dart:165`).
Cards are `LibraryNode`s with `parentId` pointing at a folder or root; each data file under `lib/data/`
contributes its subtree in `_buildFullHierarchy()`.

| sortOrder | id | name |
|---|---|---|
| 0 | `cat_arch` | Architectural Downlighting (White) |
| 1 | `cat_sports` | Game Day Fan Zone |
| 2 | `cat_holiday` | Holidays |
| 3 | `cat_movies` | Movies & Superheroes |
| 4 | `cat_nature` | **Nature & Outdoors** — *one* combined root, not two |
| 5 | `cat_party` | Parties & Events |
| 6 | `cat_season` | Seasonal Vibes |
| 7 | `cat_security` | Security & Alerts |
| 8 | `my_designs` | My Designs (dynamic; must sort last) |

`cat_nature`'s children (`lib/data/nature_outdoors_palettes.dart`): seven sub-folders — Universe & Space,
Forests & Woodlands, Ocean & Water, Mountains & Sky, Gardens & Flowers, Earth Elements, Wildlife — each with
palette cards. **There was no Rainbow folder, no Rainbow palette node anywhere in the library, and nothing
rainbow inside Nature.** The only "Rainbow" *palette* in the codebase is `canonical_palettes.dart:472`, a
`CanonicalTheme` in `ThemeCategory.mood` used by the AI/search layer — not a library node.

### B2. Root cause of the leak — traced, not assumed

**Where it showed:** every palette card opens `ColorwayEffectSelectorPage`, whose default effect list is
`WledEffectsCatalog.topPicks`. **`topPickIds` contained `9 // Rainbow`** (`wled_effects_catalog.dart:916`).
That is a Rainbow tile on every card in the library, by construction. Under the "All" / "Any Color"
filters, `filterEffects()` returns `standardEffects` unfiltered, which includes all nine
`rainbowEffectIds` (9, 14, 24, 26, 30, 33, 63, 94, 99) — also on every card. `celebrationPicks` (the
Game Day path through the same page) was the third unscoped list.

**Why it "changed system colors to rainbow" — and a correction to the app's own assumption.** The app's
comments (`pattern_generator_service.dart:16,29`, `canonical_palettes.dart:481`) say rainbow effects
"override any color palette". On v0.15.1 that is **not** what the firmware does:

```cpp
uint32_t Segment::color_wheel(uint8_t pos) const {            // FX_fcn.cpp:1145
  if (palette) return color_from_palette(pos, false, true, 0); // ← samples the SEGMENT PALETTE
  … hue wheel (red→magenta→blue→cyan→green→yellow→red) …       // only at pal 0
```

So through the selector — which sends `pal:4` for rainbow-family effects (`paletteForEffect` →
"Color Gradient") — fx 9 renders a **scrolling gradient of the card's three `col[]` colours**, not a
rainbow. The reported "turns rainbow" symptom is the **`pal:0` / pal-absent** case: paths that send a
rainbow effect with no palette leave the device on its current palette, which is 0 by default → hue
wheel. Those paths exist (`SmartPattern.toJson` omits `pal` when `paletteId` is null; the grid card's
non-Solid branch never touches `pal`; `alert_trigger_service.dart:390-503` sends fx 9/63 with no `pal`)
but are outside the Explore surface this task scopes; listed, not changed.

### B3. Folder work — what was created, and the interpretation conflict (flagged)

**Created:** root category **`cat_rainbow` "Rainbow"** (`LibraryCategoryIds.rainbow`, sortOrder 8; My
Designs moved to 9 and stays last — its "last" test is updated and green), and `lib/data/rainbow_palettes.dart`
with **one** card, `rainbow_spectrum` "Full Spectrum" (`themeColors: kRainbowSpectrum`,
`metadata: {rainbow: true, suggestedEffectId: 9}`). One card on purpose: what further "genuine rainbow
colourways" should be is a content decision (pastels and pride flags are *user-colour* palettes, not
hue-wheel rainbows), not something to invent here. **Nature & Outdoors is untouched** — its seven
sub-folders are pinned by a new test.

**Conflict, as instructed to flag rather than resolve silently.** This brief says: Rainbow as its own
folder, distinct from Nature/Outdoor. The *previous* session's brief (the thirds-preview task) described
the same bug as Rainbow being "a specific Rainbow palette scoped to the Nature and Outdoor folders". Those
are different structures. **In code and docs there is no evidence for either** — no rainbow node under
Nature, no Rainbow folder, no design note; the only prior pointer is that earlier brief's wording. The
standalone root was built because (a) it is what this brief primarily instructs, (b) it is purely
additive and reversible (one root node + one data file + one id constant), and (c) `isRainbowLibraryNode`
also honours a `metadata: {'rainbow': true}` tag, so if the Nature-scoped reading turns out to be the
intent, a rainbow card can be placed under `cat_nature` later without touching the scoping code. The
`my_designs_category_injection_test.dart` root counts were bumped 8→9 / 9→10 for the new root (expected
collateral, called out in the test comments).

### B4. The scoping fix

`lib/features/wled/rainbow_scope.dart` (pure): `isRainbowLibraryNode(node)`, `isRainbowEffectId(id)`
(registry ∪ 'Rainbow' category), `scopeRainbowEffects(list, rainbowScope:)`,
`rainbowPaletteOverride(effectId:, rainbowScope:)`.

- `9` removed from `topPickIds` (the leak line; the comment there says why).
- The selector wraps all three lists — top picks, the filtered list, and `celebrationPicks` — in
  `scopeRainbowEffects(..., rainbowScope: _isRainbowPalette)`. Rainbow-family effects are visible **only**
  on nodes under `cat_rainbow` (or tagged `rainbow: true`).
- Everything else — `paletteForEffect`, the `pal:5→4` rewrite in `normalizeWledPayload`, the Rainbow tile
  painter, `getPreviewType` — is byte-identical.

### B5. The Rainbow cards' colour output — corrected, and verified at the firmware

What a Rainbow card would have rendered before: the six-stop spectrum swatch is cut to `take(3)` for
`col[]` (red, orange, yellow), and with `pal:4` the effect sweeps a **red→orange→yellow gradient** — a
truncated warm subset, exactly the failure the brief describes.

Now: on a Rainbow-scoped node, rainbow-family effects go out with **`pal:0`** (`SelectorState.paletteOverride`,
set from `rainbowPaletteOverride`), which makes `color_wheel` fall through to its hue wheel — the full 360°
of hue in three 85-step sectors (FX_fcn.cpp:1148-1157). `mode_rainbow_cycle` (fx 9, FX.cpp:436) lays that
wheel along the strip and scrolls it. The swatch/preview is `kRainbowSpectrum`: red, orange, yellow,
green, blue, violet — hue-monotonic, tested — which is what the wheel looks like, even though `col[]`
can only carry three of them (which is precisely why the device gets `pal:0` and not those colours).
Non-rainbow effects on the same card keep honouring the user's colours (tested: fx 28 → no override).
`selectorStateFromPayload` reads an override back when the stored `pal` differs from the derived one, so a
saved Alternating/Rainbow design round-trips instead of being rewritten on its next save (tested).

---

## Verification

- **New tests — 31, all green:** `solid_layout_alternating_test.dart` (wire form per layout, the N×N rule,
  the 2-colour `pal:0` rule, the grp band formula vs the positional partition, `paletteOverride` round-trip,
  and widget tests: 1-wide/3-wide/2-colour alternating tiles, **Blocks still renders three ordered blocks**,
  fx 84-as-effect, chase untouched) and `rainbow_scope_test.dart` (no rainbow in top picks and the exact
  remaining pick order, registry ∪ category coverage, All/Any-Color list scoped, Rainbow node keeps them,
  node predicate incl. Nature negative, `pal:0` only for rainbow effects on rainbow nodes, wire payload,
  six-stop hue-monotonic spectrum, folder existence/order/My-Designs-last, Nature's seven sub-folders
  unchanged, the Full Spectrum card's placement and scope).
- **Existing suites that import the changed files** — prior blocks suite, `preview_effect_category_unification`,
  `design_edit_tuner` (payload round-trip), `normalize_wled_payload`, `effects_catalog_device_parity`,
  `sync_picker_folder_card`, `my_designs_category_injection` (counts updated): **all green**.
- `flutter analyze` (repo-wide): **385 issues, 0 errors** — identical to the `origin/main` baseline; the four
  new/changed lib files add none.
- Full `flutter test`: **3027 passed, 0 failed**, 4 skipped (the `skip: !kRunHw` bench-rig cases), exit 0 — the prior 2996 plus the 31 new tests.
- **Not runtime-verified on hardware.** No bench device is on the network for this session. The firmware
  traces above are cited by file and line; the two-colour `pal:0` alternating path and the `pal:0` rainbow
  path should be eyeballed on the bench before this ships.

## Files

New: `lib/features/wled/rainbow_scope.dart`, `lib/data/rainbow_palettes.dart`,
`test/features/wled/solid_layout_alternating_test.dart`, `test/features/wled/rainbow_scope_test.dart`.
Changed: `solid_palette_blocks.dart` (+layout helper), `selector_payload.dart` (`paletteOverride`),
`pattern_providers.dart` (layout provider), `wled_effects_catalog.dart` (top picks), `library_hierarchy_models.dart`
(`cat_rainbow`), `pattern_repository.dart` (root + nodes), `effect_preview_widget.dart` (alternating tile),
`pattern_grid_widgets.dart` (grid card via helper), `colorway_effect_selector.dart` (layout toggle, scoping,
overrides), `test/features/design/my_designs_category_injection_test.dart` (root counts).

## Left open / flagged

- Copy: "Blocks" / "Alternating" are new labels (no guide term exists).
- Rainbow folder content beyond "Full Spectrum" is a content decision.
- Nature-scoped vs standalone Rainbow: see B3.
- Other `pal`-less rainbow senders outside Explore (SmartPattern, sports alerts): see B2, unchanged.
- The app's comments claiming rainbow effects ignore palettes are wrong for 0.15.1; left as-is outside the
  files touched.
