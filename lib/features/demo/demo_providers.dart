import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/demo/demo_lead_service.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

// =============================================================================
// Demo Experience State Providers
// =============================================================================

/// Whether the demo experience is currently active.
/// When true, the app is in demo mode with limited features.
final demoExperienceActiveProvider = StateProvider<bool>((ref) => false);

/// Current step in the demo flow.
final demoStepProvider = StateProvider<DemoStep>((ref) => DemoStep.welcome);

/// Lead data captured during demo profile setup.
/// This is stored in Firestore when the user completes the profile step.
final demoLeadProvider = StateProvider<DemoLead?>((ref) => null);

/// Demo roofline segments (simplified, in-memory only).
/// Max 5 segments for demo experience.
final demoRooflineProvider = StateProvider<List<DemoSegment>>((ref) => []);

/// Home photo captured during demo (stored as bytes, not uploaded).
final demoPhotoProvider = StateProvider<Uint8List?>((ref) => null);

/// Whether the user chose to use the stock photo instead of their own.
final demoUsingStockPhotoProvider = StateProvider<bool>((ref) => false);

/// The active roofline configuration for demo mode.
///
/// Populated from one of two sources:
/// - DemoStockHome.load() when the user chooses the sample home
/// - migrateFromLegacyMask(...) after RooflineAutoDetectService runs on
///   the user's captured photo
///
/// Read by currentRooflineConfigProvider when demoExperienceActiveProvider
/// is true, so the production AnimatedRooflineOverlay renders demo
/// previews correctly.
final demoRooflineConfigProvider =
    StateProvider<RooflineConfiguration?>((ref) => null);

/// Currently selected pattern ID in demo mode.
final demoSelectedPatternProvider = StateProvider<String?>((ref) => null);

/// List of pattern IDs viewed during the demo (for analytics).
final demoPatternsViewedProvider = StateProvider<List<String>>((ref) => []);

/// Demo schedule items (auto-generated based on profile).
final demoScheduleProvider = Provider<List<DemoScheduleItem>>((ref) {
  final lead = ref.watch(demoLeadProvider);
  if (lead == null) {
    return DemoSchedulePresets.generateForProfile(
      zipCode: null,
      currentDate: DateTime.now(),
    );
  }
  return DemoSchedulePresets.generateForProfile(
    zipCode: lead.zipCode,
    currentDate: DateTime.now(),
  );
});

/// Total pixel count from demo roofline segments.
final demoTotalPixelCountProvider = Provider<int>((ref) {
  final segments = ref.watch(demoRooflineProvider);
  return segments.fold(0, (sum, seg) => sum + seg.pixelCount);
});

/// Whether the demo has a valid roofline configuration.
final demoHasRooflineProvider = Provider<bool>((ref) {
  final segments = ref.watch(demoRooflineProvider);
  return segments.isNotEmpty;
});

/// Curated patterns available in demo mode.
final demoCuratedPatternsProvider = Provider<List<DemoPatternInfo>>((ref) {
  return DemoCuratedPatterns.all;
});

/// Demo patterns grouped by category.
final demoPatternsbyCategory = Provider<Map<String, List<DemoPatternInfo>>>((ref) {
  final patterns = ref.watch(demoCuratedPatternsProvider);
  final grouped = <String, List<DemoPatternInfo>>{};
  for (final pattern in patterns) {
    grouped.putIfAbsent(pattern.category, () => []).add(pattern);
  }
  return grouped;
});

// =============================================================================
// Demo Flow Navigation
// =============================================================================

/// Notifier for managing demo flow navigation.
class DemoFlowNotifier extends Notifier<DemoStep> {
  @override
  DemoStep build() => DemoStep.welcome;

  /// Move to the next step in the demo flow.
  void nextStep() {
    final currentIndex = state.index;
    if (currentIndex < DemoStep.values.length - 1) {
      state = DemoStep.values[currentIndex + 1];
    }
  }

  /// Move to the previous step in the demo flow.
  void previousStep() {
    final currentIndex = state.index;
    if (currentIndex > 0) {
      state = DemoStep.values[currentIndex - 1];
    }
  }

  /// Jump to a specific step.
  void goToStep(DemoStep step) {
    state = step;
  }

  /// Skip the current step (if skippable).
  void skipStep() {
    if (state.isSkippable) {
      nextStep();
    }
  }

  /// Reset to the beginning of the demo flow.
  void reset() {
    state = DemoStep.welcome;
  }

  /// Check if we can go back.
  bool get canGoBack => state.index > 0;

