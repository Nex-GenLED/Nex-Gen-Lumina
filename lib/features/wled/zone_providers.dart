import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart' show appForegroundProvider;
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

/// #112 — how often the segment list is refreshed, or `null` for "not at all".
///
/// Was a flat 3.0 s `Timer.periodic`. Over the relay every tick is a `getState`
/// bridge command, so it issued one every 3 s whether or not anyone was looking
/// (2026-09-12: the bulk of 194 commands in 6 minutes). Segment names and ids
/// change only when the hardware layout does.
class ZoneSegmentsPollPolicy {
  const ZoneSegmentsPollPolicy._();

  /// Direct (LAN): cheap per tick, but no reason to poll a near-static list
  /// every 3 s.
  static const Duration direct = Duration(seconds: 15);

  /// Via Bridge: every tick is a relay command with real cost.
  static const Duration viaBridge = Duration(seconds: 60);

  static Duration? intervalFor({
    required bool foreground,
    required bool dashboardVisible,
    required bool isRemote,
  }) {
    if (!foreground || !dashboardVisible) return null;
    return isRemote ? viaBridge : direct;
  }
}

/// #112 — whether the Home dashboard, the one surface that watches the segment
/// list continuously, is on screen. `WledDashboardPage` sets it from
/// `TickerMode` (false while another tab or a pushed route covers it).
/// Defaults to true so any other consumer keeps being refreshed as before.
final dashboardVisibleProvider = StateProvider<bool>((ref) => true);

/// Holds and auto-refreshes the list of segments from the WLED device.
class ZoneSegmentsNotifier extends AsyncNotifier<List<WledSegment>> {
  Timer? _timer;
  bool _ready = false;
  bool _disposed = false;

