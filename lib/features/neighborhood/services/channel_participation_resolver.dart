import 'package:nexgen_command/models/roofline_segment.dart';

/// Resolves which channel indices participate in a Neighborhood Sync or
/// Game Day show for the LOCAL user's own controller.
///
/// This is a PURE function — no Riverpod, no Firestore, no I/O — so the
/// same logic can be called from the foreground engine and mirrored into
/// the background isolate (which is locked to SharedPreferences and cannot
/// resolve providers).
///
/// Policy:
///
/// 1. If [explicit] is non-null, it is returned verbatim. The user's
///    picker choice (or trace-time selection) always wins, even if it
///    names channels the device doesn't currently report. Validation of
///    channel ids against the live device is the apply-site's job, not
///    the resolver's. **An explicit list that omits a channel still
///    excludes that channel** — explicit exclusions take precedence over
///    the untraced-default-in policy below.
///
/// 2. If [explicit] is null and [segments] is empty (untraced install),
///    every channel in [allDeviceChannelIds] participates. This is the
///    backward-safe fallback for users who have a controller but have
///    never run the design wizard — without it, sync would silently no-op
///    for them.
///
/// 3. If [explicit] is null and [segments] is non-empty, the default
///    policy (Lever 2, 2026-05-23) is:
///      • channels with at least one isPrimary segment PARTICIPATE
///      • channels with segments but NO isPrimary segment are EXCLUDED
///        (the user signaled "secondary only" on this channel)
///      • channels in [allDeviceChannelIds] with NO segment at all
///        ("untraced" — patio, accent, side strip) PARTICIPATE.
///    The untraced-default-in branch is the Lever 2 fix: real installs
///    routinely have controller channels that aren't part of the traced
///    roofline geometry but are still intended to be in shows. Excluding
///    them silently (the pre-2026-05-23 behavior) made the channel
///    disappear from sync/Game Day with no UI signal.
///
/// The returned list is sorted ascending by channel id when produced by
/// the default policy. Explicit lists are returned in the order supplied.
List<int> resolveParticipatingChannels({
  required List<int>? explicit,
  required List<RooflineSegment> segments,
  required List<int> allDeviceChannelIds,
}) {
  if (explicit != null) return explicit;

  if (segments.isEmpty) {
    return List<int>.from(allDeviceChannelIds);
  }

  final tracedChannels = <int>{};
  final primaryChannels = <int>{};
  for (final seg in segments) {
    tracedChannels.add(seg.channelIndex);
    if (seg.isPrimary) primaryChannels.add(seg.channelIndex);
  }

  // Untraced device channels (present on the controller, absent from the
  // roofline) default to participating. When the device hasn't been seen
  // (allDeviceChannelIds is empty — e.g. resolver fired before the
  // /json/cfg fetch settled), this set is empty and only the primary-
  // derived channels are returned; the next resolution after the device
  // is reachable will include the untraced ones.
  final untracedDeviceChannels =
      allDeviceChannelIds.toSet().difference(tracedChannels);

  final result = primaryChannels.union(untracedDeviceChannels).toList()..sort();
  return result;
}
