import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A single day entry within a multi-day schedule plan.
class SchedulePlanDay {
  /// Unique key for this day (e.g. "2025-02-13").
  final String key;

  /// Which day of the week (e.g. "THU").
  final String dayOfWeek;

  /// Short date label (e.g. "2/13").
  final String dateLabel;

  /// Human-readable design name (e.g. "Royal Blue & Gold Static").
  final String designName;

  /// The lighting suggestion for this day's preview / colors / effect.
  final LuminaLightingSuggestion suggestion;

  const SchedulePlanDay({
    required this.key,
    required this.dayOfWeek,
    required this.dateLabel,
    required this.designName,
    required this.suggestion,
  });

  SchedulePlanDay copyWith({
    String? designName,
    LuminaLightingSuggestion? suggestion,
  }) {
    return SchedulePlanDay(
      key: key,
      dayOfWeek: dayOfWeek,
      dateLabel: dateLabel,
      designName: designName ?? this.designName,
      suggestion: suggestion ?? this.suggestion,
    );
  }
}

/// The full multi-day schedule plan that Lumina proposes for user confirmation.
class SchedulePlan {
  /// Display name for the plan (e.g. "KC Royals Week").
  final String name;

  /// Date range label (e.g. "Feb 10 – Feb 16").
  final String dateRange;

  /// When each day's schedule triggers (e.g. "Sunset").
  final String triggerTime;

  /// Optional off-time label (e.g. "11:00 PM").
  final String? offTime;

  /// The individual day entries.
  final List<SchedulePlanDay> days;

  const SchedulePlan({
    required this.name,
    required this.dateRange,
    required this.triggerTime,
    this.offTime,
    required this.days,
  });

  SchedulePlan copyWith({
    String? name,
    String? dateRange,
    String? triggerTime,
    String? offTime,
    List<SchedulePlanDay>? days,
  }) {
    return SchedulePlan(
      name: name ?? this.name,
      dateRange: dateRange ?? this.dateRange,
      triggerTime: triggerTime ?? this.triggerTime,
      offTime: offTime ?? this.offTime,
      days: days ?? this.days,
    );
  }
}

// ---------------------------------------------------------------------------
// Submission state
// ---------------------------------------------------------------------------

enum PlanSubmissionStatus { idle, submitting, success, error }

class PlanSubmissionState {
  final PlanSubmissionStatus status;
  final String? confirmationMessage;
  final String? errorMessage;

  const PlanSubmissionState({
    this.status = PlanSubmissionStatus.idle,
    this.confirmationMessage,
    this.errorMessage,
  });
}

// ---------------------------------------------------------------------------
// Controller state
// ---------------------------------------------------------------------------

/// Full state for the schedule plan card.
class SchedulePlanState {
  /// The plan being displayed / edited. Null if no plan is active.
  final SchedulePlan? plan;

  /// Index of the day currently being edited inline (-1 = none).
  final int editingDayIndex;

  /// Submission progress.
  final PlanSubmissionState submission;

  const SchedulePlanState({
    this.plan,
    this.editingDayIndex = -1,
    this.submission = const PlanSubmissionState(),
  });

  bool get hasPlan => plan != null;
  bool get isEditing => editingDayIndex >= 0;
  bool get isSubmitting =>
      submission.status == PlanSubmissionStatus.submitting;
  bool get isSuccess => submission.status == PlanSubmissionStatus.success;

