// +126 (f) — the label-to-TimeOfDay helper the schedule editor re-opens on.
//
// A 24-hour account saves "17:30"; the editor's old AM/PM-only regex never
// matched it, so the wheel re-opened on the 7:00 PM default. The helper reads
// both forms through parseTimeLabel (the firing side's parser) and refuses
// solar words, which are not clock times.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/utils/time_format.dart';

void main() {
  group('timeOfDayFromLabel', () {
    test('24-hour "17:30" → 17:30', () {
      expect(timeOfDayFromLabel('17:30'),
          const TimeOfDay(hour: 17, minute: 30));
    });

    test('12-hour "5:30 PM" → 17:30', () {
      expect(timeOfDayFromLabel('5:30 PM'),
          const TimeOfDay(hour: 17, minute: 30));
    });

    test('"12:00 AM" is midnight, "12:00 PM" is noon', () {
      expect(timeOfDayFromLabel('12:00 AM'),
          const TimeOfDay(hour: 0, minute: 0));
      expect(timeOfDayFromLabel('12:00 PM'),
          const TimeOfDay(hour: 12, minute: 0));
    });

    test('24-hour midnight and the last minute of the day', () {
      expect(timeOfDayFromLabel('00:00'), const TimeOfDay(hour: 0, minute: 0));
      expect(timeOfDayFromLabel('0:05'), const TimeOfDay(hour: 0, minute: 5));
      expect(
          timeOfDayFromLabel('23:59'), const TimeOfDay(hour: 23, minute: 59));
    });

    test('whitespace and case are tolerated', () {
      expect(timeOfDayFromLabel('  7:05pm '),
          const TimeOfDay(hour: 19, minute: 5));
    });

    test('solar labels are NOT clock times', () {
      expect(timeOfDayFromLabel('Sunset'), isNull);
      expect(timeOfDayFromLabel('sunrise'), isNull);
    });

    test('null, empty and garbage return null (never a default)', () {
      expect(timeOfDayFromLabel(null), isNull);
      expect(timeOfDayFromLabel(''), isNull);
      expect(timeOfDayFromLabel('   '), isNull);
      expect(timeOfDayFromLabel('soon'), isNull);
      expect(timeOfDayFromLabel('25:00'), isNull);
      expect(timeOfDayFromLabel('13:00 PM'), isNull);
    });
  });
}
