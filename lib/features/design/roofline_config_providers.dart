import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:uuid/uuid.dart';

/// Service for CRUD operations on roofline / pixel-map configurations.
///
/// Design Studio Slice 1 re-keys storage from the legacy per-user single doc
/// (`/users/{uid}/roofline_config/config`) to per-controller, per-channel docs
/// at `/users/{uid}/controllers/{controllerId}/pixelMap/{channelId}`. The
/// aggregate app-facing type stays [RooflineConfiguration]; the legacy methods
/// remain solely as the LAZY-migration source.
class RooflineConfigService {
  RooflineConfigService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // ── Legacy per-user path (migration source only) ────────────────────────

  /// Legacy single-config doc. Retained as the read source for the one-time
  /// lazy migration into the per-controller pixelMap; no longer written by the
  /// editor.
  DocumentReference<Map<String, dynamic>> _legacyConfigDoc(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('roofline_config')
        .doc('config');
  }

  Stream<RooflineConfiguration?> streamConfiguration(String userId) {
    return _legacyConfigDoc(userId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return RooflineConfiguration.fromJson(doc.id, doc.data()!);
    });
  }

  Future<RooflineConfiguration?> getConfiguration(String userId) async {
    final doc = await _legacyConfigDoc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return RooflineConfiguration.fromJson(doc.id, doc.data()!);
  }

  /// Legacy save — used only by the mask→config migration
  /// ([rooflineLegacyMigrationProvider]); the editor now saves per-controller.
  Future<void> saveConfiguration(
    String userId,
    RooflineConfiguration config,
  ) async {
    await _legacyConfigDoc(userId)
        .set(UserService.sanitizeForFirestore(config.toJson()));
  }

  Future<void> deleteConfiguration(String userId) async {
    await _legacyConfigDoc(userId).delete();
  }

  // ── Per-controller pixelMap path (Slice 1) ──────────────────────────────

  CollectionReference<Map<String, dynamic>> pixelMapCollection(
    String userId,
    String controllerId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('controllers')
        .doc(controllerId)
        .collection('pixelMap');
  }

  /// Streams the raw per-channel docs for a controller (channel-index sorted).
  Stream<List<PixelMapChannel>> streamPixelMapChannels(
    String userId,
    String controllerId,
  ) {
    return pixelMapCollection(userId, controllerId).snapshots().map((snap) {
      final channels = snap.docs
          .map((d) => PixelMapChannel.fromFirestore(controllerId, d))
          .toList()
        ..sort((a, b) => a.channelIndex.compareTo(b.channelIndex));
      return channels;
    });
  }

  /// One-shot load of the per-channel docs for a controller.
  Future<List<PixelMapChannel>> loadPixelMapChannels(
    String userId,
    String controllerId,
  ) async {
    final snap = await pixelMapCollection(userId, controllerId).get();
    final channels = snap.docs
        .map((d) => PixelMapChannel.fromFirestore(controllerId, d))
        .toList()
      ..sort((a, b) => a.channelIndex.compareTo(b.channelIndex));
    return channels;
  }

  /// Splits [config] by channel and writes one doc per channel. Device-truth
  /// [sourceCounts] (channelIndex → `WledLedBus.len`) seed each channel's
  /// `source_pixel_count`; channels absent from the new config are deleted so
  /// removing a channel's segments doesn't leave an orphan doc.
  Future<void> savePixelMap(
    String userId,
    String controllerId,
    RooflineConfiguration config, {
    Map<int, int> sourceCounts = const {},
    String createdBy = '',
    int mapVersion = 1,
    Map<int, bool> staleByChannel = const {},
  }) async {
    final col = pixelMapCollection(userId, controllerId);
    final channels = splitConfigToPixelMapChannels(
      config,
      controllerId: controllerId,
      sourceCounts: sourceCounts,
      createdBy: createdBy,
      mapVersion: mapVersion,
      now: DateTime.now(),
      staleByChannel: staleByChannel,
    );
    final keepIds = channels.map((c) => c.channelIndex.toString()).toSet();

    final existing = await col.get();
    final batch = _firestore.batch();
    for (final ch in channels) {
      batch.set(
        col.doc(ch.channelIndex.toString()),
        UserService.sanitizeForFirestore(ch.toJson()),
      );
    }
    for (final doc in existing.docs) {
      if (!keepIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }

  /// Persists per-channel staleness flags (channelIndex → isStale). Called from
  /// a device-connect hook when live bus lengths drift from `source_pixel_count`.
  Future<void> updateChannelStaleFlags(
    String userId,
    String controllerId,
    Map<int, bool> staleByChannel,
  ) async {
    if (staleByChannel.isEmpty) return;
    final col = pixelMapCollection(userId, controllerId);
    final batch = _firestore.batch();
    staleByChannel.forEach((ch, stale) {
      batch.set(
        col.doc(ch.toString()),
        {'is_stale': stale, 'updated_at': Timestamp.now()},
        SetOptions(merge: true),
      );
    });
    await batch.commit();
  }

  /// LAZY migration: if the controller has no pixelMap docs yet but a legacy
  /// per-user config exists with segments, split it into per-channel docs under
  /// this controller and mark the legacy doc migrated. No batch job — this runs
  /// on the first per-controller read. Returns true if a migration was written.
  Future<bool> migrateLegacyToPixelMap(
    String userId,
    String controllerId,
  ) async {
    // Already migrated? Any pixelMap doc means yes — cheap guard first.
    final existing = await pixelMapCollection(userId, controllerId).limit(1).get();
    if (existing.docs.isNotEmpty) return false;

    final legacy = await getConfiguration(userId);
    if (legacy == null || legacy.segments.isEmpty) return false;

    await savePixelMap(
      userId,
      controllerId,
      legacy,
      createdBy: userId,
      // No live device counts at migration time — seed from mapped sums.
      sourceCounts: const {},
    );

    // Mark the legacy doc migrated (kept for rollback/audit — not deleted).
    await _legacyConfigDoc(userId).set(
      {
        'migrated_to_pixel_map': true,
        'migrated_controller_id': controllerId,
        'migrated_at': Timestamp.now(),
      },
      SetOptions(merge: true),
    );
    debugPrint('PixelMap migration: legacy config → '
        'controllers/$controllerId/pixelMap (${legacy.segments.length} segs)');
    return true;
  }
}

/// Provider for the roofline configuration service.
final rooflineConfigServiceProvider = Provider<RooflineConfigService>((ref) {
  return RooflineConfigService();
});

/// Resolves the controller whose pixel map is "active": the currently selected
/// controller, else the user's first saved controller (residential single-
/// controller default). Null when the user has no controllers.
final activePixelMapControllerIdProvider = Provider<String?>((ref) {
  final selected = ref.watch(selectedControllerIdProvider);
  if (selected != null && selected.isNotEmpty) return selected;
  return ref.watch(controllersStreamProvider).maybeWhen(
        data: (list) => list.isNotEmpty ? list.first.id : null,
        orElse: () => null,
      );
});

/// One-shot lazy migration of the legacy per-user config into the active
/// controller's per-channel pixelMap. No-op when already migrated or no legacy
/// config exists. Activated transitively by [currentRooflineConfigProvider].
final pixelMapMigrationProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(effectiveUserUidProvider);
  final controllerId = ref.watch(activePixelMapControllerIdProvider);
  if (uid == null || controllerId == null) return false;
  final service = ref.read(rooflineConfigServiceProvider);
  return service.migrateLegacyToPixelMap(uid, controllerId);
});

