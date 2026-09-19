// M4 / F4 / N1b — ONE index base for the pixel map.
//
// `RooflineSegment.startPixel` is CHANNEL-LOCAL. These tests pin the writer
// (`recalculateStartPixels`), the Firestore write boundary
// (`splitConfigToPixelMapChannels`), the explicit whole-controller translation
// the AI camp uses, and the fit check that a length-only staleness test missed.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 9, 19);

/// The bench home: channel 1 = 128 LEDs, channel 2 = 162 LEDs.
RooflineConfiguration _twoChannel() => RooflineConfiguration(
      id: 'c',
      name: 'bench',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 2,
      segments: const [
        RooflineSegment(id: 'a1', name: 'Front run', pixelCount: 100, channelIndex: 0),
        RooflineSegment(id: 'a2', name: 'Front peak', pixelCount: 28, startPixel: 100, channelIndex: 0, type: SegmentType.peak),
        RooflineSegment(id: 'b1', name: 'Garage run', pixelCount: 162, channelIndex: 1),
      ],
    );

void main() {
  group('writer: recalculateStartPixels is per-channel', () {
    test('an anchor edit on a channel-2 segment leaves it starting at 0', () {
      final cfg = _twoChannel();
      final seg = cfg.segmentById('b1')!;
      // Exactly what RooflineConfigEditorNotifier.updateSegment does.
      final edited = cfg.updateSegment('b1', seg.copyWith(anchorPixels: [0, 160]));

      expect(edited.segmentById('a1')!.startPixel, 0);
      expect(edited.segmentById('a2')!.startPixel, 100);
      expect(edited.segmentById('b1')!.startPixel, 0,
          reason: 'was 128 — cumulative across channels (F4)');
      expect(edited.segmentById('b1')!.endPixel, 161);
    });

    test('the Anchors tool then lands on the LEDs the user marked', () {
      final cfg = _twoChannel();
      final edited = cfg.updateSegment(
          'b1', cfg.segmentById('b1')!.copyWith(anchorPixels: [0, 160]));
      final anchors = anchorIndices(edited.segmentsForChannel(1));
      expect(anchors, {0, 1, 160, 161});

      final doc = PixelDesignDocument.blank(
        baseColor: const [10, 10, 12, 0],
        channelLengths: const {0: 128, 1: 162},
      ).paint(1, anchors, const [255, 0, 0, 0]);
      expect(doc.paintedCount, 4, reason: 'was 2 of 4 — the rest fell off the end');
    });

    test('add / remove / reorder all keep every channel based at 0', () {
      var cfg = _twoChannel().addSegment(const RooflineSegment(
          id: 'b2', name: 'Garage corner', pixelCount: 6, channelIndex: 1));
      expect(cfg.segmentById('b2')!.startPixel, 162);
      expect(cfg.segmentById('b1')!.startPixel, 0);

      cfg = cfg.reorderSegments(3, 0); // channel-2 corner first in the list
      expect(cfg.segmentById('b2')!.startPixel, 0);
      expect(cfg.segmentById('b1')!.startPixel, 6);
      expect(cfg.segmentById('a1')!.startPixel, 0,
          reason: 'channel 1 is untouched by a channel-2 segment ahead of it');

      cfg = cfg.removeSegment('a1');
      expect(cfg.segmentById('a2')!.startPixel, 0);
      expect(cfg.channelsWithMisfitSegments({0: 128, 1: 168}), isEmpty);
    });

    test('a single-channel home is unchanged (cumulative == channel-local)', () {
      final cfg = RooflineConfiguration(
        id: 'c', name: 'one', createdAt: _now, updatedAt: _now,
        segments: const [
          RooflineSegment(id: 'x', name: 'A', pixelCount: 40),
          RooflineSegment(id: 'y', name: 'B', pixelCount: 60),
        ],
      ).recalculateStartPixels();
      expect([for (final s in cfg.segments) s.startPixel], [0, 40]);
    });
  });

  group('write boundary: splitConfigToPixelMapChannels re-derives start_pixel', () {
    test('a cumulatively-numbered config is written channel-local', () {
      // The shape the old writer (and the legacy per-user config) produced.
      final cumulative = RooflineConfiguration(
        id: 'c', name: 'legacy', createdAt: _now, updatedAt: _now,
        segments: const [
          RooflineSegment(id: 'a', name: 'Ch1', pixelCount: 41, startPixel: 0, channelIndex: 0),
          RooflineSegment(id: 'b', name: 'Ch2', pixelCount: 41, startPixel: 41, channelIndex: 1),
        ],
      );
      final docs = splitConfigToPixelMapChannels(cumulative,
          controllerId: 'ctrl', sourceCounts: const {0: 41, 1: 41}, now: _now);
      expect(docs[1].segments.single.startPixel, 0);
      expect(docs[1].segmentsFitChannel(), isTrue);
    });

    test('a correct map passes through byte-identical (no-op)', () {
      final cfg = _twoChannel();
      final docs = splitConfigToPixelMapChannels(cfg, controllerId: 'ctrl', now: _now);
      expect(docs[0].segments, cfg.segmentsForChannel(0));
      expect(docs[1].segments, cfg.segmentsForChannel(1));
    });
  });

  group('fit check catches what a length-only staleness test missed', () {
    PixelMapChannel doc(List<RooflineSegment> segs, int source) => PixelMapChannel(
        controllerId: 'c', channelIndex: 1, segments: segs,
        sourcePixelCount: source, createdAt: _now, updatedAt: _now);

    test('production shape: start_pixel 41 + 41 px on a 41-LED channel', () {
      final d = doc(const [
        RooflineSegment(id: 'b', name: 'Ch2', pixelCount: 41, startPixel: 41, channelIndex: 1)
      ], 41);
      expect(d.isStaleAgainst(41), isFalse, reason: 'lengths match — the old check passed it');
      expect(d.segmentsFitChannel(41), isFalse);
      expect(d.needsRemapAgainst(41), isTrue);
    });

    test('overflow: 168 mapped px on a 128-LED channel', () {
      final d = doc(const [
        RooflineSegment(id: 'a', name: 'A', pixelCount: 128, startPixel: 0),
        RooflineSegment(id: 'b', name: 'B', pixelCount: 40, startPixel: 128),
      ], 128);
      expect(d.needsRemapAgainst(128), isTrue);
    });

    test('a healthy channel does not need a remap; unknown device is not stale', () {
      final d = doc(const [
        RooflineSegment(id: 'b', name: 'Ch2', pixelCount: 162, channelIndex: 1)
      ], 162);
      expect(d.needsRemapAgainst(162), isFalse);
      expect(d.needsRemapAgainst(null), isFalse);
    });
  });

  group('whole-controller translation for the global camp', () {
    test('globalStartOf uses device-truth channel lengths when known', () {
      // Channel 1 is only PARTLY mapped (120 of 128): the mapped total would
      // put channel 2 at 120; the strip really starts it at 128.
      final cfg = RooflineConfiguration(
        id: 'c', name: 'p', createdAt: _now, updatedAt: _now,
        segments: const [
          RooflineSegment(id: 'a', name: 'Ch1', pixelCount: 120, channelIndex: 0),
          RooflineSegment(id: 'b', name: 'Ch2', pixelCount: 162, channelIndex: 1),
        ],
      );
      expect(cfg.globalStartOf(cfg.segmentById('b')!), 120);
      final live = cfg.withChannelPixelCounts(const {0: 128, 1: 162});
      expect(live.globalStartOf(live.segmentById('b')!), 128);
      expect(live.globalEndOf(live.segmentById('b')!), 289);
      expect(live.globalPixelCount, 290);
      expect(live.segmentForPixel(128)!.id, 'b');
      expect(live.segmentForPixel(119)!.id, 'a');
    });

    test('aggregating channel docs attaches their source_pixel_count', () {
      final cfg = aggregatePixelMapChannelsToConfig('ctrl', [
        PixelMapChannel(controllerId: 'ctrl', channelIndex: 0, sourcePixelCount: 128,
            segments: const [RooflineSegment(id: 'a', name: 'A', pixelCount: 120)],
            createdAt: _now, updatedAt: _now),
        PixelMapChannel(controllerId: 'ctrl', channelIndex: 1, sourcePixelCount: 162,
            segments: const [RooflineSegment(id: 'b', name: 'B', pixelCount: 162, channelIndex: 1)],
            createdAt: _now, updatedAt: _now),
      ]);
      expect(cfg.channelPixelCounts, {0: 128, 1: 162});
      expect(cfg.globalStartOf(cfg.segmentById('b')!), 128);
    });

    test('AI composer: a channel-2 peak is composed at its whole-controller LEDs', () async {
      final cfg = RooflineConfiguration(
        id: 'c', name: 'ai', createdAt: _now, updatedAt: _now,
        segments: const [
          RooflineSegment(id: 'a', name: 'Front run', pixelCount: 128, channelIndex: 0),
          RooflineSegment(id: 'b', name: 'Garage run', pixelCount: 150, channelIndex: 1),
          RooflineSegment(id: 'p', name: 'Garage peak', pixelCount: 12, startPixel: 150,
              channelIndex: 1, type: SegmentType.peak,
              architecturalRole: ArchitecturalRole.peak),
        ],
      ).withChannelPixelCounts(const {0: 128, 1: 162});

      final res = await DesignStudioOrchestrator()
          .processUserInput(prompt: 'red on the peaks', config: cfg);
      final groups = res.pattern?.colorGroups ?? const [];
      expect(groups, isNotEmpty, reason: '${res.status} ${res.errorMessage}');
      // Peak = channel-local 150..161 → whole-controller 278..289.
      expect(groups.map((g) => g.startLed).reduce((a, b) => a < b ? a : b), 278);
      expect(groups.map((g) => g.endLed).reduce((a, b) => a > b ? a : b), 289);
    });
  });
}
