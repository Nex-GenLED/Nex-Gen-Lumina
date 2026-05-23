// Tests for composeEffectLabel — the Now Playing label composer
// (Fix 3 / Bug A).
//
// Heuristic (audit-locked):
//   - labelHint == null                        → returns null
//   - effectId not in WledEffectsCatalog       → returns labelHint unchanged
//   - labelHint != effect.name (case-fold)     → returns labelHint unchanged
//     (caller has a custom label like "Royals Game Day" — leave alone)
//   - effect.colorBehavior is generatesOwnColors
//     or usesPalette                           → returns labelHint unchanged
//     (effect ignores user colors — appending would mislead)
//   - all colors resolve to pad/unknown/custom → returns labelHint unchanged
//     (nothing nameable to append)
//   - else                                     → "EffectName Color[/Color][/Color]"
//
// Effects from the catalog used in these tests:
//   id 0  = Solid     (usesSelectedColors)
//   id 17 = Twinkle   (usesSelectedColors)
//   id 9  = Rainbow   (generatesOwnColors)
//   id 65 = Palette   (usesPalette)

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

void main() {
  group('composeEffectLabel — happy path (effect uses selected colors)', () {
    test('Solid + single red → "Solid Red"', () {
      final result = composeEffectLabel(
        labelHint: 'Solid',
        effectId: 0,
        colors: const [
          [255, 0, 0, 0],
        ],
      );
      expect(result, equals('Solid Red'));
    });

    test('Twinkle + red+green → "Twinkle Red/Green"', () {
      final result = composeEffectLabel(
        labelHint: 'Twinkle',
        effectId: 17,
        colors: const [
          [255, 0, 0, 0],
          [0, 255, 0, 0],
        ],
      );
      expect(result, equals('Twinkle Red/Green'));
    });

    test(
        'Solid + post-Fix-2 padded 3-slot col (red + 2 pads) → "Solid Red" '
        '(pad slots resolve to "custom" and are dropped)', () {
      final result = composeEffectLabel(
        labelHint: 'Solid',
        effectId: 0,
        colors: const [
          [255, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
      );
      expect(result, equals('Solid Red'));
    });

    test(
        'labelHint case-insensitive match against effect.name. "solid" '
        '(lowercase) still composes against the catalog\'s "Solid".', () {
      final result = composeEffectLabel(
        labelHint: 'solid',
        effectId: 0,
        colors: const [
          [255, 0, 0, 0],
        ],
      );
      // Preserves the caller\'s casing on the prefix, appends Title-Cased
      // color name.
      expect(result, equals('solid Red'));
    });

    test('three-color effect → all three named colors appear', () {
      final result = composeEffectLabel(
        labelHint: 'Twinkle',
        effectId: 17,
        colors: const [
          [255, 0, 0, 0],
          [255, 255, 255, 0],
          [0, 0, 255, 0],
        ],
      );
      expect(result, equals('Twinkle Red/White/Blue'));
    });

    test('duplicate colors are deduped in the assembled list', () {
      final result = composeEffectLabel(
        labelHint: 'Twinkle',
        effectId: 17,
        colors: const [
          [255, 0, 0, 0],
          [255, 0, 0, 0],
          [0, 0, 255, 0],
        ],
      );
      expect(result, equals('Twinkle Red/Blue'));
    });
  });

  group('composeEffectLabel — leave-alone guards', () {
    test(
        'custom labelHint ("Royals Game Day") never matches a catalog '
        'effect.name → returns labelHint unchanged. This is the key '
        'guard against "Royals Game Day Red" mislabels.', () {
      final result = composeEffectLabel(
        labelHint: 'Royals Game Day',
        effectId: 17,
        colors: const [
          [255, 0, 0, 0],
          [0, 0, 255, 0],
        ],
      );
      expect(result, equals('Royals Game Day'));
    });

    test('Rainbow (generatesOwnColors) → labelHint unchanged', () {
      final result = composeEffectLabel(
        labelHint: 'Rainbow',
        effectId: 9,
        colors: const [
          [255, 0, 0, 0],
        ],
      );
      expect(result, equals('Rainbow'));
    });

    test('Palette (usesPalette) → labelHint unchanged', () {
      final result = composeEffectLabel(
        labelHint: 'Palette',
        effectId: 65,
        colors: const [
          [255, 0, 0, 0],
        ],
      );
      expect(result, equals('Palette'));
    });

    test('labelHint == null → returns null (TRANSIENT semantics)', () {
      final result = composeEffectLabel(
        labelHint: null,
        effectId: 0,
        colors: const [
          [255, 0, 0, 0],
        ],
      );
      expect(result, isNull);
    });

    test('effectId not in the catalog (e.g. -1) → labelHint unchanged', () {
      final result = composeEffectLabel(
        labelHint: 'Solid',
        effectId: -1,
        colors: const [
          [255, 0, 0, 0],
        ],
      );
      expect(result, equals('Solid'));
    });

    test(
        'all colors resolve to "custom" (no named bucket) → labelHint '
        'unchanged. Appending nothing leaves the chip cleaner than '
        '"Solid Custom".', () {
      final result = composeEffectLabel(
        labelHint: 'Solid',
        effectId: 0,
        colors: const [
          [120, 80, 160, 0], // muted purple-ish, no bucket
        ],
      );
      expect(result, equals('Solid'));
    });

    test(
        'colors list is empty (caller had no color info) → labelHint '
        'unchanged', () {
      final result = composeEffectLabel(
        labelHint: 'Solid',
        effectId: 0,
        colors: const [],
      );
      expect(result, equals('Solid'));
    });

    test(
        'colors all pad slots (after Fix 2 padding, but the apply was '
        'a partial update that didn\'t name any real color) → unchanged', () {
      final result = composeEffectLabel(
        labelHint: 'Solid',
        effectId: 0,
        colors: const [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
      );
      expect(result, equals('Solid'));
    });
  });
}