/// Streams the raw per-channel pixelMap docs for the active controller. Kicks
/// the lazy migration so a legacy config is folded in on first read.
final currentPixelMapChannelsProvider =
    StreamProvider<List<PixelMapChannel>>((ref) {
  // Fire lazy migration (result ignored); the stream reflects migrated docs.
  ref.watch(pixelMapMigrationProvider);

  final uid = ref.watch(effectiveUserUidProvider);
  final controllerId = ref.watch(activePixelMapControllerIdProvider);
  if (uid == null || controllerId == null) {
    return Stream.value(const <PixelMapChannel>[]);
  }
  final service = ref.read(rooflineConfigServiceProvider);
  return service.streamPixelMapChannels(uid, controllerId);
});

/// Provider that streams the current roofline configuration (the aggregate the
/// ~12 existing consumers read). Design Studio Slice 1 re-sources this from the
/// per-controller pixelMap docs while keeping the `RooflineConfiguration?`
/// contract identical.
///
/// In demo mode, short-circuits to the demo-scoped config so
/// AnimatedRooflineOverlay renders correctly for unauthenticated demo users.
/// Returns null when there is no user or no active controller.
final currentRooflineConfigProvider =
    StreamProvider<RooflineConfiguration?>((ref) {
  // DEMO MODE: short-circuit to the demo-scoped config.
  final isDemo = ref.watch(demoExperienceActiveProvider);
  if (isDemo) {
    final demoConfig = ref.watch(demoRooflineConfigProvider);
    return Stream.value(demoConfig);
  }

  // Fire lazy migration (result ignored); the service stream reflects the
  // migrated docs. Watching it rebuilds this provider once migration settles.
  ref.watch(pixelMapMigrationProvider);

  final uid = ref.watch(effectiveUserUidProvider);
  final controllerId = ref.watch(activePixelMapControllerIdProvider);
  if (uid == null || controllerId == null) {
    // No user / no controller yet → no per-controller map. Null preserves the
    // legacy "no config" contract for consumers.
    return Stream.value(null);
  }

  // Map the per-channel docs stream straight to the aggregate. Building the
  // stream directly (rather than nesting an AsyncValue<List<...>>) keeps a
  // single real stream so StreamProvider.future resolves on first emission.
  final service = ref.read(rooflineConfigServiceProvider);
  return service.streamPixelMapChannels(uid, controllerId).map(
        (channels) => channels.isEmpty
            ? null
            : aggregatePixelMapChannelsToConfig(controllerId, channels),
      );
});

