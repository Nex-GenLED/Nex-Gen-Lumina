// Tests for normalizeWledPayload's col-slot padding (Fix 2 / Bug B).
//
// Background:
//   WLED's seg.col is a 3-slot fixed array. A partial-col apply (1 or 2
//   color slots) leaves the device's unspecified slots holding the PRIOR
//   pattern's colors. On the next /json/state poll the app reads back
//   new-slot-0 + stale-slots-1/2 and the dashboard renders all three →
//   the "blend" symptom.
//
// Lights on the device are correct (the effect engine only consumes the
// slots its fx needs). This is a display-only bug.
//
// Fix:
//   normalizeWledPayload (the shared chokepoint every applyJson flows
//   through, local + remote bridge + savePreset) pads col UP to 3 slots
//   with [0, 0, 0, 0] when col is present and non-empty. The device
//   receives an explicit 3-slot col → next poll reads coherent state.
//
// Guarantees this padding MUST preserve (the "leave alone" cases):
//   - payload with NO col key            → untouched (no synthesis)
//   - col present but empty []           → untouched (no slot info)
//   - col with > 3 slots                 → untouched (pad up only)
//   - non-fx ("partial update") payload  → untouched (slider tweaks)
//   - per-pixel i[] arrays               → untouched (not col)
//
// And validateRgbwList still runs FIRST: a 3-channel input like
// [r, g, b] is first padded to [r, g, b, 0] then the slot pad uses
// the 4-channel black [0, 0, 0, 0] to match.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

