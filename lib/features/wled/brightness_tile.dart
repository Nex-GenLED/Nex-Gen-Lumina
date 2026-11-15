// Flutter-free apart from `PixelSpan` (per_pixel.dart, foundation only).
//
// A BRIGHTNESS TILE is a short repeating sequence of light levels laid along
// each run of lights: pixel 1 at 100 %, then 80, 60, 40, 60, 80, then 100
// again (a 6-pixel wave), the same wave stretched over 18 pixels, a one-way
// ramp, a staircase, or any sequence the customer types in.
//
// WHY PER-PIXEL DATA (bench 2026-11-14, docs/bench/brightness_patterns_129_
// bench_2026-11-14.md): no WLED 0.15.x effect can draw these. fx 83 Solid
// Pattern is a foreground/background size pattern (one lit pixel, then the
// second colour), fx 65 Palette cannot cycle faster than ≈ 16·(len−1)/143
// pixels on a bus (11 px on 100 LEDs, 18 on 162) and holds three colour
// slots, and every effect restarts at each bus. So a tile goes to the
// controller as a per-pixel `i` frame through the Design Studio spine
// (design_apply.dart): a solid base, then the lit colour of every pixel,
// range-compressed and chunked. That frame is a still picture — the
// controller freezes the segment — so a tile is applied live or saved as a
// painted design; scheduling follows the painted-design rules
// (design_api_preset.dart).
//
// WHY GAMMA HERE: the controller gamma-corrects every colour it receives
// (`light.gc.col` 2.8, the fleet standard), so a channel value `v` lights at
// `255·(v/255)^2.8`. A pixel meant to give 40 % of the light must be SENT at
// `255·0.40^(1/2.8)` = 184, not at 102 — 102 lights at 7.7 %. [rgbwAtLevel]
// does that inverse once, for every channel including W. The six shipped
// presets ("Deep Fade" 100/60/30 …) used to scale the colour value instead and
// lit at 100/24/3.4 %.
import 'dart:math' as math;

import 'package:nexgen_command/features/wled/per_pixel.dart';

/// The controller's colour gamma (`light.gc.col`, asserted by the healer).
const double kControllerColourGamma = 2.8;

/// The shape a tile was built from — kept so the tuner can re-open it on the
/// same controls, and so a design can say what it is.
enum BrightnessShape { triangle, ramp, steps, custom }

/// A repeating sequence of light levels (percent of full, 0–100), one per
/// tile cell; every cell is [bandWidth] pixels wide; the run starts
/// [offset] pixels into the cycle.
class BrightnessTile {
  final List<int> levels;
  final int bandWidth;
  final int offset;
  final BrightnessShape shape;

  BrightnessTile({
    required List<int> levels,
    this.bandWidth = 1,
    this.offset = 0,
    this.shape = BrightnessShape.custom,
  })  : assert(levels.isNotEmpty),
        assert(bandWidth >= 1),
        levels = List.unmodifiable(
            [for (final l in levels) l.clamp(0, 100)]);

  /// Bright → dim → bright over [cycle] pixels: the V the brief draws as T1
  /// (cycle 6: 100/80/60/40/60/80) and T2 (cycle 18).
  factory BrightnessTile.triangle({
    int brightest = 100,
    int dimmest = 40,
    int cycle = 6,
    int offset = 0,
  }) {
    final n = math.max(2, cycle);
    // Light 1 is the brightest; light m+1 (m = n ~/ 2) is the dimmest — a
    // real light at the dimmest level for every cycle length, not only even
    // ones (over 9 lights the old `1 - |1 - 2i/n|` bottomed out at 47 % for
    // a dimmest of 40). The fall takes m steps, the rise back n - m; for an
    // even cycle the two halves are mirror images, as before.
    final m = n ~/ 2;
    final span = brightest - dimmest;
    return BrightnessTile(
      levels: [
        for (var i = 0; i < n; i++)
          (i <= m
                  ? brightest - span * i / m
                  : brightest - span * (n - i) / (n - m))
              .round(),
      ],
      offset: offset,
      shape: BrightnessShape.triangle,
    );
  }

