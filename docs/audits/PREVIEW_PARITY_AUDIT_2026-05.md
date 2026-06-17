# Preview Parity Audit — Pattern Detail vs Now Playing

**Author:** Claude (read-only audit)
**Date:** 2026-05-27
**Goal:** Identify why the pattern detail card preview and the Now Playing
home-screen preview render visibly different output for the same applied
state. Visual parity is the requirement; structural unification is **not**
in scope. No code changes.

---

## TL;DR

Both surfaces use the **same widget** ([AnimatedRooflineOverlay](../../lib/widgets/animated_roofline_overlay.dart#L19))
and the **same painter** ([RooflineLightPainter](../../lib/widgets/roofline_light_painter.dart#L43)).
The painter is shared, so interpretation parity is automatic. **The
divergence is entirely in the inputs** each surface hands the widget.

Five concrete input differences, in descending order of visual impact:

1. **`previewColors` source diverges.** The detail card reads from
   `widget.paletteNode.themeColors` (the pattern's intended colors, frozen
   in catalog metadata). Now Playing reads `wledState.displayColors` —
   which is rebuilt every poll from the device's `seg[0].col[]` array.
   After a 3.5s post-apply suppression window, **stale-slot bleed** from
   the prior pattern (Bug B in [project_preview_followups_2026_05_22.md](../project_preview_followups_2026_05_22.md))
   poisons the dashboard list while the detail card stays clean.
2. **`brightness` is dropped on the detail card.** Detail card omits the
   parameter → `AnimatedRooflineOverlay` defaults to **255**. Dashboard
   passes `state.brightness`. Detail card always renders at full
   brightness; dashboard scales LED dot luminance to the device setting.
3. **`forceOn` differs.** Detail card passes `true` (always lit).
   Dashboard passes `state.isOn` (respects power state).
4. **`colorGroupSize` / `spacing` source diverges.** Detail card reads
   `selectorColorGroupProvider` / `selectorSpacingProvider` — the local
   slider state. Dashboard reads `state.colorGroupSize` / `state.spacing` —
   parsed from polled `seg[0].grp` / `seg[0].spc`. Outside the suppression
   window these can disagree (e.g. slider was changed but device hasn't
   yet echoed `grp` back, or vice versa).
5. **Dashboard wraps the overlay in opacity + ambient glow + sky tint.**
   `AnimatedOpacity(opacity: isFresh ? 1.0 : 0.5)` halves the LED render
   when state is stale; `_SkyGradientOverlay` washes the photo with sky
   color; `_AmbientLedGlow` adds a bottom edge wash tinted by
   `displayColors.first`. Detail card has none of these chrome layers.

The **primary user-perceptible** difference is #1 (stale colors bleeding
into Now Playing). #2 explains why the same pattern can look "more vivid"
on the detail card. #5 is a cosmetic style difference that nudges the eye
even when inputs are identical.

The detail card is closer to "correct" for representing the *requested
pattern*. The dashboard is closer to "correct" for representing the
*device's actual current state*. They're solving different problems with
the same painter, which is why they don't agree.

Pre-existing design proposals at [docs/unified_preview_interpreter_design_2026-05-22.md](../unified_preview_interpreter_design_2026-05-22.md)
and [scripts/preview_unification_design_2026-05-22.md](../../scripts/preview_unification_design_2026-05-22.md)
address a *different* parity problem (between the roofline painter, the
14-effect card painter, and the Lumina chat strip — three different
painters). Those docs don't cover this audit's case because **this case
has no painter divergence**. Their fixes would not move the needle here.

---

## Step 1 — The two renderers

### Detail card preview (post-Explore→category→pattern)

Navigation: `/explore/:categoryId` → `CategoryDetailScreen` →
`/explore/:categoryId/sub/:subId` → `ThemeSelectionScreen` → on tile tap
opens [ColorwayEffectSelectorPage](../../lib/features/wled/colorway_effect_selector.dart#L47).

Roofline preview built in [_buildRooflinePreview](../../lib/features/wled/colorway_effect_selector.dart#L776).
Rendering call at [colorway_effect_selector.dart:826](../../lib/features/wled/colorway_effect_selector.dart#L826):

```dart
AnimatedRooflineOverlay(
  previewColors: _isBrightnessGradient
      ? _gradientColorsForPreset(ref.watch(selectorGradientPresetProvider))
      : _paletteColors,
  previewEffectId: effectId,
  previewSpeed: speed,
  forceOn: true,
  targetAspectRatio: constraints.maxWidth / constraints.maxHeight,
  useBoxFitCover: true,
  colorGroupSize: ref.watch(selectorColorGroupProvider),
  spacing: ref.watch(selectorSpacingProvider),
)
```

**Inputs passed:**

| Parameter | Value source |
|---|---|
| `previewColors` | `widget.paletteNode.themeColors` (catalog metadata), or `_gradientColorsForPreset(...)` for brightness-gradient patterns |
| `previewEffectId` | `effectId` (local effect-selector grid selection) |
| `previewSpeed` | `speed` (local `selectorSpeedProvider`) |
| `forceOn` | hard-coded `true` |
| `targetAspectRatio` | `constraints.maxWidth / constraints.maxHeight` |
| `useBoxFitCover` | `true` |
| `colorGroupSize` | `selectorColorGroupProvider` (local slider) |
| `spacing` | `selectorSpacingProvider` (local slider) |
| `brightness` | **omitted** (defaults to 255 inside overlay) |
| `imageAlignment` | omitted (defaults to `Offset.zero`) |
| `backgroundColor` | omitted (defaults to `0xFF000000`) |
| `mask` | omitted (overlay falls through to `ref.watch(rooflineMaskProvider)`) |

Surrounding chrome:
- House image (`profile.housePhotoUrl` or `Demohomephoto.jpg`) at the
  back ([colorway_effect_selector.dart:797](../../lib/features/wled/colorway_effect_selector.dart#L797)).
- A single bottom→top legibility gradient overlay ([colorway_effect_selector.dart:807](../../lib/features/wled/colorway_effect_selector.dart#L807)).
- 140px fixed height, rounded 16px container.

### Now Playing preview (home dashboard)

Lives in the hero card in [_WledDashboardPageState](../../lib/features/dashboard/wled_dashboard_page.dart#L600).
Rendering call at [wled_dashboard_page.dart:634](../../lib/features/dashboard/wled_dashboard_page.dart#L634):

```dart
AnimatedRooflineOverlay(
  previewColors: state.displayColors,
  previewEffectId: state.effectId,
  previewSpeed: state.speed,
  brightness: state.brightness,
  forceOn: state.isOn,
  targetAspectRatio: targetAspectRatio,
  imageAlignment: Offset.zero,
  useBoxFitCover: true,
  colorGroupSize: state.colorGroupSize,
  spacing: state.spacing,
)
```

**Inputs passed:**

| Parameter | Value source |
|---|---|
| `previewColors` | `state.displayColors` — getter on `WledStateModel`: `colorSequence.isNotEmpty ? colorSequence : [color]` ([wled_models.dart:103](../../lib/features/wled/wled_models.dart#L103)) |
| `previewEffectId` | `state.effectId` (polled or applyPreviewSync-written) |
| `previewSpeed` | `state.speed` |
| `brightness` | **`state.brightness`** |
| `forceOn` | **`state.isOn`** |
| `targetAspectRatio` | `constraints.maxWidth / constraints.maxHeight` |
| `imageAlignment` | `Offset.zero` (explicit) |
| `useBoxFitCover` | `true` |
| `colorGroupSize` | `state.colorGroupSize` |
| `spacing` | `state.spacing` |

Surrounding chrome (in z-order from back to front):
- House image (custom or `Demohomephoto.jpg`).
- `_SkyGradientOverlay(skyTheme: _currentSkyTheme)` — wraps photo with
  time-of-day sky tint ([wled_dashboard_page.dart:621-623](../../lib/features/dashboard/wled_dashboard_page.dart#L621)).
- **`AnimatedOpacity(opacity: isFresh ? 1.0 : 0.5)`** wrapping the
  overlay — dims preview to 50% when `wledStateFreshProvider` is false
  ([wled_dashboard_page.dart:631-633](../../lib/features/dashboard/wled_dashboard_page.dart#L631)).
- Bottom→top legibility gradient at `bottom: 24` ([wled_dashboard_page.dart:654-668](../../lib/features/dashboard/wled_dashboard_page.dart#L654)).
- `_AmbientLedGlow(color: displayColors.first)` — adds a bottom edge
  glow tinted to the first display color ([wled_dashboard_page.dart:670-680](../../lib/features/dashboard/wled_dashboard_page.dart#L670)).
- Now Playing bar (frosted glass with effect name, brightness slider,
  power button).

### Shared painter contract

`AnimatedRooflineOverlay.build` normalizes its inputs at [animated_roofline_overlay.dart:117-131](../../lib/widgets/animated_roofline_overlay.dart#L117):

- When `previewColors != null` (both surfaces always pass it):
  - `effectiveColors = widget.previewColors!`
  - `effectiveEffectId = widget.previewEffectId ?? 0`
  - `effectiveSpeed = (rawSpeed * 0.5).round().clamp(0, 150)` ← *speed is halved and clamped at 150*
  - `effectiveBrightness = widget.brightness ?? 255`
  - `isOn = widget.forceOn ?? true`
  - `effectiveReverse = false` ← **NEVER set from device state in preview mode**
- `intensity` is hard-coded to **128** before being handed to the painter
  ([animated_roofline_overlay.dart:176](../../lib/widgets/animated_roofline_overlay.dart#L176)).
- Mask + segment paths come from `currentRooflineConfigProvider` /
  `rooflineMaskProvider` — identical on both surfaces.

`RooflineLightPainter` is the same instance type with identical paint
behavior. Each surface owns its own `AnimationController` (independent
phase), but `_controller.duration` is driven the same way on both via
`speedToDurationForEffect(effectiveSpeed, category)`.

---

## Step 2 — Input parity: what each surface sees

Concrete example: user applies **Blue Wave + Chase motion** from the
detail card.

### Inputs on the detail card (steady state)

| Field | Value |
|---|---|
| `previewColors` | `paletteNode.themeColors` → e.g. `[Color(0xFF0066FF), Color(0xFF66CCFF)]` (2 colors, exactly the pattern's design) |
| `previewEffectId` | `_effectiveEffectId(selectedId)` → if selectedId=0 and 2 colors → **substitutes 83** (Solid Pattern); else the raw effect ID |
| `previewSpeed` | `selectorSpeedProvider` (slider, 0-255) |
| `brightness` | not passed → defaults to **255** |
| `forceOn` | `true` |
| `colorGroupSize` | `selectorColorGroupProvider` (slider) |
| `spacing` | `selectorSpacingProvider` (slider) |

### Inputs on Now Playing immediately after Apply

`_applyPattern` calls `applyPreviewSync(colors: previewColors, ...)` at
[colorway_effect_selector.dart:317](../../lib/features/wled/colorway_effect_selector.dart#L317),
which calls `applyLocalPreview` ([wled_providers.dart:985-1009](../../lib/features/wled/wled_providers.dart#L985)):

```dart
state = state.copyWith(
  isOn: true,
  colorSequence: colors,           // ← the same List<Color> the detail card uses
  color: colors.isNotEmpty ? colors.first : Colors.white,
  effectId: effectId,
  speed: speed,
  intensity: intensity,
  brightness: brightness,          // ← always 255 from the colorway selector caller
  customEffectName: effectName,
  colorGroupSize: colorGroupSize,  // ← from selector slider
  spacing: spacing,                // ← from selector slider
);
_lastLocalApplyAt = DateTime.now();
```

Within the next **3500ms** ([wled_providers.dart:403-404](../../lib/features/wled/wled_providers.dart#L403)),
`_isPollOverwriteSuppressed()` returns true and `_applyStateData` skips
writes to the visual fields ([wled_providers.dart:640-649](../../lib/features/wled/wled_providers.dart#L640)).

**In this window the two surfaces have nearly identical inputs.** The
only divergences inside the suppression window are:

- `brightness`: detail = 255 (default), dashboard = 255 (from applyLocalPreview default). **Match.**
- `forceOn`: detail = `true`, dashboard = `state.isOn` which is `true` (set by applyLocalPreview). **Match.**
- `previewColors`: identical `List<Color>` (handed through).
- `colorGroupSize` / `spacing`: identical (handed through).
- `previewEffectId`: identical (`fxId` = `_effectiveEffectId(...)`).
- `previewSpeed`: identical (whatever `selectorSpeedProvider` was).

### Inputs on Now Playing after the 3.5s suppression window

Polling resumes; `_applyStateData` writes the polled `seg[0]` into state.

`seg[0].col[]` is parsed at [wled_providers.dart:605-637](../../lib/features/wled/wled_providers.dart#L605):

```dart
for (final c in cols) {
  if (c is List && c.length >= 3) {
    final rr = (c[0] as num).toInt().clamp(0, 255);
    final gg = (c[1] as num).toInt().clamp(0, 255);
    final bb = (c[2] as num).toInt().clamp(0, 255);

    if (rr > 0 || gg > 0 || bb > 0) {
      colorSequence.add(Color.fromARGB(255, rr, gg, bb));   // ← every non-zero slot
    }
    ...
  }
}
```

**This is the stale-slot bleed described in [Bug B](../project_preview_followups_2026_05_22.md#bug-b--stale-color-slots-preview-blend-symptom).**
WLED's partial-col-update behavior leaves prior values in unwritten
slots. When the previous pattern wrote 3 colors (red/white/blue) and the
new pattern writes only 1 (blue), the device's polled `col[]` returns
all three, and the dashboard renders all three. The detail card, still
reading from `widget.paletteNode.themeColors`, is unaffected — its color
list is frozen catalog metadata, not poll-derived.

After the window closes there are also derived differences in:
- `state.brightness`: polled `bri` may differ from the 255 the apply
  forced. Now Playing dims; detail card stays at 255.
- `state.colorGroupSize` / `state.spacing`: polled `grp` / `spc` reflect
  device state, not slider state. If the user has been twisting sliders
  after Apply, the detail card shows slider values and Now Playing shows
  device-echoed values.
- `state.isOn`: if the user power-cycles the device externally, the
  dashboard goes dark. Detail card keeps rendering (`forceOn: true`).

### Divergence checklist

| Aspect | Inside 3.5s window | After 3.5s window |
|---|---|---|
| `previewColors` length / order | match | **DIVERGE** (poll re-adds stale non-zero slots) |
| `previewEffectId` | match | match (poll re-confirms same fx) |
| `previewSpeed` | match | match unless slider changed |
| `brightness` | match (both effectively 255) | **DIVERGE** if user later moves the dashboard's brightness slider (detail stays 255) |
| `forceOn` / `isOn` | match | **DIVERGE** on external power off |
| `colorGroupSize` / `spacing` | match | **DIVERGE** when poll echoes a value different from selector slider state |
| `intensity` consumed by painter | match (both hard-coded 128 in overlay) | match |
| `reverse` consumed by painter | match (both forced `false` because `previewColors != null`) | match |
| Roofline mask + segment paths | match (same providers) | match |
| Effect-ID → category resolution | match | match |
| RGBW conversion | n/a — both pass `List<Color>` (RGB) directly to painter | n/a |

**No** input field is normalized differently between the two surfaces.
The divergence comes from **different sources for the same fields**.

---

## Step 3 — Interpretation parity: how the painter renders the inputs

Both surfaces hand inputs to `RooflineLightPainter` via the same
`AnimatedRooflineOverlay`. The painter handles them identically.

### Animation

- Both surfaces own a `_controller` instance ([animated_roofline_overlay.dart:81-89](../../lib/widgets/animated_roofline_overlay.dart#L81))
  with the same `Duration(seconds: 2)` initial period.
- `_controller.duration` is updated each build via `speedToDurationForEffect(effectiveSpeed, category)`.
- Animation runs (`_controller.repeat()`) for any non-`solid` category,
  stops for solid ([animated_roofline_overlay.dart:137-151](../../lib/widgets/animated_roofline_overlay.dart#L137)).
- The two controllers are **not phase-locked**. At any instant they're
  at different `_controller.value` positions. For a chase or scanner
  effect the two previews show the lead pixel in different places. This
  is fine for "is this the same pattern?" parity but they'll never look
  pixel-identical at the same wall-clock instant.

### Spacing / density

`colorGroupSize` and `spacing` are passed through to the painter and
honored identically. The interpretation is the same; only the source
diverges (Step 2). Both surfaces correctly render `1 On 2 Off` style
patterns when their respective sources agree.

### Color blend / multi-color gradient

`RooflineLightPainter` picks color per-pixel via index-modulo against
`colors` (with `colorGroupSize` grouping). Both surfaces use the same
logic. Multi-color patterns will look the same **when given the same
color list** — which, again, is exactly where Step 2 diverges.

### Brightness

`brightnessFactor = brightness / 255.0` ([roofline_light_painter.dart:112](../../lib/widgets/roofline_light_painter.dart#L112))
and `if (!isOn || colors.isEmpty || brightness == 0) return;` early-out
([roofline_light_painter.dart:108](../../lib/widgets/roofline_light_painter.dart#L108)).

- Detail card: `brightness = 255` always → `brightnessFactor = 1.0`.
- Now Playing: `brightness = state.brightness` (typically 100-200) →
  `brightnessFactor < 1.0` and LEDs render dimmer. **Visible.**

### Roofline mask / segment boundaries

Both read the same `currentRooflineConfigProvider` / `rooflineMaskProvider`
inside the overlay. Multi-channel segments are honored identically on
both surfaces. No divergence.

### Other painter behavior (notes for completeness)

- `intensity` is hard-wired to **128** by the overlay regardless of
  what `state.intensity` or `selectorIntensityProvider` says. Twinkle
  density is identical on both surfaces but won't reflect the user's ix
  slider on either.
- `reverse` is **always false** in preview mode because the `else` branch
  of [animated_roofline_overlay.dart:117](../../lib/widgets/animated_roofline_overlay.dart#L117)
  only runs when `previewColors == null`. Both surfaces always pass
  `previewColors`, so neither reflects `seg[0].rev`. (Pre-existing bug,
  same on both surfaces.)

---

## Step 4 — Fidelity parity (chrome around the overlay)

Even with identical painter output, the surrounding visual style
biases perception:

| Layer | Detail card | Now Playing |
|---|---|---|
| Container height | Fixed 140px | LayoutBuilder, ≥300px (`naturalHeight = maxWidth * 492/994`, clamped) |
| Border | `Border.all(NexGenPalette.line)` 1px | None on the photo card |
| Border radius | 16 | None at the photo level; Now Playing bar uses 16 separately |
| Background photo | `housePhotoUrl` or `Demohomephoto.jpg`, `BoxFit.cover` | Same source, same fit |
| Sky overlay | **None** | `_SkyGradientOverlay(skyTheme:)` — time-of-day sky tint over the photo |
| Legibility gradient | Single bottom→top dark gradient, full height | Bottom→top dark gradient anchored to `bottom: 24, height: 130` |
| LED render | `AnimatedRooflineOverlay` directly | `AnimatedOpacity(opacity: isFresh ? 1.0 : 0.5)` wrapping the overlay |
| Ambient floor wash | **None** | `_AmbientLedGlow(color: displayColors.first)` adds a bottom-edge glow tinted by the first color |
| Overlaid controls | None over the preview | Now Playing bar, power button, add-photo button, "Last Known State" chip |
| Canvas resolution / scale | Painter renders to LayoutBuilder constraints (≤140px tall) | Painter renders to ≥300px tall |
| LED dot size | Computed by painter from path length; same code | Same code, but bigger canvas → bigger dots |

**Implications:**

- The dashboard render is physically larger (~2× taller). Same LED count
  along the path means dot pitch is larger on the dashboard → dots
  appear visually denser/brighter. Detail card preview always feels
  "smaller and tighter."
- `_SkyGradientOverlay` tints the photo behind the dashboard LEDs.
  Detail card has a flat, untinted photo. This shifts the perceived
  color of every LED.
- `_AmbientLedGlow` adds a bottom-edge color wash on the dashboard that
  doesn't exist on the detail card. Bias toward `displayColors.first`.
- Stale-data dimming (`AnimatedOpacity 0.5`) on the dashboard has no
  counterpart on the detail card. When polls are slow or the device is
  unresponsive, the dashboard preview is *deliberately* half-bright.

---

## Step 5 — Diff summary + fix proposal

### Diff table

| Aspect | Detail card behavior | Now Playing behavior | Visible difference? | Fix candidate |
|---|---|---|---|---|
| `previewColors` source | `paletteNode.themeColors` (catalog) | `state.displayColors` (polled `col[]`, includes stale slots) | **Yes** — primary perceived divergence | Fix payload-construction to pad unused `col` slots with `[0,0,0]` (Bug B fix at `wled_payload_utils.dart`). Once device returns clean slots, the `if (rr > 0 || gg > 0 || bb > 0)` guard in `_applyStateData` keeps `colorSequence` to only the intended colors. |
| `previewEffectId` source | local selector | polled `seg[0].fx` | No (poll echoes same fx after Apply) | None needed |
| `previewSpeed` source | local selector | polled `seg[0].sx` | No | None needed |
| `brightness` value | omitted → defaults to **255** | `state.brightness` (whatever device reports) | **Yes** — detail always at full brightness | Either (a) pass `brightness: state.brightness` on the detail card so it matches device dimming, or (b) explicitly pass `brightness: 255` on the dashboard for "what does this pattern look like at full brightness" semantics. Pick which surface defines "correct." |
| `forceOn` value | `true` | `state.isOn` | Only when device is off | Same choice — detail = "this pattern" semantic; dashboard = "current device" semantic |
| `colorGroupSize` / `spacing` source | local sliders | polled `grp`/`spc` | Sometimes — when slider edits race the poll | Already fixed inside the 3.5s window. Outside the window, polled values are correct device state. Could extend suppression to 5-6s if mismatch is observed but the slider->device race is small. |
| `intensity` consumed | hard-coded 128 | hard-coded 128 | No | (Pre-existing bug — neither surface honors `ix`. Fix would touch the overlay, not parity.) |
| `reverse` consumed | hard-coded false | hard-coded false | No | (Pre-existing bug — preview mode never reads `seg.rev`.) |
| Animation phase alignment | independent controller | independent controller | Yes for moving effects, but two instances of the same surface would also diverge | Out of scope — phase locking would need a shared controller, structural change. |
| Container size / dot pitch | 140px tall, fixed | ≥300px tall, photo-aspect | **Yes** (visual density) | Out of scope — these are separate surfaces with separate layout intents. |
| Sky tint over photo | **none** | `_SkyGradientOverlay` | **Yes** (background color shift) | Add `_SkyGradientOverlay` to detail card *or* remove from dashboard. Recommend keep on dashboard (time-of-day ambience is intentional) and accept this as a deliberate chrome difference. |
| Ambient floor glow | **none** | `_AmbientLedGlow` | **Yes** | Same — chrome difference; intentional on dashboard. |
| Stale-data dimming | **none** | `AnimatedOpacity(isFresh ? 1.0 : 0.5)` | Yes when poll is stale | Chrome difference. Detail card has no notion of staleness — its color source is the catalog, which is never stale. |

### Which surface is "correct"?

Neither is strictly correct — they answer different questions:

- **Detail card** answers *"What does this pattern look like, idealized?"*
  Uses catalog colors, hard-codes full brightness and always-on, ignores
  device state.
- **Now Playing** answers *"What is the device actually rendering right
  now?"* Uses polled state, respects brightness/power, reflects whatever
  the device has actually written into its `col[]` array.

For the **user-facing "they should agree" requirement**, the dashboard
is the surface that needs correcting — not because its semantic is
wrong, but because its data source has a known integrity problem
(stale-slot bleed) and it dims more aggressively than the detail card.

### Minimum change set to close the visible gap

In priority order, smallest blast radius first:

1. **Fix the payload-construction stale-slot bleed** (Bug B preferred
   fix in [project_preview_followups_2026_05_22.md §B](../project_preview_followups_2026_05_22.md#preferred-fix)).
   Pad `col[]` to 3 slots with `[0,0,0]` in the payload builders. This
   forces WLED to clear stale slots on every apply. After this, the
   dashboard's polled `colorSequence` matches the detail card's
   `paletteNode.themeColors` for the same pattern. **~half-day, contained
   to one file. Single biggest visual parity win.**
2. **Decide a brightness semantic for the detail card preview.**
   Either (a) pass `brightness: state.brightness` so it dims with the
   device, matching Now Playing — or (b) leave it at 255 with the
   intent "what this pattern looks like at full intensity" and accept
   the difference. If (a): one-line change at
   [colorway_effect_selector.dart:826](../../lib/features/wled/colorway_effect_selector.dart#L826).
3. **Decide a `forceOn` semantic** the same way. Recommend (b) — the
   detail card is a pattern preview, not a device-state mirror; users
   would be confused if the detail card went dark when they powered the
   device off.
4. **Accept the chrome differences (sky overlay, ambient glow, stale
   opacity) as intentional.** They're deliberate dashboard polish, not
   accidents. Removing them flattens the dashboard's premium feel for
   marginal parity gain.
5. **`grp`/`spc` race**: if observed in practice, extend
   `_kLocalApplyPollSuppressWindow` from 3500ms → ~5000ms. Cheap; only
   tweaks a constant.

**Single highest-leverage fix:** Bug B payload padding. That alone makes
the detail card and Now Playing render the same colors for the same
applied pattern. Everything else in the diff table is either a
deliberate chrome difference or a low-frequency edge case.

---

## Notes on parallel-session design docs

Two design docs already exist:

- [docs/unified_preview_interpreter_design_2026-05-22.md](../unified_preview_interpreter_design_2026-05-22.md)
- [scripts/preview_unification_design_2026-05-22.md](../../scripts/preview_unification_design_2026-05-22.md)

**What they cover:** the painter-level fragmentation between
`RooflineLightPainter` (used by `AnimatedRooflineOverlay`),
`EffectPreviewWidget`'s 14 sub-painters (pattern grid tiles in
`pattern_grid_widgets.dart` and Edit Pattern), and
`LightEffectAnimator` (Lumina chat strip). Three painters with three
different effect-bucket tables, three different palette interpretations.

**What they don't cover (and isn't needed for):** this audit's case.
The two surfaces in question — pattern detail card preview *roofline*
and Now Playing dashboard *roofline* — both consume
`AnimatedRooflineOverlay` + `RooflineLightPainter`. Their divergence is
**100% upstream of the painter**, in the inputs each surface chooses.
A unified interpreter wouldn't change either surface's input source, so
the visible gap (Bug B stale-slot bleed + brightness/forceOn semantics)
survives unification.

The unification work is still valuable for the *other* painter parity
problem (chat strip vs. pattern card thumbnails vs. dashboard roofline
all disagreeing on the same effect). It should not be conflated with
this audit's gap.

Do not touch the AI / preview interpreter design — that's parallel
session territory and the design proposals there have not been adopted.
The fix paths in §5 above are independent of that work.
