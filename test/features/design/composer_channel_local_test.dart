// Roofline slice 3 — the AI composer's ranges are CHANNEL-LOCAL (the D-2
// defect). NEW-BEHAVIOUR tests: they read the channel-local picture the
// composer now carries (`ComposedPattern.channelGroups` / `channelLengths`),
// the per-channel wire payload, and the whole-controller projection kept for
// the flat-space consumers. The fail-before file is
// composer_channel_local_fail_before_test.dart.
//
// Fixtures: one bus of 100; two buses of 128 / 162 (the first mapped 120 of
// 128); three buses of 162 / 128 / 100 with a peak at the end of bus 3. No
// device, no provider container.

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart' hide ArchitecturalRole;
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/services/pattern_composer.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 11, 5);

RooflineConfiguration _config(List<RooflineSegment> segments, Map<int, int> buses) =>
    RooflineConfiguration(
      id: 'c',
      name: 'bench',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: buses.length,
      segments: segments,
    ).withChannelPixelCounts(buses);

RooflineConfiguration _oneBus() => _config(const [
      RooflineSegment(id: 'a', name: 'Front run', pixelCount: 100, channelIndex: 0),
    ], const {0: 100});

RooflineConfiguration _twoBusesPartlyMapped() => _config(const [
      RooflineSegment(id: 'a', name: 'Front run', pixelCount: 120, channelIndex: 0),
      RooflineSegment(id: 'b', name: 'Garage run', pixelCount: 162, channelIndex: 1),
    ], const {0: 128, 1: 162});

RooflineConfiguration _threeBuses() => _config(const [
      RooflineSegment(id: 'a', name: 'Front run', pixelCount: 162, channelIndex: 0),
      RooflineSegment(id: 'b', name: 'Side run', pixelCount: 128, channelIndex: 1),
      RooflineSegment(id: 'c', name: 'Garage run', pixelCount: 90, channelIndex: 2),
      RooflineSegment(id: 'p', name: 'Garage peak', pixelCount: 10, startPixel: 90,
          channelIndex: 2, type: SegmentType.peak,
          architecturalRole: ArchitecturalRole.peak),
    ], const {0: 162, 1: 128, 2: 100});

List<(int, int)> _spans(List<LedColorGroup>? groups) =>
    [for (final g in groups ?? const <LedColorGroup>[]) (g.startLed, g.endLed)];

int _litCount(List<LedColorGroup>? groups) {
  var n = 0;
  for (final g in groups ?? const <LedColorGroup>[]) {
    if (g.color.take(4).any((v) => v > 0)) n += g.endLed - g.startLed + 1;
  }
  return n;
}