  /// Bright → dim over [cycle] pixels, then the cycle restarts bright.
  factory BrightnessTile.ramp({
    int brightest = 100,
    int dimmest = 40,
    int cycle = 6,
    int offset = 0,
  }) {
    final n = math.max(2, cycle);
    return BrightnessTile(
      levels: [
        for (var i = 0; i < n; i++)
          (brightest - (brightest - dimmest) * i / (n - 1)).round(),
      ],
      offset: offset,
      shape: BrightnessShape.ramp,
    );
  }

  /// Discrete steps, each [bandWidth] pixels wide (the shipped presets).
  factory BrightnessTile.steps(
    List<int> levels, {
    int bandWidth = 1,
    int offset = 0,
  }) =>
      BrightnessTile(
        levels: levels,
        bandWidth: bandWidth,
        offset: offset,
        shape: BrightnessShape.steps,
      );

  /// Pixels in one full cycle.
  int get cycleLength => levels.length * bandWidth;

  /// How many different levels the tile holds.
  int get distinctLevelCount => levels.toSet().length;

  int get brightest => levels.reduce(math.max);
  int get dimmest => levels.reduce(math.min);

  /// The light level of the pixel at channel-local index [pixel].
  int levelAt(int pixel) {
    final cycle = cycleLength;
    final idx = ((pixel + offset) % cycle + cycle) % cycle;
    return levels[idx ~/ bandWidth];
  }

  /// Light levels along a run of [length] pixels.
  List<int> levelsForRun(int length) =>
      [for (var p = 0; p < length; p++) levelAt(p)];

  BrightnessTile copyWith({
    List<int>? levels,
    int? bandWidth,
    int? offset,
    BrightnessShape? shape,
  }) =>
      BrightnessTile(
        levels: levels ?? this.levels,
        bandWidth: bandWidth ?? this.bandWidth,
        offset: offset ?? this.offset,
        shape: shape ?? this.shape,
      );

  Map<String, dynamic> toJson() => {
        'levels': levels,
        'band_width': bandWidth,
        'offset': offset,
        'shape': shape.name,
      };

  static BrightnessTile? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['levels'];
    if (raw is! List || raw.isEmpty) return null;
    final levels = <int>[];
    for (final v in raw) {
      if (v is num) levels.add(v.round());
    }
    if (levels.isEmpty) return null;
    final shapeName = json['shape'];
    final shape = BrightnessShape.values.firstWhere(
        (s) => s.name == shapeName,
        orElse: () => BrightnessShape.custom);
    return BrightnessTile(
      levels: levels,
      bandWidth: math.max(1, (json['band_width'] as num?)?.toInt() ?? 1),
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      shape: shape,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrightnessTile &&
      other.bandWidth == bandWidth &&
      other.offset == offset &&
      other.shape == shape &&
      other.levels.length == levels.length &&
      [for (var i = 0; i < levels.length; i++) other.levels[i] == levels[i]]
          .every((e) => e);

  @override
  int get hashCode => Object.hash(bandWidth, offset, shape, Object.hashAll(levels));

  @override
  String toString() =>
      'BrightnessTile(${shape.name} $levels ×$bandWidth +$offset)';
}

/// The channel value to SEND so the controller lights it at [levelPct] % of
/// [channel]'s own light — the inverse of the controller's gamma.
int channelAtLevel(int channel, int levelPct) {
  if (levelPct <= 0 || channel <= 0) return 0;
  if (levelPct >= 100) return channel.clamp(0, 255);
  final k = math.pow(levelPct / 100.0, 1 / kControllerColourGamma);
  return (channel * k).round().clamp(0, 255);
}

/// [baseRgbw] dimmed to [levelPct] % of its light, every channel including W.
List<int> rgbwAtLevel(List<int> baseRgbw, int levelPct) {
  final out = [0, 0, 0, 0];
  for (var i = 0; i < 4 && i < baseRgbw.length; i++) {
    out[i] = channelAtLevel(baseRgbw[i], levelPct);
  }
  return out;
}

/// The per-pixel spans that paint [tile] in [baseRgbw] along a run of
/// [length] pixels — FULL coverage (the controller blacks a segment before
/// its first per-pixel write), consecutive equal pixels merged.
List<PixelSpan> brightnessTileSpans(
  BrightnessTile tile,
  List<int> baseRgbw,
  int length,
) {
  if (length <= 0) return const [];
  final out = <PixelSpan>[];
  var runStart = 0;
  var runLevel = tile.levelAt(0);
  for (var p = 1; p <= length; p++) {
    final level = p < length ? tile.levelAt(p) : -1;
    if (level == runLevel) continue;
    out.add(PixelSpan(
        start: runStart, end: p - 1, color: rgbwAtLevel(baseRgbw, runLevel)));
    runStart = p;
    runLevel = level;
  }
  return out;
}

/// JSON elements one `i` array costs for [spans] (the controller's ceiling
/// is counted in elements, not bytes — see design_api_preset.dart): a single
/// pixel is `index, [r,g,b,w]` = 6, a range is `start, stop, [r,g,b,w]` = 7.
int perPixelElementCount(List<PixelSpan> spans) =>
    spans.fold(0, (n, s) => n + (s.start == s.end ? 6 : 7));

/// A shipped preset: a tile and the words on its card.
class BrightnessPatternPreset {
  final String id;
  final String name;
  final String description;
  final BrightnessTile tile;
  const BrightnessPatternPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.tile,
  });

  /// The levels as fractions of full, oldest-API shape (`steps`).
  List<double> get steps => [for (final l in tile.levels) l / 100];
}

