// +113 — the walkthrough's marks-to-sections compiler: placing a mark twice
// changes nothing, every section id is unique and stable across re-saves,
// the channel length comes from the strip first, and a section can be merged
// back into its neighbour by removing one mark.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_feature_marking.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

List<RooflineSegment> _compile(List<CaptureMark> marks,
        {List<RooflineSegment> existing = const [], int len = 100, int ch = 1}) =>
    applyFeatureMarksToChannel(
        channelIndex: ch, pixelCount: len, existing: existing, marks: marks);

List<(int, int)> _ranges(List<RooflineSegment> s) =>
    [for (final x in s) (x.startPixel, x.pixelCount)];

void main() {
  group('placeMark — one light carries one mark', () {
    const corner20 = CaptureMark(pixel: 20, kind: MarkKind.corner);

    test('placing the same mark twice returns the same list', () {
      final once = placeMark(const [], corner20);
      final twice = placeMark(once, corner20);
      expect(identical(once, twice), isTrue);
      expect(twice.length, 1);
    });

    test('marks stay sorted by light', () {
      var marks = placeMark(const [], const CaptureMark(pixel: 50, kind: MarkKind.corner));
      marks = placeMark(marks, corner20);
      expect(marks.map((m) => m.pixel), [20, 50]);
    });

    test('a run split on a corner changes nothing — the corner already splits', () {
      final marks = placeMark(const [corner20],
          const CaptureMark(pixel: 20, kind: MarkKind.runBoundary));
      expect(marks.single.kind, MarkKind.corner);
    });

    test('a peak on a corner replaces it', () {
      final marks = placeMark(const [corner20],
          const CaptureMark(pixel: 20, kind: MarkKind.peak));
      expect(marks.single.kind, MarkKind.peak);
      expect(marks.length, 1);
    });
  });

  group('applyFeatureMarksToChannel — stable, unique ids', () {
    test('re-saving the same marks yields the same sections and ids', () {
      const marks = [
        CaptureMark(pixel: 50, kind: MarkKind.corner),
        CaptureMark(pixel: 70, kind: MarkKind.runBoundary),
      ];
      final first = _compile(marks);
      final second = _compile(marks, existing: first);
      final third = _compile(marks, existing: second);
      expect(_ranges(second), _ranges(first));
      expect(second.map((s) => s.id).toList(), first.map((s) => s.id).toList());
      expect(third.map((s) => s.id).toList(), first.map((s) => s.id).toList());
      expect(first.fold<int>(0, (a, s) => a + s.pixelCount), 100);
    });

    test('adding a corner before an old section never duplicates an id '
        '(the ch1_seg1 collision)', () {
      final first = _compile(const [CaptureMark(pixel: 50, kind: MarkKind.corner)]);
      // The old map's ids are positional, exactly as the shipped compiler wrote
      // them: ch1_seg0, ch1_seg1 (the corner), ch1_seg2.
      final legacy = [
        for (var i = 0; i < first.length; i++) first[i].copyWith(id: 'ch1_seg$i'),
      ];
      final second = _compile(const [
        CaptureMark(pixel: 20, kind: MarkKind.corner),
        CaptureMark(pixel: 50, kind: MarkKind.corner),
      ], existing: legacy);

      expect(second.length, 5);
      final ids = second.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'ids unique: $ids');
      // The untouched old sections keep their stored ids.
      expect(second[3].id, 'ch1_seg1', reason: 'corner at 50 carried forward');
      expect(second[4].id, 'ch1_seg2', reason: 'trailing run carried forward');
      // Partition still complete and in order.
      expect(_ranges(second), [(0, 20), (20, 1), (21, 29), (50, 1), (51, 49)]);
      expect(second.every((s) => s.featureConfirmed), isTrue);
    });

    test('withUniqueSectionIds renames a repeated id by where it starts', () {
      final dup = [
        const RooflineSegment(id: 'x', name: 'a', pixelCount: 5, startPixel: 0, channelIndex: 1),
        const RooflineSegment(id: 'x', name: 'b', pixelCount: 5, startPixel: 5, channelIndex: 1),
        const RooflineSegment(id: 'ch1_at10', name: 'c', pixelCount: 5, startPixel: 10, channelIndex: 1),
        const RooflineSegment(id: 'ch1_at10', name: 'd', pixelCount: 5, startPixel: 10, channelIndex: 1),
      ];
      final out = withUniqueSectionIds(dup, 1);
      expect(out.map((s) => s.id), ['x', 'ch1_at5', 'ch1_at10', 'ch1_at10_2']);
      expect(_ranges(out), _ranges(dup), reason: 'only ids change');
    });
  });

  group('channelLengthForMarking — the strip first', () {
    final config = RooflineConfiguration(
      id: 'c',
      controllerId: 'c',
      name: 'r',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      segments: const [
        RooflineSegment(id: 'a', name: 'Run', pixelCount: 57, channelIndex: 0),
      ],
      channelPixelCounts: const {0: 104},
    );

    test('live strip length wins', () {
      expect(channelLengthForMarking(config, 0, liveLength: 120), 120);
    });
    test('then the recorded strip length (source_pixel_count)', () {
      expect(channelLengthForMarking(config, 0), 104);
      expect(channelLengthForMarking(config, 0, liveLength: 0), 104);
    });
    test('then the stored sum, and 0 for an unmapped channel', () {
      final noRecord = config.copyWith(channelPixelCounts: const {});
      expect(channelLengthForMarking(noRecord, 0), 57);
      expect(channelLengthForMarking(noRecord, 3), 0);
      expect(mappedLengthOfChannel(config, 0), 57);
    });
  });

  group('planSectionRemoval — delete a section by merging it away', () {
    const marks = [
      CaptureMark(pixel: 20, kind: MarkKind.corner),
      CaptureMark(pixel: 50, kind: MarkKind.peak, slopeLength: 3),
      CaptureMark(pixel: 80, kind: MarkKind.runBoundary),
    ];
    final sections = _compile(marks);
    // run · corner · run · peakUp · peak · peakDown · run · run

    test('removing a corner gives its light back to the run around it', () {
      final corner = sections.firstWhere((s) => s.type == SegmentType.corner);
      final plan = planSectionRemoval(
          channelIndex: 1, pixelCount: 100, marks: marks, section: corner)!;
      expect(plan.mark.kind, MarkKind.corner);
      expect(plan.marksAfter.length, 2);
      expect(plan.sectionsAfter.any((s) => s.type == SegmentType.corner), isFalse);
      expect(plan.sectionsAfter.first.pixelCount, 47, reason: '0..46 one run');
      expect(plan.sectionsAfter.fold<int>(0, (a, s) => a + s.pixelCount), 100);
    });

    test('removing any part of a peak removes the whole apex trio', () {
      final down = sections.firstWhere((s) =>
          s.type == SegmentType.peak && s.direction == SegmentDirection.downward);
      final plan = planSectionRemoval(
          channelIndex: 1, pixelCount: 100, marks: marks, section: down)!;
      expect(plan.mark.kind, MarkKind.peak);
      expect(plan.sectionsAfter.where((s) => s.type == SegmentType.peak), isEmpty);
    });

    test('removing a run that starts at a split merges it into the run before', () {
      final lastRun = sections.last;
      expect(lastRun.startPixel, 80);
      final plan = planSectionRemoval(
          channelIndex: 1, pixelCount: 100, marks: marks, section: lastRun)!;
      expect(plan.mark.kind, MarkKind.runBoundary);
      expect(plan.sectionsAfter.last.startPixel, 54);
      expect(plan.sectionsAfter.last.pixelCount, 46);
    });

    test('the first run of a channel merges into the next when it ends at a split', () {
      const splitOnly = [CaptureMark(pixel: 30, kind: MarkKind.runBoundary)];
      final two = _compile(splitOnly);
      final plan = planSectionRemoval(
          channelIndex: 1, pixelCount: 100, marks: splitOnly, section: two.first)!;
      expect(plan.sectionsAfter.length, 1);
      expect(plan.sectionsAfter.single.pixelCount, 100);
    });

    test('a run between two features cannot be merged by one removal — and says why', () {
      final between = sections[2];
      expect(between.type, SegmentType.run);
      expect(between.startPixel, 21);
      expect(
          planSectionRemoval(
              channelIndex: 1, pixelCount: 100, marks: marks, section: between),
          isNull);
      expect(
          sectionRemovalBlocker(
              channelIndex: 1, pixelCount: 100, marks: marks, section: between),
          contains('between marked features'));
    });

    test('an unmarked channel has nothing to merge', () {
      final one = _compile(const []);
      expect(
          sectionRemovalBlocker(
              channelIndex: 1, pixelCount: 100, marks: const [], section: one.single),
          'This channel is already one straight run.');
    });

    test('a removable section has no blocker', () {
      final corner = sections.firstWhere((s) => s.type == SegmentType.corner);
      expect(
          sectionRemovalBlocker(
              channelIndex: 1, pixelCount: 100, marks: marks, section: corner),
          isNull);
    });
  });

  test('marksSummary counts what Start over removes', () {
    final s = marksSummary(const [
      CaptureMark(pixel: 1, kind: MarkKind.corner),
      CaptureMark(pixel: 2, kind: MarkKind.corner),
      CaptureMark(pixel: 3, kind: MarkKind.peak),
      CaptureMark(pixel: 4, kind: MarkKind.runBoundary),
    ]);
    expect((s.corners, s.peaks, s.splits, s.other), (2, 1, 1, 0));
  });

  test('markFeatureRange matches what the compiler lights', () {
    expect(markFeatureRange(const CaptureMark(pixel: 10, kind: MarkKind.corner), 100),
        (start: 10, end: 11));
    expect(
        markFeatureRange(
            const CaptureMark(pixel: 10, kind: MarkKind.peak, slopeLength: 3), 100),
        (start: 7, end: 14));
    expect(
        markFeatureRange(
            const CaptureMark(pixel: 1, kind: MarkKind.peak, slopeLength: 3), 100),
        (start: 0, end: 5));
    expect(
        markFeatureRange(const CaptureMark(pixel: 10, kind: MarkKind.runBoundary), 100),
        (start: 10, end: 10));
  });
}
