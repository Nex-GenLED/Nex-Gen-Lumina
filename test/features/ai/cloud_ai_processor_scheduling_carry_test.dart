// test/features/ai/cloud_ai_processor_scheduling_carry_test.dart
//
// #58b — proves scheduling intents are carried on the TYPED
// LuminaCommandResult.schedulingIntents field independent of wledPayload, so
// they survive a null/absent top-level `wled` (the prompt's EPHEMERAL
// Example C shape) instead of being silently dropped.
//
// Pure parser tests via the parseAiResponseForTest seam — no Firebase, no
// Riverpod, no widget harness. The carry is the entire fix surface; dispatch
// only checks presence of the typed field.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';

void main() {
  group('CloudAIProcessor scheduling-intent carry (#58b)', () {
    test('Example C: wled:null + schedulingIntent → intents carried on the '
        'typed field, wledPayload stays null', () {
      // The exact shape the Smart prompt's EPHEMERAL Example C tells the model
      // to emit for a clock-time schedule with no immediate design.
      const response = 'Got it. '
          '{"message":"Warm white at 11pm.","wled":null,'
          '"schedulingIntent":{"timeLabel":"23:00","offTimeLabel":null,'
          '"repeatDays":[],"patternName":"Warm White"}}';

      final result =
          CloudAIProcessor.parseAiResponseForTest(response, 'warm white at 11pm');

      // Pre-#58b this was null (intents dropped because wled was null).
      expect(result.schedulingIntents, isNotNull);
      expect(result.schedulingIntents!.length, 1);
      expect(result.schedulingIntents!.single.timeLabel, '23:00');
      expect(result.schedulingIntents!.single.patternName, 'Warm White');
      expect(result.hasSchedulingIntents, isTrue);

      // No top-level design was emitted — honesty preserved, no synthesized
      // junk payload. sharedWledPayload downstream stays null.
      expect(result.wledPayload, isNull);
    });

    test('REGRESSION: wled-present still carries intents on the typed field '
        'AND keeps the in-wled mirror (:193 retained)', () {
      const response = 'Scheduled! '
          '{"patternName":"Warm White","wled":{"on":true,'
          '"seg":[{"fx":0,"col":[[255,180,40,0]]}]},'
          '"schedulingIntent":{"timeLabel":"Sunset","offTimeLabel":"Sunrise",'
          '"repeatDays":["Fri"],"patternName":"Warm White"}}';

      final result =
          CloudAIProcessor.parseAiResponseForTest(response, 'every friday');

      // Typed carrier (what dispatch now reads).
      expect(result.schedulingIntents, isNotNull);
      expect(result.schedulingIntents!.length, 1);
      expect(result.schedulingIntents!.single.timeLabel, 'Sunset');

      // Working-case wled is unchanged and still carries the redundant mirror
      // at the attach junction — byte-compat with the existing truncation
      // test, which asserts wledPayload['schedulingIntents'].
      expect(result.wledPayload, isNotNull);
      expect(result.wledPayload!['on'], true);
      final mirror = result.wledPayload!['schedulingIntents'];
      expect(mirror, isA<List>());
      expect((mirror as List).length, 1);
      expect(mirror.whereType<SchedulingIntent>().length, 1,
          reason: 'mirror holds the SAME typed objects as the carrier');
    });

    test('no scheduling intent in response → typed field null', () {
      const response = 'Here you go. '
          '{"patternName":"Warm White","wled":{"on":true,'
          '"seg":[{"fx":0,"col":[[255,180,40,0]]}]}}';

      final result =
          CloudAIProcessor.parseAiResponseForTest(response, 'warm white');

      expect(result.schedulingIntents, isNull);
      expect(result.hasSchedulingIntents, isFalse);
    });
  });
}
