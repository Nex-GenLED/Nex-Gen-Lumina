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
