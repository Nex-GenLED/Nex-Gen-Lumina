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

/// An "N on, M off" pattern over the inclusive range `[start, end]`: [on] lit
/// LEDs, then [off] dark, repeating from [start]. This is the vocabulary users
/// actually speak ("4 off, 1 on"); `everyNthInRange(step: k)` is the special
/// case `on: 1, off: k - 1`.
///
/// Returns BOTH halves so a caller can paint the lit LEDs AND clear the dark
/// ones — which is what makes re-running it with different numbers produce the
/// new pattern instead of the union of old and new (followup N3a: every-5th
/// re-run as every-7th left 41 LEDs lit where a clean every-7th is 19).
///
/// [on] < 1 is treated as 1, [off] < 0 as 0. An inverted range yields nothing.
({List<int> lit, List<int> dark}) onOffPatternInRange({
  required int start,
  required int end,
  required int on,
  required int off,
}) {
  final lit = <int>[], dark = <int>[];
  if (end < start) return (lit: lit, dark: dark);
  final n = on < 1 ? 1 : on;
  final m = off < 0 ? 0 : off;
  final cycle = n + m;
  for (int i = start; i <= end; i++) {
    ((i - start) % cycle < n ? lit : dark).add(i);
  }
  return (lit: lit, dark: dark);
}

/// Parses the editor's "Go to LED" box: `"57"` → that LED, `"12-40"` (also
/// `12–40`, `12 to 40`, `12:40`) → the inclusive range, either order. Indices
/// are channel-local and must lie inside `[0, length)`. Null when it is not a
/// number / range, or falls outside the channel.
({int start, int end})? parseLedTarget(String input, int length) {
  final m = RegExp(r'^\s*(\d+)\s*(?:(?:-|–|—|:|to)\s*(\d+))?\s*$',
          caseSensitive: false)
      .firstMatch(input);
  if (m == null || length <= 0) return null;
  final a = int.parse(m.group(1)!);
  final b = m.group(2) == null ? a : int.parse(m.group(2)!);
  final lo = a <= b ? a : b, hi = a <= b ? b : a;
  if (hi >= length) return null;
  return (start: lo, end: hi);
}
