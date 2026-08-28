// Pure-Dart (no flutter / dart:ui) channel model + bus→channel derivation,
// extracted from zone_providers.dart so the bench/ CLI and buildChannelPowerPayload
// can resolve channels without pulling in Riverpod / flutter/material.
// zone_providers.dart re-exports these, so existing importers are unaffected.

import 'package:nexgen_command/features/wled/wled_hardware_config.dart';

/// A logical channel derived from hardware bus configuration.
/// Each WLED bus (GPIO output) maps to one channel with a defined LED range.
class DeviceChannel {
  final int id; // bus index (0, 1, ...)
  final String name; // "Channel 1", "Channel 2"
  final int start; // LED start index (inclusive)
  final int stop; // LED stop index (exclusive)
  final int gpioPin; // GPIO pin number

  const DeviceChannel({
    required this.id,
    required this.name,
    required this.start,
    required this.stop,
    required this.gpioPin,
  });
}

/// Pure bus → channel derivation: each WLED bus (`hw.led.ins[]` entry) becomes
/// one [DeviceChannel] with its LED range and GPIO pin. Shared by
/// `deviceChannelsProvider` (UI isolate, via Riverpod) and the Riverpod-free
/// paths that must resolve channels straight from a [WledHardwareConfig] —
/// e.g. `AlertTriggerService` resolving each controller's channels inside the
/// background isolate, and the bench/ CLI, where no provider container exists.
///
/// Returns an empty list for a null/empty config (caller treats that as the U1
/// "nothing to target" gate). Keep this in lockstep with `deviceChannelsProvider`.
List<DeviceChannel> deviceChannelsFromConfig(WledHardwareConfig? hwConfig) {
  if (hwConfig == null || hwConfig.buses.isEmpty) return const [];
  return hwConfig.buses.asMap().entries.map((e) {
    final i = e.key;
    final bus = e.value;
    return DeviceChannel(
      id: i,
      name: 'Channel ${i + 1}',
      start: bus.start,
      stop: bus.start + bus.len,
      gpioPin: bus.pin.isNotEmpty ? bus.pin.first : -1,
    );
  }).toList();
}

// ---------------------------------------------------------------------------
// DISPLAY-ONLY channel fallbacks (#91, remote channels)
// ---------------------------------------------------------------------------
//
// `deviceChannelsFromConfig` above is DEVICE TRUTH: it reads `hw.led.ins[]`
// from `/json/cfg`, which only `WledService` can fetch. `CloudRelayRepository`
// has no cfg door at all (`getConfig() async => null`, and the bridge firmware
// dispatches only `getState`/`getInfo`), so off-LAN the bus list is null, every
// derivation collapses to `[]`, and the dashboard shows NO CHANNELS while
// whole-controller commands keep working.
//
// The builders below reconstruct a channel list for DISPLAY from sources that
// ARE readable off-LAN. They are deliberately separate from
// `deviceChannelsFromConfig` and feed only `displayChannelsProvider` — nothing
// here may ever reach the healer, the facts publisher, or a staleness check,
// which need device truth or nothing. See P2-63.
//
// WHAT IS SAFE TO DERIVE FROM THESE. Per-channel writes emit `id` + intent and
// NEVER bounds (#95 for power, #89 for `applyChannelFilter`), so an approximate
// `start`/`stop` cannot reach the wire. Callers that DISPLAY a range must still
// check the source tag — see `DisplayChannelSource`.

/// Where a [DisplayChannels] list came from, best first.
///
/// Only [live] is device truth. The rest are caches or live-state inference and
/// carry known inaccuracies, documented per-value.
enum DisplayChannelSource {
  /// `/json/cfg hw.led.ins[]` via `deviceChannelsFromConfig`. Bounds and GPIO
  /// pins are exact.
  live,

  /// `controllers/{id}/pixelMap/{n}` docs. Channel ids and per-channel LENGTHS
  /// are device-truth-at-map-time; `start`/`stop` are a cumulative sum and are
  /// therefore only correct for contiguous ascending buses. GPIO unknown.
  pixelMap,