  @override
  Future<List<WledSegment>> build() async {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });
    // #112 — re-evaluate the cadence the moment any input changes: app
    // backgrounded, dashboard covered, route flipped Direct <-> Via Bridge.
    ref.listen<bool>(appForegroundProvider, (_, __) => _scheduleNext());
    ref.listen<bool>(dashboardVisibleProvider, (_, __) => _scheduleNext());
    ref.listen<bool>(isRemoteModeProvider, (_, __) => _scheduleNext());
    // Initial fetch
    final list = await _fetchOnce();
    _ready = true;
    _scheduleNext();
    return list;
  }

  /// Arms the next refresh per [ZoneSegmentsPollPolicy], or leaves polling
  /// stopped. One timer at a time (self-scheduling, not periodic), so a slow
  /// relay fetch can no longer have the next tick stack on top of it.
  void _scheduleNext() {
    if (_disposed || !_ready) return;
    _timer?.cancel();
    _timer = null;
    final interval = ZoneSegmentsPollPolicy.intervalFor(
      foreground: ref.read(appForegroundProvider),
      dashboardVisible: ref.read(dashboardVisibleProvider),
      isRemote: ref.read(isRemoteModeProvider),
    );
    if (interval == null) return;
    _timer = Timer(interval, () async {
      if (_disposed) return;
      await _refreshSilently();
      _scheduleNext();
    });
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
///   2+3. The `pixelMap/{n}` docs and the denormalized id list, resolved
///      TOGETHER (#92). The id list is the CENSUS — it decides how many
///      channels exist; the pixel map contributes lengths for the ids it
///      covers. Tagged [DisplayChannelSource.pixelMap] only when the map
///      covers every id, else [DisplayChannelSource.participation]. Resolving
///      these as separate first-non-empty tiers was #91's bug: a controller
///      with ids [0,1,2] and only `pixelMap/0` reported a single channel.
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

  // 2 + 3. Pixel map and the denormalized id census, RESOLVED TOGETHER.
  //
  // #92: these were separate first-non-empty tiers, and pixelMap won on
  // PRESENCE. A partially-mapped controller (ids [0,1,2], only pixelMap/0
  // written) therefore reported ONE channel and the selector bar hid itself —
  // #91's own bug, on a real account. The id census decides HOW MANY channels
  // exist; the pixel map only contributes lengths to the ids it covers.
  final pixelMap = ref.watch(currentPixelMapChannelsProvider).valueOrNull ??
      const <PixelMapChannel>[];
  final lengthByChannel = <int, int>{
    for (final c in pixelMap) c.channelIndex: c.sourcePixelCount,
  };
  final ids = ref.watch(cachedChannelIdsProvider).valueOrNull ?? const <int>[];

  if (ids.isNotEmpty) {
    final merged = mergeChannelIdsWithPixelCounts(
      ids: ids,
      lengthByChannelIndex: lengthByChannel,
    );
    // Tagged pixelMap ONLY when the map covers every id — a partial map has
    // no business claiming per-channel lengths for channels it never saw.
    final covered = pixelMapCoversAll(
      ids: ids,
      lengthByChannelIndex: lengthByChannel,
    );
    return DisplayChannels(
      merged,
      covered
          ? DisplayChannelSource.pixelMap
          : DisplayChannelSource.participation,
    );
  }

  // No id census (older controller doc, or the healer has never run). Fall
  // back to the pixel map alone — its own doc set is then the only census
  // available, which is #91's original tier-2 behaviour.
  if (lengthByChannel.isNotEmpty) {
    final built = deviceChannelsFromPixelCounts(lengthByChannel);
    if (built.isNotEmpty) {
      return DisplayChannels(built, DisplayChannelSource.pixelMap);
    }
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

// ---------------------------------------------------------------------------
// APPLY channel census — which channels exist, for the apply gate
// ---------------------------------------------------------------------------

/// Where [ApplyChannelCensus.ids] came from.
enum ApplyChannelSource {
  /// `/json/cfg hw.led.ins[]`, read directly. The home-network answer.
  device,

  /// The id list a home-network session published onto the controller's
  /// account record ([cachedChannelIdsProvider]).
  cached,

  /// The controller's live segment list, fetched through the relay
  /// ([segmentDerivedChannelsProvider]).
  relay,

  /// No source has an answer.
  none,
}

/// The channel ids an apply may target, with where they came from.
///
/// IDS ONLY, on purpose. An apply states a look per channel id and never a
/// bound (`applyChannelFilter` rule 2, pinned again at the wire), so a census
/// that knows which channels exist but not where they start and stop is
/// sufficient for it. That is what makes the away-from-home sources sound
/// here when they are NOT sound for anything that provisions.
class ApplyChannelCensus {
  final List<int> ids;
  final ApplyChannelSource source;

  /// True while a source that could still answer is being read. An empty
  /// [ids] with [pending] set means "not known yet", not "there are none".
  final bool pending;

  const ApplyChannelCensus(this.ids, this.source, {this.pending = false});

  static const ApplyChannelCensus none =
      ApplyChannelCensus(<int>[], ApplyChannelSource.none);

  static const ApplyChannelCensus loading =
      ApplyChannelCensus(<int>[], ApplyChannelSource.none, pending: true);
}

/// The channel census behind [effectiveChannelIdsProvider].
///
/// WHY THIS EXISTS. The gate used to read [deviceChannelsProvider] alone, and
/// away from home that is always empty: the relay cannot read `/json/cfg`. So
/// every favourite, pattern, design and Light Up Now stopped before sending,
/// on a controller that was relaying power, brightness and colour perfectly.
///
/// PRECEDENCE:
///   1. [ApplyChannelSource.device] — on the home network this is the only
///      source consulted, and the early return is what keeps a healthy local
///      session free of any extra account read or relay command.
///   2. [ApplyChannelSource.cached] — away from home only. Bus-derived ids
///      that a home-network session published for THIS controller.
///   3. [ApplyChannelSource.relay] — away from home, and only once the cached
///      list has come back empty: one relayed state read. Last, because
///      segment layout can drift from the buses (a reboot can collapse two
///      segments) and because every relay command has a real cost.
///
/// On the home network with the hardware read still in flight the census is
/// empty and [ApplyChannelCensus.pending]; the cached list is deliberately not
/// used to fill that gap, so a stale account record can never outvote the
/// controller the phone is standing next to.
final applyChannelCensusProvider = Provider<ApplyChannelCensus>((ref) {
  final live = ref.watch(deviceChannelsProvider);
  if (live.isNotEmpty) {
    return ApplyChannelCensus(
      [for (final c in live) c.id],
      ApplyChannelSource.device,
    );
  }

  if (!ref.watch(isRemoteModeProvider)) {
    return ref.watch(deviceHardwareConfigProvider).isLoading
        ? ApplyChannelCensus.loading
        : ApplyChannelCensus.none;
  }

  final cached = ref.watch(cachedChannelIdsProvider);
  final cachedIds = cached.valueOrNull ?? const <int>[];
  if (cachedIds.isNotEmpty) {
    return ApplyChannelCensus(
      List<int>.unmodifiable(cachedIds),
      ApplyChannelSource.cached,
    );
  }
  if (cached.isLoading) return ApplyChannelCensus.loading;

  final relayed = ref.watch(segmentDerivedChannelsProvider);
  final relayedIds = [
    for (final c in relayed.valueOrNull ?? const <DeviceChannel>[]) c.id,
  ];
  if (relayedIds.isNotEmpty) {
    return ApplyChannelCensus(relayedIds, ApplyChannelSource.relay);
  }
  return relayed.isLoading ? ApplyChannelCensus.loading : ApplyChannelCensus.none;
});

/// The channel list to hand `applyChannelFilter` as its census: the hardware
/// buses when they are known, else the [applyChannelCensusProvider] ids with
/// no bounds at all.
///
/// Sound for the same reason [ApplyChannelCensus] is — `applyChannelFilter`
/// reads ids from it and nothing else. NOT a bounds source: away from home
/// every `start`/`stop` in it is zero.
final applyFilterChannelsProvider = Provider<List<DeviceChannel>>((ref) {
  final live = ref.watch(deviceChannelsProvider);
  if (live.isNotEmpty) return live;
  return deviceChannelsFromIds(ref.watch(applyChannelCensusProvider).ids);
});

/// How long [resolveEffectiveChannelIds] waits on each source.
class ApplyGateTimeouts {
  const ApplyGateTimeouts._();

  /// The hardware read on the home network. Matches the notifier's existing
  /// cold-start bound for colour and speed.
  static const Duration hardware = Duration(seconds: 3);

  /// The account read for the cached list.
  static const Duration cached = Duration(seconds: 5);

  /// One relayed state read. A relay round trip is typically 5–10 s.
  static const Duration relay = Duration(seconds: 15);
}

/// [effectiveChannelIdsProvider], but willing to WAIT for a source that has
/// not answered yet — so the first tap after launch, or the first tap away
/// from home, is not refused just because a read was still in flight.
///
/// Returns immediately when the gate already has an answer, and whenever no
/// source is pending. Never throws. An empty result means the gate is closed;
/// ask `applyBlockedReason` why.
Future<List<int>> resolveEffectiveChannelIds(
  T Function<T>(ProviderListenable<T> provider) read, {
  Duration hardwareTimeout = ApplyGateTimeouts.hardware,
  Duration cachedTimeout = ApplyGateTimeouts.cached,
  Duration relayTimeout = ApplyGateTimeouts.relay,
}) async {
  Future<void> settle<T>(Future<T> source, Duration limit) async {
    try {
      await source.timeout(limit);
    } catch (_) {
      // A source that fails or times out simply does not answer; the census
      // reports that on the next read.
    }
  }

  // Each source is waited on at most once: a source that timed out is still
  // "pending" on the next read, and waiting on it again would only multiply
  // the delay before the customer is told.
  final waited = <ApplyChannelSource>{};
  while (true) {
    final ids = read(effectiveChannelIdsProvider);
    if (ids.isNotEmpty) return ids;
    if (!read(applyChannelCensusProvider).pending) return ids;

    if (!read(isRemoteModeProvider)) {
      if (!waited.add(ApplyChannelSource.device)) return ids;
      await settle(read(deviceHardwareConfigProvider.future), hardwareTimeout);
    } else if (read(cachedChannelIdsProvider).isLoading) {
      if (!waited.add(ApplyChannelSource.cached)) return ids;
      await settle(read(cachedChannelIdsProvider.future), cachedTimeout);
    } else {
      if (!waited.add(ApplyChannelSource.relay)) return ids;
      await settle(
          read(segmentDerivedChannelsProvider.future), relayTimeout);
    }
  }
}

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
///
/// "Device channel ids" is [applyChannelCensusProvider], which on the home
/// network is exactly [deviceChannelsProvider] and away from home is the
/// relay-capable census — see there. Callers that find this empty should ask
/// `applyBlockedReason` (lib/shared/apply_blocked_reason.dart) what to tell
/// the customer rather than returning silently.
final effectiveChannelIdsProvider = Provider<List<int>>((ref) {
  final filter = ref.watch(selectedChannelIdsProvider);
  final channelIds = ref.watch(applyChannelCensusProvider).ids;
  final participating = ref.watch(participatingChannelIdsProvider);

  if (channelIds.isEmpty) return const <int>[];

  // Start with the selector-narrowed set, or all device channels if no
  // selector active.
  Iterable<int> baseIds;
  if (filter == null) {
    baseIds = channelIds;
  } else {
    baseIds = channelIds.where(filter.contains);
  }

  // Apply participation gate. null = no preference, so don't narrow.
  if (participating != null) {
    final pSet = participating.toSet();
    baseIds = baseIds.where(pSet.contains);
  }

  return baseIds.toList();
});
