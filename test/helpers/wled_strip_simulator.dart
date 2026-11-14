// A pure-Dart model of what a WLED 0.15.x controller RENDERS for one
// `/json/state` segment, so a test can look at the strip a payload produces
// instead of at the payload's fields.
//
// Modelled from the firmware source (0.15.1 and 0.15.4 `FX.cpp`,
// `FX_fcn.cpp`, `json.cpp`, `colors.cpp`) and anchored to live-view frames
// read from the bench controllers on 2026-11-14
// (docs/bench/brightness_patterns_129_bench_2026-11-14.md):
//
//   * colours are gamma-corrected (`light.gc.col` 2.8, the fleet standard)
//     before any blending: `SEGCOLOR(n)` is `gamma32(col[n])`, palette stops
//     are gamma32'd, and every `i` pixel is gamma32'd at deserialise;
//   * fx 0 Solid, fx 2 Breathe (at its brightest instant), fx 65 Palette
//     (rotation `c1`, Size `ix`, Shift `sx`, still), fx 83 Solid Pattern,
//     fx 84 Solid Pattern Tri, and per-pixel `i` arrays (single index and
//     [start, stopExclusive) ranges, RGBW lists);
//   * palettes 0 (segment colours direct), 2, 3, 4 ("Color Gradient" =
//     `CRGBPalette16(col2, col1, col0)`) and 5 ("Colors Only", the positional
//     `[c0×5, c1×5, c2×5, c0]` or `[c0×8, c1×8]`), linear blend
//     (`light.pal-mode` 0).
//
// Output pixels are the LIT colour: the 8-bit RGBW the LEDs receive before
// master brightness, which is what the controller's live view reports.
import 'dart:math' as math;

/// `gamma32` for one 8-bit channel at gamma 2.8 (`calcGammaTable`).
int gamma8(int v) => (math.pow(v.clamp(0, 255) / 255.0, 2.8) * 255.0 + 0.5).toInt();

/// The channel value whose lit output is [lightPct] % of full (inverse gamma).
int valueForLight(double lightPct) =>
    (255 * math.pow(lightPct.clamp(0, 100) / 100.0, 1 / 2.8)).round().clamp(0, 255);

List<int> _gamma32(List<int> rgbw) => [for (final c in _rgbw(rgbw)) gamma8(c)];

List<int> _rgbw(List<dynamic> c) {
  final out = [0, 0, 0, 0];
  for (var i = 0; i < c.length && i < 4; i++) {
    out[i] = (c[i] as num).toInt().clamp(0, 255);
  }
  return out;
}

/// FastLED `scale8`.
int _scale8(int i, int scale) => (i * (scale + 1)) >> 8;

/// FastLED `CRGBPalette16(c1, c2, c3)` / `(c1, c2)`: 16 RGB entries.
List<List<int>> _gradient16(List<List<int>> stops) {
  final entries = List<List<int>>.generate(16, (_) => [0, 0, 0]);
  if (stops.length == 1) {
    for (var i = 0; i < 16; i++) {
      entries[i] = stops[0].sublist(0, 3);
    }
    return entries;
  }
  void fill(int from, List<int> a, int to, List<int> b) {
    final span = math.max(1, to - from);
    for (var i = from; i <= to; i++) {
      for (var ch = 0; ch < 3; ch++) {
        entries[i][ch] = (a[ch] + (b[ch] - a[ch]) * (i - from) / span).round();
      }
    }
  }
  if (stops.length == 2) {
    fill(0, stops[0], 15, stops[1]);
  } else {
    fill(0, stops[0], 8, stops[1]);
    fill(8, stops[1], 15, stops[2]);
  }
  return entries;
}

/// FastLED `ColorFromPalette(pal, index, 255, LINEARBLEND)`.
List<int> _colorFromPalette(List<List<int>> entries, int index) {
  final idx = index & 0xFF;
  final hi4 = idx >> 4;
  final lo4 = idx & 0x0F;
  final e1 = entries[hi4];
  final e2 = entries[(hi4 + 1) & 0x0F];
  if (lo4 == 0) return [...e1];
  final f2 = lo4 << 4;
  final f1 = 255 - f2;
  return [
    for (var ch = 0; ch < 3; ch++)
      (_scale8(e1[ch], f1) + _scale8(e2[ch], f2)).clamp(0, 255),
  ];
}

bool _isBlack(List<int> c) => c[0] == 0 && c[1] == 0 && c[2] == 0 && c[3] == 0;

