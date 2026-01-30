import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';

/// Effect mood categories for user-friendly filtering.
/// Each mood groups effects by the "vibe" they create.
///
/// NOTE: This enum is kept for backward compatibility with existing UI code.
/// The new EffectMoodCategory in effect_database.dart provides more granular control.
enum EffectMood {
  /// Gentle, relaxing effects - breathe, fade, solid
  calmElegant,

  /// Twinkling, magical effects - sparkle, fairy, twinkle
  subtleMagic,

  /// High-energy, party effects - chase, running, bouncing
  festiveFun,

  /// Impressive, attention-grabbing effects - reveal, tide, meteor
  dramatic,

  /// Continuous flowing motion - wipe, sweep, scan, wave
  smoothMotion,
}

/// Extension for mood display properties
extension EffectMoodDisplay on EffectMood {
  String get label {
    switch (this) {
      case EffectMood.calmElegant:
        return 'Calm';
      case EffectMood.subtleMagic:
        return 'Magical';
      case EffectMood.festiveFun:
        return 'Party';
      case EffectMood.dramatic:
        return 'Dramatic';
      case EffectMood.smoothMotion:
        return 'Flowing';
    }
  }

  String get emoji {
    switch (this) {
      case EffectMood.calmElegant:
        return '😌';
      case EffectMood.subtleMagic:
        return '✨';
      case EffectMood.festiveFun:
        return '🎉';
      case EffectMood.dramatic:
        return '🎭';
      case EffectMood.smoothMotion:
        return '🌊';
    }
  }

  String get description {
    switch (this) {
      case EffectMood.calmElegant:
        return 'Gentle, relaxing ambiance';
      case EffectMood.subtleMagic:
        return 'Twinkling, magical sparkle';
      case EffectMood.festiveFun:
        return 'High-energy party vibes';
      case EffectMood.dramatic:
        return 'Bold, attention-grabbing';
      case EffectMood.smoothMotion:
        return 'Continuous flowing motion';
    }
  }

  Color get color {
    switch (this) {
      case EffectMood.calmElegant:
        return const Color(0xFF7B68EE); // Medium slate blue
      case EffectMood.subtleMagic:
        return const Color(0xFFFFD700); // Gold
      case EffectMood.festiveFun:
        return const Color(0xFFFF6B6B); // Coral red
      case EffectMood.dramatic:
        return const Color(0xFFE040FB); // Purple accent
      case EffectMood.smoothMotion:
        return const Color(0xFF00BCD4); // Cyan
    }
  }

  IconData get icon {
    switch (this) {
      case EffectMood.calmElegant:
        return Icons.spa_outlined;
      case EffectMood.subtleMagic:
        return Icons.auto_awesome;
      case EffectMood.festiveFun:
        return Icons.celebration;
      case EffectMood.dramatic:
        return Icons.theater_comedy;
      case EffectMood.smoothMotion:
        return Icons.waves;
    }
  }

  /// Convert to the new EffectMoodCategory set for database lookups
  Set<EffectMoodCategory> toEffectMoodCategories() {
    switch (this) {
      case EffectMood.calmElegant:
        return {EffectMoodCategory.calm, EffectMoodCategory.elegant, EffectMoodCategory.romantic};
      case EffectMood.subtleMagic:
        return {EffectMoodCategory.magical, EffectMoodCategory.romantic};
      case EffectMood.festiveFun:
        return {EffectMoodCategory.festive, EffectMoodCategory.playful};
      case EffectMood.dramatic:
        return {EffectMoodCategory.mysterious};
      case EffectMood.smoothMotion:
        return {EffectMoodCategory.natural, EffectMoodCategory.modern};
    }
  }
}

/// Maps effect IDs to their mood categories.
/// Now powered by the comprehensive EffectDatabase.
///
/// This class provides backward compatibility while leveraging the new
/// EffectDatabase for more accurate mood matching.
class EffectMoodSystem {
  EffectMoodSystem._();

  /// Convert EffectMoodCategory to legacy EffectMood
  static EffectMood? _categoryToLegacyMood(EffectMoodCategory category) {
    switch (category) {
      case EffectMoodCategory.calm:
      case EffectMoodCategory.elegant:
      case EffectMoodCategory.romantic:
      case EffectMoodCategory.cozy:
        return EffectMood.calmElegant;
      case EffectMoodCategory.magical:
        return EffectMood.subtleMagic;
      case EffectMoodCategory.festive:
      case EffectMoodCategory.playful:
        return EffectMood.festiveFun;
      case EffectMoodCategory.mysterious:
        return EffectMood.dramatic;
      case EffectMoodCategory.natural:
      case EffectMoodCategory.modern:
        return EffectMood.smoothMotion;
    }
  }

  /// Get the mood for an effect ID (legacy API)
  /// Returns the primary mood based on the new EffectDatabase
  static EffectMood? getMood(int effectId) {
    final metadata = EffectDatabase.getEffect(effectId);
    if (metadata == null || metadata.moods.isEmpty) return null;

    // Return the first matching mood, preferring certain categories
    for (final category in metadata.moods) {
      final legacyMood = _categoryToLegacyMood(category);
      if (legacyMood != null) return legacyMood;
    }
    return null;
  }

