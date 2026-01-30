// Models for Pattern Library
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/effect_database.dart';

/// Represents a folder/category for patterns in the Pattern Library.
class PatternCategory {
  final String id;
  final String name;
  final String imageUrl;

  const PatternCategory({required this.id, required this.name, required this.imageUrl});

  factory PatternCategory.fromJson(Map<String, dynamic> json) => PatternCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'imageUrl': imageUrl};
}

/// Represents an individual pattern/effect, including its WLED JSON payload.
class PatternItem {
  final String id;
  final String name;
  final String imageUrl;
  final String categoryId;
  final Map<String, dynamic> wledPayload;

  const PatternItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.categoryId,
    required this.wledPayload,
  });

  factory PatternItem.fromJson(Map<String, dynamic> json) => PatternItem(
        id: json['id'] as String,
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String,
        categoryId: json['categoryId'] as String,
        wledPayload: (json['wledPayload'] as Map).cast<String, dynamic>(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        'categoryId': categoryId,
        'wledPayload': wledPayload,
      };

  PatternItem copyWith({String? name, String? imageUrl, String? categoryId, Map<String, dynamic>? wledPayload}) => PatternItem(
        id: id,
        name: name ?? this.name,
        imageUrl: imageUrl ?? this.imageUrl,
        categoryId: categoryId ?? this.categoryId,
        wledPayload: wledPayload != null ? Map<String, dynamic>.from(wledPayload) : this.wledPayload,
      );

  @override
  String toString() => 'PatternItem(id: '+id+', name: '+name+')';
}

/// Represents a Sub-Category under a main PatternCategory.
/// Each sub-category carries a small palette of theme colors to drive UI presets.
class SubCategory {
  final String id;
  final String name;
  final List<Color> themeColors;
  final String parentCategoryId;

  const SubCategory({required this.id, required this.name, required this.themeColors, required this.parentCategoryId});

  factory SubCategory.fromJson(Map<String, dynamic> json) => SubCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        themeColors: ((json['themeColors'] as List?) ?? const <dynamic>[])
            .whereType<int>()
            .map((v) => Color(v))
            .toList(growable: false),
        parentCategoryId: json['parentCategoryId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        // Store theme colors as ARGB ints
        'themeColors': themeColors.map((c) => c.value).toList(growable: false),
        'parentCategoryId': parentCategoryId,
      };
}

/// Mood categories for semantic pattern matching
enum PatternMood {
  calm,
  romantic,
  elegant,
  festive,
  mysterious,
  playful,
  magical,
  cozy,
  energetic,
  dramatic,
}

/// Vibe descriptors for fine-grained matching
enum PatternVibe {
  serene,
  dreamy,
  intimate,
  luxurious,
  joyful,
  exciting,
  spooky,
  whimsical,
  majestic,
  tranquil,
  vibrant,
  subtle,
  bold,
  gentle,
  dynamic,
  warm,
  cool,
  natural,
  modern,
}

/// Color family categorization
enum ColorFamily {
  warm,      // reds, oranges, yellows
  cool,      // blues, purples, cyans
  neutral,   // whites, grays, blacks
  pastel,    // soft muted colors
  neon,      // bright saturated colors
  earthTone, // browns, greens, natural
  jewel,     // deep rich colors
  monochrome, // single color variations
}

/// Rich data model for pattern suggestions/previews.
///
/// Used by the Pattern Library UI and recommendation engines.
/// Includes effect details, motion type, direction, and WLED payload.
///
/// IMPORTANT: When choosing effectId, be aware that some WLED effects are
/// "palette-based" and ignore the segment colors (col array). These include:
/// - 110 (Flow), 9 (Colorful), 11 (Rainbow), 63 (Pride 2015), etc.
///
/// Effects that properly use segment colors include:
/// - 0 (Solid), 1 (Blink), 2 (Breathe), 9 (Chase), 12 (Theater Chase),
/// - 28 (Chase 2), 41 (Running), 42 (Saw), 65 (Comet), 66 (Fireworks), etc.
class GradientPattern {
  final String name;
  final String? subtitle; // e.g., "Gold chasing Red" or "Static warm glow"
  final List<Color> colors;
  final int effectId; // WLED fx value
  final String? effectName; // e.g., "Chase", "Breathe", "Solid"
  final String? direction; // e.g., "left", "right", "center-out", "none"
  final bool isStatic;
  final int speed; // 0-255
  final int intensity; // 0-255
  final int brightness; // 0-255

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: Rich semantic metadata for improved AI matching
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary moods this pattern evokes (e.g., calm, festive, romantic)
  final Set<PatternMood> moods;

  /// Vibe descriptors for fine-grained matching (e.g., dreamy, bold, cozy)
  final Set<PatternVibe> vibes;

  /// Color family categorization for quick filtering
  final Set<ColorFamily> colorFamilies;

