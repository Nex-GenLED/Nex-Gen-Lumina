// Roofline slice 3 follow-up — prompt-parser quirk 3, the fail-before test:
// effect-word precedence.
//
// TODAY the motion-type scan takes the first vocabulary list, in table
// order (chase, wave, twinkle, pulse, scan), with ANY word present in the
// clause. The chase list carries the generic motion words "moving", "move",
// "run", "running", "traveling", "travel", so a clause that names an effect
// and also says it moves — the studio placeholder's own "wave effect moving
// right to left" — is a chase. And the wave list carries "pulse", "pulsing"
// and "breathing", so a prompted pulse is a wave (fx 67), not the pulse the
// clarification sheet's chip gives (fx 2).
//
// Against the unchanged parser the first group fails; the controls (a
// generic motion word alone, or an effect word with no generic word) pass
// and must keep passing: that behaviour is unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 11, 6);

RooflineConfiguration _roof() => RooflineConfiguration(
      id: 'ctl-a',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 2,
      segments: const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 100, channelIndex: 0),
        RooflineSegment(id: 'b', name: 'Garage run', pixelCount: 100, channelIndex: 1),
      ],
    ).withChannelPixelCounts(const {0: 100, 1: 100});

void main() {
  final orch = DesignStudioOrchestrator();

  group('an explicit effect word decides the effect', () {
    for (final (prompt, type, fx) in [
      // The studio placeholder's own wording.
      ('wave effect moving right to left', MotionType.wave, 67),
      ('red pulse inward', MotionType.pulse, 2),
      ('red pulsing inward', MotionType.pulse, 2),
      ('red breathing inward', MotionType.pulse, 2),
      ('red wave moving inward', MotionType.wave, 67),
      ('red twinkle running inward', MotionType.twinkle, 80),
    ]) {
      test('"$prompt" → ${type.name}, fx $fx', () async {
        final intent = await orch.parseOnly(prompt: prompt, config: _roof());
        final motion = intent.layers.single.motion;
        expect(motion, isNotNull, reason: 'no motion parsed');
        expect(motion!.motionType, type, reason: 'was ${motion.motionType.name}');
        expect(motion.effectId, fx, reason: 'was ${motion.effectId}');
      });
    }

    test('the placeholder wording composes a wave moving right to left, on every bus',
        () async {
      final res = await orch.processUserInput(
          prompt: 'wave effect moving right to left', config: _roof());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      expect(res.pattern!.effectId, 67, reason: 'was ${res.pattern!.effectId}');
      expect(res.pattern!.motionDirection, MotionDirection.rightToLeft);
      final seg = (res.pattern!.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['fx']), [67, 67]);
    });
  });

  group('controls — unchanged', () {
    for (final (prompt, type, fx) in <(String, MotionType, int?)>[
      // A generic motion word alone is a chase, as before.
      ('red moving right', MotionType.chase, 28),
      ('red running left', MotionType.chase, 28),
      ('red traveling inward', MotionType.chase, 28),
      ('red moving inward', MotionType.chase, 28),
      // An effect word with no generic word, as before.
      ('red chase inward', MotionType.chase, 28),
      ('red flowing inward', MotionType.chase, 28),
      ('red marching inward', MotionType.chase, 28),
      ('red rippling inward', MotionType.wave, 67),
      ('red sparkling inward', MotionType.twinkle, 80),
      ('red throbbing inward', MotionType.pulse, 2),
      ('red sweeping inward', MotionType.scan, null),
    ]) {
      test('"$prompt" → ${type.name}, fx ${fx ?? 'none'}', () async {
        final intent = await orch.parseOnly(prompt: prompt, config: _roof());
        final motion = intent.layers.single.motion!;
        expect(motion.motionType, type);
        expect(motion.effectId, fx);
      });
    }

    test('no motion word, no motion', () async {
      final intent = await orch.parseOnly(prompt: 'red on the whole house', config: _roof());
      expect(intent.layers.single.motion, isNull);
    });
  });
}
