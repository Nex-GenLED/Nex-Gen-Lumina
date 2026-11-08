// Roofline slice 3 follow-up — prompt-parser defect 1, the new-behaviour
// tests: the side-carrying direction phrases the parser now reads, where
// they stop (a place is still a place), and the precedence between them.
// The defect itself is proven by nlu_direction_not_location_fail_before_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
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

void main() {
  final orch = DesignStudioOrchestrator();

  group('NLUService.sideDirectionOf', () {
    const toRight = MotionDirection.leftToRight;
    const toLeft = MotionDirection.rightToLeft;
    for (final (clause, dir) in [
      ('chase left to right', toRight),
      ('chase right to left', toLeft),
      ('wave l to r', toRight),
      ('wave r to l', toLeft),
      ('moving rightward', toRight),
      ('moving leftwards', toLeft),
      ('chase to the right', toRight),
      ('chase to the left', toLeft),
      ('running from left', toRight),
      ('running from right', toLeft),
      ('flowing toward right', toRight),
      ('flowing toward left', toLeft),
      ('moving right', toRight),
      ('chase left', toLeft),
      ('running towards the left', toLeft),
      ('wave toward the right', toRight),
    ]) {
      test('"$clause" → ${dir.name}', () {
        expect(NLUService.sideDirectionOf(clause), dir);
      });
    }

    test('the two-word form wins over "<motion> left": "chase left to right"', () {
      expect(NLUService.sideDirectionOf('chase left to right'), toRight);
      expect(NLUService.sideDirectionOf('moving right to left'), toLeft);
    });

    test('a place names no direction', () {
      for (final clause in [
        'chase on the left side',
        'red on the right',
        'warm white left of house',
        'blue on the right side',
        'chase inward',
        'wave',
      ]) {
        expect(NLUService.sideDirectionOf(clause), isNull, reason: clause);
      }
    });
  });

  group('NLUService.withoutSideDirectionPhrases', () {
    test('blanks the direction and leaves the place', () {
      expect(NLUService.withoutSideDirectionPhrases('chase left to right'),
          isNot(contains('left')));
      expect(NLUService.withoutSideDirectionPhrases('red moving right'),
          isNot(contains('right')));
      expect(NLUService.withoutSideDirectionPhrases('red on the left side'),
          contains('left side'));
      expect(NLUService.withoutSideDirectionPhrases('chase on the left side'),
          contains('left side'));
    });

    test('"to the left" is a direction only with a motion in the clause', () {
      expect(NLUService.withoutSideDirectionPhrases('chase to the left'),
          isNot(contains('left')));
      expect(NLUService.withoutSideDirectionPhrases('red to the left of the garage'),
          contains('to the left'));
    });

    test('"left to right" is a direction even with no motion word', () {
      expect(NLUService.withoutSideDirectionPhrases('red left to right'),
          isNot(contains('left')));
    });
  });

  group('through the parser', () {
    test('"moving right" is left-to-right, not the silent inward of before', () async {
      final intent = await orch.parseOnly(prompt: 'red moving right', config: _roof());
      expect(intent.layers.single.motion!.direction, MotionDirection.leftToRight);
    });

    test('"running left" is a motion on the whole roofline, not the runs', () async {
      final intent = await orch.parseOnly(prompt: 'red running left', config: _roof());
      final layer = intent.layers.single;
      expect(layer.targetZone.type, ZoneSelectorType.all);
      expect(layer.motion!.direction, MotionDirection.rightToLeft);
    });

    test('a direction and a place in one clause: both are kept', () async {
      final intent =
          await orch.parseOnly(prompt: 'red wave moving right on the left side', config: _roof());
      final layer = intent.layers.single;
      expect(layer.targetZone.type, ZoneSelectorType.location);
      expect(layer.targetZone.location, 'left');
      expect(layer.motion!.direction, MotionDirection.leftToRight);
    });

    test('a motion with no direction still asks, as before', () async {
      final intent = await orch.parseOnly(prompt: 'red chase', config: _roof());
      expect(intent.ambiguities.map((a) => a.type), contains(AmbiguityType.directionAmbiguity));
      expect(intent.layers.single.targetZone.type, ZoneSelectorType.all);
    });

    test('the inward / outward table entries are untouched', () async {
      final a = await orch.parseOnly(prompt: 'red chase inward', config: _roof());
      expect(a.layers.single.motion!.direction, MotionDirection.inward);
      final b = await orch.parseOnly(prompt: 'red wave outward', config: _roof());
      expect(b.layers.single.motion!.direction, MotionDirection.outward);
    });

    test('a place with a motion word keeps asking its direction', () async {
      final intent = await orch.parseOnly(prompt: 'red chase on the left side', config: _roof());
      expect(intent.layers.single.targetZone.location, 'left');
      expect(intent.ambiguities.map((a) => a.type), contains(AmbiguityType.directionAmbiguity));
    });

    test('the placeholder example, in full: corners clause and motion clause', () async {
      final intent = await orch.parseOnly(
          prompt: 'Dark green with red accents on corners, wave effect moving right to left',
          config: _roof());
      expect(intent.layers, hasLength(2));
      final motionLayer = intent.layers.firstWhere((l) => l.motion != null);
      expect(motionLayer.motion!.direction, MotionDirection.rightToLeft);
      expect(motionLayer.targetZone.type, isNot(ZoneSelectorType.location));
    });
  });
}
