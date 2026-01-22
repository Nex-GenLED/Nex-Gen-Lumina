import 'package:cloud_firestore/cloud_firestore.dart';

/// Change tolerance levels for Autopilot scheduling.
///
/// Controls how frequently Lumina changes the lighting patterns.
enum ChangeToleranceLevel {
  /// No weekly changes (events only)
  minimal(0, 'No Weekly Changes', 'Events only'),
  /// 1-2 changes per week
  low(1, 'Low', '1-2 changes per week'),
  /// 2-4 changes per week
  moderate(2, 'Moderate', '2-4 changes per week'),
  /// 4-7 changes per week
  active(3, 'Active', '4-7 changes per week'),
  /// 1-2 changes per day
  dynamic(4, 'Dynamic', '1-2 changes per day');

  const ChangeToleranceLevel(this.value, this.label, this.description);

  final int value;
  final String label;
  final String description;

  static ChangeToleranceLevel fromValue(int value) {
    return ChangeToleranceLevel.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ChangeToleranceLevel.moderate,
    );
  }

  /// Get the maximum number of changes per day for this tolerance level
  int get maxChangesPerDay {
    switch (this) {
      case ChangeToleranceLevel.minimal:
        return 0; // Only on event days
      case ChangeToleranceLevel.low:
        return 0; // 1-2 changes per week (not daily)
      case ChangeToleranceLevel.moderate:
        return 1; // 2-4 changes per week
      case ChangeToleranceLevel.active:
        return 1; // 4-7 changes per week (daily)
      case ChangeToleranceLevel.dynamic:
        return 2; // 1-2 changes per day
    }
  }

  /// Get the minimum days between changes (0 = can change multiple times per day)
  int get minDaysBetweenChanges {
    switch (this) {
      case ChangeToleranceLevel.minimal:
        return 7; // No weekly changes (only events)
      case ChangeToleranceLevel.low:
        return 3; // 1-2 changes per week
      case ChangeToleranceLevel.moderate:
        return 2; // 2-4 changes per week
      case ChangeToleranceLevel.active:
        return 1; // 4-7 changes per week (daily)
      case ChangeToleranceLevel.dynamic:
        return 0; // 1-2 changes per day
    }
  }
}

/// Autopilot configuration profile for a user.
///
/// Stored as part of the user profile in Firestore.
class AutopilotProfile {
  /// Whether autopilot is enabled
  final bool enabled;

  /// How often patterns should change (0-5 scale)
  final ChangeToleranceLevel changeToleranceLevel;

  /// Preferred effect styles: 'static', 'animated', 'chase', 'twinkle', 'rainbow'
  final List<String> preferredEffectStyles;

  /// When the schedule was last generated
  final DateTime? lastGeneratedAt;

  /// Accumulated learning data from user feedback
  final Map<String, dynamic>? learningData;

  /// Confidence threshold for auto-applying schedules (0.0-1.0)
  /// Only used when autonomyLevel == 2 (Proactive)
  final double autoApplyThreshold;

  const AutopilotProfile({
    this.enabled = false,
    this.changeToleranceLevel = ChangeToleranceLevel.moderate,
    this.preferredEffectStyles = const ['static', 'animated'],
    this.lastGeneratedAt,
    this.learningData,
    this.autoApplyThreshold = 0.75,
  });

  /// Default profile for new users
  static const AutopilotProfile defaultProfile = AutopilotProfile();

  /// Check if schedule regeneration is needed
  bool needsRegeneration({int daysSinceLastGeneration = 7}) {
    if (!enabled) return false;
    if (lastGeneratedAt == null) return true;

    final daysSince = DateTime.now().difference(lastGeneratedAt!).inDays;
    return daysSince >= daysSinceLastGeneration;
  }

  factory AutopilotProfile.fromJson(Map<String, dynamic> json) {
    return AutopilotProfile(
      enabled: (json['enabled'] as bool?) ?? false,
      changeToleranceLevel: ChangeToleranceLevel.fromValue(
        (json['change_tolerance_level'] as num?)?.toInt() ?? 2,
      ),
      preferredEffectStyles: (json['preferred_effect_styles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['static', 'animated'],
      lastGeneratedAt: json['last_generated_at'] != null
          ? (json['last_generated_at'] as Timestamp).toDate()
          : null,
      learningData: json['learning_data'] as Map<String, dynamic>?,
      autoApplyThreshold:
          (json['auto_apply_threshold'] as num?)?.toDouble() ?? 0.75,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'change_tolerance_level': changeToleranceLevel.value,
      'preferred_effect_styles': preferredEffectStyles,
      if (lastGeneratedAt != null)
        'last_generated_at': Timestamp.fromDate(lastGeneratedAt!),
      if (learningData != null) 'learning_data': learningData,
      'auto_apply_threshold': autoApplyThreshold,
    };
  }

  AutopilotProfile copyWith({
    bool? enabled,
    ChangeToleranceLevel? changeToleranceLevel,
    List<String>? preferredEffectStyles,
    DateTime? lastGeneratedAt,
    Map<String, dynamic>? learningData,
    double? autoApplyThreshold,
  }) {
    return AutopilotProfile(
      enabled: enabled ?? this.enabled,
      changeToleranceLevel: changeToleranceLevel ?? this.changeToleranceLevel,
      preferredEffectStyles:
          preferredEffectStyles ?? this.preferredEffectStyles,
      lastGeneratedAt: lastGeneratedAt ?? this.lastGeneratedAt,
      learningData: learningData ?? this.learningData,
      autoApplyThreshold: autoApplyThreshold ?? this.autoApplyThreshold,
    );
  }

  @override
  String toString() =>
      'AutopilotProfile(enabled: $enabled, tolerance: ${changeToleranceLevel.label})';
}
