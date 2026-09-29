import 'dart:ui';

import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

// Pure logic behind the customer feature walkthrough
// (roofline_feature_walkthrough.dart). The walk itself reuses the installer's
// Map Roofline capture model — marks at corners, peak apexes and run splits,
// compiled by [compileMarksToChannelSegments] — so an installer-marked
// channel and a customer-marked channel have the same shape.

/// Rebuilds the marks that would produce [channelSegments], so a channel
/// that is already marked (or split into runs) opens in the walkthrough as
/// it is, rather than as one blank run.
List<CaptureMark> marksFromChannelSegments(
    List<RooflineSegment> channelSegments) {
  final segs = [...channelSegments]
    ..sort((a, b) => a.startPixel.compareTo(b.startPixel));
  final marks = <CaptureMark>[];
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i];
    final prev = i > 0 ? segs[i - 1] : null;
    final next = i + 1 < segs.length ? segs[i + 1] : null;
    final isPeak = s.type == SegmentType.peak ||
        s.architecturalRole == ArchitecturalRole.peak;
    final isCorner = s.type == SegmentType.corner ||
        s.architecturalRole == ArchitecturalRole.corner;

    if (isPeak && s.pixelCount == 1) {
      // An apex: the installer's symmetric trio is up-slope, apex, down-slope.
      final up = prev != null &&
              prev.type == SegmentType.peak &&
              prev.direction == SegmentDirection.upward
          ? prev.pixelCount
          : 0;
      final down = next != null &&
              next.type == SegmentType.peak &&
              next.direction == SegmentDirection.downward
          ? next.pixelCount
          : 0;
      final slope = up > down ? up : down;
      marks.add(CaptureMark(
          pixel: s.startPixel,
          kind: MarkKind.peak,
          slopeLength: slope < 1 ? 1 : slope));
      continue;
    }
    if (isPeak &&
        ((s.direction == SegmentDirection.upward &&
                next != null &&
                next.pixelCount == 1 &&
                next.type == SegmentType.peak) ||
            (s.direction == SegmentDirection.downward &&
                prev != null &&
                prev.pixelCount == 1 &&
                prev.type == SegmentType.peak))) {
      continue; // a slope of an apex trio — the apex mark rebuilds it
    }
    if (isCorner) {
      marks.add(CaptureMark(
          pixel: s.startPixel, kind: MarkKind.corner, width: s.pixelCount));
      continue;
    }
    if (s.type != SegmentType.run || s.architecturalRole != null) {
      // A peak section, column or connector that is not an apex trio.
      marks.add(CaptureMark(
        pixel: s.startPixel,
        kind: MarkKind.custom,
        width: s.pixelCount,
        customType: s.type == SegmentType.run ? SegmentType.peak : s.type,
        customRole: s.architecturalRole,
        name: s.name,
      ));
      continue;
    }
    // A run that follows another run: keep the split between them.
    if (prev != null &&
        prev.type == SegmentType.run &&
        prev.architecturalRole == null) {
      marks.add(CaptureMark(pixel: s.startPixel, kind: MarkKind.runBoundary));
    }
  }
  return marks;
}

/// Compiles [marks] into the channel's features and carries forward what the
/// customer or installer already set on [existing] segments of the channel:
///
///  * a feature whose range exactly matches an existing segment keeps that
///    segment's id, name, anchors, photo points, direction and other details
///    — only its type and role change;
///  * other features take their photo points from the existing outline over
///    the same LEDs, the anchors that fall inside them, and the story level
///    of the segment they start in;
///  * every feature is marked [RooflineSegment.featureConfirmed].
///
/// [pixelCount] is the channel's length.
List<RooflineSegment> applyFeatureMarksToChannel({
  required int channelIndex,
  required int pixelCount,
  required List<RooflineSegment> existing,
  required List<CaptureMark> marks,
}) {
  final old = [...existing]
    ..sort((a, b) => a.startPixel.compareTo(b.startPixel));
  final compiled = compileMarksToChannelSegments(
    channelIndex: channelIndex,
    pixelCount: pixelCount,
    marks: marks,
  );
  return [
    for (final f in compiled) _carryForward(f, old),
  ];
}

