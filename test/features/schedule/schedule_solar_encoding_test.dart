import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

// Option B — WLED 0.15.1 POSITIONAL solar encoding (behind the
// solar_scheduling flag, default OFF). Sunrise = timers.ins[8], sunset =
// ins[9], hour:255 marker, minute field = offset. These pin the pure encoding
// + assembly + the single-sunrise/single-sunset constraint. The coord gate and
// flag read live in syncAll (integration); the refuse-when-disabled path is
// covered here via solarEnabled:false. BENCH GATE: none of this is "done"
// until a real 0.15.1 controller is observed firing at actual sunrise/sunset.
void main() {
  const svc = ScheduleSyncService();

  ScheduleItem item({
    required String id,
    required String time,
    String? off,
    int? presetId = 15,
    List<String> days = const ['Daily'],
  }) =>
      ScheduleItem(
        id: id,
        timeLabel: time,
        offTimeLabel: off,
        repeatDays: days,
        actionLabel: 'Pattern: $id',
        enabled: true,
        presetId: presetId,
      );

  List<Map<String, dynamic>> generalIns(List<ScheduleItem> s,
          {required bool solar}) =>
      ((svc.buildCfgPayload(s, solarEnabled: solar)['timers'] as Map)['ins']
              as List)
          .cast<Map<String, dynamic>>();

  group('buildSolarTimerEntry — 0.15.1 encoding', () {
    test('hour:255 marker, offset in min, en:1, macro, dow', () {
      final e = ScheduleSyncService.buildSolarTimerEntry(
          offsetMinutes: 30, macro: 12, dow: 127);
      expect(e['hour'], 255, reason: 'the 0.15.1 solar marker, NOT 24/25');
      expect(e['min'], 30, reason: 'minute field is the offset, not a wall clock');
      expect(e['en'], 1);
      expect(e['macro'], 12);
      expect(e['dow'], 127);
    });

    test('offset clamps to ±120', () {
      expect(
          ScheduleSyncService.buildSolarTimerEntry(
              offsetMinutes: 999, macro: 1, dow: 1)['min'],
          120);
      expect(
          ScheduleSyncService.buildSolarTimerEntry(
              offsetMinutes: -999, macro: 1, dow: 1)['min'],
          -120);
    });
  });

  group('flag OFF — solar still refused (production-safe)', () {
    test('a solar schedule produces NO general timers', () {
      expect(generalIns([item(id: 'a', time: 'Sunset')], solar: false), isEmpty);
      expect(
          generalIns([item(id: 'b', time: '7:00 PM', off: 'Sunrise')],
              solar: false),
          isEmpty,
          reason: 'a half-solar schedule is refused whole when flag off');
    });
    test('clock schedules unaffected by the flag (slots 0-7)', () {
      final ins = generalIns([item(id: 'c', time: '7:00 PM')], solar: false);
      expect(ins.length, 1);
      expect(ins.first['hour'], 19);
    });
  });

  group('flag ON — buildCfgPayload defers solar to positional slots', () {
    test('solar-only schedule contributes NO general timer', () {
      expect(
          generalIns([item(id: 'a', time: 'Sunset', off: 'Sunrise')],
              solar: true),
          isEmpty,
          reason: 'both boundaries solar → nothing in slots 0-7');
    });
    test('mixed schedule: clock ON kept in 0-7, solar OFF deferred', () {
      final ins =
          generalIns([item(id: 'm', time: '7:00 PM', off: 'Sunrise')], solar: true);
      expect(ins.length, 1);
      expect(ins.first['hour'], 19, reason: 'clock ON stays a general timer');
    });
    test('clock schedules still land in general slots', () {
      final ins = generalIns([item(id: 'c', time: '6:30 AM')], solar: true);
      expect(ins.length, 1);
      expect(ins.first['hour'], 6);
    });
  });

  group('solarTimerSlots — constraint + flexible pairing', () {
    test('dusk-to-dawn fills BOTH slots from one schedule', () {
      final r = svc.solarTimerSlots(
          [item(id: 'dtd', time: 'Sunset', off: 'Sunrise', presetId: 15)]);
      expect(r.sunset, isNotNull);
      expect(r.sunrise, isNotNull);
      expect(r.sunset!['hour'], 255);
      expect(r.sunset!['macro'], 15, reason: 'sunset ON uses the design preset');
      expect(r.sunrise!['macro'], 2, reason: 'sunrise OFF uses the off preset');
      expect(r.rejected, isEmpty);
    });

    test('a 2nd sunset boundary is rejected (only one sunset slot)', () {
      final r = svc.solarTimerSlots([
        item(id: 'first', time: 'Sunset'),
        item(id: 'second', time: 'Sunset'),
      ]);
      expect(r.sunset, isNotNull);
      expect(r.rejected, hasLength(1));
      expect(r.rejected.first, contains('second'));
    });

    test('independent assignment: one sunrise + one sunset, different schedules',
        () {
      final r = svc.solarTimerSlots([
        item(id: 'morning', time: 'Sunrise'),
        item(id: 'evening', time: 'Sunset'),
      ]);
      expect(r.sunrise, isNotNull);
      expect(r.sunset, isNotNull);
      expect(r.rejected, isEmpty);
    });
  });

  group('assembleSolarAwareIns — 10-slot positional layout', () {
    bool isStub(Map<String, dynamic> t) => t['en'] == 0;
    test('sunrise → slot 8, sunset → slot 9, general → 0-7, rest stubs', () {
      final general = [
        {'en': 1, 'hour': 19, 'min': 0, 'macro': 15, 'dow': 127},
      ];
      final sunrise =
          ScheduleSyncService.buildSolarTimerEntry(offsetMinutes: 0, macro: 2, dow: 127);
      final sunset = ScheduleSyncService.buildSolarTimerEntry(
          offsetMinutes: -15, macro: 15, dow: 127);
      final ins = ScheduleSyncService.assembleSolarAwareIns(general,
          sunrise: sunrise, sunset: sunset);

      expect(ins.length, 10);
      expect(ins[0]['hour'], 19, reason: 'general timer at slot 0');
      expect(List.generate(7, (i) => i + 1).every((i) => isStub(ins[i])), isTrue,
          reason: 'slots 1-7 disabled');
      expect(ins[8]['hour'], 255, reason: 'sunrise at slot 8');
      expect(ins[8]['macro'], 2);
      expect(ins[9]['hour'], 255, reason: 'sunset at slot 9');
      expect(ins[9]['min'], -15, reason: 'offset round-trips');
    });

    test('no solar → slots 8/9 are disabled stubs (reclaim)', () {
      final ins = ScheduleSyncService.assembleSolarAwareIns(const []);
      expect(ins.length, 10);
      expect(isStub(ins[8]), isTrue);
      expect(isStub(ins[9]), isTrue);
    });
  });

  group('splitByTimerCapacity — solar boundaries do not consume general slots',
      () {
    test('8 clock + 1 dusk-to-dawn all fit (solar uses 8/9, not 0-7)', () {
      final schedules = [
        for (var i = 0; i < 8; i++) item(id: 'clock$i', time: '6:00 AM'),
        item(id: 'solar', time: 'Sunset', off: 'Sunrise'),
      ];
      final cap =
          ScheduleSyncService.splitByTimerCapacity(schedules, solarEnabled: true);
      expect(cap.overflowed, isFalse,
          reason: 'the solar schedule consumes no general slot');
      expect(cap.armed.length, 9);
    });
  });

  group('round-trip: dusk-to-dawn through the full flag-on push shape', () {
    test('slot 8 = sunrise OFF, slot 9 = sunset ON, both hour:255', () {
      final schedules = [
        item(id: 'dtd', time: 'Sunset', off: 'Sunrise', presetId: 15),
      ];
      final general = generalIns(schedules, solar: true); // empty (both solar)
      final solar = svc.solarTimerSlots(schedules);
      final ins = ScheduleSyncService.assembleSolarAwareIns(general,
          sunrise: solar.sunrise, sunset: solar.sunset);

      expect(ins.length, 10);
      expect(ins.sublist(0, 8).every((t) => t['en'] == 0), isTrue,
          reason: 'no general timers for a solar-only schedule');
      expect(ins[8]['hour'], 255);
      expect(ins[8]['macro'], 2, reason: 'sunrise slot holds the OFF boundary');
      expect(ins[9]['hour'], 255);
      expect(ins[9]['macro'], 15, reason: 'sunset slot holds the ON boundary');
    });
  });
}
