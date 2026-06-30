// test/features/ai/scheduling_intent_prompt_fragment_test.dart
//
// #58 Commit 2 — fragment-equivalence + action-removal guard.
//
// Asserts the scheduling schema description the model is held to is now
// SOURCED from the single static SchedulingIntent.schemaPromptFragment (so the
// producer prompt and the typed parser can never drift), and that the dead
// `action` field was removed from the assembled Smart prompt in every place it
// appeared (the inline master-schema stubs, the schema block, and the worked
// example). Locks both invariants against accidental future drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/lumina_ai/lumina_ai_service.dart';

void main() {
  group('SchedulingIntent.schemaPromptFragment', () {
    const fragment = SchedulingIntent.schemaPromptFragment;

    test('carries the full scheduling schema description, semantically intact',
        () {
      // Section anchors + every modeled field + the compound example survive.
      expect(fragment, contains('═══ SCHEDULING INTENT ═══'));
      expect(fragment, contains('`schedulingIntent` schema:'));
      expect(fragment, contains('"timeLabel": "HH:MM" | "Sunset" | "Sunrise"'));
      expect(fragment,
          contains('"offTimeLabel": "HH:MM" | "Sunset" | "Sunrise" | null'));
      expect(fragment, contains('"repeatDays":'));
      expect(fragment, contains('"patternName": string'));
      expect(fragment, contains('─── COMPOUND SCHEDULES ───'));
      expect(fragment, contains('schedulingIntents'));
      // Worked example, action-free.
      expect(fragment,
          contains('{"timeLabel":"Sunset","offTimeLabel":"Sunrise"'));
      expect(fragment, contains('"patternName":"Friday Red"'));
    });

    test('does NOT mention the removed `action` field (dead contract)', () {
      expect(fragment.contains('"action"'), isFalse,
          reason: 'action field removed from the schema in #58 Commit 2');
      expect(fragment.contains('add" | "replace'), isFalse,
          reason: 'add/replace semantics text removed with the action field');
    });
  });

  group('Smart system prompt assembly', () {
    final smart = LuminaAI.debugSmartSystemPrompt;

    test('embeds the scheduling fragment verbatim (single source of truth)',
        () {
      expect(smart.contains(SchedulingIntent.schemaPromptFragment), isTrue,
          reason:
              'the Smart prompt must be assembled from the fragment so the '
              'producer and the typed parser derive from one source');
    });

    test('contains no `action` token anywhere in the scheduling contract', () {
      // Covers BOTH the dedicated section (via the fragment) AND the inline
      // master-schema stubs (Block A), which were edited in place.
      expect(smart.contains('"action":string'), isFalse,
          reason: 'inline schedulingIntent/schedulingIntents stubs (Block A) '
              'must no longer declare action');
      expect(smart.contains('"action": "add"'), isFalse);
      expect(smart.contains('"action":"add"'), isFalse);
    });

    test('inline master-schema still declares the scheduling keys (action '
        'removal did not drop the keys themselves)', () {
      expect(
          smart.contains(
              '"schedulingIntent":{"timeLabel":string,"offTimeLabel":string|null,'),
          isTrue);
      expect(
          smart.contains(
              '"schedulingIntents":[{"timeLabel":string,"offTimeLabel":string|null,'),
          isTrue);
    });
  });
}
