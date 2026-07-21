// Unit tests for timersInsLanded — the readback comparator that decides whether
// a schedule cfg write actually landed on the controller (used by the retry +
// readback-verify hardening in ScheduleSyncService). Pure function, no I/O.

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

void main() {
  group('timersInsLanded', () {
    test('exact match (single enabled slot) → true', () {
      final sent = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      final back = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('en normalization: sent int 1 vs readback bool true → match', () {
      final sent = [_t(en: 1, hour: 7, min: 5, macro: 3, dow: 62)];
      final back = [_t(en: true, hour: 7, min: 5, macro: 3, dow: 62)];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('controller returns extra keys (start/end/mon/day) → still matches on '
        'the controlled fields', () {
      final sent = [_t(en: 1, hour: 22, min: 0, macro: 15, dow: 127)];
      final back = [
        _t(
          en: 1,
          hour: 22,
          min: 0,
          macro: 15,
          dow: 127,
          extra: {'start': {'mon': 1, 'day': 1}, 'end': {'mon': 12, 'day': 31}},
        )
      ];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('disabled slot: enabled bit matches, other fields ignored → true', () {
      // We sent a cleared stub (en:0); the controller still holds stale
      // hour/macro under en:0. A disabled slot compares on the enabled bit only.
      final sent = [_t(en: 0, hour: 0, min: 0, macro: 0, dow: 0)];
      final back = [_t(en: 0, hour: 13, min: 30, macro: 9, dow: 64)];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('mismatch on a controlled field (min) for an enabled slot → false', () {
      final sent = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      final back = [_t(en: 1, hour: 10, min: 41, macro: 12, dow: 127)];
      expect(timersInsLanded(sent, back), isFalse);
    });

    test('enabled bit differs (we sent enabled, device shows disabled) → false',
        () {
      final sent = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      final back = [_t(en: 0, hour: 10, min: 40, macro: 12, dow: 127)];
      expect(timersInsLanded(sent, back), isFalse);
    });

    test('readback shorter than sent → false (cannot confirm the slot)', () {
      final sent = [
        _t(en: 1, hour: 6, min: 0, macro: 12, dow: 127),
        _t(en: 1, hour: 22, min: 0, macro: 2, dow: 127),
      ];
      final back = [_t(en: 1, hour: 6, min: 0, macro: 12, dow: 127)];
      expect(timersInsLanded(sent, back), isFalse);
    });

    test('padded stubs after a real timer: real matches, stubs disabled → true',
        () {
      final sent = [
        _t(en: 1, hour: 10, min: 40, macro: 12, dow: 127),
        _t(en: 0),
        _t(en: 0),
      ];
      final back = [
        _t(en: 1, hour: 10, min: 40, macro: 12, dow: 127),
        _t(en: 0, hour: 5, min: 5, macro: 1, dow: 3), // stale under en:0 — ok
        _t(en: 0),
      ];
      expect(timersInsLanded(sent, back), isTrue);
    });

    test('controller has MORE slots than we sent → compares only what we sent',
        () {
      final sent = [_t(en: 1, hour: 10, min: 40, macro: 12, dow: 127)];
      final back = [
        _t(en: 1, hour: 10, min: 40, macro: 12, dow: 127),
        _t(en: 0),
        _t(en: 0),
      ];
      expect(timersInsLanded(sent, back), isTrue);
    });
  });
}
