// Roofline slice 3 — "start from this design": a variation composes in the
// saved design's colours when the prompt names none, over the saved design's
// STAMPED bus lengths, and an ordinary prompt is untouched.
//
// New behaviour. The orchestrator and composer are pure; the config source
// (`configForAiPipeline`) runs in a provider container with no device.
//
// Fixture: a saved design in red / blue / white, stamped for three buses of
// 100 (ctl-a); the live device, when present, has ONE bus of 40.

import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_color_summary.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart' hide ArchitecturalRole;
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/services/nlu_service.dart';
import 'package:nexgen_command/features/design/services/pattern_composer.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 11, 5);
const kStamp = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);

const kBase = DesignColorSummary(swatches: [
  DesignColorSwatch(rgbw: [255, 0, 0, 0], share: 0.5),
  DesignColorSwatch(rgbw: [0, 0, 255, 0], share: 0.4),
  DesignColorSwatch(rgbw: [255, 255, 255, 0], share: 0.1),
]);

CustomDesign _saved() => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: kStamp,
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(channelId: id, channelName: 'Channel ${id + 1}', ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 89, color: [0, 0, 255, 0]),
                LedColorGroup(startLed: 90, endLed: 99, color: [255, 255, 255, 0]),
              ]),
      ],
    );

/// A one-bus map of 40 LEDs — what the config carries before any lengths are
/// attached.
RooflineConfiguration _map() => RooflineConfiguration(
      id: 'r',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      controllerId: 'ctl-a',
      segments: const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 40, channelIndex: 0),
      ],
    );

List<List<int>> _litColors(List<LedColorGroup>? groups) => [
      for (final g in groups ?? const <LedColorGroup>[])
        if (g.color.take(4).any((v) => v > 0)) g.color,
    ];

