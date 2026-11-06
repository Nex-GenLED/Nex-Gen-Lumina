// Roofline slice 3 follow-up — prompt-parser defect 2, the fail-before test.
//
// TODAY the parser's motion carries no WLED effect id. The composer reads a
// missing id as 0, 0 as "no effect", and emits the still-picture `i`
// payload; the stored composed_pattern says has_motion: true, effect_id: 0;
// and motionEffectOf() reads that as static. Only the model's two named
// constructors (chaseLeftToRight 28, wave 67) and the clarification sheet's
// effect choice (chase 28, wave 67, twinkle 80, pulse 2, flow 68) ever set
// one — so a prompted "chase" and a chosen "Chase" chip behave differently.
//
// The prompts avoid "left"/"right" so defect 1 (direction read as a
// location) cannot mask this one. Against the unchanged parser every test
// here fails.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart'
    show motionEffectOf;
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 11, 6);

RooflineConfiguration _threeBuses() => RooflineConfiguration(
      id: 'ctl-a',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 3,
      segments: const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 162, channelIndex: 0),
        RooflineSegment(id: 'b', name: 'Side run', pixelCount: 128, channelIndex: 1),
        RooflineSegment(id: 'c', name: 'Garage run', pixelCount: 100, channelIndex: 2),
      ],
    ).withChannelPixelCounts(const {0: 162, 1: 128, 2: 100});

void main() {
  final orch = DesignStudioOrchestrator();

  group('a prompted motion carries the effect id the studio already uses', () {
    for (final (prompt, type, fx) in [
      ('red chase inward', MotionType.chase, 28),
      ('red wave outward', MotionType.wave, 67),
      ('red twinkle inward', MotionType.twinkle, 80),
      ('red breathe inward', MotionType.pulse, 2),
    ]) {
      test('"$prompt" → ${type.name}, fx $fx', () async {
        final intent = await orch.parseOnly(prompt: prompt, config: _threeBuses());
        final motion = intent.layers.single.motion;
        expect(motion, isNotNull, reason: 'no motion parsed');
        expect(motion!.motionType, type);
        expect(motion.effectId, fx, reason: 'effectId was ${motion.effectId}');
      });
    }
  });

  group('…and it reaches the composer and the saved design', () {
    test('the effect branch: fx on every bus, no i array', () async {
      final res = await orch.processUserInput(prompt: 'red chase inward', config: _threeBuses());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      final p = res.pattern!;
      expect(p.hasMotion, isTrue);
      expect(p.effectId, 28, reason: 'was ${p.effectId}: the static branch');
      final seg = (p.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['id']), [0, 1, 2]);
      for (final s in seg) {
        expect(s['fx'], 28, reason: 'seg ${s['id']}');
        expect(s.containsKey('i'), isFalse, reason: 'a still picture was emitted');
      }
    });

    test('motionEffectOf() reads the saved design as a motion', () async {
      final res = await orch.processUserInput(prompt: 'red chase inward', config: _threeBuses());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      final design = customDesignFromComposedPattern(
          pattern: res.pattern!, segments: const [], ownerId: 'owner');
      final motion = motionEffectOf(design);
      expect(motion, isNotNull,
          reason: 'stored has_motion: true with effect_id 0 — read as static');
      expect(motion!.effectId, 28);
      expect(motion.speed, 128);
    });
  });
}
