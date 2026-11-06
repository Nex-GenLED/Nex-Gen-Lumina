// Roofline slice 3 follow-up — prompt-parser quirk 4, the new-behaviour
// tests: every clause-level ambiguity the parser raises names its layer, so
// the clarification sheet's answer lands on that layer and no other. The
// defect itself is proven by nlu_clarification_answer_lands_fail_before_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart'
    show RooflineSegment, SegmentType;

final _now = DateTime(2026, 11, 6);

/// Two buses of 100 with a marked peak on bus 1 and a marked corner on bus 2.
RooflineConfiguration _roof() => RooflineConfiguration(
      id: 'ctl-a',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 2,
      segments: const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 90, channelIndex: 0),
        RooflineSegment(id: 'p', name: 'Front peak', pixelCount: 10, startPixel: 90,
            channelIndex: 0, type: SegmentType.peak),
        RooflineSegment(id: 'b', name: 'Side run', pixelCount: 90, channelIndex: 1),
        RooflineSegment(id: 'c', name: 'Side corner', pixelCount: 10, startPixel: 90,
            channelIndex: 1, type: SegmentType.corner),
      ],
    ).withChannelPixelCounts(const {0: 100, 1: 100});

/// One bus with six marked peaks, for the "many peaks" zone question.
RooflineConfiguration _manyPeaks() => RooflineConfiguration(
      id: 'ctl-b',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 1,
      segments: [
        for (var i = 0; i < 6; i++)
          RooflineSegment(
              id: 'p$i', name: 'Peak ${i + 1}', pixelCount: 10, startPixel: i * 20,
              type: SegmentType.peak),
        for (var i = 0; i < 6; i++)
          RooflineSegment(
              id: 'r$i', name: 'Run ${i + 1}', pixelCount: 10, startPixel: i * 20 + 10),
      ],
    ).withChannelPixelCounts(const {0: 120});

void main() {
  final orch = DesignStudioOrchestrator();

  group('every clause-level ambiguity names its layer', () {
    test('the direction question', () async {
      final intent = await orch.parseOnly(prompt: 'red chase', config: _roof());
      final a = intent.ambiguities.single;
      expect(a.type, AmbiguityType.directionAmbiguity);
      expect(a.affectedLayerId, 'layer_0');
      expect(a.sourceClause, 'red chase');
    });

    test('the zone question (many matching segments)', () async {
      final intent = await orch.parseOnly(prompt: 'red on the peaks', config: _manyPeaks());
      final a = intent.ambiguities.single;
      expect(a.type, AmbiguityType.zoneAmbiguity);
      expect(a.affectedLayerId, 'layer_0');
    });

    test('a second clause names the second layer', () async {
      final intent = await orch.parseOnly(
          prompt: 'red on the peaks and blue chase on the corners', config: _roof());
      expect(intent.layers.map((l) => l.id), ['layer_0', 'layer_1']);
      expect(intent.ambiguities.single.affectedLayerId, 'layer_1');
    });

    test('a cross-layer conflict names no single layer (unchanged)', () async {
      final intent = await orch.parseOnly(prompt: 'red and blue', config: _roof());
      final conflict = intent.ambiguities
          .singleWhere((a) => a.type == AmbiguityType.conflictResolution);
      expect(conflict.affectedLayerId, isNull);
    });
  });

  group('the answer lands', () {
    test('a prompt whose effect id came from the effect-word precedence fix: '
        '"red pulse", answer "Right to left"', () async {
      // "red pulse", not "red pulsing": the bare "in" of the direction table
      // matches inside "puls-in-g" and answers the direction silently
      // (known, not fixed).
      final first = await orch.processUserInput(prompt: 'red pulse', config: _roof());
      expect(first.status, DesignStudioStatus.needsClarification);
      final q = first.pendingQuestions!
          .singleWhere((q) => q.type == ClarificationType.directionAmbiguity);
      expect(q.affectedLayerId, 'layer_0');
      final rtl = q.options.firstWhere((o) => o.id == 'right_to_left');

      final second = await orch.applyClarifications(
        currentIntent: first.intent!,
        questions: first.pendingQuestions!,
        choices: {q.id: rtl},
        config: _roof(),
      );
      expect(second.isReady, isTrue, reason: '${second.status}: ${second.errorMessage}');
      final motion = second.intent!.layers.single.motion!;
      expect(motion.motionType, MotionType.pulse);
      expect(motion.effectId, 2);
      expect(motion.direction, MotionDirection.rightToLeft);
      expect(second.pattern!.effectId, 2);
      expect(second.pattern!.motionDirection, MotionDirection.rightToLeft);
      final seg = (second.pattern!.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['fx']), [2, 2]);
    });

    test('two ambiguous clauses: each answer lands on its own layer', () async {
      final first = await orch.processUserInput(
          prompt: 'red chase on the peaks and blue wave on the corners', config: _roof());
      expect(first.status, DesignStudioStatus.needsClarification,
          reason: '${first.status}: ${first.errorMessage}');
      final qs = first.pendingQuestions!
          .where((q) => q.type == ClarificationType.directionAmbiguity)
          .toList();
      expect(qs.map((q) => q.affectedLayerId), ['layer_0', 'layer_1']);
      final q0 = qs[0];
      final q1 = qs[1];
      final rtl0 = q0.options.firstWhere((o) => o.id == 'right_to_left');
      final ltr1 = q1.options.firstWhere((o) => o.id == 'left_to_right');

      final second = await orch.applyClarifications(
        currentIntent: first.intent!,
        questions: first.pendingQuestions!,
        choices: {q0.id: rtl0, q1.id: ltr1},
        config: _roof(),
      );
      expect(second.isReady, isTrue, reason: '${second.status}: ${second.errorMessage}');
      final layers = second.intent!.layers;
      expect(layers[0].motion!.direction, MotionDirection.rightToLeft);
      expect(layers[0].motion!.effectId, 28);
      expect(layers[1].motion!.direction, MotionDirection.leftToRight);
      expect(layers[1].motion!.effectId, 67);
    });

    test('the "Left to right" answer is honoured too (no silent default)', () async {
      final first = await orch.processUserInput(prompt: 'red chase', config: _roof());
      final q = first.pendingQuestions!.single;
      final ltr = q.options.firstWhere((o) => o.id == 'left_to_right');
      final second = await orch.applyClarifications(
        currentIntent: first.intent!,
        questions: first.pendingQuestions!,
        choices: {q.id: ltr},
        config: _roof(),
      );
      expect(second.isReady, isTrue);
      expect(second.intent!.layers.single.motion!.direction, MotionDirection.leftToRight);
      expect(second.intent!.ambiguities, isEmpty);
    });
  });
}
