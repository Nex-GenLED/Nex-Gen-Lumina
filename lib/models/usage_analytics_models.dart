import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Represents a single pattern usage event
class PatternUsageEvent {
  final String id;
  final DateTime createdAt;
  final String source; // 'lumina', 'manual', 'schedule', 'geofence', 'voice'
  final List<String>? colorNames;
  final int? effectId;
  final String? effectName;
  final int? paletteId;
  final int? brightness;
  final int? speed;
  final int? intensity;
  final Map<String, dynamic>? wledPayload;
  final String? patternName; // If applied from a saved pattern

  PatternUsageEvent({
    required this.id,
    required this.createdAt,
    required this.source,
    this.colorNames,
    this.effectId,
    this.effectName,
    this.paletteId,
    this.brightness,
    this.speed,
    this.intensity,
    this.wledPayload,
    this.patternName,
  });

  factory PatternUsageEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PatternUsageEvent(
      id: doc.id,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      source: (data['source'] as String?) ?? 'unknown',
      colorNames: (data['colors'] as List?)?.map((e) => e.toString()).toList(),
      effectId: (data['effect_id'] as num?)?.toInt(),
      effectName: data['effect_name'] as String?,
      paletteId: (data['palette_id'] as num?)?.toInt(),
      brightness: (data['brightness'] as num?)?.toInt(),
      speed: (data['speed'] as num?)?.toInt(),
      intensity: (data['intensity'] as num?)?.toInt(),
      wledPayload: data['wled'] as Map<String, dynamic>?,
      patternName: data['pattern_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'created_at': Timestamp.fromDate(createdAt),
      'source': source,
      if (colorNames != null && colorNames!.isNotEmpty) 'colors': colorNames,
      if (effectId != null) 'effect_id': effectId,
      if (effectName != null) 'effect_name': effectName,
      if (paletteId != null) 'palette_id': paletteId,
      if (brightness != null) 'brightness': brightness,
      if (speed != null) 'speed': speed,
      if (intensity != null) 'intensity': intensity,
      if (wledPayload != null) 'wled': wledPayload,
      if (patternName != null) 'pattern_name': patternName,
    };
  }
}

/// Aggregated usage statistics for a pattern
class PatternUsageStats {
  final String patternId;
  final String patternName;
  final int usageCount;
  final DateTime lastUsed;
  final DateTime firstUsed;
  final List<String> sources; // Which sources triggered this pattern
  final double avgBrightness;
  final List<Color>? primaryColors;
  final int? effectId;
  final String? effectName;

  PatternUsageStats({
    required this.patternId,
    required this.patternName,
    required this.usageCount,
    required this.lastUsed,
    required this.firstUsed,
    required this.sources,
    required this.avgBrightness,
    this.primaryColors,
    this.effectId,
    this.effectName,
  });

  /// Calculate score for ranking favorites (higher = more relevant)
  double get favoriteScore {
    // Recent usage is weighted more heavily
    final daysSinceLastUse = DateTime.now().difference(lastUsed).inDays;
    final recencyScore = 1.0 / (1.0 + daysSinceLastUse / 7.0); // Decay over weeks

    // Frequency matters
    final frequencyScore = usageCount.toDouble();

    // Combine with weights
    return (recencyScore * 10) + (frequencyScore * 2);
  }
}

/// Represents a behavioral pattern detected by the habit learner
class DetectedHabit {
  final String id;
  final HabitType type;
  final String description;
  final double confidence; // 0.0 - 1.0
  final DateTime detectedAt;
  final Map<String, dynamic> metadata;
  final String? suggestedScheduleId; // If we created a schedule suggestion

  DetectedHabit({
    required this.id,
    required this.type,
    required this.description,
    required this.confidence,
    required this.detectedAt,
    required this.metadata,
    this.suggestedScheduleId,
  });

