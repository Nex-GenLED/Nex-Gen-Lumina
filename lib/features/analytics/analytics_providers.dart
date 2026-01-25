import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/services/analytics_aggregator.dart';
import 'package:nexgen_command/models/analytics_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

// ==================== User Preference Providers ====================

/// Provider for user's analytics opt-in preference
/// Default is true (opt-in), but users can disable in settings
final analyticsOptInProvider = StateProvider<bool>((ref) {
  // Check user profile for preference
  final profile = ref.watch(currentUserProfileProvider).value;
  return profile?.analyticsEnabled ?? true; // Default opt-in
});

// ==================== Analytics Service Provider ====================

/// Provider for AnalyticsAggregator service
final analyticsAggregatorProvider = Provider.family<AnalyticsAggregator?, String>((ref, userId) {
  if (userId.isEmpty) return null;

  // Check if user has opted in to analytics
  final optedIn = ref.watch(analyticsOptInProvider);
  if (!optedIn) return null;

  return AnalyticsAggregator(userId: userId);
});

/// Provider for current user's analytics aggregator
final currentUserAnalyticsProvider = Provider<AnalyticsAggregator?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;

  return ref.watch(analyticsAggregatorProvider(user.uid));
});

// ==================== Trending Patterns Providers ====================

/// Stream of trending patterns (top 10 most used)
final trendingPatternsProvider = StreamProvider.autoDispose<List<GlobalPatternStats>>((ref) async* {
  final aggregator = ref.watch(currentUserAnalyticsProvider);
  if (aggregator == null) {
    yield [];
    return;
  }

  await for (final patterns in aggregator.streamTrendingPatterns(limit: 10)) {
    yield patterns;
  }
});

/// Future provider for trending patterns (one-time fetch)
final trendingPatternsFutureProvider = FutureProvider.autoDispose<List<GlobalPatternStats>>((ref) async {
  final aggregator = ref.watch(currentUserAnalyticsProvider);
  if (aggregator == null) return [];

  return await aggregator.getTrendingPatterns(limit: 10);
});

// ==================== Pattern Requests Providers ====================

/// Stream of most requested patterns
final mostRequestedPatternsProvider = StreamProvider.autoDispose<List<PatternRequest>>((ref) async* {
  final aggregator = ref.watch(currentUserAnalyticsProvider);
  if (aggregator == null) {
    yield [];
    return;
  }

  await for (final requests in aggregator.streamMostRequestedPatterns(limit: 20)) {
    yield requests;
  }
});

/// Future provider for most requested patterns
final mostRequestedPatternsFutureProvider = FutureProvider.autoDispose<List<PatternRequest>>((ref) async {
  final aggregator = ref.watch(currentUserAnalyticsProvider);
  if (aggregator == null) return [];

  return await aggregator.getMostRequestedPatterns(limit: 20);
});

// ==================== Effect Popularity Providers ====================

/// Future provider for effect popularity stats
final effectPopularityProvider = FutureProvider.autoDispose<List<EffectPopularity>>((ref) async {
  final aggregator = ref.watch(currentUserAnalyticsProvider);
  if (aggregator == null) return [];

  return await aggregator.getEffectPopularity(limit: 20);
});

// ==================== Analytics Action Notifiers ====================

/// Notifier for submitting pattern feedback
class PatternFeedbackNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Nothing to build
  }

  /// Submit feedback for a pattern
  Future<void> submitFeedback({
    required String patternName,
    required int rating,
    String? comment,
    required bool saved,
    String? source,
  }) async {
    final aggregator = ref.read(currentUserAnalyticsProvider);
    if (aggregator == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await aggregator.submitPatternFeedback(
        patternName: patternName,
        rating: rating.clamp(1, 5),
        comment: comment,
        saved: saved,
        source: source,
      );
    });
  }
}

final patternFeedbackNotifierProvider = AutoDisposeAsyncNotifierProvider<PatternFeedbackNotifier, void>(
  () => PatternFeedbackNotifier(),
);

/// Notifier for requesting missing patterns
class PatternRequestNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Nothing to build
  }

  /// Request a new pattern
  Future<void> requestPattern({
    required String requestedTheme,
    String? description,
    List<String>? suggestedColors,
    String? suggestedCategory,
  }) async {
    final aggregator = ref.read(currentUserAnalyticsProvider);
    if (aggregator == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await aggregator.requestPattern(
        requestedTheme: requestedTheme,
        description: description,
        suggestedColors: suggestedColors,
        suggestedCategory: suggestedCategory,
      );
    });
  }

  /// Vote for an existing pattern request
  Future<void> voteForRequest(String requestId) async {
    final aggregator = ref.read(currentUserAnalyticsProvider);
    if (aggregator == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await aggregator.voteForPatternRequest(requestId);
    });
  }
}

final patternRequestNotifierProvider = AutoDisposeAsyncNotifierProvider<PatternRequestNotifier, void>(
  () => PatternRequestNotifier(),
);

/// Notifier for managing analytics opt-in/opt-out
class AnalyticsPreferenceNotifier extends AutoDisposeAsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // Get current preference from user profile
    final profile = ref.watch(currentUserProfileProvider).value;
    return profile?.analyticsEnabled ?? true;
  }

  /// Update analytics opt-in preference
  Future<void> setOptIn(bool enabled) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Update user profile in Firestore
      final userService = ref.read(userServiceProvider);
      await userService.updateUserProfile(user.uid, {
        'analytics_enabled': enabled,
      });

      // Update local state
      ref.read(analyticsOptInProvider.notifier).state = enabled;

      return enabled;
    });
  }
}

final analyticsPreferenceNotifierProvider = AutoDisposeAsyncNotifierProvider<AnalyticsPreferenceNotifier, bool>(
  () => AnalyticsPreferenceNotifier(),
);