  /// Occasions/contexts this pattern is ideal for
  final Set<String> idealOccasions;

  /// Occasions/contexts to avoid recommending this pattern
  final Set<String> avoidOccasions;

  /// Human-readable color names for display and AI context
  final List<String> colorNames;

  /// Keywords that should trigger this pattern
  final Set<String> keywords;

  /// Confidence score for recommendations (0.0 - 1.0)
  /// Higher = more universally liked, lower = more niche
  final double universalAppeal;

  const GradientPattern({
    required this.name,
    this.subtitle,
    required this.colors,
    this.effectId = 0,
    this.effectName,
    this.direction,
    this.isStatic = true,
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 210,
    // New semantic fields with sensible defaults
    this.moods = const {},
    this.vibes = const {},
    this.colorFamilies = const {},
    this.idealOccasions = const {},
    this.avoidOccasions = const {},
    this.colorNames = const [],
    this.keywords = const {},
    this.universalAppeal = 0.5,
  });

  /// Check if this pattern's effect respects user colors
  bool get effectRespectsColors {
    return EffectDatabase.effectRespectsColors(effectId);
  }

  /// Get the effect metadata from the database
  EffectMetadata? get effectMetadata {
    return EffectDatabase.getEffect(effectId);
  }

  /// Check if pattern matches a given mood
  bool matchesMood(PatternMood mood) => moods.contains(mood);

  /// Check if pattern matches any of the given moods
  bool matchesAnyMood(Set<PatternMood> targetMoods) {
    if (moods.isEmpty || targetMoods.isEmpty) return false;
    return moods.intersection(targetMoods).isNotEmpty;
  }

  /// Check if pattern has a specific vibe
  bool hasVibe(PatternVibe vibe) => vibes.contains(vibe);

  /// Check if pattern is suitable for an occasion
  bool suitableForOccasion(String occasion) {
    final lower = occasion.toLowerCase();
    if (avoidOccasions.contains(lower)) return false;
    return idealOccasions.isEmpty || idealOccasions.contains(lower);
  }

  /// Check if pattern contains a specific keyword
  bool matchesKeyword(String keyword) {
    final lower = keyword.toLowerCase();
    return keywords.any((k) => k.toLowerCase().contains(lower) || lower.contains(k.toLowerCase()));
  }

  /// Calculate match score against query criteria (0.0 - 1.0)
  double calculateMatchScore({
    Set<PatternMood>? targetMoods,
    Set<PatternVibe>? targetVibes,
    Set<ColorFamily>? targetColorFamilies,
    String? occasion,
    List<String>? queryKeywords,
  }) {
    double score = 0.0;
    int factors = 0;

    // Mood matching (weighted heavily)
    if (targetMoods != null && targetMoods.isNotEmpty) {
      factors += 3;
      if (moods.isNotEmpty) {
        final moodOverlap = moods.intersection(targetMoods).length;
        score += 3 * (moodOverlap / targetMoods.length);
      }
    }

    // Vibe matching
    if (targetVibes != null && targetVibes.isNotEmpty) {
      factors += 2;
      if (vibes.isNotEmpty) {
        final vibeOverlap = vibes.intersection(targetVibes).length;
        score += 2 * (vibeOverlap / targetVibes.length);
      }
    }

    // Color family matching
    if (targetColorFamilies != null && targetColorFamilies.isNotEmpty) {
      factors += 2;
      if (colorFamilies.isNotEmpty) {
        final colorOverlap = colorFamilies.intersection(targetColorFamilies).length;
        score += 2 * (colorOverlap / targetColorFamilies.length);
      }
    }

    // Occasion matching
    if (occasion != null && occasion.isNotEmpty) {
      factors += 2;
      if (idealOccasions.contains(occasion.toLowerCase())) {
        score += 2;
      } else if (avoidOccasions.contains(occasion.toLowerCase())) {
        score -= 1; // Penalty
      }
    }

    // Keyword matching
    if (queryKeywords != null && queryKeywords.isNotEmpty) {
      factors += 1;
      final matches = queryKeywords.where(matchesKeyword).length;
      score += (matches / queryKeywords.length);
    }

    // Apply universal appeal as a modifier
    if (factors > 0) {
      final baseScore = score / factors;
      return baseScore * 0.8 + universalAppeal * 0.2;
    }

    return universalAppeal;
  }

