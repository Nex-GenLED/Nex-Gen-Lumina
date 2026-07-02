import 'package:nexgen_command/models/roofline_segment.dart';

/// Design Studio Slice 2 — pure boundary-marking capture logic.
///
/// The installer walks a channel with a single lit pixel and drops a small
/// number of MARKS at feature edges (corners, peak apexes, run splits). This
/// module turns that sparse mark list into the ordered [RooflineSegment]
/// feature list the Slice 1 pixelMap stores — ranges BETWEEN marks are
/// auto-inferred as runs, so a 600-pixel home needs ~10–20 taps, not 600.
///
/// All coordinates are CHANNEL-LOCAL (0-based within the channel's `bus.len`).
/// Pure + deterministic — no Firestore, no device, no Riverpod.

/// What an installer's tap denotes.
enum MarkKind {
  /// A point feature — an outside/inside corner (default 1 px).
  corner,

  /// A gable/roof apex. Expands to a symmetric peakUp/peak/peakDown trio via
  /// [CaptureMark.slopeLength].
  peak,

  /// Splits the inferred run at this pixel into two runs (e.g. front vs side,
  /// both runs but distinct segments). Adds NO non-run feature itself.
  runBoundary,

  /// A caller-typed feature ([CaptureMark.customType] / [customRole]) spanning
  /// [CaptureMark.width] px.
  custom,
}

/// One installer tap at a channel-local [pixel].
class CaptureMark {
  final int pixel;
  final MarkKind kind;

  /// Feature width for [MarkKind.corner] / [MarkKind.custom] (px). Default 1.
  final int width;

  /// Half-span of a [MarkKind.peak] — LEDs on each slope. Total peak = 2L+1.
  final int slopeLength;

  /// Type/role for [MarkKind.custom].
  final SegmentType customType;
  final ArchitecturalRole? customRole;

  /// Optional human label; auto-generated when null.
  final String? name;

  const CaptureMark({
    required this.pixel,
    required this.kind,
    this.width = 1,
    this.slopeLength = 3,
    this.customType = SegmentType.run,
    this.customRole,
    this.name,
  });

  CaptureMark copyWith({int? pixel, MarkKind? kind, int? width, int? slopeLength}) {
    return CaptureMark(
      pixel: pixel ?? this.pixel,
      kind: kind ?? this.kind,
      width: width ?? this.width,
      slopeLength: slopeLength ?? this.slopeLength,
      customType: customType,
      customRole: customRole,
      name: name,
    );
  }
}

/// A half-open [start, end) channel-local range with a resolved feature type.
class _Feature {
  final int start; // inclusive
  final int end; // exclusive
  final SegmentType type;
  final ArchitecturalRole? role;
  final SegmentDirection direction;
  final String label;
  const _Feature(this.start, this.end, this.type, this.role, this.direction,
      this.label);
  int get len => end - start;
}

/// The 3 segments of a symmetric peak centered on [apexPixel] with
/// [slopeLength] LEDs per slope, clamped to `[0, pixelCount)`. Order:
/// peakUp (upward) · peak (apex) · peakDown (downward).
List<RooflineSegment> symmetricPeakSegments({
  required int channelIndex,
  required int pixelCount,
  required int apexPixel,
  required int slopeLength,
  int startSortOrder = 0,
  int startLocalPixel = 0,
}) {
  final L = slopeLength < 1 ? 1 : slopeLength;
  final upStart = (apexPixel - L).clamp(0, pixelCount - 1);
  final downEnd = (apexPixel + L).clamp(0, pixelCount - 1);
  final apex = apexPixel.clamp(0, pixelCount - 1);

  final out = <RooflineSegment>[];
  var order = startSortOrder;
  if (apex > upStart) {
    out.add(RooflineSegment(
      id: 'peakup_$apexPixel',
      name: 'Peak Up',
      startPixel: upStart,
      pixelCount: apex - upStart,
      type: SegmentType.peak,
      direction: SegmentDirection.upward,
      architecturalRole: ArchitecturalRole.peak,
      channelIndex: channelIndex,
      sortOrder: order++,
      isConnectedToPrevious: true,
    ));
  }
  out.add(RooflineSegment(
    id: 'peak_$apexPixel',
    name: 'Peak',
    startPixel: apex,
    pixelCount: 1,
    type: SegmentType.peak,
    architecturalRole: ArchitecturalRole.peak,
    channelIndex: channelIndex,
    sortOrder: order++,
    isProminent: true,
    isConnectedToPrevious: true,
  ));
  if (downEnd > apex) {
    out.add(RooflineSegment(
      id: 'peakdown_$apexPixel',
      name: 'Peak Down',
      startPixel: apex + 1,
      pixelCount: downEnd - apex,
      type: SegmentType.peak,
      direction: SegmentDirection.downward,
      architecturalRole: ArchitecturalRole.peak,
      channelIndex: channelIndex,
      sortOrder: order++,
      isConnectedToPrevious: true,
    ));
  }
  return out;
}

