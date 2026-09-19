// M14 (followup N3c, N3d) — the AI Design Studio understands spacing phrasing,
// stops reading "off" as the colour black, and its "(with remainder)" answer
// no longer loops.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/services/nlu_service.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 9, 19);
RooflineConfiguration _roof(int pixels) => RooflineConfiguration(
      id: 'c', name: 'r', createdAt: _now, updatedAt: _now,
      segments: [RooflineSegment(id: 'a', name: 'Front run', pixelCount: pixels)],
    );

int _lit(List<LedColorGroup> groups) {
  int n = 0;
  for (final g in groups) {
    final c = g.color;
    if (c[0] + c[1] + c[2] + (c.length > 3 ? c[3] : 0) > 0) n += g.endLed - g.startLed + 1;
  }
  return n;
}

void main() {
  final orch = DesignStudioOrchestrator();

  group('canonicalizeSpacingPhrases', () {
    const expected = 'spc:1:6';
    for (final phrase in [
      '1 on 6 off', '1 on, 6 off', '1 on and 6 off', '1 on then 6 off', '1 on / 6 off',
      '6 off 1 on', '6 off, 1 on', '6 off and 1 on',
      'one on six off', 'six off, one on',
      '1 led on, 6 leds off', '6 lights off 1 light on',
    ]) {
      test('"$phrase"', () {
        expect(NLUService.canonicalizeSpacingPhrases('warm white $phrase'),
            'warm white $expected');
      });
    }

    test('leaves unrelated uses of on / off alone', () {
      for (final s in ['turn the corners off', 'red on the peaks', 'lights on at 6']) {
        expect(NLUService.canonicalizeSpacingPhrases(s), s);
      }
    });
  });

  group('parsing → the right rule, in every phrasing', () {
    for (final phrase in [
      '1 on 6 off', '1 on, 6 off', '6 off 1 on', '6 off, 1 on', '1 on and 6 off',
    ]) {
      test('"warm white $phrase" → pattern 1/6', () async {
        final intent = await orch.parseOnly(prompt: 'warm white $phrase', config: _roof(126));
        expect(intent.layers, hasLength(1),
            reason: 'the comma / "and" must not split the phrase into two layers');
        final rule = intent.layers.single.colors.spacingRule!;
        expect([rule.type, rule.onCount, rule.offCount], [SpacingType.pattern, 1, 6]);
      });
    }
  });

  test('"off" inside a spacing phrase is NOT the colour black', () async {
    // 128 px / (1+3) divides evenly → composes without a question.
    final res = await orch.processUserInput(prompt: 'warm white 1 on 3 off', config: _roof(128));
    expect(res.isReady, isTrue, reason: '${res.status} ${res.errorMessage}');
    final groups = res.pattern!.colorGroups;
    expect(_lit(groups), 32, reason: 'was 32 groups of [0,0,0,0] — a fully dark pattern');
    expect(groups.first.color.take(3).any((v) => v > 0), isTrue);
    final layer = res.intent!.layers.single;
    expect(layer.colors.accentColor, isNull, reason: 'was black, from the word "off"');
  });

  test('…while a genuine "off" still means dark', () async {
    final intent = await orch.parseOnly(prompt: 'corners off', config: _roof(128));
    expect(intent.layers.single.colors.primaryColor.toARGB32() & 0xFFFFFF, 0);
  });

  group('the spacing question can be ANSWERED', () {
    // 128 px with 1 on / 6 off leaves a remainder → the solver asks.
    Future<DesignStudioResult> ask() =>
        orch.processUserInput(prompt: 'warm white 1 on 6 off', config: _roof(128));

    test('every offered option resolves — none re-asks (was an endless loop)', () async {
      final first = await ask();
      expect(first.needsClarification, isTrue);
      final q = first.pendingQuestions!.single;
      final answerable = q.options.where((o) => o.id != 'manual').toList();
      expect(answerable.map((o) => o.id), containsAll(['original']));

      for (final option in answerable) {
        final res = await orch.applyClarifications(
          currentIntent: first.intent!,
          questions: first.pendingQuestions!,
          choices: {q.id: option},
          config: _roof(128),
        );
        expect(res.isReady, isTrue,
            reason: '"${option.label}" returned ${res.status} — it used to '
                'come back as the same question');
        expect(_lit(res.pattern!.colorGroups), greaterThan(0));
      }
    });

    test('"(with remainder)" gives exactly what was asked for', () async {
      final first = await ask();
      final q = first.pendingQuestions!.single;
      final original = q.options.firstWhere((o) => o.id == 'original');
      final res = await orch.applyClarifications(
        currentIntent: first.intent!, questions: first.pendingQuestions!,
        choices: {q.id: original}, config: _roof(128));
      final rule = res.intent!.layers.single.colors.spacingRule!;
      expect([rule.onCount, rule.offCount, rule.acceptRemainder], [1, 6, true]);
      expect(_lit(res.pattern!.colorGroups), 19, reason: 'every 7th of 128');
    });
  });

  test('acceptRemainder round-trips and is only ever written as true', () {
    const rule = SpacingRule(type: SpacingType.pattern, onCount: 1, offCount: 6);
    expect(rule.toJson().containsKey('accept_remainder'), isFalse);
    expect(rule.accepted().toJson()['accept_remainder'], true);
    expect(const SpacingRule.everyNth(7).acceptRemainder, isFalse);
  });
}
