// An overnight schedule's OFF fires on the NEXT day (fix/122-timer-table,
// item 2).
//
// WLED checks the weekday bit of the minute a row fires. The app gave the OFF
// row the ON days' bits, so a Mon–Fri "Sunset → Sunrise" turned off on Monday
// morning (ending nothing) and never on Saturday morning: Friday night ran
// until Monday. Each test drives the real ScheduleSyncService.syncAll and runs
// a whole week of minutes through firmware models transcribed from WLED source
// (support/wled_timer_firmware.dart — not bench-verified, hence "per WLED
// source"). Sun times: sunrise 06:46, sunset 17:14.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

import 'arm_check_harness.dart';
import 'support/wled_timer_firmware.dart';

const int kLook = 10;
const List<String> kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

Future<List<Map<String, dynamic>>> syncTable(ScheduleItem s) async {
  final repo = FaithfulController();
  final ref =
      armCheckContainer(repo, solarFlag: true).read(armCheckRefProvider);
  final r = await const ScheduleSyncService().syncAll(ref, [s]);
  expect(r.success, isTrue, reason: 'sync: ${r.error} ${r.presetErrors}');
  return repo.lastIns;
}

/// Everything that fires from Monday 00:00 for [days] days.
List<String> week(WledTimerFirmware fw, {int days = 7, int start = 1}) => [
      for (final e in runDays(fw, days: days, startWeekday: start)) '$e',
    ];

final firmwares = <String, WledTimerFirmware Function()>{
  '0.15.x': Wled015Timers.new,
  '16.0.1': Wled16Timers.new,
};

void main() {
  setUp(resetRepairAttempts);

  for (final MapEntry(key: name, value: make) in firmwares.entries) {
    group('per WLED source, $name', () {
      test(
          'Mon–Fri "Sunset → Sunrise": Friday night ends Saturday at sunrise, '
          'and nothing fires on Monday morning', () async {
        final fw = make()
          ..post(await syncTable(patternSchedule(
              on: 'Sunset',
              off: 'Sunrise',
              presetId: kLook,
              repeatDays: kWeekdays)));
        expect(week(fw), [
          'Mon 17:14 → $kLook',
          'Tue 06:46 → 2',
          'Tue 17:14 → $kLook',
          'Wed 06:46 → 2',
          'Wed 17:14 → $kLook',
          'Thu 06:46 → 2',
          'Thu 17:14 → $kLook',
          'Fri 06:46 → 2',
          'Fri 17:14 → $kLook',
          'Sat 06:46 → 2',
        ]);
      });

      test('Fri+Sat "6 PM → 1 AM": each night ends at 1 AM the next morning',
          () async {
        final fw = make()
          ..post(await syncTable(patternSchedule(
              on: '6:00 PM',
              off: '1:00 AM',
              presetId: kLook,
              repeatDays: const ['Fri', 'Sat'])));
        expect(week(fw), [
          'Fri 18:00 → $kLook',
          'Sat 01:00 → 2',
          'Sat 18:00 → $kLook',
          'Sun 01:00 → 2',
        ]);
      });

      test('Fri+Sat "Sunset → 12:00 AM": midnight belongs to the next day',
          () async {
        final fw = make()
          ..post(await syncTable(patternSchedule(
              on: 'Sunset',
              off: '12:00 AM',
              presetId: kLook,
              repeatDays: const ['Fri', 'Sat'])));
        expect(week(fw), [
          'Fri 17:14 → $kLook',
          'Sat 00:00 → 2',
          'Sat 17:14 → $kLook',
          'Sun 00:00 → 2',
        ]);
      });

      test('Sunday-only "6 PM → Sunrise" ends on Monday morning', () async {
        final fw = make()
          ..post(await syncTable(patternSchedule(
              on: '6:00 PM',
              off: 'Sunrise',
              presetId: kLook,
              repeatDays: const ['Sun'])));
        expect(week(fw, days: 2, start: 7),
            ['Sun 18:00 → $kLook', 'Mon 06:46 → 2']);
      });

      test('same-day shapes keep their own days (Mon–Fri "6 PM → 11 PM", '
          'Mon–Fri "12:01 AM → Sunrise")', () async {
        final evening = make()
          ..post(await syncTable(patternSchedule(
              on: '6:00 PM',
              off: '11:00 PM',
              presetId: kLook,
              repeatDays: kWeekdays)));
        final evenings = week(evening);
        expect(evenings.where((e) => e.endsWith('→ 2')).map((e) => e.substring(0, 3)),
            kWeekdays);
        final morning = make()
          ..post(await syncTable(patternSchedule(
              on: '12:01 AM',
              off: 'Sunrise',
              presetId: kLook,
              repeatDays: kWeekdays)));
        final mornings = week(morning);
        expect(mornings.where((e) => e.endsWith('→ 2')).map((e) => e.substring(0, 3)),
            kWeekdays);
      });

      test('daily schedules are unchanged', () async {
        final fw = make()
          ..post(await syncTable(patternSchedule(
              on: 'Sunset', off: 'Sunrise', presetId: kLook)));
        expect(week(fw).where((e) => e.endsWith('06:46 → 2')), hasLength(7));
      });
    });
  }
}