/// Renders one WLED segment of [length] virtual pixels.
///
/// [seg] is the segment as it would reach the controller (after the app's
/// chokepoint, so `sx`/`ix`/`pal`/`c1`… are stated). [segmentIndex] and
/// [segmentCount] matter only to fx 65, whose rotation reads the segment
/// number. Returns [length] lit RGBW pixels.
class WledStripSimulator {
  const WledStripSimulator();

  List<List<int>> render(
    Map<String, dynamic> seg,
    int length, {
    int segmentIndex = 0,
    int segmentCount = 1,
  }) {
    final out = List<List<int>>.generate(length, (_) => [0, 0, 0, 0]);
    if (length <= 0) return out;
    if (seg['on'] == false) return out;

    final rawCols = (seg['col'] as List?) ?? const [];
    final cols = <List<int>>[
      for (var i = 0; i < 3; i++)
        i < rawCols.length ? _rgbw(rawCols[i] as List) : [0, 0, 0, 0],
    ];
    final lit = [for (final c in cols) _gamma32(c)]; // SEGCOLOR(n)
    final pal = (seg['pal'] as num?)?.toInt() ?? 0;
    final sx = (seg['sx'] as num?)?.toInt() ?? 128;
    final ix = (seg['ix'] as num?)?.toInt() ?? 128;
    final c1 = (seg['c1'] as num?)?.toInt() ?? 128;
    final o1 = seg['o1'] == true;
    final o2 = seg['o2'] == true;

    // Per-pixel paint: the segment is frozen and filled black first.
    final iarr = seg['i'];
    if (iarr is List) {
      _paint(out, iarr, length);
      return out;
    }

    final fx = (seg['fx'] as num?)?.toInt() ?? 0;
    final palette = _loadPalette(pal, lit);

    // Segment::color_from_palette(i, mapping, wrap, mcol)
    List<int> fromPalette(int i, bool mapping, bool wrap, int mcol) {
      final color = lit[mcol];
      if (palette == null) return [...color];
      var paletteIndex = i;
      if (mapping && length > 1) paletteIndex = (i * 255) ~/ (length - 1);
      if (!wrap) paletteIndex = _scale8(paletteIndex, 240);
      final rgb = _colorFromPalette(palette, paletteIndex);
      return [rgb[0], rgb[1], rgb[2], color[3]];
    }

    switch (fx) {
      case 0: // Solid
        for (var i = 0; i < length; i++) {
          out[i] = [...lit[0]];
        }
        return out;
      case 2: // Breathe, at its brightest instant (lum 254)
        for (var i = 0; i < length; i++) {
          out[i] = _blend(lit[1], fromPalette(i, true, false, 0), 254);
        }
        return out;
      case 83: // Solid Pattern: lit = 1 + sx of palette, unlit = 1 + ix of col[1]
        final litN = 1 + sx;
        final unlitN = 1 + ix;
        var drawingLit = true;
        var cnt = 0;
        for (var i = 0; i < length; i++) {
          out[i] = drawingLit ? fromPalette(i, true, false, 0) : [...lit[1]];
          cnt++;
          if (cnt >= (drawingLit ? litN : unlitN)) {
            cnt = 0;
            drawingLit = !drawingLit;
          }
        }
        return out;
      case 84: // Solid Pattern Tri
        final segSize = (ix >> 5) + 1;
        var currSeg = 0;
        var count = 0;
        for (var i = 0; i < length; i++) {
          out[i] = [...lit[currSeg % 3]];
          count++;
          if (count >= segSize) {
            currSeg++;
            count = 0;
          }
        }
        return out;
      case 65: // Palette (still: o1 Animate Shift off, o2 Animate Rotation off)
        if (o1 || o2) {
          throw UnsupportedError('fx 65 with animation is time-varying');
        }
        final maxX = math.max(1, length - 1).toDouble();
        final maxY = math.max(1, segmentCount - 1).toDouble();
        final theta = (c1 + 128) * math.pi / 256.0;
        final sinT = math.sin(theta);
        final cosT = math.cos(theta);
        // o3 (Anamorphic) on: maxXIn = maxX, maxYIn = maxY, maxXOut = maxYOut = 1
        final scale = sinT.abs() + cosT.abs();
        const centerX = 0.5, centerY = 0.5;
        final y = segmentIndex.toDouble();
        final ytCosTheta = cosT * (y - centerY * maxY) / (maxY * scale);
        for (var x = 0; x < length; x++) {
          final xtSinTheta = sinT * (x - centerX * maxX) / (maxX * scale);
          final sourceX = xtSinTheta + ytCosTheta + centerX;
          var colorIndex = (sourceX.clamp(0.0, 1.0) * 255).toInt();
          if (ix <= 128) {
            colorIndex = (colorIndex * ix) ~/ 128;
          } else {
            colorIndex = ((ix - 112) * colorIndex) ~/ 16;
          }
          colorIndex -= sx;
          out[x] = _colorWheel(colorIndex & 0xFF, palette, lit[0]);
        }
        return out;
      default:
        throw UnsupportedError('fx $fx is not modelled by WledStripSimulator');
    }
  }

