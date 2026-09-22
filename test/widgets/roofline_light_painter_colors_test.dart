// test/widgets/roofline_light_painter_colors_test.dart
//
// The painter's COLOUR ASSIGNMENT in its solid branch — the test that did not
// exist when the hero roofline drew every solid look as alternating bands.
//
// Device truth (WLED 0.15.1, solid_palette_blocks.dart): fx 83 + a palette lays
// N colours out as N contiguous positional blocks; fx 84, and fx 83 + pal 0,
// cycle `col[]` in runs of `grp` LEDs. `roofline_projection_test.dart` covers
// where the dots land; this covers what colour each one is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/widgets/roofline_light_painter.dart';

const _r = Color(0xFFFF0000);
const _w = Color(0xFFFFFFFF);
const _b = Color(0xFF0000FF);

/// The colour of each of [count] LEDs, as the solid branch assigns them.
List<Color> _strip(RooflineLightPainter p, List<Color> colors, int count) =>
    [for (var i = 0; i < count; i++) p.solidLedColor(i, count, colors)];

/// Run-length encode a strip so a block partition reads as `[[R,n],[W,n],…]`.
List<List<Object>> _runs(List<Color> strip) {
  final out = <List<Object>>[];
  for (final c in strip) {
    if (out.isNotEmpty && out.last[0] == c) {
      out.last[1] = (out.last[1] as int) + 1;
    } else {
      out.add([c, 1]);
    }
  }
  return out;
}

/// Records every drawCircle centre; everything else is a no-op.
class _RecordingCanvas implements Canvas {
  final List<Offset> circles = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('solidLedColor — fx 83 + a palette is positional BLOCKS', () {
    test('three colours over 30 LEDs: three contiguous runs, slot order', () {
      final p = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 83, paletteId: 5);
      expect(_runs(_strip(p, const [_r, _w, _b], 30)), [
        [_r, 10],
        [_w, 10],
        [_b, 10],
      ]);
    });

    test('two colours: two halves', () {
      final p = RooflineLightPainter(colors: const [_r, _b], effectId: 83, paletteId: 5);
      expect(_runs(_strip(p, const [_r, _b], 20)), [
        [_r, 10],
        [_b, 10],
      ]);
    });

    test('is the SAME partition the dot row and the tile draw (one rule)', () {
      final p = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 83, paletteId: 5);
      for (var i = 0; i < 75; i++) {
        expect(p.solidLedColor(i, 75, const [_r, _w, _b]),
            const [_r, _w, _b][solidPaletteBlockIndex(i, 75, 3)],
            reason: 'LED $i');
      }
    });

    test('grp does not turn blocks into bands (the device ignores it for the '
        'partition; the hero used to draw (i ~/ grp) % N)', () {
      final p = RooflineLightPainter(
          colors: const [_r, _w, _b], effectId: 83, paletteId: 5, colorGroupSize: 3);
      expect(_runs(_strip(p, const [_r, _w, _b], 30)).length, 3,
          reason: 'three runs, not ten bands of three');
    });

    test('pal 4 (Color Gradient) is still a palette → blocks', () {
      final p = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 83, paletteId: 4);
      expect(p.solidPaintsBlocks(3), isTrue);
    });

    test('a fourth colour is ignored — WLED has three slots', () {
      const four = [_r, _w, _b, Color(0xFF00FF00)];
      final p = RooflineLightPainter(colors: four, effectId: 83, paletteId: 5);
      final runs = _runs(_strip(p, four, 30));
      expect(runs.map((r) => r[0]), [_r, _w, _b]);
    });
  });

  group('solidLedColor — everything else keeps the grp CYCLE', () {
    test('fx 84 (Alternating, three colours): r,w,b,r,w,b…', () {
      final p = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 84, paletteId: 5);
      expect(_strip(p, const [_r, _w, _b], 6), const [_r, _w, _b, _r, _w, _b]);
    });

    test('fx 83 + pal 0 (Alternating, two colours): r,b,r,b…', () {
      final p = RooflineLightPainter(colors: const [_r, _b], effectId: 83, paletteId: 0);
      expect(_strip(p, const [_r, _b], 6), const [_r, _b, _r, _b, _r, _b]);
      expect(p.solidPaintsBlocks(2), isFalse);
    });

    test('Alternating bands are exactly grp wide (rrr,www,bbb)', () {
      final p = RooflineLightPainter(
          colors: const [_r, _w, _b], effectId: 84, paletteId: 5, colorGroupSize: 3);
      expect(_strip(p, const [_r, _w, _b], 9),
          const [_r, _r, _r, _w, _w, _w, _b, _b, _b]);
    });

    test('plain fx 0 with several colours keeps the cycle (Edit Pattern\'s '
        'per-pixel preview relies on it)', () {
      final p = RooflineLightPainter(colors: const [_r, _b], effectId: 0, paletteId: 5);
      expect(_strip(p, const [_r, _b], 4), const [_r, _b, _r, _b]);
    });

    test('a single colour is flat under every fx / pal', () {
      for (final fx in [0, 83, 84]) {
        for (final pal in [0, 5]) {
          final p = RooflineLightPainter(colors: const [_r], effectId: fx, paletteId: pal);
          expect(_strip(p, const [_r], 5), List.filled(5, _r), reason: 'fx $fx pal $pal');
        }
      }
    });

    test('paletteId defaults to 0 — callers that never knew the palette draw '
        'exactly what they always did', () {
      final p = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 83);
      expect(p.paletteId, 0);
      expect(_strip(p, const [_r, _w, _b], 6), const [_r, _w, _b, _r, _w, _b]);
    });
  });

  group('the painter, not just the rule', () {
    // paint() through the solid branch: same dot count for both layouts (the
    // partition changes colours, never positions), and a palette change alone
    // is a repaint — otherwise a Blocks ↔ Alternating toggle would not redraw.
    const size = Size(240, 120);

    test('Blocks and Alternating place the same dots', () {
      List<Offset> render(int pal) {
        final rec = _RecordingCanvas();
        RooflineLightPainter(
          colors: const [_r, _w, _b],
          effectId: 83,
          paletteId: pal,
          useBoxFitCover: true,
          targetAspectRatio: 2.0,
        ).paint(rec, size);
        return rec.circles;
      }

      final blocks = render(5);
      final alternating = render(0);
      expect(blocks, isNotEmpty);
      expect(alternating, blocks);
    });

    test('shouldRepaint is true when only the palette changed', () {
      final a = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 83, paletteId: 5);
      final b = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 83, paletteId: 0);
      final c = RooflineLightPainter(colors: const [_r, _w, _b], effectId: 83, paletteId: 5);
      expect(b.shouldRepaint(a), isTrue);
      expect(c.shouldRepaint(a), isFalse);
    });
  });
}
