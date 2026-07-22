# Lumina Design Pipeline Audit (Item #40)

**Status:** Read-only audit, no code changes. Working-tree only.
**Date:** 2026-05-07
**Branch:** `submission/app-store-v1`
**Author:** Claude (audit dispatched by Tyler)

---

## Executive Summary

The Lumina design pipeline (chat → design model → WLED payload → physical LEDs) has expressive **inputs** (the AI prompt accepts rich natural language) and expressive **outputs** (WLED supports 3 color slots per segment, multiple segments, palettes, and 100+ effects), but a **narrow middle**: the canonical Dart models can carry only one effect at a time, the AI-response JSON schema returns only one design per turn, and at least one render path (`CustomDesign.toWledPayload()`) drops the multi-color-aware `fx 0 → 83` substitution that the parallel `GradientPattern` path applies. The result is a class of bugs (2b solid-color collapse, 6 single-design eagerness, 8a-c multi-color split-and-drop, GameDay multi-team-color flattening, Diamond Family shimmer collapsing to single-effect twinkle) that all trace back to the same architectural ceiling: **the pipeline can plumb one (effect, color) pair end-to-end, but cannot represent layered effects, multi-design alternatives, or per-zone color-effect bindings**.

---

## 1. Current Model Capabilities

There are **three parallel design representations** in the codebase, each with overlapping but non-identical capabilities. This proliferation is itself a finding — see Open Questions.

### 1.1 `GradientPattern` (legacy/canonical pattern model)

