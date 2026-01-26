import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/habit_learner.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/analytics/analytics_providers.dart';

/// Provider for the HabitLearner service
final habitLearnerProvider = Provider.family<HabitLearner?, String>((ref, userId) {
  if (userId.isEmpty) return null;

  final userService = ref.watch(userServiceProvider);
  return HabitLearner(
    userService: userService,
    userId: userId,
  );
});

/// Provider for current user's habit learner
final currentUserHabitLearnerProvider = Provider<HabitLearner?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;

  return ref.watch(habitLearnerProvider(user.uid));
});

// ==================== Favorites ====================

/// System default favorites that are always available
final _systemDefaultFavorites = [
  FavoritePattern(
    id: 'system_warm_white',
    patternName: 'Warm White',
    addedAt: DateTime(2024, 1, 1),
    usageCount: 0,
    patternData: {
      'on': true,
      'bri': 220,
      'seg': [{'id': 0, 'fx': 0, 'col': [[255, 180, 100, 255]]}]
    },
    autoAdded: false,
  ),
  FavoritePattern(
    id: 'system_bright_white',
    patternName: 'Bright White',
    addedAt: DateTime(2024, 1, 1),
    usageCount: 0,
    patternData: {
      'on': true,
      'bri': 255,
      'seg': [{'id': 0, 'fx': 0, 'col': [[255, 255, 255, 255]]}]
    },
    autoAdded: false,
  ),
];

/// Stream of user's favorite patterns (includes system defaults)
final favoritePatternsProvider = StreamProvider.autoDispose<List<FavoritePattern>>((ref) async* {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    // Return only system defaults when not logged in
    yield _systemDefaultFavorites;
    return;
  }

  final userService = ref.watch(userServiceProvider);
  await for (final favoritesData in userService.streamFavorites(user.uid)) {
    final userFavorites = favoritesData
        .map((data) => FavoritePattern.fromJson(data))
        .toList();

    // Sort user favorites by usage and recency
    userFavorites.sort((a, b) {
      // Manual favorites first
      if (a.autoAdded != b.autoAdded) {
        return a.autoAdded ? 1 : -1;
      }
      // Then by last used (most recent first)
      if (a.lastUsed != null && b.lastUsed != null) {
        return b.lastUsed!.compareTo(a.lastUsed!);
      }
      // Then by usage count
      return b.usageCount.compareTo(a.usageCount);
    });

    // Combine system defaults with user favorites
    // System defaults appear first, then user patterns
    final combined = <FavoritePattern>[
      ..._systemDefaultFavorites,
      ...userFavorites,
    ];

    yield combined;
  }
});

/// Notifier for managing favorites
class FavoritesNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Nothing to build
  }

  /// Add a pattern to favorites
  Future<void> addFavorite({
    required String patternName,
    required Map<String, dynamic> patternData,
    bool autoAdded = false,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    final userService = ref.read(userServiceProvider);
    await userService.addFavorite(user.uid, {
      'pattern_name': patternName,
      'pattern_data': patternData,
      'auto_added': autoAdded,
    });
  }

  /// Remove a favorite
  Future<void> removeFavorite(String favoriteId) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    final userService = ref.read(userServiceProvider);
    await userService.removeFavorite(user.uid, favoriteId);
  }

  /// Update favorite usage (called when user applies a favorite)
  Future<void> recordFavoriteUsage(String favoriteId) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    final userService = ref.read(userServiceProvider);
    await userService.updateFavoriteUsage(user.uid, favoriteId);
  }

  /// Trigger auto-favorites update
  Future<void> refreshAutoFavorites({int topN = 5}) async {
    final habitLearner = ref.read(currentUserHabitLearnerProvider);
    if (habitLearner == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await habitLearner.updateAutoFavorites(topN: topN);
    });
  }
}

final favoritesNotifierProvider = AutoDisposeAsyncNotifierProvider<FavoritesNotifier, void>(
  () => FavoritesNotifier(),
);

// ==================== Smart Suggestions ====================

/// Stream of active smart suggestions
final activeSuggestionsProvider = StreamProvider.autoDispose<List<SmartSuggestion>>((ref) async* {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    yield [];
    return;
  }

  final userService = ref.watch(userServiceProvider);
  await for (final suggestionsData in userService.streamActiveSuggestions(user.uid)) {
    final suggestions = suggestionsData
        .map((data) => SmartSuggestion.fromJson(data))
        .where((s) => s.isActive) // Filter out dismissed/expired
        .toList();

    // Sort by priority (highest first)
    suggestions.sort((a, b) => b.priority.compareTo(a.priority));

    yield suggestions;
  }
});

