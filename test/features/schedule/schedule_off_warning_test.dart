// test/features/schedule/schedule_off_warning_test.dart
//
// COMMIT 1 (SCHEDULE CLARITY PAIR) — manual-apply OFF-boundary awareness.
//
// Ground truth: autopilot's daily "Warm White (Daily evening lighting)"
// schedule turns the lights OFF at Sunrise. A user applying a pattern at night
// gets no signal it will be killed hours later. nextEnabledOffBoundaryWithin()
// decides — purely and deterministically — whether an ENABLED schedule has an
// OFF boundary near enough to warn about, and how to render it.
//
// These assert: fires only for an enabled off-boundary schedule inside the
// window; silent when none / disabled / off-boundary absent / out-of-window;
// and solar off boundaries render as the WORD, not a resolved clock time.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';

void main() {
  ScheduleItem sched({
    String id = 's1',
    String on = 'Sunset',
    String? off = 'Sunrise',
    List<String> days = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    String action = 'Warm White (Daily evening lighting)',
    bool enabled = true,
  }) =>
      ScheduleItem(
        id: id,
        timeLabel: on,
        offTimeLabel: off,
        repeatDays: days,
        actionLabel: action,
        enabled: enabled,
      );

  // A fixed night reference so the daily Sunrise OFF (~06:00 next day) lands
  // ~8h out — comfortably inside the 18h window.
  final night = DateTime(2026, 7, 9, 22, 0); // Thu 10 PM
  final morning = DateTime(2026, 7, 9, 8, 0); // Thu 8 AM

  group('nextEnabledOffBoundaryWithin — fires only when it should', () {
    test('daily Sunset→Sunrise, applied at night → notice with solar word', () {
      final n = nextEnabledOffBoundaryWithin([sched()], night);
      expect(n, isNotNull);
      expect(n!.scheduleName, 'Warm White'); // reason stripped
      expect(n.offLabel, 'Sunrise'); // rendered as the WORD, not a clock time
    });

    test('applied in the morning → next Sunrise is ~22h out → no notice', () {
      // today's ~06:00 sunrise already passed at 08:00, next is tomorrow.
      expect(nextEnabledOffBoundaryWithin([sched()], morning), isNull);
    });

    test('disabled schedule → no notice', () {
      expect(
        nextEnabledOffBoundaryWithin([sched(enabled: false)], night),
        isNull,
      );
    });

    test('schedule with no off boundary → no notice', () {
      expect(nextEnabledOffBoundaryWithin([sched(off: null)], night), isNull);
      expect(nextEnabledOffBoundaryWithin([sched(off: '')], night), isNull);
    });

    test('empty schedule list → no notice', () {
      expect(nextEnabledOffBoundaryWithin(const [], night), isNull);
    });

    test('clock off boundary within window → notice with formatted time', () {
      final n = nextEnabledOffBoundaryWithin(
        [sched(on: '7:00 PM', off: '11:00 PM')],
        DateTime(2026, 7, 9, 20, 0), // 8 PM, off at 11 PM → 3h
      );
      expect(n, isNotNull);
      expect(n!.offLabel, '11:00 PM');
    });

    test('Pattern:-prefixed action → clean display name', () {
      final n = nextEnabledOffBoundaryWithin(
        [sched(action: 'Pattern: Candy Cane')],
        night,
      );
      expect(n!.scheduleName, 'Candy Cane');
    });

    test('picks the SOONEST qualifying off boundary across schedules', () {
      final later = sched(id: 'late', off: 'Sunrise'); // ~06:00 → ~8h
      final sooner = sched(
        id: 'soon',
        on: '9:00 PM',
        off: '11:30 PM',
        action: 'Pattern: Blue',
      ); // 1.5h from 22:00
      final n = nextEnabledOffBoundaryWithin([later, sooner], night);
      expect(n!.scheduleName, 'Blue');
      expect(n.offLabel, '11:30 PM');
    });
  });

  group('window boundary', () {
    // Sunrise approximated at 06:00 next day.
    test('just inside 18h → fires', () {
      // 12:30 PM → next 06:00 is 17.5h out (< 18h).
      final n = nextEnabledOffBoundaryWithin([sched()], DateTime(2026, 7, 9, 12, 30));
      expect(n, isNotNull);
    });

    test('just outside 18h → silent', () {
      // 11:30 AM → next 06:00 is 18.5h out (> 18h).
      final n = nextEnabledOffBoundaryWithin([sched()], DateTime(2026, 7, 9, 11, 30));
      expect(n, isNull);
    });
  });

  group('scheduleDisplayName', () {
    test('strips reason and Pattern: prefix', () {
      expect(
        scheduleDisplayName(sched(action: 'Warm White (Daily evening lighting)')),
        'Warm White',
      );
      expect(scheduleDisplayName(sched(action: 'Pattern: Candy Cane')), 'Candy Cane');
      expect(scheduleDisplayName(sched(action: 'Turn Off')), 'Turn Off');
    });
  });
}