**File:** [lib/features/wled/pattern_models.dart:325-351](lib/features/wled/pattern_models.dart#L325-L351)

```dart
Map<String, dynamic> toWledPayload() {
  final cols = colors.take(3).map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true)).toList();
  if (cols.isEmpty) cols.add(rgbToRgbw(255, 255, 255, forceZeroWhite: true));

  // When effect 0 (Solid) is used with multiple colors, substitute effect 83
  // (Solid Pattern) which distributes colors in repeating blocks. Solid only
  // shows the first color, losing the rest of the palette.
  final fx = (effectId == 0 && colors.length > 1) ? 83 : effectId;

  return {
    'on': true,
    'bri': brightness,
    'seg': [{ 'fx': fx, 'sx': speed, 'ix': intensity, 'pal': 5,
              'col': cols, 'grp': 1, 'spc': 0, 'of': 0 }]
  };
}
```

**Expresses:** up to 3 colors, one effect (with `fx 0 → 83` workaround for multi-color solid), one segment, palette pinned to "Colors Only" (5).
**Does not express:** per-segment splits, layered effects, per-LED indexing.

### 1.2 `CustomDesign` (newer "design studio" model)

**File:** [lib/features/design/design_models.dart:165-197](lib/features/design/design_models.dart#L165-L197)

```dart
Map<String, dynamic> toWledPayload() {
  final segments = <Map<String, dynamic>>[];
  for (final channel in channels) {
    if (!channel.included) continue;
    final colors = channel.colorGroups.take(3).map((g) => g.color).toList();
    if (colors.isEmpty) colors.add([255, 255, 255, 0]);
    segments.add({
      'id': channel.channelId,
      'col': colors,
      'fx': channel.effectId,        // ← no fx 0 → 83 substitution
      'sx': channel.speed,
      'ix': channel.intensity,
      'rev': channel.reverse,
    });
  }
  return { 'on': true, 'bri': brightness, 'seg': segments };
}
```

**Expresses:** N channels (= per-segment splits), up to 3 colors per channel, one effect per channel.
**Does not express:** layered effects, the `fx 0 → 83` workaround (Bug 2b lives here).

### 1.3 `ComposedPattern` (NLU/composer output)

**File:** [lib/features/design/models/composed_pattern.dart:10-58](lib/features/design/models/composed_pattern.dart#L10-L58)

```dart
class ComposedPattern {
  final String name;
  final List<LedColorGroup> colorGroups;   // per-LED static colors
  final int effectId;                      // ← single effect only
  final int speed;
  final int intensity;
  final int brightness;
  final bool hasMotion;
  final MotionDirection? motionDirection;
  final bool reverse;
  final Map<String, dynamic> wledPayload;
  final List<Color> usedColors;
  ...
}
```

**Expresses:** per-LED static colors via `LedColorGroup`, one effect, motion direction.
**Does not express:** layered effects (no `overlayEffectId`), multi-design alternatives.

### 1.4 `BrandCustomDesign` (brand library)

**File:** [lib/models/commercial/brand_custom_design.dart:16-55](lib/models/commercial/brand_custom_design.dart#L16-L55)

```dart
class BrandCustomDesign {
  final String designId;            // e.g. 'shimmer'
  final String displayName;         // e.g. 'Shimmer'
  final String wledEffectName;      // cosmetic, e.g. 'Twinkle'
  final int wledEffectId;           // ← single effect, e.g. 50 for Twinkle
  final Map<String, dynamic> effectParams;  // sx, ix, pal passthrough
  final String? description;
  final String mood;
  ...
}
```

**Critical finding:** `wledEffectId` is **a single int**. There is no `baseEffectId` + `overlayEffectId` pair. This means the Diamond Family "shimmer" pattern (spec'd in memory as sapphire base + white twinkle overlay) **cannot** be expressed as a true base+overlay composite. It must collapse to either (a) one effect that approximates the look (e.g., Twinkle 50 with sapphire+white in `col[]`) or (b) a sequence rather than a layer.

### 1.5 PatternType enum

**File:** [lib/features/design/models/design_intent.dart:523-534](lib/features/design/models/design_intent.dart#L523-L534)

```dart
enum PatternType {
  solid,
  alternating,
  gradient,
  wave,
  twinkle,
  ...
}
```

These are **mutually exclusive** modes — you cannot say "twinkle ON TOP OF solid". The model has no concept of stacked patterns.

---

## 2. Pipeline Transformation Gaps (chat → model → render)

### 2.1 AI response schema is single-design

**File:** [lib/lumina_ai/lumina_ai_service.dart:203-208](lib/lumina_ai/lumina_ai_service.dart#L203-L208)

```
'- JSON schema: {"message":string,"patternName":string,"thought":string,'
'"colors":[{"name":string,"rgb":[R,G,B,W]}],'
'"effect":{"name":string,"id":number,"direction":string,"isStatic":boolean},'
'"speed":number,"intensity":number,"wled":object,'
'"schedulingIntent":{...}|null}\n'
```

There is **no `"alternatives": [...]`** or `"designs": [...]` array. Each AI turn returns exactly one `(patternName, colors, effect)` triple. **This is the architectural root cause of Bug 6** ("chat too eager — gives 1 design when user asks for 3").

### 2.2 Pattern composer drops secondary color on solid

**File:** [lib/features/design/services/pattern_composer.dart:272-294](lib/features/design/services/pattern_composer.dart#L272-L294)

```dart
switch (pattern.type) {
  case PatternType.solid:
    groups.add(LedColorGroup(
      startLed: range.start,
      endLed: range.end,
      color: primaryColorList,        // ← only primary; secondary silently dropped
    ));
    break;

  case PatternType.alternating:
    final secondaryColorList = colors.secondaryColor != null
        ? _colorToList(colors.secondaryColor!)
        : _colorToList(Colors.black);
    for (int i = range.start; i <= range.end; i++) {
      final isOdd = (i - range.start) % 2 == 1;
      groups.add(LedColorGroup(
        startLed: i, endLed: i,
        color: isOdd ? secondaryColorList : primaryColorList,
      ));
    }
    break;
  ...
}
```

If the NLU classifier (`nlu_service.dart:430`) defaults to `PatternType.solid` whenever no spacing/alternating cue is detected, **a "blue and gold solid" request resolves to gold being silently dropped** unless the classifier specifically recognizes "and" as alternating intent. Bug 8a (multi-color split into separate single-color designs) is the upstream symptom; the composer's `PatternType.solid` branch is the downstream amplifier.

### 2.3 GameDay places multi-team colors in `col[]` but a single `fx`

**File:** [lib/features/ai/lumina_brain.dart:774-796](lib/features/ai/lumina_brain.dart#L774-L796)

```dart
final segCol = <List<int>>[];
for (var i = 0; i < team.colors.length; i++) {
  final rgb = ...safeRGBW(...);
  segCol.add(rgb);
}

final wledPayload = {
  'on': true,
  'bri': 255,
  'seg': [{
    'id': 0,
    'on': true,
    'bri': 255,
    'col': segCol.isEmpty ? [[255, 255, 255, 0]] : segCol,
    'fx': effectId,                // ← single fx for all team colors
    'sx': speed,
    'ix': intensity,
  }],
};
```

If `effectId == 0` (Solid), only `col[0]` (e.g., royal blue) renders — gold is dropped. There is **no conditional logic** that picks a multi-color-aware effect (41 Running Dual, 43 Tricolor Chase, 83 Solid Pattern) based on `team.colors.length`. This is the GameDay multi-color flattening bug.

### 2.4 Render-path divergence (the Bug 2b smoking gun)

The **same** "fx 0 → 83 when colors > 1" workaround exists in `GradientPattern.toWledPayload()` (line 333) but is **absent** from `CustomDesign.toWledPayload()` (line 185). Any design that flows through `CustomDesign` — including, plausibly, the "design studio" custom-creation path — loses the workaround. Anything that flows through `GradientPattern` (legacy/curated patterns) keeps it. Bug 2b reproduces only on the `CustomDesign` path.

---

## 3. WLED Capabilities Being Underused

WLED supports per-segment definitions with up to 3 color slots (`c[0]`, `c[1]`, `c[2]`), palettes (`pal`), and effects that consume multiple slots. The codebase **does** populate `col[]` with up to 3 colors in all three render paths — that's correct. What it underuses:

- **Per-segment effect bindings.** `CustomDesign.toWledPayload()` does emit one segment per channel with its own `fx`, but no AI flow currently produces multi-channel `CustomDesign`s. Most renders go through the single-segment `GradientPattern` path or the single-segment GameDay payload, so "left half blue, right half gold" rarely makes it to WLED even though the model could express it.
- **Effect-color slot semantics.** WLED effects use `c[0]` as primary, `c[1]` as secondary (e.g., chase color), `c[2]` as background. The Lumina pipeline treats colors as a fungible list and passes them to `col[]` in arbitrary order — there is no role concept ("this is the chase color, this is the background").
- **Palette selection.** `GradientPattern` pins palette to 5 ("Colors Only"). `CustomDesign` and the GameDay payload don't set palette at all, leaving WLED to use whatever was last applied. No flow uses palettes intentionally as a design lever (e.g., "Christmas palette" → palette 11).
- **Layered/composite effects.** WLED itself does not have an overlay effect concept — overlay must be simulated with carefully chosen `(fx, col, palette)` triples, OR by per-LED static colors with a transparent twinkle. The pipeline does not attempt either; "shimmer" collapses to single-effect Twinkle.

---

## 4. Bug-to-Gap Mapping

| Bug | Symptom | Architectural Gap | File:Line |
|---|---|---|---|
| **2b** | Solid pattern only renders Color 1 | `CustomDesign.toWledPayload()` missing `fx 0 → 83` substitution | [design_models.dart:185](lib/features/design/design_models.dart#L185) |
| **6** | Chat returns 1 design when user asks for 3 | AI JSON schema has no `alternatives[]` field | [lumina_ai_service.dart:203-208](lib/lumina_ai/lumina_ai_service.dart#L203-L208) |
| **8a** | Multi-color request split into separate single-color designs | NLU defaults to `PatternType.solid`, composer drops secondary | [pattern_composer.dart:273-279](lib/features/design/services/pattern_composer.dart#L273-L279) |
| **8b** | "Confirm" silently drops multi-color | Suspected: schedule-write path collapses `colors[]` to first | _Not localized in this audit — see Open Questions_ |
| **8c** | No preview/edit affordance on scheduled items | UI gap (out of scope for design-pipeline audit) | _N/A_ |
| **GameDay multi-color** | Royals royal-blue + gold renders only blue | No `effectId` selection logic based on `team.colors.length` | [lumina_brain.dart:782-796](lib/features/ai/lumina_brain.dart#L782-L796) |
| **Shimmer** | Sapphire base + white twinkle overlay collapses to single-effect Twinkle | `BrandCustomDesign.wledEffectId` is a single int; no overlay slot | [brand_custom_design.dart:33](lib/models/commercial/brand_custom_design.dart#L33) |

---

## 5. Capability Matrix

| Capability | Expressible in Model? | Renderable to WLED? | Gap Location |
|---|---|---|---|
| Single solid color | ✅ | ✅ | None |
| Multi-color solid (alternating/block split across LEDs) | ✅ (LedColorGroup; `PatternType.alternating`) | ⚠️ Path-dependent: `GradientPattern` ✅ via fx 83, `CustomDesign` ❌ | [design_models.dart:185](lib/features/design/design_models.dart#L185) |
| Single effect + single color | ✅ | ✅ | None |
| Single effect + secondary color (chase color, background) | ⚠️ Colors carried, but no role semantics | ⚠️ Order-dependent | No `c[0]/c[1]/c[2]` role mapping anywhere |
| Multi-segment split (front blue, side gold) | ✅ (`CustomDesign.channels`) | ✅ | AI never produces this — NLU has no zone parsing |
| Effect + overlay (shimmer base + twinkle) | ❌ | ❌ | All models have single `effectId` |
| Per-LED individual addressing | ✅ (`LedColorGroup`) | ✅ via static `col` + fx 0 | Workable but requires fx 0 → 83 substitution; missing in `CustomDesign` |
| Multiple alternative designs per turn | ❌ | N/A | AI schema has no `alternatives[]` |
| Animated palette across LEDs | ⚠️ Possible via WLED palette param, but no model field | ⚠️ Only `GradientPattern` sets `pal: 5` | No palette selection logic |

---

## 6. Recommended Capability Addition Priority

### Priority 1 — Multi-color solid render parity (Bug 2b)

**Scope:** Small (~20 LOC, 1 file).
**File:** `lib/features/design/design_models.dart` near line 185.
**Action:** Port the `fx 0 → 83` substitution from `GradientPattern.toWledPayload()` to `CustomDesign.toWledPayload()`.
**Why first:** Lowest LOC, no architectural change, immediately unblocks Bug 2b and preempts the same class of bug for any future flow that uses `CustomDesign`. This is purely a bug fix, not a capability addition.

### Priority 2 — Multi-design alternatives (Bug 6)

**Scope:** Medium (~100-150 LOC, 2-3 files).
**Files:** `lib/lumina_ai/lumina_ai_service.dart` (schema + prompt), `lib/features/ai/lumina_brain.dart` (extraction around line 627), UI presentation (separate, deferred).
**Action:** Add `"alternatives": [{patternName, colors, effect, speed, intensity, wled}, ...]` to the AI JSON schema; update the system prompt to instruct the model when to populate it (e.g., "if user asks for multiple options, ideas, or 'a few', return 2-3 alternatives"); update extraction to surface the list.
**Why second:** Highest user-visible impact for a single feature. Architectural change is additive (new field) — no migration of existing data.

### Priority 3 — GameDay effect selection by color count

**Scope:** Small (~30-50 LOC, 1 file).
**File:** `lib/features/ai/lumina_brain.dart` near line 791 (the `'fx': effectId` line).
**Action:** Before assembling the payload, if `team.colors.length >= 2 && effectId == 0`, substitute fx 83 (Solid Pattern). If `length >= 2 && Solid intent`, optionally pick fx 41 (Running Dual) or 43 (Tricolor Chase) based on team-color count and motion intent.
**Why third:** Mirrors the Priority 1 fix conceptually but at the GameDay layer; small scope; unblocks a launch-relevant scenario (Royals/Chiefs at home).

### Priority 4 — Zone-intent NLU (Bug 8a foundation)

**Scope:** Medium-large (~300-500 LOC, 3+ files).
**Files:** `lib/features/design/services/nlu_service.dart` (zone parser), AI prompt update, `pattern_composer.dart` (zone-aware composition), possibly new `ZoneIntent` model.
**Action:** Teach the NLU to recognize "left/right/front/back/half/half" and map to existing roofline channels. Composer produces multi-segment `CustomDesign` instead of single-segment `GradientPattern`.
**Why fourth:** Higher LOC, requires roofline-config integration, but unlocks a wide class of expressive requests that currently fail silently.

### Priority 5 — Effect layering (shimmer)

**Scope:** Large (~500+ LOC, 3+ files).
**Files:** `BrandCustomDesign` schema (add `baseEffectId`/`overlayEffectId`), `ComposedPattern` (add overlay fields), composer logic to render overlay (likely as per-LED static base + fx for overlay), brand-design generator.
**Action:** Extend the model to carry two effects per design and define semantics (base = `LedColorGroup` static colors with fx 0; overlay = a transparent-friendly fx like Twinkle 50 with `c[2]` = background = base color). Note: WLED has no native overlay; this is simulation via careful (fx, col, palette) selection.
**Why fifth:** Highest impact for brand library and aspirational design quality, but largest scope and the one with the most open design questions (semantics of "overlay" in a WLED-compatible way).

### Total estimated workstream

Priorities 1+2+3 (the bug-fix tier) ≈ **2 days**.
Priorities 4+5 (the capability tier) ≈ **5-7 days**.
**Total: ~8-10 days of focused work** to close the full Item #40 gap.

---

## 7. Open Questions for Tyler

1. **Three-model proliferation.** `GradientPattern`, `CustomDesign`, `ComposedPattern`, and `BrandCustomDesign` all represent "a design" with overlapping fields and divergent render paths. Is the long-term plan to converge on one (and which?), or is the current parallelism intentional (e.g., legacy curated vs. AI-generated vs. user-custom)? The Bug 2b divergence is a direct consequence of multiple `toWledPayload()` implementations — the fix is one-line, but the root cause is two-payload-builders.

2. **Bug 8b localization.** "Confirm silently drops multi-color" — I traced AI extraction (`lumina_brain.dart` ~line 627) and `GameDayAutopilotService.populateCalendarForTeam()` but did not find an explicit drop point. Where in the schedule-write path do you suspect the colors are flattened? Is it in the Firestore write, the `ScheduleSyncService` payload builder, or a UI-layer collapse before persist?

3. **Shimmer semantic.** Should "shimmer" be:
   (a) A single WLED effect that approximates the look (current behavior — Twinkle 50 with sapphire+white in `col[]`),
   (b) A simulated overlay using per-LED static base + low-density fx, or
   (c) Reserved for a future WLED-native overlay capability?
   This determines whether Priority 5 is a model+render change or just a brand-library curation refinement.

4. **Zone vocabulary scope.** Should "front", "back", "left", "right", "side" be hardcoded in NLU, or should users define named zones in the roofline config (e.g., "garage door", "porch", "second story")? The latter is more powerful but ties the NLU to per-user config.

5. **Multi-design UX placement.** When the AI returns 2-3 alternatives, where do they surface — chat bubble carousel, swipeable preview, modal selector? This shapes whether the AI should return all alternatives at once or stream them one-at-a-time on user nav.

6. **`pal: 5` policy.** `GradientPattern` pins palette to 5 ("Colors Only"). `CustomDesign` doesn't set it. Should `CustomDesign` adopt the same default to prevent rainbow palette bleed, or is leaving it unset intentional (e.g., to support themed palettes)?

---

## Verification Notes

All file:line citations spot-checked against working tree:

- ✅ [pattern_models.dart:330-333](lib/features/wled/pattern_models.dart#L330-L333) — `fx 0 → 83` substitution exists in `GradientPattern`
- ✅ [design_models.dart:185](lib/features/design/design_models.dart#L185) — substitution absent from `CustomDesign`
- ✅ [lumina_ai_service.dart:203-208](lib/lumina_ai/lumina_ai_service.dart#L203-L208) — schema has no `alternatives[]`
- ✅ [pattern_composer.dart:273-279](lib/features/design/services/pattern_composer.dart#L273-L279) — solid drops secondary
- ✅ [lumina_brain.dart:774-796](lib/features/ai/lumina_brain.dart#L774-L796) — single `fx` for multi-color team
- ✅ [composed_pattern.dart:24](lib/features/design/models/composed_pattern.dart#L24) — single `effectId` field
- ✅ [brand_custom_design.dart:33](lib/models/commercial/brand_custom_design.dart#L33) — single `wledEffectId` field

No code was modified. No commits were made. This document is uncommitted in the working tree.