  /// Get all effect IDs for a specific mood
  /// Now powered by the comprehensive EffectDatabase
  static List<int> getEffectIdsForMood(EffectMood mood) {
    final categories = mood.toEffectMoodCategories();
    final effects = EffectDatabase.getEffectsForAnyMood(categories);
    return effects.map((e) => e.id).toList();
  }

  /// Get all effect IDs that match any of the given moods
  static List<int> getEffectIdsForMoods(Set<EffectMood> moods) {
    if (moods.isEmpty) return EffectDatabase.effects.keys.toList();

    final categories = <EffectMoodCategory>{};
    for (final mood in moods) {
      categories.addAll(mood.toEffectMoodCategories());
    }

    final effects = EffectDatabase.getEffectsForAnyMood(categories);
    return effects.map((e) => e.id).toList();
  }

  /// Check if an effect ID matches a mood
  static bool effectMatchesMood(int effectId, EffectMood mood) {
    final categories = mood.toEffectMoodCategories();
    final metadata = EffectDatabase.getEffect(effectId);
    if (metadata == null) return false;
    return metadata.moods.intersection(categories).isNotEmpty;
  }

  /// Filter a list of effect IDs to only those matching the given mood
  static List<int> filterByMood(List<int> effectIds, EffectMood? mood) {
    if (mood == null) return effectIds;
    return effectIds.where((id) => effectMatchesMood(id, mood)).toList();
  }

  /// Get mood counts for a list of effect IDs (for UI display)
  static Map<EffectMood, int> getMoodCounts(List<int> effectIds) {
    final counts = <EffectMood, int>{};
    for (final mood in EffectMood.values) {
      counts[mood] = effectIds.where((id) => effectMatchesMood(id, mood)).length;
    }
    return counts;
  }

  /// All moods in display order
  static const List<EffectMood> displayOrder = [
    EffectMood.calmElegant,
    EffectMood.subtleMagic,
    EffectMood.festiveFun,
    EffectMood.dramatic,
    EffectMood.smoothMotion,
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: Enhanced API using EffectDatabase
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if an effect respects user colors
  /// CRITICAL: Use this to avoid recommending rainbow/palette effects for themed lighting
  static bool effectRespectsColors(int effectId) {
    return EffectDatabase.effectRespectsColors(effectId);
  }

  /// Get all effects that respect user colors
  static List<int> getColorRespectingEffectIds() {
    return EffectDatabase.getColorRespectingEffects().map((e) => e.id).toList();
  }

  /// Get effects that override colors (rainbow, palette-based)
  /// Use ONLY when user explicitly requests rainbow/multicolor
  static List<int> getColorOverridingEffectIds() {
    return EffectDatabase.getColorOverridingEffects().map((e) => e.id).toList();
  }

  /// Get effect metadata
  static EffectMetadata? getEffectMetadata(int effectId) {
    return EffectDatabase.getEffect(effectId);
  }

  /// Find effects matching multiple criteria
  /// Always respects colors unless explicitly disabled
  static List<int> findMatchingEffectIds({
    EffectMood? mood,
    MotionType? motionType,
    EnergyLevel? minEnergy,
    EnergyLevel? maxEnergy,
    String? occasion,
    bool requireColorRespect = true,
  }) {
    final categories = mood?.toEffectMoodCategories();

    final effects = EffectDatabase.findMatchingEffects(
      moods: categories,
      motionType: motionType,
      minEnergy: minEnergy,
      maxEnergy: maxEnergy,
      occasion: occasion,
      requireColorRespect: requireColorRespect,
    );

    return effects.map((e) => e.id).toList();
  }

  /// Get recommended effects for a scenario
  /// ALWAYS respects colors by default (critical for themed lighting)
  static List<int> getRecommendedEffectIds({
    required String scenario,
    bool allowColorOverride = false,
  }) {
    return EffectDatabase.getRecommendedEffectIds(
      scenario: scenario,
      colorRespectRequired: !allowColorOverride,
    );
  }

  /// Check if an effect should be avoided for a given occasion
  static bool shouldAvoidEffectForOccasion(int effectId, String occasion) {
    return EffectDatabase.shouldAvoidEffect(effectId, occasion);
  }

  /// Get the best effect for a mood + color respect requirement
  static int? getBestEffectForMood(EffectMood mood, {bool mustRespectColors = true}) {
    final effectIds = findMatchingEffectIds(
      mood: mood,
      requireColorRespect: mustRespectColors,
    );

    if (effectIds.isEmpty) return null;

    // Return the first one (they're generally in order of preference)
    return effectIds.first;
  }

  /// Get effect name
  static String getEffectName(int effectId) {
    return EffectDatabase.getEffect(effectId)?.name ?? 'Unknown';
  }

  /// Get effect description
  static String getEffectDescription(int effectId) {
    return EffectDatabase.getEffect(effectId)?.description ?? '';
  }

  /// Get recommended speed range for an effect
  static (int min, int max, int default_) getRecommendedSpeedRange(int effectId) {
    final metadata = EffectDatabase.getEffect(effectId);
    if (metadata == null) return (0, 255, 128);
    return (metadata.minSpeed, metadata.maxSpeed, metadata.defaultSpeed);
  }

  /// Get recommended intensity range for an effect
  static (int min, int max, int default_) getRecommendedIntensityRange(int effectId) {
    final metadata = EffectDatabase.getEffect(effectId);
    if (metadata == null) return (0, 255, 128);
    return (metadata.minIntensity, metadata.maxIntensity, metadata.defaultIntensity);
  }
}
