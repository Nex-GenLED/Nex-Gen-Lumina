// test/features/ai/cloud_ai_processor_strip_json_test.dart
//
// Tests for `CloudAIProcessor.stripJsonForDisplay` — the guard that keeps the
// proprietary WLED payload out of the Lumina AI chat bubble.
//
// Lumina's transport returns prose with the WLED JSON appended (or fenced).
// The payload is extracted separately for the apply-to-device path; the
// display text must NEVER carry the raw payload. This previously leaked when a
// malformed payload defeated the JSON extractor and the whole response was
// surfaced verbatim (recommendation + raw JSON in the same bubble).
//
// Pure-function tests — no model call, no Firebase, no Riverpod.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';

void main() {
  group('CloudAIProcessor.stripJsonForDisplay', () {
    // The proprietary payload field names that must never reach the bubble.
    const payloadFieldMarkers = [
      '"patternName"',
      '"wled"',
      '"seg"',
      '"col"',
      '"fx"',
      '"sx"',
      '"ix"',
      '"effect"',
    ];

    void expectNoPayloadLeak(String rendered) {
      expect(rendered.contains('{'), isFalse,
          reason: 'no opening brace of a JSON object should remain');
      expect(rendered.contains('}'), isFalse,
          reason: 'no closing brace of a JSON object should remain');
      for (final marker in payloadFieldMarkers) {
        expect(rendered.contains(marker), isFalse,
            reason: 'payload field $marker must not be displayed');
      }
    }

    test('prose + trailing JSON object → only prose, no payload', () {
      const raw =
          'Here\'s a vibrant purple design for you! '
          '{"patternName":"Purple Haze","thought":"moody","colors":[{"name":"Purple","rgb":[160,32,240,0]}],'
          '"effect":{"name":"Breathe","id":2,"isStatic":false},"speed":80,"intensity":140,'
          '"wled":{"on":true,"bri":255,"seg":[{"id":0,"col":[[160,32,240,0]],"fx":2,"sx":80,"ix":140}]}}';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result, 'Here\'s a vibrant purple design for you!');
      expectNoPayloadLeak(result);
    });

    test('prose + fenced ```json block → only prose, no payload', () {
      const raw = 'Cozy autumn glow coming up!\n'
          '```json\n'
          '{"patternName":"Autumn","wled":{"on":true,"seg":[{"fx":0,"col":[[255,120,0,0]]}]}}\n'
          '```';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result, 'Cozy autumn glow coming up!');
      expectNoPayloadLeak(result);
    });

    test('MALFORMED JSON (trailing comma) still gets scrubbed — this is the '
        'leak path that defeated the parser', () {
      // jsonDecode would throw on this; the old fallback displayed it verbatim.
      const raw = 'Game day red is ready! '
          '{"patternName":"Chiefs Red","wled":{"on":true,"seg":[{"fx":2,},],},}';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result, 'Game day red is ready!');
      expectNoPayloadLeak(result);
    });

    test('prose braces with no quoted key are preserved (not JSON)', () {
      const raw = 'Try a 2:1 ratio {roughly} for the peaks.';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result, 'Try a 2:1 ratio {roughly} for the peaks.');
    });

    test('pure conversational prose passes through unchanged', () {
      const raw =
          "I couldn't find a matching design. Try describing the colors or "
          'mood you\'re looking for.';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result, raw);
    });

    test('braces inside a quoted string value do not break brace matching', () {
      const raw = 'Done! '
          '{"patternName":"Curly {brace} name","wled":{"on":true}} Enjoy!';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result, 'Done! Enjoy!');
      expectNoPayloadLeak(result);
    });

    test('two JSON objects in one response are both removed', () {
      const raw = 'Sure thing. '
          '{"patternName":"A","wled":{"on":true}} '
          'and also {"patternName":"B","wled":{"on":false}}';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result.contains('Sure thing.'), isTrue);
      expect(result.contains('and also'), isTrue);
      expectNoPayloadLeak(result);
    });

    test('response that is ONLY a payload collapses to empty (caller '
        'substitutes a friendly fallback)', () {
      const raw =
          '{"patternName":"X","wled":{"on":true,"seg":[{"fx":0}]}}';

      final result = CloudAIProcessor.stripJsonForDisplay(raw);

      expect(result, isEmpty);
      expectNoPayloadLeak(result);
    });
  });
}
