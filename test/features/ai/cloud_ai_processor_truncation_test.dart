// test/features/ai/cloud_ai_processor_truncation_test.dart
//
// Truncation safety net — parser-layer proof.
//
// This is the leak/drop surface: when a reply's JSON is unbalanced/cut off,
// the OLD parser leaked the raw payload into the chat bubble AND created no
// schedule silently (parsed==null returned a plain success). These tests force
// that condition at the parser and assert the three invariants the submission
// gate requires:
//   1. NO raw JSON reaches the bubble (responseText has no braces / payload
//      field names).
//   2. NO phantom schedule (wledPayload is null → nothing for the screen to
//      dispatch as a schedule).
//   3. A parse FAILURE is not dressed up as a clean success ("Done.").
//
// Genuine stop_reason==max_tokens is caught upstream as
// LuminaResponseTruncatedException (Layer 1) and surfaces its own friendly
// message; this file proves Layer 3's defense-in-depth for malformed bodies
// that reach the parser, plus the happy-path regressions.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';

void main() {
  group('CloudAIProcessor parser — truncation containment (Layer 3)', () {
    const payloadMarkers = [
      '"patternName"', '"wled"', '"seg"', '"col"', '"fx"', '"schedulingIntents"',
    ];

    void expectNoRawJson(String text) {
      expect(text.contains('{'), isFalse, reason: 'no JSON opening brace');
      expect(text.contains('}'), isFalse, reason: 'no JSON closing brace');
      for (final m in payloadMarkers) {
        expect(text.contains(m), isFalse, reason: '$m must not be displayed');
      }
    }

    test('FORCED TRUNCATION: prose + cut-off unbalanced payload → no raw JSON, '
        'no schedule, not a phantom success', () {
      // A verbose schedule reply truncated mid-object (unbalanced braces).
      const truncated = 'Here is your holiday plan across the season! '
          '{"patternName":"Holiday Lights","message":"All set",'
          '"schedulingIntents":[{"timeLabel":"Sunset","offTimeLabel":"Sunrise",'
          '"repeatDays":["Mon","Tue","Wed"],"wled":{"on":true,"bri":255,'
          '"seg":[{"fx":2,"col":[[255,0';

      final result = CloudAIProcessor.parseAiResponseForTest(truncated, 'plan');

      // (1) No raw JSON in the bubble.
      expectNoRawJson(result.responseText);
      // (2) No phantom schedule — nothing for the screen to dispatch.
      expect(result.wledPayload, isNull);
      expect(result.recurringSportsAutopilotIntent, isNull);
      expect(result.ephemeralSessionIntent, isNull);
      // (3) Prose survived; it reads as a real message, not a leak.
      expect(result.responseText, 'Here is your holiday plan across the season!');
    });

    test('FORCED TRUNCATION: payload-only cut-off reply → friendly retry '
        'message, NOT the success-toned "Done."', () {
      // Nothing but a cut-off payload. Old behavior: scrub empties it → showed
      // "Done." (false success). Now: parse-failure → honest retry message.
      const truncated =
          '{"patternName":"X","wled":{"on":true,"seg":[{"fx":2,"col":[[10,20';

      final result = CloudAIProcessor.parseAiResponseForTest(truncated, 'x');

      expectNoRawJson(result.responseText);
      expect(result.wledPayload, isNull);
      expect(result.responseText, isNot('Done.'));
      expect(result.responseText, contains('cleanly'));
    });

    test('REGRESSION: clean conversational reply (no JSON) passes through', () {
      const clean =
          "I couldn't find a matching design. Try describing the colors "
          "or mood you're looking for.";

      final result = CloudAIProcessor.parseAiResponseForTest(clean, 'huh');

      expect(result.responseText, clean);
      expect(result.wledPayload, isNull);
    });

    test('REGRESSION: clean reply with empty scrub still allowed to say '
        '"Done." (no JSON attempt present)', () {
      // No brace at all → not a parse failure → "Done." fallback is legitimate.
      final result = CloudAIProcessor.parseAiResponseForTest('   ', 'noop');
      expect(result.responseText, 'Done.');
      expect(result.wledPayload, isNull);
    });

    test('REGRESSION: valid full JSON payload still parses + yields wled', () {
      const ok = 'Warm white evening, coming up! '
          '{"patternName":"Warm White","wled":{"on":true,"bri":180,'
          '"seg":[{"fx":0,"col":[[255,180,40,0]]}]}}';

      final result = CloudAIProcessor.parseAiResponseForTest(ok, 'warm white');

      expect(result.wledPayload, isNotNull);
      expect(result.wledPayload!['on'], true);
      expectNoRawJson(result.responseText);
      expect(result.responseText, 'Warm white evening, coming up!');
    });

    test('REGRESSION: valid JSON with schedulingIntents still dispatches '
        '(intents survive on wledPayload)', () {
      const ok = 'Scheduled! '
          '{"patternName":"Warm White","wled":{"on":true,'
          '"seg":[{"fx":0,"col":[[255,180,40,0]]}]},'
          '"schedulingIntent":{"action":"add","timeLabel":"Sunset",'
          '"offTimeLabel":"Sunrise","repeatDays":["Fri"],'
          '"patternName":"Warm White"}}';

      final result = CloudAIProcessor.parseAiResponseForTest(ok, 'every friday');

      expect(result.wledPayload, isNotNull);
      final intents = result.wledPayload!['schedulingIntents'];
      expect(intents, isA<List>());
      expect((intents as List).length, 1);
    });
  });
}