  SchedulePlanState copyWith({
    SchedulePlan? plan,
    int? editingDayIndex,
    PlanSubmissionState? submission,
  }) {
    return SchedulePlanState(
      plan: plan ?? this.plan,
      editingDayIndex: editingDayIndex ?? this.editingDayIndex,
      submission: submission ?? this.submission,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the multi-day schedule plan state:
/// - Setting / clearing the plan
/// - Per-day inline edits
/// - Batch submission to the schedule backend
class SchedulePlanNotifier extends Notifier<SchedulePlanState> {
  @override
  SchedulePlanState build() => const SchedulePlanState();

  // -----------------------------------------------------------------------
  // Plan lifecycle
  // -----------------------------------------------------------------------

  /// Present a new plan for user confirmation.
  void setPlan(SchedulePlan plan) {
    state = SchedulePlanState(plan: plan);
  }

  /// Dismiss the plan (user navigated away or cancelled).
  void clearPlan() {
    state = const SchedulePlanState();
  }

  // -----------------------------------------------------------------------
  // Per-day editing
  // -----------------------------------------------------------------------

  /// Open the inline adjustment panel for a specific day.
  void beginEditingDay(int dayIndex) {
    if (state.plan == null) return;
    if (dayIndex < 0 || dayIndex >= state.plan!.days.length) return;
    state = state.copyWith(editingDayIndex: dayIndex);
  }

  /// Close the inline adjustment panel.
  void stopEditing() {
    state = state.copyWith(editingDayIndex: -1);
  }

  /// Replace a single day's suggestion (after user edits or voice command).
  void updateDay(int dayIndex, {
    String? designName,
    LuminaLightingSuggestion? suggestion,
  }) {
    final plan = state.plan;
    if (plan == null) return;
    if (dayIndex < 0 || dayIndex >= plan.days.length) return;

    final updatedDays = List<SchedulePlanDay>.of(plan.days);
    updatedDays[dayIndex] = updatedDays[dayIndex].copyWith(
      designName: designName,
      suggestion: suggestion,
    );

    state = state.copyWith(plan: plan.copyWith(days: updatedDays));
  }

  /// Find and update a day by day-of-week label (e.g. "FRI", "SATURDAY").
  /// Returns true if a match was found.
  bool updateDayByName(String dayName, {
    String? designName,
    LuminaLightingSuggestion? suggestion,
  }) {
    final plan = state.plan;
    if (plan == null) return false;

    final target = dayName.trim().toUpperCase();
    for (int i = 0; i < plan.days.length; i++) {
      final day = plan.days[i];
      if (day.dayOfWeek.toUpperCase() == target ||
          _expandDay(day.dayOfWeek).toUpperCase() == target) {
        updateDay(i, designName: designName, suggestion: suggestion);
        return true;
      }
    }
    return false;
  }

  // -----------------------------------------------------------------------
  // Submission
  // -----------------------------------------------------------------------

  /// Batch-create all schedule events in the backend.
  Future<void> scheduleAll() async {
    final plan = state.plan;
    if (plan == null) return;

    state = state.copyWith(
      submission: const PlanSubmissionState(
        status: PlanSubmissionStatus.submitting,
      ),
    );

    try {
      final notifier = ref.read(schedulesProvider.notifier);
      final items = _planToScheduleItems(plan);
      await notifier.addAll(items);

      state = state.copyWith(
        submission: PlanSubmissionState(
          status: PlanSubmissionStatus.success,
          confirmationMessage:
              'Your ${plan.name} is scheduled! '
              'First one kicks in tonight at ${plan.triggerTime.toLowerCase()}.',
        ),
      );
    } catch (e) {
      debugPrint('SchedulePlanNotifier: scheduleAll failed: $e');
      state = state.copyWith(
        submission: PlanSubmissionState(
          status: PlanSubmissionStatus.error,
          errorMessage: 'Failed to create schedule events. Please try again.',
        ),
      );
    }
  }

  /// Reset submission state back to idle (e.g. after success animation).
  void resetSubmission() {
    state = state.copyWith(
      submission: const PlanSubmissionState(),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /// Convert the plan into a list of [ScheduleItem]s for the backend.
  List<ScheduleItem> _planToScheduleItems(SchedulePlan plan) {
    return plan.days.map((day) {
      final s = day.suggestion;

      // Build a WLED payload from the suggestion if one isn't already set.
      final payload = s.wledPayload ?? _buildPayload(s);

      // Map day-of-week abbreviation to the repeat-days format used by
      // ScheduleItem (e.g. "Thu").
      final repeatDay = _expandDay(day.dayOfWeek);

      return ScheduleItem(
        id: 'plan_${plan.name.hashCode}_${day.key}',
        timeLabel: plan.triggerTime,
        offTimeLabel: plan.offTime,
        repeatDays: [repeatDay],
        actionLabel: day.designName,
        enabled: true,
        wledPayload: payload,
      );
    }).toList();
  }

  /// Build a WLED JSON payload from a [LuminaLightingSuggestion].
  Map<String, dynamic> _buildPayload(LuminaLightingSuggestion s) {
    final bri = (s.brightness * 255).round().clamp(0, 255);
    final cols = s.colors.take(3).map((c) => [
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
          0,
        ]).toList();
    if (cols.isEmpty) cols.add([255, 255, 255, 0]);

    final speed = s.speed != null ? (s.speed! * 255).round() : 128;

    return {
      'on': true,
      'bri': bri,
      'seg': [
        {
          'fx': s.effect.id,
          'sx': speed,
          'col': cols,
          'pal': 5,
        },
      ],
    };
  }

  /// Expand a 3-letter day abbreviation to the title-case form used by
  /// [ScheduleItem.repeatDays] (e.g. "THU" → "Thu", "FRI" → "Fri").
  static String _expandDay(String abbr) {
    final upper = abbr.trim().toUpperCase();
    const map = {
      'MON': 'Mon', 'TUE': 'Tue', 'WED': 'Wed', 'THU': 'Thu',
      'FRI': 'Fri', 'SAT': 'Sat', 'SUN': 'Sun',
      'MONDAY': 'Mon', 'TUESDAY': 'Tue', 'WEDNESDAY': 'Wed',
      'THURSDAY': 'Thu', 'FRIDAY': 'Fri', 'SATURDAY': 'Sat',
      'SUNDAY': 'Sun',
    };
    return map[upper] ?? abbr;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global provider for the multi-day schedule plan state.
final schedulePlanProvider =
    NotifierProvider<SchedulePlanNotifier, SchedulePlanState>(
  SchedulePlanNotifier.new,
);
