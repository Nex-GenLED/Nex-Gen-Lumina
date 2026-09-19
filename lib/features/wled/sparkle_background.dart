// A readable background for WLED's "sparkles over a field" effects.
//
// THE FIRMWARE FACT (WLED v0.15.1 FX.cpp, read from the tag — and the effect
// metadata says the same thing: colour slot 2 is labelled "Bg"):
//
//   17  Twinkle       SEGMENT.fade_out(224)  → every pixel fades toward col[1]
//   20  Sparkle       field = color_from_palette(i, …, mcol 1); spark = col[0]
//   51  Fairytwinkle  color_blend(SEGCOLOR(1), palette, flasherBri)
//   80  Twinklefox    CRGB bg = SEGCOLOR(1)
//   81  Twinklecat    (same base as Twinklefox)
//   106 Twinkleup     color_blend(SEGCOLOR(1), palette, pixBri)
//
// For these, `col[1]` is not "the palette's second colour" — it is the FIELD
// the sparkles sit on. The app models `col[]` as "this palette's colours" and
// sends them in order, so a palette whose colours are close together floods
// the strip with colour #2 and draws near-identical sparkles on top.
//
// BENCH (192.168.1.150, 10 s / 133 live-view frames, 2026-09-19): Architectural
// 3000K + Twinkle rendered 97 of 97 lit LEDs constant in every frame, ~93 % of
// lit samples exactly `col[1]`, 10 LEDs ever changed — a SOLID. Same payload
// with col[1] black: the field disappears.
//
// THE RULE, stated once and applied where payloads are BUILT:
// when the field would be indistinguishable from the sparkles, the field is
// replaced with a DIM version of the sparkle colour. Palettes whose colours
// are clearly different (red / green) are left exactly as they were — a green
// house with red sparkles is a legitimate look and not this defect.
//
// Pure Dart: no Flutter, no providers.

import 'dart:math' as math;

/// Effects that draw sparkles over a field of `col[1]`. Source-verified above.
const Set<int> kSparkleOverFieldEffectIds = {17, 20, 51, 80, 81, 106};

/// Of those, the col-based ones whose sparkle colour is `col[0]` when `pal:0`
/// (`color_from_palette` returns `SEGCOLOR(mcol)` for the default palette).
/// Twinklefox/-cat are palette-driven and keep whatever palette they had.
const Set<int> _kSparkleIsPrimaryWithPal0 = {17, 20, 51, 106};

/// RGB distance below which two colours count as "the same colour" for a
/// sparkle-vs-field purpose. Every Architectural Kelvin pair is 21–66 apart and
/// every brightness-gradient step pair under 100; red vs green is ~360.
const double kSparkleFieldMinDistance = 120;

/// How bright the substituted field is, relative to the sparkle colour. Dim
/// enough to read as "off-ish" next to a full-brightness sparkle (WLED's 2.8
/// colour gamma takes 30 % input to ~3 % light), bright enough that an
/// architectural wash still reads as lit rather than dark.
const double kSparkleFieldDimFactor = 0.30;

double _rgbDistance(List<int> a, List<int> b) {
  double sum = 0;
  for (int i = 0; i < 3; i++) {
    final d = (a[i] - b[i]).toDouble();
    sum += d * d;
  }
  // The W channel is light too: treat it as a fourth axis.
  final wa = a.length > 3 ? a[3] : 0, wb = b.length > 3 ? b[3] : 0;
  sum += ((wa - wb) * (wa - wb)).toDouble();
  return math.sqrt(sum);
}

bool _isDark(List<int> c) =>
    c.length < 3 || (c[0] + c[1] + c[2] + (c.length > 3 ? c[3] : 0)) < 48;

/// Result of [readableSparkleColors].
class SparkleColors {
  /// The `col` array to send.
  final List<List<int>> colors;

  /// A `pal` that must win over the catalog's derived palette, or null.
  final int? paletteOverride;

  /// True when the field was replaced (for tests / logging).
  final bool fieldReplaced;

  const SparkleColors(this.colors,
      {this.paletteOverride, this.fieldReplaced = false});
}

/// Returns the `col` (and, when needed, `pal`) to send for [effectId] given the
/// palette's [colors] (RGBW, up to three).
///
/// Anything outside [kSparkleOverFieldEffectIds] comes back untouched, as does
/// a palette with a single colour (WLED's own `col[1]` default is black) or one
/// whose second colour is already dark or clearly different from the first.
SparkleColors readableSparkleColors(int effectId, List<List<int>> colors) {
  if (!kSparkleOverFieldEffectIds.contains(effectId) || colors.length < 2) {
    return SparkleColors(colors);
  }
  final sparkle = colors[0], field = colors[1];
  if (sparkle.length < 3 || field.length < 3) return SparkleColors(colors);
  if (_isDark(field)) return SparkleColors(colors);
  if (_rgbDistance(sparkle, field) >= kSparkleFieldMinDistance) {
    return SparkleColors(colors);
  }

  final dim = [
    for (int i = 0; i < 4; i++)
      i < sparkle.length ? (sparkle[i] * kSparkleFieldDimFactor).round() : 0,
  ];
  final out = <List<int>>[
    sparkle,
    dim,
    // Slot 3 stays as it was; when the palette only had two near-identical
    // colours there is nothing worth keeping there.
    if (colors.length > 2) colors[2],
  ];
  return SparkleColors(
    out,
    // With "Colors Only" (pal 5) the sparkle palette is BUILT from col[] — so
    // the dim field we just put in slot 2 would become half the sparkles.
    // pal 0 makes the sparkle exactly col[0].
    paletteOverride: _kSparkleIsPrimaryWithPal0.contains(effectId) ? 0 : null,
    fieldReplaced: true,
  );
}

/// [readableSparkleColors] for an already-built WLED seg map (`fx`, `col`,
/// `pal`). Returns a NEW map; a seg that is not a sparkle effect, or whose
/// field is already readable, comes back as an equal copy.
Map<String, dynamic> withReadableSparkleField(Map<String, dynamic> seg) {
  final fx = seg['fx'];
  final col = seg['col'];
  if (fx is! int || col is! List) return Map<String, dynamic>.from(seg);
  final colors = <List<int>>[
    for (final c in col)
      if (c is List) [for (final v in c) (v as num).toInt()],
  ];
  final r = readableSparkleColors(fx, colors);
  if (!r.fieldReplaced) return Map<String, dynamic>.from(seg);
  return {
    ...seg,
    'col': r.colors,
    if (r.paletteOverride != null) 'pal': r.paletteOverride,
  };
}