RooflineSegment _carryForward(RooflineSegment f, List<RooflineSegment> old) {
  RooflineSegment? exact;
  for (final o in old) {
    if (o.startPixel == f.startPixel && o.pixelCount == f.pixelCount) {
      exact = o;
      break;
    }
  }
  final keepDirection = f.type == SegmentType.run;
  if (exact != null) {
    return RooflineSegment(
      id: exact.id,
      name: exact.name,
      pixelCount: exact.pixelCount,
      startPixel: exact.startPixel,
      type: f.type,
      anchorPixels: exact.anchorPixels,
      anchorLedCount: exact.anchorLedCount,
      sortOrder: f.sortOrder,
      direction: keepDirection ? exact.direction : f.direction,
      anchorPoints: exact.anchorPoints,
      description: exact.description,
      isPrimary: exact.isPrimary,
      symmetryPairId: exact.symmetryPairId,
      architecturalRole: f.architecturalRole,
      location: exact.location,
      adjacentSegmentIds: exact.adjacentSegmentIds,
      isProminent: f.isProminent,
      isConnectedToPrevious: f.isConnectedToPrevious,
      level: exact.level,
      points: exact.points,
      channelIndex: exact.channelIndex,
      overrideColor: exact.overrideColor,
      featureConfirmed: true,
    );
  }

  final start = f.startPixel;
  final end = f.startPixel + f.pixelCount; // exclusive
  final container = _segmentAt(old, start);
  final anchors = <int>[];
  for (final o in old) {
    for (final a in o.anchorPixels) {
      final g = o.startPixel + a;
      if (g >= start && g + o.anchorLedCount <= end) anchors.add(g - start);
    }
  }
  anchors.sort();
  return f.copyWith(
    anchorPixels: anchors.toSet().toList(),
    level: container?.level ?? f.level,
    direction:
        keepDirection && container != null ? container.direction : f.direction,
    points: _pointsForRange(old, start, end),
    featureConfirmed: true,
  );
}

RooflineSegment? _segmentAt(List<RooflineSegment> old, int pixel) {
  for (final o in old) {
    if (pixel >= o.startPixel && pixel < o.startPixel + o.pixelCount) return o;
  }
  return null;
}

/// The part of the existing photo outline that covers LEDs [start, end).
/// Empty when the LEDs were never traced.
List<Offset> _pointsForRange(List<RooflineSegment> old, int start, int end) {
  final out = <Offset>[];
  void add(Offset? p) {
    if (p != null && (out.isEmpty || out.last != p)) out.add(p);
  }

  add(_pointAtPixel(old, start.toDouble()));
  for (final o in old) {
    if (o.points.length < 2 || o.pixelCount <= 0) continue;
    final lengths = _cumulativeLengths(o.points);
    final total = lengths.last;
    if (total <= 0) continue;
    for (var i = 1; i < o.points.length - 1; i++) {
      final pixel = o.startPixel + lengths[i] / total * o.pixelCount;
      if (pixel > start && pixel < end) add(o.points[i]);
    }
  }
  add(_pointAtPixel(old, end.toDouble()));
  return out.length >= 2 ? out : const [];
}

Offset? _pointAtPixel(List<RooflineSegment> old, double pixel) {
  for (final o in old) {
    final s = o.startPixel.toDouble();
    final e = (o.startPixel + o.pixelCount).toDouble();
    if (pixel >= s && pixel <= e && o.points.length >= 2 && o.pixelCount > 0) {
      return _alongPolyline(o.points, (pixel - s) / o.pixelCount);
    }
  }
  return null;
}

List<double> _cumulativeLengths(List<Offset> pts) {
  final out = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    out.add(out.last + (pts[i] - pts[i - 1]).distance);
  }
  return out;
}

Offset _alongPolyline(List<Offset> pts, double t) {
  final lengths = _cumulativeLengths(pts);
  final total = lengths.last;
  if (total <= 0) return pts.first;
  final target = t.clamp(0.0, 1.0) * total;
  for (var i = 1; i < pts.length; i++) {
    if (target <= lengths[i]) {
      final span = lengths[i] - lengths[i - 1];
      final k = span <= 0 ? 0.0 : (target - lengths[i - 1]) / span;
      return Offset.lerp(pts[i - 1], pts[i], k)!;
    }
  }
  return pts.last;
}

/// [config] with channel [channelIndex]'s segments replaced by [segments];
/// every other channel is untouched.
RooflineConfiguration replaceChannelSegments(
  RooflineConfiguration config,
  int channelIndex,
  List<RooflineSegment> segments,
) {
  final channels = {...config.allChannelIndices, channelIndex}.toList()..sort();
  final ordered = <RooflineSegment>[
    for (final ch in channels)
      ...(ch == channelIndex ? segments : config.segmentsForChannel(ch)),
  ];
  return config.copyWith(
    segments: [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(sortOrder: i),
    ],
    totalChannelCount: config.totalChannelCount > channelIndex
        ? config.totalChannelCount
        : channelIndex + 1,
  );
}

/// The channel's length for the walkthrough: what the stored map covers, or
/// the live strip length when the map has nothing on that channel.
int channelLengthForMarking(
  RooflineConfiguration config,
  int channelIndex, {
  int? liveLength,
}) {
  final mapped = config
      .segmentsForChannel(channelIndex)
      .fold<int>(0, (sum, s) => sum + s.pixelCount);
  if (mapped > 0) return mapped;
  return liveLength ?? 0;
}