/// Per-channel staleness state (channelIndex → isStale) for the active
/// controller. Compares each channel doc's device-truth `source_pixel_count`
/// against the live `WledLedBus.len` from [deviceChannelsProvider]. A channel
/// whose live length has drifted is stale ("roofline changed — remap channel
/// N"). UI consumption is Slice 2/5; Slice 1 provides the state. A device that
/// is unreachable (no live channels) yields all-false (not provably stale).
final pixelMapStalenessProvider = Provider<Map<int, bool>>((ref) {
  final channels = ref.watch(currentPixelMapChannelsProvider).maybeWhen(
        data: (list) => list,
        orElse: () => const <PixelMapChannel>[],
      );
  final deviceChannels = ref.watch(deviceChannelsProvider);
  final liveByChannel = <int, int>{
    for (final ch in deviceChannels) ch.id: ch.stop - ch.start,
  };
  return {
    for (final c in channels)
      c.channelIndex: c.isStaleAgainst(liveByChannel[c.channelIndex]),
  };
});

/// Provider that returns whether the user has a roofline configuration.
final hasRooflineConfigProvider = Provider<bool>((ref) {
  final config = ref.watch(currentRooflineConfigProvider);
  return config.maybeWhen(
    data: (c) => c != null && c.segments.isNotEmpty,
    orElse: () => false,
  );
});

/// One-shot migration provider: converts a legacy single-path [RooflineMask]
/// into a [RooflineConfiguration] with a single segment.
///
/// Runs silently in the background when user data loads. The condition:
///   RooflineMask exists with custom points AND RooflineConfiguration either
///   doesn't exist or has no segments with traced points.
///
/// Once a config with valid segment points exists, the check short-circuits
/// and never re-migrates. Watch this provider from any top-level widget
/// (e.g. the dashboard) to activate it.
final rooflineLegacyMigrationProvider = FutureProvider<void>((ref) async {
  // 1. Need an authenticated user.
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;
  if (user == null) return;

  // 2. Need a legacy mask with custom points.
  //    Watching this re-runs when the profile loads.
  final mask = ref.watch(rooflineMaskProvider);
  if (mask == null || !mask.hasCustomPoints || mask.points.length < 2) return;

  // 3. One-time fetch of config (not reactive — avoids loop after we write).
  final service = ref.read(rooflineConfigServiceProvider);
  final existing = await service.getConfiguration(user.uid);

  // Short-circuit: already have a config with traced segments.
  if (existing != null &&
      existing.segments.any((s) => s.points.length >= 2)) {
    return;
  }

  // 4. Determine pixel count: try the live device, fall back to 100.
  int totalPixels = 100;
  try {
    final deviceCount = ref.read(deviceTotalLedCountProvider).valueOrNull;
    if (deviceCount != null && deviceCount > 0) {
      totalPixels = deviceCount;
    }
  } catch (_) {
    // Device not connected — keep default.
  }

  // 5. Migrate.
  final photoPath = ref.read(houseImageUrlProvider);
  final migrated = migrateFromLegacyMask(
    maskPoints: mask.points,
    totalPixelCount: totalPixels,
    photoPath: photoPath,
  );

  final configToSave = migrated.copyWith(id: 'config');
  await service.saveConfiguration(user.uid, configToSave);
  debugPrint('Roofline migration complete: legacy mask → '
      'single-segment config (${mask.points.length} points, $totalPixels px)');
});

