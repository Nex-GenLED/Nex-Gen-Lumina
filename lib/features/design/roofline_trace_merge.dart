import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// LED count given to a NEW traced segment the photo trace could not
/// estimate. (Existing segments always keep their stored count.)
const int kNewTracedSegmentFallbackCount = 30;

/// Row 71 (+110): merges a photo trace into the stored roofline map.
///
/// "Finish" on Trace Roofline used to delete EVERY stored segment — including
/// installer-mapped ones the editor never showed, because they have no photo
/// points — and re-add only the traced ones with estimated LED counts and no
/// anchors. One tap silently replaced the installed pixel map.
///
/// The merge instead:
///  * keeps every stored segment the trace did not show (no photo points)
///    exactly as stored;
///  * for a stored segment that was traced, updates ONLY its photo points
///    (and label / story level). Its LED count, start, channel, anchors,
///    type, architectural role and feature confirmation are kept;
///  * removes a stored segment only when it was shown in the trace and the
///    customer deleted it there;
///  * appends a NEW traced segment (one the store has never seen) at the end
///    of its channel, with the trace's estimated count.
///
/// Stored order is kept: the order of segments along a channel is the order
/// of the LEDs on the strip, which reordering outlines on a photo cannot
/// change. Start pixels are rebased per channel when the map is saved.
///
/// [shownInEditor] is the ids of the stored segments the trace editor was
/// given (those with photo points).
RooflineConfiguration mergeTraceIntoRoofline({
  required RooflineConfiguration stored,
  required List<RooflineSegment> traced,
  required Set<String> shownInEditor,
}) {
  final tracedById = {for (final t in traced) t.id: t};
  final storedIds = {for (final s in stored.segments) s.id};
  final merged = <RooflineSegment>[];

  for (final s in stored.segments) {
    final t = tracedById[s.id];
    if (t != null) {
      merged.add(s.copyWith(points: t.points, name: t.name, level: t.level));
    } else if (!shownInEditor.contains(s.id)) {
      merged.add(s);
    }
    // else: shown in the trace and deleted there by the customer.
  }

  for (final t in traced) {
    if (storedIds.contains(t.id)) continue;
    merged.add(t.copyWith(
      pixelCount:
          t.pixelCount > 0 ? t.pixelCount : kNewTracedSegmentFallbackCount,
    ));
  }

  // Group by channel in first-appearance order, keeping order within each
  // channel, then renumber.
  final channelOrder = <int>[];
  for (final s in merged) {
    if (!channelOrder.contains(s.channelIndex)) {
      channelOrder.add(s.channelIndex);
    }
  }
  final ordered = <RooflineSegment>[
    for (final ch in channelOrder) ...merged.where((s) => s.channelIndex == ch),
  ];
  return stored.copyWith(segments: [
    for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortOrder: i),
  ]);
}
