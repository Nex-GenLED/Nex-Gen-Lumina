import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents aggregated analytics for a pattern query across all users.
/// Stored in Firestore at `/pattern_analytics/{queryHash}`
///
/// This enables cross-user learning by tracking:
/// - Which patterns get the most positive feedback
/// - Common refinement requests
/// - Effect/color combinations that work well together
class PatternAnalytics {
  /// Unique identifier (hash of normalized query)
  final String id;

  /// Original query variants that map to this pattern
  /// e.g., ["christmas party", "christmas celebration", "xmas bash"]
  final List<String> queryVariants;

  /// Normalized/canonical query (used for matching)
  final String normalizedQuery;

  /// Total number of times this pattern was applied
  final int totalApplications;

  /// Number of thumbs-up reactions
  final int thumbsUp;

  /// Number of thumbs-down reactions
  final int thumbsDown;

  /// Approval rate (thumbsUp / totalApplications)
  double get approvalRate {
    if (totalApplications == 0) return 0.5;
    return thumbsUp / totalApplications;
  }

  /// Most successful effect ID based on feedback
  final int? bestEffectId;

  /// Most successful effect name
  final String? bestEffectName;

  /// Most successful color combination (as RGB arrays)
  final List<List<int>>? bestColors;

  /// Most successful color names for display
  final List<String>? bestColorNames;

  /// Average speed used across successful applications
  final int? avgSpeed;

  /// Average intensity used across successful applications
  final int? avgIntensity;

  /// Average brightness used across successful applications
  final int? avgBrightness;

  /// Common refinement requests for this pattern
  /// e.g., {"slower": 45, "brighter": 23, "different effect": 12}
  final Map<String, int> commonRefinements;

  /// Detected mood categories from user feedback
  final List<String> detectedMoods;

  /// Detected vibe descriptors from user feedback
  final List<String> detectedVibes;

  /// When this analytics entry was first created
  final DateTime createdAt;

  /// When this analytics entry was last updated
  final DateTime updatedAt;

  /// Number of unique users who applied this pattern
  final int uniqueUsers;

  /// Confidence score for recommendations (0.0 - 1.0)
  /// Based on sample size and approval rate
  double get confidenceScore {
    // Need at least 10 applications for reliable data
    if (totalApplications < 10) return 0.3;
    if (totalApplications < 50) return 0.5 + (approvalRate * 0.3);
    return 0.7 + (approvalRate * 0.3);
  }

  const PatternAnalytics({
    required this.id,
    required this.queryVariants,
    required this.normalizedQuery,
    required this.totalApplications,
    required this.thumbsUp,
    required this.thumbsDown,
    this.bestEffectId,
    this.bestEffectName,
    this.bestColors,
    this.bestColorNames,
    this.avgSpeed,
    this.avgIntensity,
    this.avgBrightness,
    this.commonRefinements = const {},
    this.detectedMoods = const [],
    this.detectedVibes = const [],
    required this.createdAt,
    required this.updatedAt,
    this.uniqueUsers = 0,
  });

