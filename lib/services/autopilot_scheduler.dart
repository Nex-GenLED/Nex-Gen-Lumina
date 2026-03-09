import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/sports_background_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/models/autopilot_activity_entry.dart';
import 'package:nexgen_command/models/autopilot_override.dart';
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
/// - Coordinates with Sports Alerts via the override protocol
/// - Proactively detects upcoming games and activates game mode
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

  // ---------------------------------------------------------------------------
  // Override protocol state
  // ---------------------------------------------------------------------------

  /// Currently active override token (null when no override is in progress).
  OverrideToken? _activeOverride;

  /// Activity log — most recent first, capped at [_maxLogEntries].
  final List<AutopilotActivityEntry> _activityLog = [];
  static const _maxLogEntries = 50;

  /// Counter for sports context evaluation cadence (every 5th cycle = ~5 min).
  int _sportsCheckCounter = 0;

  /// Tracks which team slugs have already triggered game-mode activation
  /// this session, to avoid repeated activations.
  final Set<String> _activatedTeamSlugs = {};

  AutopilotScheduler(this._ref);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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
    _activatedTeamSlugs.clear();
    debugPrint('AutopilotScheduler: Stopped');
  }

  // ---------------------------------------------------------------------------
  // Override protocol — public API
  // ---------------------------------------------------------------------------

  /// Request temporary control of the WLED device.
  ///
  /// Called by [AlertTriggerService] before running a score-alert animation
  /// so the scheduler pauses and captures state for clean restoration.
  ///
  /// Returns an [OverrideToken] on success, or `null` if another override
  /// is already active.
  Future<OverrideToken?> requestOverride({
    required OverrideSource source,
    required Duration duration,
  }) async {
    if (_activeOverride != null && !_activeOverride!.isExpired) {
      debugPrint(
        'AutopilotScheduler: Override already active from '
        '${_activeOverride!.source}, rejecting',
      );
      return null;
    }

    // Capture current WLED state via repository
    Map<String, dynamic>? capturedState;
    try {
      final repo = _ref.read(wledRepositoryProvider);
      if (repo != null) {
        capturedState = await repo.getState();
      }
    } catch (e) {
      debugPrint('AutopilotScheduler: Failed to capture state: $e');
    }

    _activeOverride = OverrideToken(
      source: source,
      duration: duration,
      capturedState: capturedState,
    );

    _addActivityLogEntry(AutopilotActivityEntry(
      timestamp: DateTime.now(),
      type: ActivityEntryType.overrideStarted,
      source: source.name,
      message: 'Score alert override started (${duration.inSeconds}s)',
    ));

    debugPrint(
      'AutopilotScheduler: Override granted to ${source.name} '
      'for ${duration.inSeconds}s',
    );
    return _activeOverride;
  }

  /// Release a previously granted override, restoring the captured state.
  ///
  /// Called by [AlertTriggerService] after its animation completes. The
  /// scheduler — not the alert service — owns restoration when autopilot
  /// is running.
  Future<void> releaseOverride(OverrideToken token) async {
    if (_activeOverride == null || _activeOverride!.id != token.id) {
      debugPrint('AutopilotScheduler: Ignoring stale override release');
      return;
    }

    // Restore captured state
    if (token.capturedState != null && token.capturedState!.isNotEmpty) {
      try {
        final repo = _ref.read(wledRepositoryProvider);
        if (repo != null) {
          await repo.applyJson(token.capturedState!);
          debugPrint('AutopilotScheduler: State restored after override');
        }
      } catch (e) {
        debugPrint('AutopilotScheduler: Failed to restore state: $e');
      }
    }

    _addActivityLogEntry(AutopilotActivityEntry(
      timestamp: DateTime.now(),
      type: ActivityEntryType.overrideEnded,
      source: token.source.name,
      message: 'Override ended, previous state restored',
    ));

    _activeOverride = null;
  }

  /// Whether an override is currently active.
  bool get isOverrideActive =>
      _activeOverride != null && !_activeOverride!.isExpired;

  // ---------------------------------------------------------------------------
  // Activity log
  // ---------------------------------------------------------------------------

  void _addActivityLogEntry(AutopilotActivityEntry entry) {
    _activityLog.insert(0, entry);
    if (_activityLog.length > _maxLogEntries) {
      _activityLog.removeLast();
    }
  }

  /// Public read-only view of recent autopilot decisions.
  List<AutopilotActivityEntry> get activityLog =>
      List.unmodifiable(_activityLog);

  // ---------------------------------------------------------------------------
  // Core scheduling loop
  // ---------------------------------------------------------------------------

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
    // Skip scheduling while an override is active
    if (_activeOverride != null && !_activeOverride!.isExpired) {
      debugPrint('AutopilotScheduler: Skipping check — override active');
      return;
    }

    // Auto-cleanup expired overrides
    if (_activeOverride != null && _activeOverride!.isExpired) {
      debugPrint('AutopilotScheduler: Override expired, auto-releasing');
      releaseOverride(_activeOverride!);
    }

    final now = DateTime.now();
    final profile = _getCurrentProfile();

    if (profile == null || !profile.autopilotEnabled) return;

    // Sports context check every 5 minutes (every 5th cycle)
    _sportsCheckCounter++;
    if (_sportsCheckCounter >= 5) {
      _sportsCheckCounter = 0;
      _evaluateSportsContext(profile);
    }

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

        _addActivityLogEntry(AutopilotActivityEntry(
          timestamp: DateTime.now(),
          type: ActivityEntryType.patternApplied,
          source: item.trigger.name,
          message: '${item.patternName} applied — ${item.reason}',
        ));

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

  // ---------------------------------------------------------------------------
  // Proactive sports context evaluation
  // ---------------------------------------------------------------------------

  /// Evaluate whether any of the user's teams have an upcoming game and
  /// proactively activate game mode.
  ///
  /// Called every ~5 minutes from the scheduling loop.
  Future<void> _evaluateSportsContext(UserModel profile) async {
    if (!profile.autoDetectGameDays) return;

    final teams = profile.sportsTeamPriority.isNotEmpty
        ? profile.sportsTeamPriority
        : profile.sportsTeams;
    if (teams.isEmpty) return;

    final gameScheduleService = GameScheduleService();

    try {
      for (final teamSlug in teams) {
        // Skip teams we've already activated this session
        if (_activatedTeamSlugs.contains(teamSlug)) continue;

        final teamInfo = kTeamColors[teamSlug];
        if (teamInfo == null) continue;

        final hasGame = await gameScheduleService.hasGameSoon(
          teamInfo.espnTeamId,
          teamInfo.sport,
          minutes: 60,
        );

        if (hasGame) {
          _activatedTeamSlugs.add(teamSlug);

          _addActivityLogEntry(AutopilotActivityEntry(
            timestamp: DateTime.now(),
            type: ActivityEntryType.gameDetected,
            source: 'evaluateSportsContext',
            message:
                '${teamInfo.teamName} game starting within 60 min — '
                'activating game mode',
            metadata: {'teamSlug': teamSlug, 'sport': teamInfo.sport.name},
          ));

          // Auto-activate the background score monitoring service
          try {
            await startSportsService();

            _addActivityLogEntry(AutopilotActivityEntry(
              timestamp: DateTime.now(),
              type: ActivityEntryType.backgroundServiceActivated,
              source: 'evaluateSportsContext',
              message:
                  'Sports monitoring auto-started for ${teamInfo.teamName}',
            ));
          } catch (e) {
            debugPrint(
              'AutopilotScheduler: Failed to start sports service: $e',
            );
          }

          // Optionally shift to pre-game team colorway
          if (profile.preGameLighting) {
            await _applyPreGameColorway(teamInfo);
          }

          // One team at a time to avoid conflicts
          break;
        }
      }
    } catch (e) {
      debugPrint('AutopilotScheduler: Sports context evaluation failed: $e');
    } finally {
      gameScheduleService.dispose();
    }
  }

  /// Apply a subtle team-color baseline before the game starts.
  Future<void> _applyPreGameColorway(TeamColors teamInfo) async {
    final repo = _ref.read(wledRepositoryProvider);
    if (repo == null) return;

    final primary = AlertTriggerService.colorToRgbw(teamInfo.primary);
    final secondary = AlertTriggerService.colorToRgbw(teamInfo.secondary);

    final payload = <String, dynamic>{
      'on': true,
      'bri': 180,
      'seg': [
        {
          'fx': 0, // Solid
          'sx': 128,
          'ix': 128,
          'col': [primary, secondary, [0, 0, 0, 0]],
        },
      ],
    };

    try {
      await repo.applyJson(payload);

      _addActivityLogEntry(AutopilotActivityEntry(
        timestamp: DateTime.now(),
        type: ActivityEntryType.preGameLightingApplied,
        source: 'evaluateSportsContext',
        message: '${teamInfo.teamName} pre-game colorway applied',
      ));
    } catch (e) {
      debugPrint('AutopilotScheduler: Failed to apply pre-game colorway: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Suggestion handling
  // ---------------------------------------------------------------------------

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

    // Persist rejection and deprioritize after 3 rejections
    await _ref
        .read(autopilotSettingsServiceProvider)
        .recordPatternRejection(suggestion.patternName);
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

  // Start immediately if autopilot is already enabled at app launch
  if (ref.read(autopilotEnabledProvider)) {
    scheduler.start();
  }

  // React to future enable/disable changes
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
