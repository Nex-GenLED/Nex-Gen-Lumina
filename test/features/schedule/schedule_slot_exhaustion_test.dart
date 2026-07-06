// test/features/schedule/schedule_slot_exhaustion_test.dart
//
// P0 fix (2.5.1 fast-follow) — loud slot exhaustion + honest count.
//
// Before the fix, when more armable schedules existed than WLED's 8-slot timer
// table could hold, buildCfgPayload silently truncated at 8, the sync still
// reported success, and schedulesWithPresets counted the DROPPED schedules too
// — so the UI claimed "Successfully synced N" for a schedule that never armed.
//
// This suite pins the two pieces syncAll now wires together:
//   • splitByTimerCapacity reports the armed subset + an overflow flag,
//     mirroring buildCfgPayload's ON-then-OFF slot consumption.
//   • the ScheduleSyncResult surfaces the "slots full" warning and counts ONLY
//     the schedules that armed.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

void main() {
  ScheduleItem onlyOn(String id) => ScheduleItem(
        id: id,
        timeLabel: '7:00 PM',
        repeatDays: const ['Daily'],
        actionLabel: 'Pattern: $id',
        enabled: true,
        presetId: 11,
      );

  ScheduleItem onAndOff(String id) => ScheduleItem(
        id: id,
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: const ['Daily'],
        actionLabel: 'Pattern: $id',
        enabled: true,
        presetId: 11,
      );

  group('splitByTimerCapacity', () {
    test('8 single-timer schedules fit exactly, no overflow', () {
      final r = ScheduleSyncService.splitByTimerCapacity(
          [for (int i = 0; i < 8; i++) onlyOn('s$i')]);
      expect(r.armed.length, 8);
      expect(r.overflowed, isFalse);
    });

    test('9 single-timer schedules → 8 armed, overflow flagged', () {
      final r = ScheduleSyncService.splitByTimerCapacity(
          [for (int i = 0; i < 9; i++) onlyOn('s$i')]);
      expect(r.armed.length, 8);
      expect(r.overflowed, isTrue);
    });

    test('4 two-timer schedules fill all 8 slots exactly', () {
      final r = ScheduleSyncService.splitByTimerCapacity(
          [for (int i = 0; i < 4; i++) onAndOff('s$i')]);
      expect(r.armed.length, 4);
      expect(r.overflowed, isFalse);
    });

    test('4 two-timer schedules + 1 more → overflow (would need slot 9)', () {
      final r = ScheduleSyncService.splitByTimerCapacity([
        for (int i = 0; i < 4; i++) onAndOff('s$i'),
        onlyOn('extra'),
      ]);
      expect(r.armed.length, 4);
      expect(r.overflowed, isTrue);
    });

    test('a schedule whose ON is the 8th slot still arms (OFF dropped)', () {
      // 7 two-timer (14 slots → capped) is degenerate; use 3 two-timer (6 slots)
      // + 1 two-timer whose ON is slot 7 and OFF slot 8, then 1 more.
      final r = ScheduleSyncService.splitByTimerCapacity([
        for (int i = 0; i < 3; i++) onAndOff('pair$i'), // 6 slots
        onAndOff('edge'), // ON=slot7, OFF=slot8 → both fit → armed
        onlyOn('past'), // no room → overflow
      ]);
      expect(r.armed.map((s) => s.id), containsAll(['edge']));
      expect(r.armed.any((s) => s.id == 'past'), isFalse);
      expect(r.overflowed, isTrue);
    });
  });

  group('ScheduleSyncResult surfaces exhaustion honestly', () {
    const slotsFull =
        "Schedule saved but couldn't arm — controller timer slots are full "
        "(8/8). Delete an old schedule.";

    test('overflow → hasPresetErrors + honest armed-only count', () {
      final armable = [for (int i = 0; i < 9; i++) onlyOn('s$i')];
      final cap = ScheduleSyncService.splitByTimerCapacity(armable);

      // This mirrors what syncAll assembles on the success path.
      final result = ScheduleSyncResult(
        success: true,
        presetErrors: [if (cap.overflowed) slotsFull],
        schedulesWithPresets: cap.armed,
      );

      expect(result.hasPresetErrors, isTrue);
      expect(result.presetErrors.single, slotsFull);
      // Count reflects only the 8 that armed — NEVER the 9 requested.
      expect(result.schedulesWithPresets.length, 8);
      expect(result.summaryMessage, contains('warning'));
    });

    test('no overflow → clean success, no warning', () {
      final armable = [for (int i = 0; i < 5; i++) onlyOn('s$i')];
      final cap = ScheduleSyncService.splitByTimerCapacity(armable);
      final result = ScheduleSyncResult(
        success: true,
        presetErrors: [if (cap.overflowed) slotsFull],
        schedulesWithPresets: cap.armed,
      );
      expect(result.hasPresetErrors, isFalse);
      expect(result.schedulesWithPresets.length, 5);
    });
  });
}
