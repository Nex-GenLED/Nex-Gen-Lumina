// test/features/schedule/solar_comparator_test.dart
//
// SOLAR READBACK COMPARATOR — audit/SOLAR_COMPARATOR.md, part 2.
//
// HARD BLOCKER ON THE SOLAR FLAG. isRealEnabledTimer excludes hour == 255, so
// every solar row is dropped from BOTH sides of timersInsLanded: flip the flag
// without this and a solar row verifies clean whether it landed correctly,
// landed wrong, or never landed at all. Structurally the same blindness as P0-8.
//
// The NEGATIVE cases are the point of this suite. A comparator that only
// returns true proves nothing — each corruption below (wrong macro, wrong dow,
// wrong offset, sunrise/sunset swapped, slot missing) must be CAUGHT.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/timer_landing.dart';

void main() {
  Map<String, dynamic> stub() =>
      {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0};

  Map<String, dynamic> clock({int hour = 20, int macro = 1, int dow = 127}) =>
      {'en': 1, 'hour': hour, 'min': 0, 'macro': macro, 'dow': dow};

  /// A solar sentinel row. `min` is the SIGNED offset, not a wall-clock minute.
  Map<String, dynamic> solar({
    int en = 1,
    int offset = 0,
    int macro = 2,
    int dow = 127,
  }) =>
      {'en': en, 'hour': 255, 'min': offset, 'macro': macro, 'dow': dow};

  /// What syncAll pushes: slots 0-7 general, 8 = sunrise, 9 = sunset.
  List<Map<String, dynamic>> sent({
    Map<String, dynamic>? sunrise,
    Map<String, dynamic>? sunset,
    List<Map<String, dynamic>> general = const [],
  }) {
    final out = <Map<String, dynamic>>[...general];
    while (out.length < 8) {
      out.add(stub());
    }
    out.add(sunrise ?? stub());
    out.add(sunset ?? stub());
    return out;
  }

  /// What WLED echoes: real entries, then the 255-markers TRAILING, stubs
  /// dropped. This compaction is why ordinal pairing is required.
  List<Map<String, dynamic>> readback({
    List<Map<String, dynamic>> general = const [],
    Map<String, dynamic>? sunrise,
    Map<String, dynamic>? sunset,
  }) =>
      [
        ...general,
        if (sunrise != null) sunrise,
        if (sunset != null) sunset,
      ];

  group('extraction — SENT is positional, READBACK is ordinal', () {
    test('readback: first 255 is sunrise, second is sunset, even compacted', () {
      final e = extractReadbackSolarEntries(readback(
        general: [clock(), clock(hour: 23, macro: 2)],
        sunrise: solar(macro: 2, dow: 127),
        sunset: solar(macro: 10, dow: 31),
      ));
      expect(e.length, 2);
      expect(e[0]['macro'], 2, reason: 'first 255 = sunrise');
      expect(e[1]['macro'], 10, reason: 'second 255 = sunset');
    });

    test('sent: read by SLOT INDEX 8/9, not by order', () {
      final rows = extractSentSolarRows(
          sent(sunrise: solar(macro: 2), sunset: solar(macro: 10)));
      expect(rows.map((r) => r.isSunrise), [true, false]);
      expect(rows.map((r) => r.macro), [2, 10]);
    });

    test('sent: a DISABLED slot 8 is omitted, and slot 9 stays SUNSET', () {
      // The correctness fix. Reading this ordinally would label the surviving
      // row "sunrise" and then fail to match its own readback.
      final rows = extractSentSolarRows(
          sent(sunrise: solar(en: 0), sunset: solar(macro: 10)));
      expect(rows.length, 1);
      expect(rows.single.isSunrise, isFalse,
          reason: 'slot 9 is sunset regardless of whether slot 8 survived');
      expect(rows.single.macro, 10);
    });

    test('sent: an 8-slot push (no solar assembly) yields nothing', () {
      final short = [clock(), ...List.generate(7, (_) => stub())];
      expect(extractSentSolarRows(short), isEmpty);
    });

    test('general timers are never mistaken for solar rows', () {
      expect(
          extractReadbackSolarEntries(
              readback(general: [clock(), clock(hour: 6), clock(hour: 23)])),
          isEmpty);
    });
  });

  group('normalizeSolarOffset — SIGNED, not an unsigned byte', () {
    test('positive offsets pass through', () {
      expect(normalizeSolarOffset(0), 0);
      expect(normalizeSolarOffset(30), 30);
      expect(normalizeSolarOffset(120), 120);
    });

    test('an unsigned-byte round trip folds back to negative', () {
      // If firmware stores -30 in a uint8 it reads back as 226.
      expect(normalizeSolarOffset(226), -30);
      expect(normalizeSolarOffset(136), -120);
      expect(normalizeSolarOffset(255), -1);
    });

    test('the 127/128 boundary', () {
      expect(normalizeSolarOffset(127), 127);
      expect(normalizeSolarOffset(128), -128);
    });
  });

  group('solarTimersLanded — POSITIVE', () {
    test('both slots land, compacted readback', () {
      final s = sent(
        general: [clock()],
        sunrise: solar(macro: 2, dow: 127),
        sunset: solar(macro: 10, dow: 31),
      );
      final r = readback(
        general: [clock()],
        sunrise: solar(macro: 2, dow: 127),
        sunset: solar(macro: 10, dow: 31),
      );
      expect(solarTimersLanded(s, r), isTrue);
    });

    test('sunrise only', () {
      final s = sent(sunrise: solar(macro: 2, dow: 127));
      final r = readback(sunrise: solar(macro: 2, dow: 127));
      expect(solarTimersLanded(s, r), isTrue);
    });

    test('no solar claimed → vacuously true', () {
      expect(solarTimersLanded(sent(), readback()), isTrue);
      expect(solarTimersLanded(sent(general: [clock()]), readback(general: [clock()])), isTrue);
    });

    test('SUNSET ONLY (sunrise disabled) — the common production shape', () {
      // "on at sunset, off at a clock time". WLED drops the disabled slot 8, so
      // the readback carries a SINGLE 255-row (bench-confirmed 2026-08-05).
      // Reading that ordinally would call it sunrise and fail a good write —
      // count-driven pairing resolves it.
      final s = sent(sunrise: solar(en: 0), sunset: solar(macro: 10, dow: 31));
      final r = readback(sunset: solar(macro: 10, dow: 31));
      expect(solarTimersLanded(s, r), isTrue,
          reason: 'exactly one armed slot, exactly one returned row — '
              'unambiguous by count');
    });

    test('SUNRISE ONLY also matches its single returned row', () {
      final s = sent(sunrise: solar(macro: 2, dow: 127));
      final r = readback(sunrise: solar(macro: 2, dow: 127));
      expect(solarTimersLanded(s, r), isTrue);
    });

    test('offset round-tripped through an unsigned byte still matches', () {
      final s = sent(sunrise: solar(offset: -30, macro: 2));
      final r = readback(sunrise: solar(offset: 226, macro: 2)); // uint8 form
      expect(solarTimersLanded(s, r), isTrue,
          reason: 'normalizeSolarOffset must fold 226 back to -30');
    });
  });

  group('solarTimersLanded — NEGATIVE (the point of the suite)', () {
    final good = sent(
      general: [clock()],
      sunrise: solar(macro: 2, dow: 127),
      sunset: solar(macro: 10, dow: 31),
    );

    test('CATCHES a wrong macro', () {
      final r = readback(
        general: [clock()],
        sunrise: solar(macro: 99, dow: 127), // corrupted
        sunset: solar(macro: 10, dow: 31),
      );
      expect(solarTimersLanded(good, r), isFalse);
    });

    test('CATCHES a wrong dow', () {
      final r = readback(
        general: [clock()],
        sunrise: solar(macro: 2, dow: 1), // corrupted
        sunset: solar(macro: 10, dow: 31),
      );
      expect(solarTimersLanded(good, r), isFalse);
    });

    test('CATCHES a wrong offset', () {
      final s = sent(sunrise: solar(offset: 15, macro: 2));
      final r = readback(sunrise: solar(offset: 16, macro: 2));
      expect(solarTimersLanded(s, r), isFalse);
    });

    test('CATCHES a sign error on the offset', () {
      // +30 sent, -30 read back. If the comparator treated min as unsigned it
      // would see 30 vs 226 and might mask this; signed comparison catches it.
      final s = sent(sunrise: solar(offset: 30, macro: 2));
      final r = readback(sunrise: solar(offset: 226, macro: 2));
      expect(solarTimersLanded(s, r), isFalse);
    });

    test('CATCHES sunrise/sunset SWAPPED', () {
      final r = readback(
        general: [clock()],
        sunrise: solar(macro: 10, dow: 31), // sunset's content, first position
        sunset: solar(macro: 2, dow: 127),
      );
      expect(solarTimersLanded(good, r), isFalse);
    });

    test('CATCHES a slot that never landed', () {
      final r = readback(general: [clock()], sunrise: solar(macro: 2, dow: 127));
      expect(solarTimersLanded(good, r), isFalse,
          reason: 'sunset was sent enabled and is absent');
    });

    test('CATCHES an entirely empty readback', () {
      expect(solarTimersLanded(good, const []), isFalse);
    });

    test('CATCHES en downgraded to 0 by the firmware', () {
      // The en-must-be-INT class: a JSON bool stores as 0. If that happened to a
      // solar row the strip would never fire and the general comparator would
      // never notice.
      final s = sent(sunrise: solar(en: 1, macro: 2));
      final r = readback(sunrise: solar(en: 0, macro: 2));
      expect(solarTimersLanded(s, r), isFalse);
    });
  });

  group('the blind spot this closes', () {
    test('timersInsLanded passes a totally corrupted solar row', () {
      final s = sent(general: [clock()], sunrise: solar(macro: 2, dow: 127));
      final corrupted =
          readback(general: [clock()], sunrise: solar(macro: 99, dow: 3));

      expect(timersInsLanded(s, corrupted), isTrue,
          reason: 'documents the blindness: the general comparator cannot see '
              'solar rows at all');
      expect(solarTimersLanded(s, corrupted), isFalse,
          reason: 'the solar comparator catches what it misses');
    });
  });
}
