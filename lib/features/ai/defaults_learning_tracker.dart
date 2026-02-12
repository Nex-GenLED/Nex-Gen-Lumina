import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

// ---------------------------------------------------------------------------
// Learning tracker
// ---------------------------------------------------------------------------

/// Tracks user adjustments to Lumina's defaults and learns preferences.
///
/// Uses the existing [UserService] persistence infrastructure:
/// - `saveDetectedHabit()` for storing learned patterns
/// - `getDetectedHabits()` for retrieving them
/// - `logPatternUsage()` for recording applied/adjusted patterns
///
/// The tracker records when a user changes a parameter after Lumina's
/// suggestion, then aggregates these signals into bias values that
/// the [LuminaDefaultsEngine] reads on subsequent requests.
class DefaultsLearningTracker {
  final UserService _userService;
  final String _userId;

  /// In-memory cache of loaded habits (avoids repeated Firestore reads).
  Map<String, dynamic>? _cachedHabits;

  DefaultsLearningTracker({
    required UserService userService,
    required String userId,
  })  : _userService = userService,
        _userId = userId;

  // -------------------------------------------------------------------------
  // Recording signals
  // -------------------------------------------------------------------------

  /// Record that the user adjusted a parameter after Lumina's suggestion.
  ///
  /// [parameterName]: 'brightness', 'effect', 'colors', 'speed', 'zone'
  /// [suggestedValue]: what Lumina proposed (e.g., 0.65 for brightness)
  /// [adjustedValue]: what the user changed it to (e.g., 0.85)
  /// [skyDarkness]: context at the time of adjustment (0.0-1.0)
  /// [hourOfDay]: 0-23
  Future<void> recordAdjustment({
    required String parameterName,
    required dynamic suggestedValue,
    required dynamic adjustedValue,
    required double skyDarkness,
    required int hourOfDay,
  }) async {
    try {
      await _userService.logPatternUsage(
        userId: _userId,
        source: 'lumina_adjusted',
        patternName: 'adjustment:$parameterName',
        brightness: parameterName == 'brightness'
            ? ((adjustedValue as double) * 255).round()
            : null,
        effectId: parameterName == 'effect' ? adjustedValue as int? : null,
        speed: parameterName == 'speed'
            ? ((adjustedValue as double) * 255).round()
            : null,
        wled: {
          'parameter': parameterName,
          'suggested': suggestedValue,
          'adjusted': adjustedValue,
          'sky_darkness': skyDarkness,
          'hour': hourOfDay,
        },
      );
    } catch (e) {
      debugPrint('DefaultsLearningTracker.recordAdjustment failed: $e');
    }
  }

