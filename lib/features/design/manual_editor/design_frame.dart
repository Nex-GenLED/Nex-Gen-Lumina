import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// Design Studio Slice 4 (1b) — the mode-agnostic per-LED color FRAME that the
/// unified preview renders. `channelIndex → per-LED colors (channel-local)`.
/// Both authoring modes are just producers of this frame:
///   • manual editor → [frameFromDocument]
///   • AI studio     → [frameFromGlobalGroups] (ComposedPattern groups are
///     global-indexed; mapped to channel-local via the device bus offsets)
typedef DesignFrame = Map<int, List<Color>>;

/// The manual document's per-LED colors (already channel-local).
DesignFrame frameFromDocument(PixelDesignDocument doc) {
  final frame = <int, List<Color>>{};
  for (final ch in doc.channelLengths.keys) {
    final len = doc.channelLength(ch);
    frame[ch] = [
      for (int i = 0; i < len; i++) _toColor(doc.colorAt(ch, i)),
    ];
  }
  return frame;
}

/// Maps GLOBAL-indexed [groups] (AI ComposedPattern) onto per-channel frames
/// using each [DeviceChannel]'s global `[start, stop)` window. Unpainted LEDs
/// take [base]. When [channels] is empty, returns a single channel-0 frame of
/// length [fallbackLength] (global == local for single-bus installs).
DesignFrame frameFromGlobalGroups({
  required List<LedColorGroup> groups,
  required List<DeviceChannel> channels,
  Color base = Colors.black,
  int fallbackLength = 0,
}) {
  Color colorAtGlobal(int g) {
    for (final grp in groups) {
      if (g >= grp.startLed && g <= grp.endLed) return _toColor(grp.color);
    }
    return base;
  }

  if (channels.isEmpty) {
    return {
      0: [for (int g = 0; g < fallbackLength; g++) colorAtGlobal(g)],
    };
  }
  final frame = <int, List<Color>>{};
  for (final ch in channels) {
    final len = (ch.stop - ch.start).clamp(0, 100000);
    frame[ch.id] = [
      for (int local = 0; local < len; local++) colorAtGlobal(ch.start + local),
    ];
  }
  return frame;
}

Color _toColor(List<int> rgbw) {
  if (rgbw.length >= 3) {
    // Blend a little of the W channel into RGB so the on-screen dot reads warm
    // when W is high (screens have no W primary).
    final w = rgbw.length >= 4 ? rgbw[3] : 0;
    int mix(int c, int warm) => (c + warm * (w / 255.0) * 0.6).round().clamp(0, 255);
    return Color.fromARGB(255, mix(rgbw[0], 255), mix(rgbw[1], 235), mix(rgbw[2], 200));
  }
  return Colors.black;
}

/// A stored [CustomDesign]'s per-channel color groups → a preview frame.
///
/// Third producer alongside [frameFromDocument] (manual authoring) and
/// [frameFromGlobalGroups] (AI authoring): this one reads a design back OFF
/// Firestore for the read-only detail preview. Groups on a saved design are
/// already channel-local — reconciled at save time, the same invariant
/// `customDesignToSpans` relies on (design_apply.dart:85-93) — so they map
/// straight to channel-local indices with no re-projection.
///
/// [channelLengths] comes from the connected device (`deviceChannelsProvider`).
/// When it is empty (no device / off-LAN) each channel falls back to its own
/// stored `ChannelDesign.ledCount`, so the detail screen still previews a
/// design while disconnected. Excluded channels are omitted entirely — an
/// absent key is how the frame expresses "this channel is not in scope",
/// matching [DesignPreview]'s `frame[ch] == null → no LEDs` handling.
///
/// NO new pixel logic: base fill + last-group-wins is exactly
/// [frameFromGlobalGroups]'s rule, and [_toColor] is shared verbatim.
DesignFrame frameFromCustomDesign(
  CustomDesign design, {
  Map<int, int> channelLengths = const {},
  Color base = Colors.black,
}) {
  final frame = <int, List<Color>>{};
  for (final ch in design.channels) {
    if (!ch.included) continue;
    final len = channelLengths[ch.channelId] ?? ch.ledCount;
    if (len <= 0) continue;
    Color colorAtLocal(int i) {
      for (final grp in ch.colorGroups) {
        if (i >= grp.startLed && i <= grp.endLed) return _toColor(grp.color);
      }
      return base;
    }

    frame[ch.channelId] = [for (int i = 0; i < len; i++) colorAtLocal(i)];
  }
  return frame;
}
