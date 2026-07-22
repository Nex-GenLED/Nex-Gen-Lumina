// test/features/ai/cloud_ai_processor_normalize_test.dart
//
// Parser tests for `CloudAIProcessor.normalizeSchedulingIntents` — the
// canonicalizer that collapses the cloud schema's TWO scheduling shapes
// (`schedulingIntent` singular + `schedulingIntents` array, Item #51
// compound-schedule support) into a single List<Map> the handler reads.
//
// Pure-function tests with fixture maps. No model call, no Firebase, no
// Riverpod. The helper is exposed for tests via `@visibleForTesting`;
// the rest of the file remains private.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';

void main() {
  group('CloudAIProcessor.normalizeSchedulingIntents', () {
    Map<String, dynamic> _intent(String patternName, String timeLabel) => {
          'action': 'add',
          'timeLabel': timeLabel,
          'offTimeLabel': null,
          'repeatDays': const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          'patternName': patternName,
        };

    test('schedulingIntents array of 2 → list of 2 in canonical form', () {
      final obj = {
        'schedulingIntents': [
          _intent('Warm White Wash', 'Sunset'),
          _intent('Friday Red', '19:00'),
        ],
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNotNull);
      expect(result, isA<List<SchedulingIntent>>());
      expect(result!.length, 2);
      expect(result[0].patternName, 'Warm White Wash');
      expect(result[1].patternName, 'Friday Red');
    });

    test('singular schedulingIntent map → wrapped as one-element list', () {
      final obj = {
        'schedulingIntent': _intent('Warm White Wash', 'Sunset'),
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result.first.patternName, 'Warm White Wash');
    });

    test('neither field present → null (key omitted from bag downstream)',
        () {
      final obj = <String, dynamic>{
        'message': 'Just a design, no schedule.',
        'wled': {'on': true},
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNull);
    });

    test('both fields null → null', () {
      final obj = <String, dynamic>{
        'schedulingIntents': null,
        'schedulingIntent': null,
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNull);
    });

    test('schedulingIntents present but not a List → falls through to '
        'singular path', () {
      final obj = {
        // Model occasionally emits a bare false / "none" / object instead
        // of an array. Defensive: the singular fallback should still be
        // consulted in that case.
        'schedulingIntents': false,
        'schedulingIntent': _intent('Warm White Wash', 'Sunset'),
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNotNull);
      expect(result!.length, 1,
          reason: 'non-List schedulingIntents is ignored; '
              'singular schedulingIntent is used');
      expect(result.first.patternName, 'Warm White Wash');
    });

    test('schedulingIntents with malformed entries → non-Map entries dropped',
        () {
      final obj = {
        'schedulingIntents': [
          _intent('Good 1', '18:00'),
          'this is a string, not a schedule object',
          _intent('Good 2', '21:00'),
          42, // numeric junk
          null,
        ],
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNotNull);
      expect(result!.length, 2,
          reason: 'only the two valid Map entries survive');
      expect(result.map((m) => m.patternName).toList(),
          ['Good 1', 'Good 2']);
    });

    test('schedulingIntents array of all malformed entries → null', () {
      final obj = {
        'schedulingIntents': [
          'string',
          42,
          null,
          true,
        ],
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNull,
          reason: 'empty post-filter list is collapsed to null so the bag '
              "doesn't carry an empty key");
    });

    test('schedulingIntents array — empty list literal → null', () {
      final obj = {
        'schedulingIntents': <dynamic>[],
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNull);
    });

    test('schedulingIntents array takes precedence over singular when both '
        'present', () {
      // The prompt forbids the model from emitting both. If it ever does
      // (defensive), the array wins because it's the more expressive form.
      final obj = {
        'schedulingIntents': [_intent('From Array', 'Sunset')],
        'schedulingIntent': _intent('From Singular', '20:00'),
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result.first.patternName, 'From Array');
    });

    test('typed coercion: singular Map → one-element typed list, fields '
        'parsed', () {
      // Confirms the singular→one-element coercion AND the typed defaulting
      // survive the #58 typing change in one assertion.
      final obj = {
        'schedulingIntent': {
          'action': 'add',
          'timeLabel': '19:00',
          'offTimeLabel': null,
          'repeatDays': const ['Fri'],
          'patternName': 'Friday Red',
        },
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isA<List<SchedulingIntent>>());
      expect(result!.length, 1);
      final intent = result.first;
      expect(intent.patternName, 'Friday Red');
      expect(intent.timeLabel, '19:00');
      expect(intent.offTimeLabel, isNull);
      expect(intent.repeatDays, ['Fri']);
      // `action` was removed from the contract in #58 Commit 2; a model that
      // still emits it is tolerated (extra key ignored), not parsed.
    });

    test('typed coercion: garbage field values in a well-formed Map entry → '
        'defaults, no throw', () {
      // Entry IS a Map (passes the entry-level filter) but its fields are
      // garbage scalars. fromJson must coerce to defaults rather than throw,
      // preserving the normalizer\'s never-throws contract.
      final obj = {
        'schedulingIntents': [
          {
            'timeLabel': 42, // non-String → default 'Sunset'
            'offTimeLabel': 7, // non-String → null
            'repeatDays': 'not-a-list', // non-List → all 7 days
            'patternName': true, // non-String → 'Custom'
            'wled': 'nope', // non-Map → null
          },
        ],
      };

      final result = CloudAIProcessor.normalizeSchedulingIntents(obj);

      expect(result, isNotNull);
      expect(result!.length, 1);
      final intent = result.first;
      expect(intent.timeLabel, 'Sunset');
      expect(intent.offTimeLabel, isNull);
      expect(intent.repeatDays,
          ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
      expect(intent.patternName, 'Custom');
      expect(intent.wled, isNull);
    });
  });
}
