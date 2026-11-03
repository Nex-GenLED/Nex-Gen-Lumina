// Every sun OFF shares one row (fix/122-timer-table, item 4).
//
// The controller has one sunrise row and one sunset row. Every sun OFF is the
// same macro (2, master off), so OFFs at the same event merge into one row
// with the union of their days. The editor gives every new schedule an OFF at
// Sunrise, so two ordinary schedules used to leave the second with no OFF at
// all. An ON at an event owns its row; an OFF at the same instant is warned.
//
// Drives the real ScheduleSyncService.syncAll and runs a week of minutes
// through firmware models transcribed from WLED source (support/
// wled_timer_firmware.dart — not bench-verified, hence "per WLED source").
// Sun times: sunrise 06:46, sunset 17:14.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

import 'arm_check_harness.dart';
import 'support/wled_timer_firmware.dart';

Future<ScheduleSyncResult> sync(
    FaithfulController repo, List<ScheduleItem> schedules) {
  final ref =
      armCheckContainer(repo, solarFlag: true).read(armCheckRefProvider);
  return const ScheduleSyncService().syncAll(ref, schedules);
}

List<String> week(WledTimerFirmware fw) => [for (final e in runDays(fw)) '$e'];

final firmwares = <String, WledTimerFirmware Function()>{
  '0.15.x': Wled015Timers.new,
  '16.0.1': Wled16Timers.new,
};

void main() {
  setUp(resetRepairAttempts);

  for (final MapEntry(key: name, value: make) in firmwares.entries) {
    group('per WLED source, $name', () {
      test(
          'weeknights "6 PM → Sunrise" and weekends "5 PM → Sunrise": every '
          'night ends at sunrise (the second schedule used to lose its OFF)',
          () async {
        final repo = FaithfulController();
        final r = await sync(repo, [
          patternSchedule(
              on: '6:00 PM',
              off: 'Sunrise',
              label: 'Pattern: weeknights',
              presetId: 10,
              repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']),
          patternSchedule(
              on: '5:00 PM',
              off: 'Sunrise',
              label: 'Pattern: weekends',
              presetId: 11,
              repeatDays: const ['Sat', 'Sun']),
        ]);
        expect(r.success, isTrue, reason: '${r.error}');
        expect(r.presetErrors, isEmpty);
        final fw = make()..post(repo.lastIns);
        expect(week(fw), [
          'Mon 06:46 → 2', // Sunday night ends
          'Mon 18:00 → 10',
          'Tue 06:46 → 2',
          'Tue 18:00 → 10',
          'Wed 06:46 → 2',
          'Wed 18:00 → 10',
          'Thu 06:46 → 2',
          'Thu 18:00 → 10',
          'Fri 06:46 → 2',
          'Fri 18:00 → 10',
          'Sat 06:46 → 2',
          'Sat 17:00 → 11',
          'Sun 06:46 → 2',
          'Sun 17:00 → 11',
        ]);
      });

      test(
          '"2 PM → Sunset" listed before "Sunset → 11 PM": the evening look '
          'still starts at sunset (the earlier OFF used to take the row) and '
          'the OFF that could not arm is named', () async {
        final repo = FaithfulController();
        final r = await sync(repo, [
          patternSchedule(
              on: '2:00 PM',
              off: 'Sunset',
              label: 'Pattern: afternoon',
              presetId: 12),
          patternSchedule(
              on: 'Sunset',
              off: '11:00 PM',
              label: 'Pattern: evening',
              presetId: 10),
        ]);
        expect(r.success, isTrue, reason: '${r.error}');
        final fw = make()..post(repo.lastIns);
        expect(week(fw).where((e) => e.startsWith('Wed')),
            ['Wed 14:00 → 12', 'Wed 17:14 → 10', 'Wed 23:00 → 2']);
        expect(
            r.presetErrors,
            contains('Only one sunrise and one sunset schedule are supported '
                'per controller — "Pattern: afternoon (Sunset OFF)" was not '
                'armed.'));
      });
    });
  }

  test('two Sunset OFFs share one sunset row with both schedules\' days', () {
    final r = const ScheduleSyncService().solarTimerSlots([
      patternSchedule(
          on: '2:00 PM',
          off: 'Sunset',
          label: 'Pattern: weekday afternoons',
          presetId: 12,
          repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']),
      patternSchedule(
          on: '1:00 PM',
          off: 'Sunset',
          label: 'Pattern: weekend afternoons',
          presetId: 13,
          repeatDays: const ['Sat', 'Sun']),
    ]);
    expect(r.rejected, isEmpty);
    expect(r.sunset, {'en': 1, 'hour': 254, 'min': 0, 'macro': 2, 'dow': 127});
  });
}
