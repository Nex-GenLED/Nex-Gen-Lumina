// Lumina AI → every participating channel (#163).
//
// A Lumina reply is ONE look for the house. The builders and the cloud model
// hand it over in several shapes: a single segment pinned to `id: 0` (the
// team, holiday and multi-night builders), a bare segment object, a single
// id-less segment. Only the last was ever fanned out. An explicit id passes
// both the apply funnel and the participation chokepoint as "segment 0
// specifically", and a bare object lands on WLED's selected segment, so on a
// three-channel controller the other two channels kept their old look while
// the reply, the Home preview and Now Playing all showed the new one.
//
// These helpers are pure; `WledNotifier.applyLuminaDesign` puts them together
// with the channel census.

import 'package:nexgen_command/features/wled/device_channel.dart';

/// The keys of a Lumina payload that belong on the wire. Everything else
/// (`patternName`, `colors`, `effect`, …) is display metadata and never rides
/// to the controller.
const Set<String> kLuminaDeviceKeys = {
  'on',
  'bri',
  'seg',
  'transition',
  'tt',
  'ps',
  'pl',
};

/// PURE. The device part of [lumina]: a payload nested under `wled` is
/// unwrapped, then only [kLuminaDeviceKeys] are kept.
Map<String, dynamic> luminaDevicePayload(Map<String, dynamic> lumina) {
  final wled = lumina['wled'];
  final source = wled is Map ? Map<String, dynamic>.from(wled) : lumina;
  return {
    for (final e in source.entries)
      if (kLuminaDeviceKeys.contains(e.key)) e.key: e.value,
  };
}

/// PURE. The look of a single-look payload as one segment TEMPLATE: the
/// segment's own fields with its `id`, its geometry and its `on` removed (the
/// apply states those per channel). Null when [device] is not a single look:
/// no `seg` (a power or brightness change, which acts on the whole controller)
/// or several segments (a scene that states each channel itself).
Map<String, dynamic>? luminaSingleLookTemplate(Map<String, dynamic> device) {
  final seg = device['seg'];
  Map? only;
  if (seg is Map) {
    only = seg;
  } else if (seg is List && seg.length == 1 && seg.first is Map) {
    only = seg.first as Map;
  }
  if (only == null) return null;
  return {
    for (final e in only.entries)
      if (!const {'id', 'start', 'stop', 'rev', 'mi', 'on'}.contains(e.key))
        '${e.key}': e.value,
  };
}

/// PURE. [device] with its `seg` replaced by one fully stated segment per
/// channel in [targets]: the template's look, the channel's `id`, `on: true`.
/// Nothing is said about channels outside [targets] — the same rule as the
/// design apply spine (a channel the look is not for keeps what it has).
Map<String, dynamic> luminaPayloadForChannels(
  Map<String, dynamic> device,
  Map<String, dynamic> template,
  List<int> targets,
) {
  final ids = [...targets]..sort();
  return {
    for (final e in device.entries)
      if (e.key != 'seg') e.key: e.value,
    'seg': [
      for (final id in ids) <String, dynamic>{'id': id, ...template, 'on': true},
    ],
  };
}

/// PURE. The line a reply card shows for a look SENT to [sent], out of the
/// controller's [census]. Derived from what was written, never assumed:
/// "All 3 channels" when every channel got it, otherwise the channels by
/// name. A one-channel controller reads "Your lights".
String luminaChannelsLabel(List<int> sent, List<DeviceChannel> census) {
  final ids = [...sent]..sort();
  final censusIds = census.map((c) => c.id).toSet();
  if (census.length <= 1 && ids.length <= 1) return 'Your lights';
  if (ids.length == censusIds.length && ids.toSet().containsAll(censusIds)) {
    return 'All ${ids.length} channels';
  }
  final names = [
    for (final id in ids)
      census
              .where((c) => c.id == id)
              .map((c) => c.name.trim())
              .where((n) => n.isNotEmpty)
              .firstOrNull ??
          'Channel ${id + 1}',
  ];
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}
