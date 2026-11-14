import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart'
    show liveDesignLayoutStamp;
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/wled/brightness_tile.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// How a brightness tile reaches the lights and how it is kept.
///
/// A tile is a per-pixel picture (brightness_tile.dart says why), so it
/// travels the Design Studio spine — a solid base write, then every channel's
/// pixels as range-compressed `i` chunks — to EVERY channel the controller
/// has (kept to the census and to the channels not set aside), the same
/// targeting a painted design gets. It is never pushed through
/// `applyChannelFilter`: a template segment cannot carry a per-pixel frame,
/// and the frame depends on each bus's length.
///
/// Kept, a tile is a painted [CustomDesign] (`perPixel: true`, stamped for the
/// buses it was laid over), so My Designs, Favorites and the schedule picker
/// treat it exactly as they treat a design painted by hand — including the
/// painted-design scheduling rules (design_api_preset.dart).

/// Channel id → bus length, from the LAN config read.
Map<int, int> liveChannelLengths(ProviderReader read) => {
      for (final c in read(deviceChannelsProvider))
        c.id: (c.stop - c.start).clamp(0, 100000),
    };

/// Paints [tile] in [baseRgbw] on every channel. [label] is the Now Playing
/// label on full success; [brightness] is stated only when a level was
/// actually chosen (the house otherwise keeps its own).
Future<SpineWriteResult> applyBrightnessTileWith(
  ProviderReader read, {
  required BrightnessTile tile,
  required List<int> baseRgbw,
  String? label,
  int? brightness,
}) async {
  final lengths = liveChannelLengths(read);
  if (lengths.isEmpty) return SpineWriteResult.noChannels;
  final targets = designTargetChannels(read, lengths.keys);
  if (targets.isEmpty) return SpineWriteResult.noChannels;
  return applyBaseAndSpansWith(
    read,
    baseRgbw: baseRgbw,
    spansByChannel: {
      for (final id in targets)
        id: brightnessTileSpans(tile, baseRgbw, lengths[id]!),
    },
    label: label,
    brightness: brightness,
    targetChannels: targets,
  );
}

/// The per-channel colour groups a tile paints over [channelLengths]:
/// full coverage, one group per run of equal brightness.
List<ChannelDesign> brightnessTileChannels(
  BrightnessTile tile,
  List<int> baseRgbw,
  Map<int, int> channelLengths,
) {
  final ids = channelLengths.keys.toList()..sort();
  return [
    for (final id in ids)
      if (channelLengths[id]! > 0)
        ChannelDesign(
          channelId: id,
          channelName: 'Channel ${id + 1}',
          ledCount: channelLengths[id]!,
          colorGroups: [
            for (final s in brightnessTileSpans(tile, baseRgbw, channelLengths[id]!))
              LedColorGroup(startLed: s.start, endLed: s.end, color: s.color),
          ],
        ),
  ];
}

/// The painted design a tile becomes when saved to My Designs. [brightness]
/// is the live master level when the controller is connected (recorded so the
/// design comes back at the level it was made under), else the model default.
CustomDesign brightnessTileDesign(
  ProviderReader read, {
  required String name,
  required String ownerId,
  required BrightnessTile tile,
  required List<int> baseRgbw,
  int? brightness,
}) {
  final lengths = liveChannelLengths(read);
  final now = DateTime.now();
  return CustomDesign(
    id: '',
    name: name,
    description: 'Brightness pattern · ${tile.levels.join(' / ')} %',
    createdAt: now,
    updatedAt: now,
    ownerId: ownerId,
    channels: brightnessTileChannels(tile, baseRgbw, lengths),
    brightness: brightness ?? 200,
    brightnessStated: brightness != null,
    perPixel: true,
    tags: const ['brightness_pattern'],
    layoutStamp: liveDesignLayoutStamp(read),
  );
}
