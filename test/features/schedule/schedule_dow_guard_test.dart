// test/features/schedule/schedule_dow_guard_test.dart
//
// P0 fix (2.5.1 fast-follow) — dead dow:0 timer guard.
//
// Ground truth from the field: enabled schedules with empty/unrecognized
// repeatDays produced a WLED dow mask of 0 ("no days"), so the timer took a
// slot but NEVER fired — and accumulated until the 8-slot table was full.
// Policy is REFUSE-AND-WARN (never silently normalize an empty set to daily).
//
// This suite asserts NO creation/arming path can emit an ENABLED dow:0 timer:
//   • buildCfgPayload drops schedules whose repeatDays yield dow:0.
//   • valid repeat days still arm with the correct nonzero mask.
//   • the AI path (partitionSchedulableByDays / buildScheduleItemsFromIntents)
//     rejects empty/garbage repeatDays instead of persisting a dead entry.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/features/ai/scheduling_intent_handler.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';

void main() {
  const svc = ScheduleSyncService();

  ScheduleItem item({
    required String id,
    required List<String> repeatDays,
    String time = '8:44 PM',
  }) =>
      ScheduleItem(
        id: id,
        timeLabel: time,
        repeatDays: repeatDays,
        actionLabel: 'Pattern: Test',
        enabled: true,
        presetId: 11, // pre-assigned to skip allocation logic
      );

  List<Map<String, dynamic>> insFor(List<ScheduleItem> s) =>
      ((svc.buildCfgPayload(s)['timers'] as Map)['ins'] as List)
          .cast<Map<String, dynamic>>();

  group('buildCfgPayload never emits an enabled dow:0 timer', () {
    test('empty repeatDays → dropped entirely (no phantom dead timer)', () {
      expect(insFor([item(id: 'a', repeatDays: const [])]), isEmpty);
    });

    test('all-unrecognized repeatDays → dropped', () {
      expect(insFor([item(id: 'a', repeatDays: const ['Funday', 'xyz'])]),
          isEmpty);
    });

    test('valid single day arms with the correct nonzero mask', () {
      final ins = insFor([item(id: 'a', repeatDays: const ['Mon'])]);
      expect(ins.single['dow'], kWledDowMonday);
      expect(ins.single['dow'], isNot(0));
    });

    test('Daily arms with 127', () {
      final ins = insFor([item(id: 'a', repeatDays: const ['Daily'])]);
      expect(ins.single['dow'], kWledDowDaily);
    });

    test('mixed set: only valid schedules arm, none with dow:0', () {
      final ins = insFor([
        item(id: 'ok1', repeatDays: const ['Mon']),
        item(id: 'dead1', repeatDays: const []),
        item(id: 'ok2', repeatDays: const ['Fri', 'Sat']),
        item(id: 'dead2', repeatDays: const ['nonsense']),
      ]);
      expect(ins.length, 2, reason: 'the two empty/garbage entries are dropped');
      for (final t in ins) {
        expect(t['dow'], isNot(0),
            reason: 'no armed timer may carry a dead dow:0 mask');
      }
    });

    test('unrecognized names among valid ones contribute nothing but still arm',
        () {
      // ['Mon','gibberish'] → mask is just Monday (nonzero) → armed.
      final ins = insFor([item(id: 'a', repeatDays: const ['Mon', 'gibberish'])]);
      expect(ins.single['dow'], kWledDowMonday);
    });
  });

  group('AI path rejects empty/garbage repeatDays (refuse-and-warn)', () {
    SchedulingIntent intent(List<String> days, {String name = 'Chiefs Red'}) =>
        SchedulingIntent(
          timeLabel: '8:44 PM',
          repeatDays: days,
          patternName: name,
        );

    test('partitionSchedulableByDays drops empty-days intents by name', () {
      final part = partitionSchedulableByDays([
        intent(const ['Mon'], name: 'Good'),
        intent(const [], name: 'OneShot'),
        intent(const ['zzz'], name: 'Garbage'),
      ]);
      expect(part.schedulable.map((i) => i.patternName), ['Good']);
      expect(part.unschedulableNames, containsAll(['OneShot', 'Garbage']));
    });

    test('every intent unschedulable → schedulable empty (nothing persisted)',
        () {
      final part = partitionSchedulableByDays([intent(const [])]);
      expect(part.schedulable, isEmpty);
      expect(part.unschedulableNames, isNotEmpty);
    });

    test('buildScheduleItemsFromIntents skips dow:0 intents defensively', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          intent(const ['Mon'], name: 'Good'),
          intent(const [], name: 'Dead'),
        ],
        sourcePromptId: 'p',
        batchTs: 1234,
        sharedWledPayload: const {'on': true},
      );
      expect(items.length, 1);
      expect(items.single.actionLabel, 'Pattern: Good');
      expect(wledDowMaskForDayList(items.single.repeatDays), isNot(0));
    });
  });
}
