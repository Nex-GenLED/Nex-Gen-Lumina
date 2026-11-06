// Roofline slice 3 follow-up — prompt-parser defect 1, the fail-before test.
//
// TODAY the parser reads the bare words "left" and "right" as the left or
// right SIDE of the house (a location zone) wherever they occur in a clause,
// so a direction of motion — "left to right", "right to left", "moving
// right", "chase left" — turns the clause into a location layer. The
// composer resolves a location by segment name ("left"/"west",
// "right"/"east"); on an ordinary map nothing matches, the layer paints
// nothing, and the studio answers "No layers produced LED assignments". The
// studio's own "Chase Effect" quick idea ("Blue chase effect moving left to
// right") and its placeholder example's motion clause ("wave effect moving
// right to left") both go this way. A bare "moving right" / "chase left" is
// not a direction phrase at all today: the direction falls through to a table
// whose bare "in" matches the "in" inside "moving", and the motion is
// silently inward.
//
// Against the unchanged parser the first two groups fail; the controls pass.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 11, 6);

/// Three buses, 162 / 128 / 100, named the way an installer names them — no
/// "left"/"west"/"right"/"east" anywhere, as on most maps.
RooflineConfiguration _threeBuses() => RooflineConfiguration(
      id: 'ctl-a',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 3,
      segments: const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 162, channelIndex: 0),
        RooflineSegment(id: 'b', name: 'Side run', pixelCount: 128, channelIndex: 1),
        RooflineSegment(id: 'c', name: 'Garage run', pixelCount: 90, channelIndex: 2),
        RooflineSegment(id: 'p', name: 'Garage peak', pixelCount: 10, startPixel: 90,
            channelIndex: 2, type: SegmentType.peak),
      ],
    ).withChannelPixelCounts(const {0: 162, 1: 128, 2: 100});

void main() {
  final orch = DesignStudioOrchestrator();

  group('a direction of motion is never a location zone', () {
    for (final (prompt, direction) in [
      // The studio's "Chase Effect" quick idea, verbatim.
      ('Blue chase effect moving left to right', MotionDirection.leftToRight),
      // The placeholder example's motion clause.
      ('wave effect moving right to left', MotionDirection.rightToLeft),
      ('red moving right', MotionDirection.leftToRight),
      ('red chase left', MotionDirection.rightToLeft),
    ]) {
      test('"$prompt" → the whole roofline, moving ${direction.name}', () async {
        final intent = await orch.parseOnly(prompt: prompt, config: _threeBuses());
        final layer = intent.layers.single;
        expect(layer.targetZone.type, ZoneSelectorType.all,
            reason: 'zone was "${layer.targetZone.description}"');
        expect(layer.motion, isNotNull, reason: 'no motion parsed');
        expect(layer.motion!.direction, direction);
        expect(
            intent.ambiguities.where((a) => a.type == AmbiguityType.directionAmbiguity),
            isEmpty,
            reason: 'the direction was stated; no question is due');
      });
    }

    test('the "Chase Effect" quick idea composes, on every bus', () async {
      final res = await orch.processUserInput(
          prompt: 'Blue chase effect moving left to right', config: _threeBuses());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      expect(res.pattern!.channelGroups.keys.toList()..sort(), [0, 1, 2]);
    });

    test('the placeholder example composes', () async {
      final res = await orch.processUserInput(
          prompt: 'wave effect moving right to left', config: _threeBuses());
      expect(res.isReady, isTrue, reason: '${res.status}: ${res.errorMessage}');
      expect(res.pattern!.channelGroups.keys.toList()..sort(), [0, 1, 2]);
    });
  });

  group('controls — a place is still a place', () {
    for (final (prompt, side) in [
      ('red on the left side', 'left'),
      ('red on the right side', 'right'),
      ('warm white on the left', 'left'),
      ('blue left of house', 'left'),
      // A motion word in the clause does not make a place a direction.
      ('chase on the left side', 'left'),
    ]) {
      test('"$prompt" → location "$side"', () async {
        final intent = await orch.parseOnly(prompt: prompt, config: _threeBuses());
        final zone = intent.layers.single.targetZone;
        expect(zone.type, ZoneSelectorType.location);
        expect(zone.location, side);
      });
    }
  });
}
