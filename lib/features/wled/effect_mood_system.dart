import 'package:flutter/material.dart';

/// Effect mood categories for user-friendly filtering.
/// Each mood groups effects by the "vibe" they create.
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
}

/// Maps effect IDs to their mood categories.
/// Includes both WLED native effects and Lumina custom effects.
class EffectMoodSystem {
  EffectMoodSystem._();

  /// Effect ID to mood mapping
  static const Map<int, EffectMood> _effectMoods = {
    // Calm & Elegant - gentle, relaxing
    0: EffectMood.calmElegant,    // Solid
    2: EffectMood.calmElegant,    // Breathe
    12: EffectMood.calmElegant,   // Fade
    1007: EffectMood.calmElegant, // Ocean Swell (custom)

    // Subtle Magic - twinkling, magical
    17: EffectMood.subtleMagic,   // Twinkle
    20: EffectMood.subtleMagic,   // Sparkle
    49: EffectMood.subtleMagic,   // Fairy
    87: EffectMood.subtleMagic,   // Glitter

    // Festive Fun - high energy, party
    13: EffectMood.festiveFun,    // Theater
    15: EffectMood.festiveFun,    // Running
    28: EffectMood.festiveFun,    // Chase
    91: EffectMood.festiveFun,    // Bouncing Balls

    // Dramatic - impressive, attention-grabbing
    59: EffectMood.dramatic,      // Multi Comet
    76: EffectMood.dramatic,      // Meteor
    1001: EffectMood.dramatic,    // Rising Tide (custom)
    1002: EffectMood.dramatic,    // Falling Tide (custom)
    1003: EffectMood.dramatic,    // Pulse Burst (custom)
    1005: EffectMood.dramatic,    // Grand Reveal (custom)

    // Smooth Motion - continuous flowing
    3: EffectMood.smoothMotion,   // Wipe
    6: EffectMood.smoothMotion,   // Sweep
    10: EffectMood.smoothMotion,  // Scan
    40: EffectMood.smoothMotion,  // Scanner
    96: EffectMood.smoothMotion,  // Drip
  };

  /// Get the mood for an effect ID
  static EffectMood? getMood(int effectId) => _effectMoods[effectId];

  /// Get all effect IDs for a specific mood
  static List<int> getEffectIdsForMood(EffectMood mood) {
    return _effectMoods.entries
        .where((e) => e.value == mood)
        .map((e) => e.key)
        .toList();
  }

  /// Get all effect IDs that match any of the given moods
  static List<int> getEffectIdsForMoods(Set<EffectMood> moods) {
    if (moods.isEmpty) return _effectMoods.keys.toList();
    return _effectMoods.entries
        .where((e) => moods.contains(e.value))
        .map((e) => e.key)
        .toList();
  }

  /// Check if an effect ID matches a mood
  static bool effectMatchesMood(int effectId, EffectMood mood) {
    return _effectMoods[effectId] == mood;
  }

  /// Filter a list of effect IDs to only those matching the given mood
  static List<int> filterByMood(List<int> effectIds, EffectMood? mood) {
    if (mood == null) return effectIds;
    return effectIds.where((id) => _effectMoods[id] == mood).toList();
  }

  /// Get mood counts for a list of effect IDs (for UI display)
  static Map<EffectMood, int> getMoodCounts(List<int> effectIds) {
    final counts = <EffectMood, int>{};
    for (final mood in EffectMood.values) {
      counts[mood] = effectIds.where((id) => _effectMoods[id] == mood).length;
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
}
