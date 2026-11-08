// Roofline slice 3 — the AI composer's ranges are CHANNEL-LOCAL (the D-2
// global-index defect, ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03 §A.4 and the
// Parent Segment spec §3.2).
//
// This is the FAIL-BEFORE file: it uses only the API that existed before the
// change (the orchestrator, `customDesignFromComposedPattern`,
// `withChannelPixelCounts`), so it compiles against the unchanged composer and
// shows the defect there. The new-behaviour assertions (the channel-local
// groups themselves, the per-channel wire payload) are in
// composer_channel_local_test.dart.
//
// What the defect looked like on the unchanged code:
//   * the composer worked in ONE flat index space across every bus, then
//     consolidated over the MAPPED pixel total, so a bus whose map was
//     shorter than its strip lost the tail of the NEXT bus (2-bus case);
//   * the composed groups were global, so with no WLED segment list to split
//     them over (off the LAN, before the state read) every bus collapsed into
//     "channel 0" with indices past its own length (3-bus cases).
//
// Fixtures: one bus of 100; two buses of 128 / 162 with the first one mapped
// 120 of 128; three buses of 162 / 128 / 100 with a peak at the end of bus 3.
// No device, no provider container.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
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

/// One bus of 100, fully mapped.
RooflineConfiguration _oneBus() => _config(const [
      RooflineSegment(id: 'a', name: 'Front run', pixelCount: 100, channelIndex: 0),
    ], const {0: 100});

/// Two buses: bus 1 is 128 LEDs but mapped as 120; bus 2 is 162, mapped.
RooflineConfiguration _twoBusesPartlyMapped() => _config(const [
      RooflineSegment(id: 'a', name: 'Front run', pixelCount: 120, channelIndex: 0),
      RooflineSegment(id: 'b', name: 'Garage run', pixelCount: 162, channelIndex: 1),
    ], const {0: 128, 1: 162});

/// Three buses of 162 / 128 / 100 (the spare's bench layout), with a peak on
/// the last ten LEDs of bus 3.
RooflineConfiguration _threeBuses() => _config(const [
      RooflineSegment(id: 'a', name: 'Front run', pixelCount: 162, channelIndex: 0),
      RooflineSegment(id: 'b', name: 'Side run', pixelCount: 128, channelIndex: 1),
      RooflineSegment(id: 'c', name: 'Garage run', pixelCount: 90, channelIndex: 2),
      RooflineSegment(id: 'p', name: 'Garage peak', pixelCount: 10, startPixel: 90,
          channelIndex: 2, type: SegmentType.peak,
          architecturalRole: ArchitecturalRole.peak),
    ], const {0: 162, 1: 128, 2: 100});

bool _lit(LedColorGroup g) =>
    g.color.take(4).any((v) => v > 0);

void main() {
  final orch = DesignStudioOrchestrator();

  /// Compose [prompt] and build it into a design the way the studio's Save and
  /// Apply do, with NO WLED segment list (off the LAN, or before the state
  /// read lands).
  Future<CustomDesign> designFor(String prompt, RooflineConfiguration cfg) async {
    final res = await orch.processUserInput(prompt: prompt, config: cfg);
    expect(res.isReady, isTrue, reason: '${res.status} ${res.errorMessage}');
    return customDesignFromComposedPattern(
        pattern: res.pattern!, segments: const [], ownerId: 'u');
  }

  group('one bus (the control case: right before and after)', () {
    test('"warm white" paints channel 0, LEDs 0-99, and nothing else', () async {
      final d = await designFor('warm white', _oneBus());
      expect(d.channels.map((c) => c.channelId), [0]);
      final ch = d.channels.single;
      expect(ch.ledCount, 100);
      expect(ch.colorGroups.where(_lit).map((g) => (g.startLed, g.endLed)), [(0, 99)]);
    });
  });

  group('two buses, the first mapped shorter than its strip', () {
    test('"warm white" reaches the last LED of bus 2 (global 289), not the '
        'mapped total (281)', () async {
      final res = await orch.processUserInput(
          prompt: 'warm white', config: _twoBusesPartlyMapped());
      expect(res.isReady, isTrue, reason: '${res.status} ${res.errorMessage}');
      final groups = res.pattern!.colorGroups.where(_lit).toList();
      expect(groups, isNotEmpty);
      final last = groups.map((g) => g.endLed).reduce((a, b) => a > b ? a : b);
      expect(last, 289,
          reason: 'was 281: the flat space was consolidated over the MAPPED '
              'pixel total (120 + 162), so the last 8 LEDs of bus 2 went dark');
    });
  });

  group('three buses, no WLED segment list to split over', () {
    test('"warm white" lands on all three channels at their own lengths', () async {
      final d = await designFor('warm white', _threeBuses());
      expect(d.channels.map((c) => c.channelId).toList(), [0, 1, 2],
          reason: 'was [0]: every bus collapsed into channel 0');
      expect(d.channels.map((c) => c.ledCount).toList(), [162, 128, 100]);
      for (final ch in d.channels) {
        expect(ch.colorGroups.where(_lit).map((g) => (g.startLed, g.endLed)),
            [(0, ch.ledCount - 1)],
            reason: 'channel ${ch.channelId}');
      }
    });

    test('"red on the peaks" paints bus 3, LEDs 90-99 — channel-local, not '
        'global 380-389 on channel 0', () async {
      final d = await designFor('red on the peaks', _threeBuses());
      final bus3 = d.channels.where((c) => c.channelId == 2).toList();
      expect(bus3, hasLength(1), reason: 'channels: ${d.channels.map((c) => c.channelId)}');
      expect(bus3.single.ledCount, 100);
      expect(bus3.single.colorGroups.where(_lit).map((g) => (g.startLed, g.endLed)),
          [(90, 99)]);
      // The other two buses carry no red.
      for (final ch in d.channels.where((c) => c.channelId != 2)) {
        expect(ch.colorGroups.where(_lit), isEmpty, reason: 'channel ${ch.channelId}');
      }
    });
  });
}
