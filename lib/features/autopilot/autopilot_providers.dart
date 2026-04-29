import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/autopilot_activity_entry.dart';
import 'package:nexgen_command/models/autopilot_event.dart';
import 'package:nexgen_command/models/autopilot_profile.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/models/custom_holiday.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/autopilot_generation_service.dart';
import 'package:nexgen_command/services/autopilot_notification_service.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';

/// Provider for the user's autopilot enabled state.
/// Derived from the user profile.
final autopilotEnabledProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.autopilotEnabled ?? false,
    orElse: () => false,
  );
});

/// Whether the current user has a commercial profile type.
final isCommercialProfileProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.profileType == 'commercial',
    orElse: () => false,
  );
});

/// Happy hour lock windows from the user profile.
final happyHourLocksProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.happyHourLocks ?? const [],
    orElse: () => const [],
  );
});

/// Provider for the change tolerance level.
/// 0-5 scale from minimal to maximum changes.
final changeToleranceLevelProvider = Provider<ChangeToleranceLevel>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) =>
        ChangeToleranceLevel.fromValue(profile?.changeToleranceLevel ?? 2),
    orElse: () => ChangeToleranceLevel.moderate,
  );
});

/// Provider for preferred effect styles.
final preferredEffectStylesProvider = Provider<List<String>>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) =>
        profile?.preferredEffectStyles ?? const ['static', 'animated'],
    orElse: () => const ['static', 'animated'],
  );
});

/// Provider for custom holidays added by the user.
final customHolidaysProvider = Provider<List<CustomHoliday>>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.customHolidays ?? const [],
    orElse: () => const [],
  );
});

/// Provider for sports team priority list.
/// First team has highest priority for conflict resolution.
final sportsTeamPriorityProvider = Provider<List<String>>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) {
      final priority = profile?.sportsTeamPriority ?? const [];
      if (priority.isEmpty) {
        // Fall back to sportsTeams list if no priority set
        return profile?.sportsTeams ?? const [];
      }
      return priority;
    },
    orElse: () => const [],
  );
});

/// Provider for the autonomy level.
/// 0: Passive, 1: Suggest, 2: Proactive
final autonomyLevelProvider = Provider<int>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.autonomyLevel ?? 1,
    orElse: () => 1,
  );
});

/// How autopilot handles conflicts with user-set calendar entries.
enum AutopilotConflictPolicy {
  /// Always keep the user's manual entry — skip the autopilot event.
  keepMine,
  /// Always trust autopilot — overwrite the user's entry.
  trustAutopilot,
  /// Ask the user every time a conflict is detected.
  ask;

  static AutopilotConflictPolicy fromString(String? value) {
    switch (value) {
      case 'keep_mine':
        return AutopilotConflictPolicy.keepMine;
      case 'trust_autopilot':
        return AutopilotConflictPolicy.trustAutopilot;
      default:
        return AutopilotConflictPolicy.ask;
    }
  }

  String toJson() {
    switch (this) {
      case AutopilotConflictPolicy.keepMine:
        return 'keep_mine';
      case AutopilotConflictPolicy.trustAutopilot:
        return 'trust_autopilot';
      case AutopilotConflictPolicy.ask:
        return 'ask';
    }
  }
}

/// Provider for the user's autopilot conflict resolution policy.
final autopilotConflictPolicyProvider = Provider<AutopilotConflictPolicy>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) =>
        AutopilotConflictPolicy.fromString(profile?.autopilotConflictPolicy),
    orElse: () => AutopilotConflictPolicy.ask,
  );
});

/// Provider for when the autopilot schedule was last generated.
final autopilotLastGeneratedProvider = Provider<DateTime?>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.autopilotLastGenerated,
    orElse: () => null,
  );
});

/// Provider for when the Game Day autopilot calendar was last regenerated.
/// Tracks its own weekly cadence separately from [autopilotLastGeneratedProvider].
final gameDayLastGeneratedProvider = Provider<DateTime?>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.gameDayLastGenerated,
    orElse: () => null,
  );
});

