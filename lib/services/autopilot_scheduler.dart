import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/autopilot_generation_service.dart';
import 'package:nexgen_command/services/preference_learning_service.dart';

/// The main orchestrator for autopilot functionality.
///
/// This scheduler:
/// - Checks if schedule regeneration is needed
/// - Generates new schedules when required
/// - Applies patterns at scheduled times (when autonomyLevel == 2)
/// - Creates suggestions for user approval (when autonomyLevel == 1)
/// - Manages the autopilot lifecycle
class AutopilotScheduler {
  final Ref _ref;

  /// Timer for periodic checking.
  Timer? _checkTimer;

  /// Current active schedule items.
  List<AutopilotScheduleItem> _activeSchedule = [];

  /// Whether the scheduler is currently running.
  bool _isRunning = false;

  /// Auto-apply confidence threshold.
  static const kAutoApplyThreshold = 0.75;

  AutopilotScheduler(this._ref);

  /// Start the autopilot scheduler.
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    debugPrint('AutopilotScheduler: Starting...');

    // Initial check
    _runCycle();

    // Set up periodic checking (every minute)
    _checkTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkScheduledItems(),
    );
  }

  /// Stop the autopilot scheduler.
  void stop() {
    _isRunning = false;
    _checkTimer?.cancel();
    _checkTimer = null;
    debugPrint('AutopilotScheduler: Stopped');
  }

  /// Run a full autopilot cycle.
  Future<void> _runCycle() async {
    final profile = _getCurrentProfile();
    if (profile == null || !profile.autopilotEnabled) {
      debugPrint('AutopilotScheduler: Autopilot disabled or no profile');
      return;
    }

    // Check if we need to regenerate the schedule
    if (_needsRegeneration(profile)) {
      await _regenerateSchedule(profile);
    }
  }

  /// Check if schedule regeneration is needed.
  bool _needsRegeneration(UserModel profile) {
    final lastGenerated = profile.autopilotLastGenerated;
    if (lastGenerated == null) return true;

    final daysSince = DateTime.now().difference(lastGenerated).inDays;
    return daysSince >= 7; // Regenerate weekly
  }

  /// Regenerate the weekly schedule.
  Future<void> _regenerateSchedule(UserModel profile) async {
    debugPrint('AutopilotScheduler: Regenerating schedule...');

    try {
      final generationService = _ref.read(autopilotGenerationServiceProvider);
      final schedule = await generationService.generateWeeklySchedule(
        profile: profile,
      );

      // Apply learned preference adjustments
      final learningService = _ref.read(preferenceLearningServiceProvider);
      final learned = await learningService.getLearnedPreferences();

      final adjustedSchedule = schedule.map((item) {
        final adjustedConfidence = learningService.adjustConfidence(
          item.confidenceScore,
          item,
          learned,
        );
        return item.copyWith(confidenceScore: adjustedConfidence);
      }).toList();

      _activeSchedule = adjustedSchedule;

      // Process items based on autonomy level
      await _processScheduleItems(adjustedSchedule, profile);

      // Mark schedule as generated
      final settingsService = _ref.read(autopilotSettingsServiceProvider);
      await settingsService.markScheduleGenerated();

      debugPrint('AutopilotScheduler: Generated ${schedule.length} schedule items');
    } catch (e) {
      debugPrint('AutopilotScheduler: Failed to regenerate schedule: $e');
    }
  }

  /// Process generated schedule items based on autonomy level.
  Future<void> _processScheduleItems(
    List<AutopilotScheduleItem> items,
    UserModel profile,
  ) async {
    final autonomyLevel = profile.autonomyLevel ?? 1;
    final suggestionsNotifier = _ref.read(autopilotSuggestionsProvider.notifier);
    final learningService = _ref.read(preferenceLearningServiceProvider);

    for (final item in items) {
      if (autonomyLevel == 2 && item.confidenceScore >= kAutoApplyThreshold) {
        // Auto-apply high-confidence items in Proactive mode
        await _scheduleForApplication(item);

        // Record as auto-applied
        await learningService.recordFeedback(
          scheduleItemId: item.id,
          patternName: item.patternName,
          trigger: item.trigger,
          type: FeedbackType.autoApplied,
        );
      } else if (autonomyLevel >= 1) {
        // Add to suggestions for user approval
        suggestionsNotifier.addSuggestion(
          AutopilotSuggestion(
            id: item.id,
            patternName: item.patternName,
            reason: item.reason,
            scheduledTime: item.scheduledTime,
            repeatDays: item.repeatDays,
            wledPayload: item.wledPayload,
            confidenceScore: item.confidenceScore,
            createdAt: item.createdAt,
          ),
        );
      }
    }
  }

  /// Schedule an item for application at its scheduled time.
  Future<void> _scheduleForApplication(AutopilotScheduleItem item) async {
    final now = DateTime.now();
    final delay = item.scheduledTime.difference(now);

    if (delay.isNegative) {
      // Scheduled time has passed, apply immediately if within window
      if (delay.inHours > -2) {
        await _applyPattern(item);
      }
    } else {
      // Schedule for future
      Timer(delay, () => _applyPattern(item));
    }
  }

  /// Check scheduled items and apply any that are due.
  void _checkScheduledItems() {
    final now = DateTime.now();
    final profile = _getCurrentProfile();

    if (profile == null || !profile.autopilotEnabled) return;

    for (final item in _activeSchedule) {
      if (item.shouldFireAt(now) && !item.isApproved) {
        if (profile.autonomyLevel == 2 &&
            item.confidenceScore >= kAutoApplyThreshold) {
          _applyPattern(item);
        }
      }
    }
  }

  /// Apply a pattern to the WLED device.
  Future<void> _applyPattern(AutopilotScheduleItem item) async {
    debugPrint('AutopilotScheduler: Applying pattern "${item.patternName}"');

    try {
      final repo = _ref.read(wledRepositoryProvider);
      if (repo == null) {
        debugPrint('AutopilotScheduler: No WLED repository available');
        return;
      }

      // Apply the WLED payload
      final success = await repo.applyJson(item.wledPayload);

      if (success) {
        debugPrint('AutopilotScheduler: Successfully applied ${item.patternName}');

        // Mark as applied in the schedule
        final index = _activeSchedule.indexWhere((s) => s.id == item.id);
        if (index >= 0) {
          _activeSchedule[index] = item.copyWith(
            isApproved: true,
            wasAutoApplied: true,
          );
        }
      } else {
        debugPrint('AutopilotScheduler: Failed to apply ${item.patternName}');
      }
    } catch (e) {
      debugPrint('AutopilotScheduler: Error applying pattern: $e');
    }
  }

  /// Handle user approval of a suggestion.
  Future<void> approveSuggestion(String suggestionId) async {
    final suggestionsNotifier = _ref.read(autopilotSuggestionsProvider.notifier);
    final suggestions = _ref.read(autopilotSuggestionsProvider);
    final suggestion = suggestions.firstWhere(
      (s) => s.id == suggestionId,
      orElse: () => throw Exception('Suggestion not found'),
    );

    // Apply the pattern
    final item = AutopilotScheduleItem(
      id: suggestion.id,
      scheduledTime: suggestion.scheduledTime,
      repeatDays: suggestion.repeatDays,
      patternName: suggestion.patternName,
      reason: suggestion.reason,
      trigger: AutopilotTrigger.custom,
      confidenceScore: suggestion.confidenceScore,
      wledPayload: suggestion.wledPayload,
      createdAt: suggestion.createdAt,
    );

    await _applyPattern(item);

    // Mark as applied
    suggestionsNotifier.markAsApplied(suggestionId);

    // Record feedback
    final learningService = _ref.read(preferenceLearningServiceProvider);
    await learningService.recordFeedback(
      scheduleItemId: suggestionId,
      patternName: suggestion.patternName,
      trigger: AutopilotTrigger.custom,
      type: FeedbackType.accepted,
    );
  }

  /// Handle user rejection of a suggestion.
  Future<void> rejectSuggestion(String suggestionId) async {
    final suggestionsNotifier = _ref.read(autopilotSuggestionsProvider.notifier);
    final suggestions = _ref.read(autopilotSuggestionsProvider);
    final suggestion = suggestions.firstWhere(
      (s) => s.id == suggestionId,
      orElse: () => throw Exception('Suggestion not found'),
    );

    // Mark as rejected
    suggestionsNotifier.markAsRejected(suggestionId);

    // Record feedback
    final learningService = _ref.read(preferenceLearningServiceProvider);
    await learningService.recordFeedback(
      scheduleItemId: suggestionId,
      patternName: suggestion.patternName,
      trigger: AutopilotTrigger.custom,
      type: FeedbackType.rejected,
    );
  }

  /// Force regeneration of the schedule.
  Future<void> forceRegenerate() async {
    final profile = _getCurrentProfile();
    if (profile == null) return;

    // Clear existing suggestions
    _ref.read(autopilotSuggestionsProvider.notifier).clearAll();

    await _regenerateSchedule(profile);
  }

  /// Get the current active schedule.
  List<AutopilotScheduleItem> get activeSchedule =>
      List.unmodifiable(_activeSchedule);

  /// Get the next scheduled item.
  AutopilotScheduleItem? get nextScheduledItem {
    final now = DateTime.now();
    final future = _activeSchedule
        .where((item) => item.scheduledTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    return future.isNotEmpty ? future.first : null;
  }

  UserModel? _getCurrentProfile() {
    final profileAsync = _ref.read(currentUserProfileProvider);
    return profileAsync.maybeWhen(
      data: (p) => p,
      orElse: () => null,
    );
  }
}

/// Provider for the autopilot scheduler.
final autopilotSchedulerProvider = Provider<AutopilotScheduler>((ref) {
  final scheduler = AutopilotScheduler(ref);

  // Auto-start when provider is created if autopilot is enabled
  ref.listen(autopilotEnabledProvider, (previous, next) {
    if (next) {
      scheduler.start();
    } else {
      scheduler.stop();
    }
  });

  // Clean up on dispose
  ref.onDispose(() {
    scheduler.stop();
  });

  return scheduler;
});

/// Provider for the next scheduled autopilot item.
final nextAutopilotItemProvider = Provider<AutopilotScheduleItem?>((ref) {
  final scheduler = ref.watch(autopilotSchedulerProvider);
  return scheduler.nextScheduledItem;
});

/// Provider to check if autopilot is currently active.
final autopilotActiveProvider = Provider<bool>((ref) {
  final enabled = ref.watch(autopilotEnabledProvider);
  final scheduler = ref.watch(autopilotSchedulerProvider);
  return enabled && scheduler.activeSchedule.isNotEmpty;
});
