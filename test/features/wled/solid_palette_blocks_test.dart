// Preview/reality mismatch: Solid + a multi-colour palette.
//
// The device (WLED 0.15.1, fx 83 + pal:5) lays the palette out POSITIONALLY —
// N contiguous blocks in col[] order, thirds for three colours. The previews
// used to cycle colours bulb-by-bulb (`colors[i % N]`), which the hardware
// never renders. These tests pin the shared partition and the shared
// substitution decision, then prove the two preview surfaces use them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';

/// Renders every pixel of a [count]-pixel strip to its colour-slot index.
List<int> strip(int count, int colours) =>
    [for (var i = 0; i < count; i++) solidPaletteBlockIndex(i, count, colours)];

void main() {
  group('solidPaletteBlockIndex — the device partition', () {
    test('three colours → contiguous thirds, in slot order', () {
      expect(strip(18, 3), [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2]);
    });

    test('two colours → contiguous halves (generalises, not hardcoded to 3)', () {
      expect(strip(18, 2), [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
    });

    test('one colour → a single block (plain Solid shows col[0] only)', () {
      expect(strip(18, 1), List.filled(18, 0));
    });

    test('never alternates: the slot index is monotonic along the strip', () {
      for (final colours in [2, 3]) {
        for (final count in [3, 18, 100, 290]) {
          final s = strip(count, colours);
          for (var i = 1; i < s.length; i++) {
            expect(s[i] >= s[i - 1], isTrue,
                reason: 'pixel $i went backwards for $colours colours / $count px');
          }
          expect(s.first, 0);
          expect(s.last, colours - 1);
          expect(s.toSet().length, colours, reason: 'every colour gets a block');
        }
      }
    });

    test('a real 290-LED channel with three colours splits at 96/97 and 193/194', () {
      final s = strip(290, 3);
      expect(s[96], 0);
      expect(s[97], 1);
      expect(s[193], 1);
      expect(s[194], 2);
    });

    test('the midpoint of block k maps to slot k (what the painter relies on)',
        () {
      for (final n in [1, 2, 3]) {
        for (var k = 0; k < n; k++) {
          final mid = (2 * k + 1) * 1000 ~/ (2 * n);
          expect(solidPaletteBlockIndex(mid, 1000, n), k,
              reason: 'n=$n k=$k mid=$mid');
        }
      }
      // The left edge is NOT safe: k=2 of 3 truncates to 666 → slot 1.
      expect(solidPaletteBlockIndex(2 * 1000 ~/ 3, 1000, 3), 1);
    });

    test('the old per-bulb formula is NOT what this produces', () {
      final old = [for (var i = 0; i < 18; i++) i % 3];
      expect(strip(18, 3), isNot(old));
    });

    test('clamps to WLED\'s three colour slots and tolerates junk indices', () {
      expect(solidPaletteBlockIndex(17, 18, 7), 2);
      expect(solidPaletteBlockIndex(-5, 18, 3), 0);
      expect(solidPaletteBlockIndex(999, 18, 3), 2);
      expect(solidPaletteBlockIndex(0, 0, 3), 0);
    });
  });

  group('isSolidPaletteSubstitution — the shared apply/preview decision', () {
    test('Solid with 2+ colours is substituted (fx 83)', () {
      expect(isSolidPaletteSubstitution(effectId: 0, colorCount: 2), isTrue);
      expect(isSolidPaletteSubstitution(effectId: 0, colorCount: 3), isTrue);
      expect(effectiveSolidEffectId(effectId: 0, colorCount: 3), 83);
    });

    test('Solid with one colour stays Solid', () {
      expect(isSolidPaletteSubstitution(effectId: 0, colorCount: 1), isFalse);
      expect(effectiveSolidEffectId(effectId: 0, colorCount: 1), 0);
    });

    test('architectural palettes keep Solid — spacing comes from grp/spc', () {
      expect(
        isSolidPaletteSubstitution(
            effectId: 0, colorCount: 3, isArchitectural: true),
        isFalse,
      );
      expect(
        effectiveSolidEffectId(
            effectId: 0, colorCount: 3, isArchitectural: true),
        0,
      );
    });

    test('a genuine alternating effect is untouched (only Solid changes)', () {
      // 28 = Chase — a real chase must still preview and apply as a chase.
      expect(isSolidPaletteSubstitution(effectId: 28, colorCount: 3), isFalse);
      expect(effectiveSolidEffectId(effectId: 28, colorCount: 3), 28);
      expect(getPreviewType(28), EffectPreviewType.chase);
    });
  });

  group('EffectPreviewWidget — the tile preview', () {
    const red = Color(0xFFFF0000);
    const white = Color(0xFFFFFFFF);
    const blue = Color(0xFF0000FF);

    Future<void> pump(WidgetTester t, int fx, List<Color> colors) {
      // Center hands the SizedBox loose constraints; as a bare `home` it
      // would be stretched to the full test surface and the widths below
      // would be meaningless.
      return t.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 90,
            height: 30,
            child: EffectPreviewWidget(effectId: fx, colors: colors),
          ),
        ),
      ));
    }

    /// Colour → left edge, for the block Containers that were laid out.
    Map<Color, double> blockEdges(WidgetTester t, List<Color> colors) {
      final out = <Color, double>{};
      for (final c in colors) {
        final f = find.byWidgetPredicate(
            (w) => w is Container && w.color == c && w.decoration == null);
        if (f.evaluate().isNotEmpty) out[c] = t.getTopLeft(f.first).dx;
      }
      return out;
    }

    testWidgets('fx 83 + three colours renders three ordered contiguous blocks',
        (t) async {
      await pump(t, 83, const [red, white, blue]);
      final edges = blockEdges(t, const [red, white, blue]);
      expect(edges.keys, containsAll([red, white, blue]),
          reason: 'one block per colour');
      expect(edges[red]! < edges[white]!, isTrue, reason: 'col[0] first');
      expect(edges[white]! < edges[blue]!, isTrue, reason: 'col[1] second');
      // Equal thirds of a 90px strip.
      expect(edges[white]! - edges[red]!, closeTo(30, 0.5));
      expect(edges[blue]! - edges[white]!, closeTo(30, 0.5));
    });

    testWidgets('fx 83 + two colours renders two halves', (t) async {
      await pump(t, 83, const [red, blue]);
      final edges = blockEdges(t, const [red, blue]);
      expect(edges.keys, containsAll([red, blue]));
      expect(edges[blue]! - edges[red]!, closeTo(45, 0.5));
    });

    testWidgets('plain fx 0 still previews as one flat colour (col[0])',
        (t) async {
      await pump(t, 0, const [red, white, blue]);
      final edges = blockEdges(t, const [red, white, blue]);
      expect(edges.keys, [red], reason: 'fx 0 shows col[0] only on the device');
    });

    testWidgets('a chase (fx 28) does not become blocks', (t) async {
      await pump(t, 28, const [red, white, blue]);
      expect(blockEdges(t, const [red, white, blue]), isEmpty,
          reason: 'animated painters do not build flat colour Containers');
    });
  });
}
