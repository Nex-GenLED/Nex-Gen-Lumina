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
///    the resolver's.
///
/// 2. If [explicit] is null and [segments] is empty (untraced install),
///    every channel in [allDeviceChannelIds] participates. This is the
///    backward-safe fallback for users who have a controller but have
///    never run the design wizard — without it, sync would silently no-op
///    for them.
///
/// 3. If [explicit] is null and [segments] is non-empty, a channel
///    participates iff at least one of its segments has `isPrimary == true`.
///    A channel with no segments at all is excluded by this rule (it has
///    no primary segment) — this is intentional for partially-traced
///    installs, but flagged in Bundle 1's test Case 4 for Tyler to
///    confirm before Bundle 3 wires this into the apply path.
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

  final participating = <int>{};
  for (final seg in segments) {
    if (seg.isPrimary) participating.add(seg.channelIndex);
  }
  final result = participating.toList()..sort();
  return result;
}
