import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/suggestion_history.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';

// ---------------------------------------------------------------------------
// Enum
// ---------------------------------------------------------------------------

/// How much variety a user prefers across multi-day or repeated lighting events.
enum VarietyPreferenceLevel {
  /// Same effect, same parameters every time. User values reliability.
  consistent,

  /// Alternates between 2 effects max. Small speed/intensity changes.
  subtle,

  /// Different effects each day using the same color palette.
  varied,

  /// Different effects AND occasional accent/secondary color variation.
  eclectic,
}

// ---------------------------------------------------------------------------
// Profile model
// ---------------------------------------------------------------------------

/// Models a user's preference for variety vs consistency in lighting patterns.
///
/// Inferred from:
///  - Effect diversity in [SuggestionHistoryService] (how many unique effects used)
///  - Frequency of open-ended queries ("surprise me", "something different")
///  - Frequency of consistency requests ("same as last time", "keep it")
///  - Saved favorites diversity (how varied their saved patterns are)
///
/// Used by [LuminaSmartScheduler] to determine how to generate
/// multi-day pattern rotations.
class UserVarietyProfile {
  /// 0.0 = strongly prefers consistency. 1.0 = strongly prefers variety.
  final double varietyScore;

  final VarietyPreferenceLevel level;

  /// Effect IDs the user has recently engaged with.
  final Set<int> recentEffectIds;

  /// Whether the user has explicitly requested variety at least once.
  final bool hasRequestedVariety;

  /// Whether the user has explicitly requested consistency.
  final bool hasRequestedConsistency;

  const UserVarietyProfile({
    required this.varietyScore,
    required this.level,
    this.recentEffectIds = const {},
    this.hasRequestedVariety = false,
    this.hasRequestedConsistency = false,
  });

  /// Neutral default for new users — lean toward variety since the app
  /// is meant to showcase capabilities.
  factory UserVarietyProfile.defaultProfile() => const UserVarietyProfile(
        varietyScore: 0.62,
        level: VarietyPreferenceLevel.varied,
      );

  // -----------------------------------------------------------------------
  // Effect rotation builder
  // -----------------------------------------------------------------------

  /// Given a pool of [themeEffects] suggested for a concept (team, holiday, etc.),
  /// selects an ordered list of [count] effect IDs appropriate to this user's
  /// preference level.
  ///
  /// [count] matches the number of schedule occurrences (e.g., 7 for a week).
  List<int> buildEffectRotation({
    required List<int> themeEffects,
    required int count,
  }) {
    if (themeEffects.isEmpty) return List.filled(count, 0);

    switch (level) {
      case VarietyPreferenceLevel.consistent:
        // Same effect every single day — no deviation.
        return List.filled(count, themeEffects.first);

      case VarietyPreferenceLevel.subtle:
        // Rotate between 2 effects only.
        final pool = themeEffects.take(2).toList();
        return List.generate(count, (i) => pool[i % pool.length]);

      case VarietyPreferenceLevel.varied:
        // Full rotation through all suggested effects.
        return List.generate(
            count, (i) => themeEffects[i % themeEffects.length]);

      case VarietyPreferenceLevel.eclectic:
        // Prioritize effects the user has engaged with, then fill from theme pool.
        final boosted = [
          ...recentEffectIds.where(themeEffects.contains),
          ...themeEffects,
        ].toSet().toList();
        return List.generate(count, (i) => boosted[i % boosted.length]);
    }
  }

  // -----------------------------------------------------------------------
  // Dynamic parameter builder
  // -----------------------------------------------------------------------

