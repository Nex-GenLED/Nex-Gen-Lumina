// test/features/schedule/solar_first_wins_test.dart
//
// SOLAR FIRST-WINS CONTENTION — audit/SOLAR_COMPARATOR.md part 3.
//
// WLED 0.15.1 has exactly ONE sunrise slot (8) and ONE sunset slot (9). Ellie
// Cochran has TWO Sunset->Sunrise schedules, so the moment the solar flag flips
// one of hers is rejected. This pins that she is told WHICH schedule lost and
// why — the message must name the schedule and the boundary, not be a count.
//
// The rendering half shipped in +61 (presetErrors text now renders in the
// SnackBar and status row with a Details dialog). This suite pins the half that
// composes the message.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

void main() {
  const svc = ScheduleSyncService();

  ScheduleItem dusk(String id, {String on = 'Sunset', String? off = 'Sunrise'}) =>
      ScheduleItem(
        id: id,
        timeLabel: on,
        offTimeLabel: off,
        repeatDays: const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
        actionLabel: 'Pattern: $id',
        enabled: true,
        presetId: 11,
      );

  group('one sunset slot — the second schedule is rejected, and named', () {
    test("Ellie's exact shape: two Sunset schedules, one arms one is rejected",
        () {
      // Her live data: "Pattern: 1 On 4 Off - Solid" and
      // "Warm White (Daily evening lighting)", both Sunset -> Sunrise.
      final res = svc.solarTimerSlots([
        dusk('1 On 4 Off - Solid'),
        dusk('Warm White (Daily evening lighting)'),
      ]);

      expect(res.sunset, isNotNull, reason: 'the FIRST one arms');
      expect(res.rejected, isNotEmpty, reason: 'the second must be refused');

      final msg = res.rejected.join(' | ');
      expect(msg, contains('Warm White (Daily evening lighting)'),
          reason: 'the LOSING schedule must be named — a count is not enough');
      expect(msg, contains('Sunset'),
          reason: 'and which boundary of it lost');
      expect(msg, isNot(contains('1 On 4 Off - Solid')),
          reason: 'the winner must not be reported as rejected');
    });

    test('the rejection text is what syncAll turns into a user-facing warning',
        () {
      final res = svc.solarTimerSlots([dusk('A'), dusk('B')]);
      // syncAll wraps each entry as:
      //   'Only one sunrise and one sunset schedule are supported per
      //    controller — "$who" was not armed.'
      for (final who in res.rejected) {
        expect(who, isNotEmpty);
        expect(who, matches(RegExp(r'\(.*(Sunset|Sunrise).*(ON|OFF)\)')),
            reason: 'names the boundary and its direction so the message reads '
                'as an instruction, not a code');
      }
    });

    test('a single solar schedule is never rejected', () {
      final res = svc.solarTimerSlots([dusk('only')]);
      expect(res.sunset, isNotNull);
      expect(res.rejected, isEmpty);
    });

    test('sunrise and sunset are independent slots', () {
      // One schedule owning sunset + another owning sunrise both fit.
      final res = svc.solarTimerSlots([
        dusk('dusk-only', on: 'Sunset', off: null),
        dusk('dawn-only', on: 'Sunrise', off: null),
      ]);
      expect(res.sunset, isNotNull);
      expect(res.sunrise, isNotNull);
      expect(res.rejected, isEmpty);
    });

    test('the global sunrise-off takes slot 8 and supersedes silently', () {
      // sunriseTaken=true models the global "off at sunrise" setting owning
      // slot 8. A schedule's redundant sunrise OFF is the same macro 2, so it
      // is superseded WITHOUT a user-facing rejection — its sunset still arms.
      final res =
          svc.solarTimerSlots([dusk('dusk-to-dawn')], sunriseTaken: true);
      expect(res.sunset, isNotNull, reason: 'the ON boundary still arms');
      expect(res.rejected, isEmpty,
          reason: 'identical master-OFF effect — warning the user would be noise');
    });
  });
}