void main() {
  final orch = DesignStudioOrchestrator();
  final cfg = _map().withChannelPixelCounts(const {0: 100, 1: 100, 2: 100});

  group('NLUService.mentionsColor', () {
    test('a colour word, specific or vague, is a mention', () {
      for (final p in ['warm white', 'something blue', 'red on the peaks', 'gold', 'corners off']) {
        expect(NLUService.mentionsColor(p), isTrue, reason: p);
      }
    });

    test('an arrangement alone is not — and the "off" in a spacing phrase is '
        'not the colour black', () {
      for (final p in ['every other light', '1 on 3 off', 'one on, six off', 'alternating', 'gradient', 'chase inward']) {
        expect(NLUService.mentionsColor(p), isFalse, reason: p);
      }
    });
  });

  group('PatternComposer.seedColors', () {
    test('the parser\'s default (white, nothing else) takes the saved colours, '
        'spacing kept', () {
      const unstated = ColorAssignment(
          primaryColor: Colors.white, spacingRule: SpacingRule.everyOther());
      expect(PatternComposer.isUnstatedColors(unstated), isTrue);
      final seeded = PatternComposer.seedColors(unstated, kBase);
      expect(seeded.primaryColor, const Color(0xFFFF0000));
      expect(seeded.secondaryColor, const Color(0xFF0000FF));
      expect(seeded.accentColor, const Color(0xFFFFFFFF));
      expect(seeded.spacingRule?.type, SpacingType.pattern);
    });

    test('stated colours are left alone', () {
      const stated = ColorAssignment.solid(Color(0xFFFFD700));
      expect(PatternComposer.isUnstatedColors(stated), isFalse);
      expect(identical(PatternComposer.seedColors(stated, kBase), stated), isTrue);
      const whiteWithAccent = ColorAssignment(
          primaryColor: Colors.white, accentColor: Color(0xFFFF0000));
      expect(PatternComposer.isUnstatedColors(whiteWithAccent), isFalse);
    });

    test('an empty base seeds nothing', () {
      const unstated = ColorAssignment(primaryColor: Colors.white);
      expect(identical(PatternComposer.seedColors(unstated, DesignColorSummary.empty), unstated),
          isTrue);
    });
  });

  group('DesignStudioOrchestrator.seedFor', () {
    test('base colours only for a prompt that names no colour', () {
      expect(DesignStudioOrchestrator.seedFor('every other light', kBase), kBase);
      expect(DesignStudioOrchestrator.seedFor('white every other light', kBase), isNull);
      expect(DesignStudioOrchestrator.seedFor('every other light', null), isNull);
      expect(DesignStudioOrchestrator.seedFor('every other light', DesignColorSummary.empty),
          isNull);
    });
  });

  group('a variation through the orchestrator', () {
    test('"every other light" composes in the saved design\'s colours on every bus',
        () async {
      final res = await orch.processUserInput(
          prompt: 'every other light', config: cfg, baseColors: kBase);
      expect(res.isReady, isTrue, reason: '${res.status} ${res.errorMessage}');
      final p = res.pattern!;
      expect(p.channelLengths, {0: 100, 1: 100, 2: 100});
      for (final ch in [0, 1, 2]) {
        final lit = _litColors(p.channelGroups[ch]);
        expect(lit, isNotEmpty, reason: 'channel $ch');
        // The spacing rule lights its accent: the saved design's third colour.
        expect(lit.toSet(), {[255, 255, 255, 0]}, reason: 'channel $ch');
      }
      // The intent the studio shows is the seeded one.
      expect(res.intent!.layers.single.colors.primaryColor, const Color(0xFFFF0000));
      expect(res.intent!.layers.single.colors.accentColor, const Color(0xFFFFFFFF));
      // The stored layer says what it composed with.
      final stored = p.toJson()['source_intent'] as Map<String, dynamic>;
      final colors = (stored['layers'] as List).single['colors'] as Map;
      expect(colors['primary_color'], [255, 0, 0, 255]);
    });

    test('an alternating pattern takes the saved design\'s first two colours', () {
      // Through the composer: the prompt parser reads "alternating" as the
      // every-other SPACING rule (accent colour), so the alternating PATTERN
      // is reached with an explicit intent.
      final intent = DesignIntent(
        originalPrompt: 'alternating',
        layers: const [
          DesignLayer(
            id: 'l0',
            name: 'alternating',
            targetZone: ZoneSelector.all(),
            colors: ColorAssignment(primaryColor: Colors.white),
            pattern: PatternRule.alternating(),
          ),
        ],
        parsedAt: _now,
      );
      final res = orch.quickCompose(intent: intent, config: cfg, baseColors: kBase);
      expect(res.isSuccess, isTrue, reason: res.errorMessage);
      final groups = res.pattern!.channelGroups[0]!;
      expect(groups.first.color, [255, 0, 0, 0]);
      expect(groups[1].color, [0, 0, 255, 0]);
      expect(groups.length, 100, reason: 'one group per LED, red / blue alternating');
    });

    test('a prompt that names a colour keeps it: "white every other light" is white',
        () async {
      final res = await orch.processUserInput(
          prompt: 'white every other light', config: cfg, baseColors: kBase);
      expect(res.isReady, isTrue, reason: '${res.status} ${res.errorMessage}');
      expect(_litColors(res.pattern!.channelGroups[0]).toSet(), {[255, 255, 255, 0]});
      expect(res.intent!.layers.single.colors.primaryColor, Colors.white);
    });

    test('with no base the same prompt composes as it always has (white)', () async {
      final res = await orch.processUserInput(prompt: 'every other light', config: cfg);
      expect(res.isReady, isTrue, reason: '${res.status} ${res.errorMessage}');
      expect(_litColors(res.pattern!.channelGroups[0]).toSet(), {[255, 255, 255, 0]});
    });
  });

  group('configForAiPipeline — the lengths the variation is composed over', () {
    ProviderContainer container({VariationBase? base, List<DeviceChannel> live = const []}) {
      final c = ProviderContainer(overrides: [
        currentRooflineConfigProvider.overrideWith((ref) => Stream.value(_map())),
        deviceChannelsProvider.overrideWithValue(live),
        if (base != null) variationBaseProvider.overrideWith((ref) => base),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    const liveOneBus = [
      DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 40, gpioPin: 2),
    ];

    test('a variation session: the saved design\'s stamped bus lengths, not the '
        'live device', () async {
      final c = container(base: variationBaseFor(_saved()), live: liveOneBus);
      await c.read(currentRooflineConfigProvider.future);
      expect(configForAiPipeline(c.read)!.channelPixelCounts, {0: 100, 1: 100, 2: 100});
    });

    test('an ordinary session: the live device', () async {
      final c = container(live: liveOneBus);
      await c.read(currentRooflineConfigProvider.future);
      expect(configForAiPipeline(c.read)!.channelPixelCounts, {0: 40});
    });

    test('no device, no base: the map as recorded', () async {
      final c = container();
      await c.read(currentRooflineConfigProvider.future);
      expect(configForAiPipeline(c.read)!.channelPixelCounts, isEmpty);
    });

    test('Start over clears the base', () {
      final c = container(base: variationBaseFor(_saved()));
      expect(c.read(variationBaseProvider), isNotNull);
      resetDesignStudioWith(c.read);
      expect(c.read(variationBaseProvider), isNull);
    });
  });
}
