import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

// Commit 2 (Option A): schedule_sync refuses sunrise/sunset ("solar") timers
// at the write boundary. The app maps solar labels to WLED hour 24/25, which
// WLED never fires as sunrise/sunset — hour 24 fires HOURLY (snapping lights
// off every hour on a solar-OFF boundary) and hour 25 never matches the RTC.
// These tests pin the buildCfgPayload boundary (the pure one; also the path
// the lease manager uses). Coord-independent by construction — buildCfgPayload
// takes no coordinates.
void main() {
  const svc = ScheduleSyncService();

  ScheduleItem item({
    required String id,
    required String time,
    String? offTime,
    List<String> days = const ['Daily'],
    bool enabled = true,
  }) =>
      ScheduleItem(
        id: id,
        timeLabel: time,
        offTimeLabel: offTime,
        repeatDays: days,
        actionLabel: 'Test $id',
        enabled: enabled,
        presetId: 11,
      );

  List<Map<String, dynamic>> ins(List<ScheduleItem> s) =>
      ((svc.buildCfgPayload(s)['timers'] as Map)['ins'] as List)
          .cast<Map<String, dynamic>>();

  group('solar refuse', () {
    test('solar ON label → no timer written', () {
      expect(ins([item(id: 'x', time: 'sunset')]), isEmpty);
      expect(ins([item(id: 'y', time: 'sunrise')]), isEmpty);
    });

    test('clock ON + solar OFF → WHOLE schedule refused (a solar OFF is the '
        'hour:24 hourly-snap-off — as bad as a solar ON)', () {
      // The clock ON would be valid alone, but the solar OFF poisons it.
      expect(ins([item(id: 'z', time: '7:00 PM', offTime: 'sunrise')]), isEmpty);
    });

    test('refusal is coord-independent (buildCfgPayload has no coords input)',
        () {
      // There is no coordinate parameter — the refuse can never depend on one.
      expect(ins([item(id: 'c', time: 'Sunset')]), isEmpty);
    });
  });

  group('no regression — valid schedules still arm', () {
    test('clock time passes, hour is a real 0-23 value', () {
      final built = ins([item(id: 'ok', time: '7:00 PM')]);
      expect(built.length, 1);
      expect(built.first['hour'], 19);
      expect(built.first['hour'], inInclusiveRange(0, 23));
    });

    test('clock ON + clock OFF → two timers, both real hours', () {
      final built = ins([item(id: 'onoff', time: '6:00 AM', offTime: '10:00 PM')]);
      expect(built.length, 2);
      expect(built.every((t) => (t['hour'] as int) >= 0 && (t['hour'] as int) <= 23),
          isTrue);
    });

    test('dow:0 guard still fires (empty repeatDays → no timer)', () {
      expect(ins([item(id: 'nodays', time: '7:00 PM', days: const [])]), isEmpty);
    });

    test('unparseable time still yields no timer (bad-time path intact)', () {
      expect(ins([item(id: 'junk', time: 'half past banana')]), isEmpty);
    });
  });
}
