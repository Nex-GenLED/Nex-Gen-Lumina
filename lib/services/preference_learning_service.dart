import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';

/// Type of feedback for a suggestion.
enum FeedbackType {
  accepted,
  rejected,
  modified,
  autoApplied,
}

/// A single feedback record for a suggestion.
class SuggestionFeedback {
  final String id;
  final String scheduleItemId;
  final String patternName;
  final AutopilotTrigger trigger;
  final FeedbackType feedbackType;
  final DateTime timestamp;
  final String? modificationNotes;
  final List<int>? originalColors;
  final List<int>? modifiedColors;
  final int? originalEffectId;
  final int? modifiedEffectId;

  const SuggestionFeedback({
    required this.id,
    required this.scheduleItemId,
    required this.patternName,
    required this.trigger,
    required this.feedbackType,
    required this.timestamp,
    this.modificationNotes,
    this.originalColors,
    this.modifiedColors,
    this.originalEffectId,
    this.modifiedEffectId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'schedule_item_id': scheduleItemId,
      'pattern_name': patternName,
      'trigger': trigger.name,
      'feedback_type': feedbackType.name,
      'timestamp': Timestamp.fromDate(timestamp),
      if (modificationNotes != null) 'modification_notes': modificationNotes,
      if (originalColors != null) 'original_colors': originalColors,
      if (modifiedColors != null) 'modified_colors': modifiedColors,
      if (originalEffectId != null) 'original_effect_id': originalEffectId,
      if (modifiedEffectId != null) 'modified_effect_id': modifiedEffectId,
    };
  }

  factory SuggestionFeedback.fromJson(Map<String, dynamic> json) {
    return SuggestionFeedback(
      id: json['id'] as String,
      scheduleItemId: json['schedule_item_id'] as String,
      patternName: json['pattern_name'] as String,
      trigger: AutopilotTrigger.values.firstWhere(
        (t) => t.name == json['trigger'],
        orElse: () => AutopilotTrigger.custom,
      ),
      feedbackType: FeedbackType.values.firstWhere(
        (f) => f.name == json['feedback_type'],
        orElse: () => FeedbackType.accepted,
      ),
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      modificationNotes: json['modification_notes'] as String?,
      originalColors: (json['original_colors'] as List?)?.cast<int>(),
      modifiedColors: (json['modified_colors'] as List?)?.cast<int>(),
      originalEffectId: json['original_effect_id'] as int?,
      modifiedEffectId: json['modified_effect_id'] as int?,
    );
  }
}

/// Aggregated learned preferences from user feedback.
class LearnedPreferences {
  /// Colors that tend to be accepted.
  final List<int> preferredColors;

  /// Colors that tend to be rejected or modified away from.
  final List<int> avoidedColors;

  /// Effect IDs that tend to be accepted.
  final List<int> preferredEffectIds;

  /// Effect IDs that tend to be rejected.
  final List<int> avoidedEffectIds;

  /// Success rate by trigger type (0.0 to 1.0).
  final Map<String, double> triggerSuccessRates;

  /// Success rate by pattern name.
  final Map<String, double> patternSuccessRates;

  /// Time of day preferences (hours with higher acceptance rates).
  final List<int> preferredHours;

  /// Day of week preferences (0=Monday, 6=Sunday).
  final List<int> preferredDays;

  /// Total feedback count.
  final int totalFeedbackCount;

  /// Last updated timestamp.
  final DateTime lastUpdated;

  const LearnedPreferences({
    this.preferredColors = const [],
    this.avoidedColors = const [],
    this.preferredEffectIds = const [],
    this.avoidedEffectIds = const [],
    this.triggerSuccessRates = const {},
    this.patternSuccessRates = const {},
    this.preferredHours = const [],
    this.preferredDays = const [],
    this.totalFeedbackCount = 0,
    required this.lastUpdated,
  });

  factory LearnedPreferences.empty() {
    return LearnedPreferences(lastUpdated: DateTime.now());
  }

  Map<String, dynamic> toJson() {
    return {
      'preferred_colors': preferredColors,
      'avoided_colors': avoidedColors,
      'preferred_effect_ids': preferredEffectIds,
      'avoided_effect_ids': avoidedEffectIds,
      'trigger_success_rates': triggerSuccessRates,
      'pattern_success_rates': patternSuccessRates,
      'preferred_hours': preferredHours,
      'preferred_days': preferredDays,
      'total_feedback_count': totalFeedbackCount,
      'last_updated': Timestamp.fromDate(lastUpdated),
    };
  }

