import 'package:cloud_firestore/cloud_firestore.dart';

/// Change tolerance levels for Autopilot scheduling.
///
/// Controls how frequently Lumina changes the lighting patterns.
enum ChangeToleranceLevel {
  /// 1-2 changes per week (events only)
  minimal(0, 'Minimal', '1-2 changes/week'),
  /// 3-4 changes per week
  low(1, 'Low', '3-4 changes/week'),
  /// Daily changes
  moderate(2, 'Moderate', 'Daily changes'),
  /// 1-2 changes per day
  active(3, 'Active', '1-2 changes/day'),
  /// Multiple changes per day
  dynamic(4, 'Dynamic', 'Multiple/day'),
  /// Frequent changes, always fresh
  maximum(5, 'Maximum', 'Frequent changes');

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
        return 0; // Only on event days, but more events
      case ChangeToleranceLevel.moderate:
        return 1;
      case ChangeToleranceLevel.active:
        return 2;
      case ChangeToleranceLevel.dynamic:
        return 4;
      case ChangeToleranceLevel.maximum:
        return 8;
    }
  }

  /// Get the minimum days between changes (0 = can change multiple times per day)
  int get minDaysBetweenChanges {
    switch (this) {
      case ChangeToleranceLevel.minimal:
        return 3;
      case ChangeToleranceLevel.low:
        return 2;
      case ChangeToleranceLevel.moderate:
        return 1;
      case ChangeToleranceLevel.active:
      case ChangeToleranceLevel.dynamic:
      case ChangeToleranceLevel.maximum:
        return 0;
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
