// test/features/ai/scheduling_intent_handler_test.dart
//
// Item construction tests for the compound schedule dispatcher
// (Item #51 Type-A completion). Exercises the pure helper
// `buildScheduleItemsFromIntents` extracted from
// `handleSchedulingIntents` so the per-item invariants — shared
// sourcePromptId, unique ids, field defaulting, "Pattern: " action-label
// prefix, atomic-batch one-blob wledPayload — can be asserted without
// standing up Riverpod, ScaffoldMessenger, or Firebase Auth.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/scheduling_intent_handler.dart';

void main() {
  // Fixed batch-timestamp so id format assertions stay deterministic.
  const batchTs = 1_700_000_000_000;
  const sharedPromptId = 'prompt-uuid-abc';
  const sharedWled = <String, dynamic>{
    'on': true,
    'bri': 200,
    'seg': [
      {
        'fx': 0,
        'col': [
          [255, 255, 255, 0],
        ],
      },
    ],
  };

  Map<String, dynamic> _intent({
    String patternName = 'Warm White Wash',
    String timeLabel = 'Sunset',
    String? offTimeLabel = 'Sunrise',
    List<String> repeatDays = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
  }) =>
      {
        'action': 'add',
        'timeLabel': timeLabel,
        'offTimeLabel': offTimeLabel,
        'repeatDays': repeatDays,
        'patternName': patternName,
      };

  group('buildScheduleItemsFromIntents — single intent', () {
    test('1-element intents → 1 ScheduleItem with full field mapping', () {
      final items = buildScheduleItemsFromIntents(
        intents: [_intent()],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      expect(items.length, 1);
      final item = items.first;
      expect(item.id, 'ai-$batchTs-0');
      expect(item.timeLabel, 'Sunset');
      expect(item.offTimeLabel, 'Sunrise');
      expect(item.repeatDays, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
      expect(item.actionLabel, 'Pattern: Warm White Wash');
      expect(item.enabled, isTrue);
      expect(item.wledPayload, sharedWled);
      expect(item.sourcePromptId, sharedPromptId);
    });

    test('back-compat: parser-wrapped singular schedulingIntent (now a '
        '1-element list) still yields exactly 1 schedule', () {
      // The cloud parser's normalizeSchedulingIntents wraps a singular
      // schedulingIntent into a 1-element list. The handler downstream
      // shouldn't notice the difference — this is the "singular emission
      // still works end-to-end" invariant.
      final wrappedSingular = [
        _intent(patternName: 'Friday Red', timeLabel: '19:00'),
      ];

      final items = buildScheduleItemsFromIntents(
        intents: wrappedSingular,
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      expect(items.length, 1);
      expect(items.first.actionLabel, 'Pattern: Friday Red');
      expect(items.first.timeLabel, '19:00');
    });
  });

  group('buildScheduleItemsFromIntents — compound batch', () {
    test('2-element intents → 2 items, SAME sourcePromptId, UNIQUE ids', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          _intent(patternName: 'Warm White Wash', timeLabel: 'Sunset'),
          _intent(
            patternName: 'Friday Red',
            timeLabel: '19:00',
            offTimeLabel: null,
            repeatDays: const ['Fri'],
          ),
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      expect(items.length, 2);

      // Shared provenance — every item in this batch carries the same id.
      expect(items[0].sourcePromptId, sharedPromptId);
      expect(items[1].sourcePromptId, sharedPromptId);
      expect(items[0].sourcePromptId, items[1].sourcePromptId);

      // Unique item ids — the indexed suffix prevents collision even
      // when minted in the same millisecond.
      expect(items[0].id, 'ai-$batchTs-0');
      expect(items[1].id, 'ai-$batchTs-1');
      expect(items[0].id, isNot(equals(items[1].id)));

      // Per-item fields preserved independently.
      expect(items[0].actionLabel, 'Pattern: Warm White Wash');
      expect(items[1].actionLabel, 'Pattern: Friday Red');
      expect(items[0].repeatDays.length, 5);
      expect(items[1].repeatDays, ['Fri']);
      expect(items[0].offTimeLabel, 'Sunrise');
      expect(items[1].offTimeLabel, isNull);
    });

    test('every item in a 3-batch carries the shared sourcePromptId', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          _intent(patternName: 'A', timeLabel: '06:00'),
          _intent(patternName: 'B', timeLabel: '12:00'),
          _intent(patternName: 'C', timeLabel: '18:00'),
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      expect(items.length, 3);
      final stamps = items.map((i) => i.sourcePromptId).toSet();
      expect(stamps, {sharedPromptId},
          reason: 'every sibling shares the one provenance stamp');
    });

    test('every item in a batch carries the same wledPayload reference '
        '(Type-A limitation — one blob, N items)', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          _intent(patternName: 'A'),
          _intent(patternName: 'B'),
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      // Documents the known Type-A limitation: one cloud response carries
      // one wled blob; every sibling reuses it. A future per-intent
      // payload schema would change this.
      expect(items[0].wledPayload, sharedWled);
      expect(items[1].wledPayload, sharedWled);
      expect(identical(items[0].wledPayload, items[1].wledPayload), isTrue);
    });
  });

  group('buildScheduleItemsFromIntents — edge cases', () {
    test('empty intents → empty list (no items minted)', () {
      final items = buildScheduleItemsFromIntents(
        intents: const [],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      expect(items, isEmpty);
    });

    test('intent missing timeLabel → defaults to "Sunset"', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          {'patternName': 'Defaulty'},
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );

      expect(items.first.timeLabel, 'Sunset');
    });

    test('intent missing repeatDays → defaults to all 7 days', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          {'patternName': 'Daily', 'timeLabel': '18:00'},
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );

      expect(items.first.repeatDays,
          ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
    });

    test('intent missing patternName → defaults to "Custom"', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          {'timeLabel': '20:00'},
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );

      expect(items.first.actionLabel, 'Pattern: Custom');
    });

    test('null sharedWledPayload → items carry null payload', () {
      final items = buildScheduleItemsFromIntents(
        intents: [_intent(), _intent()],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );

      expect(items.every((i) => i.wledPayload == null), isTrue);
    });
  });
}
