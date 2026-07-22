// test/features/schedule/schedule_sync_time_parse_test.dart
//
// Latent timer-bug fix — _parseTimeLabel midnight fallback.
//
// Verifies via the public buildCfgPayload that:
//   • 24-hour labels ("10:11", "23:30", "0:05") parse to the right hour/min
//     instead of silently falling back to 00:00 (midnight).
//   • 12-hour am/pm labels still parse correctly (regression guard).
//   • A genuinely unparseable label is NOT armed at midnight — the timer is
//     dropped entirely (buildCfgPayload emits no entry for it). The loud
//     "left unarmed + warned" surfacing lives in syncAll's pre-arm guard.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

void main() {
  const svc = ScheduleSyncService();

  ScheduleItem item({
    required String timeLabel,
    String? offTimeLabel,
  }) =>
      ScheduleItem(
        id: 't',
        timeLabel: timeLabel,
        offTimeLabel: offTimeLabel,
        repeatDays: const ['Daily'],
        actionLabel: 'Pattern: Test',
        enabled: true,
        presetId: 10, // pre-assigned to skip allocation logic
      );

  List<Map<String, dynamic>> insFor(ScheduleItem s) {
    final payload = svc.buildCfgPayload([s]);
    final ins = ((payload['timers'] as Map)['ins'] as List)
        .cast<Map<String, dynamic>>();
    return ins;
  }

  group('_parseTimeLabel via buildCfgPayload', () {
    test('bare 24-hour "10:11" parses to 10:11, NOT midnight', () {
      final ins = insFor(item(timeLabel: '10:11'));
      expect(ins.length, 1);
      expect(ins.first['hour'], 10);
      expect(ins.first['min'], 11);
    });

    test('24-hour "23:30" parses to 23:30', () {
      final ins = insFor(item(timeLabel: '23:30'));
      expect(ins.single['hour'], 23);
      expect(ins.single['min'], 30);
    });

    test('24-hour "0:05" parses to 00:05 (genuine midnight-ish time allowed)',
        () {
      final ins = insFor(item(timeLabel: '0:05'));
      expect(ins.single['hour'], 0);
      expect(ins.single['min'], 5);
    });

    test('am/pm regression — "7:00 PM" → 19:00', () {
      final ins = insFor(item(timeLabel: '7:00 PM'));
      expect(ins.single['hour'], 19);
      expect(ins.single['min'], 0);
    });

    test('am/pm regression — "12:00 AM" → 00:00', () {
      final ins = insFor(item(timeLabel: '12:00 AM'));
      expect(ins.single['hour'], 0);
      expect(ins.single['min'], 0);
    });

    test('am/pm regression — "12:30 PM" → 12:30 (noon)', () {
      final ins = insFor(item(timeLabel: '12:30 PM'));
      expect(ins.single['hour'], 12);
      expect(ins.single['min'], 30);
    });

    test('unparseable label is dropped, NOT armed at midnight', () {
      final ins = insFor(item(timeLabel: 'whenever'));
      expect(ins, isEmpty,
          reason: 'unparseable time must not arm a phantom 00:00 timer');
    });

    test('out-of-range 24-hour "25:99" is dropped, NOT clamped/armed', () {
      final ins = insFor(item(timeLabel: '25:99'));
      expect(ins, isEmpty);
    });

    test('sunrise/sunset still map to solar timer codes (24/25)', () {
      expect(insFor(item(timeLabel: 'sunrise')).single['hour'], 24);
      expect(insFor(item(timeLabel: 'sunset')).single['hour'], 25);
    });

    test('valid ON with unparseable OFF — ON arms, malformed OFF dropped', () {
      // buildCfgPayload drops only the bad boundary; syncAll's pre-arm guard
      // is what removes the whole half-parseable schedule. Here we just assert
      // the malformed OFF never becomes a midnight timer.
      final ins = insFor(item(timeLabel: '6:00 PM', offTimeLabel: 'nope'));
      expect(ins.length, 1);
      expect(ins.single['hour'], 18);
    });
  });
}
