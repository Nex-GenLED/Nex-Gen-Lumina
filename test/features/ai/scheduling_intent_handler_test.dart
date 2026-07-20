// test/features/ai/scheduling_intent_handler_test.dart
//
// Pure-function tests for the compound schedule dispatcher (Item #51
// Type-A). Two helpers exposed via @visibleForTesting:
//   • buildScheduleItemsFromIntents — item construction (ids,
//     sourcePromptId, field defaulting, per-element vs shared wled)
//   • classifyIntents — honesty guard that drops "lying" intents
//     (distinct patternName + no per-element wled) so the user never
//     sees a sibling labeled "Friday Red" running a warm-white payload
// Exercises both helpers without standing up Riverpod, ScaffoldMessenger,
// or Firebase Auth.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
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

  // Build a typed intent from the same raw map shape the cloud parser feeds
  // through SchedulingIntent.fromJson. The #58 typing change moved the field
  // defaulting/coercion into fromJson, so tests exercise the real parse path
  // rather than hand-constructing the typed object.
  SchedulingIntent _intent({
    String patternName = 'Warm White Wash',
    String timeLabel = 'Sunset',
    String? offTimeLabel = 'Sunrise',
    List<String> repeatDays = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
    Map<String, dynamic>? wled,
  }) =>
      SchedulingIntent.fromJson({
        'action': 'add',
        'timeLabel': timeLabel,
        'offTimeLabel': offTimeLabel,
        'repeatDays': repeatDays,
        'patternName': patternName,
        if (wled != null) 'wled': wled,
      });

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

    test('intents without per-element wled → all items reuse the shared '
        'top-level payload', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          _intent(patternName: 'A'),
          _intent(patternName: 'B'),
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      // When no per-element wled is provided, siblings fall back to the
      // top-level payload — by design, not a limitation. (The honesty
      // guard upstream ensures this fallback only happens when the
      // intent's patternName matches the top-level, so labels stay
      // honest.)
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

    test('intent missing timeLabel → REFUSED, never fabricated (was: silent '
        '"Sunset" default → hour:25 timer that never fires)', () {
      final intent = SchedulingIntent.fromJson({'patternName': 'Defaulty'});
      expect(intent.timeUnresolved, isTrue,
          reason: 'a missing time must not be invented');
      expect(intent.timeLabel, isEmpty);

      final items = buildScheduleItemsFromIntents(
        intents: [intent],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );

      expect(items, isEmpty,
          reason: 'a timeless intent must never be built into a schedule');
    });

    test('non-string timeLabel (model junk) → also refused', () {
      final intent =
          SchedulingIntent.fromJson({'patternName': 'Junk', 'timeLabel': 25});
      expect(intent.timeUnresolved, isTrue);
      final items = buildScheduleItemsFromIntents(
        intents: [intent],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );
      expect(items, isEmpty);
    });

    test('genuine clock time "1:20 PM" → resolved, stored verbatim', () {
      final intent = SchedulingIntent.fromJson(
          {'patternName': 'Warm White', 'timeLabel': '1:20 PM'});
      expect(intent.timeUnresolved, isFalse);
      final items = buildScheduleItemsFromIntents(
        intents: [intent],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );
      expect(items.single.timeLabel, '1:20 PM');
    });

    test('genuine solar "Sunset"→"Sunrise" → still stored (solar creation '
        'path preserved; whether it FIRES is a separate finding)', () {
      final intent = SchedulingIntent.fromJson({
        'patternName': 'Warm White',
        'timeLabel': 'Sunset',
        'offTimeLabel': 'Sunrise',
      });
      expect(intent.timeUnresolved, isFalse);
      final items = buildScheduleItemsFromIntents(
        intents: [intent],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: null,
      );
      expect(items.single.timeLabel, 'Sunset');
      expect(items.single.offTimeLabel, 'Sunrise');
    });

    test('intent missing repeatDays → defaults to all 7 days', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          SchedulingIntent.fromJson(
              {'patternName': 'Daily', 'timeLabel': '18:00'}),
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
          SchedulingIntent.fromJson({'timeLabel': '20:00'}),
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

  // ── Per-element wled (Item #51 Type-A full) ────────────────────────────
  // Two distinct designs in one compound prompt: each intent carries its
  // own `wled` Map, and buildScheduleItemsFromIntents prefers the
  // per-element payload over the shared top-level one.
  group('buildScheduleItemsFromIntents — per-element wled', () {
    const redWled = <String, dynamic>{
      'on': true,
      'bri': 255,
      'seg': [
        {
          'fx': 0,
          'col': [
            [255, 0, 0, 0],
          ],
        },
      ],
    };

    test('two intents with distinct per-element wled → items get '
        'DIFFERENT payloads, shared sourcePromptId', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          _intent(patternName: 'Warm White Wash'),
          SchedulingIntent.fromJson({
            'action': 'add',
            'timeLabel': '19:00',
            'offTimeLabel': null,
            'repeatDays': ['Fri'],
            'patternName': 'Friday Red',
            'wled': redWled,
          }),
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      expect(items.length, 2);
      // Sibling 0 had no per-element wled → falls back to the top-level
      // warm-white payload.
      expect(items[0].wledPayload, sharedWled);
      // Sibling 1 had its own wled → carries the red payload, NOT the
      // shared one.
      expect(items[1].wledPayload, isNot(equals(sharedWled)));
      expect(
          (items[1].wledPayload!['seg'] as List).first['col'].first.first, 255);
      // Provenance stamp still shared across the batch.
      expect(items[0].sourcePromptId, items[1].sourcePromptId);
    });

    test('per-element wled is copied (not aliased) so callers can mutate '
        'their input without affecting persisted items', () {
      final mutableRed = {
        'on': true,
        'seg': [
          {'fx': 0},
        ],
      };
      final intent = SchedulingIntent.fromJson({
        'patternName': 'Red',
        'timeLabel': '19:00',
        'wled': mutableRed,
      });
      final items = buildScheduleItemsFromIntents(
        intents: [intent],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      // Defensive copy: mutating the source map after parsing must not
      // mutate the item's stored payload (fromJson copies wled at parse time).
      mutableRed['on'] = false;
      expect(items.first.wledPayload!['on'], isTrue);
    });

    test('intent with non-Map wled value → silently falls back to '
        'shared payload (defensive)', () {
      final items = buildScheduleItemsFromIntents(
        intents: [
          SchedulingIntent.fromJson({
            'patternName': 'Warm White Wash',
            'timeLabel': 'Sunset',
            'wled': 'not-a-map', // model junk
          }),
        ],
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );

      expect(items.first.wledPayload, sharedWled);
    });
  });

  // ── Honesty guard (classifyIntents) ────────────────────────────────────
  // The guard partitions intents into the slice safe to schedule (`kept`)
  // vs the names of dropped "lying" siblings (distinct patternName + no
  // per-element wled → would attach the wrong design under a truthful
  // label). Surfaces dropped names to the user via the post-add chat
  // message; never silently drops.
  group('classifyIntents — honesty guard', () {
    const friRed = <String, dynamic>{
      'on': true,
      'seg': [
        {'fx': 0, 'col': [[255, 0, 0, 0]]}
      ],
    };

    test('same patternName as top-level → kept (legit reuse)', () {
      final result = classifyIntents(
        intents: [_intent(patternName: 'Warm White Wash')],
        topLevelPatternName: 'Warm White Wash',
      );
      expect(result.kept.length, 1);
      expect(result.droppedNames, isEmpty);
    });

    test('distinct patternName WITH per-element wled → kept (legit '
        'distinct design)', () {
      final result = classifyIntents(
        intents: [
          SchedulingIntent.fromJson({
            'patternName': 'Friday Red',
            'timeLabel': '19:00',
            'wled': friRed,
          }),
        ],
        topLevelPatternName: 'Warm White Wash',
      );
      expect(result.kept.length, 1);
      expect(result.droppedNames, isEmpty);
    });

    test('two intents: distinct patternName, NO per-element wled → '
        'guard drops the distinct one, names it', () {
      final result = classifyIntents(
        intents: [
          _intent(patternName: 'Warm White Wash'),
          // Distinct name, no own wled → would lie about the design.
          SchedulingIntent.fromJson({
            'patternName': 'Friday Red',
            'timeLabel': '19:00',
          }),
        ],
        topLevelPatternName: 'Warm White Wash',
      );
      expect(result.kept.length, 1);
      expect(result.kept.first.patternName, 'Warm White Wash');
      expect(result.droppedNames, ['Friday Red']);
    });

    test('all ambiguous → fallback keeps intents[0], drops the rest by '
        'name', () {
      // Pathological: model produced 3 distinct names but no per-element
      // payloads, AND none matches the top-level. The fallback rule
      // schedules the first one (the user gets *something*) and surfaces
      // the rest as dropped.
      final result = classifyIntents(
        intents: [
          SchedulingIntent.fromJson({'patternName': 'Alpha', 'timeLabel': '06:00'}),
          SchedulingIntent.fromJson({'patternName': 'Bravo', 'timeLabel': '12:00'}),
          SchedulingIntent.fromJson(
              {'patternName': 'Charlie', 'timeLabel': '18:00'}),
        ],
        topLevelPatternName: 'Original Design',
      );
      expect(result.kept.length, 1);
      expect(result.kept.first.patternName, 'Alpha');
      expect(result.droppedNames, ['Bravo', 'Charlie'],
          reason: 'first becomes kept; rest stay dropped — never zero kept');
    });

    test('case-insensitive name match against top-level', () {
      final result = classifyIntents(
        intents: [
          _intent(patternName: 'WARM WHITE WASH'),
          _intent(patternName: '  warm white wash  '), // whitespace
        ],
        topLevelPatternName: 'Warm White Wash',
      );
      expect(result.kept.length, 2);
      expect(result.droppedNames, isEmpty);
    });

    test('topLevelPatternName null → only intents with their own wled '
        'are kept', () {
      // No top-level patternName to reuse. The only honest path is per-
      // element wled. An intent without one falls into the pathological
      // fallback if it's the only intent.
      final resultWithOwnWled = classifyIntents(
        intents: [
          SchedulingIntent.fromJson({'patternName': 'X', 'wled': friRed}),
        ],
        topLevelPatternName: null,
      );
      expect(resultWithOwnWled.kept.length, 1);
      expect(resultWithOwnWled.droppedNames, isEmpty);

      final resultWithoutOwnWled = classifyIntents(
        intents: [
          SchedulingIntent.fromJson({'patternName': 'X'}),
          SchedulingIntent.fromJson({'patternName': 'Y'}),
        ],
        topLevelPatternName: null,
      );
      // Both ambiguous → fallback keeps intents[0], drops the rest.
      expect(resultWithoutOwnWled.kept.length, 1);
      expect(resultWithoutOwnWled.kept.first.patternName, 'X');
      expect(resultWithoutOwnWled.droppedNames, ['Y']);
    });

    test('empty intents → empty kept, empty dropped', () {
      final result = classifyIntents(
        intents: const [],
        topLevelPatternName: 'Anything',
      );
      expect(result.kept, isEmpty);
      expect(result.droppedNames, isEmpty);
    });
  });

  // ── Back-compat regression (singular wrapped to 1-element list) ─────────
  group('back-compat — parser-wrapped singular still works', () {
    test('1 intent matching top-level name → kept, scheduled as 1 item', () {
      // The cloud parser normalizes a singular `schedulingIntent` into
      // a 1-element list. The model sets patternName equal to the
      // top-level — so the guard keeps it.
      final classification = classifyIntents(
        intents: [_intent(patternName: 'Warm White Wash')],
        topLevelPatternName: 'Warm White Wash',
      );
      final items = buildScheduleItemsFromIntents(
        intents: classification.kept,
        sourcePromptId: sharedPromptId,
        batchTs: batchTs,
        sharedWledPayload: sharedWled,
      );
      expect(items.length, 1);
      expect(items.first.actionLabel, 'Pattern: Warm White Wash');
      expect(items.first.wledPayload, sharedWled);
    });
  });
}
