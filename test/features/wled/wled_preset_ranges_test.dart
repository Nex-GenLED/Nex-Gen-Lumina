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

  group('presetIdForUserPattern', () {
    test('returns value in reserved range for known IDs', () {
      for (final id in [
        'pattern_a',
        'pattern_b',
        'sunset_glow',
        'warm_holiday',
        'christmas_red_green',
        'abc123',
        '',
        'a',
      ]) {
        final result = presetIdForUserPattern(id);
        expect(result, greaterThanOrEqualTo(kUserPatternPresetRangeStart));
        expect(result, lessThanOrEqualTo(kUserPatternPresetRangeEnd));
      }
    });

    test('is deterministic — same ID returns same preset ID', () {
      final first = presetIdForUserPattern('test_pattern');
      final second = presetIdForUserPattern('test_pattern');
      expect(first, equals(second));
    });

    test('different IDs generally return different preset IDs', () {
      final ids = List.generate(50, (i) => 'pattern_$i');
      final presets = ids.map(presetIdForUserPattern).toSet();
      // Not asserting all unique (collisions allowed),
      // just that we get a reasonable spread
      expect(presets.length, greaterThan(20));
    });

    test('handles empty string', () {
      final result = presetIdForUserPattern('');
      expect(result, greaterThanOrEqualTo(kUserPatternPresetRangeStart));
      expect(result, lessThanOrEqualTo(kUserPatternPresetRangeEnd));
    });

    test('handles very long IDs', () {
      final longId = 'a' * 1000;
      final result = presetIdForUserPattern(longId);
      expect(result, greaterThanOrEqualTo(kUserPatternPresetRangeStart));
      expect(result, lessThanOrEqualTo(kUserPatternPresetRangeEnd));
    });

    test('handles UUIDs', () {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      final result = presetIdForUserPattern(uuid);
      expect(result, greaterThanOrEqualTo(kUserPatternPresetRangeStart));
      expect(result, lessThanOrEqualTo(kUserPatternPresetRangeEnd));
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