  /// `controllers/{id}.participating_channels_device_ids`. Ids only — no
  /// lengths, no bounds, no pins.
  participation,

  /// `seg[]` from a live `/json/state` (relayable through the bridge). Bounds
  /// are real, but the list reflects the device's CURRENT segment layout, which
  /// collapses to a single seg0 after a reboot until a preset reloads.
  segments,

  /// Nothing was available.
  none,
}

/// A channel list plus the provenance of the list itself.
///
/// Display-only. Consumers that act on hardware must keep using
/// `deviceChannelsProvider`; consumers that DRAW must check [isLive] before
/// presenting a value as measured.
class DisplayChannels {
  final List<DeviceChannel> channels;
  final DisplayChannelSource source;

  const DisplayChannels(this.channels, this.source);

  /// Nothing available from any tier.
  static const DisplayChannels empty =
      DisplayChannels(<DeviceChannel>[], DisplayChannelSource.none);

  /// True only for [DisplayChannelSource.live] — i.e. bounds and pins are real.
  bool get isLive => source == DisplayChannelSource.live;

  /// True when this list carries a real per-channel LED count. False for
  /// [DisplayChannelSource.participation], which knows ids and nothing else.
  bool get hasLengths =>
      source == DisplayChannelSource.live ||
      source == DisplayChannelSource.pixelMap ||
      source == DisplayChannelSource.segments;

  bool get isEmpty => channels.isEmpty;
  bool get isNotEmpty => channels.isNotEmpty;
  int get length => channels.length;

  @override
  String toString() =>
      'DisplayChannels(${channels.length} from ${source.name})';
}

/// Build a display channel list from per-channel pixel COUNTS — the
/// `source_pixel_count` on each `pixelMap/{channelIndex}` doc, which was itself
/// captured from the live `WledLedBus.len` at map time.
///
/// Channels are emitted in ascending index order and `start` is a running sum
/// of the preceding lengths. That reconstruction is exact only when the buses
/// are contiguous and ascending — the fleet's shape today, but not a guarantee,
/// which is why the result is tagged [DisplayChannelSource.pixelMap] rather
/// than passed off as device truth. A gap in the doc set (channel 1 mapped,
/// channel 0 never mapped) shifts every subsequent offset; ids stay correct.
///
/// `gpioPin` is -1 throughout: a pixel map does not record wiring.
List<DeviceChannel> deviceChannelsFromPixelCounts(
    Map<int, int> lengthByChannelIndex) {
  if (lengthByChannelIndex.isEmpty) return const [];
  final indices = lengthByChannelIndex.keys.toList()..sort();
  final out = <DeviceChannel>[];
  var cursor = 0;
  for (final index in indices) {
    final len = lengthByChannelIndex[index] ?? 0;
    final safeLen = len < 0 ? 0 : len;
    out.add(DeviceChannel(
      id: index,
      name: 'Channel ${index + 1}',
      start: cursor,
      stop: cursor + safeLen,
      gpioPin: -1,
    ));
    cursor += safeLen;
  }
  return out;
}

