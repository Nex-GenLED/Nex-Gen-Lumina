// test/features/wled/wled_dow_test.dart
//
// Standalone coverage for the canonical WLED dow helper added in
// Item #72. The helper centralizes the Mon=bit 0..Sun=bit 6 convention
// that WLED firmware actually uses (verified empirically against
// firmware 0.14+ on 2026-05-19). Tests reference the kWledDow*
// constants symbolically — never hardcode integers — so any future
// convention drift fails loudly at the source of truth.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';

void main() {
  group('wledDowMaskForWeekday', () {
    test('Monday → kWledDowMonday (bit 0)', () {
      expect(wledDowMaskForWeekday(DateTime.monday), kWledDowMonday);
      expect(kWledDowMonday, 1);
    });

    test('Tuesday → kWledDowTuesday (bit 1)', () {
      expect(wledDowMaskForWeekday(DateTime.tuesday), kWledDowTuesday);
      expect(kWledDowTuesday, 2);
    });

    test('Wednesday → kWledDowWednesday (bit 2)', () {
      expect(wledDowMaskForWeekday(DateTime.wednesday), kWledDowWednesday);
      expect(kWledDowWednesday, 4);
    });

    test('Thursday → kWledDowThursday (bit 3)', () {
      expect(wledDowMaskForWeekday(DateTime.thursday), kWledDowThursday);
      expect(kWledDowThursday, 8);
    });

    test('Friday → kWledDowFriday (bit 4)', () {
      expect(wledDowMaskForWeekday(DateTime.friday), kWledDowFriday);
      expect(kWledDowFriday, 16);
    });

    test('Saturday → kWledDowSaturday (bit 5)', () {
      expect(wledDowMaskForWeekday(DateTime.saturday), kWledDowSaturday);
      expect(kWledDowSaturday, 32);
    });

    test('Sunday → kWledDowSunday (bit 6)', () {
      expect(wledDowMaskForWeekday(DateTime.sunday), kWledDowSunday);
      expect(kWledDowSunday, 64);
    });

    test('out-of-range weekday returns 0', () {
      expect(wledDowMaskForWeekday(0), 0);
      expect(wledDowMaskForWeekday(8), 0);
      expect(wledDowMaskForWeekday(-1), 0);
    });
  });

  group('wledDowMaskForDayName', () {
    test('full names map correctly', () {
      expect(wledDowMaskForDayName('Monday'), kWledDowMonday);
      expect(wledDowMaskForDayName('Tuesday'), kWledDowTuesday);
      expect(wledDowMaskForDayName('Wednesday'), kWledDowWednesday);
      expect(wledDowMaskForDayName('Thursday'), kWledDowThursday);
      expect(wledDowMaskForDayName('Friday'), kWledDowFriday);
      expect(wledDowMaskForDayName('Saturday'), kWledDowSaturday);
      expect(wledDowMaskForDayName('Sunday'), kWledDowSunday);
    });

    test('three-letter prefixes map correctly', () {
      expect(wledDowMaskForDayName('Mon'), kWledDowMonday);
      expect(wledDowMaskForDayName('Tue'), kWledDowTuesday);
      expect(wledDowMaskForDayName('Wed'), kWledDowWednesday);
      expect(wledDowMaskForDayName('Thu'), kWledDowThursday);
      expect(wledDowMaskForDayName('Fri'), kWledDowFriday);
      expect(wledDowMaskForDayName('Sat'), kWledDowSaturday);
      expect(wledDowMaskForDayName('Sun'), kWledDowSunday);
    });

    test('four-letter variants (Tues, Thurs)', () {
      expect(wledDowMaskForDayName('Tues'), kWledDowTuesday);
      expect(wledDowMaskForDayName('Thurs'), kWledDowThursday);
    });

    test('case-insensitive', () {
      expect(wledDowMaskForDayName('TUESDAY'), kWledDowTuesday);
      expect(wledDowMaskForDayName('tuesday'), kWledDowTuesday);
      expect(wledDowMaskForDayName('TuEsDay'), kWledDowTuesday);
    });

    test('whitespace tolerated', () {
      expect(wledDowMaskForDayName('  Monday  '), kWledDowMonday);
    });

    test('unrecognized input returns 0', () {
      expect(wledDowMaskForDayName('garbage'), 0);
      expect(wledDowMaskForDayName(''), 0);
      expect(wledDowMaskForDayName('daily'), 0,
          reason:
              'daily is a list-level concept; use kWledDowDaily directly');
    });
  });

  group('wledDowMaskForDayList', () {
    test('single day', () {
      expect(wledDowMaskForDayList(['Monday']), kWledDowMonday);
    });

    test('two distinct days are OR-d', () {
      // Mon + Fri = bit 0 | bit 4 = 1 + 16 = 17
      expect(
        wledDowMaskForDayList(['Monday', 'Friday']),
        kWledDowMonday | kWledDowFriday,
      );
      expect(kWledDowMonday | kWledDowFriday, 17);
    });

    test('Daily wins regardless of other entries', () {
      expect(wledDowMaskForDayList(['Daily']), kWledDowDaily);
      expect(wledDowMaskForDayList(['daily']), kWledDowDaily);
      expect(wledDowMaskForDayList(['Mon', 'Daily', 'Fri']), kWledDowDaily);
    });

    test('empty list returns 0', () {
      expect(wledDowMaskForDayList(<String>[]), 0);
    });

    test('all seven days summed equals kWledDowDaily', () {
      final all = wledDowMaskForDayList(
        ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
         'Saturday', 'Sunday'],
      );
      expect(all, kWledDowDaily);
      expect(all, 127);
    });

    test('unrecognized entries contribute 0', () {
      expect(wledDowMaskForDayList(['Monday', 'gibberish']),
          kWledDowMonday);
    });

    test('duplicates do not double-count', () {
      expect(wledDowMaskForDayList(['Mon', 'Monday', 'MON']),
          kWledDowMonday);
    });
  });

  group('regression — convention constants', () {
    // These pin the WLED firmware contract. If any of these fail,
    // either:
    //   (a) someone edited the constants without re-verifying against
    //       WLED firmware behavior — review and revert, OR
    //   (b) WLED firmware itself changed its dow convention, in which
    //       case Item #72's documentation needs an updated empirical
    //       readback citation.
    test('Mon=bit 0..Sun=bit 6 convention is unchanged', () {
      expect(kWledDowMonday, 1);
      expect(kWledDowTuesday, 2);
      expect(kWledDowWednesday, 4);
      expect(kWledDowThursday, 8);
      expect(kWledDowFriday, 16);
      expect(kWledDowSaturday, 32);
      expect(kWledDowSunday, 64);
      expect(kWledDowDaily, 127);
    });
  });
}
