// Roofline slice 3 follow-up — prompt-parser defect 2, the new-behaviour
// tests: the effect id a prompted motion carries is the one the studio's
// clarification sheet already applies for the same word (a drift guard ties
// the two), a motion word with no entry stays a still picture, and the
// direction answer keeps the id. The defect itself is proven by
// nlu_motion_effect_id_fail_before_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart'
    show motionEffectOf;
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/services/clarification_service.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/services/nlu_service.dart';
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

/// The sheet's effect chips, by option id, and the motion each stands for.
const kSheetChips = <String, MotionType>{
  'chase': MotionType.chase,
  'wave': MotionType.wave,
  'twinkle': MotionType.twinkle,
  'pulse': MotionType.pulse,
  'flow': MotionType.flow,
};

/// What the clarification sheet puts on a layer when the owner taps [chipId].
MotionSettings? _sheetMotionFor(String chipId) {
  const layer = DesignLayer(
    id: 'layer_0',
    name: 'red',
    targetZone: ZoneSelector.all(),
    colors: ColorAssignment.solid(Color(0xFFFF0000)),
  );
  final intent = DesignIntent(
    originalPrompt: 'red',
    layers: const [layer],
    ambiguities: const [
      AmbiguityFlag(
        type: AmbiguityType.effectAmbiguity,
        description: 'Which effect?',
        choices: [],
        affectedLayerId: 'layer_0',
      ),
    ],
    parsedAt: _now,
  );
  final option = ClarificationOption(id: chipId, label: chipId);
  final question = ClarificationQuestion(
    id: 'effect_0',
    type: ClarificationType.effectAmbiguity,
    questionText: 'Which effect?',
    options: [option],
    affectedLayerId: 'layer_0',
  );
  final refined = ClarificationService().applyClarifications(
    original: intent,
    choices: {'effect_0': option},
    questions: [question],
  );
  return refined.layers.single.motion;
}