  /// Generates per-occurrence speed/intensity values that match the user's
  /// variety preference. Even "consistent" users get minimal natural variation
  /// so the lights don't look broken — just stable.
  ///
  /// Returns a list of [count] maps with keys 'speed' and 'intensity' (0–255).
  List<Map<String, int>> buildDynamicVariation({required int count}) {
    switch (level) {
      case VarietyPreferenceLevel.consistent:
        // Identical every day. User chose this — respect it.
        return List.filled(count, {'speed': 128, 'intensity': 180});

      case VarietyPreferenceLevel.subtle:
        // Gentle oscillation: slow → medium → fast → medium → repeat
        const speeds = [80, 128, 170, 128];
        return List.generate(count, (i) => {
              'speed': speeds[i % speeds.length],
              'intensity': 180,
            });

      case VarietyPreferenceLevel.varied:
        // Notable variation each day — feels intentionally different.
        const presets = [
          {'speed': 70, 'intensity': 150},  // Slow & elegant
          {'speed': 150, 'intensity': 200}, // Medium-energetic
          {'speed': 100, 'intensity': 170}, // Moderate
          {'speed': 190, 'intensity': 215}, // Fast & bright
          {'speed': 85, 'intensity': 160},  // Relaxed
          {'speed': 165, 'intensity': 205}, // Energetic
          {'speed': 55, 'intensity': 140},  // Dreamy
        ];
        return List.generate(count, (i) => presets[i % presets.length]);

      case VarietyPreferenceLevel.eclectic:
        // Max variation — user loves surprises.
        const presets = [
          {'speed': 50, 'intensity': 130},
          {'speed': 200, 'intensity': 230},
          {'speed': 90, 'intensity': 160},
          {'speed': 175, 'intensity': 210},
          {'speed': 65, 'intensity': 145},
          {'speed': 215, 'intensity': 240},
          {'speed': 110, 'intensity': 175},
        ];
        return List.generate(count, (i) => presets[i % presets.length]);
    }
  }

  // -----------------------------------------------------------------------
  // Utility
  // -----------------------------------------------------------------------

  /// Human-readable description for UI and AI context injection.
  String get userFacingDescription {
    switch (level) {
      case VarietyPreferenceLevel.consistent:
        return 'prefers reliable, consistent lighting designs';
      case VarietyPreferenceLevel.subtle:
        return 'appreciates subtle variety day-to-day';
      case VarietyPreferenceLevel.varied:
        return 'enjoys a fresh look each time';
      case VarietyPreferenceLevel.eclectic:
        return 'loves creative variety and unexpected surprises';
    }
  }

  /// Short AI prompt hint injected into LuminaBrain context.
  String buildAIContextHint() {
    return 'USER VARIETY PREFERENCE:\n'
        '- Score: ${varietyScore.toStringAsFixed(2)} / 1.0\n'
        '- Level: ${level.name.toUpperCase()} — this user $userFacingDescription\n'
        '- When generating multi-day or repeated schedules, '
        '${_rotationInstruction()}';
  }

  String _rotationInstruction() {
    switch (level) {
      case VarietyPreferenceLevel.consistent:
        return 'use the SAME effect and parameters every occurrence. '
            'Do not vary effects, speed, or palette across days.';
      case VarietyPreferenceLevel.subtle:
        return 'alternate between at most 2 effects. '
            'Vary speed slightly but keep the palette identical each day.';
      case VarietyPreferenceLevel.varied:
        return 'rotate through different effects each occurrence using the '
            'same color palette. Each day should feel distinctly different.';
      case VarietyPreferenceLevel.eclectic:
        return 'use a DIFFERENT effect every occurrence and subtly vary '
            'speed and intensity for maximum creative variety. '
            'This user actively wants to be surprised.';
    }
  }

  @override
  String toString() =>
      'UserVarietyProfile(score=$varietyScore, level=${level.name})';
}

// ---------------------------------------------------------------------------
// Analyzer — infers profile from available data
// ---------------------------------------------------------------------------

/// Infers a [UserVarietyProfile] from available user data without requiring
/// explicit user input.
class UserVarietyProfileAnalyzer {
  UserVarietyProfileAnalyzer._();

