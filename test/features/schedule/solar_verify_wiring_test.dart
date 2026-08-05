// test/features/schedule/solar_verify_wiring_test.dart
//
// SOLAR COMPARATOR WIRED INTO THE VERIFY PATH — audit/SOLAR_COMPARATOR.md.
//
// The payloads and readbacks below are LITERAL CAPTURES from 192.168.1.150
// (WLED 0.15.1, vid 2507300) on 2026-08-05, not hand-written fixtures. They pin
// the contrast that is the whole point of the wiring:
//
//   a corrupted solar row is INVISIBLE to timersInsLanded (returns true)
//   and CAUGHT by solarTimersLanded (returns false).
//
// Before this wiring, _pushCfgWithVerify called timersInsLanded alone — so a
// solar row verified clean whether it landed, landed wrong, or never landed.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/timer_landing.dart';

void main() {
  // ── SENT: what assembleSolarAwareIns emits — 10 entries, slot 8 sunrise
  //    (disabled here), slot 9 sunset (armed, macro 10, dow 31).
  List<Map<String, dynamic>> sent() => [
        {'en': 1, 'hour': 20, 'min': 0, 'macro': 1, 'dow': 127},
        for (var i = 0; i < 7; i++)
          {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0},
        {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0}, // slot 8 disabled
        {'en': 1, 'hour': 255, 'min': 0, 'macro': 10, 'dow': 31}, // slot 9
      ];

  // ── READBACK captured from the rig after sending exactly the above.
  //    Note the compaction: 10 sent → 2 returned, the 255-row trailing.
  List<Map<String, dynamic>> readbackGood() => [
        {
          'en': 1, 'hour': 20, 'min': 0, 'macro': 1, 'dow': 127,
          'start': {'mon': 1, 'day': 1}, 'end': {'mon': 12, 'day': 31},
        },
        {'en': 1, 'hour': 255, 'min': 0, 'macro': 10, 'dow': 31},
      ];

  // ── READBACK captured after the controller was given macro 99 instead of 10.
  //    The clock timer is untouched; ONLY the solar row differs.
  List<Map<String, dynamic>> readbackCorrupted() => [
        {
          'en': 1, 'hour': 20, 'min': 0, 'macro': 1, 'dow': 127,
          'start': {'mon': 1, 'day': 1}, 'end': {'mon': 12, 'day': 31},
        },
        {'en': 1, 'hour': 255, 'min': 0, 'macro': 99, 'dow': 31},
      ];

  group('hardware-captured contrast — the reason for the wiring', () {
    test('GOOD readback: both comparators pass', () {
      expect(timersInsLanded(sent(), readbackGood()), isTrue);
      expect(solarTimersLanded(sent(), readbackGood()), isTrue);
    });

    test('CORRUPTED solar row: timersInsLanded is BLIND, solar CATCHES it', () {
      expect(timersInsLanded(sent(), readbackCorrupted()), isTrue,
          reason: 'THE BUG: isRealEnabledTimer excludes hour == 255, so the '
              'general comparator cannot see the corrupted solar row at all — '
              'this is what shipped green before the wiring');

      expect(solarTimersLanded(sent(), readbackCorrupted()), isFalse,
          reason: 'THE FIX: the solar comparator catches it');
    });

    test('combined verdict flips from pass to fail', () {
      // _pushCfgWithVerify now returns `clockOk && solarOk`.
      bool verdict(List<Map<String, dynamic>> rb) =>
          timersInsLanded(sent(), rb) && solarTimersLanded(sent(), rb);

      expect(verdict(readbackGood()), isTrue);
      expect(verdict(readbackCorrupted()), isFalse);
    });

    test('the failure is SOLAR-ONLY, so it maps to solarMismatch', () {
      // The clock half still verifies — that distinction is what earns
      // CfgPushOutcome.solarMismatch its own state instead of folding into
      // mismatch, which would tell the user their whole schedule broke.
      final clockOk = timersInsLanded(sent(), readbackCorrupted());
      final solarOk = solarTimersLanded(sent(), readbackCorrupted());
      expect(clockOk && !solarOk, isTrue,
          reason: 'exactly the solarOnlyMismatch condition in the readback '
              'closure');
    });
  });

  group('the one-slot production shape does NOT false-alarm', () {
    test('sunset armed alone verifies against its single returned row', () {
      // Bench-confirmed: slot 8 disabled + slot 9 armed returns ONE 255-row.
      // An ordinal reading of the SENT side would call it sunrise and fail a
      // perfectly good write. This is the case the wiring must not break.
      expect(solarTimersLanded(sent(), readbackGood()), isTrue);
      expect(extractSentSolarRows(sent()).single.isSunrise, isFalse,
          reason: 'slot 9 is sunset even when slot 8 was dropped');
      expect(extractReadbackSolarEntries(readbackGood()).length, 1);
    });
  });
}
