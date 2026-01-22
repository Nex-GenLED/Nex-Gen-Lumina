import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/autopilot_profile.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/models/custom_holiday.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/autopilot_generation_service.dart';

/// Provider for the user's autopilot enabled state.
/// Derived from the user profile.
final autopilotEnabledProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.autopilotEnabled ?? false,
    orElse: () => false,
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

/// Provider for when the autopilot schedule was last generated.
final autopilotLastGeneratedProvider = Provider<DateTime?>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.autopilotLastGenerated,
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
    }
  }

  /// Generate autopilot schedules and add them to the user's schedule list.
  Future<void> generateAndPopulateSchedules() async {
    final profileAsync = _ref.read(currentUserProfileProvider);
    final profile = profileAsync.maybeWhen(
      data: (p) => p,
      orElse: () => null,
    );
    if (profile == null) {
      debugPrint('AutopilotSettingsService: No profile found, cannot generate schedules');
      return;
    }

    debugPrint('AutopilotSettingsService: Generating autopilot schedules...');

    try {
      // Generate autopilot schedule items
      final generationService = _ref.read(autopilotGenerationServiceProvider);
      final autopilotItems = await generationService.generateWeeklySchedule(
        profile: profile,
      );

      debugPrint('AutopilotSettingsService: Generated ${autopilotItems.length} autopilot items');

      // Convert to regular ScheduleItem format
      final scheduleItems = autopilotItems.map((item) => _convertToScheduleItem(item)).toList();

      // Add to user's schedules (merge with existing)
      final schedulesNotifier = _ref.read(schedulesProvider.notifier);
      await schedulesNotifier.addAll(scheduleItems);

      // Mark schedule as generated
      await markScheduleGenerated();

      debugPrint('AutopilotSettingsService: Added ${scheduleItems.length} schedules from Autopilot');
    } catch (e) {
      debugPrint('AutopilotSettingsService: Failed to generate schedules: $e');
    }
  }

  /// Convert an AutopilotScheduleItem to a regular ScheduleItem.
  ScheduleItem _convertToScheduleItem(AutopilotScheduleItem item) {
    // Format time label
    String timeLabel = _formatTime(item.scheduledTime);

    // Add trigger context to time label for special triggers
    if (item.trigger == AutopilotTrigger.sunset) {
      timeLabel = 'Sunset';
    } else if (item.trigger == AutopilotTrigger.sunrise) {
      timeLabel = 'Sunrise';
    }

    // Format repeat days
    List<String> repeatDays = item.repeatDays;
    if (repeatDays.isEmpty) {
      // One-time event - use the date as the "repeat" indicator
      repeatDays = [_formatDate(item.scheduledTime)];
    }

    // Build action label
    String actionLabel = 'Pattern: ${item.patternName}';
    if (item.reason.isNotEmpty) {
      actionLabel = '${item.patternName} (${item.reason})';
    }

    return ScheduleItem(
      id: 'autopilot-${item.id}',
      timeLabel: timeLabel,
      repeatDays: repeatDays,
      actionLabel: actionLabel,
      enabled: true,
    );
  }

  /// Format time as "h:mm AM/PM"
  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
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

  Future<void> _updateProfile(UserModel Function(UserModel) updater) async {
    final profileAsync = _ref.read(currentUserProfileProvider);
    final profile = profileAsync.maybeWhen(
      data: (p) => p,
      orElse: () => null,
    );
    if (profile == null) return;

    final updated = updater(profile);
    final userService = _ref.read(userServiceProvider);
    await userService.updateUser(updated);
  }
}

final autopilotSettingsServiceProvider = Provider<AutopilotSettingsService>(
  (ref) => AutopilotSettingsService(ref),
);
