import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:uuid/uuid.dart';

/// Service for CRUD operations on roofline configurations in Firestore.
class RooflineConfigService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get the document reference for a user's roofline configuration.
  /// Each user has a single roofline configuration document.
  DocumentReference<Map<String, dynamic>> _configDoc(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('roofline_config')
        .doc('config');
  }

  /// Stream the user's roofline configuration.
  /// Returns null if no configuration exists.
  Stream<RooflineConfiguration?> streamConfiguration(String userId) {
    return _configDoc(userId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return RooflineConfiguration.fromJson(doc.id, doc.data()!);
    });
  }

  /// Get the user's roofline configuration (one-time fetch).
  Future<RooflineConfiguration?> getConfiguration(String userId) async {
    final doc = await _configDoc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return RooflineConfiguration.fromJson(doc.id, doc.data()!);
  }

  /// Save or update the user's roofline configuration.
  Future<void> saveConfiguration(
    String userId,
    RooflineConfiguration config,
  ) async {
    await _configDoc(userId).set(config.toJson());
  }

  /// Delete the user's roofline configuration.
  Future<void> deleteConfiguration(String userId) async {
    await _configDoc(userId).delete();
  }
}

/// Provider for the roofline configuration service.
final rooflineConfigServiceProvider = Provider<RooflineConfigService>((ref) {
  return RooflineConfigService();
});

/// Provider that streams the current user's roofline configuration.
/// Returns null if the user is not logged in or has no configuration.
final currentRooflineConfigProvider =
    StreamProvider<RooflineConfiguration?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;

  if (user == null) {
    return Stream.value(null);
  }

  final service = ref.read(rooflineConfigServiceProvider);
  return service.streamConfiguration(user.uid);
});

/// Provider that returns whether the user has a roofline configuration.
final hasRooflineConfigProvider = Provider<bool>((ref) {
  final config = ref.watch(currentRooflineConfigProvider);
  return config.maybeWhen(
    data: (c) => c != null && c.segments.isNotEmpty,
    orElse: () => false,
  );
});

/// State notifier for editing a roofline configuration.
///
/// This manages the in-memory editing state before saving to Firestore.
class RooflineConfigEditorNotifier
    extends StateNotifier<RooflineConfiguration?> {
  final Ref _ref;
  final _uuid = const Uuid();

  RooflineConfigEditorNotifier(this._ref) : super(null);

  /// Initialize the editor with the current configuration or a new empty one.
  Future<void> initialize() async {
    final authState = _ref.read(authStateProvider);
    final user = authState.valueOrNull;

    if (user == null) {
      state = RooflineConfiguration.empty();
      return;
    }

    final service = _ref.read(rooflineConfigServiceProvider);
    final existing = await service.getConfiguration(user.uid);

    if (existing != null) {
      state = existing;
    } else {
      state = RooflineConfiguration.empty();
    }
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
    );

    state = state!.addSegment(segment);
  }

  /// Update an existing segment.
  void updateSegment(String segmentId, {
    String? name,
    int? pixelCount,
    SegmentType? type,
    List<int>? anchorPixels,
    int? anchorLedCount,
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

  /// Save the current configuration to Firestore.
  Future<bool> save() async {
    if (state == null) return false;

    final authState = _ref.read(authStateProvider);
    final user = authState.valueOrNull;

    if (user == null) return false;

    try {
      final service = _ref.read(rooflineConfigServiceProvider);
      final configToSave = state!.copyWith(
        id: 'config',
        updatedAt: DateTime.now(),
      );
      await service.saveConfiguration(user.uid, configToSave);
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
