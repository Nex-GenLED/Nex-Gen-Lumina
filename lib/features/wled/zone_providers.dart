import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Holds and auto-refreshes the list of segments from the WLED device.
class ZoneSegmentsNotifier extends AsyncNotifier<List<WledSegment>> {
  Timer? _timer;

  @override
  Future<List<WledSegment>> build() async {
    ref.onDispose(() => _timer?.cancel());
    // Initial fetch
    final list = await _fetchOnce();
    // Start light polling to keep names/ids fresh
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshSilently());
    return list;
  }

  Future<List<WledSegment>> _fetchOnce() async {
    try {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return [];
      return await repo.fetchSegments();
    } catch (e) {
      debugPrint('Zone fetch error: $e');
      return [];
    }
  }

  Future<void> _refreshSilently() async {
    final list = await _fetchOnce();
    state = AsyncData(list);
  }

  Future<void> refreshNow() async {
    state = const AsyncLoading();
    final list = await _fetchOnce();
    state = AsyncData(list);
  }
}

final zoneSegmentsProvider = AsyncNotifierProvider<ZoneSegmentsNotifier, List<WledSegment>>(ZoneSegmentsNotifier.new);

/// Selected segment IDs for group operations
final selectedSegmentsProvider = StateProvider<Set<int>>((ref) => <int>{});

// ---------------------------------------------------------------------------
// Channel Selection Filter (bus-based)
// ---------------------------------------------------------------------------

/// A logical channel derived from hardware bus configuration.
/// Each WLED bus (GPIO output) maps to one channel with a defined LED range.
class DeviceChannel {
  final int id;       // bus index (0, 1, ...)
  final String name;  // "Channel 1", "Channel 2"
  final int start;    // LED start index (inclusive)
  final int stop;     // LED stop index (exclusive)
  final int gpioPin;  // GPIO pin number

  const DeviceChannel({
    required this.id,
    required this.name,
    required this.start,
    required this.stop,
    required this.gpioPin,
  });
}

/// Derives channels from hardware bus configuration (`/json/cfg → hw.led.ins[]`).
/// Each bus becomes one channel with its LED range and GPIO pin.
final deviceChannelsProvider = Provider<List<DeviceChannel>>((ref) {
  final hwConfig = ref.watch(deviceHardwareConfigProvider).valueOrNull;
  if (hwConfig == null || hwConfig.buses.isEmpty) return [];
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
});

/// Tracks which channel (bus) IDs the user has explicitly selected for
/// receiving aesthetic commands (patterns, colors, effects, speed, intensity).
///
/// - `null` → **All Channels** mode (default). Commands target all buses.
/// - `Set<int>` → Only these bus indices receive aesthetic commands.
final selectedChannelIdsProvider = StateProvider<Set<int>?>((ref) => null);

/// Convenience flag: `true` when the user has narrowed to a channel subset.
final isChannelFilterActiveProvider = Provider<bool>((ref) {
  return ref.watch(selectedChannelIdsProvider) != null;
});

/// Returns the effective list of channel (bus) IDs that should receive commands.
///
/// When the channel filter is `null` (all-channels mode), returns every known
/// bus index. When the filter is active, returns only the IDs present in both
/// the filter set and the device's bus list.
final effectiveChannelIdsProvider = Provider<List<int>>((ref) {
  final filter = ref.watch(selectedChannelIdsProvider);
  final channels = ref.watch(deviceChannelsProvider);
  if (filter == null || channels.isEmpty) {
    return channels.map((c) => c.id).toList();
  }
  return channels
      .where((c) => filter.contains(c.id))
      .map((c) => c.id)
      .toList();
});
