import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
// DeviceChannel + deviceChannelsFromConfig moved to a pure-Dart file (bench/ CLI
// imports them without dart:ui); re-exported so existing importers are unaffected.
export 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';

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

// DeviceChannel + deviceChannelsFromConfig live in device_channel.dart (pure
// Dart) and are re-exported above.

/// Derives channels from hardware bus configuration (`/json/cfg → hw.led.ins[]`).
/// Each bus becomes one channel with its LED range and GPIO pin.
final deviceChannelsProvider = Provider<List<DeviceChannel>>((ref) {
  final hwConfig = ref.watch(deviceHardwareConfigProvider).valueOrNull;
  return deviceChannelsFromConfig(hwConfig);
});

// ---------------------------------------------------------------------------
// DISPLAY channel list (#91) — what to DRAW when the cfg read is unavailable
// ---------------------------------------------------------------------------

/// Tier 3 source: the channel-id list the facts publisher denormalized onto
/// `users/{uid}/controllers/{controllerId}.participating_channels_device_ids`
/// during a LAN session.
///
/// A plain `get()`, not a stream — the shape of a controller does not change
/// while the user is off-site, and a listener would hold a Firestore watch open
/// for a value that is written at most once per app session. Returns `[]` on
/// any failure, including a rules denial: this is a display fallback and must
/// never surface an error where a channel list belongs.
///
/// Kept public so tests can override it; not intended for direct use — read
/// [displayChannelsProvider], which applies the precedence.
final cachedChannelIdsProvider = FutureProvider<List<int>>((ref) async {
  final uid = ref.watch(effectiveUserUidProvider);
  final controllerId = ref.watch(activePixelMapControllerIdProvider);
  if (uid == null || uid.isEmpty) return const <int>[];
  if (controllerId == null || controllerId.isEmpty) return const <int>[];
  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('controllers')
        .doc(controllerId)
        .get();
    final raw = snap.data()?[kParticipatingChannelsDeviceIdsField];
    if (raw is! List) return const <int>[];
    return raw.whereType<num>().map((n) => n.toInt()).toList();
  } catch (e) {
    debugPrint('cachedChannelIdsProvider: controller-doc read failed — $e');
    return const <int>[];
  }
});

/// Tier 4 source: channels inferred from the live `/json/state` `seg[]`.
///
/// Works off-LAN with no prior LAN session because the bridge relays `getState`
/// and returns the response body verbatim. This is the last resort precisely
/// because segment layout is mutable — see [deviceChannelsFromSegments] on the
/// reboot-collapse case.
///
/// Kept public so tests can override it; read [displayChannelsProvider].
final segmentDerivedChannelsProvider =
    FutureProvider<List<DeviceChannel>>((ref) async {
  final repo = ref.watch(wledRepositoryProvider);
  if (repo == null) return const <DeviceChannel>[];
  try {
    final live = await repo.getState();
    if (live == null) return const <DeviceChannel>[];
    return deviceChannelsFromSegments(live['seg']);
  } catch (e) {
    debugPrint('segmentDerivedChannelsProvider: getState failed — $e');
    return const <DeviceChannel>[];
  }
});

/// DISPLAY-ONLY channel list with provenance. **Never** a substitute for
/// [deviceChannelsProvider] on a path that touches hardware or publishes facts.
///
/// WHY THIS EXISTS. [deviceChannelsProvider] derives from `/json/cfg
/// hw.led.ins[]`, and `CloudRelayRepository.getConfig()` returns null
/// unconditionally — the bridge firmware has no cfg dispatch branch. Off-LAN
/// the bus list is therefore null, `deviceChannelsFromConfig` returns `[]`, and
/// the dashboard renders no channels at all while `applyJson` (colour,
/// patterns, whole-controller power) relays perfectly. The channels were never
/// unreachable; the app just could not draw them.
///
/// PRECEDENCE, best-known first. Each tier is consulted only when the ones
/// above it are empty, and the lower tiers are not even `watch`ed on the LAN
/// path — so a healthy local session performs no extra Firestore read and no
/// extra `getState`:
///   1. [DisplayChannelSource.live] — [deviceChannelsProvider] (`/json/cfg`).
///   2. [DisplayChannelSource.pixelMap] — `pixelMap/{n}` docs. Preferred over
///      the tiers below because it carries per-channel lengths AND survives a
///      segment collapse.
///   3. [DisplayChannelSource.participation] — the denormalized id list.
///   4. [DisplayChannelSource.segments] — live `seg[]`, the only tier that
///      needs no prior LAN session.
///
/// Synchronous by construction: every tier is read through `valueOrNull`, so
/// there is no loading state to flash and the list silently UPGRADES as better
/// sources resolve. A tier that is still in flight simply does not win yet.
final displayChannelsProvider = Provider<DisplayChannels>((ref) {
  // 1. Device truth. Return immediately — the early return is also what keeps
  //    tiers 2-4 uninstantiated on LAN.
  final live = ref.watch(deviceChannelsProvider);
  if (live.isNotEmpty) {
    return DisplayChannels(live, DisplayChannelSource.live);
  }

  // 2. Per-channel pixel map.
  final pixelMap = ref.watch(currentPixelMapChannelsProvider).valueOrNull ??
      const <PixelMapChannel>[];
  if (pixelMap.isNotEmpty) {
    final built = deviceChannelsFromPixelCounts({
      for (final c in pixelMap) c.channelIndex: c.sourcePixelCount,
    });
    if (built.isNotEmpty) {
      return DisplayChannels(built, DisplayChannelSource.pixelMap);
    }
  }

  // 3. Denormalized channel ids from the last LAN session.
  final ids = ref.watch(cachedChannelIdsProvider).valueOrNull ?? const <int>[];
  if (ids.isNotEmpty) {
    return DisplayChannels(
        deviceChannelsFromIds(ids), DisplayChannelSource.participation);
  }

  // 4. Live segment layout, relayed through the bridge.
  final segs = ref.watch(segmentDerivedChannelsProvider).valueOrNull ??
      const <DeviceChannel>[];
  if (segs.isNotEmpty) {
    return DisplayChannels(segs, DisplayChannelSource.segments);
  }

  return DisplayChannels.empty;
});

