import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/compound_command_detector.dart';

void main() {
  // Fixed reference date for deterministic tests: Wednesday, April 2, 2026.
  final now = DateTime(2026, 4, 2);

  // -----------------------------------------------------------------
  // resolveDate helper
  // -----------------------------------------------------------------
  group('resolveDate', () {
    test('resolves "today" to current date', () {
      final d = CompoundCommandDetector.resolveDate('today', now: now);
      expect(d, DateTime(2026, 4, 2));
    });

    test('resolves "tomorrow" to next day', () {
      final d = CompoundCommandDetector.resolveDate('tomorrow', now: now);
      expect(d, DateTime(2026, 4, 3));
    });

    test('resolves a day name to the next occurrence', () {
      // April 2 2026 is a Thursday (weekday 4).
      // "friday" (weekday 5) is 1 day ahead → April 3.
      final d = CompoundCommandDetector.resolveDate('friday', now: now);
      expect(d, DateTime(2026, 4, 3));
    });

    test('resolves same-day day name to today', () {
      // April 2 2026 is a Thursday
      final d = CompoundCommandDetector.resolveDate('thursday', now: now);
      expect(d, DateTime(2026, 4, 2));
    });

    test('resolves a day name to next week when day has passed', () {
      // April 2 is Thursday (weekday 4) → "monday" (weekday 1) is past,
      // so it resolves to next Monday: April 6.
      final d = CompoundCommandDetector.resolveDate('monday', now: now);
      expect(d, DateTime(2026, 4, 6));
    });

    test('resolves month + day in the future', () {
      final d = CompoundCommandDetector.resolveDate('July 4th', now: now);
      expect(d, DateTime(2026, 7, 4));
    });

    test('resolves month + day in the past to next year', () {
      // January 1 is before April 2 → rolls to 2027
      final d = CompoundCommandDetector.resolveDate('January 1', now: now);
      expect(d, DateTime(2027, 1, 1));
    });

    test('resolves abbreviated month names', () {
      final d = CompoundCommandDetector.resolveDate('Dec 25', now: now);
      expect(d, DateTime(2026, 12, 25));
    });

    test('respects onOrAfter for end-date chaining', () {
      final start = DateTime(2026, 4, 6); // Monday
      final d = CompoundCommandDetector.resolveDate(
        'friday',
        onOrAfter: start,
        now: now,
      );
      expect(d, DateTime(2026, 4, 10)); // Friday after that Monday
    });

    test('returns null for unrecognised text', () {
      final d = CompoundCommandDetector.resolveDate('purple', now: now);
      expect(d, isNull);
    });
  });

  // -----------------------------------------------------------------
  // "starting X through Y" detection
  // -----------------------------------------------------------------
  group('detect – starting X through Y', () {
    test('day-name range: starting Friday through Sunday', () {
      final r = CompoundCommandDetector.detect(
        'Blue lights starting Friday through Sunday from sunset to sunrise',
      );

      expect(r.isCompound, isTrue);
      expect(r.lightingIntent.toLowerCase(), contains('blue lights'));

      final t = r.temporal!;
      expect(t.hasDateRange, isTrue);
      expect(t.startDate, isNotNull);
      expect(t.endDate, isNotNull);
      expect(t.endDate!.isAfter(t.startDate!) || t.endDate == t.startDate,
          isTrue);
      // Friday → Sunday = 3 days
      expect(t.dayCount, 3);
      expect(t.recurrence, RecurrenceType.daily);
      // Time triggers should still be parsed
      expect(t.startTrigger, TimeTrigger.sunset);
      expect(t.endTrigger, TimeTrigger.sunrise);
    });

    test('month-day range: starting April 5th through April 12th', () {
      final r = CompoundCommandDetector.detect(
        'Christmas theme starting April 5th through April 12th',
      );

      expect(r.isCompound, isTrue);
      final t = r.temporal!;
      expect(t.hasDateRange, isTrue);
      expect(t.dayCount, 8); // 5th through 12th inclusive
    });

    test('single-day range collapses to once', () {
      final r = CompoundCommandDetector.detect(
        'Warm white starting Friday through Friday',
      );

      expect(r.isCompound, isTrue);
      final t = r.temporal!;
      expect(t.hasDateRange, isTrue);
      expect(t.dayCount, 1);
      expect(t.recurrence, RecurrenceType.once);
    });

    test('date range is stripped from lighting intent', () {
      final r = CompoundCommandDetector.detect(
        'Give me a party theme starting Monday through Wednesday',
      );

      expect(r.isCompound, isTrue);
      final intent = r.lightingIntent.toLowerCase();
      expect(intent, isNot(contains('starting')));
      expect(intent, isNot(contains('through')));
      expect(intent, isNot(contains('monday')));
      expect(intent, isNot(contains('wednesday')));
      expect(intent, contains('party theme'));
    });

    test('dateRangeLabel produces a human-readable string', () {
      final r = CompoundCommandDetector.detect(
        'Royals colors starting Friday through Sunday',
      );
      final t = r.temporal!;
      expect(t.dateRangeLabel, isNotEmpty);
      expect(t.dateRangeLabel, contains('through'));
    });

    test('no false positive on unrelated input', () {
      final r = CompoundCommandDetector.detect(
        'Give me a blue and gold design',
      );
      expect(r.isCompound, isFalse);
      expect(r.temporal, isNull);
    });
  });

  // -----------------------------------------------------------------
  // Existing patterns still work (regression guard)
  // -----------------------------------------------------------------
  group('detect – existing patterns (regression)', () {
    test('tonight still detected', () {
      final r = CompoundCommandDetector.detect('Patriots colors tonight');
      expect(r.isCompound, isTrue);
      expect(r.temporal!.recurrence, RecurrenceType.once);
      expect(r.temporal!.dayCount, 1);
      expect(r.temporal!.hasDateRange, isFalse);
    });

    test('every night this week still detected', () {
      final r = CompoundCommandDetector.detect(
        'Blue and gold every night this week from sunset to sunrise',
      );
      expect(r.isCompound, isTrue);
      expect(r.temporal!.recurrence, RecurrenceType.daily);
      expect(r.temporal!.dayCount, 7);
      expect(r.temporal!.startTrigger, TimeTrigger.sunset);
      expect(r.temporal!.endTrigger, TimeTrigger.sunrise);
      expect(r.temporal!.hasDateRange, isFalse);
    });

    test('clock time range still detected', () {
      final r = CompoundCommandDetector.detect(
        'Red theme from 7pm to 10pm',
      );
      expect(r.isCompound, isTrue);
      expect(r.temporal!.startHour, 19);
      expect(r.temporal!.endHour, 22);
    });
  });
}
