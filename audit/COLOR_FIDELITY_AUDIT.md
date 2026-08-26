# Colour Fidelity Audit

**Read-only.** No files modified beyond this document; no commits; no
`flutter test` / `flutter analyze`. Bench access limited to GETs on
`/json/{info,effects,palettes,fxdata}` — **no POSTs, no state change**. Bridge
firmware untouched.

---

## 1. Branch, HEAD, firmware

> ### Premise correction — the merge has not happened
>
> The brief says *"BRANCH: main, post-merge of feat/design-card."* It is not
> merged. `main` is still at **`c14368d`**, exactly where it was before Phase A;
> `git branch --merged main` does not list `feat/design-card`.
>
> I audited **`feat/design-card` @ `18479ba`**, which contains all the Phase A–C
> work and the addendum. Every finding below therefore describes the code as it
> will be *after* the merge you intend. Where a finding pre-dates the branch
> (D1, D2 and most of Task 1 do), it is equally true on `main` today, and I say
> so per item.

| | |
|---|---|
| Branch audited | `feat/design-card` |
| HEAD | `18479ba1b68c3e774805eb3b7bf67c381fd12f46` |
| `main` | `c14368d` (unmerged) |
| Controller | `192.168.1.150` — **reachable**, all four GETs returned 200 |
| Firmware | **WLED 0.15.1**, `vid 2507300`, esp32, core `v3.3.6-16-gcc5440f6a2` |
| Tables | `fxcount 187`, `palcount 71` — **`/json/fxdata` EXISTS on this build** (5 557 bytes) |
| LEDs | 290, `seglc [3,3]`, `rgbw: true`, `wv: 2`, `maxseg: 32` |

The pinned-version rule holds: this is 0.15.1, not 0.15.4.

---

## 2. Preview renderer inventory (Task 1)