/// State notifier for editing a roofline configuration.
///
/// This manages the in-memory editing state before saving to Firestore.
class RooflineConfigEditorNotifier
    extends StateNotifier<RooflineConfiguration?> {
  final Ref _ref;
  final _uuid = const Uuid();

  RooflineConfigEditorNotifier(this._ref) : super(null);

  /// Initialize the editor with the active controller's map, or a new empty
  /// one. Migrates any legacy per-user config into the pixelMap first so an
  /// existing home isn't lost on first open (Slice 1).
  Future<void> initialize() async {
    final uid = _ref.read(effectiveUserUidProvider);
    final controllerId = _ref.read(activePixelMapControllerIdProvider);

    if (uid == null || controllerId == null) {
      state = RooflineConfiguration.empty();
      return;
    }

    final service = _ref.read(rooflineConfigServiceProvider);
    await service.migrateLegacyToPixelMap(uid, controllerId);
    final channels = await service.loadPixelMapChannels(uid, controllerId);

    state = channels.isEmpty
        ? RooflineConfiguration.empty()
            .copyWith(id: controllerId, controllerId: controllerId)
        : aggregatePixelMapChannelsToConfig(controllerId, channels);
  }

  /// Load an existing configuration into the editor.
  void loadConfiguration(RooflineConfiguration config) {
    state = config;
  }

  /// Set the configuration name.
  void setName(String name) {
    if (state == null) return;
    state = state!.copyWith(name: name);
  }

  /// Add a new segment to the configuration.
  void addSegment({
    required String name,
    required int pixelCount,
    SegmentType type = SegmentType.run,
    List<int>? anchorPixels,
    int anchorLedCount = 2,
    int channelIndex = 0,
    int level = 1,
    List<Offset> points = const [],
    bool isConnectedToPrevious = false,
  }) {
    if (state == null) return;

    final segment = RooflineSegment(
      id: _uuid.v4(),
      name: name,
      pixelCount: pixelCount,
      type: type,
      anchorPixels: anchorPixels ?? [],
      anchorLedCount: anchorLedCount,
      sortOrder: state!.segments.length,
      channelIndex: channelIndex,
      level: level,
      points: points,
      isConnectedToPrevious: isConnectedToPrevious,
    );

    state = state!.addSegment(segment);
  }

  /// Update the photo path on the configuration.
  void setPhotoPath(String? path) {
    if (state == null) return;
    state = state!.copyWith(
      photoPath: path,
      clearPhotoPath: path == null,
    );
  }

  /// Update the total channel count.
  void setTotalChannelCount(int count) {
    if (state == null) return;
    state = state!.copyWith(totalChannelCount: count);
  }

  /// Update the spatial points for a segment (from trace tool).
  void setSegmentPoints(String segmentId, List<Offset> points) {
    if (state == null) return;
    final existing = state!.segmentById(segmentId);
    if (existing == null) return;
    final updated = existing.copyWith(points: points);
    state = state!.updateSegment(segmentId, updated);
  }

  /// Update the channel assignment for a segment.
  void setSegmentChannel(String segmentId, int channelIndex) {
    if (state == null) return;
    final existing = state!.segmentById(segmentId);
    if (existing == null) return;
    final updated = existing.copyWith(channelIndex: channelIndex);
    state = state!.updateSegment(segmentId, updated);
  }

  /// Update the story level for a segment.
  void setSegmentLevel(String segmentId, int level) {
    if (state == null) return;
    final existing = state!.segmentById(segmentId);
    if (existing == null) return;
    final updated = existing.copyWith(level: level);
    state = state!.updateSegment(segmentId, updated);
  }

  /// Update an existing segment.
  void updateSegment(String segmentId, {
    String? name,
    int? pixelCount,
    SegmentType? type,
    List<int>? anchorPixels,
    int? anchorLedCount,
    int? channelIndex,
    int? level,
    List<Offset>? points,
  }) {
    if (state == null) return;

    final existing = state!.segmentById(segmentId);
    if (existing == null) return;

    final updated = existing.copyWith(
      name: name,
      pixelCount: pixelCount,
      type: type,
      anchorPixels: anchorPixels,
      anchorLedCount: anchorLedCount,
      channelIndex: channelIndex,
      level: level,
      points: points,
    );

    state = state!.updateSegment(segmentId, updated);
  }

  /// Remove a segment from the configuration.
  void removeSegment(String segmentId) {
    if (state == null) return;
    state = state!.removeSegment(segmentId);
  }

  /// Reorder segments (drag and drop).
  void reorderSegments(int oldIndex, int newIndex) {
    if (state == null) return;
    state = state!.reorderSegments(oldIndex, newIndex);
  }

  /// Set anchor pixels for a segment.
  void setSegmentAnchors(String segmentId, List<int> anchorPixels) {
    updateSegment(segmentId, anchorPixels: anchorPixels);
  }

  /// Add an anchor point to a segment.
  void addAnchor(String segmentId, int localPixelIndex) {
    if (state == null) return;

    final segment = state!.segmentById(segmentId);
    if (segment == null) return;

    // Don't add duplicate anchors
    if (segment.anchorPixels.contains(localPixelIndex)) return;

    // Validate anchor position
    if (localPixelIndex < 0 ||
        localPixelIndex + segment.anchorLedCount > segment.pixelCount) {
      return;
    }

    final newAnchors = [...segment.anchorPixels, localPixelIndex]..sort();
    updateSegment(segmentId, anchorPixels: newAnchors);
  }

  /// Remove an anchor point from a segment.
  void removeAnchor(String segmentId, int localPixelIndex) {
    if (state == null) return;

    final segment = state!.segmentById(segmentId);
    if (segment == null) return;

    final newAnchors =
        segment.anchorPixels.where((a) => a != localPixelIndex).toList();
    updateSegment(segmentId, anchorPixels: newAnchors);
  }

  /// Toggle anchor at a position (add if not present, remove if present).
  void toggleAnchor(String segmentId, int localPixelIndex) {
    if (state == null) return;

    final segment = state!.segmentById(segmentId);
    if (segment == null) return;

    if (segment.anchorPixels.contains(localPixelIndex)) {
      removeAnchor(segmentId, localPixelIndex);
    } else {
      addAnchor(segmentId, localPixelIndex);
    }
  }

  /// Apply default anchors to a segment based on its type.
  void applyDefaultAnchors(String segmentId) {
    if (state == null) return;

    final segment = state!.segmentById(segmentId);
    if (segment == null) return;

    updateSegment(segmentId, anchorPixels: segment.defaultAnchors);
  }

  /// Apply default anchors to all segments.
  void applyDefaultAnchorsToAll() {
    if (state == null) return;

    for (final segment in state!.segments) {
      applyDefaultAnchors(segment.id);
    }
  }

  /// Validate the configuration against a WLED device's total pixel count.
  bool validateAgainstDevice(int devicePixelCount) {
    if (state == null) return false;
    return state!.validateAgainstDevice(devicePixelCount);
  }

  /// Save the current map to the active controller's per-channel pixelMap
  /// (Slice 1). Per-channel `source_pixel_count` is seeded from device-truth
  /// `WledLedBus.len` via [deviceChannelsProvider] — never hand-typed. Returns
  /// false if there's no user or active controller.
  Future<bool> save() async {
    if (state == null) return false;

    final uid = _ref.read(effectiveUserUidProvider);
    final controllerId = _ref.read(activePixelMapControllerIdProvider);
    if (uid == null || controllerId == null) return false;

    try {
      final service = _ref.read(rooflineConfigServiceProvider);
      final deviceChannels = _ref.read(deviceChannelsProvider);
      final sourceCounts = <int, int>{
        for (final ch in deviceChannels) ch.id: ch.stop - ch.start,
      };
      final configToSave = state!.copyWith(
        id: controllerId,
        controllerId: controllerId,
        updatedAt: DateTime.now(),
      );
      await service.savePixelMap(
        uid,
        controllerId,
        configToSave,
        sourceCounts: sourceCounts,
        createdBy: uid,
      );
      state = configToSave;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear the editor state.
  void clear() {
    state = null;
  }

  /// Reset to a new empty configuration.
  void reset() {
    state = RooflineConfiguration.empty();
  }
}

/// Provider for the roofline configuration editor.
final rooflineConfigEditorProvider =
    StateNotifierProvider<RooflineConfigEditorNotifier, RooflineConfiguration?>(
  (ref) => RooflineConfigEditorNotifier(ref),
);

/// Provider that returns the total pixel count from the current editor state.
final editorTotalPixelCountProvider = Provider<int>((ref) {
  final config = ref.watch(rooflineConfigEditorProvider);
  return config?.totalPixelCount ?? 0;
});

/// Provider that returns the segment count from the current editor state.
final editorSegmentCountProvider = Provider<int>((ref) {
  final config = ref.watch(rooflineConfigEditorProvider);
  return config?.segmentCount ?? 0;
});
