// Unit tests for timersInsLanded — the CONTENT-match readback comparator that
// decides whether a schedule cfg write landed on the controller.
//
// Bench-proven readback shape (WLED vid 2507300, SKIKBILY): the controller
// echoes enabled real entries + 2 solar sentinels (hour:255) and DROPS disabled
// padding stubs, so the array COMPACTS and reorders — sent-index ≠ readback-index.
// The comparator matches by content anywhere in the array, not per index.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

Map<String, dynamic> _t({
  required Object en,
  int hour = 0,
  int min = 0,
  int macro = 0,
  int dow = 0,
  Map<String, dynamic> extra = const {},
}) =>
    {'en': en, 'hour': hour, 'min': min, 'macro': macro, 'dow': dow, ...extra};

// A disabled padding stub as buildCfgPayload emits it.
Map<String, dynamic> _stub() => _t(en: 0);

// The two solar sentinel entries the controller always echoes (hour:255).
List<Map<String, dynamic>> _solarSentinels() =>
    [_t(en: 1, hour: 255, macro: 0), _t(en: 1, hour: 255, macro: 0)];

void main() {
  group('timersInsLanded — content match', () {
    test('exact match, single enabled real timer → true', () {
      final sent = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      final back = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('en normalization: sent int 1 vs readback bool true → match', () {
      final sent = [_t(en: 1, hour: 7, min: 5, macro: 3, dow: 62)];
      final back = [_t(en: true, hour: 7, min: 5, macro: 3, dow: 62)];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('controller returns extra keys (start/end/mon/day) → still matches', () {
      final sent = [_t(en: 1, hour: 22, min: 0, macro: 15, dow: 127)];
      final back = [
        _t(en: 1, hour: 22, min: 0, macro: 15, dow: 127, extra: {
          'start': {'mon': 1, 'day': 1},
          'end': {'mon': 12, 'day': 31},
        })
      ];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('COMPACTED readback: sent 8 (1 real + 7 stubs), device echoes 3 '
        '(the real + 2 solar sentinels, stubs dropped) → true', () {
      final sent = [
        _t(en: 1, hour: 10, min: 40, macro: 12, dow: 127),
        _stub(), _stub(), _stub(), _stub(), _stub(), _stub(), _stub(),
      ];
      final back = [
        _t(en: 1, hour: 10, min: 40, macro: 12, dow: 127),
        ..._solarSentinels(),
      ];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('solar sentinels present in readback are ignored → true', () {
      final sent = [_t(en: 1, hour: 6, min: 30, macro: 11, dow: 127), _stub()];
      final back = [..._solarSentinels(), _t(en: 1, hour: 6, min: 30, macro: 11, dow: 127)];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('order shuffled: two real timers echoed in reverse order → true', () {
      final a = _t(en: 1, hour: 6, min: 0, macro: 12, dow: 127);
      final b = _t(en: 1, hour: 22, min: 0, macro: 2, dow: 127);
      final sent = [a, b, _stub(), _stub()];
      final back = [b, ..._solarSentinels(), a];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('real timer echoed at a DIFFERENT index → true (index-independent)', () {
      final real = _t(en: 1, hour: 19, min: 15, macro: 14, dow: 96);
      final sent = [real, _stub(), _stub()];
      final back = [_stub(), _stub(), _stub(), _stub(), _stub(), real]; // index 5
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('ON + OFF pair (OFF macro:2) both present → true', () {
      final on = _t(en: 1, hour: 18, min: 0, macro: 12, dow: 127);
      final off = _t(en: 1, hour: 23, min: 0, macro: 2, dow: 127);
      final sent = [on, off, _stub()];
      final back = [off, on, ..._solarSentinels()];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('mismatch on a controlled field (min) → false', () {
      final sent = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      final back = [_t(en: 1, hour: 10, min: 41, macro: 12, dow: 127)];
      expect(timersInsLanded(sent, back), isFalse);
    });

    test('a sent real timer is missing from the readback entirely → false', () {
      final sent = [
        _t(en: 1, hour: 6, min: 0, macro: 12, dow: 127),
        _t(en: 1, hour: 22, min: 0, macro: 2, dow: 127),
      ];
      final back = [
        _t(en: 1, hour: 6, min: 0, macro: 12, dow: 127), // only the ON echoed
        ..._solarSentinels(),
      ];
      expect(timersInsLanded(sent, back), isFalse);
    });

    test('our real timer reads back DISABLED (en:0) → false', () {
      final sent = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      final back = [_t(en: 0, hour: 10, min: 40, macro: 12, dow: 127)];
      expect(timersInsLanded(sent, back), isFalse);
    });

    group('cleared schedule (no real entries sent)', () {
      test('readback has only solar sentinels → true (device cleared)', () {
        final sent = [_stub(), _stub(), _stub()];
        expect(timersInsLanded(sent, _solarSentinels()), isTrue);
      });

      test('readback empty → true', () {
        expect(timersInsLanded([_stub(), _stub()], const []), isTrue);
      });

      test('readback still holds an enabled non-solar timer → false '
          '(clear did not land)', () {
        final sent = [_stub(), _stub()];
        final back = [
          _t(en: 1, hour: 8, min: 0, macro: 12, dow: 127),
          ..._solarSentinels(),
        ];
        expect(timersInsLanded(sent, back), isFalse);
      });
    });
  });
}
