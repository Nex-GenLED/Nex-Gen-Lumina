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
  return withUniqueSectionIds(
    [for (final f in compiled) _carryForward(f, old)],
    channelIndex,
  );
}

/// [sections] with every id unique on the channel. A section carried forward
/// from the stored map keeps the id it was stored under; a new section is
/// named by where it starts (`ch1_at42`); a collision is renamed the same way.
///
/// Re-marking a channel used to hand two sections the same id: the compiler
/// names sections by POSITION (`ch1_seg1`), and a section that matched an old
/// range kept the old positional id — so after a corner was added before it,
/// the new section at position 1 and the old `ch1_seg1` sat on the channel
/// together. One delete in Segment Setup then removed both, and the trace
/// merge (which keys by id) brought a deleted one back. Compiling the same
/// marks twice yields the same ids, so a repeated save changes nothing.
List<RooflineSegment> withUniqueSectionIds(
    List<RooflineSegment> sections, int channelIndex) {
  final seen = <String>{};
  final out = <RooflineSegment>[];
  for (final s in sections) {
    if (seen.add(s.id)) {
      out.add(s);
      continue;
    }
    var id = 'ch${channelIndex}_at${s.startPixel}';
    var n = 2;
    while (!seen.add(id)) {
      id = 'ch${channelIndex}_at${s.startPixel}_${n++}';
    }
    out.add(s.copyWith(id: id));
  }
  return out;
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
    // Named by where it starts, not by its position in the list, so it can
    // never collide with a carried-forward positional id (see
    // [withUniqueSectionIds]).
    id: 'ch${f.channelIndex}_at${f.startPixel}',
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

/// The channel's length for the walkthrough — device truth first.
///
///  1. the live strip length, when the controller being marked is the one
///     the app is connected to;
///  2. else the strip length recorded on the channel's map doc
///     (`source_pixel_count`, surfaced as [RooflineConfiguration.channelPixelCounts]);
///  3. else what the stored segments add up to.
///
/// It used to be the stored sum first and the strip only when the map had
/// nothing on the channel. A map that had drifted from the strip (a photo
/// trace's estimated LED count, a segment appended by Segment Setup or
/// Trace) then lit and marked the wrong lights, and every save wrote the
/// drift back as confirmed features. See [mappedLengthOfChannel] for the sum
/// the notice compares against.
int channelLengthForMarking(
  RooflineConfiguration config,
  int channelIndex, {
  int? liveLength,
}) {
  if (liveLength != null && liveLength > 0) return liveLength;
  final recorded = config.channelPixelCounts[channelIndex];
  if (recorded != null && recorded > 0) return recorded;
  return mappedLengthOfChannel(config, channelIndex);
}

/// What the stored segments on [channelIndex] add up to.
int mappedLengthOfChannel(RooflineConfiguration config, int channelIndex) =>
    config
        .segmentsForChannel(channelIndex)
        .fold<int>(0, (sum, s) => sum + s.pixelCount);

// ── Placing and removing marks ──────────────────────────────────────────────

/// [marks] with [mark] placed. One light carries at most one mark, so:
///
///  * the same mark already there → the SAME list comes back (placing a mark
///    twice changes nothing);
///  * a run split on a light that already has a corner or peak → unchanged
///    (the feature already splits the run);
///  * any other mark on that light → replaced (the customer changed their
///    mind about what the light is sitting on).
List<CaptureMark> placeMark(List<CaptureMark> marks, CaptureMark mark) {
  final at = marks.indexWhere((m) => m.pixel == mark.pixel);
  if (at < 0) {
    return [...marks, mark]..sort((a, b) => a.pixel.compareTo(b.pixel));
  }
  final there = marks[at];
  if (_sameMark(there, mark)) return marks;
  if (mark.kind == MarkKind.runBoundary && there.kind != MarkKind.runBoundary) {
    return marks;
  }
  final out = [...marks];
  out[at] = mark;
  return out;
}

bool _sameMark(CaptureMark a, CaptureMark b) =>
    a.pixel == b.pixel &&
    a.kind == b.kind &&
    a.width == b.width &&
    a.slopeLength == b.slopeLength &&
    a.customType == b.customType &&
    a.customRole == b.customRole;

/// The channel-local range `[start, end)` the compiler gives [m]'s feature. A
/// run split covers nothing — it only cuts the run it falls in.
({int start, int end}) markFeatureRange(CaptureMark m, int pixelCount) {
  final p = m.pixel.clamp(0, pixelCount - 1);
  switch (m.kind) {
    case MarkKind.runBoundary:
      return (start: p, end: p);
    case MarkKind.corner:
    case MarkKind.custom:
      final w = m.width < 1 ? 1 : m.width;
      return (start: p, end: (p + w).clamp(0, pixelCount));
    case MarkKind.peak:
      final l = m.slopeLength < 1 ? 1 : m.slopeLength;
      return (
        start: (p - l).clamp(0, pixelCount - 1),
        end: (p + l).clamp(0, pixelCount - 1) + 1,
      );
  }
}

/// Removing one mark so a section merges back into the lights around it.
class SectionRemoval {
  const SectionRemoval({
    required this.mark,
    required this.marksAfter,
    required this.sectionsAfter,
  });

  /// The mark that goes.
  final CaptureMark mark;

  /// The channel's marks without it.
  final List<CaptureMark> marksAfter;

  /// What the channel compiles to without it.
  final List<RooflineSegment> sectionsAfter;
}

/// How to delete [section] from a channel: which single mark to remove so
/// its lights merge into the neighbouring section. Null when no one mark does
/// that — [sectionRemovalBlocker] says why.
///
///  * a corner, peak or other feature → the mark that made it; its lights
///    join the run around it;
///  * a run that starts at a run split → that split; the run joins the run
///    before it;
///  * a run that ends at a run split → that split; the run joins the run
///    after it.
///
/// Decided by compiling the marks without each candidate and checking the
/// section is gone, so it stays right if the compiler's rules change.
SectionRemoval? planSectionRemoval({
  required int channelIndex,
  required int pixelCount,
  required List<CaptureMark> marks,
  required RooflineSegment section,
}) {
  if (pixelCount <= 0 || marks.isEmpty) return null;
  final start = section.startPixel;
  final end = section.startPixel + section.pixelCount;
  final isRun = section.type == SegmentType.run && section.architecturalRole == null;

  final candidates = <int>[];
  for (var i = 0; i < marks.length; i++) {
    final m = marks[i];
    if (isRun) {
      if (m.kind == MarkKind.runBoundary && (m.pixel == start || m.pixel == end)) {
        candidates.add(i);
      }
    } else if (m.kind != MarkKind.runBoundary) {
      final r = markFeatureRange(m, pixelCount);
      if (start >= r.start && start < r.end) candidates.add(i);
    }
  }
  // Merging left (the split at the run's start) before merging right.
  if (isRun) {
    candidates.sort((a, b) {
      final aLeft = marks[a].pixel == start ? 0 : 1;
      final bLeft = marks[b].pixel == start ? 0 : 1;
      return aLeft.compareTo(bLeft);
    });
  }

  for (final i in candidates) {
    final after = [...marks]..removeAt(i);
    final compiled = compileMarksToChannelSegments(
      channelIndex: channelIndex,
      pixelCount: pixelCount,
      marks: after,
    );
    final stillThere = compiled.any((s) =>
        s.startPixel == start &&
        s.pixelCount == section.pixelCount &&
        s.type == section.type &&
        s.architecturalRole == section.architecturalRole);
    if (!stillThere) {
      return SectionRemoval(
          mark: marks[i], marksAfter: after, sectionsAfter: compiled);
    }
  }
  return null;
}

/// Why [section] cannot be merged away by removing one mark. Null when it can.
String? sectionRemovalBlocker({
  required int channelIndex,
  required int pixelCount,
  required List<CaptureMark> marks,
  required RooflineSegment section,
}) {
  if (marks.isEmpty) return 'This channel is already one straight run.';
  final plan = planSectionRemoval(
    channelIndex: channelIndex,
    pixelCount: pixelCount,
    marks: marks,
    section: section,
  );
  if (plan != null) return null;
  final isRun = section.type == SegmentType.run && section.architecturalRole == null;
  if (isRun) {
    return 'This run sits between marked features. Remove the corner or peak '
        'next to it to merge them.';
  }
  return 'This section comes from the saved map. Save the channel once to '
      'rebuild it, then remove it.';
}

/// What "Start over" on a channel removes, for its confirmation.
({int corners, int peaks, int splits, int other}) marksSummary(
    List<CaptureMark> marks) {
  var corners = 0, peaks = 0, splits = 0, other = 0;
  for (final m in marks) {
    switch (m.kind) {
      case MarkKind.corner:
        corners++;
      case MarkKind.peak:
        peaks++;
      case MarkKind.runBoundary:
        splits++;
      case MarkKind.custom:
        other++;
    }
  }
  return (corners: corners, peaks: peaks, splits: splits, other: other);
}