  /// Generate WLED payload from this pattern
  /// Forces W=0 for saturated colors to maintain color accuracy
  Map<String, dynamic> toWledPayload() {
    // Force W=0 for pattern colors to prevent white LED from washing out saturated colors
    final cols = colors.take(3).map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true)).toList();
    if (cols.isEmpty) cols.add(rgbToRgbw(255, 255, 255, forceZeroWhite: true));

    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
          'pal': 0,
          'col': cols,
        }
      ]
    };
  }

  /// Create a copy with updated fields
  GradientPattern copyWith({
    String? name,
    String? subtitle,
    List<Color>? colors,
    int? effectId,
    String? effectName,
    String? direction,
    bool? isStatic,
    int? speed,
    int? intensity,
    int? brightness,
    Set<PatternMood>? moods,
    Set<PatternVibe>? vibes,
    Set<ColorFamily>? colorFamilies,
    Set<String>? idealOccasions,
    Set<String>? avoidOccasions,
    List<String>? colorNames,
    Set<String>? keywords,
    double? universalAppeal,
  }) {
    return GradientPattern(
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      colors: colors ?? this.colors,
      effectId: effectId ?? this.effectId,
      effectName: effectName ?? this.effectName,
      direction: direction ?? this.direction,
      isStatic: isStatic ?? this.isStatic,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      moods: moods ?? this.moods,
      vibes: vibes ?? this.vibes,
      colorFamilies: colorFamilies ?? this.colorFamilies,
      idealOccasions: idealOccasions ?? this.idealOccasions,
      avoidOccasions: avoidOccasions ?? this.avoidOccasions,
      colorNames: colorNames ?? this.colorNames,
      keywords: keywords ?? this.keywords,
      universalAppeal: universalAppeal ?? this.universalAppeal,
    );
  }

  /// Convert to JSON for storage/transmission
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'subtitle': subtitle,
      'colors': colors.map((c) => c.value).toList(),
      'effectId': effectId,
      'effectName': effectName,
      'direction': direction,
      'isStatic': isStatic,
      'speed': speed,
      'intensity': intensity,
      'brightness': brightness,
      'moods': moods.map((m) => m.name).toList(),
      'vibes': vibes.map((v) => v.name).toList(),
      'colorFamilies': colorFamilies.map((c) => c.name).toList(),
      'idealOccasions': idealOccasions.toList(),
      'avoidOccasions': avoidOccasions.toList(),
      'colorNames': colorNames,
      'keywords': keywords.toList(),
      'universalAppeal': universalAppeal,
    };
  }

  /// Create from JSON
  factory GradientPattern.fromJson(Map<String, dynamic> json) {
    return GradientPattern(
      name: json['name'] as String,
      subtitle: json['subtitle'] as String?,
      colors: (json['colors'] as List?)
          ?.map((c) => Color(c as int))
          .toList() ?? const [],
      effectId: json['effectId'] as int? ?? 0,
      effectName: json['effectName'] as String?,
      direction: json['direction'] as String?,
      isStatic: json['isStatic'] as bool? ?? true,
      speed: json['speed'] as int? ?? 128,
      intensity: json['intensity'] as int? ?? 128,
      brightness: json['brightness'] as int? ?? 210,
      moods: (json['moods'] as List?)
          ?.map((m) => PatternMood.values.firstWhere(
                (e) => e.name == m,
                orElse: () => PatternMood.calm,
              ))
          .toSet() ?? const {},
      vibes: (json['vibes'] as List?)
          ?.map((v) => PatternVibe.values.firstWhere(
                (e) => e.name == v,
                orElse: () => PatternVibe.subtle,
              ))
          .toSet() ?? const {},
      colorFamilies: (json['colorFamilies'] as List?)
          ?.map((c) => ColorFamily.values.firstWhere(
                (e) => e.name == c,
                orElse: () => ColorFamily.neutral,
              ))
          .toSet() ?? const {},
      idealOccasions: (json['idealOccasions'] as List?)?.cast<String>().toSet() ?? const {},
      avoidOccasions: (json['avoidOccasions'] as List?)?.cast<String>().toSet() ?? const {},
      colorNames: (json['colorNames'] as List?)?.cast<String>() ?? const [],
      keywords: (json['keywords'] as List?)?.cast<String>().toSet() ?? const {},
      universalAppeal: (json['universalAppeal'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// Extension to help convert between mood systems
extension PatternMoodExtension on PatternMood {
  /// Convert to EffectMoodCategory for database lookups
  EffectMoodCategory? toEffectMoodCategory() {
    switch (this) {
      case PatternMood.calm:
        return EffectMoodCategory.calm;
      case PatternMood.romantic:
        return EffectMoodCategory.romantic;
      case PatternMood.elegant:
        return EffectMoodCategory.elegant;
      case PatternMood.festive:
        return EffectMoodCategory.festive;
      case PatternMood.mysterious:
        return EffectMoodCategory.mysterious;
      case PatternMood.playful:
        return EffectMoodCategory.playful;
      case PatternMood.magical:
        return EffectMoodCategory.magical;
      case PatternMood.cozy:
        return EffectMoodCategory.cozy;
      case PatternMood.energetic:
        return EffectMoodCategory.festive; // Closest match
      case PatternMood.dramatic:
        return EffectMoodCategory.mysterious; // Closest match
    }
  }
}
