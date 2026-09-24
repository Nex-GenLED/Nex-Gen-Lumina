import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/habit_learner.dart';
import 'package:nexgen_command/features/favorites/favorites_load_guard.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/analytics/analytics_providers.dart';
import 'package:nexgen_command/features/whites/white_preference_providers.dart';

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

/// Build the two reserved white slots from user preferences.
/// These always occupy positions 0 and 1 in the favorites list.
List<FavoritePattern> _buildWhiteSlots(Ref ref) {
  final primary = ref.watch(preferredWhitePrimaryProvider);
  final complement = ref.watch(preferredWhiteComplementProvider);

  return [
    FavoritePattern(
      id: 'white_primary',
      patternName: primary.name,
      addedAt: DateTime(2024, 1, 1),
      usageCount: 0,
      patternData: primary.toWledPayload(),
      autoAdded: false,
    ),
    FavoritePattern(
      id: 'white_complement',
      patternName: complement.name,
      addedAt: DateTime(2024, 1, 1),
      usageCount: 0,
      patternData: complement.toWledPayload(),
      autoAdded: false,
    ),
  ];
}

/// Slots 1-2 of My Favorites: the user's preferred whites, permanently
/// reserved. Built locally (defaults until the profile carries preferences),
/// so this row renders at once and never waits on Firestore.
final favoriteWhiteSlotsProvider =
    Provider.autoDispose<List<FavoritePattern>>((ref) => _buildWhiteSlots(ref));

/// Where the signed-in account's OWN profile stands.
enum ProfileProvisioning {
  /// The profile stream has not produced anything yet (cold start).
  loading,

  /// No document, a document that does not parse yet, or no `owner_id` — the
  /// first-login window before the installer's profile write or the
  /// server-side healer lands.
  notProvisioned,

  /// Parses and carries a non-empty `owner_id`, the field `firestore.rules`
  /// `isProvisionedUser()` keys on.
  provisioned,
}

/// [ProfileProvisioning] for the signed-in account.
///
/// `select`, so this rebuilds only when the answer changes. The favorites
/// listen used to rebuild on every emission of the profile stream (through
/// the white slots), i.e. on every write to `users/{uid}` — dozens per second
/// during the build-107 repair loop — and each rebuild threw away the pending
/// listen and started a new one.
final ownProfileProvisioningProvider =
    Provider.autoDispose<ProfileProvisioning>((ref) {
  return ref.watch(currentUserProfileProvider.select((profile) {
    if (!profile.hasValue) {
      return profile.hasError
          ? ProfileProvisioning.notProvisioned
          : ProfileProvisioning.loading;
    }
    return (profile.value?.ownerId ?? '').isNotEmpty
        ? ProfileProvisioning.provisioned
        : ProfileProvisioning.notProvisioned;
  }));
});

/// Slots 3+ of My Favorites: the customer's saved favorites, manual first,
/// then most recently used, then most used.
///
/// Never hangs:
///   • signed out → `[]`;
///   • the signed-in account's own profile not provisioned yet (first login,
///     before the installer's profile write or the server-side healer lands)
///     → `[]` without subscribing — My Favorites shows its empty state;
///   • the profile still loading → loading, but under the same deadline: a
///     profile that never arrives ends in the Retry state, not a spinner;
///   • otherwise the Firestore listen must produce its first snapshot within
///     [favoritesLoadTimeoutProvider], or the listen is cancelled and the
///     provider errors (My Favorites shows Retry).
final userFavoritePatternsProvider =
    StreamProvider.autoDispose<List<FavoritePattern>>((ref) {
  // Effective UID — respects installer impersonation via the
  // existing-customer flow.
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) return Stream.value(const <FavoritePattern>[]);

  // An installer viewing a customer reads THAT customer's favorites; this
  // session's own profile says nothing about whether theirs is provisioned.
  final viewingCustomer =
      (ref.watch(installerAccessingCustomerProvider) ?? '').isNotEmpty;
  final timeout = ref.watch(favoritesLoadTimeoutProvider);
  if (!viewingCustomer) {
    switch (ref.watch(ownProfileProvisioningProvider)) {
      case ProfileProvisioning.notProvisioned:
        return Stream.value(const <FavoritePattern>[]);
      case ProfileProvisioning.loading:
        // Rebuilt (and this stream dropped) the moment the profile arrives.
        return firstEventWithin(
          StreamController<List<FavoritePattern>>().stream,
          timeout,
        );
      case ProfileProvisioning.provisioned:
        break;
    }
  }

  final userService = ref.watch(userServiceProvider);
  return firstEventWithin(
    userService.streamFavorites(uid).map(sortUserFavorites),
    timeout,
  );
});

/// Parses and orders the stored favorites for My Favorites.
@visibleForTesting
List<FavoritePattern> sortUserFavorites(
    List<Map<String, dynamic>> favoritesData) {
  final userFavorites =
      favoritesData.map((data) => FavoritePattern.fromJson(data)).toList();
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
  return userFavorites;
}

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
    // Skip reserved white slots and system defaults - not stored in Firestore
    if (favoriteId.startsWith('system_') || favoriteId.startsWith('white_')) return;

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