| Renderer | file:class | Inputs | Per-pixel colour rule | Solid special case? | Reads effect metadata? |
|---|---|---|---|---|---|
| **Pixel strip** (Lumina sheet) | [pixel_effect_controller.dart](../lib/features/ai/pixel_effect_controller.dart) via `PixelStripPreview`/`PixelRenderer` | colour list + `EffectType` (speed, brightness). **No `pal`, no `grp`/`spc`, no `col` slots** | **`_baseColor(i) => _baseColors[i % _baseColors.length]`** ([:312-315](../lib/features/ai/pixel_effect_controller.dart#L312-L315)) — **confirmed: cycles col entries by pixel index regardless of effect** | **No.** `EffectType.solid` → `_updateStatic` ([:140-148](../lib/features/ai/pixel_effect_controller.dart#L140-L148)) calls the same `_baseColor(i)`; it differs from chase only by a 3 % brightness pulse | Category only, via `effectTypeFromWledId` ([light_effect_animator.dart:29-47](../lib/features/ai/light_effect_animator.dart#L29-L47)). Never colour-slot data |
| **Roofline painter** (hero, Design Studio, AR) | [roofline_light_painter.dart](../lib/widgets/roofline_light_painter.dart) | colour list, `effectId`, speed, intensity, `colorGroupSize`, `spacing`, `ledCount` | **`_getColorForLed(i) => colors[(i ~/ groupSize) % colors.length]`** ([:363-366](../lib/widgets/roofline_light_painter.dart#L363-L366)). `colorGroupSize` **defaults to 1** ([:141](../lib/widgets/roofline_light_painter.dart#L141)) → one bulb each | **No.** `EffectCategory.solid` → `_paintSolidPath` ([:522-528](../lib/widgets/roofline_light_painter.dart#L522-L528)) → the same cycling helper. It honours `spacing`, not fx | Category only, `categorizeEffect` ([ar_preview_providers.dart:118-135](../lib/features/ar/ar_preview_providers.dart#L118-L135)) |
| **Roofline, real-index mode** | same painter, `realIndexMode: true` | Pre-computed `ledColors` per segment | `ledColors[i]` verbatim ([:316](../lib/widgets/roofline_light_painter.dart#L316)) — **truthful to whatever built the frame** | N/A — no fx involved | No |
| **`DesignPreview` seam** (DesignDetailScreen, Studio) | [design_preview.dart:17](../lib/features/design/manual_editor/design_preview.dart#L17) | `DesignFrame` = per-LED colours | Real-index mode above. For a stored design the frame comes from `frameFromCustomDesign`, which reads **`colorGroups` only** | N/A | **No — and it ignores `fx` entirely.** A chase design previews as its static colour layout |
| **Tile preview** | [effect_preview_widget.dart](../lib/features/wled/effect_preview_widget.dart) | colours + `effectId` | **`kWledColorRoles`** ([:33-55](../lib/features/wled/effect_preview_widget.dart#L33-L55)) — the app's only per-effect colour-slot model | Yes: fx 0/83/84/85/98 → `EffectPreviewType.solid` ([:97-99](../lib/features/wled/effect_preview_widget.dart#L97-L99)) | **Yes — the only one that does.** But see F-B below: **15 of 180 effects have entries**, and fx 0 is not one of them |
| **Explore card thumbnail** | `_CompactPatternItemCard` + `_GradientDotPreview` ([pattern_grid_widgets.dart:1558-1575](../lib/features/wled/pattern_grid_widgets.dart#L1558-L1575)) | card payload + active colours + `ledsPerColor` | `usePreparedBandPreview` renders equal repeating bands **when the apply path will substitute fx 83** | **Yes, effectively** — the only preview whose comment states it must match what apply produces | Indirectly: it mirrors its own substitution rule |
| **Light preview strip** (chat) | [light_preview_strip.dart:167-169](../lib/features/ai/light_preview_strip.dart#L167-L169) | colour list + `EffectType` | `_currentColors[i % _currentColors.length]` — same modulo cycling | No | Category only |
| **Sync house preview** | [sync_control_panel.dart](../lib/features/neighborhood/widgets/sync_control_panel.dart) `_PalettePickerCard` / `FolderPickerCard` | `LibraryNode.themeColors` | Swatch strip; no per-LED simulation | N/A | No |

### Findings

**F-A. Six of eight renderers cycle `col` by pixel index, for every effect.** The
rule is literally `colors[i % colors.length]`. It is correct for fx 83/84
(banded), wrong for fx 0, and unrelated to what WLED does for the other 183.

**F-B. The app's per-effect colour-slot model covers 15 of 180 effects.**
`kWledColorRoles` is real and well-reasoned, but it is a hand-maintained
allow-list. Everything absent falls back to `primary 0 / background 1 /
accent 2` — i.e. **the app assumes three consumed colours by default**, which
firmware contradicts for 160 of 180 (§5). fx 0 is absent from the map.

**F-C. `DesignPreview` — the seam Phase A introduced — ignores `fx` by
construction.** `frameFromCustomDesign` paints `colorGroups` ranges only. For a
per-pixel design that is exactly right. For an **effect** design it renders the
static colour layout and no motion, so a saved chase previews as a solid fill.
This is a known limit of the seam, not a regression.

---

## 3. Card-to-payload trace (Task 2)

**The path.** Explore card tap → `_CompactPatternItemCard._applyPattern` →
`_preparePayload(rawPayload, activeColors, ledsPerColor)`
([pattern_grid_widgets.dart:1484-1543](../lib/features/wled/pattern_grid_widgets.dart#L1484-L1543)) →
`applyChannelFilter` → `repo.applyJson` → `normalizeWledPayload` at the wire.

For the **colourway tuner** (the "colour card" of D1) the entry point is
`ColorwayEffectSelectorPage`, whose `initState` seeds
**`selectorEffectIdProvider = 0`** — Solid —
([colorway_effect_selector.dart:260](../lib/features/wled/colorway_effect_selector.dart#L260)).
That is the default D1 names.

| Question | Answer |
|---|---|
| Default effect | **fx 0 (Solid)**, set at [:260](../lib/features/wled/colorway_effect_selector.dart#L260) |
| `pal` handling | Card path forces `pal: 5` **only inside its fx-0 branch** ([:1524](../lib/features/wled/pattern_grid_widgets.dart#L1524)); the tuner derives it from the catalog; stored designs emit none (§3-2e) |
| Colour count | Card carries **all active** colours (uncapped in `_preparePayload`); every other builder caps at 3 |
| Same object as the preview? | **No — built separately.** The preview is drawn from `_getColors()` + `EffectType`; the payload is built by `_preparePayload` from `rawPayload`. They are two derivations of the same card that agree only because `usePreparedBandPreview` re-implements the substitution rule by hand ([:1568-1575](../lib/features/wled/pattern_grid_widgets.dart#L1568-L1575)). Nothing enforces that they stay in step. |

### 2e — Builder table and the two divergences *(merged from [COLOUR_FIDELITY_ADDENDUM.md](COLOUR_FIDELITY_ADDENDUM.md) §2e)*

| # | Builder | file:line | fx substitution | `pal` | `grp`/`spc` | Colours |
|---|---|---|---|---|---|---|
| 1 | `CustomDesign.toWledPayload` | [design_models.dart:244-278](../lib/features/design/design_models.dart#L244-L278) | **0 → 83** when >1 group. Never 84 | **NONE EMITTED** | #88 constants | `.take(3)`/channel |
| 2 | `buildSelectorPayload` | [selector_payload.dart:107-131](../lib/features/wled/selector_payload.dart#L107-L131) | None — caller decides | `paletteForEffect(fx)` — derived | From providers | `.take(3)` |
| 3 | `_preparePayload` (card) | [pattern_grid_widgets.dart:1484-1543](../lib/features/wled/pattern_grid_widgets.dart#L1484-L1543) | **0 → 83 (2 col) / 84 (3+)**; **N → 0** for 1 colour | `pal: 5`, fx-0 branch only | **`grp: ledsPerColor`** | all active |
| 4 | `GradientPattern.toWledPayload` | [pattern_models.dart:326-356](../lib/features/wled/pattern_models.dart#L326-L356) | **0 → 83**, never 84 | `pal: 5` **unconditional** | #88 constants | `.take(3)` |
| 5 | `SyncPatternAssignment.fromLibraryNode` | [neighborhood_models.dart:1286-1308](../lib/features/neighborhood/neighborhood_models.dart#L1286-L1308) | None | `pal: 5` default | defaults | **preview swatches** |
| 6 | Sync member apply | [neighborhood_sync_engine.dart:760-777](../lib/features/neighborhood/neighborhood_sync_engine.dart#L760-L777) | None | assignment's | assignment's | `.take(3)` |
| 7 | `customDesignToSpans` | [design_apply.dart:95-113](../lib/features/design/manual_editor/design_apply.dart#L95-L113) | N/A — per-pixel `i` | N/A | N/A | all |
| 8 | `Scene.toWledPayload` | [scene_models.dart:234-240](../lib/features/scenes/scene_models.dart#L234-L240) | delegates to #1 | delegates | delegates | delegates |
| 9 | `EditablePattern.toWledPayload` | [editable_pattern_model.dart:123](../lib/features/wled/editable_pattern_model.dart#L123) | *not audited — different store* | — | — | — |
| — | `normalizeWledPayload` *(transformer)* | [wled_payload_utils.dart:553-640](../lib/features/wled/wled_payload_utils.dart#L553-L640) | none | **absent `pal` → untouched** ([:632](../lib/features/wled/wled_payload_utils.dart#L632)); rewrites explicit `pal:5` → `4` for palette-driven fx ([:635](../lib/features/wled/wled_payload_utils.dart#L635)) | injects #88 defaults via `putIfAbsent` | untouched |

**The `pal` disagreement.** Builder #1 emits **zero `'pal'` keys** (verified: the
only "pal" in `toWledPayload` is the word *palette* in a comment), and normalize
leaves an absent `pal` alone. **A saved design inherits whatever palette the
segment previously held** — the #67 inherited-state class. Meanwhile #4 hardcodes
`pal:5`, #3 sets it only in one branch, #2 derives it. Same design, three
surfaces, three palettes.

**The fx-0 substitution divergence.** #1 always picks 83; #3 picks 83 for two
colours and **84** for three
([pattern_grid_widgets.dart:1505-1525](../lib/features/wled/pattern_grid_widgets.dart#L1505-L1525)).
83 is a two-colour effect and 84 a three-colour one (§4), so **a three-colour
design shows its third colour from its card and loses it from My Designs.**

### 2f — Sync payload *(merged from addendum §2f)*

`SyncPatternAssignment.toJson` carries nine primitives and **no payload field**
([neighborhood_models.dart:1314-1324](../lib/features/neighborhood/neighborhood_models.dart#L1314-L1324));
the model's own `wledPayload` ([:1213](../lib/features/neighborhood/neighborhood_models.dart#L1213))
is not serialised. Members apply **one id-less seg**
([neighborhood_sync_engine.dart:760-777](../lib/features/neighborhood/neighborhood_sync_engine.dart#L760-L777)),
broadcast to every participating channel — so **channel scope is lost outright**,
**per-pixel is structurally unrepresentable** (no `i` channel exists), colours are
capped at 3 twice, and fx is passed verbatim with no substitution. Effect designs
are only partly representable and **are not transmitted regardless**, because
assignments are built from a node's preview swatches rather than from the design.

---

## 4. Effect table: app vs firmware (Task 3)

**App tables found:** `WledEffectsCatalog` (180 entries,
[wled_effects_catalog.dart](../lib/features/wled/wled_effects_catalog.dart)) — the
declared single source; `wled_effect_metadata.dart` (slider labels);
`effect_speed_profiles.dart` (speed curves); `kWledColorRoles`
(15 colour-slot entries); `effect_mood_system.dart` (mood tags).
`EffectDatabase` still exists but the preview mappers were moved off it (#6).

### Names — clean

**Zero mismatches across all 180 app entries** against `/json/effects`. The #82
correction held. Seven firmware effects (of 187) are absent from the app catalog;
none is referenced by app code.

### Colour consumption declared by firmware

Parsed from `/json/fxdata`, field 2 (`;colors;`), counting non-empty slots:

| Colours consumed | App-catalog effects | Share |
|---|---|---|
| **0** (palette-driven — user `col` ignored) | 57 | 32 % |
| **1** | 28 | 16 % |
| **2** | 75 | 42 % |
| **3** | **20** | **11 %** |

**85 of 180 (47 %) consume one colour or none.** Only 11 % consume three.

Sample of the ids the app actually ships as defaults:

| fx | Firmware name | ncol | `colors` field | Sliders |
|---|---|---|---|---|
| **0** | **Solid** | **0** | `''` | `''` |
| 1 | Blink | 2 | `!,!` | `!,Duty cycle` |
| 3 | Wipe | 2 | `!,!` | `!,!` |
| 10 | Scan | 3 | `!,!,!` | `!,# of dots,…` |
| 20 | Sparkle | 2 | `!,!` | `!,…,Overlay` |
| 28 | Chase | 3 | `!,!,!` | `!,Width` |
| 63 | Pride 2015 | **0** | `''` | `!` |
| 66 | Fire 2012 | **0** | `''` | `Cooling,Spark rate,…` |
| 74 | Colortwinkles | **0** | `''` | `Fade speed,Spawn speed` |
| 77 | Meteor Smooth | **0** | `''` | `!,Trail,…` |
| **83** | **Solid Pattern** | **2** | `Fg,!` | **`Fg size,Bg size`** |
| **84** | **Solid Pattern Tri** | **3** | `1,2,3` | **`,Size`** |
| 87 | Glitter | 1 | `,,Glitter col` | `!,!,…,Overlay` |
| 110 | Flow | **0** | `''` | `!,Zones` |
| 115 | Blends | **0** | `''` | `Shift speed,Blend speed` |

Note fx 87 **Glitter**: its one consumed colour sits in **slot 3** (`col[2]`), so
a three-colour design running Glitter uses only its *third* colour.

### `/json/palettes` — first six

`0 Default` · `1 * Random Cycle` · `2 * Color 1` · `3 * Colors 1&2` ·
`4 * Color Gradient` · `5 * Colors Only`

Confirms the app's `pal:5` = "Colors Only" and `pal:4` = "Color Gradient"
assumptions in `normalizeWledPayload`.

### CLOSING THE ADDENDUM'S CAVEAT — `ix` / "Pattern Size"

The addendum's BLOCKERS finding rested on `wled_effect_metadata.dart:325-336`
(`usesSpeed: false, usesIntensity: true, intensityLabel: 'Pattern Size'` for both
83 and 84) and flagged that this was the app's own metadata, not a firmware
source. Cross-checked against `/json/fxdata`:

| fx | Raw fxdata | Slider 1 (`sx`) | Slider 2 (`ix`) | App says | Verdict |
|---|---|---|---|---|---|
| **83** | `Fg size,Bg size;Fg,!;!;;pal=0` | **`Fg size`** — foreground band | **`Bg size`** — background band | `usesSpeed: false`, `ix` = "Pattern Size" | **CONTRADICTED** |
| **84** | `,Size;1,2,3;;;pal=0` | *(empty — unused)* | **`Size`** | `usesSpeed: false`, `ix` = "Pattern Size" | **CONFIRMED** |

**fx 83: the app metadata is wrong on both counts.** `sx` **is** used — it is the
foreground band size — and `ix` is the *background* band size, not a single
"Pattern Size". Two independent sizes, not one.

Three consequences:

1. **The card path is vindicated.** `s['sx'] = n; s['ix'] = n`
   ([pattern_grid_widgets.dart:1512-1516](../lib/features/wled/pattern_grid_widgets.dart#L1512-L1516))
   sets both band sizes equal — exactly what its comment claims, and exactly
   right per firmware. This is the only place in the app that models fx 83
   correctly.
2. **The design path is indicted.** Builder #1 writes `channel.speed` into `sx`
   and `channel.intensity` into `ix`. When its 0 → 83 substitution fires, those
   two stored values silently become **foreground and background band sizes**.
3. **`kWledColorRoles[83]` is also wrong**: it declares `accent: 2` (three bands),
   but firmware says 83 consumes **two** colours. 84 is the three-colour one, and
   84 has no roles entry at all.

The addendum's substance stands — `ix` does change meaning — but its *mechanism*
is corrected: it is not one repurposed slider, it is **two**, and `sx` is not
inert.

---

## 5. Colour-usage census (Task 4)

| Source | Typical fx | Colours supplied | Consumed (firmware) | `pal` | Palette-driven at `pal=0`? |
|---|---|---|---|---|---|
| Colourway tuner default | **0 Solid** | up to 3 (`_paletteColsRgbw`) | **0 — col[0] only** | derived | fx 0 ignores palette |
| Colourway tuner, user picks an effect | any of 180 | up to 3 | 0/1/2/3 per §4 | derived | 57 of 180 are palette-driven |
| Explore card, 2 active colours | 0 → **83** | 2 | 2 | `pal:5` | no |
| Explore card, 3 active colours | 0 → **84** | 3 | 3 | `pal:5` | no (84 declares no palette segment) |
| Explore card, 1 active colour | any → **0** | 1 | 0 (col[0]) | untouched | n/a |
| `GradientPattern` cards | 0 → **83**, or catalog fx | 3 (`take(3)`) | 2 at 83 — **third dropped** | `pal:5` always | no |
| Stored design, multi-group | 0 → **83** | 3 | **2 — third dropped** | **none emitted → inherited** | unknown at rest |
| Stored design, single group | as stored | 1 | per effect | **none emitted → inherited** | unknown at rest |
| Per-pixel design | none (`i` writes) | all | all | n/a | n/a |
| Smart presets / base ladder | per preset | 1–3 | per effect | varies | varies |

**Summary counts.**
- 3 supplied → 3 consumed: only when the effect is one of the **20** three-colour
  effects, or the card path routes to fx 84.
- **3 supplied → 2 consumed: the commonest saved case** — any multi-colour design
  substituted to fx 83, plus 75 two-colour effects.
- **3 supplied → 1 consumed: 28 effects**, plus Glitter's slot-3 quirk.
- **3 supplied → 0 consumed: 57 effects** (32 %) ignore user colours entirely and
  render their own palette. Nothing in the app warns the user of this.

### 4d — Sync and Game Day *(merged from addendum §4d)*

| | Neighborhood Sync assignment | Game Day `savedDesignPayload` |
|---|---|---|
| Store | Sync command / per-house maps | `/users/{uid}/game_day_autopilot/{slug}` |
| Colour form | `colors: List<int>`, `c.value & 0xFFFFFF` ([:1300](../lib/features/neighborhood/neighborhood_models.dart#L1300)) | **full RGBW `col` arrays** |
| W channel | **dropped at write**, re-derived by `rgbToRgbw` at apply | **preserved** |
| Cap | 3 at apply | 3 |
| `pal` | assignment's (default 5) | **catalog-derived** (built by the tuner) |
| Verdict | lossy by construction — a nine-field recipe, not a design | **best-specified stored form in the app** |

**The asymmetry stands:** Game Day persists a *better-specified* payload than
`/users/{uid}/designs` does — full RGBW, `pal` stated — because it stores the
tuner's built payload, while the designs collection stores structured channels
and re-derives, dropping `pal` on the way.

---

## 6. Saved-payload exposure (Task 5)

| Store | Path | Payload form |
|---|---|---|
| Designs | `/users/{uid}/designs` ([design_service.dart:15](../lib/features/design/design_service.dart#L15)) | structured `channels`; payload re-derived on read |
| Scenes | `/users/{uid}/scenes` ([scene_providers.dart:20](../lib/features/scenes/scene_providers.dart#L20)) | embedded `CustomDesign` |
| Favorites | `/users/{uid}/favorites` | `wledPayload` jsonEncoded |
| Patterns | `/users/{uid}/patterns` | `EditablePattern` |
| Schedules | inline `wledPayload` per item | full seg |
| Game Day | `/users/{uid}/game_day_autopilot/{slug}` | `saved_design_payload` jsonEncoded |

**Does any path rewrite a saved payload's `fx` or `col` on read?**

- **On deserialisation — no.** `fromFirestore`/`fromJson` are faithful; nothing
  mutates `fx` or `col` at read time.
- **On apply — yes, twice, and both are visible to the user.**
  1. `normalizeWledPayload` rewrites an explicit **`pal: 5` → `pal: 4`** for
     palette-driven effects ([wled_payload_utils.dart:635](../lib/features/wled/wled_payload_utils.dart#L635)).
     `fx` and `col` are untouched, but the palette change alters rendered colour.
     Applied to Game Day saved designs at
     [game_day_autopilot_background_worker.dart:524/559](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L524).
  2. **`fx` is rewritten at build time, not read time** — the 0 → 83/84
     substitution (§3-2e). A design stored as `fx: 0` is *never* applied as
     `fx: 0` when it has multiple colours. The stored value and the applied value
     differ permanently, with no marker.

**Exposure:** a user's saved design is faithfully stored and faithfully read,
then **systematically altered on the way to the hardware** — palette possibly
rewritten, effect possibly substituted, colours possibly truncated to 3 and then
partly ignored by the effect. None of this is surfaced.

---

## 7. Root cause

**D1 — preview shows alternating colours, hardware paints one.**
Every strip and roofline renderer colours pixel *i* as `colors[i % colors.length]`
regardless of effect — `_baseColor` at
[pixel_effect_controller.dart:312-315](../lib/features/ai/pixel_effect_controller.dart#L312-L315)
and `_getColorForLed` at
[roofline_light_painter.dart:363-366](../lib/widgets/roofline_light_painter.dart#L363-L366),
the latter with `colorGroupSize` defaulting to 1 ([:141](../lib/widgets/roofline_light_painter.dart#L141)) —
and neither has a Solid special case: `EffectType.solid` and
`EffectCategory.solid` route to `_updateStatic` / `_paintSolidPath`, which call
those same cycling helpers. The card meanwhile defaults to **fx 0**
([colorway_effect_selector.dart:260](../lib/features/wled/colorway_effect_selector.dart#L260)),
whose firmware fxdata is the **empty string** — Solid declares no colour slots and
paints the whole segment `col[0]`.

**D2 — three colours supplied, one or two consumed.**
Builders cap at three and hand all three to the device, but firmware declares how
many each effect actually reads, and across the app's 180 catalogued effects only
**20 (11 %) consume three** while **85 (47 %) consume one or none** (§4) — and the
default, fx 0, consumes **zero** beyond `col[0]`. The app has no per-effect
consumption model to warn or adapt: `kWledColorRoles`
([effect_preview_widget.dart:33-55](../lib/features/wled/effect_preview_widget.dart#L33-L55))
covers 15 of 180 effects and everything else falls back to assuming three slots
are used.

**D3 — two substitutions, and a palette nobody states.**
The fx-0 substitution is implemented twice with different rules — unconditionally
83 in [design_models.dart:261-266](../lib/features/design/design_models.dart#L261-L266),
but 83-or-84-by-colour-count in
[pattern_grid_widgets.dart:1505-1525](../lib/features/wled/pattern_grid_widgets.dart#L1505-L1525) —
so the same three-colour design keeps its third colour from its card (fx 84,
three slots) and loses it from My Designs (fx 83, two slots). Separately,
`CustomDesign.toWledPayload` emits **no `pal` key at all** while every sibling
builder states one, and `normalizeWledPayload` leaves an absent `pal` untouched
([wled_payload_utils.dart:632](../lib/features/wled/wled_payload_utils.dart#L632)),
so a saved design renders under whatever palette the previous look left on the
segment — the #67 inherited-state class.

---

## 8. Blockers

**B1 — `ix` changes meaning under substitution. CONFIRMED by firmware, mechanism
revised.**

The addendum's finding holds and is now firmware-backed, but the mechanism is
worse than the app's metadata suggested. `/json/fxdata` for fx 83 is
`Fg size,Bg size;Fg,!;!;;pal=0`: **both sliders are sizes** — `sx` = foreground
band, `ix` = background band. The app's
`wled_effect_metadata.dart:325-336` claim (`usesSpeed: false`, `ix` = a single
"Pattern Size") is **CONTRADICTED for 83** and **CONFIRMED for 84**
(`,Size;1,2,3;;;pal=0` — `sx` genuinely unused there).

So when builder #1's 0 → 83 substitution fires, a design's stored **`speed` AND
`intensity`** are both silently reinterpreted as band geometry — not one slider,
two. A design saved `fx:0, speed:128, intensity:200` renders as
`fx:83, Fg size:128, Bg size:200`: uneven bands the user never chose.

**A truthful static-pattern preview needs the as-applied `(fx, sx, ix)` and the
slider semantics that follow from it, taken from `fxdata`, not the stored `fx`.**
The minimum is one shared resolver derived from the single substitution rule —
which requires first reconciling the two incompatible rules (D3).

**B2 — the #88 `grp`/`spc` model gap does NOT block 83/84 size, but does block
banding.** Size on 83/84 travels on `sx`/`ix`, which `ChannelDesign` stores.
The gap (`ChannelDesign` has no `grouping`/`spacing`;
[design_models.dart:272](../lib/features/design/design_models.dart#L272) spreads the
constants) blocks user-chosen LED-per-colour banding on **non-substituted**
multi-colour effects — the card path's `grp: ledsPerColor`, discarded on save.
Real, separate, lower priority.

**B3 — no per-effect colour-consumption model exists.** Fixing D2 needs
`fxdata`-derived consumption counts for all 187 effects. The data is available
from the controller at runtime and is currently not fetched by any code path
(§9).

---

## 9. Unknowns

| Unknown | Where I'd expect the answer |
|---|---|
| Whether the app ever fetches `/json/fxdata`. `grep fxdata lib/` returns nothing, so the richest firmware source is unused — but I did not audit whether a fetch exists under another name | [lib/features/wled/wled_service.dart](../lib/features/wled/wled_service.dart) |
| Whether `kWledColorRoles`' 15 entries were derived from `fxdata` or by observation. Its fx-83 entry (`accent: 2`) contradicts firmware, which suggests observation | git history of [effect_preview_widget.dart](../lib/features/wled/effect_preview_widget.dart) |
| What `pal` a saved design actually inherits in the field. Determined by whatever ran previously on that segment; unknowable without a device read per user | `/json/state` per controller |
| How many stored designs are multi-colour Solids — i.e. how many actually hit the substitution | client-credential read of `/users/{uid}/designs` |
| `EditablePattern.toWledPayload` behaviour (builder #9) | [editable_pattern_model.dart:123](../lib/features/wled/editable_pattern_model.dart#L123) — different store, out of scope here |
| Whether 0.15.1's `Fg size`/`Bg size` semantics match 0.15.4 | not testable — the fleet is pinned to 0.15.1 |
| Whether the seven firmware effects absent from the app catalog matter | `/json/effects` ids not in `WledEffectsCatalog` |

---

## 10. Appendices

### A. `/json/fxdata` — fx 83 and 84 (the cross-check evidence)

```
fx 83  "Solid Pattern"      →  Fg size,Bg size;Fg,!;!;;pal=0
fx 84  "Solid Pattern Tri"  →  ,Size;1,2,3;;;pal=0
fx  0  "Solid"              →  (empty string)
```

Field order: `[name@]sliders ; colors ; palette ; flags ; defaults`.
For 83 — sliders `Fg size`(sx) + `Bg size`(ix); colours `Fg,!` = **2**; palette
`!` = used; default `pal=0`.
For 84 — slider 1 empty (sx unused), slider 2 `Size`(ix); colours `1,2,3` = **3**;
palette segment empty = **not palette-driven**; default `pal=0`.

### B. `/json/palettes` — first six of 71

```
0  Default
1  * Random Cycle
2  * Color 1
3  * Colors 1&2
4  * Color Gradient
5  * Colors Only
```

### C. Full raw captures

Saved to the session scratchpad rather than inlined (187-entry arrays):

```
wled_info.json      965 B
wled_effects.json  2190 B   (187 names)
wled_palettes.json  771 B   (71 names)
wled_fxdata.json   5557 B   (187 entries)
```

Reproduce with:

```
curl -s http://192.168.1.150/json/info
curl -s http://192.168.1.150/json/effects
curl -s http://192.168.1.150/json/palettes
curl -s http://192.168.1.150/json/fxdata
```

All four returned HTTP 200 on 2026-08-24. **No POSTs were issued; controller
state was not altered.**

---

## What I would have had to fabricate, and didn't

1. **That the audit ran on merged `main`.** It did not — `main` is at `c14368d`
   and the branch is unmerged. Corrected in §1 rather than reported as asked.
2. **`EditablePattern.toWledPayload` (builder #9).** Left unaudited rather than
   guessed; it serves a different store.
3. **A count of affected saved designs.** Needs a client credential I do not have.
4. **Whether the app fetches `fxdata`.** `grep` finds nothing, but I did not
   exhaustively audit `wled_service.dart` for an aliased fetch, so it is listed
   as unknown rather than asserted.
5. **0.15.4 slider semantics.** The fleet is pinned to 0.15.1; I did not
   extrapolate.