  factory DetectedHabit.fromJson(Map<String, dynamic> json) {
    return DetectedHabit(
      id: json['id'] as String,
      type: HabitType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => HabitType.other,
      ),
      description: json['description'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      detectedAt: (json['detected_at'] as Timestamp).toDate(),
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
      suggestedScheduleId: json['suggested_schedule_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'description': description,
      'confidence': confidence,
      'detected_at': Timestamp.fromDate(detectedAt),
      'metadata': metadata,
      if (suggestedScheduleId != null) 'suggested_schedule_id': suggestedScheduleId,
    };
  }
}

/// Types of habits the system can detect
enum HabitType {
  timeOfDay, // User turns on/off lights at consistent times
  recurring, // User applies specific patterns on specific days
  contextual, // User responds to events (sunset, weather, etc.)
  preference, // User shows preference for certain colors/effects
  other,
}

/// A suggestion generated by the system
class SmartSuggestion {
  final String id;
  final SuggestionType type;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool dismissed;
  final Map<String, dynamic> actionData; // Data needed to execute the suggestion
  final String? relatedHabitId;
  final double priority; // 0.0 - 1.0, higher = more important

  SmartSuggestion({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.createdAt,
    this.expiresAt,
    this.dismissed = false,
    required this.actionData,
    this.relatedHabitId,
    required this.priority,
  });

  factory SmartSuggestion.fromJson(Map<String, dynamic> json) {
    return SmartSuggestion(
      id: json['id'] as String,
      type: SuggestionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SuggestionType.other,
      ),
      title: json['title'] as String,
      description: json['description'] as String,
      createdAt: (json['created_at'] as Timestamp).toDate(),
      expiresAt: (json['expires_at'] as Timestamp?)?.toDate(),
      dismissed: (json['dismissed'] as bool?) ?? false,
      actionData: (json['action_data'] as Map?)?.cast<String, dynamic>() ?? {},
      relatedHabitId: json['related_habit_id'] as String?,
      priority: (json['priority'] as num?)?.toDouble() ?? 0.5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'description': description,
      'created_at': Timestamp.fromDate(createdAt),
      if (expiresAt != null) 'expires_at': Timestamp.fromDate(expiresAt!),
      'dismissed': dismissed,
      'action_data': actionData,
      if (relatedHabitId != null) 'related_habit_id': relatedHabitId,
      'priority': priority,
    };
  }

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isActive => !dismissed && !isExpired;
}

/// Types of suggestions the system can make
enum SuggestionType {
  createSchedule, // Suggest creating a schedule based on usage patterns
  applyPattern, // Suggest applying a pattern now (e.g., sunset warm white)
  eventReminder, // Remind about upcoming event (game day, holiday)
  favorite, // Suggest adding to favorites
  automation, // Suggest enabling geofence or other automation
  optimization, // Suggest settings optimization
  other,
}

/// User's favorite patterns
class FavoritePattern {
  final String id;
  final String patternName;
  final DateTime addedAt;
  final DateTime? lastUsed;
  final int usageCount;
  final Map<String, dynamic> patternData; // The actual pattern/WLED payload
  final bool autoAdded; // True if added by learning system, false if manually added

  FavoritePattern({
    required this.id,
    required this.patternName,
    required this.addedAt,
    this.lastUsed,
    this.usageCount = 0,
    required this.patternData,
    this.autoAdded = false,
  });

  factory FavoritePattern.fromJson(Map<String, dynamic> json) {
    return FavoritePattern(
      id: json['id'] as String,
      patternName: json['pattern_name'] as String,
      addedAt: (json['added_at'] as Timestamp).toDate(),
      lastUsed: (json['last_used'] as Timestamp?)?.toDate(),
      usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
      patternData: (json['pattern_data'] as Map?)?.cast<String, dynamic>() ?? {},
      autoAdded: (json['auto_added'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pattern_name': patternName,
      'added_at': Timestamp.fromDate(addedAt),
      if (lastUsed != null) 'last_used': Timestamp.fromDate(lastUsed!),
      'usage_count': usageCount,
      'pattern_data': patternData,
      'auto_added': autoAdded,
    };
  }

  FavoritePattern copyWith({
    String? patternName,
    DateTime? lastUsed,
    int? usageCount,
    Map<String, dynamic>? patternData,
  }) {
    return FavoritePattern(
      id: id,
      patternName: patternName ?? this.patternName,
      addedAt: addedAt,
      lastUsed: lastUsed ?? this.lastUsed,
      usageCount: usageCount ?? this.usageCount,
      patternData: patternData ?? this.patternData,
      autoAdded: autoAdded,
    );
  }
}
