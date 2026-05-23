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
      expect(seg['of'], equals(0));
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
}