  /// Analyze available signals and return an inferred [UserVarietyProfile].
  ///
  /// Call this during [LuminaBrain.chat] before compound command handling.
  static UserVarietyProfile analyze({
    required SuggestionHistoryService historyService,
    List<dynamic>? savedFavorites,  // List<FavoritePattern> — typed loosely to avoid coupling
    int openEndedQueryCount = 0,    // From analytics service
    int consistencyQueryCount = 0,  // Queries like "same as before", "keep it"
  }) {
    double score = 0.50;
    final signals = <String>[];

    // -------------------------------------------------------------------
    // Signal 1: Effect diversity from recent suggestion history
    // -------------------------------------------------------------------
    final recentEffects = historyService.recentEffectIds;
    final diversityCount = recentEffects.length;

    if (diversityCount >= 5) {
      score += 0.20;
      signals.add('high_diversity:$diversityCount');
    } else if (diversityCount >= 3) {
      score += 0.10;
      signals.add('moderate_diversity:$diversityCount');
    } else if (diversityCount <= 1 && historyService.historySize > 3) {
      // User has a long history but keeps using the same effect
      score -= 0.18;
      signals.add('low_diversity:$diversityCount');
    }

    // -------------------------------------------------------------------
    // Signal 2: Open-ended query frequency
    // Open-ended = "surprise me", "something different", "random"
    // -------------------------------------------------------------------
    if (openEndedQueryCount >= 5) {
      score += 0.25;
      signals.add('high_variety_requests:$openEndedQueryCount');
    } else if (openEndedQueryCount >= 2) {
      score += 0.13;
      signals.add('some_variety_requests:$openEndedQueryCount');
    }

    // -------------------------------------------------------------------
    // Signal 3: Consistency request frequency
    // Consistency = "same as last night", "keep it", "don't change"
    // -------------------------------------------------------------------
    if (consistencyQueryCount >= 3) {
      score -= 0.25;
      signals.add('strong_consistency_preference:$consistencyQueryCount');
    } else if (consistencyQueryCount >= 1) {
      score -= 0.12;
      signals.add('some_consistency:$consistencyQueryCount');
    }

    // -------------------------------------------------------------------
    // Signal 4: Saved favorites diversity
    // Many different effects saved → user appreciates variety
    // All the same effect saved → user prefers consistency
    // -------------------------------------------------------------------
    if (savedFavorites != null && savedFavorites.isNotEmpty) {
      // Attempt to read effectId from each favorite (defensive — duck typed)
      final effectIds = <int>{};
      for (final fav in savedFavorites) {
        try {
          final id = (fav as dynamic).effectId as int?;
          if (id != null) effectIds.add(id);
        } catch (_) {}
      }

      if (effectIds.length >= 4) {
        score += 0.15;
        signals.add('diverse_saved_effects:${effectIds.length}');
      } else if (effectIds.length <= 1 && savedFavorites.length > 2) {
        score -= 0.10;
        signals.add('homogeneous_saved_effects:${effectIds.length}');
      }
    }

    score = score.clamp(0.0, 1.0);

    final level = score >= 0.75
        ? VarietyPreferenceLevel.eclectic
        : score >= 0.52
            ? VarietyPreferenceLevel.varied
            : score >= 0.32
                ? VarietyPreferenceLevel.subtle
                : VarietyPreferenceLevel.consistent;

    debugPrint('👤 UserVarietyProfile: score=${score.toStringAsFixed(2)}, '
        'level=${level.name}, signals=${signals.join(", ")}');

    return UserVarietyProfile(
      varietyScore: score,
      level: level,
      recentEffectIds: recentEffects,
      hasRequestedVariety: openEndedQueryCount > 0,
      hasRequestedConsistency: consistencyQueryCount > 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Provides the current user's inferred variety preference.
///
/// Reads from [SuggestionHistoryService] and saved favorites.
/// Updated whenever favorites change.
final userVarietyProfileProvider = Provider<UserVarietyProfile>((ref) {
  final history = SuggestionHistoryService.instance;
  final favoritesAsync = ref.watch(favoritesPatternsProvider);
  final favorites = favoritesAsync.whenOrNull(data: (f) => f);

  // TODO: wire analytics service for openEndedQueryCount / consistencyQueryCount
  // when PatternAnalyticsService surfaces those aggregated counts.
  return UserVarietyProfileAnalyzer.analyze(
    historyService: history,
    savedFavorites: favorites,
  );
});