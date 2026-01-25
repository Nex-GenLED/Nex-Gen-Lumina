import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Global pattern statistics aggregated across all users
class GlobalPatternStats {
  final String patternId;
  final String patternName;
  final String? category;
  final int totalApplications;
  final int uniqueUsers;
  final double avgWeeklyApplications;
  final double last30DaysGrowth;
  final List<List<int>>? colorPalette;
  final int? effectId;
  final List<String> tags;
  final DateTime firstSeen;
  final DateTime lastUpdated;

  const GlobalPatternStats({
    required this.patternId,
    required this.patternName,
    this.category,
    required this.totalApplications,
    required this.uniqueUsers,
    required this.avgWeeklyApplications,
    required this.last30DaysGrowth,
    this.colorPalette,
    this.effectId,
    required this.tags,
    required this.firstSeen,
    required this.lastUpdated,
  });

  factory GlobalPatternStats.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GlobalPatternStats(
      patternId: doc.id,
      patternName: data['pattern_name'] as String? ?? '',
      category: data['category'] as String?,
      totalApplications: (data['total_applications'] as num?)?.toInt() ?? 0,
      uniqueUsers: (data['unique_users'] as num?)?.toInt() ?? 0,
      avgWeeklyApplications: (data['avg_weekly_applications'] as num?)?.toDouble() ?? 0.0,
      last30DaysGrowth: (data['last_30_days_growth'] as num?)?.toDouble() ?? 0.0,
      colorPalette: (data['color_palette'] as List?)
          ?.map((c) => (c as List).map((v) => (v as num).toInt()).toList())
          .toList(),
      effectId: (data['effect_id'] as num?)?.toInt(),
      tags: (data['tags'] as List?)?.map((t) => t.toString()).toList() ?? [],
      firstSeen: (data['first_seen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUpdated: (data['last_updated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'pattern_name': patternName,
        'category': category,
        'total_applications': totalApplications,
        'unique_users': uniqueUsers,
        'avg_weekly_applications': avgWeeklyApplications,
        'last_30_days_growth': last30DaysGrowth,
        'color_palette': colorPalette,
        'effect_id': effectId,
        'tags': tags,
        'first_seen': Timestamp.fromDate(firstSeen),
        'last_updated': Timestamp.fromDate(lastUpdated),
      };

  /// Calculate a trending score (higher = more trending)
  double get trendingScore {
    // Weight recent growth heavily
    final growthScore = last30DaysGrowth * 10;
    // Weight unique users moderately
    final userScore = uniqueUsers.toDouble() * 0.5;
    // Weight total applications lightly
    final applicationScore = totalApplications.toDouble() * 0.1;

    return growthScore + userScore + applicationScore;
  }

  /// Is this pattern trending upward?
  bool get isTrending => last30DaysGrowth > 0.2; // 20% growth

  /// Is this pattern new (< 30 days old)?
  bool get isNew => DateTime.now().difference(firstSeen).inDays < 30;
}

/// Weekly trending patterns report
class TrendingReport {
  final String id;
  final DateTime weekOf;
  final List<TrendingPattern> topPatterns;
  final List<TrendingPattern> emergingPatterns;
  final List<TrendingPattern> decliningPatterns;
  final DateTime generatedAt;

  const TrendingReport({
    required this.id,
    required this.weekOf,
    required this.topPatterns,
    required this.emergingPatterns,
    required this.decliningPatterns,
    required this.generatedAt,
  });

  factory TrendingReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TrendingReport(
      id: doc.id,
      weekOf: (data['week_of'] as Timestamp?)?.toDate() ?? DateTime.now(),
      topPatterns: (data['top_patterns'] as List?)
              ?.map((p) => TrendingPattern.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      emergingPatterns: (data['emerging_patterns'] as List?)
              ?.map((p) => TrendingPattern.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      decliningPatterns: (data['declining_patterns'] as List?)
              ?.map((p) => TrendingPattern.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      generatedAt: (data['generated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'week_of': Timestamp.fromDate(weekOf),
        'top_patterns': topPatterns.map((p) => p.toJson()).toList(),
        'emerging_patterns': emergingPatterns.map((p) => p.toJson()).toList(),
        'declining_patterns': decliningPatterns.map((p) => p.toJson()).toList(),
        'generated_at': Timestamp.fromDate(generatedAt),
      };
}

/// Individual pattern in a trending report
class TrendingPattern {
  final String patternName;
  final int usageCount;
  final double growthRate;
  final int rank;

  const TrendingPattern({
    required this.patternName,
    required this.usageCount,
    required this.growthRate,
    required this.rank,
  });

  factory TrendingPattern.fromJson(Map<String, dynamic> json) => TrendingPattern(
        patternName: json['pattern_name'] as String? ?? '',
        usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
        growthRate: (json['growth_rate'] as num?)?.toDouble() ?? 0.0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'pattern_name': patternName,
        'usage_count': usageCount,
        'growth_rate': growthRate,
        'rank': rank,
      };
}

/// Color trend data
class ColorTrend {
  final String id;
  final DateTime weekOf;
  final List<PopularColor> topColors;
  final List<ColorCombination> topCombinations;
  final Map<String, dynamic> seasonalPreferences;
  final DateTime generatedAt;

  const ColorTrend({
    required this.id,
    required this.weekOf,
    required this.topColors,
    required this.topCombinations,
    required this.seasonalPreferences,
    required this.generatedAt,
  });

  factory ColorTrend.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ColorTrend(
      id: doc.id,
      weekOf: (data['week_of'] as Timestamp?)?.toDate() ?? DateTime.now(),
      topColors: (data['top_colors'] as List?)
              ?.map((c) => PopularColor.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      topCombinations: (data['top_combinations'] as List?)
              ?.map((c) => ColorCombination.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      seasonalPreferences: (data['seasonal_preferences'] as Map<String, dynamic>?) ?? {},
      generatedAt: (data['generated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'week_of': Timestamp.fromDate(weekOf),
        'top_colors': topColors.map((c) => c.toJson()).toList(),
        'top_combinations': topCombinations.map((c) => c.toJson()).toList(),
        'seasonal_preferences': seasonalPreferences,
        'generated_at': Timestamp.fromDate(generatedAt),
      };
}

/// Popular color data
class PopularColor {
  final List<int> rgb;
  final int usageCount;
  final String? colorName;

  const PopularColor({
    required this.rgb,
    required this.usageCount,
    this.colorName,
  });

  factory PopularColor.fromJson(Map<String, dynamic> json) => PopularColor(
        rgb: (json['rgb'] as List).map((v) => (v as num).toInt()).toList(),
        usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
        colorName: json['color_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'rgb': rgb,
        'usage_count': usageCount,
        'color_name': colorName,
      };
}

/// Color combination data
class ColorCombination {
  final List<List<int>> colors;
  final int usageCount;
  final String? patternName;

  const ColorCombination({
    required this.colors,
    required this.usageCount,
    this.patternName,
  });

  factory ColorCombination.fromJson(Map<String, dynamic> json) => ColorCombination(
        colors: (json['colors'] as List)
            .map((c) => (c as List).map((v) => (v as num).toInt()).toList())
            .toList(),
        usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
        patternName: json['pattern_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'colors': colors,
        'usage_count': usageCount,
        'pattern_name': patternName,
      };
}

/// Effect popularity data
class EffectPopularity {
  final int effectId;
  final String effectName;
  final int usageCount;
  final double avgSpeed;
  final double avgIntensity;
  final List<PopularColor> preferredColors;
  final DateTime lastUpdated;

  const EffectPopularity({
    required this.effectId,
    required this.effectName,
    required this.usageCount,
    required this.avgSpeed,
    required this.avgIntensity,
    required this.preferredColors,
    required this.lastUpdated,
  });

  factory EffectPopularity.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EffectPopularity(
      effectId: (data['effect_id'] as num?)?.toInt() ?? 0,
      effectName: data['effect_name'] as String? ?? '',
      usageCount: (data['usage_count'] as num?)?.toInt() ?? 0,
      avgSpeed: (data['avg_speed'] as num?)?.toDouble() ?? 128.0,
      avgIntensity: (data['avg_intensity'] as num?)?.toDouble() ?? 128.0,
      preferredColors: (data['preferred_colors'] as List?)
              ?.map((c) => PopularColor.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      lastUpdated: (data['last_updated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'effect_id': effectId,
        'effect_name': effectName,
        'usage_count': usageCount,
        'avg_speed': avgSpeed,
        'avg_intensity': avgIntensity,
        'preferred_colors': preferredColors.map((c) => c.toJson()).toList(),
        'last_updated': Timestamp.fromDate(lastUpdated),
      };
}

/// Pattern feedback from users
class PatternFeedback {
  final String id;
  final String patternName;
  final int rating; // 1-5 stars
  final String? comment;
  final bool saved;
  final DateTime createdAt;
  final String? source; // 'pattern_library', 'lumina_ai', etc.

  const PatternFeedback({
    required this.id,
    required this.patternName,
    required this.rating,
    this.comment,
    required this.saved,
    required this.createdAt,
    this.source,
  });

  factory PatternFeedback.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PatternFeedback(
      id: doc.id,
      patternName: data['pattern_name'] as String? ?? '',
      rating: (data['rating'] as num?)?.toInt() ?? 3,
      comment: data['comment'] as String?,
      saved: data['saved'] as bool? ?? false,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      source: data['source'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'pattern_name': patternName,
        'rating': rating,
        'comment': comment,
        'saved': saved,
        'created_at': Timestamp.fromDate(createdAt),
        'source': source,
      };
}

/// Pattern request from user (missing patterns)
class PatternRequest {
  final String id;
  final String requestedTheme;
  final String? description;
  final List<String>? suggestedColors;
  final String? suggestedCategory;
  final DateTime createdAt;
  final int voteCount;
  final bool fulfilled;

  const PatternRequest({
    required this.id,
    required this.requestedTheme,
    this.description,
    this.suggestedColors,
    this.suggestedCategory,
    required this.createdAt,
    required this.voteCount,
    required this.fulfilled,
  });

  factory PatternRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PatternRequest(
      id: doc.id,
      requestedTheme: data['requested_theme'] as String? ?? '',
      description: data['description'] as String?,
      suggestedColors: (data['suggested_colors'] as List?)?.map((c) => c.toString()).toList(),
      suggestedCategory: data['suggested_category'] as String?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      voteCount: (data['vote_count'] as num?)?.toInt() ?? 1,
      fulfilled: data['fulfilled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'requested_theme': requestedTheme,
        'description': description,
        'suggested_colors': suggestedColors,
        'suggested_category': suggestedCategory,
        'created_at': Timestamp.fromDate(createdAt),
        'vote_count': voteCount,
        'fulfilled': fulfilled,
      };
}