/// Merge a channel-ID census with whatever per-channel LENGTHS are known —
/// the #92 completeness fix for the gap #91 shipped with.
///
/// **The gap, concretely.** #91's precedence took the pixel-map tier on
/// PRESENCE. A real venue (`YcSGiwes…`) has
/// `participating_channels_device_ids: [0, 1, 2]` but only ONE pixelMap doc
/// (`pixelMap/0`), because only channel 0 was ever mapped. Tier 2 therefore
/// "won" with a single channel, the selector bar hid itself at its
/// `length <= 1` guard, and that account still saw no channels off-LAN — the
/// exact symptom #91 set out to fix. The id census knew there were three.
///
/// [ids] is the census and decides WHICH channels exist; it is never narrowed
/// by what the pixel map happens to cover. [lengthByChannelIndex] contributes
/// a length wherever it has one. Channels are emitted in ascending id order
/// with `start` as a running sum of the lengths known SO FAR — so a channel
/// whose length is unknown contributes zero and does not shift the ones after
/// it by a guessed amount.
///
/// The caller decides the provenance tag: `pixelMap` only when the map covers
/// every id (see [pixelMapCoversAll]); otherwise `participation`, because a
/// partially-mapped list cannot honestly claim per-channel lengths.
List<DeviceChannel> mergeChannelIdsWithPixelCounts({
  required List<int> ids,
  required Map<int, int> lengthByChannelIndex,
}) {
  if (ids.isEmpty) return const [];
  final unique = ids.toSet().toList()..sort();
  final out = <DeviceChannel>[];
  var cursor = 0;
  for (final id in unique) {
    final raw = lengthByChannelIndex[id] ?? 0;
    final len = raw < 0 ? 0 : raw;
    out.add(DeviceChannel(
      id: id,
      name: 'Channel ${id + 1}',
      start: cursor,
      stop: cursor + len,
      gpioPin: -1,
    ));
    cursor += len;
  }
  return out;
}

/// True when [lengthByChannelIndex] has an entry for EVERY id in [ids] — the
/// condition under which a merged list may still be tagged
/// [DisplayChannelSource.pixelMap] rather than demoted to
/// [DisplayChannelSource.participation].
///
/// An empty census is not "covered": there is nothing to be complete about.
bool pixelMapCoversAll({
  required List<int> ids,
  required Map<int, int> lengthByChannelIndex,
}) {
  if (ids.isEmpty) return false;
  return ids.toSet().every(lengthByChannelIndex.containsKey);
}

/// Build a display channel list from bare channel IDS — the
/// `participating_channels_device_ids` array the facts publisher denormalizes
/// onto the controller doc from a LAN session.
///
/// Bounds are zeroed and GPIO is -1 because this source genuinely does not know
/// them. A caller that renders an LED range from this list would be inventing
/// one; check [DisplayChannels.hasLengths] first.
List<DeviceChannel> deviceChannelsFromIds(List<int> ids) {
  if (ids.isEmpty) return const [];
  final unique = ids.toSet().toList()..sort();
  return [
    for (final id in unique)
      DeviceChannel(
        id: id,
        name: 'Channel ${id + 1}',
        start: 0,
        stop: 0,
        gpioPin: -1,
      ),
  ];
}

/// Build a display channel list from the `seg` array of a `/json/state` read.
///
/// This is the only fallback that works with NO prior LAN session, because the
/// bridge relays `getState` and hands back the response body verbatim
/// (`executeCommand` → `GET /json/state`, stored whole as the command's
/// `result`).
///
/// Only segments with `stop > start` are counted. WLED pads its state with
/// inactive slots whose `stop` is 0, and rendering those as channels would
/// invent hardware. The consequence is the reboot-collapse case: a controller
/// that has folded two buses into one seg0 spanning the whole strip yields ONE
/// channel here — under-reporting, which is correct for a live-state view and
/// is why pixelMap outranks this tier.
List<DeviceChannel> deviceChannelsFromSegments(dynamic seg) {
  if (seg is! List || seg.isEmpty) return const [];
  final rows = <int, DeviceChannel>{};
  for (final entry in seg) {
    if (entry is! Map) continue;
    final id = entry['id'];
    if (id is! int) continue;
    final start = entry['start'];
    final stop = entry['stop'];
    if (start is! int || stop is! int) continue;
    if (stop <= start) continue;
    rows[id] = DeviceChannel(
      id: id,
      name: 'Channel ${id + 1}',
      start: start,
      stop: stop,
      gpioPin: -1,
    );
  }
  if (rows.isEmpty) return const [];
  final ids = rows.keys.toList()..sort();
  return [for (final id in ids) rows[id]!];
}