/// Notifier for managing suggestions
class SuggestionsNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Nothing to build
  }

  /// Dismiss a suggestion
  Future<void> dismissSuggestion(String suggestionId) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    final userService = ref.read(userServiceProvider);
    await userService.dismissSuggestion(user.uid, suggestionId);
  }

  /// Generate new suggestions based on current habits
  Future<void> generateSuggestions() async {
    final habitLearner = ref.read(currentUserHabitLearnerProvider);
    if (habitLearner == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await habitLearner.generateSuggestions();
    });
  }
}

final suggestionsNotifierProvider = AutoDisposeAsyncNotifierProvider<SuggestionsNotifier, void>(
  () => SuggestionsNotifier(),
);

// ==================== Detected Habits ====================

/// Provider for detected habits
final detectedHabitsProvider = FutureProvider.autoDispose<List<DetectedHabit>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];

  final userService = ref.watch(userServiceProvider);
  final habitsData = await userService.getDetectedHabits(user.uid, limit: 20);

  return habitsData
      .map((data) => DetectedHabit.fromJson(data))
      .where((h) => h.confidence >= 0.6) // Only show confident habits
      .toList()
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
});

/// Notifier for habit analysis
class HabitAnalysisNotifier extends AutoDisposeAsyncNotifier<List<DetectedHabit>> {
  @override
  Future<List<DetectedHabit>> build() async {
    // Automatically analyze on build
    return _analyzeHabits();
  }

  Future<List<DetectedHabit>> _analyzeHabits() async {
    final habitLearner = ref.read(currentUserHabitLearnerProvider);
    if (habitLearner == null) return [];

    return await habitLearner.analyzeHabits(daysToAnalyze: 30);
  }

  /// Trigger habit analysis
  Future<void> analyzeHabits({int days = 30}) async {
    final habitLearner = ref.read(currentUserHabitLearnerProvider);
    if (habitLearner == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return await habitLearner.analyzeHabits(daysToAnalyze: days);
    });
  }
}

final habitAnalysisNotifierProvider = AutoDisposeAsyncNotifierProvider<HabitAnalysisNotifier, List<DetectedHabit>>(
  () => HabitAnalysisNotifier(),
);

// ==================== Usage Analytics ====================

/// Stream of recent pattern usage events
final recentUsageProvider = StreamProvider.autoDispose.family<List<PatternUsageEvent>, int>(
  (ref, limit) async* {
    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      yield [];
      return;
    }

    final userService = ref.watch(userServiceProvider);
    await for (final usageData in userService.streamRecentUsage(user.uid, limit: limit)) {
      final events = usageData.map((data) {
        // Create a mock document snapshot for fromFirestore
        return PatternUsageEvent(
          id: data['id'] as String,
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
      }).toList();

      yield events;
    }
  },
);

/// Provider for pattern usage frequency
final patternFrequencyProvider = FutureProvider.autoDispose.family<Map<String, int>, int>(
  (ref, days) async {
    final user = ref.watch(authStateProvider).value;
    if (user == null) return {};

    final userService = ref.watch(userServiceProvider);
    return await userService.getPatternFrequency(user.uid, days: days);
  },
);

/// Notifier for logging pattern usage
class UsageLoggerNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Nothing to build
  }

  /// Log a pattern usage event
  Future<void> logUsage({
    required String source,
    String? patternName,
    List<String>? colorNames,
    int? effectId,
    String? effectName,
    int? paletteId,
    int? brightness,
    int? speed,
    int? intensity,
    Map<String, dynamic>? wledPayload,
  }) async {
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      final userService = ref.read(userServiceProvider);
      await userService.logPatternUsage(
        userId: user.uid,
        source: source,
        patternName: patternName,
        colorNames: colorNames,
        effectId: effectId,
        effectName: effectName,
        paletteId: paletteId,
        brightness: brightness,
        speed: speed,
        intensity: intensity,
        wled: wledPayload,
      );

      // Contribute to global analytics if user has opted in
      final aggregator = ref.read(currentUserAnalyticsProvider);
      if (aggregator != null) {
        final event = PatternUsageEvent(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          createdAt: DateTime.now(),
          source: source,
          colorNames: colorNames,
          effectId: effectId,
          effectName: effectName,
          paletteId: paletteId,
          brightness: brightness,
          speed: speed,
          intensity: intensity,
          wledPayload: wledPayload,
          patternName: patternName,
        );

        // Fire and forget - don't block on analytics
        aggregator.contributePatternUsage(event).catchError((e) {
          // Silently fail - analytics should never block user experience
        });
      }
    } catch (e) {
      // Silently fail - usage logging should never crash the app
      debugPrint('❌ UsageLoggerNotifier.logUsage failed: $e');
    }
  }
}

final usageLoggerNotifierProvider = AutoDisposeAsyncNotifierProvider<UsageLoggerNotifier, void>(
  () => UsageLoggerNotifier(),
);