/// Computed provider to check if schedule regeneration is needed.
final needsScheduleRegenerationProvider = Provider<bool>((ref) {
  final enabled = ref.watch(autopilotEnabledProvider);
  if (!enabled) return false;

  final lastGenerated = ref.watch(autopilotLastGeneratedProvider);
  if (lastGenerated == null) return true;

  final daysSince = DateTime.now().difference(lastGenerated).inDays;
  return daysSince >= 7; // Regenerate weekly
});

// ─── Generation lifecycle state ─────────────────────────────────────────────

/// Lifecycle status of the autopilot schedule generation pipeline.
enum AutopilotGenerationStatus { idle, loading, error }

/// State for [autopilotGenerationStateProvider]. Tracks whether a schedule
/// generation is currently running, and surfaces any error message that the
/// UI should display alongside a retry affordance.
class AutopilotGenerationState {
  final AutopilotGenerationStatus status;
  final String? errorMessage;

  const AutopilotGenerationState({
    this.status = AutopilotGenerationStatus.idle,
    this.errorMessage,
  });

  bool get isLoading => status == AutopilotGenerationStatus.loading;
  bool get hasError => status == AutopilotGenerationStatus.error;
}

/// Notifier driving the schedule-generation lifecycle. Owned by
/// [AutopilotSettingsService.generateAndPopulateSchedules]; widgets read it
/// to drive spinners, error UI, and retry buttons.
class AutopilotGenerationStateNotifier
    extends StateNotifier<AutopilotGenerationState> {
  AutopilotGenerationStateNotifier() : super(const AutopilotGenerationState());

  void setLoading() => state = const AutopilotGenerationState(
        status: AutopilotGenerationStatus.loading,
      );

  void setError(String message) => state = AutopilotGenerationState(
        status: AutopilotGenerationStatus.error,
        errorMessage: message,
      );

  void setIdle() => state = const AutopilotGenerationState();
}

final autopilotGenerationStateProvider = StateNotifierProvider<
    AutopilotGenerationStateNotifier, AutopilotGenerationState>(
  (ref) => AutopilotGenerationStateNotifier(),
);

/// State notifier for managing autopilot suggestions.
class AutopilotSuggestionsNotifier extends StateNotifier<List<AutopilotSuggestion>> {
  AutopilotSuggestionsNotifier() : super([]);

  void addSuggestion(AutopilotSuggestion suggestion) {
    state = [...state, suggestion];
  }

  void removeSuggestion(String id) {
    state = state.where((s) => s.id != id).toList();
  }

  void clearAll() {
    state = [];
  }

  void markAsApplied(String id) {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(status: SuggestionStatus.applied) else s
    ];
  }

  void markAsRejected(String id) {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(status: SuggestionStatus.rejected) else s
    ];
  }
}

final autopilotSuggestionsProvider =
    StateNotifierProvider<AutopilotSuggestionsNotifier, List<AutopilotSuggestion>>(
  (ref) => AutopilotSuggestionsNotifier(),
);

/// Provider for pending suggestions count (for badge display).
final pendingSuggestionsCountProvider = Provider<int>((ref) {
  final suggestions = ref.watch(autopilotSuggestionsProvider);
  return suggestions.where((s) => s.status == SuggestionStatus.pending).length;
});

/// Helper class for autopilot suggestions.
class AutopilotSuggestion {
  final String id;
  final String patternName;
  final String reason;
  final DateTime scheduledTime;
  final List<String> repeatDays;
  final Map<String, dynamic> wledPayload;
  final double confidenceScore;
  final SuggestionStatus status;
  final DateTime createdAt;

  /// Lumina's narrative voice for this suggestion.
  /// e.g., "Thursday: Chiefs vs. Raiders kickoff — red and gold pulse at game time."
  final String? message;

  const AutopilotSuggestion({
    required this.id,
    required this.patternName,
    required this.reason,
    required this.scheduledTime,
    required this.repeatDays,
    required this.wledPayload,
    required this.confidenceScore,
    this.status = SuggestionStatus.pending,
    required this.createdAt,
    this.message,
  });

  AutopilotSuggestion copyWith({
    String? id,
    String? patternName,
    String? reason,
    DateTime? scheduledTime,
    List<String>? repeatDays,
    Map<String, dynamic>? wledPayload,
    double? confidenceScore,
    SuggestionStatus? status,
    DateTime? createdAt,
    String? message,
  }) {
    return AutopilotSuggestion(
      id: id ?? this.id,
      patternName: patternName ?? this.patternName,
      reason: reason ?? this.reason,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      repeatDays: repeatDays ?? this.repeatDays,
      wledPayload: wledPayload ?? this.wledPayload,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      message: message ?? this.message,
    );
  }
}

