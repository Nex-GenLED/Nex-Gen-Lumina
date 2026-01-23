import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nexgen_command/features/autopilot/habit_learner.dart';
import 'package:nexgen_command/services/suggestion_service.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Background service for running periodic habit analysis and suggestion generation.
///
/// This service should be triggered:
/// - Once per day (via WorkManager or similar)
/// - On app startup (to check for contextual suggestions)
/// - After significant usage events (optional)
class BackgroundLearningService {
  static final BackgroundLearningService _instance = BackgroundLearningService._internal();
  factory BackgroundLearningService() => _instance;
  BackgroundLearningService._internal();

  DateTime? _lastDailyRun;
  bool _isRunning = false;

  /// Run on app startup - checks for contextual suggestions
  Future<void> onAppStartup() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      debugPrint('🚀 BackgroundLearningService: App startup check');

      final userService = UserService();
      final suggestionService = SuggestionService(
        userService: userService,
        userId: user.uid,
      );

      // Check for contextual suggestions (sunset, morning, etc.)
      await suggestionService.checkContextualSuggestions();

      debugPrint('✅ BackgroundLearningService: Startup check complete');
    } catch (e) {
      debugPrint('❌ BackgroundLearningService startup failed: $e');
    }
  }

  /// Run daily maintenance - habit analysis and auto-favorites update
  Future<void> runDailyMaintenance({bool force = false}) async {
    // Prevent duplicate runs
    if (_isRunning) {
      debugPrint('⚠️ BackgroundLearningService: Already running, skipping');
      return;
    }

    // Check if we've already run today
    final now = DateTime.now();
    if (!force && _lastDailyRun != null) {
      final lastRun = _lastDailyRun!;
      if (now.year == lastRun.year &&
          now.month == lastRun.month &&
          now.day == lastRun.day) {
        debugPrint('⏭️ BackgroundLearningService: Already ran today, skipping');
        return;
      }
    }

    try {
      _isRunning = true;
      _lastDailyRun = now;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ BackgroundLearningService: No user, skipping');
        return;
      }

      debugPrint('🔄 BackgroundLearningService: Starting daily maintenance');

      final userService = UserService();
      final habitLearner = HabitLearner(
        userService: userService,
        userId: user.uid,
      );
      final suggestionService = SuggestionService(
        userService: userService,
        userId: user.uid,
      );

      // 1. Analyze habits (detect patterns)
      debugPrint('🧠 Analyzing user habits...');
      final habits = await habitLearner.analyzeHabits(daysToAnalyze: 30);
      debugPrint('✅ Detected ${habits.length} habits');

      // 2. Update auto-favorites
      debugPrint('⭐ Updating auto-favorites...');
      await habitLearner.updateAutoFavorites(topN: 5);
      debugPrint('✅ Auto-favorites updated');

      // 3. Generate suggestions
      debugPrint('💡 Generating smart suggestions...');
      await suggestionService.runDailySuggestionCheck();
      debugPrint('✅ Suggestions generated');

      debugPrint('✅ BackgroundLearningService: Daily maintenance complete');
    } catch (e, stack) {
      debugPrint('❌ BackgroundLearningService failed: $e');
      debugPrint('Stack trace: $stack');
    } finally {
      _isRunning = false;
    }
  }

  /// Check if we should run daily maintenance
  /// Returns true if it's been more than 20 hours since last run
  bool shouldRunDaily() {
    if (_lastDailyRun == null) return true;

    final now = DateTime.now();
    final hoursSinceLastRun = now.difference(_lastDailyRun!).inHours;

    return hoursSinceLastRun >= 20; // Run if it's been 20+ hours
  }

  /// Manual trigger for testing
  Future<void> forceRun() async {
    _lastDailyRun = null; // Reset to allow run
    await runDailyMaintenance(force: true);
  }

  /// Reset state (for testing)
  void reset() {
    _lastDailyRun = null;
    _isRunning = false;
  }
}

/// Convenience provider access
final backgroundLearningService = BackgroundLearningService();