/// Live per-channel power state (P1-43 UI): channel (bus) id → whether that
/// channel is currently LIT, read from `/json/state` seg[] on-flags gated by the
/// device master. Reflects the device, not assumption. A one-shot read (the
/// selector chips show it on open); `ref.invalidate` it after a per-channel
/// toggle to refresh. Master-off ⇒ nothing lit regardless of seg flags.
final channelPowerStatesProvider = FutureProvider<Map<int, bool>>((ref) async {
  final repo = ref.watch(wledRepositoryProvider);
  if (repo == null) return const <int, bool>{};
  try {
    final live = await repo.getState();
    if (live == null) return const <int, bool>{};
    final masterOn = live['on'] == true;
    final result = <int, bool>{};
    final segs = live['seg'];
    if (segs is List) {
      for (final s in segs) {
        if (s is Map && s['id'] is int) {
          result[s['id'] as int] = masterOn && s['on'] == true;
        }
      }
    }
    return result;
  } catch (_) {
    return const <int, bool>{};
  }
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

/// The user's EXPLICIT participation set, or null when they have not made one.
///
/// Bridges [participationOverrideNotifier] into Riverpod and kicks the one-time
/// disk load so the value is warm by the time the dashboard first builds.
///
/// This is the writer-of-record for participation *intent*, as opposed to
/// [participatingChannelIdsProvider] which reports the resolved *outcome*. A
/// non-null value here is also the provenance flag the reconciler keys off —
/// see `participation_reconciler.dart`.
final participationOverrideProvider = Provider<List<int>?>((ref) {
  void listener() => ref.invalidateSelf();
  participationOverrideNotifier.addListener(listener);
  ref.onDispose(() => participationOverrideNotifier.removeListener(listener));
  // Warm on first read; the listener above rebuilds this provider when the
  // load lands. Fire-and-forget — never block a build on disk.
  unawaited(getParticipationOverride());
  return peekParticipationOverride();
});

/// Sync-readable participation list, exposed for Riverpod consumers.
///
/// Bridges the module-level [participationCacheNotifier] (Bundle 3b.2's
/// in-memory cache) into Riverpod: any consumer that `ref.watch`es this
/// rebuilds when [saveLocalParticipatingChannels] is called.
///
/// An explicit user override OUTRANKS the cache. The cache holds the
/// resolver's last output, which is recomputed from roofline geometry; the
/// override is what the user said. Preferring it here means the dashboard
/// honours an include-back on the very next frame, without waiting for a Game
/// Day or sync resolve to re-derive and re-cache.
///
/// Returns:
///   - `null`  → no preference set (cache cold, or never written) — the
///               dashboard gate treats this as "all device channels
///               participate" for backward compatibility.
///   - `[]`    → explicit "no channels" — gate produces empty effective
///               list and callers should skip-apply.
///   - `[..]`  → explicit set — outer gate on [effectiveChannelIdsProvider].
final participatingChannelIdsProvider = Provider<List<int>?>((ref) {
  final override = ref.watch(participationOverrideProvider);
  if (override != null) return override;

  void listener() => ref.invalidateSelf();
  participationCacheNotifier.addListener(listener);
  ref.onDispose(() => participationCacheNotifier.removeListener(listener));
  return peekCachedParticipatingChannels();
});

/// Returns the effective list of channel (bus) IDs that should receive
/// dashboard apply commands.
///
/// U1 semantics (Bundle 3b.3b): participation is the OUTER gate; the
/// selector narrows within it. Computation:
///
///   base = selector == null
///            ? all device channel ids                     // "All Zones"
///            : selector ∩ device channel ids              // explicit subset
///   effective = participation == null
///                 ? base                                  // no pref → unchanged
///                 : base ∩ participation                  // gate non-participating
///
/// Empty effective → callers MUST skip-apply (never broadcast an empty
/// seg array). "All Zones" means all PARTICIPATING zones, not all
/// physical channels.
final effectiveChannelIdsProvider = Provider<List<int>>((ref) {
  final filter = ref.watch(selectedChannelIdsProvider);
  final channels = ref.watch(deviceChannelsProvider);
  final participating = ref.watch(participatingChannelIdsProvider);

  if (channels.isEmpty) return const <int>[];

  // Start with the selector-narrowed set, or all device channels if no
  // selector active.
  Iterable<int> baseIds;
  if (filter == null) {
    baseIds = channels.map((c) => c.id);
  } else {
    baseIds = channels.where((c) => filter.contains(c.id)).map((c) => c.id);
  }

  // Apply participation gate. null = no preference, so don't narrow.
  if (participating != null) {
    final pSet = participating.toSet();
    baseIds = baseIds.where(pSet.contains);
  }

  return baseIds.toList();
});