  /// `Segment::color_wheel`: palette lookup, or the rainbow hue wheel on pal 0.
  List<int> _colorWheel(int pos, List<List<int>>? palette, List<int> col0) {
    if (palette != null) {
      final rgb = _colorFromPalette(palette, pos);
      return [rgb[0], rgb[1], rgb[2], col0[3]];
    }
    final w = col0[3];
    var p = 255 - pos;
    if (p < 85) return [255 - p * 3, 0, p * 3, w];
    if (p < 170) {
      p -= 85;
      return [0, p * 3, 255 - p * 3, w];
    }
    p -= 170;
    return [p * 3, 255 - p * 3, 0, w];
  }

  /// `Segment::loadPalette` for the segment-colour palettes; null = pal 0.
  List<List<int>>? _loadPalette(int pal, List<List<int>> lit) {
    switch (pal) {
      case 0:
        return null;
      case 2:
        return _gradient16([lit[0]]);
      case 3:
        return _gradient16([lit[0], lit[1]]);
      case 4:
        return _gradient16([lit[2], lit[1], lit[0]]);
      case 5:
        final p = lit[0].sublist(0, 3), s = lit[1].sublist(0, 3);
        if (!_isBlack(lit[2])) {
          final t = lit[2].sublist(0, 3);
          return [p, p, p, p, p, s, s, s, s, s, t, t, t, t, t, p];
        }
        return [p, p, p, p, p, p, p, p, s, s, s, s, s, s, s, s];
      default:
        throw UnsupportedError('palette $pal is not modelled (built-in palette)');
    }
  }

  List<int> _blend(List<int> a, List<int> b, int blend) => [
        for (var ch = 0; ch < 4; ch++)
          ((a[ch] * (255 - blend) + b[ch] * blend) ~/ 255).clamp(0, 255),
      ];

  void _paint(List<List<int>> out, List iarr, int length) {
    var start = 0, stop = 0, set = 0;
    for (final item in iarr) {
      if (item is num) {
        if (set == 0) {
          start = item.toInt().abs();
          set = 1;
        } else {
          stop = item.toInt().abs();
          set = 2;
        }
        continue;
      }
      if (item is! List) continue;
      if (set < 2 || stop <= start) stop = start + 1;
      final c = _gamma32(_rgbw(item));
      for (var p = start; p < stop && p < length; p++) {
        out[p] = [...c];
      }
      set = 0;
    }
  }
}

/// Light level of each pixel as a percentage of the brightest pixel's
/// strongest channel (white → every channel equal). A black strip is all 0.
List<double> lightLevels(List<List<int>> pixels) {
  if (pixels.isEmpty) return const [];
  var peak = 0;
  var peakCh = 0;
  for (final p in pixels) {
    for (var ch = 0; ch < 3; ch++) {
      if (p[ch] > peak) {
        peak = p[ch];
        peakCh = ch;
      }
    }
  }
  if (peak == 0) return List.filled(pixels.length, 0);
  return [for (final p in pixels) p[peakCh] / peak * 100];
}

/// Renders every design segment of a wire [payload] onto channels of the
/// given lengths (channel id → length). A segment without `id` is segment 0.
/// Later payloads paint over earlier ones (call once per body, in order).
Map<int, List<List<int>>> renderPayloadOnto(
  Map<String, dynamic> payload,
  Map<int, int> channelLengths, {
  Map<int, List<List<int>>>? into,
}) {
  final sim = const WledStripSimulator();
  final strips = into ??
      {
        for (final e in channelLengths.entries)
          e.key: List<List<int>>.generate(e.value, (_) => [0, 0, 0, 0]),
      };
  final segs = payload['seg'];
  if (segs is! List) return strips;
  final ids = channelLengths.keys.toList()..sort();
  for (final raw in segs) {
    if (raw is! Map) continue;
    final seg = Map<String, dynamic>.from(raw);
    final id = (seg['id'] as num?)?.toInt() ?? 0;
    final len = channelLengths[id];
    if (len == null) continue;
    if (seg['on'] == false) {
      strips[id] = List<List<int>>.generate(len, (_) => [0, 0, 0, 0]);
      continue;
    }
    if (!seg.containsKey('fx') && !seg.containsKey('i')) continue;
    strips[id] = sim.render(seg, len,
        segmentIndex: ids.indexOf(id), segmentCount: ids.length);
  }
  return strips;
}
