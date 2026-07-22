# Unified Preview Interpreter — Design (2026-05-22)

## 0. Why this exists

The prior audit identified three live roofline-preview painters plus one dead one, each with its own effect-ID-to-category map, each with subtly different rules for what to do with the user's color slots, and each with its own gaps. The result: the same pattern can render three different ways across the app (dashboard, pattern card, Lumina chat strip), and at least one of those ways disagrees with what WLED actually does on the device.

The recommended path is **one interpreter** — a single function `RenderedPattern → painter draw` — driven by a single fx-ID hook table, not 187 hand-tuned per-effect models. This doc decides the contract of that interpreter, the hook-table shape, the migration sequence, and where the work stops being worth doing.

References: this builds on the audit in [the existing painter files](lib/widgets/roofline_light_painter.dart) and the prior memory item set; concrete file:line citations are inline throughout.

---

## 1. Input union — what a unified interpreter must accept

Tabulating exactly what each painter reads today:

| Input | `RooflineLightPainter` (dashboard) | `EffectPreviewWidget` (pattern cards) | `LightEffectAnimator`+`LightPreviewStrip` (Lumina chat) |
|---|---|---|---|
| `effectId` | yes ([roofline_light_painter.dart:46](lib/widgets/roofline_light_painter.dart#L46)) | yes ([effect_preview_widget.dart:142](lib/features/wled/effect_preview_widget.dart#L142)) | yes via `effectTypeFromWledId` ([light_effect_animator.dart:20](lib/features/ai/light_effect_animator.dart#L20)) |
| `colors` (list) | yes ([roofline_light_painter.dart:44](lib/widgets/roofline_light_painter.dart#L44)) | yes ([effect_preview_widget.dart:143](lib/features/wled/effect_preview_widget.dart#L143)) | yes ([light_preview_strip.dart:25](lib/features/ai/light_preview_strip.dart#L25)) |
| Per-fx role mapping (col[0] vs col[1] semantics) | **no** — col[0] is treated as the dominant on-screen color regardless of effect | **yes** — `kWledColorRoles` per-fx table at [effect_preview_widget.dart:34-55](lib/features/wled/effect_preview_widget.dart#L34) | **no** |
| `paletteId` (WLED `pal`) | **no** — never read | **no** — never read | **no** — never read |
| `speed` (sx, 0-255) | yes ([roofline_light_painter.dart:48](lib/widgets/roofline_light_painter.dart#L48)) but only drives the animation duration upstream via `speedToDurationForEffect` ([ar_preview_providers.dart:252](lib/features/ar/ar_preview_providers.dart#L252)); the painter itself never uses the value | implicit — preview duration is a hardcoded per-category constant ([effect_preview_widget.dart:204-237](lib/features/wled/effect_preview_widget.dart#L204)), `sx` ignored | yes, normalized 0-1 ([light_effect_animator.dart:100](lib/features/ai/light_effect_animator.dart#L100)) |
| `intensity` (ix, 0-255) | yes — used by `_paintTwinklePath` for sparkle count ([roofline_light_painter.dart:522](lib/widgets/roofline_light_painter.dart#L522)) | **no** | **no** |
| `brightness` (bri, 0-255) | yes ([roofline_light_painter.dart:51](lib/widgets/roofline_light_painter.dart#L51)) | **no** | yes ([light_preview_strip.dart:38](lib/features/ai/light_preview_strip.dart#L38)) |
| `colorGroupSize` (WLED `grp`) | yes ([roofline_light_painter.dart:71](lib/widgets/roofline_light_painter.dart#L71)) | **no** | **no** |
| `spacing` (WLED `spc`) | yes ([roofline_light_painter.dart:75](lib/widgets/roofline_light_painter.dart#L75)) | **no** | **no** |
| `reverse` (seg.rev) | yes ([roofline_light_painter.dart:78](lib/widgets/roofline_light_painter.dart#L78)) | **no** | **no** |
| Multi-segment paths (per-channel) | yes ([roofline_light_painter.dart:84](lib/widgets/roofline_light_painter.dart#L84)) | **no** — single rectangle | **no** — single horizontal strip (optional arc) |
| `isOn` / off | yes ([roofline_light_painter.dart:50](lib/widgets/roofline_light_painter.dart#L50)) | **no** — always renders | **no** — always renders |
| Background color | yes ([roofline_light_painter.dart:67](lib/widgets/roofline_light_painter.dart#L67)) | derived from secondary color | derived per-effect |

The fragmentation lives in the **asymmetric consumer columns**. `EffectPreviewWidget` is the only painter that handles col-slot roles correctly; `RooflineLightPainter` is the only one that respects `grp/spc/reverse`; `LightPreviewStrip` is the only one that takes a normalized speed at the painter level. Each painter is partly right, completely independently.

A unified interpreter must accept the **union** of these inputs. Several inputs (paletteId, role mapping) are *not* in any current painter — those are net-new and the unification is the moment to add them.

---

## 2. The `RenderedPattern` contract

```dart
enum ColorRole { primary, background, accent }

enum PaletteResolution {
  /// The payload sets `pal:5` (Colors-Only). The preview must drive itself
  /// from the col entries and ignore any palette. This is the default for
  /// every pattern that flows through `GradientPattern.toWledPayload()`.
  honorCols,

  /// The payload sets a non-Colors-Only palette and the effect honors it
  /// (e.g. fx 9 Rainbow has respectsColors:false in EffectDatabase). The
  /// preview should render the palette's color sweep regardless of cols.
  usePalette,
}

enum MotionPrimitive {
  solid, breathe, chase, wipe, scanner, twinkle, sparkle,
  meteor, fire, fireworks, ripple, rainbow, strobe, ambient,
  noise, popcorn, bouncing, dripping, explosive, morphing,
}

class RenderedPattern {
  final int effectId;

  /// Resolved by ColorRole, not col-slot position. Built once at construction
  /// from (cols, kFxHooks[effectId].roles) so painters never have to know
  /// that fx 17 (Twinkle) puts background at col[1].
  final Map<ColorRole, Color> rolesResolved;

  /// Raw col entries as RGB (for primitives that legitimately need slot order:
  /// fx 83 Solid Pattern with grp band-cycling, multi-color chase). Length 1-3.
  final List<Color> rawCols;

  final int? paletteId;                  // WLED `pal`, null if unset
  final PaletteResolution paletteResolution;

  final double speed;       // 0..1 normalized from sx
  final double intensity;   // 0..1 normalized from ix
  final double brightness;  // 0..1 normalized from bri

  final int groupSize;      // WLED `grp`, default 1
  final int spacing;        // WLED `spc`, default 0
  final bool reverse;       // seg.rev
  final bool isOn;

  final MotionPrimitive primitive;       // resolved from fxId via _kFxHooks
}
```

### 2a. Palette resolution — the central correctness question

Every pattern emitted by `GradientPattern.toWledPayload()` forces `'pal': 5` (Colors-Only) — see [pattern_models.dart:343](lib/features/wled/pattern_models.dart#L343). The comment explicitly notes this is to "prevent rainbow palette blending" on effects like Spots Fade and Twinkle Fox. So for the Lumina pattern library, `paletteResolution = honorCols` is the **correct universal default** — the device is being told to ignore its own palette and use only the col entries.

But the audit found that for `respectsColors:false` effects in `EffectDatabase`, the current dashboard painter at [ar_preview_providers.dart:213-214](lib/features/ar/ar_preview_providers.dart#L213) routes to `EffectCategory.rainbow` and then `_paintRainbowPath` ignores the user colors entirely when there's only one ([roofline_light_painter.dart:480-498](lib/widgets/roofline_light_painter.dart#L480)). This is **wrong**: the device with `pal:5` is honoring the cols, but the preview is showing an HSV rainbow. The preview lies.

**Decision:** `PaletteResolution.honorCols` wins whenever the payload sets `pal:5` (which Lumina always does). The unified interpreter should never decide on its own to override cols based on `respectsColors`. The `respectsColors` flag is metadata for the *recommendation engine* (don't suggest "Rainbow" when the user asked for red and green) — it's not a preview directive.

`PaletteResolution.usePalette` exists for future cases where:
- User explicitly picks a palette in a non-Lumina UI (Edit Pattern advanced controls — currently absent but planned).
- A Lumina AI suggestion deliberately uses a palette (currently never).

For v1 of the unified interpreter, **only `honorCols` needs to be implemented**. `usePalette` is a stub that falls back to `honorCols` until needed.

### 2b. Role resolution

`kWledColorRoles` at [effect_preview_widget.dart:34-55](lib/features/wled/effect_preview_widget.dart#L34) is the seed of truth. The current entries (verbatim from that file):

| fx ID | Effect name | primary | background | accent |
|---|---|---|---|---|
| 1 | Blink | col[0] | col[1] | — |
| 13 | Scanner | col[0] | col[1] | — |
| 17 | Twinkle | col[0] | col[1] | — |
| 18 | Dissolve | col[0] | col[1] | — |
| 23 | Strobe | col[0] | col[1] | — |
| 28 | Chase 2 | col[0] | col[1] | col[2] |
| 40 | Scanner Dual | col[0] | col[1] | — |
| 41 | Running | col[0] | col[1] | — |
| 49 | Fairy | col[0] | col[1] | — |
| 51 | Fairytwinkle | col[0] | col[1] | — |
| 74 | Colortwinkles | col[0] | col[1] | — |
| 80 | Twinklefox | col[0] | col[1] | — |
| 81 | Twinklecat | col[0] | col[1] | — |
| 83 | Solid Pattern | col[0] | col[1] | col[2] |
| 87 | Glitter | col[0] | col[1] | — |

Effects not in this table use the default `WledColorRoles()` which is primary=col[0], background=null, accent=null — which means the dashboard's `_paintTwinklePath` is rendering Twinkle 17 with `colors.first` as the spark (wrong — col[0] in the cards is rendered as the spark via `primaryRole`, but `colors.first` is whatever the user picked first, which for "Classic Christmas" is red). The cards have it right; the dashboard has it wrong.

**Decision:** the unified interpreter resolves roles **once at `RenderedPattern` construction**:
```dart
final roles = _kFxHooks[fxId]?.roles ?? const {ColorRole.primary: 0};
final resolved = {
  for (final entry in roles.entries)
    entry.key: (entry.value < cols.length) ? cols[entry.value] : cols.first,
};
```
Painters never see col indices. They ask `rolesResolved[ColorRole.background]` and get a `Color` (or the primary as fallback when not mapped).

### 2c. Motion expression

`speed`, `intensity`, `groupSize`, `spacing`, `reverse` are all in `RenderedPattern` as normalized scalars. Primitives consume what's relevant — `Primitive.twinkle` uses `intensity`; `Primitive.solid` uses `groupSize`+`spacing`; `Primitive.chase` uses `speed`+`reverse`. The interpreter doesn't pre-filter — it passes the whole `RenderedPattern` and the primitive picks what it needs.

---

## 3. Per-effect hook table

### 3a. The motion primitives (proposed: 20)

These are the only things that need hand-tuned code. Each primitive is a single function `(Canvas, Size, List<Offset> ledPositions, RenderedPattern, double phase) → void`. The 20 below cover the audit's identified categories without 1:1 mapping to fx IDs:

| Primitive | One-line behavior |
|---|---|
| `solid` | Each LED = `rolesResolved[primary]`, optionally cycled by `groupSize`+`spacing` |
| `breathe` | All LEDs pulse `primary` brightness via sine on `phase` |
| `chase` | `primary` segments slide over a `background` fill, trail fades, `reverse` flips direction |
| `wipe` | Moving boundary transitions LEDs from `background` to `primary` |
| `scanner` | One soft `primary` beam ping-pongs over `background` |
| `twinkle` | `background` base + sparse `primary` sparks (count from `intensity`) |
| `sparkle` | `primary` base + rapid white flashes |
| `meteor` | Bright `primary` head with fading trail moves across |
| `fire` | Hardcoded warm gradient ignoring cols (matches `_FirePainter` decision at [effect_preview_widget.dart:776-836](lib/features/wled/effect_preview_widget.dart#L776)) |
| `fireworks` | Bursts at random positions, expand and fade |
| `ripple` | Concentric rings expand from center |
| `rainbow` | HSV sweep, used **only** when `paletteResolution == usePalette` |
| `strobe` | `primary` on for first half of phase, `background` for second |
| `ambient` | Slow drifting gradient between `primary`/`background`/`accent` |
| `noise` | Two overlapping radial gradients drift |
| `popcorn` | Circles rise from bottom and fade |
| `bouncing` | Multiple balls bounce with different speeds |
| `dripping` | Drops travel forward with exponential falloff |
| `explosive` | Random pixel groups fire each cycle, quadratic decay |
| `morphing` | Layered sine waves blend between `primary` and `background` |

These are the union of `RooflineLightPainter`'s 12 categories and `EffectPreviewWidget`'s 16 sub-painters, deduplicated. `LightEffectAnimator`'s 8 cases all map to one of these.

### 3b. The hook table

```dart
class FxHook {
  final MotionPrimitive primitive;
  final Map<ColorRole, int> roles; // ColorRole -> col index
  const FxHook({required this.primitive, this.roles = const {ColorRole.primary: 0}});
}

const Map<int, FxHook> _kFxHooks = {
  0:  FxHook(primitive: MotionPrimitive.solid),                                    // Solid
  1:  FxHook(primitive: MotionPrimitive.strobe,   roles: {primary: 0, background: 1}), // Blink
  2:  FxHook(primitive: MotionPrimitive.breathe),                                  // Breathe
  9:  FxHook(primitive: MotionPrimitive.rainbow),                                  // Rainbow (respectsColors:false; but pal:5 makes this honorCols → fall through to ?)
  11: FxHook(primitive: MotionPrimitive.rainbow),                                  // Rainbow Cycle
  13: FxHook(primitive: MotionPrimitive.scanner, roles: {primary: 0, background: 1}),
  17: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}),
  18: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}), // Dissolve
  23: FxHook(primitive: MotionPrimitive.strobe,  roles: {primary: 0, background: 1}),
  28: FxHook(primitive: MotionPrimitive.chase,   roles: {primary: 0, background: 1, accent: 2}),
  40: FxHook(primitive: MotionPrimitive.scanner, roles: {primary: 0, background: 1}),
  41: FxHook(primitive: MotionPrimitive.chase,   roles: {primary: 0, background: 1}),
  49: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}),
  51: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}),
  66: FxHook(primitive: MotionPrimitive.fireworks),
  74: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}),
  80: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}),
  81: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}),
  83: FxHook(primitive: MotionPrimitive.solid,   roles: {primary: 0, background: 1, accent: 2}), // Solid Pattern
  87: FxHook(primitive: MotionPrimitive.twinkle, roles: {primary: 0, background: 1}),
  // ... extends to cover Lumina's shipped pattern catalog
};
```

**Resolution for fx 9 / fx 11 (the bug):** with `pal:5` in the payload, the device honors cols, not the rainbow palette. So fx 9 with cols=[red,green] should render two-color cycling, not HSV rainbow. The fix is: `Primitive.rainbow` checks `pattern.paletteResolution` — if `honorCols`, fall through to a 2-3-color cycle using `rawCols` (essentially the `usePatternColors` branch already in [roofline_light_painter.dart:485-490](lib/widgets/roofline_light_painter.dart#L485)). The HSV branch only runs for `usePalette`.

### 3c. Fallback chain (graceful degradation)

Unknown fx IDs (firmware adds a new effect, Lumina suggests an exotic ID, etc.) flow through:

1. **Direct lookup** in `_kFxHooks`. Hit → use it.
2. **Category fallback** via `EffectDatabase.getEffect(fxId).motionType`:
   - `static` → `Primitive.solid`
   - `pulsing` → `Primitive.breathe`
   - `chasing` → `Primitive.chase` with `roles: {primary: 0, background: 1}`
   - `flowing` → `Primitive.wipe`
   - `twinkling` → `Primitive.twinkle` with `roles: {primary: 0, background: 1}`
   - `flickering` → `Primitive.fire`
   - `explosive` → `Primitive.explosive`
   - `scanning` → `Primitive.scanner`
   - `dripping` → `Primitive.dripping`
   - `bouncing` → `Primitive.bouncing`
   - `morphing` → `Primitive.morphing`
3. **Ultimate fallback:** unknown to `EffectDatabase` → `Primitive.solid` with col[0].

This means a new firmware effect renders *sensibly* instead of breaking, and the hook table only needs explicit entries for effects whose default role mapping is wrong (Twinkle family at col[1], multi-band Solid Pattern at col[2]).

### 3d. Maintenance estimate

Lumina ships a curated pattern catalog; a `Grep` for `effectId:` and `fx:` in `pattern_repository.dart` and the seed-pattern files would give the exact unique-ID count. From the audit's references and the existing tables: the **active set is ~25-40 unique fx IDs**, not 187. The hook table needs:

- ~20-25 explicit entries covering Lumina's shipped patterns.
- The 15 already in `kWledColorRoles` are the seed.
- All other fx IDs fall through the category chain.

That's a one-time table of ~30 lines, not a per-effect model file.

---

## 4. Migration path — 3-4 painters → 1

Phases ordered by blast radius (lowest first):

### Phase A — Cleanup (zero-risk)

Delete dead `arPreviewProvider` wiring. Confirmed: `startPreview` has zero production callers ([ar_preview_providers.dart:133](lib/features/ar/ar_preview_providers.dart#L133); Grep for `startPreview\(` returns only the definition itself). `arPreview.isActive` is checked at [animated_roofline_overlay.dart:103](lib/widgets/animated_roofline_overlay.dart#L103) and [animated_roofline_overlay.dart:126-131](lib/widgets/animated_roofline_overlay.dart#L126) but always returns `false` because nothing flips it true.

**Action:** delete the `else if (arPreview.isActive)` branch in `animated_roofline_overlay.dart` and the entire `ar_preview_providers.dart` `ARPreviewState`/`ARPreviewNotifier`/`arPreviewProvider`/`isPreviewModeProvider`/`previewColorsProvider`/`previewEffectIdProvider`. Keep `rooflineMaskProvider`, `useStockImageProvider`, `houseImageUrlProvider`, `hasCustomHouseImageProvider`, `EffectCategory`, `categorizeEffect`, `speedToDuration`, `speedToDurationForEffect` — those are used elsewhere.

**Effort:** ≤1 hr including verification grep. **Rollback:** trivial revert.

### Phase B — Build interpreter dormant (additive)

Create `lib/features/wled/preview/`:
- `rendered_pattern.dart` — `RenderedPattern`, `ColorRole`, `PaletteResolution`, `MotionPrimitive`, `FxHook`.
- `fx_hook_table.dart` — the `_kFxHooks` const map.
- `motion_primitives.dart` — the 20 primitive functions, each taking `(Canvas, Size, List<Offset>, RenderedPattern, double phase)`.
- `unified_preview_painter.dart` — `UnifiedRooflinePainter extends CustomPainter`, looks up primitive, calls it. Also `UnifiedStripPainter` and `UnifiedCardPainter` thin wrappers for the strip/card surface shapes.
- `preview_debug_screen.dart` — a debug-only screen rendering the unified painter beside each legacy painter for a list of representative patterns (Classic Christmas Twinkle fx 17, Solid Pattern fx 83, Chase fx 28, Rainbow fx 9, etc.). Behind `kDebugMode`.

Feature flag: a `const bool kUseUnifiedPreview = false;` constant. Nothing in production paths references the new code until phase C.

**Effort:** 1.5-2 dev-days (primitives are the meat — they're mostly ports of existing painter code, but each needs to read from `RenderedPattern.rolesResolved` instead of slot indices).

### Phase C — Migrate Lumina chat strip (lowest blast)

`LightPreviewStrip` is the smallest surface — used in [lumina_response_card.dart](lib/features/ai/lumina_response_card.dart), [lumina_adjustment_panel.dart](lib/features/ai/lumina_adjustment_panel.dart), and itself. Replace `LightEffectAnimator.computeFrame` + `LedGlowPainter` with `UnifiedStripPainter`.

- **File touched:** `light_preview_strip.dart`.
- **Rollback:** revert the file (one painter swap).
- **Verification:** open Lumina chat, send 5 suggestions covering: Solid (fx 0), Twinkle (fx 17), Chase (fx 28), Rainbow (fx 9), Fire (fx 66 fireworks or similar). Confirm side-by-side in the debug screen first.

**Effort:** 0.5 day.

### Phase D — Migrate EffectPreviewWidget (pattern cards)

Replace the 16 sub-painters in [effect_preview_widget.dart](lib/features/wled/effect_preview_widget.dart) with a single `CustomPaint(painter: UnifiedCardPainter(pattern: ...))`. The `kWledColorRoles` table at [effect_preview_widget.dart:34-55](lib/features/wled/effect_preview_widget.dart#L34) is already folded into `_kFxHooks` so deletes after the cutover.

- **Files touched:** `effect_preview_widget.dart` (gut and rewrite as thin wrapper), callers at `pattern_grid_widgets.dart` and `colorway_effect_selector.dart` (no API change if `EffectPreviewWidget(effectId:, colors:)` signature stays).
- **Rollback:** revert the file.
- **Verification:** scroll the pattern library, compare 20 cards visually against the legacy painters via the debug screen.

**Effort:** 1 day.

### Phase E — Migrate Edit Pattern preview

The Edit Pattern screen uses `EffectPreviewWidget` (confirmed via Grep at [colorway_effect_selector.dart](lib/features/wled/colorway_effect_selector.dart)) so phase D covers it automatically. No separate work.

**Effort:** 0 (included in D).

### Phase F — Migrate dashboard hero (highest blast)

`RooflineLightPainter` inside `AnimatedRooflineOverlay`. This is the painter every user sees every time they open the app, and it's the only one that handles multi-segment paths, `grp/spc/reverse`, and brightness/off states.

- **Files touched:** `animated_roofline_overlay.dart` (swap `RooflineLightPainter` for `UnifiedRooflinePainter` with `segmentPaths` extension), `roofline_light_painter.dart` (delete after F is stable for one release).
- **Rollback:** revert `animated_roofline_overlay.dart`. `roofline_light_painter.dart` stays present through phase F as the rollback target.
- **Verification:** dashboard smoke list of 10 patterns including multi-segment configs (Tyler's home with 2 channels: Front Roofline 0-128, Side Accent 128-188 per `MEMORY.md`), brightness slider sweep, power off, schedule preview.

**Effort:** 1-1.5 days (the multi-segment painter extension is where the time goes).

### Phase G — Delete legacy painters

After phases C-F have shipped one full release (≥1 store update for store users, ≥1 week for Tyler's tablet):

- Delete `lib/widgets/roofline_light_painter.dart`.
- Delete `lib/features/wled/effect_preview_widget.dart`'s internal painters (keep the public widget class as a thin wrapper if external code imports it).
- Delete `lib/features/ai/light_effect_animator.dart` (or keep as a public pure-function API if anything outside the strip uses it — Grep first).
- Delete the `kUseUnifiedPreview` flag and the debug screen.

**Effort:** ≤1 hr.

---

## 5. The Symptom 4 (drift) interaction

The audit also identified post-navigation drift (the WRONG-DATA symptom: dashboard shows the previous pattern for ~2 seconds after applying a new one, because the poll overwrites the local-preview sink before the device confirms). **Unification does not fix Symptom 4.** Symptom 4 is fixed by the state-sync work: every apply-path writer (`applyLocalPreview` at [wled_providers.dart:857](lib/features/wled/wled_providers.dart#L857), pattern-grid apply, Lumina apply, schedule apply) must write both the wled-state notifier and any preview sinks atomically, and suppress poll-overwrite for ~2s post-apply.

After unification, however, there's only **one** painter consuming `wledState.displayColors` + `effectId` + friends. A state-sync helper has one consumer to keep aligned instead of three. So:

- **Sequence option 1 (preferred):** state-sync fix first (~half a day), then unification phases A-G.
- **Sequence option 2:** parallel, since they touch different code (state writers vs painters). Risk: a state-sync change during phase F is harder to debug because two things changed.

Recommendation: do state-sync first. It's smaller and the unification is easier to reason about against a non-drifting baseline.

---

## 6. Honest ceiling — what unification CAN'T fix

The preview is a 2D Canvas paint of an estimated roofline arc. WLED is per-LED hardware with sub-frame timing, blending modes, and audio reactivity. The unified interpreter **will not match WLED frame-for-frame** for:

- **Audio-reactive effects** (Pacifica, audio-reactive Noise variants, peak meters). The device drives these from a hardware mic; the preview has no audio input. **Forever approximate** — render a stylized motion that *suggests* the effect class.
- **Palette-driven smooth interpolation** across long strips (Sunrise, Pacifica, Aurora). WLED uses specific interpolation curves and palette LUTs; matching them in Dart is feasible but expensive. "Close enough" is the target — same color family, same motion class, not pixel-identical.
- **Custom usermod effects.** WLED supports user-defined effects with ID > 187. The unified interpreter falls back to `Primitive.solid` (per §3c step 3). That's the right behavior.
- **Multi-segment payloads with `grp/spc` combinations across heterogeneous bus lengths.** The dashboard painter handles single-bus `grp/spc` correctly; cross-bus pattern composition (e.g., front roofline runs Chase while side accent runs Solid via Lumina multi-segment payloads) requires multiple `RenderedPattern` instances mapped to multiple segments — see §8.
- **WLED firmware effects added after this hook table ships.** They render via the fallback chain (sensible but generic) until a hook entry is added.

The preview is a *suggestion* of what the device will do. The contract is "same color family, same motion class, recognizable as the same pattern." It is not "frame-accurate device emulation."

---

## 7. Effort estimate

| Phase | Effort | Notes |
|---|---|---|
| A — Delete arPreviewProvider | ≤1 hr | Trivial |
| B — Build interpreter + table + debug screen | 1.5-2 dev-days | Primitive ports are the work |
| C — Migrate chat strip | 0.5 day | |
| D — Migrate pattern cards | 1 day | |
| E — Migrate Edit Pattern | 0 | Covered by D |
| F — Migrate dashboard hero | 1-1.5 days | Multi-segment is the slow part |
| G — Delete legacy painters | ≤1 hr | One-week wait after F ships |
| **Total** | **3-5 dev-days realistic** | **1 day minimum** if dropping the debug screen and shipping C+D+F as one merge — not recommended |

State-sync fix (Symptom 4) is separate: ~0.5 day, do before phase F.

---

## 8. Bonus connections

**Per-zone / per-area preview.** `RenderedPattern` is per-area by construction. The dashboard painter already accepts `List<SegmentPathData>` ([roofline_light_painter.dart:84](lib/widgets/roofline_light_painter.dart#L84)). The unified painter extends this to `Map<int channelIndex, RenderedPattern>` — each channel gets its own `RenderedPattern`, painted along its own polyline. This is how Commercial mode and future "different pattern per zone" UIs render in one painter call. The audit's per-zone vision drops in essentially free once `RenderedPattern` exists.

**Game Day / scheduled scene preview.** Today, the Autopilot Calendar screen has no preview for what a scheduled scene will look like. Once `RenderedPattern` is the canonical preview input, any caller — chat, autopilot, schedule list, Game Day "this team scored" trigger — can build one and render it through the same painter. "What does this scene look like?" becomes a one-line lookup.

**Future-proofing.** When WLED firmware adds new fx IDs (it does, every release), the fallback chain (§3c) handles them. No code change required for sensible degradation. Adding a hook entry is a one-line PR when a specific new effect ships in Lumina's catalog.

**Static Design Studio canvas.** [live_preview_canvas.dart](lib/features/design/widgets/live_preview_canvas.dart) renders colored containers with no motion — it's a static composition tool, not a motion preview. It reads from `composedPatternProvider`, not from any of the four painters. Recommendation: **out of scope** for unification. If Design Studio needs motion preview later, it can adopt `RenderedPattern` then.

---

## 9. Open questions for Tyler

1. **Preview source-of-truth: as-sent payload or polled device state?** The audit found these diverge. As-sent is full-fidelity (we know exactly what we asked for); polled is lossy (WLED's `/json/state` doesn't echo back every parameter cleanly, and there's a 1.5s poll lag). The unified interpreter could be wired to either via `applyLocalPreview` ([wled_providers.dart:857](lib/features/wled/wled_providers.dart#L857)) or `_applyStateData` ([wled_providers.dart:462](lib/features/wled/wled_providers.dart#L462)). Current code uses both inconsistently. Pick one as the canonical preview source.

2. **Lumina chat strip — unify or keep simple?** `LightEffectAnimator` produces a `List<Color>` frame consumed by `LedGlowPainter` which renders glowing dots — friendly on small horizontal strips, very different visual character than the dashboard roofline. Unifying loses that character unless `UnifiedStripPainter` reimplements the glow-bloom look. Is the chat strip's distinct visual style **intentional** (cozy chat aesthetic) or **accidental** (just how it got built)? If intentional, the chat strip should stay on `LightEffectAnimator` and unification only covers cards + dashboard.

3. **Is phase A (delete `arPreviewProvider`) safe to ship standalone?** It's net deletion with no callers. Recommendation: yes, ship it as its own PR ahead of the unification work — it cleans up the import graph and removes a confusing dead-state branch from `animated_roofline_overlay.dart`.

4. **Acceptable approximation ceiling for audio-reactive effects.** Confirm: render them as "stylized motion in the right color family, no audio response" is acceptable, or do we need a fake audio-envelope generator to make them look more dynamic in the preview?

5. **`live_preview_canvas.dart` in or out of scope?** Recommendation: out, but Tyler may want a single visual language across both static (Design Studio) and motion (everywhere else) previews. If yes, scope grows by ~1 day.

6. **Should `paletteResolution` be inferred or explicit?** Current proposal: always `honorCols` because the payload always sets `pal:5`. But the day Lumina adds palette-driven AI suggestions, this becomes a per-pattern field that AI must set. Decide now whether `RenderedPattern.paletteResolution` is a constant constructor default or a required field — cheaper to require it now than to migrate later.
