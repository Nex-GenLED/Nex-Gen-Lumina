// Roofline slice 2 — `presetSatisfies` is `i`-aware: an API-command preset
// body is judged by a hash of the whole stored payload, not field by field.
//
// FAIL-BEFORE (defect-style). On the unchanged code a stored design preset
// that is EXACTLY what the builder would write is reported UNSATISFIED: the
// field-by-field compare uses `!=`, and two `i` lists are never equal by
// identity (audit §B.2 "an `i` List is never equal, so every sync re-saves";
// after three attempts the fourth sync in a process refuses). Every sync
// would re-save the design — a flash commit and a visible repaint on every
// connect — and the non-convergence guard would then refuse it for good.
//
// After: the stored copy and the body to write are canonicalised (keys
// sorted, the keys WLED strips on save and the ones the save adds set aside)
// and compared by SHA-256. Equal → satisfied, no write. Any difference in the
// picture, the bounds, the name or the root → unsatisfied → one write.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

/// What the sync sends: the builder's body plus the name the save adds.
Map<String, dynamic> toWrite({String name = 'Pattern: Porch stripes'}) => {
      'o': true,
      'on': true,
      'bri': 200,
      'n': name,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': 100,
          'on': true,
          'fx': 0,
          'grp': 1,
          'spc': 0,
          'pal': 0,
          'col': [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
          ],
          'i': [0, 50, [255, 0, 0, 0], 50, 100, [0, 0, 255, 0]],
        },
        {'id': 1, 'start': 100, 'stop': 200, 'on': false},
      ],
    };

/// What presets.json holds after WLED saved it: the request with `o`, `v`,
/// `time`, `error` and `psave` removed, keys in the firmware's own order.
Map<String, dynamic> stored({String name = 'Pattern: Porch stripes'}) {
  final w = toWrite(name: name)..remove('o');
  return {
    'n': w['n'],
    'seg': [
      for (final s in (w['seg'] as List))
        {for (final k in (s as Map).keys.toList().reversed) k: s[k]},
    ],
    'bri': w['bri'],
    'on': w['on'],
  };
}

void main() {
  group('presetPayloadHash', () {
    test('is stable across key order and ignores what WLED strips or adds', () {
      final a = presetPayloadHash(toWrite());
      final b = presetPayloadHash(stored());
      expect(a, b);
      expect(
          presetPayloadHash({
            ...toWrite(),
            'psave': 12,
            'v': true,
            'time': 1700000000,
            'error': 0,
          }),
          a);
      expect(a.length, 64, reason: 'sha-256 hex');
    });

    test('changes with the picture, the bounds, the name and the root', () {
      final base = presetPayloadHash(toWrite());
      final pixel = toWrite();
      (pixel['seg'][0]['i'] as List)[2] = [254, 0, 0, 0];
      expect(presetPayloadHash(pixel), isNot(base));

      final bounds = toWrite();
      bounds['seg'][1]['stop'] = 220;
      expect(presetPayloadHash(bounds), isNot(base));

      expect(presetPayloadHash(toWrite(name: 'Other')), isNot(base));
      expect(presetPayloadHash(toWrite()..['bri'] = 100), isNot(base));
    });
  });

  group('presetSatisfies on an API body', () {
    test('a stored copy equal to the body to write is SATISFIED', () {
      expect(
        ScheduleSyncService.presetSatisfies(stored(), toWrite(),
            expectedName: 'Pattern: Porch stripes'),
        isTrue,
        reason: 'on the unchanged code the i lists never compare equal, so '
            'every sync re-saved the design',
      );
    });

    test('a different picture, bound, or name is UNSATISFIED', () {
      final pixel = stored();
      (pixel['seg'][0]['i'] as List)[2] = [254, 0, 0, 0];
      expect(ScheduleSyncService.presetSatisfies(pixel, toWrite()), isFalse);

      final bounds = stored();
      bounds['seg'][1]['stop'] = 220;
      expect(ScheduleSyncService.presetSatisfies(bounds, toWrite()), isFalse);

      expect(
          ScheduleSyncService.presetSatisfies(stored(name: 'Old'), toWrite()),
          isFalse);
    });

    test('an ordinary (captured-state) preset in the slot is UNSATISFIED', () {
      final ladder = {
        'n': 'Pattern: Porch stripes',
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'on': true, 'fx': 0},
          {'id': 1, 'on': true, 'fx': 0},
        ],
      };
      expect(ScheduleSyncService.presetSatisfies(ladder, toWrite()), isFalse);
    });

    test('a non-API expectation is judged exactly as before', () {
      // The all-channel ladder rule: a stored preset with root on and the
      // named segments on is satisfied; one missing root on is not.
      final expected = {
        'n': 'NGL On',
        'on': true,
        'bri': 200,
        'ib': true,
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'on': true},
        ],
      };
      final healthy = {
        'n': 'NGL On',
        'on': true,
        'bri': 150,
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'on': true},
        ],
      };
      expect(
          ScheduleSyncService.presetSatisfies(healthy, expected,
              expectedName: 'NGL On'),
          isTrue);
      expect(
          ScheduleSyncService.presetSatisfies(
              {...healthy}..remove('on'), expected,
              expectedName: 'NGL On'),
          isFalse);
    });
  });
}
