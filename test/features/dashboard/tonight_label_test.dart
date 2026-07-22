// test/features/dashboard/tonight_label_test.dart
//
// COMMIT 2 (SCHEDULE CLARITY PAIR) — BUG-SCHED-UX-3.
//
// The dashboard upcoming-schedule header must follow the shown event's ON time:
// morning/afternoon → "TODAY", evening/night → "TONIGHT". The bug was an
// 11:40 AM event displayed under a hardcoded "TONIGHT".

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/dashboard/tonight_label.dart';

void main() {
  // now is only used for the no-schedule fallback; a fixed midday value keeps
  // the label-driven cases independent of wall-clock.
  final now = DateTime(2026, 7, 9, 12, 0);

  group('upcomingScheduleHeaderLabel — from the event ON time', () {
    test('morning clock event → TODAY', () {
      expect(upcomingScheduleHeaderLabel('11:40 AM', now), 'TODAY');
      expect(upcomingScheduleHeaderLabel('8:00 AM', now), 'TODAY');
    });

    test('evening clock event → TONIGHT', () {
      expect(upcomingScheduleHeaderLabel('7:00 PM', now), 'TONIGHT');
      expect(upcomingScheduleHeaderLabel('11:30 PM', now), 'TONIGHT');
    });

    test('solar Sunset → TONIGHT, Sunrise → TODAY', () {
      expect(upcomingScheduleHeaderLabel('Sunset', now), 'TONIGHT');
      expect(upcomingScheduleHeaderLabel('Sunrise', now), 'TODAY');
    });

    test('24-hour labels (CalendarEntry wire format)', () {
      expect(upcomingScheduleHeaderLabel('09:15', now), 'TODAY');
      expect(upcomingScheduleHeaderLabel('19:30', now), 'TONIGHT');
    });
  });

  group('threshold boundary (kEveningLabelThresholdHour = 17)', () {
    test('4:59 PM → TODAY, 5:00 PM → TONIGHT', () {
      expect(upcomingScheduleHeaderLabel('4:59 PM', now), 'TODAY');
      expect(upcomingScheduleHeaderLabel('5:00 PM', now), 'TONIGHT');
      // 24h equivalents
      expect(upcomingScheduleHeaderLabel('16:59', now), 'TODAY');
      expect(upcomingScheduleHeaderLabel('17:00', now), 'TONIGHT');
    });
  });

  group('no / unparseable label → falls back to current time of day', () {
    test('null at midday → TODAY', () {
      expect(upcomingScheduleHeaderLabel(null, DateTime(2026, 7, 9, 12)), 'TODAY');
    });
    test('null at night → TONIGHT', () {
      expect(upcomingScheduleHeaderLabel(null, DateTime(2026, 7, 9, 21)), 'TONIGHT');
    });
    test('garbage label at midday → TODAY (fallback)', () {
      expect(upcomingScheduleHeaderLabel('whenever', DateTime(2026, 7, 9, 12)), 'TODAY');
    });
  });
}
