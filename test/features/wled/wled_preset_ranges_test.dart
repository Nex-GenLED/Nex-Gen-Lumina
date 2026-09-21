import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';

void main() {
  group('Reserved range constants', () {
    test('start is 100', () {
      expect(kUserPatternPresetRangeStart, 100);
    });

    test('end is 200', () {
      expect(kUserPatternPresetRangeEnd, 200);
    });

    test('size is 101 (inclusive range)', () {
      expect(kUserPatternPresetRangeSize, 101);
    });

    test('range does not overlap system presets', () {
      expect(kUserPatternPresetRangeStart, greaterThan(2));
    });

    test('range does not overlap ScheduleItem range (10-25)', () {
      expect(kUserPatternPresetRangeStart, greaterThan(25));
    });

    test('range does not overlap CalendarEntry lease range (26-41)', () {
      expect(kUserPatternPresetRangeStart, greaterThan(41));
    });

    test('range stays within WLED preset cap (1-250)', () {
      expect(kUserPatternPresetRangeEnd, lessThanOrEqualTo(250));
    });
  });

  group('Cross-allocator coordination', () {
    test('no overlap with hardcoded ScheduleItem range constants from schedule_sync.dart', () {
      // Sanity assertion: confirm the ScheduleItem
      // range (10-25) doesn't intersect the user
      // pattern range. If a future change moves
      // either range, this test forces re-coordination.
      const scheduleItemStart = 10;
      const scheduleItemEnd = 25;
      expect(scheduleItemEnd, lessThan(kUserPatternPresetRangeStart));
      expect(scheduleItemStart, lessThan(kUserPatternPresetRangeStart));
    });

    test('no overlap with CalendarEntry lease range', () {
      const leaseStart = 26;
      const leaseEnd = 41;
      expect(leaseEnd, lessThan(kUserPatternPresetRangeStart));
      expect(leaseStart, lessThan(kUserPatternPresetRangeStart));
    });
  });
}
