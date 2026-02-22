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
// Channel Selection Filter
// ---------------------------------------------------------------------------

/// Tracks which channel (segment) IDs the user has explicitly selected for
/// receiving aesthetic commands (patterns, colors, effects, speed, intensity).
///
/// - `null` → **All Channels** mode (default). Commands behave exactly as
///   before — no behavioral change until the user actively engages the filter.
/// - `Set<int>` → Only these segment IDs receive aesthetic commands.
final selectedChannelIdsProvider = StateProvider<Set<int>?>((ref) => null);

/// Convenience flag: `true` when the user has narrowed to a channel subset.
final isChannelFilterActiveProvider = Provider<bool>((ref) {
  return ref.watch(selectedChannelIdsProvider) != null;
});

/// Returns the effective list of segment IDs that should receive commands.
///
/// When the channel filter is `null` (all-channels mode) or no segments have
/// been fetched yet, returns every known segment ID. When the filter is active,
/// returns only the IDs present in both the filter set and the device's
/// segment list (handles stale IDs from device reconfiguration).
final effectiveChannelIdsProvider = Provider<List<int>>((ref) {
  final filter = ref.watch(selectedChannelIdsProvider);
  final allSegments = ref.watch(zoneSegmentsProvider).valueOrNull ?? [];
  if (filter == null || allSegments.isEmpty) {
    return allSegments.map((s) => s.id).toList();
  }
  return allSegments
      .where((s) => filter.contains(s.id))
      .map((s) => s.id)
      .toList();
});
