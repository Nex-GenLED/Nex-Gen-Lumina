// The Alternating layout for Solid + a multi-colour palette.
//
// Device truth (WLED 0.15.1 source): 3 colours → fx 84 writes SEGCOLOR(0..2)
// in runs of (ix>>5)+1 VIRTUAL pixels; 2 colours → fx 83 at pal:0 writes
// col[0]/col[1] in runs of 1+sx / 1+ix; and every virtual pixel is expanded
// to `grouping` physical LEDs (i *= groupLength()). So the wire form is ix=0
// (or sx=ix=0), pal:0 for two colours, and the band width lives in grp — NOT
// in ix AND grp (which the firmware multiplies).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

void main() {
  group('solidLayoutFields — the wire form of each layout', () {
    test('Blocks is unchanged: fx 83 + pal:5, no sx/ix pins', () {
      for (final n in [2, 3]) {
        final f = solidLayoutFields(
            layout: SolidLayout.blocks, colorCount: n, ledsPerColor: 1);
        expect(f.fx, 83);
        expect(f.pal, 5);
        expect(f.sx, isNull);
        expect(f.ix, isNull);
      }
    });

    test('Alternating, 3 colours → fx 84 with ix:0 (1-px runs), width in grp',
        () {
      for (final w in [1, 2, 3, 5, 10]) {
        final f = solidLayoutFields(
            layout: SolidLayout.alternating, colorCount: 3, ledsPerColor: w);
        expect(f.fx, 84);
        expect(f.ix, 0, reason: 'segSize = (0 >> 5) + 1 = 1 virtual pixel');
        expect(f.grp, w, reason: 'the band width is grp, not ix');
      }
    });

    test('Alternating, 2 colours → fx 83 with pal:0 and sx=ix=0', () {
      final f = solidLayoutFields(
          layout: SolidLayout.alternating, colorCount: 2, ledsPerColor: 4);
      expect(f.fx, 83);
      expect(f.pal, 0,
          reason: 'pal:5 would map the palette POSITIONALLY (half alternating, '
              'half solid col[1]); pal:0 makes color_from_palette return '
              'SEGCOLOR(0)');
      expect(f.sx, 0);
      expect(f.ix, 0);
      expect(f.grp, 4);
    });

    test('never sends a band size AND grp (the N×N bug)', () {
      for (final n in [2, 3]) {
        for (final w in [2, 3, 5]) {
          final f = solidLayoutFields(
              layout: SolidLayout.alternating, colorCount: n, ledsPerColor: w);
          expect(f.ix ?? 0, 0);
          expect(f.sx ?? 0, 0);
          expect(f.grp, w);
        }
      }
    });

    test('one colour is plain Solid in either layout', () {
      for (final l in SolidLayout.values) {
        final f =
            solidLayoutFields(layout: l, colorCount: 1, ledsPerColor: 3);
        expect(f.fx, 0);
        expect(f.grp, 1);
      }
    });

    test('colour count clamps to WLED\'s three slots', () {
      final f = solidLayoutFields(
          layout: SolidLayout.alternating, colorCount: 6, ledsPerColor: 1);
      expect(f.fx, 84);
    });
  });

  group('alternatingBandIndex — the device\'s grp expansion', () {
    List<int> strip(int count, int w, int n) =>
        [for (var i = 0; i < count; i++) alternatingBandIndex(i, w, n)];

    test('1-wide, 3 colours: r,w,b,r,w,b…', () {
      expect(strip(9, 1, 3), [0, 1, 2, 0, 1, 2, 0, 1, 2]);
    });

    test('3-wide, 3 colours: rrr,www,bbb — exactly ledsPerColor, not N×N',
        () {
      expect(strip(9, 3, 3), [0, 0, 0, 1, 1, 1, 2, 2, 2]);
      expect(strip(18, 3, 3).sublist(9), [0, 0, 0, 1, 1, 1, 2, 2, 2]);
    });

    test('2-wide, 2 colours', () {
      expect(strip(8, 2, 2), [0, 0, 1, 1, 0, 0, 1, 1]);
    });

    test('it ALTERNATES — unlike the positional block partition', () {
      final alt = strip(18, 1, 3);
      final blocks =
          [for (var i = 0; i < 18; i++) solidPaletteBlockIndex(i, 18, 3)];
      expect(alt, isNot(blocks));
      expect(alt.toSet().length, 3);
      // Every colour appears within the first N pixels — the defining
      // property of alternating that blocks do not have.
      expect(alt.take(3).toSet().length, 3);
      expect(blocks.take(3).toSet().length, 1);
    });
  });

  group('SelectorState.paletteOverride', () {
    test('absent → pal derived from the effect (prior behaviour)', () {
      final seg = (buildSelectorPayload(const SelectorState(
        effectId: 83,
        speed: 0,
        intensity: 0,
        colors: [
          [255, 0, 0, 0],
          [0, 0, 255, 0]
        ],
      ))['seg'] as List)
          .first as Map;
      expect(seg['pal'], WledEffectsCatalog.paletteForEffect(83));
    });

    test('present → wins, and survives the payload → state round trip', () {
      const st = SelectorState(
        effectId: 83,
        speed: 0,
        intensity: 0,
        grouping: 3,
        colors: [
          [255, 0, 0, 0],
          [0, 0, 255, 0]
        ],
        paletteOverride: 0,
      );
      final payload = buildSelectorPayload(st);
      final seg = (payload['seg'] as List).first as Map;
      expect(seg['pal'], 0);
      expect(seg['grp'], 3);
      final back = selectorStateFromPayload(payload);
      expect(back.paletteOverride, 0,
          reason: 'a 2-colour Alternating design must not be rewritten to '
              'positional pal:5 on its next save');
      expect(buildSelectorPayload(back), payload);
    });

    test('a derived pal does NOT read back as an override', () {
      final payload = buildSelectorPayload(const SelectorState(
        effectId: 28,
        speed: 100,
        intensity: 100,
        colors: [
          [255, 0, 0, 0]
        ],
      ));
      expect(selectorStateFromPayload(payload).paletteOverride, isNull);
    });
  });

  group('EffectPreviewWidget — alternating tile', () {
    const red = Color(0xFFFF0000);
    const white = Color(0xFFFFFFFF);
    const blue = Color(0xFF0000FF);

    Future<void> pump(WidgetTester t, int fx, List<Color> colors,
        {int? alternating}) {
      return t.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 30,
            child: EffectPreviewWidget(
              effectId: fx,
              colors: colors,
              alternatingLedsPerColor: alternating,
            ),
          ),
        ),
      ));
    }

    /// The flat-colour cells in left-to-right order.
    List<Color> cells(WidgetTester t) {
      final f = find.byWidgetPredicate(
          (w) => w is Container && w.color != null && w.decoration == null);
      final entries = f.evaluate().map((e) {
        final w = e.widget as Container;
        return MapEntry(t.getTopLeft(find.byWidget(w)).dx, w.color!);
      }).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return [for (final e in entries) e.value];
    }

    testWidgets('Alternating, 1-wide, 3 colours: 12 cells cycling r,w,b',
        (t) async {
      await pump(t, 84, const [red, white, blue], alternating: 1);
      final c = cells(t);
      expect(c, hasLength(kAlternatingPreviewCells));
      expect(c.take(6).toList(), [red, white, blue, red, white, blue]);
    });

    testWidgets('Alternating, 3-wide: rrr,www,bbb — the width the user chose',
        (t) async {
      await pump(t, 84, const [red, white, blue], alternating: 3);
      final c = cells(t);
      expect(c.take(9).toList(),
          [red, red, red, white, white, white, blue, blue, blue]);
    });

    testWidgets('Alternating, 2 colours on fx 83 (pal:0 path): r,b,r,b…',
        (t) async {
      await pump(t, 83, const [red, blue], alternating: 1);
      expect(cells(t).take(4).toList(), [red, blue, red, blue]);
    });

    testWidgets('Blocks (no width given) on fx 83 is UNCHANGED: 3 blocks',
        (t) async {
      await pump(t, 83, const [red, white, blue]);
      final c = cells(t);
      expect(c, [red, white, blue], reason: 'the prior fix must not regress');
    });

    testWidgets('fx 84 picked as a catalog effect previews alternating (1-wide)',
        (t) async {
      await pump(t, 84, const [red, white, blue]);
      expect(cells(t).take(3).toList(), [red, white, blue]);
      expect(cells(t), hasLength(kAlternatingPreviewCells));
    });

    testWidgets('a chase is untouched by the new parameter', (t) async {
      await pump(t, 28, const [red, white, blue], alternating: 2);
      expect(cells(t), isEmpty);
      expect(getPreviewType(28), EffectPreviewType.chase);
    });
  });
}
