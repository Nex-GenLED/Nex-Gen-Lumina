/// Assigns an ordered, flat list of roofline segments to hardware channels.
///
/// The Roofline Setup Wizard collects segments as ONE ordered list (the way an
/// installer walks the roof) plus an LED count per active channel. It used to
/// save every segment with no channel at all — so on a multi-channel home the
/// whole roof landed on channel 1, overflowing it, and channel 2+ had nothing
/// for the editor's tools to act on (design-studio-followup-2026-09-19 N1c).
///
/// Pure + deterministic so it can be tested without the wizard.
library;

class ChannelAssignment {
  /// 0-based hardware channel index for each input segment, same order.
  final List<int> channelIndexBySegment;

  /// Non-null when the segments cannot be laid onto the channels as given —
  /// a segment straddles a channel boundary. Human-readable, installer-facing.
  final String? error;

  const ChannelAssignment(this.channelIndexBySegment, [this.error]);

  bool get isValid => error == null;
}

/// Walks [segmentLedCounts] across [channelLedCounts] (both in physical
/// order). A segment must sit entirely inside one channel: a strip cannot
/// continue across two controller outputs, so a straddling segment is a data
/// entry mistake and is reported rather than guessed at.
///
/// With zero or one usable channel everything is channel 0. LEDs beyond the
/// last channel's length stay on the last channel (the pixel-count mismatch is
/// surfaced separately by the map's fit check, not here).
ChannelAssignment assignSegmentsToChannels({
  required List<int> segmentLedCounts,
  required List<int> channelLedCounts,
  List<String> segmentNames = const [],
}) {
  final usable = channelLedCounts.where((c) => c > 0).length;
  if (usable <= 1) {
    // Single channel: index of the one usable channel (or 0).
    final only = channelLedCounts.indexWhere((c) => c > 0);
    return ChannelAssignment(
        List<int>.filled(segmentLedCounts.length, only < 0 ? 0 : only));
  }

  final out = <int>[];
  final last = channelLedCounts.length - 1;
  int ch = 0;
  int remaining = channelLedCounts[0];
  int walked = 0; // LEDs consumed on the current channel

  for (int i = 0; i < segmentLedCounts.length; i++) {
    final count = segmentLedCounts[i];
    // Step over exhausted (or empty) channels.
    while (remaining <= 0 && ch < last) {
      ch++;
      remaining = channelLedCounts[ch];
      walked = 0;
    }
    if (count > remaining && ch < last) {
      final name = i < segmentNames.length && segmentNames[i].isNotEmpty
          ? '"${segmentNames[i]}"'
          : 'Segment ${i + 1}';
      return ChannelAssignment(
        out,
        '$name ($count LEDs) runs past the end of Channel ${ch + 1} '
        '(only $remaining of its ${channelLedCounts[ch]} LEDs are left after '
        'LED $walked). A segment has to sit on one channel — split it into '
        '$remaining + ${count - remaining} LEDs, or correct the channel '
        'LED counts.',
      );
    }
    out.add(ch);
    remaining -= count;
    walked += count;
  }
  return ChannelAssignment(out);
}
