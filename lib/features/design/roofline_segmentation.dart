import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

// "Is this roofline segmented?" — the question Design Studio asks before it
// lets a customer select by architectural feature (corner, peak, run). The
// gate itself belongs to Design Studio; this file only answers the question.
//
// Where the answer comes from. Every pixel-map segment already stores two
// feature fields:
//   * `type` (SegmentType: run, corner, peak, column, connector). It defaults
//     to `run` on EVERY segment, so `run` on its own proves nothing.
//   * `architectural_role` (ArchitecturalRole, optional). Only the installer's
//     Map Roofline step and the installer Roofline Setup Wizard set it.
// plus, from +110, `feature_confirmed` — a person deliberately said what the
// segment is (the feature walkthrough, Segment Setup's type picker, the
// Roofline Setup Wizard).

/// What a segment is, as one answer. `type` and `architectural_role` can
/// disagree on older maps; the role wins when it names one of these kinds.
enum RooflineFeatureKind { run, corner, peak, column, connector }

RooflineFeatureKind featureKindOf(RooflineSegment s) {
  switch (s.architecturalRole) {
    case ArchitecturalRole.corner:
      return RooflineFeatureKind.corner;
    case ArchitecturalRole.peak:
      return RooflineFeatureKind.peak;
    case ArchitecturalRole.column:
      return RooflineFeatureKind.column;
    default:
      break;
  }
  switch (s.type) {
    case SegmentType.run:
      return RooflineFeatureKind.run;
    case SegmentType.corner:
      return RooflineFeatureKind.corner;
    case SegmentType.peak:
      return RooflineFeatureKind.peak;
    case SegmentType.column:
      return RooflineFeatureKind.column;
    case SegmentType.connector:
      return RooflineFeatureKind.connector;
  }
}

/// True when someone deliberately said what this segment is. A plain `run`
/// with no role and no confirmation is the default every writer stamps, not
/// a named feature.
bool isNamedFeature(RooflineSegment s) =>
    s.featureConfirmed ||
    s.architecturalRole != null ||
    s.type != SegmentType.run;

/// True when a channel's segments have been marked as features. One named
/// feature marks the whole channel: the installer's Map Roofline walk names
/// only the corners and peaks and infers the runs between them.
bool isChannelFeatureMarked(Iterable<RooflineSegment> channelSegments) =>
    channelSegments.any(isNamedFeature);

/// The answer to "is this roofline segmented?".
class RooflineSegmentation {
  const RooflineSegmentation({
    required this.markedChannels,
    required this.unmarkedChannels,
    required this.featureCounts,
  });

  /// No roofline map at all.
  static const RooflineSegmentation none = RooflineSegmentation(
    markedChannels: [],
    unmarkedChannels: [],
    featureCounts: {},
  );

  /// Channels (0-based) whose segments are marked as features.
  final List<int> markedChannels;

  /// Channels (0-based) that have a map but no named features yet.
  final List<int> unmarkedChannels;

  /// How many segments of each kind the marked channels hold.
  final Map<RooflineFeatureKind, int> featureCounts;

  bool get hasMap => markedChannels.isNotEmpty || unmarkedChannels.isNotEmpty;

  /// THE GATE ANSWER: there is a map, and every mapped channel is marked.
  bool get isSegmented => hasMap && unmarkedChannels.isEmpty;

  /// Some channels are marked and some are not.
  bool get isPartlySegmented =>
      markedChannels.isNotEmpty && unmarkedChannels.isNotEmpty;

  int get corners => featureCounts[RooflineFeatureKind.corner] ?? 0;
  int get peaks => featureCounts[RooflineFeatureKind.peak] ?? 0;
  int get runs => featureCounts[RooflineFeatureKind.run] ?? 0;

  @override
  String toString() => 'RooflineSegmentation(segmented: $isSegmented, '
      'marked: $markedChannels, unmarked: $unmarkedChannels, $featureCounts)';
}

/// Assesses a roofline map. Null or empty → [RooflineSegmentation.none].
RooflineSegmentation assessRooflineSegmentation(RooflineConfiguration? config) {
  if (config == null || config.segments.isEmpty) {
    return RooflineSegmentation.none;
  }
  final marked = <int>[];
  final unmarked = <int>[];
  final counts = <RooflineFeatureKind, int>{};
  for (final ch in config.allChannelIndices) {
    final segs = config.segmentsForChannel(ch);
    if (segs.isEmpty) continue;
    if (isChannelFeatureMarked(segs)) {
      marked.add(ch);
      for (final s in segs) {
        final kind = featureKindOf(s);
        counts[kind] = (counts[kind] ?? 0) + 1;
      }
    } else {
      unmarked.add(ch);
    }
  }
  return RooflineSegmentation(
    markedChannels: marked,
    unmarkedChannels: unmarked,
    featureCounts: counts,
  );
}

/// Assesses the stored per-channel pixel-map documents directly.
RooflineSegmentation assessPixelMapChannels(List<PixelMapChannel> channels) {
  if (channels.isEmpty) return RooflineSegmentation.none;
  return assessRooflineSegmentation(
    aggregatePixelMapChannelsToConfig(channels.first.controllerId, channels),
  );
}

/// Segmentation of the roofline the rest of the app reads
/// ([currentRooflineConfigProvider]: the selected controller's map). Loading
/// and errors come through as such, so a gate can tell "not yet known" from
/// "not segmented".
final rooflineSegmentationProvider =
    Provider<AsyncValue<RooflineSegmentation>>((ref) {
  return ref
      .watch(currentRooflineConfigProvider)
      .whenData(assessRooflineSegmentation);
});

/// Segmentation of one named controller's roofline, for a caller that knows
/// which controller it is asking about.
final rooflineSegmentationForControllerProvider =
    StreamProvider.family<RooflineSegmentation, String>((ref, controllerId) {
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null || uid.isEmpty) {
    return Stream.value(RooflineSegmentation.none);
  }
  return ref
      .read(rooflineConfigServiceProvider)
      .streamPixelMapChannels(uid, controllerId)
      .map(assessPixelMapChannels);
});
