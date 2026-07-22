# Unified Preview Interpreter — Design Proposal

**Author:** Claude (design exploration, read-only)
**Date:** 2026-05-22
**Status:** PROPOSAL — for Tyler's review. No production code changed.
**Scope:** Plan the consolidation of 3–4 preview painters into one effect
interpreter that correctly handles palettes and degrades gracefully for
unknown WLED effects. Touches preview rendering only; the WLED apply
path (`pattern_models.dart::toWledPayload`) is unchanged.

---

## 0. The Problem in One Paragraph

The roofline preview ([widgets/animated_roofline_overlay.dart](../lib/widgets/animated_roofline_overlay.dart) →
[widgets/roofline_light_painter.dart](../lib/widgets/roofline_light_painter.dart)),
the pattern-card thumbnail
([features/wled/effect_preview_widget.dart](../lib/features/wled/effect_preview_widget.dart)),
and the Lumina chat strip
([features/ai/light_preview_strip.dart](../lib/features/ai/light_preview_strip.dart) →
[features/ai/light_effect_animator.dart](../lib/features/ai/light_effect_animator.dart))
each have their own effect-category table and motion model. They disagree
with each other and — more importantly — with what the WLED device
actually renders. The audit symptoms (palette ignored, ~187 effects
crushed into 12 buckets, AI chat using a 4th painter with 8 buckets) all
stem from this fragmentation. There is also a dead AR-mode preview
notifier ([features/ar/ar_preview_providers.dart](../lib/features/ar/ar_preview_providers.dart))
still being read by `AnimatedRooflineOverlay`, plus an inverted
palette-truth issue: the *payload* forces `pal: 5` (Colors Only) so the
device renders user `col` slots, but the preview painter routes
`respectsColors:false` effects to a hardcoded HSV rainbow, so the card
shows rainbow while the strip shows the user's colors.

---

## 1. Inventory of Painters and Their Inputs

### 1.1 The four painters