  factory PatternAnalytics.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PatternAnalytics(
      id: doc.id,
      queryVariants: (data['query_variants'] as List?)?.cast<String>() ?? [],
      normalizedQuery: data['normalized_query'] as String? ?? '',
      totalApplications: (data['total_applications'] as num?)?.toInt() ?? 0,
      thumbsUp: (data['thumbs_up'] as num?)?.toInt() ?? 0,
      thumbsDown: (data['thumbs_down'] as num?)?.toInt() ?? 0,
      bestEffectId: (data['best_effect_id'] as num?)?.toInt(),
      bestEffectName: data['best_effect_name'] as String?,
      bestColors: (data['best_colors'] as List?)
          ?.map((c) => (c as List).cast<int>())
          .toList(),
      bestColorNames: (data['best_color_names'] as List?)?.cast<String>(),
      avgSpeed: (data['avg_speed'] as num?)?.toInt(),
      avgIntensity: (data['avg_intensity'] as num?)?.toInt(),
      avgBrightness: (data['avg_brightness'] as num?)?.toInt(),
      commonRefinements: (data['common_refinements'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          {},
      detectedMoods: (data['detected_moods'] as List?)?.cast<String>() ?? [],
      detectedVibes: (data['detected_vibes'] as List?)?.cast<String>() ?? [],
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      uniqueUsers: (data['unique_users'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'query_variants': queryVariants,
      'normalized_query': normalizedQuery,
      'total_applications': totalApplications,
      'thumbs_up': thumbsUp,
      'thumbs_down': thumbsDown,
      if (bestEffectId != null) 'best_effect_id': bestEffectId,
      if (bestEffectName != null) 'best_effect_name': bestEffectName,
      if (bestColors != null) 'best_colors': bestColors,
      if (bestColorNames != null) 'best_color_names': bestColorNames,
      if (avgSpeed != null) 'avg_speed': avgSpeed,
      if (avgIntensity != null) 'avg_intensity': avgIntensity,
      if (avgBrightness != null) 'avg_brightness': avgBrightness,
      'common_refinements': commonRefinements,
      'detected_moods': detectedMoods,
      'detected_vibes': detectedVibes,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'unique_users': uniqueUsers,
    };
  }

  PatternAnalytics copyWith({
    String? id,
    List<String>? queryVariants,
    String? normalizedQuery,
    int? totalApplications,
    int? thumbsUp,
    int? thumbsDown,
    int? bestEffectId,
    String? bestEffectName,
    List<List<int>>? bestColors,
    List<String>? bestColorNames,
    int? avgSpeed,
    int? avgIntensity,
    int? avgBrightness,
    Map<String, int>? commonRefinements,
    List<String>? detectedMoods,
    List<String>? detectedVibes,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? uniqueUsers,
  }) {
    return PatternAnalytics(
      id: id ?? this.id,
      queryVariants: queryVariants ?? this.queryVariants,
      normalizedQuery: normalizedQuery ?? this.normalizedQuery,
      totalApplications: totalApplications ?? this.totalApplications,
      thumbsUp: thumbsUp ?? this.thumbsUp,
      thumbsDown: thumbsDown ?? this.thumbsDown,
      bestEffectId: bestEffectId ?? this.bestEffectId,
      bestEffectName: bestEffectName ?? this.bestEffectName,
      bestColors: bestColors ?? this.bestColors,
      bestColorNames: bestColorNames ?? this.bestColorNames,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      avgIntensity: avgIntensity ?? this.avgIntensity,
      avgBrightness: avgBrightness ?? this.avgBrightness,
      commonRefinements: commonRefinements ?? this.commonRefinements,
      detectedMoods: detectedMoods ?? this.detectedMoods,
      detectedVibes: detectedVibes ?? this.detectedVibes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      uniqueUsers: uniqueUsers ?? this.uniqueUsers,
    );
  }
}

/// Represents a single feedback event from a user
/// Stored in Firestore at `/pattern_feedback/{id}`
/// Used to aggregate into PatternAnalytics
class PatternFeedbackEvent {
  final String id;
  final String? userId;
  final String queryHash;
  final String originalQuery;
  final FeedbackType feedbackType;
  final int? effectId;
  final String? effectName;
  final List<List<int>>? colors;
  final List<String>? colorNames;
  final int? speed;
  final int? intensity;
  final int? brightness;
  final String? refinementType;
  final String? feedbackReason;
  final DateTime createdAt;
  final Map<String, dynamic>? wledPayload;

  const PatternFeedbackEvent({
    required this.id,
    this.userId,
    required this.queryHash,
    required this.originalQuery,
    required this.feedbackType,
    this.effectId,
    this.effectName,
    this.colors,
    this.colorNames,
    this.speed,
    this.intensity,
    this.brightness,
    this.refinementType,
    this.feedbackReason,
    required this.createdAt,
    this.wledPayload,
  });

  factory PatternFeedbackEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PatternFeedbackEvent(
      id: doc.id,
      userId: data['user_id'] as String?,
      queryHash: data['query_hash'] as String? ?? '',
      originalQuery: data['original_query'] as String? ?? '',
      feedbackType: FeedbackType.values.firstWhere(
        (e) => e.name == data['feedback_type'],
        orElse: () => FeedbackType.applied,
      ),
      effectId: (data['effect_id'] as num?)?.toInt(),
      effectName: data['effect_name'] as String?,
      colors: (data['colors'] as List?)
          ?.map((c) => (c as List).cast<int>())
          .toList(),
      colorNames: (data['color_names'] as List?)?.cast<String>(),
      speed: (data['speed'] as num?)?.toInt(),
      intensity: (data['intensity'] as num?)?.toInt(),
      brightness: (data['brightness'] as num?)?.toInt(),
      refinementType: data['refinement_type'] as String?,
      feedbackReason: data['feedback_reason'] as String?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      wledPayload: data['wled_payload'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (userId != null) 'user_id': userId,
      'query_hash': queryHash,
      'original_query': originalQuery,
      'feedback_type': feedbackType.name,
      if (effectId != null) 'effect_id': effectId,
      if (effectName != null) 'effect_name': effectName,
      if (colors != null) 'colors': colors,
      if (colorNames != null) 'color_names': colorNames,
      if (speed != null) 'speed': speed,
      if (intensity != null) 'intensity': intensity,
      if (brightness != null) 'brightness': brightness,
      if (refinementType != null) 'refinement_type': refinementType,
      if (feedbackReason != null) 'feedback_reason': feedbackReason,
      'created_at': Timestamp.fromDate(createdAt),
      if (wledPayload != null) 'wled_payload': wledPayload,
    };
  }
}

/// Types of feedback events
enum FeedbackType {
  /// Pattern was applied to lights
  applied,

  /// User gave thumbs up
  thumbsUp,

  /// User gave thumbs down
  thumbsDown,

  /// User requested a refinement
  refined,

  /// User dismissed/cancelled
  dismissed,
}

/// Represents a correction record when user says "Wrong Vibe"
/// Used to improve vibe detection over time
class VibeCorrectionRecord {
  final String id;
  final String? userId;
  final String originalQuery;
  final String detectedVibe;
  final String desiredVibe;
  final int? originalEffectId;
  final int? suggestedEffectId;
  final DateTime createdAt;

  const VibeCorrectionRecord({
    required this.id,
    this.userId,
    required this.originalQuery,
    required this.detectedVibe,
    required this.desiredVibe,
    this.originalEffectId,
    this.suggestedEffectId,
    required this.createdAt,
  });

  factory VibeCorrectionRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VibeCorrectionRecord(
      id: doc.id,
      userId: data['user_id'] as String?,
      originalQuery: data['original_query'] as String? ?? '',
      detectedVibe: data['detected_vibe'] as String? ?? '',
      desiredVibe: data['desired_vibe'] as String? ?? '',
      originalEffectId: (data['original_effect_id'] as num?)?.toInt(),
      suggestedEffectId: (data['suggested_effect_id'] as num?)?.toInt(),
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (userId != null) 'user_id': userId,
      'original_query': originalQuery,
      'detected_vibe': detectedVibe,
      'desired_vibe': desiredVibe,
      if (originalEffectId != null) 'original_effect_id': originalEffectId,
      if (suggestedEffectId != null) 'suggested_effect_id': suggestedEffectId,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}

/// Represents a learned pattern preference that can be recommended
class LearnedPatternPreference {
  final String id;
  final String patternName;
  final String description;
  final int effectId;
  final String effectName;
  final List<List<int>> colors;
  final List<String> colorNames;
  final int speed;
  final int intensity;
  final int brightness;
  final double approvalRate;
  final int sampleSize;
  final List<String> matchingQueries;
  final DateTime learnedAt;

  const LearnedPatternPreference({
    required this.id,
    required this.patternName,
    required this.description,
    required this.effectId,
    required this.effectName,
    required this.colors,
    required this.colorNames,
    required this.speed,
    required this.intensity,
    required this.brightness,
    required this.approvalRate,
    required this.sampleSize,
    required this.matchingQueries,
    required this.learnedAt,
  });

  factory LearnedPatternPreference.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LearnedPatternPreference(
      id: doc.id,
      patternName: data['pattern_name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      effectId: (data['effect_id'] as num?)?.toInt() ?? 0,
      effectName: data['effect_name'] as String? ?? '',
      colors: (data['colors'] as List?)
              ?.map((c) => (c as List).cast<int>())
              .toList() ??
          [],
      colorNames: (data['color_names'] as List?)?.cast<String>() ?? [],
      speed: (data['speed'] as num?)?.toInt() ?? 128,
      intensity: (data['intensity'] as num?)?.toInt() ?? 128,
      brightness: (data['brightness'] as num?)?.toInt() ?? 210,
      approvalRate: (data['approval_rate'] as num?)?.toDouble() ?? 0.0,
      sampleSize: (data['sample_size'] as num?)?.toInt() ?? 0,
      matchingQueries:
          (data['matching_queries'] as List?)?.cast<String>() ?? [],
      learnedAt:
          (data['learned_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'pattern_name': patternName,
      'description': description,
      'effect_id': effectId,
      'effect_name': effectName,
      'colors': colors,
      'color_names': colorNames,
      'speed': speed,
      'intensity': intensity,
      'brightness': brightness,
      'approval_rate': approvalRate,
      'sample_size': sampleSize,
      'matching_queries': matchingQueries,
      'learned_at': Timestamp.fromDate(learnedAt),
    };
  }

  /// Generate WLED payload from this preference
  Map<String, dynamic> toWledPayload() {
    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
          'col': colors.map((c) => [...c, 0]).toList(),
        }
      ]
    };
  }
}