  /// Check if we're at the last step.
  bool get isLastStep => state.index == DemoStep.values.length - 1;
}

/// Provider for demo flow navigation.
final demoFlowProvider = NotifierProvider<DemoFlowNotifier, DemoStep>(
  DemoFlowNotifier.new,
);

// =============================================================================
// Demo Roofline Management
// =============================================================================

/// Notifier for managing demo roofline segments.
class DemoRooflineNotifier extends Notifier<List<DemoSegment>> {
  static const int maxSegments = 5;

  @override
  List<DemoSegment> build() => [];

  /// Add a new segment.
  /// Returns false if max segments reached.
  bool addSegment(DemoSegment segment) {
    if (state.length >= maxSegments) return false;
    state = [...state, segment];
    return true;
  }

  /// Remove a segment by ID.
  void removeSegment(String id) {
    state = state.where((s) => s.id != id).toList();
  }

  /// Update an existing segment.
  void updateSegment(DemoSegment segment) {
    state = state.map((s) => s.id == segment.id ? segment : s).toList();
  }

  /// Reorder segments.
  void reorderSegments(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final items = [...state];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    state = items;
  }

  /// Clear all segments.
  void clear() {
    state = [];
  }

  /// Check if we can add more segments.
  bool get canAddMore => state.length < maxSegments;
}

/// Provider for demo roofline management.
final demoRooflineNotifierProvider =
    NotifierProvider<DemoRooflineNotifier, List<DemoSegment>>(
  DemoRooflineNotifier.new,
);

// =============================================================================
// Demo Analytics Tracking
// =============================================================================

/// Tracks demo analytics events via [DemoLeadService].
class DemoAnalytics {
  static DemoLeadService? _service;

  /// Initialize with a [DemoLeadService] instance.
  /// Called from [DemoSessionNotifier.startDemo].
  static void init(DemoLeadService service) => _service = service;

  static void trackDemoStart() {
    _service?.logAnalyticsEvent(event: 'demo_start');
  }

  static void trackStepCompleted(DemoStep step, Duration timeSpent) {
    _service?.logAnalyticsEvent(
      event: 'step_completed',
      data: {'step': step.name, 'durationSeconds': timeSpent.inSeconds},
    );
  }

  static void trackPatternViewed(String patternId) {
    _service?.logAnalyticsEvent(
      event: 'pattern_viewed',
      data: {'patternId': patternId},
    );
  }

  static void trackConsultationRequested() {
    _service?.logAnalyticsEvent(event: 'consultation_requested');
  }

  static void trackDemoCompleted() {
    _service?.logAnalyticsEvent(event: 'demo_completed');
  }

  static void trackAccountCreated(String leadId) {
    _service?.logAnalyticsEvent(
      event: 'account_created',
      data: {'leadId': leadId},
    );
  }
}

// =============================================================================
// Demo Session Management
// =============================================================================

/// Manages the overall demo session state.
class DemoSessionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Start a new demo session.
  void startDemo() {
    // Reset all demo state
    ref.read(demoFlowProvider.notifier).reset();
    ref.read(demoLeadProvider.notifier).state = null;
    ref.read(demoRooflineNotifierProvider.notifier).clear();
    ref.read(demoPhotoProvider.notifier).state = null;
    ref.read(demoUsingStockPhotoProvider.notifier).state = false;
    ref.read(demoRooflineConfigProvider.notifier).state = null;
    ref.read(demoSelectedPatternProvider.notifier).state = null;
    ref.read(demoPatternsViewedProvider.notifier).state = [];

    // Mark demo as active
    ref.read(demoExperienceActiveProvider.notifier).state = true;
    state = true;

    // Initialize analytics with lead service and track start
    final leadService = ref.read(demoLeadServiceProvider);
    DemoAnalytics.init(leadService);
    DemoAnalytics.trackDemoStart();
  }

  /// End the demo session.
  void endDemo() {
    ref.read(demoExperienceActiveProvider.notifier).state = false;
    state = false;
  }

  /// Complete the demo (user finished all steps).
  void completeDemo() {
    // Update lead as completed
    final lead = ref.read(demoLeadProvider);
    if (lead != null) {
      final patternsViewed = ref.read(demoPatternsViewedProvider);
      ref.read(demoLeadProvider.notifier).state = lead.copyWith(
        demoCompleted: true,
        patternsViewed: patternsViewed,
      );
    }

    // Track analytics
    DemoAnalytics.trackDemoCompleted();
  }
}

/// Provider for demo session management.
final demoSessionProvider = NotifierProvider<DemoSessionNotifier, bool>(
  DemoSessionNotifier.new,
);