| # | File | What it draws | Lives where | Animation owner |
|---|---|---|---|---|
| 1 | `RooflineLightPainter` ([widgets/roofline_light_painter.dart:43](../lib/widgets/roofline_light_painter.dart#L43)) | Per-pixel LED dots traced along the roofline mask/polyline; "best" of the four | `AnimatedRooflineOverlay` (dashboard, demo, pattern explore, edit, autopilot detail) | `AnimationController` in overlay (`_controller.value` 0–1) |
| 2 | `EffectPreviewWidget` sub-painters ([features/wled/effect_preview_widget.dart:141](../lib/features/wled/effect_preview_widget.dart#L141)) | 14 separate small `CustomPainter`s (Breathe/Wipe/Chase/Scanner/Sparkle/Meteor/Fire/Fireworks/Ripple/Rainbow/Strobe/Ambient/Noise/Popcorn) drawn into the card tile | Pattern grid tiles, `ColorwayEffectSelectorPage` | Per-widget `AnimationController` |
| 3 | `LightEffectAnimator` + `LedGlowPainter` ([features/ai/light_effect_animator.dart:63](../lib/features/ai/light_effect_animator.dart#L63), [features/ai/light_preview_strip.dart](../lib/features/ai/light_preview_strip.dart)) | Pure-function frame computer → strip of glowing dots; 8 effect types only | Lumina chat (`LightPreviewStrip`) | Per-widget `AnimationController` |
| 4 | `arPreviewProvider` notifier ([features/ar/ar_preview_providers.dart:128](../lib/features/ar/ar_preview_providers.dart#L128)) | **Not a painter.** Optional override state that `AnimatedRooflineOverlay` reads. Effectively dead path — no UI currently calls `startPreview()` (Lumina uses the strip, not the overlay). | (read by overlay only) | (no animation) |

> #4 is "state plumbing" not a painter. The audit may have been counting
> it as a fragmentation source because `AnimatedRooflineOverlay` does
> branching on it. The cleanest move is to delete it outright in Phase 1.

### 1.2 The full union of inputs each consumes

| Input | RooflineLightPainter | EffectPreviewWidget | LightEffectAnimator | Notes |
|---|---|---|---|---|
| `effectId` (WLED fx) | ✅ → `categorizeEffect()` → 12 bucket enum | ✅ → `getPreviewType()` → 16 bucket enum (different IDs!) | ✅ → `effectTypeFromWledId()` → 8 bucket enum (different IDs again) | **Disagreement #1: three lookup tables for the same fx ID** |
| `colors: List<Color>` | ✅ + `_getColorForLed` rotation | ✅ via `primary`/`secondary`/`tertiary` + `kWledColorRoles` overrides | ✅ by `i % colors.length` | Only EffectPreview applies role-aware slot mapping |
| `paletteId` (`pal` field) | ❌ ignored | ❌ ignored | ❌ ignored | **Disagreement #2: payload forces `pal:5` but no preview is aware** |
| `speed` (sx, 0–255) | ✅ via `speedToDurationForEffect` (overlay) | ❌ — hard-coded `Duration` per type | ✅ via `durationForEffect(speed)` | Three different speed-to-duration curves |
| `intensity` (ix, 0–255) | ✅ used in twinkle | ❌ ignored | ❌ ignored | Two surfaces don't read it |
| `brightness` (bri, 0–255) | ✅ as scale + early-out | ❌ ignored | ✅ as 0–1 brightness | EffectPreview doesn't dim |
| `colorGroupSize` (`grp`) | ✅ | ❌ | ❌ | Only roofline understands repeating bands |
| `spacing` (`spc`) | ✅ | ❌ | ❌ | Same |
| `reverse` (seg.rev) | ✅ | ❌ | ❌ | Same |
| `isOn` | ✅ | (n/a — card is never "off") | (n/a — strip is never "off") | |
| Backdrop color (off pixels) | ✅ | partial — some painters dim col[1] | ❌ | |
| Custom path/mask | ✅ multi-segment & legacy | ❌ — always rectangular tile | ✅ — optional arc | Geometry is the legitimately variable axis |
| `respectsColors` flag from `EffectDatabase` | ✅ → forces rainbow renderer | ❌ — uses `WledEffectsCatalog` (a **different** catalog!) | ❌ — keyset whitelist | **Disagreement #3: two catalogs of effect metadata** |
| Effect-color-slot ROLES (kWledColorRoles) | ❌ — col[0]=fg, col[1]=bg only | ✅ partial — only for chase/sparkle | ❌ | Only one of three surfaces respects role mapping; even there it's incomplete |

### 1.3 The contract conflicts these tables produce

1. **Same effect, three different categorizations.** Effect 64 (Chase 3): `RooflineLightPainter` calls it `chase`, `EffectPreviewWidget` calls it `chase`, `LightEffectAnimator` calls it `chase` — OK. Effect 80 (Twinklefox): roofline → `twinkle` (via `MotionType.twinkling`), card → `sparkle`, chat → `sparkle`. Effect 9 (Rainbow): roofline → `rainbow` renderer ignoring user colors; card → `rainbow` painter ignoring user colors; chat → `rainbow` HSV. Three "rainbow"s, three different visual results.
2. **Palette truth diverges from device.** WLED device receives `pal:5` (Colors Only) so it uses user `col` slots even for `respectsColors:false` effects (the firmware does honor pal:5 in palette-driven effects by clamping to the supplied palette). Preview painters bypass this: `RooflineLightPainter`'s `_paintRainbowPath` for `respectsColors:false` goes straight to HSV ignoring `colors`.
3. **Role mapping only exists in one place.** `kWledColorRoles` correctly identifies that the Twinkle family has background in `col[1]` and the spark in `col[0]`. Only `EffectPreviewWidget` uses it. Roofline's `_paintTwinklePath` treats `colors.first` as the sparkle color and `backgroundColor` as off (independent of `col[1]`), which is wrong for any palette where `col[1]` is the intended background (Christmas Twinkle, etc.).
4. **Effect-ID disagreement on the SAME bucket.** `LightEffectAnimator` thinks `87 = chase` (it lists 87 in the chase set); `EffectDatabase` says 87 is `Glitter` (a `MotionType.twinkling`); `kWledColorRoles` says 87 is `WledColorRoles(primary:0, background:1)`. Hardcoded ID sets rot.

### 1.4 The complete input set a unified interpreter must accept

Source-of-truth inputs (the union):

```text
// What the device renders (drives motion + color)
effectId: int                   // WLED fx
paletteId: int                  // WLED pal (CRITICAL: drives color source)
colorSlots: List<Color> (3)     // WLED col[0..2]
speed: int (0..255)             // sx
intensity: int (0..255)         // ix
brightness: int (0..255)        // bri
colorGroupSize: int             // grp
spacing: int                    // spc
reverse: bool                   // seg.rev
isOn: bool

// Geometry (how the pixels are laid out on screen)
ledCount: int?                  // explicit LED count, or null for auto
geometry: PreviewGeometry       // see §2.2

// Render context (purely visual, no WLED meaning)
backgroundColor: Color          // unlit-pixel color (off LEDs visible behind)
phase: double (0.0..1.0)        // current animation tick
```

Everything else either derives from these (e.g. `category`, `roles`) or
is per-surface chrome (border radius, label) that doesn't belong in the
interpreter.

---

## 2. The `RenderedPattern` Representation

### 2.1 Goal

A single value type that says **"what should this pattern look like at
this moment in time"** without committing to a drawing surface. The
roofline overlay, the pattern card, and the chat strip all consume the
same `RenderedPattern` and only differ in how they paint the resulting
pixel list onto their geometry.

### 2.2 Contract

```dart
/// Frozen, per-frame snapshot of what a pattern looks like at one phase.
/// Surfaces consume this and paint their own geometry; they never re-
/// interpret the effect.
class RenderedFrame {
  /// Pixel colors, left-to-right (or strip-index order). Length == ledCount
  /// requested by the surface. Off pixels = [backgroundColor], never
  /// transparent — surfaces decide whether to dim or skip them.
  final List<Color> pixels;

  /// Per-pixel intensity 0..1, separate from RGB. Lets surfaces blend
  /// glow/halo correctly (cf. RooflineLightPainter's _drawLedDot wash).
  /// Default = 1.0 for lit pixels, 0.0 for off pixels.
  final List<double> intensities;

  /// Backdrop color the surface should paint behind unlit pixels.
  /// (Roofline uses this for the "house at night" feel; card uses it as
  /// the tile background.)
  final Color backgroundColor;

  const RenderedFrame({
    required this.pixels,
    required this.intensities,
    required this.backgroundColor,
  });
}

/// Geometry-independent description of the live pattern. Owned by the
/// interpreter, NOT by any surface.
class PatternState {
  final int effectId;
  final int paletteId;
  final List<Color> colorSlots;   // col[0..2], padded to length 3
  final int speed;
  final int intensity;
  final int brightness;
  final int colorGroupSize;
  final int spacing;
  final bool reverse;
  final bool isOn;

  const PatternState({...});
}

/// Surfaces request a frame at (phase, ledCount). Interpreter handles
/// the rest. Pure function — no I/O, no animation controller.
abstract class PreviewInterpreter {
  RenderedFrame render({
    required PatternState state,
    required int ledCount,
    required double phase,
  });
}
```

### 2.3 Palette resolution — the contract the painters currently break

The interpreter MUST resolve color before motion, and it MUST do that the
same way the device does. Today the device receives `pal:5` from
`pattern_models.dart::toWledPayload:325` so the firmware uses the
user-supplied `col[]` slots. The preview should match this exactly.

```text
COLOR-SOURCE TABLE (matches WLED firmware behavior with pal:5)

paletteId == 5 ("Colors Only")
  → source = colorSlots[0..2]
  → IGNORE the effect's respectsColors flag — pal:5 overrides it
    (this is the rule the app actually relies on; preview was wrong)

paletteId == 0 (Default — effect-defined)
  → If effect is palette-driven (e.g. Pacifica, Sunrise), use the
    effect's hardcoded palette → fall through to per-effect hook
  → Otherwise behave as "Colors Only"

paletteId == 1..4, 6..N (Rainbow, Party, etc.)
  → source = sampled from the named WLED palette LUT
  → Need a small Flutter-side palette LUT (≈70 palettes; static data)

(Future) Custom palette
  → source = supplied palette stops; same code path as named LUT
```

This single rule fixes Symptom 1 (palette ignored). The current code's
"respectsColors:false → HSV rainbow" path becomes a pure fallback that
fires only when palette is "Default" AND the effect declares an internal
palette (e.g. Fire 2012, Pacifica).

### 2.4 Why both `pixels` AND `intensities`?

The three surfaces care about brightness differently:

- Roofline: needs per-pixel intensity to drive the 3-pass dot rendering
  (fascia wash, halo, lens). Pre-multiplying alpha into the Color loses
  the gradient direction.
- Card: usually paints opaque rects, but Sparkle/Meteor want per-dot
  alpha for fade.
- Chat strip: `LedGlowPainter` already supports per-LED bloom strength.

Keeping intensity separate from color lets the interpreter express
"this pixel is full red, dimmed to 0.3" without color-banding artifacts
that come from `Color.lerp(Colors.black, red, 0.3)`.

---

## 3. The Per-Effect Hook Table

### 3.1 What's wrong with the current bucketing

- `RooflineLightPainter` collapses ~187 effects into 12 buckets.
- `EffectPreviewWidget` uses 16 buckets but routes by `WledEffectsCatalog.category` string, which is a **third** taxonomy.
- `LightEffectAnimator` uses 8 buckets with hardcoded ID sets.
- All three rot when WLED adds an effect — the new ID falls to a
  default bucket that may not match what the firmware does.

### 3.2 Proposed structure: motion primitive + role mapping + parameter pack

Don't model 187 effects. Model **8–12 motion primitives** parameterized
by a small descriptor, and route every effect through a table that maps
`effectId → MotionDescriptor`.

```dart
/// What kind of motion the renderer should draw.
/// These map closely to WLED's actual algorithm families.
enum MotionPrimitive {
  staticFill,        // Solid, Solid Pattern (fx 0, 83, 84) — banded fill, no motion
  pulse,             // Breathe, Fade, Blink (fx 1, 2, 12) — uniform brightness sine
  scroll,            // Running, Chase, Wipe (fx 3, 15, 28, etc.) — colored band translating
  scan,              // Scan, Scanner (fx 11, 13) — single bright pixel back/forth
  sparkle,           // Twinkle, Glitter, Sparkle (fx 17, 20, 87) — random lit pixels on bg
  flow,              // Noise, Fade, Aurora (fx 70, 89, 101) — slow color interpolation
  burst,             // Fireworks, Pop, Explode — discrete events with attack/decay
  flicker,           // Fire 2012, Candle (fx 66, 67) — algorithmic warmth (palette-driven)
  ripple,            // Ripple, Ripple Rainbow — concentric / spreading
  drip,              // Meteor, Drip, Lighthouse — head with fading trail
  beat,              // Audio-reactive families (later) — pulse on beat
  unknown,           // Fallback — see §3.5 degradation
}

/// One row of the lookup table. ~50 explicit rows for high-frequency
/// effects + a category-based fallback covers practically everything.
class MotionDescriptor {
  final MotionPrimitive primitive;
  final WledColorRoles roles;       // existing struct, extended
  final MotionParams params;        // primitive-specific knobs

  const MotionDescriptor({
    required this.primitive,
    this.roles = const WledColorRoles(),
    this.params = const MotionParams(),
  });
}

/// Small typed parameter pack — primitive-specific.
class MotionParams {
  final int trailLength;        // scroll/drip — defaults derived from primitive
  final int eventCount;         // burst — number of simultaneous events
  final double minDuty;         // pulse — minimum brightness in cycle
  final bool reverseByDefault;  // some effects scroll right-to-left
  // ... ~6 fields total. NOT one per effect — these are knobs the
  // primitive uses to look slightly different per row.

  const MotionParams({
    this.trailLength = 4,
    this.eventCount = 3,
    this.minDuty = 0.3,
    this.reverseByDefault = false,
  });
}
```

### 3.3 The table — keep it small

```dart
const Map<int, MotionDescriptor> kEffectMotionTable = {
  // ── Static / fill ─────────────────────────────────────────────────────
  0:  MotionDescriptor(primitive: MotionPrimitive.staticFill,
        roles: WledColorRoles(primary: 0)),
  83: MotionDescriptor(primitive: MotionPrimitive.staticFill,
        roles: WledColorRoles(primary: 0, background: 1, accent: 2)),
  84: MotionDescriptor(primitive: MotionPrimitive.staticFill,
        roles: WledColorRoles(primary: 0, background: 1, accent: 2)),

  // ── Pulse / breathe ───────────────────────────────────────────────────
  1:  MotionDescriptor(primitive: MotionPrimitive.pulse,
        roles: WledColorRoles(primary: 0, background: 1),
        params: MotionParams(minDuty: 0.0)),       // blink — hard off
  2:  MotionDescriptor(primitive: MotionPrimitive.pulse,
        roles: WledColorRoles(primary: 0),
        params: MotionParams(minDuty: 0.25)),      // breathe — soft
  12: MotionDescriptor(primitive: MotionPrimitive.pulse,
        roles: WledColorRoles(primary: 0)),

  // ── Scroll family — ~20 effects, same primitive, vary trail length ───
  3:  MotionDescriptor(primitive: MotionPrimitive.scroll,
        roles: WledColorRoles(primary: 0, background: 1)),
  15: MotionDescriptor(primitive: MotionPrimitive.scroll,
        roles: WledColorRoles(primary: 0, background: 1),
        params: MotionParams(trailLength: 3)),
  28: MotionDescriptor(primitive: MotionPrimitive.scroll,
        roles: WledColorRoles(primary: 0, background: 1, accent: 2),
        params: MotionParams(trailLength: 2)),
  // ... rest of chase/run family

  // ── Twinkle / sparkle ────────────────────────────────────────────────
  17: MotionDescriptor(primitive: MotionPrimitive.sparkle,
        roles: WledColorRoles(primary: 0, background: 1)),
  20: MotionDescriptor(primitive: MotionPrimitive.sparkle,
        roles: WledColorRoles(primary: 0, background: 1),
        params: MotionParams(eventCount: 8)),
  74: MotionDescriptor(primitive: MotionPrimitive.sparkle,
        roles: WledColorRoles(primary: 0, background: 1)),
  // Twinklefox / Twinklecat — palette-driven, roles still apply
  80: MotionDescriptor(primitive: MotionPrimitive.sparkle,
        roles: WledColorRoles(primary: 0, background: 1)),

  // ── Fire / palette-driven ────────────────────────────────────────────
  66: MotionDescriptor(primitive: MotionPrimitive.flicker),  // Fire 2012
  88: MotionDescriptor(primitive: MotionPrimitive.flicker),  // Candle

  // ... target: ~50 explicit rows for the effects that matter, the rest
  // fall through to category default (§3.5)
};
```

Sizing: 50 rows × one line each = ~50 lines of declarative data. The
current code spreads the same information across `EffectDatabase` (1100
lines of mood/vibe metadata mixed with motion), `kWledColorRoles` (15
rows), `WledEffectsCatalog.category` strings, and three painter switch
statements. The new table consolidates the **motion-relevant** subset.

### 3.4 Extending `WledColorRoles`

The existing struct ([effect_preview_widget.dart:12-25](../lib/features/wled/effect_preview_widget.dart#L12-L25))
already has `primary / background / accent` as slot indices. Two
extensions:

```dart
class WledColorRoles {
  final int primary;
  final int? background;
  final int? accent;

  /// NEW: which slots feed the palette-driven path when the effect
  /// declares its own palette but pal=5 overrides. Default = the
  /// resolved (primary, background, accent) order.
  final List<int>? paletteSlots;

  /// NEW: when the slot is out of range AND no fallback is supplied,
  /// what should the renderer do? Default: cycle through populated slots.
  final RoleFallback fallback;
}
```

Folding into the table: every row in `kEffectMotionTable` carries its
`roles` value. The existing 15 entries in `kWledColorRoles` become 15
rows in the new table, plus the primitive. The primary-only default
applies to ~140 effects that don't need special role mapping.

### 3.5 Graceful degradation for unknown effects

When WLED adds effect 188 tomorrow, the interpreter must not break.
Resolution order:

1. **Direct lookup** in `kEffectMotionTable[effectId]` → use as-is.
2. **Category lookup** in `EffectDatabase.effects[effectId].motionType`
   → translate `MotionType` enum into `MotionPrimitive` via a fixed map
   (`MotionType.chasing → MotionPrimitive.scroll`, etc.) → use with
   default `WledColorRoles()`.
3. **Catalog category** in `WledEffectsCatalog` (the second metadata
   source) → string-match `'Chase' → scroll`, `'Sparkle' → sparkle`.
4. **Hard fallback** → `MotionPrimitive.scroll` with default roles. The
   user sees a moving band of their colors. This is the worst case and
   it still respects the palette and shows the right colors.

Crucially, step 4 is **palette-correct** even if motion-wrong: an
unknown effect previews with the user's selected colors, not an HSV
rainbow. That alone removes the most jarring discrepancy.

### 3.6 The 8-vs-12-vs-16 bucket question

The audit asks whether 12 buckets is the right granularity. My read:

- **12 buckets is too many** for the renderer — three of them (`bouncing`,
  `dripping`, `explosive`, `morphing`) only render a handful of effects
  each and most users will never distinguish them in the preview. Fold
  bouncing+dripping → drip, explosive → burst, morphing → flow.
- **8 buckets (chat strip) is too few** — it can't represent fire or
  scanner distinctly, both of which are visually important.
- **Land on ~10 primitives** (the list in §3.2). Sized to (a) cover
  what's visually distinguishable at preview size, (b) match WLED's
  actual algorithm families, (c) be implementable by one developer.

---

## 4. Migration Path (3-4 painters → 1)

### 4.1 Risk-ordered phases

**Phase 0 — Delete the dead branch (no behavior change).**
Remove `arPreviewProvider` and its branch in `AnimatedRooflineOverlay`
(lines 102–139). No surface depends on it: grep shows only
`arPreviewProvider.startPreview` is wired to nothing. **Pure deletion;
risk near zero.**

**Phase 1 — Build the interpreter dormant.**
- Add `lib/features/preview/preview_interpreter.dart` with
  `PatternState`, `RenderedFrame`, `PreviewInterpreter`,
  `kEffectMotionTable`, and one implementation
  (`PrimitiveBasedInterpreter`).
- Add a Flutter palette LUT (`lib/features/preview/wled_palettes.dart` —
  ~70 palette stops, transcribed from
  [https://github.com/Aircoookie/WLED/blob/main/wled00/palettes.h](https://github.com/Aircoookie/WLED/blob/main/wled00/palettes.h)).
- **No surface consumes it yet.** Ship a unit test suite that exercises
  ~30 known patterns and pins the resulting `RenderedFrame.pixels`
  against golden values. Tests pass = baseline locked.
- **Risk: zero** — code is unreferenced.

**Phase 2 — Migrate Lumina chat strip first.**
This is the lowest-blast surface: it's only seen during AI-suggested
patterns, fewer users hit it, regression is recoverable.
- Replace `LightEffectAnimator.computeFrame` body with a delegate that
  builds `PatternState` and calls the interpreter. Keep
  `LightEffectAnimator` as a thin shim during transition.
- Visual verification: side-by-side screenshot of 5 known patterns
  (solid red, breathe blue, twinkle xmas, chase rainbow, fire).
- **Rollback:** revert one file (`light_effect_animator.dart`). The
  surface API doesn't change.

**Phase 3 — Migrate `EffectPreviewWidget` (pattern cards).**
This is the highest-volume surface (every tile renders one), but cards
are forgiving: small size, low expectation of fidelity. Migrate one
primitive at a time:
- Wire `EffectPreviewWidget` to render via `RenderedFrame` → 1D pixel
  strip painted as a horizontal row of small rects across the tile.
- Compare tile rendering against current 14 sub-painters side-by-side
  on a debug screen (build a `lib/features/dev/preview_diff_screen.dart`
  that shows old + new for every effect ID 0–187).
- **Rollback:** flip a feature flag `kUseUnifiedPreview` per-surface;
  fall back to old painter classes (kept dormant during Phase 3).

**Phase 4 — Migrate `RooflineLightPainter`.**
Highest visual fidelity, highest blast radius (dashboard hero). Last.
- `RooflineLightPainter.paint` becomes: build `PatternState`, call
  `interpreter.render(state, ledCount, phase)`, then paint
  `RenderedFrame.pixels` along the existing roofline path using the
  existing `_drawLedDot` 3-pass technique. Geometry code stays.
- Visual verification: dashboard hero, demo flow, edit-pattern screen,
  autopilot detail. Tyler has the tablet; spot-check 8–10 patterns end-
  to-end against the actual WLED device displaying the same payload.
- **Rollback:** keep the old `_paint*Path` methods. Switch behind
  `kUseUnifiedPreview` flag.

**Phase 5 — Remove old painter code paths.**
Only after Phase 4 has been live for ≥1 release with no reported
regressions. Delete:
- `RooflineLightPainter._paint{Solid,Breathe,Chase,Rainbow,Twinkle,Wave,Fire,Explosive,Scanning,Dripping,Bouncing,Morphing}Path`
- All 14 sub-painters in `effect_preview_widget.dart`
- `LightEffectAnimator._{solid,chase,fade,twinkle,sparkle,rainbow,gradient,breathe}`
- `categorizeEffect`, `getPreviewType`, `effectTypeFromWledId` — they
  collapse into one resolver in the interpreter.

### 4.2 Visual regression checks

The preview is visual. Tests need to be visual too:

1. **Golden image tests** (Flutter built-in) for each `MotionPrimitive`
   at phases 0.0, 0.25, 0.5, 0.75 using a fixed test palette
   (Christmas red+green+white). ~10 primitives × 4 phases = 40 golden
   images. Tiny — they're 200×40 PNGs.
2. **Manual side-by-side diff screen** (debug-only) for any surface
   during migration. Old painter on left, new on right.
3. **Hardware loop check**: for each of ~30 representative patterns,
   apply to Tyler's device (192.168.1.252, see memory) and compare the
   actual roofline LEDs against the preview. This is the test the
   current painters were never held to. Manual but high-signal.

### 4.3 Rollback per surface

Per-surface feature flag `kUseUnifiedPreview` (env var or build flag,
NOT a remote config — preview rendering is too hot a path to add a
network dependency). Flag flip → revert to legacy painter classes for
that surface, which remain in code through Phase 5.

---

## 5. Honest Feasibility, Effort, and the Palette Ceiling

### 5.1 Effort estimate

| Phase | Scope | Estimate (one focused developer) |
|---|---|---|
| Phase 0 | Delete `arPreviewProvider` + the overlay branch | 1 hr |
| Phase 1 | Interpreter + palette LUT + golden tests | 2–3 days |
| Phase 2 | Migrate Lumina chat strip | 0.5 day |
| Phase 3 | Migrate `EffectPreviewWidget` + diff screen | 2 days |
| Phase 4 | Migrate `RooflineLightPainter` | 2 days |
| Phase 5 | Cleanup / delete legacy painters | 0.5 day |
| **Total** | | **~7–8 days** elapsed (~5 days actual coding) |

Plus iteration: expect each phase to bounce once for visual tuning.
Realistic range: **2 weeks** for a clean landing including review +
device verification.

### 5.2 The palette ceiling — what will NEVER perfectly match

Be honest:

1. **Algorithm-divergent palette-driven effects.** Fire 2012, Aurora,
   Sunrise, Pacifica, the noise effects — these use WLED's internal
   palette interpolation + algorithmic noise (Perlin, simplex,
   custom). Even with the LUT in the app, the firmware's pseudorandom
   sequence differs. Preview will **look like the same family** —
   correct dominant colors, right motion type — but **pixel-exact match
   is not achievable** without porting the WLED algorithms verbatim.
2. **Audio-reactive effects.** WLED's audio modes react to microphone
   input on the controller. The app has no live audio bridge to the
   device. Preview these as a generic "beat" primitive with a synthetic
   beat — accept they will only be **iconographic**, not faithful.
3. **2D matrix effects.** A few WLED effects assume 2D pixel layouts
   (Lissajous, Drift, etc.). Lumina is 1D-strip only, so these are
   moot — preview them as their 1D projection.
4. **Effects that depend on `intensity` controlling something
   unpredictable** (some custom usermods). Defer; pick reasonable
   defaults.

**"Good enough" is acceptable here.** A user looking at the card
expects to see "this is a fire-colored flickering effect"; they don't
expect frame-accurate replay. Where the preview is wrong today, it's
wrong about **the colors** — that's the showstopper, and the unified
interpreter fixes it. Motion fidelity for the long tail can stay
approximate.

### 5.3 Connections to other planned work

**Per-area-zone vision.** The interpreter is geometry-agnostic by
design. The same `PreviewInterpreter` driving the full roofline drives
each zone's local preview, with the surface supplying its own `ledCount`
and geometry path. The data flow becomes:

```text
zone state (effect, colors, palette)
  → PatternState
  → PreviewInterpreter.render(state, zoneLedCount, phase)
  → RenderedFrame
  → zone-specific painter draws the geometry
```

This is exactly the shape a per-zone preview wants — multiple zones,
each with its own `PatternState`, all driven by the same interpreter.

**Game Day.** Game Day's auto-pattern selector resolves
`team → colors + effect` and applies it to the device. To preview "what
will Game Day look like at 7:00 PM tonight" the app needs a renderer
that takes `(effectId, palette, colors)` and produces a frame — exactly
the interpreter contract. Without this, Game Day previews would need
either a 4th painter (more fragmentation) or a hardware round-trip
(slow). Unified interpreter gives both surfaces (Game Day card +
roofline) the same answer.

**Design Studio live preview**
([features/design/widgets/live_preview_canvas.dart](../lib/features/design/widgets/live_preview_canvas.dart))
is another candidate consumer. Not surveyed in this design pass, but
the AI design studio likely benefits from the same shared renderer
(currently uses one of the existing four painters; can't tell without
looking).

### 5.4 What you give up

This refactor is genuinely additive but it does cost things:

1. **Three painters' worth of historical bug fixes get re-implemented
   once.** Each existing painter has small bug fixes (e.g. roofline's
   "show all LEDs in twinkle base layer with `hasBgColor`" fix). Need
   to grep and port these into the primitives so visual regressions
   aren't introduced.
2. **Per-surface tuning is harder.** Right now each painter can be
   tweaked independently. The unified version means a tweak for the
   roofline propagates to the card unless explicitly gated by surface.
   Mostly this is what we want, but it costs autonomy.
3. **Palette LUT maintenance.** WLED has ~70 named palettes. They
   rarely change but they do change. Pin to a specific WLED release
   and document the version in `wled_palettes.dart`.

---

## 6. Recommended Decision Points for Tyler

Before any code is written, decide:

1. **Is "good enough" motion fidelity acceptable?** (My recommendation:
   yes — the visible bug today is colors, not motion.)
2. **Phase 0 (delete `arPreviewProvider`) — do it now in a standalone
   PR?** It's safe, mechanical, and clears noise from the picture
   regardless of whether the full refactor happens.
3. **Pin to WLED release for palette LUT.** Suggest the same release
   the ESP32 bridge firmware tracks (1.2 currently — does it match a
   specific WLED version?). Memory note `project_bridge_firebase_uid_default_fix.md`
   suggests bridge is loosely versioned; verify before pinning.
4. **Migration order — Lumina chat → cards → roofline?** Or roofline
   first because it's the most visible? (My recommendation:
   chat-first; lowest-blast surfaces validate the interpreter before
   the hero surface gets touched.)
5. **Feature flag location.** `--dart-define=USE_UNIFIED_PREVIEW=true`
   build flag, or Riverpod provider with hardcoded `true` and a
   debug-screen toggle? (My recommendation: build flag, since preview
   rendering is performance-critical.)

---

## 7. Out of Scope

- **Audio-reactive preview.** Deferred. Lumina audio mode UI is
  in-progress per CLAUDE.md; previewing live audio reactivity is a
  separate feature.
- **2D matrix layouts.** Lumina is 1D-strip only.
- **Pixel-perfect WLED algorithm replication.** Not achievable without
  porting C++ effect code to Dart; see §5.2.
- **Changes to `pattern_models.dart::toWledPayload`.** The payload
  side already works (the device renders correctly). Don't touch the
  ship-path.
- **Refactor of `EffectDatabase` mood/vibe metadata.** Mood/vibe is
  used by AI matching, not preview. Leave alone.

---

## 8. Appendix — File Touch Map

If approved, these files would be added / modified / deleted:

**Added:**
- `lib/features/preview/preview_interpreter.dart` (interpreter + table)
- `lib/features/preview/wled_palettes.dart` (palette LUT)
- `lib/features/preview/motion_primitives.dart` (10 primitive renderers)
- `test/features/preview/preview_interpreter_test.dart` (goldens)

**Modified (Phase 2–4):**
- `lib/features/ai/light_effect_animator.dart` → shim around interpreter
- `lib/features/wled/effect_preview_widget.dart` → routes to interpreter
- `lib/widgets/roofline_light_painter.dart` → keeps geometry, replaces motion
- `lib/widgets/animated_roofline_overlay.dart` → drops `arPreview` branch

**Deleted (Phase 0 + Phase 5):**
- `lib/features/ar/ar_preview_providers.dart` (only `arPreviewProvider`
  and `ARPreviewState`/`ARPreviewNotifier` — keep `rooflineMaskProvider`
  and the geocoding-adjacent providers, which are unrelated)
- ~14 sub-painters in `effect_preview_widget.dart`
- 12 `_paint{Category}Path` methods in `roofline_light_painter.dart`
- `categorizeEffect`, `getPreviewType`, `effectTypeFromWledId`,
  `speedToDurationForEffect`

---

**End of design.** Next step: Tyler reviews, picks an answer for §6, and
the implementer starts with Phase 0 (the safe deletion).