enum SuggestionStatus { pending, applied, rejected, modified }

/// Service provider for updating autopilot settings.
class AutopilotSettingsService {
  final Ref _ref;

  AutopilotSettingsService(this._ref);

  /// Enable or disable autopilot.
  /// When enabling, generates and populates schedules based on user profile.
  Future<void> setEnabled(bool enabled) async {
    await _updateProfile((p) => p.copyWith(
          autopilotEnabled: enabled,
          updatedAt: DateTime.now(),
        ));

    if (enabled) {
      // Generate and populate schedules when autopilot is enabled
      await generateAndPopulateSchedules();
    } else {
      // Cancel weekly brief notification when autopilot is disabled
      final notificationService = _ref.read(autopilotNotificationServiceProvider);
      await notificationService.cancelWeeklyBrief();
    }
  }

  /// Generate autopilot schedules and add them to the user's schedule list.
  ///
  /// When [force] is true, the weekly refresh-gate check is skipped — the
  /// generation runs unconditionally. Manual triggers (e.g. the
  /// "Generate This Week's Schedule" button) should pass `force: true`.
  /// Automatic timer-driven calls should leave it `false`.
  ///
  /// Wraps the entire pipeline with:
  ///   - a re-entrancy guard (skips if a generation is already in flight)
  ///   - a 30-second safety-net timeout
  ///   - try/catch that surfaces errors via [autopilotGenerationStateProvider]
  ///     so the UI can display a retry affordance instead of spinning forever.
  Future<void> generateAndPopulateSchedules({bool force = false}) async {
    final genState = _ref.read(autopilotGenerationStateProvider.notifier);

    // Re-entrancy guard — Case C from the bug report. If a generation is
    // already running, don't start a second one on top of it.
    final currentStatus = _ref.read(autopilotGenerationStateProvider).status;
    if (currentStatus == AutopilotGenerationStatus.loading) {
      debugPrint(
          'AutopilotSettingsService: Generation already in progress, skipping');
      return;
    }

    // Refresh-gate guard — Case D from the bug report. Honor the weekly
    // cadence for automatic calls but allow manual triggers to bypass it.
    if (!force) {
      final lastGenerated = _ref.read(autopilotLastGeneratedProvider);
      if (lastGenerated != null) {
        final daysSince = DateTime.now().difference(lastGenerated).inDays;
        if (daysSince < 7) {
          debugPrint(
              'AutopilotSettingsService: Refresh gate not met ($daysSince days since last generation), skipping');
          return;
        }
      }
    }

    genState.setLoading();

    try {
      // Try to get the profile, waiting for it if it's still loading
      var profileAsync = _ref.read(currentUserProfileProvider);
      var profile = profileAsync.maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
      if (profile == null) {
        debugPrint('AutopilotSettingsService: Waiting for profile to load...');
        profile = await _ref
            .read(currentUserProfileProvider.future)
            .timeout(const Duration(seconds: 10));
      }
      if (profile == null) {
        debugPrint(
            'AutopilotSettingsService: No profile found, cannot generate schedules');
        genState.setError('No user profile found.');
        return;
      }

      debugPrint('AutopilotSettingsService: Generating autopilot schedules...');

      // Generate autopilot schedule items — wrapped in a 30s safety-net
      // timeout so the UI can never be stuck on the spinner indefinitely
      // even if the underlying AI call hangs.
      final generationService = _ref.read(autopilotGenerationServiceProvider);
      final autopilotItems = await generationService
          .generateWeeklySchedule(profile: profile)
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
              'Schedule generation timed out after 30 seconds');
        },
      );

      debugPrint(
          'AutopilotSettingsService: Generated ${autopilotItems.length} autopilot items');

      // Convert to regular ScheduleItem format (using user's IANA timezone for display)
      final tz = profile.timeZone;
      final userTimeFormat = profile.timeFormat;
      final scheduleItems = autopilotItems
          .map((item) => _convertToScheduleItem(
                item,
                ianaTimezone: tz,
                timeFormat: userTimeFormat,
              ))
          .toList();

      // Add to user's schedules (merge with existing)
      final schedulesNotifier = _ref.read(schedulesProvider.notifier);
      await schedulesNotifier.addAll(scheduleItems);

      // Mark schedule as generated (also moves the next-refresh window
      // forward to seven days from now).
      await markScheduleGenerated();

      // Schedule the weekly brief notification
      final notificationService =
          _ref.read(autopilotNotificationServiceProvider);
      await notificationService.scheduleWeeklyBrief(
        profile: profile,
        schedule: autopilotItems,
      );

      debugPrint(
          'AutopilotSettingsService: Added ${scheduleItems.length} schedules from Autopilot');

      genState.setIdle();
    } on TimeoutException catch (e, stack) {
      debugPrint('AutopilotSettingsService: Generation timed out: $e\n$stack');
      genState.setError(
          'Schedule generation timed out. Tap "Generate This Week\u2019s Schedule" to try again.');
    } catch (e, stack) {
      debugPrint('AutopilotSettingsService: Failed to generate schedules: $e\n$stack');
      genState.setError(
          'Couldn\u2019t generate schedule. Tap to try again.');
    }
  }

  /// Send a weekly brief notification for [AutopilotEvent] objects from the
  /// new autopilot_events subcollection.  Delegates to the existing
  /// notification service after converting event names to a human-readable
  /// summary string.
  Future<void> scheduleWeeklyBriefForEvents(
      UserModel profile, List<AutopilotEvent> events) async {
    try {
      final notificationService =
          _ref.read(autopilotNotificationServiceProvider);
      // Re-use the existing scheduleWeeklyBrief by converting AutopilotEvents
      // to AutopilotScheduleItems (minimal fields for notification body).
      final now = DateTime.now();
      final pseudoItems = events.map((e) => AutopilotScheduleItem(
            id: e.id,
            scheduledTime: e.startTime,
            repeatDays: const [],
            patternName: e.patternName,
            reason: e.sourceDetail,
            trigger: e.eventType == AutopilotEventType.game
                ? AutopilotTrigger.gameDay
                : e.eventType == AutopilotEventType.holiday
                    ? AutopilotTrigger.holiday
                    : AutopilotTrigger.sunset,
            confidenceScore: e.confidenceScore,
            wledPayload: e.wledPayload ?? const {},
            eventName: e.sourceDetail,
            createdAt: now,
          )).toList();
      await notificationService.scheduleWeeklyBrief(
          profile: profile, schedule: pseudoItems);
    } catch (e) {
      debugPrint('scheduleWeeklyBriefForEvents failed: $e');
    }
  }

  /// Convert an AutopilotScheduleItem to a regular ScheduleItem.
  ScheduleItem _convertToScheduleItem(
    AutopilotScheduleItem item, {
    String? ianaTimezone,
    String timeFormat = '12h',
  }) {
    // Resolve display time in the user's timezone
    final localTime = _toLocalTime(item.scheduledTime, ianaTimezone);

    // Format time label
    String timeLabel = _formatTime(localTime, timeFormat);

    // Add trigger context to time label for special triggers
    if (item.trigger == AutopilotTrigger.sunset) {
      timeLabel = 'Sunset';
    } else if (item.trigger == AutopilotTrigger.sunrise) {
      timeLabel = 'Sunrise';
    }

    // Default off time: Sunrise for sunset-triggered, otherwise none
    String? offTimeLabel;
    if (item.trigger == AutopilotTrigger.sunset) {
      offTimeLabel = 'Sunrise';
    }

    // Format repeat days
    List<String> repeatDays = item.repeatDays;
    if (repeatDays.isEmpty) {
      // One-time event - use the date as the "repeat" indicator
      repeatDays = [_formatDate(localTime)];
    }

    // Build action label
    String actionLabel = 'Pattern: ${item.patternName}';
    if (item.reason.isNotEmpty) {
      actionLabel = '${item.patternName} (${item.reason})';
    }

    return ScheduleItem(
      id: 'autopilot-${item.id}',
      timeLabel: timeLabel,
      offTimeLabel: offTimeLabel,
      repeatDays: repeatDays,
      actionLabel: actionLabel,
      enabled: true,
      wledPayload: item.wledPayload,
    );
  }

  /// Convert a UTC time to the user's IANA timezone, falling back to device local.
  ///
  /// Defensively re-flags the input as UTC when it isn't already — protects
  /// against upstream code that strips the `isUtc` flag during JSON
  /// serialization or model copyWith. Without this guard, a non-UTC input
  /// would either pass through `.toLocal()` as a no-op (showing UTC time
  /// labelled as local) or get a wrong offset applied by `tz.TZDateTime.from`.
  DateTime _toLocalTime(DateTime utcTime, String? ianaTimezone) {
    // Ensure the time is treated as UTC before converting
    final asUtc = utcTime.isUtc
        ? utcTime
        : DateTime.utc(
            utcTime.year, utcTime.month, utcTime.day,
            utcTime.hour, utcTime.minute, utcTime.second,
          );

    if (ianaTimezone == null || ianaTimezone.isEmpty) {
      return asUtc.toLocal();
    }
    try {
      final location = tz.getLocation(ianaTimezone);
      return tz.TZDateTime.from(asUtc, location);
    } catch (_) {
      return asUtc.toLocal();
    }
  }

  /// Format time as "h:mm AM/PM" (12h) or "HH:mm" (24h).
  String _formatTime(DateTime dt, String timeFormat) {
    final minute = dt.minute.toString().padLeft(2, '0');
    if (timeFormat == '24h') {
      final hour = dt.hour.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    final hour = dt.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:$minute $period';
  }

  /// Format date as "Jan 21" style
  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  /// Set the change tolerance level (0-5).
  Future<void> setChangeToleranceLevel(int level) async {
    await _updateProfile((p) => p.copyWith(
          changeToleranceLevel: level.clamp(0, 5),
          updatedAt: DateTime.now(),
        ));
  }

  /// Set preferred effect styles.
  Future<void> setPreferredEffectStyles(List<String> styles) async {
    await _updateProfile((p) => p.copyWith(
          preferredEffectStyles: styles,
          updatedAt: DateTime.now(),
        ));
  }

  /// Add a custom holiday.
  Future<void> addCustomHoliday(CustomHoliday holiday) async {
    final current = _ref.read(customHolidaysProvider);
    await _updateProfile((p) => p.copyWith(
          customHolidays: [...current, holiday],
          updatedAt: DateTime.now(),
        ));
  }

  /// Remove a custom holiday.
  Future<void> removeCustomHoliday(String holidayId) async {
    final current = _ref.read(customHolidaysProvider);
    await _updateProfile((p) => p.copyWith(
          customHolidays: current.where((h) => h.id != holidayId).toList(),
          updatedAt: DateTime.now(),
        ));
  }

  /// Update sports team priority order.
  Future<void> setSportsTeamPriority(List<String> teams) async {
    await _updateProfile((p) => p.copyWith(
          sportsTeamPriority: teams,
          updatedAt: DateTime.now(),
        ));
  }

  /// Update the last generated timestamp.
  Future<void> markScheduleGenerated() async {
    await _updateProfile((p) => p.copyWith(
          autopilotLastGenerated: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
  }

  /// Set the autonomy level (0-2).
  Future<void> setAutonomyLevel(int level) async {
    await _updateProfile((p) => p.copyWith(
          autonomyLevel: level.clamp(0, 2),
          updatedAt: DateTime.now(),
        ));
  }

  /// Enable or disable weekly schedule preview notifications.
  Future<void> setWeeklySchedulePreviewEnabled(bool enabled) async {
    await _updateProfile((p) => p.copyWith(
          weeklySchedulePreviewEnabled: enabled,
          updatedAt: DateTime.now(),
        ));
  }

  /// Enable or disable auto-detection of game days.
  Future<void> setAutoDetectGameDays(bool enabled) async {
    await _updateProfile((p) => p.copyWith(
          autoDetectGameDays: enabled,
          updatedAt: DateTime.now(),
        ));
  }

  /// Enable or disable pre-game team colorway lighting.
  Future<void> setPreGameLighting(bool enabled) async {
    await _updateProfile((p) => p.copyWith(
          preGameLighting: enabled,
          updatedAt: DateTime.now(),
        ));
  }

  /// Enable or disable score celebration LED animations via autopilot.
  Future<void> setScoreCelebrations(bool enabled) async {
    await _updateProfile((p) => p.copyWith(
          scoreCelebrations: enabled,
          updatedAt: DateTime.now(),
        ));
  }

  /// Record a pattern rejection and deprioritize after 3 rejections.
  Future<void> recordPatternRejection(String patternName) async {
    final profileAsync = _ref.read(currentUserProfileProvider);
    final profile = profileAsync.maybeWhen(
      data: (p) => p,
      orElse: () => null,
    );
    if (profile == null) return;

    final now = DateTime.now();
    final rejected = List<Map<String, dynamic>>.from(
      profile.rejectedPatterns.map((e) => Map<String, dynamic>.from(e)),
    );

    // Find existing entry for this pattern
    final idx = rejected.indexWhere(
      (e) => e['pattern_name'] == patternName,
    );

    int newCount;
    if (idx >= 0) {
      newCount = ((rejected[idx]['count'] as num?) ?? 0).toInt() + 1;
      rejected[idx] = {
        'pattern_name': patternName,
        'count': newCount,
        'last_rejected_at': now.toIso8601String(),
      };
    } else {
      newCount = 1;
      rejected.add({
        'pattern_name': patternName,
        'count': 1,
        'last_rejected_at': now.toIso8601String(),
      });
    }

    // Deprioritize if rejected 3+ times
    var deprioritized = profile.deprioritizedPatterns;
    if (newCount >= 3 && !deprioritized.contains(patternName)) {
      deprioritized = [...deprioritized, patternName];
      debugPrint('AutopilotSettingsService: Deprioritizing "$patternName" (rejected ${newCount}x)');
    }

    await _updateProfile((p) => p.copyWith(
          rejectedPatterns: rejected,
          deprioritizedPatterns: deprioritized,
          updatedAt: now,
        ));
  }

  /// Update only the changed profile fields, NOT the entire document.
  /// This avoids overwriting the schedules array during concurrent writes.
  Future<void> _updateProfile(UserModel Function(UserModel) updater) async {
    final profileAsync = _ref.read(currentUserProfileProvider);
    final profile = profileAsync.maybeWhen(
      data: (p) => p,
      orElse: () => null,
    );
    if (profile == null) return;

    final updated = updater(profile);

    // Diff the old vs new toJson to find only changed fields
    final oldJson = profile.toJson();
    final newJson = updated.toJson();
    final changedFields = <String, dynamic>{};
    for (final key in newJson.keys) {
      // Skip the schedules field — managed by SchedulesNotifier
      if (key == 'schedules') continue;
      if (newJson[key] != oldJson[key]) {
        changedFields[key] = newJson[key];
      }
    }

    if (changedFields.isEmpty) return;

    final userService = _ref.read(userServiceProvider);
    await userService.updateUserProfile(profile.id, changedFields);
  }
}

final autopilotSettingsServiceProvider = Provider<AutopilotSettingsService>(
  (ref) => AutopilotSettingsService(ref),
);

// ---------------------------------------------------------------------------
// Sports & Events providers
// ---------------------------------------------------------------------------

/// Whether autopilot should auto-detect game days and start monitoring.
final autoDetectGameDaysProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.autoDetectGameDays ?? true,
    orElse: () => true,
  );
});

/// Whether to apply team colorway before game starts.
final preGameLightingProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.preGameLighting ?? true,
    orElse: () => true,
  );
});

/// Whether score celebrations (LED animations) are enabled via autopilot.
final scoreCelebrationsProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.scoreCelebrations ?? true,
    orElse: () => true,
  );
});

/// Read-only view of recent autopilot activity / decision log.
final autopilotActivityLogProvider = Provider<List<AutopilotActivityEntry>>((ref) {
  final scheduler = ref.watch(autopilotSchedulerProvider);
  return scheduler.activityLog;
});

// ── Neighborhood Sync Event Integration ──────────────────────────────────

/// Whether autopilot-triggered neighborhood sync events are enabled.
final autopilotSyncEventsEnabledProvider = Provider<bool>((ref) {
  final autopilotOn = ref.watch(autopilotEnabledProvider);
  final autoDetectGames = ref.watch(autoDetectGameDaysProvider);
  return autopilotOn && autoDetectGames;
});
