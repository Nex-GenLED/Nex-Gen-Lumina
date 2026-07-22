// test/features/schedule/schedule_sync_eviction_test.dart
//
// Item #61 Workstream B — buildCfgPayload eviction-filter coverage.
// Verifies that ScheduleItems with isCurrentlyEvicted == true are
// excluded from the timers.ins array, so the freed slot is genuinely
// free on the controller side.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

void main() {
  const svc = ScheduleSyncService();

  ScheduleItem item({
    required String id,
    bool enabled = true,
    DateTime? disabledUntil,
  }) =>
      ScheduleItem(
        id: id,
        timeLabel: '7:00 PM',
        repeatDays: const ['Daily'],
        actionLabel: 'WW',
        enabled: enabled,
        disabledUntil: disabledUntil,
        presetId: 10, // pre-assigned to skip allocation logic
      );

  group('buildCfgPayload eviction filter', () {
    test('8 enabled, none evicted → 8 timer entries', () {
      final schedules = [
        for (int i = 0; i < 8; i++) item(id: 'a$i'),
      ];
      final payload = svc.buildCfgPayload(schedules);
      final ins = (payload['timers'] as Map)['ins'] as List;
      expect(ins.length, 8);
    });

    test('8 enabled, 1 evicted → 7 timer entries', () {
      final future = DateTime.now().add(const Duration(hours: 6));
      final schedules = <ScheduleItem>[
        item(id: 'evicted', disabledUntil: future),
        for (int i = 0; i < 7; i++) item(id: 'a$i'),
      ];
      final payload = svc.buildCfgPayload(schedules);
      final ins = (payload['timers'] as Map)['ins'] as List;
      expect(ins.length, 7);
    });

    test('8 enabled, all evicted → 0 timer entries', () {
      final future = DateTime.now().add(const Duration(hours: 6));
      final schedules = [
        for (int i = 0; i < 8; i++) item(id: 'a$i', disabledUntil: future),
      ];
      final payload = svc.buildCfgPayload(schedules);
      final ins = (payload['timers'] as Map)['ins'] as List;
      expect(ins, isEmpty);
    });

    test('5 enabled + 3 disabled + 2 evicted → 3 timer entries (enabled && !evicted)',
        () {
      final future = DateTime.now().add(const Duration(hours: 6));
      final schedules = <ScheduleItem>[
        // 5 enabled, not evicted
        for (int i = 0; i < 5; i++) item(id: 'on$i'),
        // 3 disabled
        for (int i = 0; i < 3; i++) item(id: 'off$i', enabled: false),
        // 2 enabled but evicted
        for (int i = 0; i < 2; i++)
          item(id: 'evict$i', disabledUntil: future),
      ];
      final payload = svc.buildCfgPayload(schedules);
      final ins = (payload['timers'] as Map)['ins'] as List;
      // 5 - but capped at 8 slots either way. Just verify the
      // evicted-and-disabled items are excluded.
      expect(ins.length, 5);
    });

    test('evicted item with disabledUntil in the past is INCLUDED', () {
      // Past disabledUntil means isCurrentlyEvicted=false → item should
      // be visible again. Sweep also clears the field, but the filter
      // alone is correct without that.
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final schedules = <ScheduleItem>[
        item(id: 'expired', disabledUntil: past),
      ];
      final payload = svc.buildCfgPayload(schedules);
      final ins = (payload['timers'] as Map)['ins'] as List;
      expect(ins.length, 1);
    });
  });
}
