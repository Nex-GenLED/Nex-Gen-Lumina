// Pure tests for fanOutPatternPayloadToBuses — the rule that turns the Explore
// tuner's single id-less segment into one segment per bus before a psave.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/pattern_preset_fanout.dart';

void main() {
  const tunerSeg = <String, dynamic>{
    'fx': 84,
    'sx': 0,
    'ix': 0,
    'pal': 5,
    'grp': 1,
    'spc': 0,
    'col': [
      [255, 140, 0, 0],
      [120, 0, 160, 0],
      [0, 90, 40, 0],
    ],
  };
  const tunerPayload = <String, dynamic>{
    'on': true,
    'bri': 255,
    'seg': [tunerSeg],
  };

  group('fans the tuner shape out over the bus set', () {
    test('two buses → two segments, ids 0 and 1, each carrying the design and on',
        () {
      final out = fanOutPatternPayloadToBuses(tunerPayload, const [0, 1]);
      expect(out['on'], isTrue);
      expect(out['bri'], 255);
      expect(out['seg'], [
        {'id': 0, ...tunerSeg, 'on': true},
        {'id': 1, ...tunerSeg, 'on': true},
      ]);
    });

    test('three buses → three segments', () {
      final out = fanOutPatternPayloadToBuses(tunerPayload, const [0, 1, 2]);
      expect((out['seg'] as List).map((s) => s['id']), [0, 1, 2]);
      for (final s in out['seg'] as List) {
        expect(s['fx'], 84);
        expect(s['on'], isTrue);
      }
    });

    test('ids are sorted and deduplicated', () {
      final out = fanOutPatternPayloadToBuses(tunerPayload, const [2, 0, 2, 1]);
      expect((out['seg'] as List).map((s) => s['id']), [0, 1, 2]);
    });

    test('bounds and a stated `on` are never copied from the template', () {
      final out = fanOutPatternPayloadToBuses({
        'on': true,
        'seg': [
          {...tunerSeg, 'start': 0, 'stop': 50, 'on': false}
        ],
      }, const [0, 1]);
      for (final s in out['seg'] as List) {
        expect(s.containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
        expect(s['on'], isTrue, reason: 'a fanned segment is always lit');
      }
    });

    test('the audio-reactive shape (fx only) fans too', () {
      final out = fanOutPatternPayloadToBuses({
        'on': true,
        'seg': [
          {'fx': 150, 'sx': 128, 'ix': 128}
        ],
      }, const [0, 1]);
      expect(out['seg'], [
        {'id': 0, 'fx': 150, 'sx': 128, 'ix': 128, 'on': true},
        {'id': 1, 'fx': 150, 'sx': 128, 'ix': 128, 'on': true},
      ]);
    });

    test('does not mutate its input', () {
      final input = {
        'on': true,
        'seg': [Map<String, dynamic>.from(tunerSeg)],
      };
      fanOutPatternPayloadToBuses(input, const [0, 1]);
      expect(input['seg'], [tunerSeg]);
    });
  });

  group('passes through unchanged — exactly today\'s behaviour', () {
    test('unknown facts (no bus ids)', () {
      expect(identical(fanOutPatternPayloadToBuses(tunerPayload, const []), tunerPayload), isTrue);
    });

    test('a single-bus controller', () {
      expect(identical(fanOutPatternPayloadToBuses(tunerPayload, const [0]), tunerPayload), isTrue);
    });

    test('a segment that already carries an id (targeted apply)', () {
      final p = {
        'on': true,
        'seg': [
          {'id': 0, ...tunerSeg}
        ],
      };
      expect(identical(fanOutPatternPayloadToBuses(p, const [0, 1]), p), isTrue);
    });

    test('a multi-segment body (My Design per-channel ids, scoped partition)', () {
      final p = {
        'on': true,
        'seg': [
          {'id': 0, 'on': false},
          {'id': 1, ...tunerSeg, 'on': true},
        ],
      };
      expect(identical(fanOutPatternPayloadToBuses(p, const [0, 1]), p), isTrue);
    });

    test('a per-pixel picture is never fanned', () {
      final p = {
        'on': true,
        'seg': [
          {
            'fx': 0,
            'i': [0, 5, [255, 0, 0, 0]]
          }
        ],
      };
      expect(identical(fanOutPatternPayloadToBuses(p, const [0, 1]), p), isTrue);
    });

    test('a top-level-only payload, and a slider tweak with no design', () {
      final top = {'on': true, 'bri': 90};
      expect(identical(fanOutPatternPayloadToBuses(top, const [0, 1]), top), isTrue);
      final tweak = {
        'seg': [
          {'sx': 200}
        ]
      };
      expect(identical(fanOutPatternPayloadToBuses(tweak, const [0, 1]), tweak), isTrue);
    });
  });
}