  /// Record that the user accepted Lumina's defaults without changes.
  Future<void> recordAccepted({
    required double brightness,
    required int effectId,
    required double skyDarkness,
    required int hourOfDay,
  }) async {
    try {
      await _userService.logPatternUsage(
        userId: _userId,
        source: 'lumina_accepted',
        brightness: (brightness * 255).round(),
        effectId: effectId,
        wled: {
          'sky_darkness': skyDarkness,
          'hour': hourOfDay,
        },
      );
    } catch (e) {
      debugPrint('DefaultsLearningTracker.recordAccepted failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Retrieving learned biases
  // -------------------------------------------------------------------------

  /// Get a brightness bias multiplier for the current context.
  ///
  /// Returns a value like `1.15` (user typically wants 15% brighter) or
  /// `0.90` (user prefers 10% dimmer). Returns `1.0` if no data.
  ///
  /// Looks for a `brightness_bias` habit whose context brackets the
  /// current [skyDarkness] value.
  Future<double> getBrightnessBias({
    required double skyDarkness,
    required int hourOfDay,
  }) async {
    try {
      final habits = await _loadHabits();
      for (final h in habits) {
        if (h['type'] != 'brightness_bias') continue;
        final ctx = h['context'] as Map<String, dynamic>?;
        if (ctx == null) continue;
        final min = (ctx['sky_darkness_min'] as num?)?.toDouble() ?? 0.0;
        final max = (ctx['sky_darkness_max'] as num?)?.toDouble() ?? 1.0;
        if (skyDarkness >= min && skyDarkness <= max) {
          return (h['bias'] as num?)?.toDouble() ?? 1.0;
        }
      }
    } catch (e) {
      debugPrint('DefaultsLearningTracker.getBrightnessBias failed: $e');
    }
    return 1.0;
  }

  /// Get learned effect preferences: which effect categories the user favors.
  ///
  /// Returns a map of effect ID → preference weight (0.0-1.0).
  /// Empty map if no learning data exists.
  Future<Map<int, double>> getEffectPreferences() async {
    try {
      final habits = await _loadHabits();
      for (final h in habits) {
        if (h['type'] != 'effect_preference') continue;
        final ids = h['preferred_effects'] as List<dynamic>?;
        if (ids == null || ids.isEmpty) continue;
        final weight = 1.0 / ids.length;
        return {for (final id in ids) (id as num).toInt(): weight};
      }
    } catch (e) {
      debugPrint('DefaultsLearningTracker.getEffectPreferences failed: $e');
    }
    return {};
  }

  // -------------------------------------------------------------------------
  // Habit analysis
  // -------------------------------------------------------------------------

  /// Analyze recent usage and detect/update habits.
  ///
  /// Call periodically (e.g., once per app session or daily) to mine
  /// recent `lumina_adjusted` usage logs and derive new bias values.
  Future<void> analyzeAndSaveHabits() async {
    try {
      final recent = await _userService.getRecentUsage(_userId, days: 30);

      // Filter to Lumina adjustments only
      final adjustments = recent
          .where((u) => u['source'] == 'lumina_adjusted')
          .toList();

      if (adjustments.length < 5) return; // Not enough data

      // Brightness bias detection
      _analyzeBrightnessBias(adjustments);

      // Effect preference detection
      _analyzeEffectPreferences(adjustments);

      // Invalidate cache so next read picks up new habits
      _cachedHabits = null;
    } catch (e) {
      debugPrint('DefaultsLearningTracker.analyzeAndSaveHabits failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Internal analysis
  // -------------------------------------------------------------------------

  Future<void> _analyzeBrightnessBias(
      List<Map<String, dynamic>> adjustments) async {
    // Collect brightness adjustments grouped by darkness bracket
    final nightAdj = <double>[]; // sky_darkness >= 0.6
    final dayAdj = <double>[];   // sky_darkness < 0.6

    for (final a in adjustments) {
      final wled = a['wled'] as Map<String, dynamic>?;
      if (wled == null || wled['parameter'] != 'brightness') continue;
      final suggested = (wled['suggested'] as num?)?.toDouble();
      final adjusted = (wled['adjusted'] as num?)?.toDouble();
      final darkness = (wled['sky_darkness'] as num?)?.toDouble() ?? 0.5;
      if (suggested == null || adjusted == null || suggested == 0) continue;

      final ratio = adjusted / suggested;
      if (darkness >= 0.6) {
        nightAdj.add(ratio);
      } else {
        dayAdj.add(ratio);
      }
    }

    // Save night brightness bias if enough samples
    if (nightAdj.length >= 3) {
      final avgBias = nightAdj.reduce((a, b) => a + b) / nightAdj.length;
      if ((avgBias - 1.0).abs() > 0.05) {
        await _userService.saveDetectedHabit(_userId, {
          'type': 'brightness_bias',
          'description': avgBias > 1.0
              ? 'User prefers ${((avgBias - 1) * 100).round()}% brighter after dark'
              : 'User prefers ${((1 - avgBias) * 100).round()}% dimmer after dark',
          'context': {'sky_darkness_min': 0.6, 'sky_darkness_max': 1.0},
          'bias': double.parse(avgBias.toStringAsFixed(2)),
          'sample_count': nightAdj.length,
        });
      }
    }

    // Save day brightness bias if enough samples
    if (dayAdj.length >= 3) {
      final avgBias = dayAdj.reduce((a, b) => a + b) / dayAdj.length;
      if ((avgBias - 1.0).abs() > 0.05) {
        await _userService.saveDetectedHabit(_userId, {
          'type': 'brightness_bias',
          'description': avgBias > 1.0
              ? 'User prefers ${((avgBias - 1) * 100).round()}% brighter during day'
              : 'User prefers ${((1 - avgBias) * 100).round()}% dimmer during day',
          'context': {'sky_darkness_min': 0.0, 'sky_darkness_max': 0.6},
          'bias': double.parse(avgBias.toStringAsFixed(2)),
          'sample_count': dayAdj.length,
        });
      }
    }
  }

  Future<void> _analyzeEffectPreferences(
      List<Map<String, dynamic>> adjustments) async {
    // Count how often each effect ID was chosen as an adjustment
    final effectCounts = <int, int>{};
    for (final a in adjustments) {
      final wled = a['wled'] as Map<String, dynamic>?;
      if (wled == null || wled['parameter'] != 'effect') continue;
      final effectId = (wled['adjusted'] as num?)?.toInt();
      if (effectId == null) continue;
      effectCounts[effectId] = (effectCounts[effectId] ?? 0) + 1;
    }

    if (effectCounts.length >= 2) {
      // Top 5 most preferred effects
      final sorted = effectCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topIds = sorted.take(5).map((e) => e.key).toList();

      await _userService.saveDetectedHabit(_userId, {
        'type': 'effect_preference',
        'description': 'User frequently adjusts to these effects',
        'preferred_effects': topIds,
        'sample_count': effectCounts.values.reduce((a, b) => a + b),
      });
    }
  }

  // -------------------------------------------------------------------------
  // Cache
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _loadHabits() async {
    if (_cachedHabits != null) {
      return (_cachedHabits!['list'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
    }
    final habits = await _userService.getDetectedHabits(_userId, limit: 20);
    _cachedHabits = {'list': habits};
    return habits;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides a [DefaultsLearningTracker] for the current user.
///
/// Returns `null` if user is not signed in.
final defaultsLearningTrackerProvider =
    Provider<DefaultsLearningTracker?>((ref) {
  final profile = ref.watch(currentUserProfileProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  if (profile == null) return null;
  final svc = ref.watch(userServiceProvider);
  return DefaultsLearningTracker(userService: svc, userId: profile.id);
});