void main() {
  final orch = DesignStudioOrchestrator();

  group('NLUService.effectIdFor', () {
    test('is the sheet\'s table: chase 28, wave 67, twinkle 80, pulse 2, flow 68', () {
      expect(NLUService.effectIdFor(MotionType.chase), 28);
      expect(NLUService.effectIdFor(MotionType.wave), 67);
      expect(NLUService.effectIdFor(MotionType.twinkle), 80);
      expect(NLUService.effectIdFor(MotionType.pulse), 2);
      expect(NLUService.effectIdFor(MotionType.flow), 68);
    });

    test('scan has no entry in any existing table, nor does "none"', () {
      expect(NLUService.effectIdFor(MotionType.scan), isNull);
      expect(NLUService.effectIdFor(MotionType.none), isNull);
    });

    test('drift guard: a prompted word and the sheet\'s chip agree, chip by chip', () {
      for (final entry in kSheetChips.entries) {
        final fromSheet = _sheetMotionFor(entry.key);
        expect(fromSheet, isNotNull, reason: 'chip ${entry.key}');
        expect(fromSheet!.motionType, entry.value, reason: 'chip ${entry.key}');
        expect(NLUService.effectIdFor(entry.value), fromSheet.effectId,
            reason: 'chip ${entry.key}: the parser and the sheet have drifted apart');
      }
    });

    test('agrees with the model\'s named constructors', () {
      expect(const MotionSettings.chaseLeftToRight().effectId,
          NLUService.effectIdFor(MotionType.chase));
      expect(const MotionSettings.wave(direction: MotionDirection.leftToRight).effectId,
          NLUService.effectIdFor(MotionType.wave));
    });
  });

  group('through the parser', () {
    test('every motion word the parser knows, by type', () async {
      for (final (prompt, type) in [
        ('red chasing inward', MotionType.chase),
        ('red flowing inward', MotionType.chase),
        ('red marching inward', MotionType.chase),
        ('red rippling inward', MotionType.wave),
        ('red rolling inward', MotionType.wave),
        ('red sparkling inward', MotionType.twinkle),
        ('red shimmering inward', MotionType.twinkle),
        ('red throbbing inward', MotionType.pulse),
      ]) {
        final intent = await orch.parseOnly(prompt: prompt, config: _roof());
        final motion = intent.layers.single.motion!;
        expect(motion.motionType, type, reason: prompt);
        expect(motion.effectId, NLUService.effectIdFor(type), reason: prompt);
      }
    });

    test('"scan" stays a still picture: no id, the static branch, reported not guessed',
        () async {
      final intent = await orch.parseOnly(prompt: 'red scan inward', config: _roof());
      final motion = intent.layers.single.motion!;
      expect(motion.motionType, MotionType.scan);
      expect(motion.effectId, isNull);

      final res = await orch.processUserInput(prompt: 'red scan inward', config: _roof());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      expect(res.pattern!.effectId, 0);
      final seg = (res.pattern!.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.every((s) => s['fx'] == 0 && s.containsKey('i')), isTrue);
      expect(motionEffectOf(customDesignFromComposedPattern(
              pattern: res.pattern!, segments: const [], ownerId: 'owner')),
          isNull);
    });

    test('the speed words still apply', () async {
      final fast = await orch.parseOnly(prompt: 'red fast chase inward', config: _roof());
      expect(fast.layers.single.motion!.speed, 200);
      expect(fast.layers.single.motion!.effectId, 28);
      final slow = await orch.parseOnly(prompt: 'red slow wave inward', config: _roof());
      expect(slow.layers.single.motion!.speed, 80);
      expect(slow.layers.single.motion!.effectId, 67);
    });

    test('answering the direction question keeps the id', () async {
      final intent = await orch.parseOnly(prompt: 'red chase', config: _roof());
      final layer = intent.layers.single;
      expect(layer.motion!.effectId, 28);
      final ambiguity = intent.ambiguities
          .firstWhere((a) => a.type == AmbiguityType.directionAmbiguity);
      // The parser leaves affectedLayerId unset; bind the question by hand.
      const option = ClarificationOption(
          id: 'right_to_left', label: 'Right to left', value: MotionDirection.rightToLeft);
      final question = ClarificationQuestion(
        id: 'direction_0',
        type: ClarificationType.directionAmbiguity,
        questionText: ambiguity.description,
        options: const [option],
        affectedLayerId: layer.id,
      );
      final refined = ClarificationService().applyClarifications(
        original: intent.copyWith(
            ambiguities: [AmbiguityFlag(
              type: ambiguity.type,
              description: ambiguity.description,
              choices: ambiguity.choices,
              affectedLayerId: layer.id,
            )]),
        choices: {'direction_0': option},
        questions: [question],
      );
      final motion = refined.layers.single.motion!;
      expect(motion.direction, MotionDirection.rightToLeft);
      expect(motion.effectId, 28);
    });
  });

  group('end to end, both fixes together', () {
    test('the "Chase Effect" quick idea: fx 28 on every bus, saved as a motion', () async {
      final res = await orch.processUserInput(
          prompt: 'Blue chase effect moving left to right', config: _roof());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      final p = res.pattern!;
      expect(p.hasMotion, isTrue);
      expect(p.effectId, 28);
      expect(p.motionDirection, MotionDirection.leftToRight);
      final seg = (p.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['id']), [0, 1]);
      for (final s in seg) {
        expect(s['fx'], 28);
        expect(s['col'], [[0, 0, 255]]);
        expect(s.containsKey('i'), isFalse);
      }
      final saved = customDesignFromComposedPattern(
          pattern: p, segments: const [], ownerId: 'owner');
      expect(motionEffectOf(saved)!.effectId, 28);
    });

    test('a wave, right to left: fx 67 on every bus', () async {
      final res = await orch.processUserInput(
          prompt: 'wave effect right to left', config: _roof());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      expect(res.pattern!.effectId, 67);
      expect(res.pattern!.motionDirection, MotionDirection.rightToLeft);
      final seg = (res.pattern!.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['fx']), [67, 67]);
    });

    test('the placeholder example\'s motion clause is a CHASE (pre-existing, '
        'not changed here): "moving" is a chase word in the motion table and '
        'chase is scanned first', () async {
      final res = await orch.processUserInput(
          prompt: 'wave effect moving right to left', config: _roof());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      expect(res.intent!.layers.single.motion!.motionType, MotionType.chase);
      expect(res.pattern!.effectId, 28, reason: 'runs as a chase, not a still picture');
      expect(res.pattern!.motionDirection, MotionDirection.rightToLeft);
    });
  });
}
