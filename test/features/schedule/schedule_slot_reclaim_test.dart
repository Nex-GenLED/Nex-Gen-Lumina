// test/features/schedule/schedule_slot_reclaim_test.dart
//
// P0 fix (2.5.1 fast-follow) — WLED timer-slot reclaim via padding.
//
// Root cause: WLED merges `timers.ins` BY INDEX and never clears slots beyond
// the pushed array's length. The app used to send only the active timers ("no
// padding needed"), so when a schedule was deleted the slot it had occupied
// kept its stale (often dow:0) timer forever — the accumulation that filled the
// 8-slot table with dead timers.
//
// Fix: every FINAL pushed payload is padded to exactly kMaxWledTimers with
// disabled stubs, so a shrinking set overwrites (zeros) the slots it vacated.
// This suite pins padTimersToMax and the N→N-1 reclaim it produces, plus the
// invariant that real sunset(25)/sunrise(24) entries survive padding untouched.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

void main() {
  const svc = ScheduleSyncService();
  const max = ScheduleSyncService.kMaxWledTimers;

  bool isDisabledStub(Map<String, dynamic> t) =>
      t['en'] == 0 &&
      t['hour'] == 0 &&
      t['min'] == 0 &&
      t['macro'] == 0 &&
      t['dow'] == 0;

  ScheduleItem sched(String id, {String time = '7:00 PM'}) => ScheduleItem(
        id: id,
        timeLabel: time,
        repeatDays: const ['Daily'],
        actionLabel: 'Pattern: $id',
        enabled: true,
        presetId: 11,
      );

  /// Mirrors what syncAll pushes: real timers from buildCfgPayload, padded to 8.
  List<Map<String, dynamic>> pushedIns(List<ScheduleItem> s) {
    final real = ((svc.buildCfgPayload(s)['timers'] as Map)['ins'] as List)
        .cast<Map<String, dynamic>>();
    return ScheduleSyncService.padTimersToMax(real);
  }

  group('padTimersToMax', () {
    test('empty → 8 disabled stubs', () {
      final out = ScheduleSyncService.padTimersToMax([]);
      expect(out.length, max);
      expect(out.every(isDisabledStub), isTrue);
    });

    test('3 real → 8 total, real kept first, remaining are disabled stubs', () {
      final real = [
        for (int i = 0; i < 3; i++)
          {'en': true, 'hour': 19, 'min': i, 'macro': 11 + i, 'dow': 127},
      ];
      final out = ScheduleSyncService.padTimersToMax(real);
      expect(out.length, max);
      expect(out.take(3), real);
      expect(out.skip(3).every(isDisabledStub), isTrue);
    });

    test('more than 8 → truncated to 8', () {
      final real = [
        for (int i = 0; i < 12; i++)
          {'en': true, 'hour': 1, 'min': 0, 'macro': 11, 'dow': 127},
      ];
      expect(ScheduleSyncService.padTimersToMax(real).length, max);
    });
  });

  group('N → N-1 reclaims the vacated slot', () {
    test('deleting the 3rd schedule turns slot index 2 into a disabled stub',
        () {
      final three = pushedIns([sched('a'), sched('b'), sched('c')]);
      final two = pushedIns([sched('a'), sched('b')]);

      // Both payloads are always exactly 8 slots (authoritative over all slots).
      expect(three.length, max);
      expect(two.length, max);

      // With 3 schedules slot 2 is a real timer; after deleting one it becomes
      // a disabled stub — i.e. the controller slot gets zeroed on next sync.
      expect(isDisabledStub(three[2]), isFalse);
      expect(isDisabledStub(two[2]), isTrue);

      // The surviving two schedules still occupy slots 0 and 1.
      expect(two[0]['macro'], 11);
      expect(two[1]['macro'], 11);
    });

    test('going to zero schedules zeros all 8 slots', () {
      final none = pushedIns(const []);
      expect(none.length, max);
      expect(none.every(isDisabledStub), isTrue);
    });
  });

  group('solar refuse (Option A) — sunrise/sunset are not written', () {
    // WAS: "solar entries survive padding" (asserted hour 25/24 preserved).
    // That premise is now the bug: WLED does not honor hour 24/25 as
    // sunrise/sunset (24 = hourly, 25 = never), so the app refuses solar
    // until it's re-encoded. See memory/project_solar_schedules_never_fire.
    test('solar schedules produce NO real timers — all slots disabled stubs',
        () {
      final ins = pushedIns([
        sched('sunsetOn', time: 'sunset'),
        sched('sunriseOn', time: 'sunrise'),
      ]);
      expect(ins.length, max);
      expect(ins.every(isDisabledStub), isTrue,
          reason: 'no hour:24/25 timer is written; the reclaim push clears '
              'any that a prior sync left on the device');
    });

    test('case-insensitive: "Sunset" / "SUNRISE" are also refused', () {
      final ins = pushedIns([
        sched('a', time: 'Sunset'),
        sched('b', time: 'SUNRISE'),
      ]);
      expect(ins.every(isDisabledStub), isTrue);
    });
  });
}