void main() {
  group('normalizeWledPayload — col slot padding (Fix 2)', () {
    test('1-color col → padded to 3 slots, slots 1+2 are [0,0,0,0]', () {
      final result = normalizeWledPayload({
        'on': true,
        'seg': [
          {
            'fx': 0,
            'col': [
              [255, 0, 0, 0],
            ],
          },
        ],
      });
      final col = ((result['seg'] as List).first as Map)['col'];
      expect(col, equals([
        [255, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('2-color col → padded to 3 slots, slot 2 is [0,0,0,0]', () {
      final result = normalizeWledPayload({
        'on': true,
        'seg': [
          {
            'fx': 28,
            'col': [
              [255, 0, 0, 0],
              [0, 0, 255, 0],
            ],
          },
        ],
      });
      final col = ((result['seg'] as List).first as Map)['col'];
      expect(col, equals([
        [255, 0, 0, 0],
        [0, 0, 255, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('3-color col → unchanged (identity for the canonical case)', () {
      final input = {
        'on': true,
        'seg': [
          {
            'fx': 9,
            'col': [
              [255, 0, 0, 0],
              [255, 255, 255, 0],
              [0, 0, 255, 0],
            ],
          },
        ],
      };
      final result = normalizeWledPayload(input);
      final col = ((result['seg'] as List).first as Map)['col'];
      expect(col, equals([
        [255, 0, 0, 0],
        [255, 255, 255, 0],
        [0, 0, 255, 0],
      ]));
    });

    test(
        'setState-shaped seg (id present, no fx, 1-color col) → col padded '
        'to 3 slots. Closes the proof chain for the 2026-05-29 cold-start '
        'fix: WledService.setState now routes its {id, sx?, col:[1]} payload '
        'through applyJson, so normalize must pad col regardless of whether '
        'fx is present.', () {
      final result = normalizeWledPayload({
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 0,
            'sx': 128,
            'col': [
              [0, 0, 255, 0],
            ],
          },
        ],
      });
      final col = ((result['seg'] as List).first as Map)['col'];
      expect(col, equals([
        [0, 0, 255, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('oversized col (4+ slots) → unchanged (pad up only, no trim)', () {
      // WLED only consumes the first 3 slots, but the documented fix is
      // "pad up only" — preserves the caller's data shape and avoids
      // surprising any path that intentionally builds an oversized col
      // (e.g. for future WLED versions or for non-WLED replay).
      final input = {
        'on': true,
        'seg': [
          {
            'fx': 9,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
              [0, 0, 255, 0],
              [255, 255, 0, 0],
            ],
          },
        ],
      };
      final result = normalizeWledPayload(input);
      final col = ((result['seg'] as List).first as Map)['col'];
      expect(col, hasLength(4));
      expect(col, equals([
        [255, 0, 0, 0],
        [0, 255, 0, 0],
        [0, 0, 255, 0],
        [255, 255, 0, 0],
      ]));
    });
  });

  group(
      'normalizeWledPayload — col padding "leave alone" regression guards',
      () {
    test(
        'partial-update payload (no fx) with no col key → col is NOT '
        'synthesized. Slider tweaks like {sx: 200} must not get a col '
        'injected that would blank the lights.', () {
      final result = normalizeWledPayload({
        'seg': [
          {'sx': 200, 'ix': 128},
        ],
      });
      final seg = (result['seg'] as List).first as Map;
      expect(seg.containsKey('col'), isFalse);
    });

    test(
        'fx present but no col key → col is NOT synthesized. Applies '
        'that intentionally use the device\'s current colors stay clean.',
        () {
      final result = normalizeWledPayload({
        'seg': [
          {'fx': 5, 'sx': 128, 'ix': 200},
        ],
      });
      final seg = (result['seg'] as List).first as Map;
      expect(seg.containsKey('col'), isFalse);
      // Verify the existing fx-default injection still ran though.
      expect(seg['grp'], equals(1));
      expect(seg['spc'], equals(0));
      // `of` INVERTED: it used to be injected alongside grp/spc. It is
      // geometry (#76) and the chokepoint had no business asserting it.
      expect(seg.containsKey('of'), isFalse);
    });

    test('empty col [] → NOT padded (preserves "no color info" semantics)',
        () {
      final result = normalizeWledPayload({
        'seg': [
          {'fx': 0, 'col': const <List<int>>[]},
        ],
      });
      final seg = (result['seg'] as List).first as Map;
      expect(seg['col'], isEmpty);
    });

    test(
        '3-channel [r,g,b] col → validateRgbwList pads to [r,g,b,0] FIRST, '
        'then the slot pad uses the 4-channel black [0,0,0,0] to match.',
        () {
      final result = normalizeWledPayload({
        'seg': [
          {
            'fx': 0,
            'col': [
              [255, 100, 50],
            ],
          },
        ],
      });
      final col = ((result['seg'] as List).first as Map)['col'];
      expect(col, equals([
        [255, 100, 50, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });
  });

  group('normalizeWledPayload — multi-seg coverage (Sync / Game Day)', () {
    test(
        'two seg entries, each with 1-color col → each is padded '
        'independently. Covers participation-expanded payloads from '
        'Neighborhood Sync and per-channel Game Day applies.', () {
      final result = normalizeWledPayload({
        'on': true,
        'seg': [
          {
            'id': 0,
            'fx': 0,
            'col': [
              [255, 0, 0, 0],
            ],
          },
          {
            'id': 1,
            'fx': 0,
            'col': [
              [0, 255, 0, 0],
            ],
          },
        ],
      });
      final segs = (result['seg'] as List);
      expect((segs[0] as Map)['col'], equals([
        [255, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
      expect((segs[1] as Map)['col'], equals([
        [0, 255, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });
  });

  group('normalizeWledPayload — per-pixel i[] arrays untouched', () {
    test(
        'segment with a 1-color col AND a per-pixel i[] array → col is '
        'padded; i[] still flows through the existing per-pixel RGBW '
        'validation but is otherwise unchanged.', () {
      final result = normalizeWledPayload({
        'seg': [
          {
            'fx': 0,
            'col': [
              [255, 0, 0, 0],
            ],
            'i': [
              [10, 20, 30, 0],
              [40, 50, 60, 0],
            ],
          },
        ],
      });
      final seg = (result['seg'] as List).first as Map;
      // col padded to 3 slots
      expect(seg['col'], equals([
        [255, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
      // i[] preserved, both entries still 4-channel
      expect(seg['i'], equals([
        [10, 20, 30, 0],
        [40, 50, 60, 0],
      ]));
    });
  });

  // Palette guard — the pal:5 strobing/blending fix. A palette-driven effect
  // (generatesOwnColors / usesPalette) sent with pal:5 ("Colors Only") has its
  // sweep stripped → strobes/blends through the col[] slots. The chokepoint
  // flips ONLY that case to pal:4 ("Color Gradient") so the effect sweeps a
  // gradient of the USER's colors (pal:0 would use the effect's built-in
  // palette and ignore user colors). Everything else is untouched.
  group('normalizeWledPayload — palette guard (pal:5 fix)', () {
    Map seg0(Map<String, dynamic> p) =>
        (normalizeWledPayload(p)['seg'] as List).first as Map;

    test('Rainbow (fx 9, generatesOwnColors) pal:5 → pal:4', () {
      expect(seg0({'seg': [{'fx': 9, 'pal': 5, 'col': [[255, 0, 0, 0]]}]})['pal'],
          equals(4));
    });

    test('Colorwaves (fx 67, usesPalette) pal:5 → pal:4', () {
      expect(seg0({'seg': [{'fx': 67, 'pal': 5, 'col': [[255, 0, 0, 0]]}]})['pal'],
          equals(4));
    });

    test('Aurora (38) and Plasma (97) pal:5 → pal:4', () {
      expect(seg0({'seg': [{'fx': 38, 'pal': 5}]})['pal'], equals(4));
      expect(seg0({'seg': [{'fx': 97, 'pal': 5}]})['pal'], equals(4));
    });

    test('col-based effects keep pal:5 (Meteor/Chase/Wipe/Twinkle) — no regression', () {
      for (final fx in [76, 28, 3, 17]) {
        expect(seg0({'seg': [{'fx': fx, 'pal': 5, 'col': [[1, 2, 3, 0]]}]})['pal'],
            equals(5), reason: 'fx $fx should keep Colors Only');
      }
    });

    test('deliberate non-5 palette on a palette-driven effect is preserved', () {
      // Holiday card semantics — pal:3 (Colors 1&2) on Rainbow must NOT be
      // rewritten; only the pal:5 sentinel is corrected. pal:0 (built-in) is
      // also left as-is — the guard targets the pal:5 bug only.
      expect(seg0({'seg': [{'fx': 9, 'pal': 3}]})['pal'], equals(3));
      expect(seg0({'seg': [{'fx': 9, 'pal': 6}]})['pal'], equals(6));
      expect(seg0({'seg': [{'fx': 9, 'pal': 0}]})['pal'], equals(0));
    });

    test('absent pal is left absent (no synthesis)', () {
      final s = seg0({'seg': [{'fx': 9, 'col': [[255, 0, 0, 0]]}]});
      expect(s.containsKey('pal'), isFalse);
    });

    test('partial update (no fx) with pal:5 is untouched', () {
      // A slider tweak emitting {sx, pal} must not be reinterpreted.
      expect(seg0({'seg': [{'sx': 100, 'pal': 5}]})['pal'], equals(5));
    });
  });

  group('WledEffectsCatalog.paletteForEffect', () {
    test('palette-driven effects → 4 (Color Gradient of user colors)', () {
      for (final fx in [9, 67, 38, 97, 66, 80, 74]) {
        expect(WledEffectsCatalog.paletteForEffect(fx), equals(4),
            reason: 'fx $fx overrides user colors → gradient sweep');
      }
    });
    test('col-based effects → 5', () {
      for (final fx in [76, 28, 3, 17, 20, 49]) {
        expect(WledEffectsCatalog.paletteForEffect(fx), equals(5),
            reason: 'fx $fx uses selected colors');
      }
    });
    test('unknown effect id falls back to 5', () {
      expect(WledEffectsCatalog.paletteForEffect(9999), equals(5));
    });
  });
}
