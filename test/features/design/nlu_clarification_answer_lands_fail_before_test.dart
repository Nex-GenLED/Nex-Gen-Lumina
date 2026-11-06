// Roofline slice 3 follow-up — prompt-parser quirk 4, the fail-before test:
// a clause-level clarification answer never lands.
//
// TODAY the clarification sheet applies an answer to the layer the question
// names (ClarificationQuestion.affectedLayerId, copied from the ambiguity),
// and skips the layer change when it names none. The constraint solver
// stamps its spacing ambiguities with the layer id; the parser's own
// ambiguities — the direction question, the colour-shade question, the
// zone question — carry none. So "red chase" asks "Which direction?", the
// owner taps "Right to left", the ambiguity is marked resolved, and the
// design composes left to right.
//
// Against the unchanged parser every test here fails.

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

void main() {
  final orch = DesignStudioOrchestrator();

  test('"red chase", answer "Right to left" → the design moves right to left', () async {
    final first = await orch.processUserInput(prompt: 'red chase', config: _roof());
    expect(first.status, DesignStudioStatus.needsClarification);
    final q = first.pendingQuestions!
        .singleWhere((q) => q.type == ClarificationType.directionAmbiguity);
    expect(q.affectedLayerId, 'layer_0',
        reason: 'the sheet applies an answer only to the layer the question names');
    final rtl = q.options.firstWhere((o) => o.id == 'right_to_left');

    final second = await orch.applyClarifications(
      currentIntent: first.intent!,
      questions: first.pendingQuestions!,
      choices: {q.id: rtl},
      config: _roof(),
    );
    expect(second.isReady, isTrue, reason: '${second.status}: ${second.errorMessage}');
    final motion = second.intent!.layers.single.motion!;
    expect(motion.direction, MotionDirection.rightToLeft, reason: 'the answer was dropped');
    expect(motion.reverse, isTrue);
    expect(motion.effectId, 28);
    expect(second.pattern!.motionDirection, MotionDirection.rightToLeft);
    expect(second.pattern!.reverse, isTrue);
  });

  test('two layers, one ambiguous: the answer lands on that layer only', () async {
    final first = await orch.processUserInput(
        prompt: 'red on the peaks and blue chase on the corners', config: _roof());
    expect(first.status, DesignStudioStatus.needsClarification,
        reason: '${first.status}: ${first.errorMessage}');
    expect(first.intent!.layers, hasLength(2));
    final q = first.pendingQuestions!
        .singleWhere((q) => q.type == ClarificationType.directionAmbiguity);
    expect(q.affectedLayerId, 'layer_1', reason: 'the chase is the second clause');
    final rtl = q.options.firstWhere((o) => o.id == 'right_to_left');

    final second = await orch.applyClarifications(
      currentIntent: first.intent!,
      questions: first.pendingQuestions!,
      choices: {q.id: rtl},
      config: _roof(),
    );
    expect(second.isReady, isTrue, reason: '${second.status}: ${second.errorMessage}');
    final layers = second.intent!.layers;
    expect(layers[0].motion, isNull, reason: 'the peaks layer stated no motion');
    expect(layers[0].targetZone.roles, [ArchitecturalRole.peak]);
    expect(layers[1].targetZone.roles, [ArchitecturalRole.corner]);
    expect(layers[1].motion!.direction, MotionDirection.rightToLeft);
    expect(layers[1].motion!.effectId, 28);
    expect(second.pattern!.motionDirection, MotionDirection.rightToLeft);
  });

  // No colour-shade case here: the parser's "Which shade of green?" question
  // cannot be raised today — every vague-colour key (green, blue, red,
  // purple) is also a colour-map key, and the vague check is skipped once
  // the colour map has matched. Found, not changed (out of scope).
}