/// The cards in every Brightness Patterns folder, first = the one the brief
/// asked for (T1), then its 18-pixel stretch (T2), then the six looks that
/// have shipped since 2026-03-17 (now rendering as they always previewed).
final List<BrightnessPatternPreset> kBrightnessPatternPresets = [
  BrightnessPatternPreset(
    id: 'wave6',
    name: 'Wave · 6 lights',
    description: '100 → 80 → 60 → 40 → 60 → 80, then again',
    tile: BrightnessTile.triangle(brightest: 100, dimmest: 40, cycle: 6),
  ),
  BrightnessPatternPreset(
    id: 'wave18',
    name: 'Wave · 18 lights',
    description: '100 down to 40 over nine lights and back',
    tile: BrightnessTile.triangle(brightest: 100, dimmest: 40, cycle: 18),
  ),
  BrightnessPatternPreset(
    id: 'gentle',
    name: 'Gentle Fade',
    description: 'Subtle brightness taper',
    tile: BrightnessTile.steps(const [100, 85, 70]),
  ),
  BrightnessPatternPreset(
    id: 'medium',
    name: 'Medium Fade',
    description: 'Balanced brightness falloff',
    tile: BrightnessTile.steps(const [100, 75, 50]),
  ),
  BrightnessPatternPreset(
    id: 'deep',
    name: 'Deep Fade',
    description: 'Dramatic brightness drop',
    tile: BrightnessTile.steps(const [100, 60, 30]),
  ),
  BrightnessPatternPreset(
    id: 'stair',
    name: 'Staircase',
    description: 'Even thirds brightness steps',
    tile: BrightnessTile.steps(const [100, 66, 33]),
  ),
  BrightnessPatternPreset(
    id: 'duo',
    name: 'Duo Alternate',
    description: 'Two-step bright/dim alternation',
    tile: BrightnessTile.steps(const [100, 70]),
  ),
  BrightnessPatternPreset(
    id: 'pulse',
    name: 'Soft Pulse',
    description: 'Rhythmic bright-dim-bright wave',
    tile: BrightnessTile.steps(const [100, 80, 100, 60]),
  ),
];

BrightnessPatternPreset? brightnessPatternPresetById(String id) {
  for (final p in kBrightnessPatternPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// The key a catalog card's `wledPayload` carries its tile under. Not a WLED
/// field: stripped before anything reaches a controller.
const String kBrightnessTilePayloadKey = '_brightnessTile';

/// The tile a pattern payload carries, or null for an ordinary effect card.
BrightnessTile? brightnessTileOf(Map<String, dynamic>? payload) =>
    payload == null ? null : BrightnessTile.fromJson(payload[kBrightnessTilePayloadKey]);

/// The base colour (RGBW) a tile card paints with: the payload's `col[0]`.
List<int>? brightnessTileBaseOf(Map<String, dynamic>? payload) {
  final segs = payload?['seg'];
  if (segs is! List) return null;
  for (final s in segs) {
    if (s is Map && s['col'] is List && (s['col'] as List).isNotEmpty) {
      final c = (s['col'] as List).first;
      if (c is List) {
        return [for (var i = 0; i < 4; i++) i < c.length ? (c[i] as num).toInt() : 0];
      }
    }
  }
  return null;
}