void main() {
  final orch = DesignStudioOrchestrator();

  Future<ComposedPattern> compose(String prompt, RooflineConfiguration cfg) async {
    final res = await orch.processUserInput(prompt: prompt, config: cfg);
    expect(res.isReady, isTrue, reason: '${res.status} ${res.errorMessage}');
    return res.pattern!;
  }

  group('channel-local groups and lengths', () {
    test('one bus: channel 0 over 100 LEDs', () async {
      final p = await compose('warm white', _oneBus());
      expect(p.channelLengths, {0: 100});
      expect(_spans(p.channelGroups[0]), [(0, 99)]);
      expect(p.totalPixels, 100);
    });

    test('two buses: each channel over its OWN device length, the short map '
        'notwithstanding', () async {
      final p = await compose('warm white', _twoBusesPartlyMapped());
      expect(p.channelLengths, {0: 128, 1: 162});
      expect(_spans(p.channelGroups[0]), [(0, 127)]);
      expect(_spans(p.channelGroups[1]), [(0, 161)]);
      expect(p.totalPixels, 290, reason: 'the strip, not the mapped 282');
    });

    test('three buses: a peak on bus 3 is composed at ITS local LEDs 90-99', () async {
      final p = await compose('red on the peaks', _threeBuses());
      expect(p.channelLengths, {0: 162, 1: 128, 2: 100});
      expect(p.channelGroups.keys, [2], reason: 'only bus 3 carries paint');
      expect(_spans(p.channelGroups[2]), [(90, 99)]);
    });

    test('three buses: "everywhere" is every LED of every bus', () async {
      final p = await compose('warm white', _threeBuses());
      expect(_spans(p.channelGroups[0]), [(0, 161)]);
      expect(_spans(p.channelGroups[1]), [(0, 127)]);
      expect(_spans(p.channelGroups[2]), [(0, 99)]);
    });

    test('a bus the map says nothing about still counts as "everywhere"', () async {
      // The map describes bus 1 only; the device has a second bus of 60.
      final cfg = _config(const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 100, channelIndex: 0),
      ], const {0: 100, 1: 60});
      final p = await compose('warm white', cfg);
      expect(p.channelLengths, {0: 100, 1: 60});
      expect(_spans(p.channelGroups[1]), [(0, 59)]);
    });
  });

  group('spacing is laid down per channel', () {
    test('"1 on 3 off" starts its own phase at LED 0 of EVERY bus', () async {
      // Two buses of 101 and 99: the house total (200) divides by four, so no
      // question is asked, but 101 % 4 = 1 — in one flat space bus 2 would
      // have started mid-cycle (its LED 0 dark).
      final cfg = _config(const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 101, channelIndex: 0),
        RooflineSegment(id: 'b', name: 'Garage run', pixelCount: 99, channelIndex: 1),
      ], const {0: 101, 1: 99});
      final p = await compose('warm white 1 on 3 off', cfg);
      for (final ch in [0, 1]) {
        final first = p.channelGroups[ch]!.first;
        expect(first.startLed, 0, reason: 'channel $ch starts lit');
        expect(_litCount(p.channelGroups[ch]), (p.channelLengths[ch]! + 3) ~/ 4,
            reason: 'channel $ch: one lit LED per four');
      }
    });
  });

  group('the whole-controller projection (flat-space consumers)', () {
    test('channels are laid end to end in id order, at their device lengths', () async {
      final p = await compose('red on the peaks', _threeBuses());
      // Bus 3 starts at 162 + 128 = 290; its peak at local 90..99 → 380..389.
      expect(_spans(p.colorGroups), [(380, 389)]);
    });

    test('two buses: the projection reaches the last LED of the strip', () async {
      final p = await compose('warm white', _twoBusesPartlyMapped());
      expect(_spans(p.colorGroups), [(0, 127), (128, 289)]);
    });
  });

  group('the wire payload addresses each channel by its own segment id', () {
    test('a static pattern: one seg per painted channel, `i` channel-local', () async {
      final p = await compose('red on the peaks', _threeBuses());
      final seg = (p.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['id']), [2]);
      expect(seg.single['fx'], 0);
      // [start, stop-exclusive, [r,g,b,w]] — local to bus 3.
      expect(seg.single['i'], [90, 100, [255, 0, 0, 0]]);
    });

    test('"everywhere" on three buses: three seg entries, ids 0, 1, 2', () async {
      final p = await compose('warm white', _threeBuses());
      final seg = (p.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['id']), [0, 1, 2]);
      expect((seg[0]['i'] as List).take(2), [0, 162]);
      expect((seg[1]['i'] as List).take(2), [0, 128]);
      expect((seg[2]['i'] as List).take(2), [0, 100]);
    });

    test('a motion pattern: one seg per painted channel carrying the effect', () {
      // Through the composer directly: the prompt parser's generic motion
      // carries no effect id (only its named constructors do), so this branch
      // is reached with an explicit MotionSettings.
      final intent = DesignIntent(
        originalPrompt: 'cyan chase',
        layers: const [
          DesignLayer(
            id: 'l0',
            name: 'cyan chase',
            targetZone: ZoneSelector.all(),
            colors: ColorAssignment.solid(Color(0xFF00FFFF)),
            motion: MotionSettings.chaseLeftToRight(),
          ),
        ],
        parsedAt: _now,
      );
      final res = PatternComposer().compose(intent: intent, config: _threeBuses());
      expect(res.isSuccess, isTrue, reason: res.errorMessage);
      final p = res.pattern!;
      expect(p.hasMotion, isTrue);
      expect(p.effectId, 28);
      final seg = (p.wledPayload['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg.map((s) => s['id']), [0, 1, 2]);
      for (final s in seg) {
        expect(s['fx'], 28);
        expect(s['col'], [[0, 255, 255]]);
        expect(s.containsKey('i'), isFalse);
        expect(s.containsKey('start'), isFalse);
      }
      // The channel-local picture is the base colour on every bus.
      expect(_spans(p.channelGroups[0]), [(0, 161)]);
      expect(_spans(p.channelGroups[2]), [(0, 99)]);
    });
  });

  group('the stored layer carries the channel-local picture', () {
    test('toJson writes channel_groups and channel_lengths keyed by channel', () async {
      final p = await compose('red on the peaks', _threeBuses());
      final json = p.toJson();
      expect(json['channel_lengths'], {'0': 162, '1': 128, '2': 100});
      expect(json['channel_groups'], {
        '2': [
          {'start_led': 90, 'end_led': 99, 'color': [255, 0, 0, 0]},
        ],
      });
    });
  });

  group('channelsFromComposedPattern reads the channel-local picture', () {
    test('every laid-out channel becomes a ChannelDesign at its own length, '
        'painted or dark, with no segment list at all', () async {
      final p = await compose('red on the peaks', _threeBuses());
      final channels = channelsFromComposedPattern(p, const []);
      expect(channels.map((c) => c.channelId), [0, 1, 2]);
      expect(channels.map((c) => c.ledCount), [162, 128, 100]);
      expect(channels.map((c) => c.channelName), ['Channel 1', 'Channel 2', 'Channel 3']);
      expect(_spans(channels[0].colorGroups), isEmpty);
      expect(_spans(channels[2].colorGroups), [(90, 99)]);
    });

    test('the device segment list supplies names only — never bounds', () async {
      final p = await compose('red on the peaks', _threeBuses());
      // A stale state read: bounds that do not match the buses at all.
      const stale = [
        WledSegment(id: 0, name: 'Roof', start: 0, stop: 50),
        WledSegment(id: 2, name: 'Garage', start: 50, stop: 80),
      ];
      final channels = channelsFromComposedPattern(p, stale);
      expect(channels.map((c) => c.channelName), ['Roof', 'Channel 2', 'Garage']);
      expect(channels.map((c) => c.ledCount), [162, 128, 100]);
      expect(_spans(channels[2].colorGroups), [(90, 99)]);
    });

    test('a hand-built pattern with no channel-local picture keeps the old '
        'split over the segment bounds', () {
      final p = ComposedPattern(
        name: 'legacy',
        colorGroups: const [
          LedColorGroup(startLed: 0, endLed: 127, color: [255, 102, 0, 0]),
          LedColorGroup(startLed: 128, endLed: 187, color: [128, 0, 128, 0]),
        ],
        wledPayload: const {'on': true},
        totalPixels: 188,
        composedAt: _now,
      );
      const segments = [
        WledSegment(id: 0, name: 'Roof', start: 0, stop: 128),
        WledSegment(id: 1, name: 'Side', start: 128, stop: 188),
      ];
      final channels = channelsFromComposedPattern(p, segments);
      expect(_spans(channels[0].colorGroups), [(0, 127)]);
      expect(_spans(channels[1].colorGroups), [(0, 59)]);
      expect(channelsFromComposedPattern(p, const []).single.ledCount, 188);
    });
  });
}