  factory LearnedPreferences.fromJson(Map<String, dynamic> json) {
    return LearnedPreferences(
      preferredColors: (json['preferred_colors'] as List?)?.cast<int>() ?? [],
      avoidedColors: (json['avoided_colors'] as List?)?.cast<int>() ?? [],
      preferredEffectIds: (json['preferred_effect_ids'] as List?)?.cast<int>() ?? [],
      avoidedEffectIds: (json['avoided_effect_ids'] as List?)?.cast<int>() ?? [],
      triggerSuccessRates: (json['trigger_success_rates'] as Map?)?.cast<String, double>() ?? {},
      patternSuccessRates: (json['pattern_success_rates'] as Map?)?.cast<String, double>() ?? {},
      preferredHours: (json['preferred_hours'] as List?)?.cast<int>() ?? [],
      preferredDays: (json['preferred_days'] as List?)?.cast<int>() ?? [],
      totalFeedbackCount: json['total_feedback_count'] as int? ?? 0,
      lastUpdated: json['last_updated'] != null
          ? (json['last_updated'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}

/// Service for tracking and learning from user feedback on autopilot suggestions.
///
/// This service:
/// - Records user feedback (accept, reject, modify)
/// - Aggregates preferences over time
/// - Provides learned preferences for improved suggestion confidence
class PreferenceLearningService {
  final Ref _ref;
  final FirebaseFirestore _firestore;

  PreferenceLearningService(this._ref) : _firestore = FirebaseFirestore.instance;

  /// Record user feedback for a suggestion.
  Future<void> recordFeedback({
    required String scheduleItemId,
    required String patternName,
    required AutopilotTrigger trigger,
    required FeedbackType type,
    String? modificationNotes,
    List<int>? originalColors,
    List<int>? modifiedColors,
    int? originalEffectId,
    int? modifiedEffectId,
  }) async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    final feedback = SuggestionFeedback(
      id: '${scheduleItemId}_${DateTime.now().millisecondsSinceEpoch}',
      scheduleItemId: scheduleItemId,
      patternName: patternName,
      trigger: trigger,
      feedbackType: type,
      timestamp: DateTime.now(),
      modificationNotes: modificationNotes,
      originalColors: originalColors,
      modifiedColors: modifiedColors,
      originalEffectId: originalEffectId,
      modifiedEffectId: modifiedEffectId,
    );

    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('autopilot_feedback')
          .doc(feedback.id)
          .set(feedback.toJson());

      // Trigger preference recalculation
      await _updateLearnedPreferences(userId);

      debugPrint('PreferenceLearning: Recorded ${type.name} feedback for $patternName');
    } catch (e) {
      debugPrint('PreferenceLearning: Failed to record feedback: $e');
    }
  }

  /// Get learned preferences for a user.
  Future<LearnedPreferences> getLearnedPreferences() async {
    final userId = _getCurrentUserId();
    if (userId == null) return LearnedPreferences.empty();

    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('learned_preferences')
          .doc('current')
          .get();

      if (doc.exists && doc.data() != null) {
        return LearnedPreferences.fromJson(doc.data()!);
      }
    } catch (e) {
      debugPrint('PreferenceLearning: Failed to get preferences: $e');
    }

    return LearnedPreferences.empty();
  }

  /// Get recent feedback for display/debugging.
  Future<List<SuggestionFeedback>> getRecentFeedback({int limit = 20}) async {
    final userId = _getCurrentUserId();
    if (userId == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('autopilot_feedback')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => SuggestionFeedback.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('PreferenceLearning: Failed to get recent feedback: $e');
      return [];
    }
  }

  /// Recalculate and store learned preferences based on feedback history.
  Future<void> _updateLearnedPreferences(String userId) async {
    try {
      // Get all feedback for this user
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('autopilot_feedback')
          .get();

      if (snapshot.docs.isEmpty) return;

      final feedbackList = snapshot.docs
          .map((doc) => SuggestionFeedback.fromJson(doc.data()))
          .toList();

      // Calculate trigger success rates
      final triggerCounts = <String, int>{};
      final triggerSuccesses = <String, int>{};

      for (final feedback in feedbackList) {
        final triggerName = feedback.trigger.name;
        triggerCounts[triggerName] = (triggerCounts[triggerName] ?? 0) + 1;

        if (feedback.feedbackType == FeedbackType.accepted ||
            feedback.feedbackType == FeedbackType.autoApplied) {
          triggerSuccesses[triggerName] = (triggerSuccesses[triggerName] ?? 0) + 1;
        }
      }

      final triggerSuccessRates = <String, double>{};
      for (final trigger in triggerCounts.keys) {
        final count = triggerCounts[trigger]!;
        final successes = triggerSuccesses[trigger] ?? 0;
        if (count >= 3) {
          // Only calculate rate if we have enough data
          triggerSuccessRates[trigger] = successes / count;
        }
      }

      // Calculate pattern success rates
      final patternCounts = <String, int>{};
      final patternSuccesses = <String, int>{};

      for (final feedback in feedbackList) {
        patternCounts[feedback.patternName] =
            (patternCounts[feedback.patternName] ?? 0) + 1;

        if (feedback.feedbackType == FeedbackType.accepted ||
            feedback.feedbackType == FeedbackType.autoApplied) {
          patternSuccesses[feedback.patternName] =
              (patternSuccesses[feedback.patternName] ?? 0) + 1;
        }
      }

      final patternSuccessRates = <String, double>{};
      for (final pattern in patternCounts.keys) {
        final count = patternCounts[pattern]!;
        final successes = patternSuccesses[pattern] ?? 0;
        if (count >= 2) {
          patternSuccessRates[pattern] = successes / count;
        }
      }

      // Identify avoided effects (rejected more than 50% of the time)
      final effectCounts = <int, int>{};
      final effectRejections = <int, int>{};

      for (final feedback in feedbackList) {
        if (feedback.originalEffectId != null) {
          effectCounts[feedback.originalEffectId!] =
              (effectCounts[feedback.originalEffectId!] ?? 0) + 1;

          if (feedback.feedbackType == FeedbackType.rejected) {
            effectRejections[feedback.originalEffectId!] =
                (effectRejections[feedback.originalEffectId!] ?? 0) + 1;
          }
        }
      }

      final avoidedEffectIds = <int>[];
      final preferredEffectIds = <int>[];

      for (final effectId in effectCounts.keys) {
        final count = effectCounts[effectId]!;
        final rejections = effectRejections[effectId] ?? 0;
        if (count >= 3) {
          final rejectionRate = rejections / count;
          if (rejectionRate > 0.5) {
            avoidedEffectIds.add(effectId);
          } else if (rejectionRate < 0.2) {
            preferredEffectIds.add(effectId);
          }
        }
      }

      // Identify preferred hours and days
      final hourAcceptances = <int, int>{};
      final hourCounts = <int, int>{};

      for (final feedback in feedbackList) {
        final hour = feedback.timestamp.hour;
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;

        if (feedback.feedbackType == FeedbackType.accepted ||
            feedback.feedbackType == FeedbackType.autoApplied) {
          hourAcceptances[hour] = (hourAcceptances[hour] ?? 0) + 1;
        }
      }

      final preferredHours = <int>[];
      for (final hour in hourCounts.keys) {
        if (hourCounts[hour]! >= 3) {
          final acceptanceRate = (hourAcceptances[hour] ?? 0) / hourCounts[hour]!;
          if (acceptanceRate > 0.7) {
            preferredHours.add(hour);
          }
        }
      }

      // Save learned preferences
      final learned = LearnedPreferences(
        preferredColors: const [], // Would need color tracking in feedback
        avoidedColors: const [],
        preferredEffectIds: preferredEffectIds,
        avoidedEffectIds: avoidedEffectIds,
        triggerSuccessRates: triggerSuccessRates,
        patternSuccessRates: patternSuccessRates,
        preferredHours: preferredHours,
        preferredDays: const [], // Would need day tracking
        totalFeedbackCount: feedbackList.length,
        lastUpdated: DateTime.now(),
      );

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('learned_preferences')
          .doc('current')
          .set(learned.toJson());

      debugPrint('PreferenceLearning: Updated preferences from ${feedbackList.length} feedback records');
    } catch (e) {
      debugPrint('PreferenceLearning: Failed to update preferences: $e');
    }
  }

  /// Adjust confidence score based on learned preferences.
  double adjustConfidence(
    double baseConfidence,
    AutopilotScheduleItem item,
    LearnedPreferences learned,
  ) {
    double adjusted = baseConfidence;

    // Adjust based on trigger success rate
    final triggerRate = learned.triggerSuccessRates[item.trigger.name];
    if (triggerRate != null) {
      // Blend base confidence with learned rate
      adjusted = adjusted * 0.5 + triggerRate * 0.5;
    }

    // Adjust based on pattern success rate
    final patternRate = learned.patternSuccessRates[item.patternName];
    if (patternRate != null) {
      adjusted = adjusted * 0.7 + patternRate * 0.3;
    }

    // Penalty for avoided effects
    if (item.effectId != null && learned.avoidedEffectIds.contains(item.effectId)) {
      adjusted -= 0.2;
    }

    // Boost for preferred effects
    if (item.effectId != null && learned.preferredEffectIds.contains(item.effectId)) {
      adjusted += 0.1;
    }

    // Time-based adjustment
    final hour = item.scheduledTime.hour;
    if (learned.preferredHours.contains(hour)) {
      adjusted += 0.05;
    }

    return adjusted.clamp(0.0, 1.0);
  }

  /// Clear all feedback and learned preferences.
  Future<void> clearAllFeedback() async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    try {
      // Delete all feedback documents
      final feedbackSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('autopilot_feedback')
          .get();

      for (final doc in feedbackSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete learned preferences
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('learned_preferences')
          .doc('current')
          .delete();

      debugPrint('PreferenceLearning: Cleared all feedback data');
    } catch (e) {
      debugPrint('PreferenceLearning: Failed to clear feedback: $e');
    }
  }

  String? _getCurrentUserId() {
    final profileAsync = _ref.read(currentUserProfileProvider);
    return profileAsync.maybeWhen(
      data: (p) => p?.id,
      orElse: () => null,
    );
  }
}

/// Provider for the preference learning service.
final preferenceLearningServiceProvider = Provider<PreferenceLearningService>(
  (ref) => PreferenceLearningService(ref),
);

/// Provider for the current user's learned preferences.
final learnedPreferencesProvider =
    FutureProvider.autoDispose<LearnedPreferences>((ref) async {
  final service = ref.watch(preferenceLearningServiceProvider);
  return service.getLearnedPreferences();
});
