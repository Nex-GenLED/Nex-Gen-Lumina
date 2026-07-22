import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/solar_schedule_cleanup.dart';

// Commit 4: one-time, LAN-only remediation that re-syncs an affected user's
// schedules once so the padded push clears stale hour:24/25 timers. These
// pin the pure control flow (all I/O injected).
void main() {
  ScheduleItem item({String time = '7:00 PM', String? offTime}) => ScheduleItem(
        id: 's',
        timeLabel: time,
        offTimeLabel: offTime,
        repeatDays: const ['Daily'],
        actionLabel: 'Test',
        enabled: true,
      );

  final solarSchedules = [item(time: 'Sunset', offTime: 'Sunrise')];
  final clockSchedules = [item(time: '7:00 PM', offTime: '11:00 PM')];

  ScheduleSyncResult ok() => ScheduleSyncResult(success: true);
  ScheduleSyncResult offLan() =>
      ScheduleSyncResult.deferredOffLan(schedulesWithPresets: const []);
  ScheduleSyncResult failed() => ScheduleSyncResult(success: false, error: 'x');

  group('scheduleListHasSolar', () {
    test('detects solar on either boundary, case-insensitively', () {
      expect(scheduleListHasSolar([item(time: 'sunset')]), isTrue);
      expect(scheduleListHasSolar([item(time: 'SUNRISE')]), isTrue);
      expect(scheduleListHasSolar([item(time: '7:00 PM', offTime: 'Sunset')]),
          isTrue);
    });
    test('clock-only schedules are not solar', () {
      expect(scheduleListHasSolar(clockSchedules), isFalse);
      expect(scheduleListHasSolar(const []), isFalse);
    });
  });

  group('runSolarScheduleCleanupIfNeeded', () {
    test('flagged user on-LAN → ONE sync, flag set, cleaned', () async {
      var syncs = 0;
      var marked = 0;
      final outcome = await runSolarScheduleCleanupIfNeeded(
        alreadyDone: false,
        schedules: solarSchedules,
        onLan: true,
        runSync: () async {
          syncs++;
          return ok();
        },
        markDone: () async => marked++,
      );
      expect(outcome, SolarCleanupOutcome.cleaned);
      expect(syncs, 1, reason: 'exactly one re-sync');
      expect(marked, 1, reason: 'flag set only after a successful sync');
    });

    test('flag already set → NO sync, alreadyDone', () async {
      var syncs = 0;
      var marked = 0;
      final outcome = await runSolarScheduleCleanupIfNeeded(
        alreadyDone: true,
        schedules: solarSchedules,
        onLan: true,
        runSync: () async {
          syncs++;
          return ok();
        },
        markDone: () async => marked++,
      );
      expect(outcome, SolarCleanupOutcome.alreadyDone);
      expect(syncs, 0);
      expect(marked, 0);
    });

    test('off-LAN → deferred, NO sync, flag left unset', () async {
      var syncs = 0;
      var marked = 0;
      final outcome = await runSolarScheduleCleanupIfNeeded(
        alreadyDone: false,
        schedules: solarSchedules,
        onLan: false,
        runSync: () async {
          syncs++;
          return ok();
        },
        markDone: () async => marked++,
      );
      expect(outcome, SolarCleanupOutcome.deferredOffLan);
      expect(syncs, 0, reason: 'never attempt a cfg write off-LAN');
      expect(marked, 0, reason: 'flag stays unset so a LAN launch retries');
    });

    test('no solar schedules → noSolar, NO sync, no flag write', () async {
      var syncs = 0;
      var marked = 0;
      final outcome = await runSolarScheduleCleanupIfNeeded(
        alreadyDone: false,
        schedules: clockSchedules,
        onLan: true,
        runSync: () async {
          syncs++;
          return ok();
        },
        markDone: () async => marked++,
      );
      expect(outcome, SolarCleanupOutcome.noSolar);
      expect(syncs, 0);
      expect(marked, 0);
    });

    test('sync attempted but did not land → syncFailed, flag unset', () async {
      var marked = 0;
      final outcome = await runSolarScheduleCleanupIfNeeded(
        alreadyDone: false,
        schedules: solarSchedules,
        onLan: true,
        runSync: () async => failed(),
        markDone: () async => marked++,
      );
      expect(outcome, SolarCleanupOutcome.syncFailed);
      expect(marked, 0, reason: 'flag must not latch before timers are cleared');
    });

    test('a mid-sync off-LAN race (deferredOffLan result) → not marked',
        () async {
      var marked = 0;
      final outcome = await runSolarScheduleCleanupIfNeeded(
        alreadyDone: false,
        schedules: solarSchedules,
        onLan: true,
        runSync: () async => offLan(),
        markDone: () async => marked++,
      );
      expect(outcome, SolarCleanupOutcome.syncFailed);
      expect(marked, 0);
    });
  });
}