/// Compiles sparse [marks] into the ordered, gap-filled, non-overlapping
/// feature list for one channel. Unmarked ranges become runs; [MarkKind.peak]
/// expands to a symmetric trio; [MarkKind.runBoundary] splits the covering run.
///
/// Overlapping non-run features are resolved by keeping the earlier-starting
/// one and dropping the later overlap (defensive — the UI prevents overlaps).
/// Returns an empty list when [pixelCount] <= 0.
List<RooflineSegment> compileMarksToChannelSegments({
  required int channelIndex,
  required int pixelCount,
  required List<CaptureMark> marks,
}) {
  if (pixelCount <= 0) return const [];

  // 1. Expand corner/peak/custom marks into non-run feature ranges.
  final features = <_Feature>[];
  final runBoundaries = <int>[];
  for (final m in marks) {
    final p = m.pixel.clamp(0, pixelCount - 1);
    switch (m.kind) {
      case MarkKind.runBoundary:
        runBoundaries.add(p);
        break;
      case MarkKind.corner:
        final w = m.width < 1 ? 1 : m.width;
        features.add(_Feature(p, (p + w).clamp(0, pixelCount),
            SegmentType.corner, ArchitecturalRole.corner,
            SegmentDirection.leftToRight, m.name ?? 'Corner'));
        break;
      case MarkKind.custom:
        final w = m.width < 1 ? 1 : m.width;
        features.add(_Feature(p, (p + w).clamp(0, pixelCount), m.customType,
            m.customRole, SegmentDirection.leftToRight,
            m.name ?? m.customType.displayName));
        break;
      case MarkKind.peak:
        final L = m.slopeLength < 1 ? 1 : m.slopeLength;
        final upStart = (p - L).clamp(0, pixelCount - 1);
        final downEnd = (p + L).clamp(0, pixelCount - 1);
        if (p > upStart) {
          features.add(_Feature(upStart, p, SegmentType.peak,
              ArchitecturalRole.peak, SegmentDirection.upward, 'Peak Up'));
        }
        features.add(_Feature(p, p + 1, SegmentType.peak,
            ArchitecturalRole.peak, SegmentDirection.leftToRight, 'Peak'));
        if (downEnd > p) {
          features.add(_Feature(p + 1, (downEnd + 1).clamp(0, pixelCount),
              SegmentType.peak, ArchitecturalRole.peak,
              SegmentDirection.downward, 'Peak Down'));
        }
        break;
    }
  }

  // 2. Sort features, drop overlaps (keep earlier start).
  features.sort((a, b) => a.start.compareTo(b.start));
  final kept = <_Feature>[];
  int cursor = 0;
  for (final f in features) {
    if (f.start < cursor || f.len <= 0) continue; // overlap / empty → drop
    kept.add(f);
    cursor = f.end;
  }

  // 3. Fill gaps (incl. leading/trailing) with runs, split at runBoundaries.
  final bounds = (runBoundaries.toSet().toList()..sort());
  final ordered = <_Feature>[];
  int pos = 0;
  for (final f in kept) {
    if (f.start > pos) {
      ordered.addAll(_runsForGap(pos, f.start, bounds));
    }
    ordered.add(f);
    pos = f.end;
  }
  if (pos < pixelCount) {
    ordered.addAll(_runsForGap(pos, pixelCount, bounds));
  }

  // 4. Materialize RooflineSegments with names + sortOrder + connectivity.
  final segments = <RooflineSegment>[];
  final counts = <SegmentType, int>{};
  for (int i = 0; i < ordered.length; i++) {
    final f = ordered[i];
    final n = (counts[f.type] = (counts[f.type] ?? 0) + 1);
    final label = f.type == SegmentType.run ? 'Run $n' : f.label;
    segments.add(RooflineSegment(
      id: 'ch${channelIndex}_seg$i',
      name: label,
      startPixel: f.start,
      pixelCount: f.len,
      type: f.type,
      direction: f.direction,
      architecturalRole: f.role,
      channelIndex: channelIndex,
      sortOrder: i,
      isProminent: f.type == SegmentType.peak,
      isConnectedToPrevious: i != 0,
    ));
  }
  return segments;
}

/// Splits `[start, end)` into run features at any [bounds] strictly inside it.
List<_Feature> _runsForGap(int start, int end, List<int> bounds) {
  final splits = bounds.where((b) => b > start && b < end).toList()..sort();
  final out = <_Feature>[];
  int s = start;
  for (final b in [...splits, end]) {
    if (b > s) {
      out.add(_Feature(s, b, SegmentType.run, null,
          SegmentDirection.leftToRight, 'Run'));
      s = b;
    }
  }
  return out;
}

/// Re-keys [source] segments onto [targetChannelIndex] for copy-across-channels.
/// Exact copy (verbatim ranges); the caller gates on an exact `bus.len` match,
/// or offers copy-then-adjust for a near-match. New ids avoid collisions.
List<RooflineSegment> copyChannelSegments(
  List<RooflineSegment> source, {
  required int targetChannelIndex,
}) {
  return [
    for (int i = 0; i < source.length; i++)
      source[i].copyWith(
        id: 'ch${targetChannelIndex}_seg$i',
        channelIndex: targetChannelIndex,
      ),
  ];
}
