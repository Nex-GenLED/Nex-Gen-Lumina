import 'package:nexgen_command/models/roofline_segment.dart';

/// Design Studio Slice 4 — pure selection math (channel-local LED indices).

/// Which feature type a "select by feature" pick targets.
enum FeatureFilter { allCorners, allPeaks, allRuns }

/// Every-[step]-th LED within the inclusive range `[start, end]`, beginning at
/// `start + offset` (the classic candy-cane / repeating-accent selector).
/// [step] < 1 is treated as 1. Indices below [start] (from a negative offset)
/// are dropped.
List<int> everyNthInRange({
  required int start,
  required int end,
  required int step,
  int offset = 0,
}) {
  final s = step < 1 ? 1 : step;
  final out = <int>[];
  for (int i = start + offset; i <= end; i += s) {
    if (i >= start) out.add(i);
  }
  return out;
}

bool _matches(RooflineSegment seg, FeatureFilter filter) {
  switch (filter) {
    case FeatureFilter.allCorners:
      return seg.type == SegmentType.corner ||
          seg.architecturalRole == ArchitecturalRole.corner;
    case FeatureFilter.allPeaks:
      return seg.type == SegmentType.peak ||
          seg.architecturalRole == ArchitecturalRole.peak;
    case FeatureFilter.allRuns:
      return seg.type == SegmentType.run;
  }
}

/// All channel-local LED indices belonging to features matching [filter].
Set<int> featureIndices(
    List<RooflineSegment> channelSegments, FeatureFilter filter) {
  final out = <int>{};
  for (final seg in channelSegments) {
    if (!_matches(seg, filter)) continue;
    for (int i = seg.startPixel; i <= seg.endPixel; i++) {
      out.add(i);
    }
  }
  return out;
}

/// All channel-local LED indices of a single segment (this peak / this run).
Set<int> segmentIndices(RooflineSegment seg) =>
    {for (int i = seg.startPixel; i <= seg.endPixel; i++) i};

/// Channel-local anchor-zone LED indices across [channelSegments]. Each
/// segment's `anchorPixels` are segment-local; the global-in-channel index is
/// `segment.startPixel + anchor`, expanded by `anchorLedCount`.
Set<int> anchorIndices(List<RooflineSegment> channelSegments) {
  final out = <int>{};
  for (final seg in channelSegments) {
    for (final a in seg.anchorPixels) {
      final base = seg.startPixel + a;
      for (int k = 0; k < seg.anchorLedCount; k++) {
        final idx = base + k;
        if (idx >= seg.startPixel && idx <= seg.endPixel) out.add(idx);
      }
    }
  }
  return out;
}
