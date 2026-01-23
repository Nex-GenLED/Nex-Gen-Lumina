import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/autopilot/habit_learner.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/notifications_service.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Background service that periodically analyzes habits and generates suggestions.
///
/// This service should be called:
/// - Once per day (check habits and refresh auto-favorites)
/// - On app startup (check for contextual suggestions)
/// - After significant usage events
class SuggestionService {
  final UserService _userService;
  final String userId;

  SuggestionService({
    required UserService userService,
    required this.userId,
  }) : _userService = userService;

  /// Run the daily suggestion generation routine
  Future<void> runDailySuggestionCheck() async {
    try {
      debugPrint('🤖 Running daily suggestion check...');

      final habitLearner = HabitLearner(
        userService: _userService,
        userId: userId,
      );

      // 1. Analyze habits
      final habits = await habitLearner.analyzeHabits(daysToAnalyze: 30);
      debugPrint('✅ Detected ${habits.length} habits');

      // 2. Update auto-favorites
      await habitLearner.updateAutoFavorites(topN: 5);
      debugPrint('✅ Updated auto-favorites');

      // 3. Generate suggestions
      final suggestions = await habitLearner.generateSuggestions();
      debugPrint('✅ Generated ${suggestions.length} suggestions');

      // 4. Send high-priority suggestions as notifications
      await _sendSuggestionNotifications(suggestions);
    } catch (e) {
      debugPrint('❌ runDailySuggestionCheck failed: $e');
    }
  }

  /// Check for contextual suggestions (sunset, game day, etc.)
  Future<void> checkContextualSuggestions() async {
    try {
      final now = DateTime.now();
      final hour = now.hour;

      // Evening/sunset suggestion
      if (hour >= 17 && hour < 20) {
        await _createSunsetSuggestion();
      }

      // Late night turn-off suggestion
      if (hour >= 22 || hour < 1) {
        await _createNightTimeSuggestion();
      }

      // Morning turn-on suggestion
      if (hour >= 6 && hour < 9) {
        await _createMorningSuggestion();
      }
    } catch (e) {
      debugPrint('❌ checkContextualSuggestions failed: $e');
    }
  }

  /// Create a sunset/evening suggestion
  Future<void> _createSunsetSuggestion() async {
    try {
      final suggestion = SmartSuggestion(
        id: 'sunset_${DateTime.now().day}',
        type: SuggestionType.applyPattern,
        title: 'Turn on Warm White for Evening',
        description: 'It\'s almost sunset - create a cozy ambiance?',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 3)),
        actionData: {
          'pattern_name': 'Warm White Glow',
          'effect_id': 0,
          'brightness': 200,
          'colors': ['warm_white'],
        },
        priority: 0.8,
      );

      await _userService.saveSuggestion(userId, suggestion.toJson());

      // Send notification
      await NotificationsService.showSuggestion(
        suggestion.title,
        suggestion.description,
      );
    } catch (e) {
      debugPrint('_createSunsetSuggestion failed: $e');
    }
  }

  /// Create a nighttime turn-off suggestion
  Future<void> _createNightTimeSuggestion() async {
    try {
      // Check if user has a habit of turning off lights at night
      final frequency = await _userService.getPatternFrequency(userId, days: 30);
      final usageByHour = await _userService.getUsageByHour(userId, days: 30);

      // Look for nighttime turn-off patterns (11pm - 1am)
      final nightUsage = [22, 23, 0].expand((h) => usageByHour[h] ?? []).toList();

      if (nightUsage.length >= 5) {
        // User has a pattern
        final suggestion = SmartSuggestion(
          id: 'night_off_${DateTime.now().day}',
          type: SuggestionType.createSchedule,
          title: 'Schedule Lights Off at 11:00 PM?',
          description: 'You usually turn off lights around this time - want to automate it?',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 3)),
          actionData: {
            'hour': 23,
            'minute': 0,
            'action': 'off',
            'days': [0, 1, 2, 3, 4, 5, 6], // Every day
          },
          priority: 0.75,
        );

        await _userService.saveSuggestion(userId, suggestion.toJson());
      }
    } catch (e) {
      debugPrint('_createNightTimeSuggestion failed: $e');
    }
  }

  /// Create a morning turn-on suggestion
  Future<void> _createMorningSuggestion() async {
    try {
      final usageByHour = await _userService.getUsageByHour(userId, days: 30);

      // Look for morning turn-on patterns (6am - 9am)
      final morningUsage = [6, 7, 8].expand((h) => usageByHour[h] ?? []).toList();

      if (morningUsage.length >= 5) {
        // User has a morning pattern
        final suggestion = SmartSuggestion(
          id: 'morning_on_${DateTime.now().day}',
          type: SuggestionType.createSchedule,
          title: 'Schedule Morning Lights at 7:00 AM?',
          description: 'You often turn on lights in the morning - automate it?',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 3)),
          actionData: {
            'hour': 7,
            'minute': 0,
            'action': 'on',
            'brightness': 150,
            'days': [1, 2, 3, 4, 5], // Weekdays
          },
          priority: 0.7,
        );

        await _userService.saveSuggestion(userId, suggestion.toJson());
      }
    } catch (e) {
      debugPrint('_createMorningSuggestion failed: $e');
    }
  }

  /// Send notifications for high-priority suggestions
  Future<void> _sendSuggestionNotifications(List<SmartSuggestion> suggestions) async {
    try {
      // Only notify for high-priority suggestions
      final highPriority = suggestions.where((s) => s.priority >= 0.8).toList();

      for (final suggestion in highPriority.take(2)) {
        // Max 2 notifications
        await NotificationsService.showSuggestion(
          suggestion.title,
          suggestion.description,
        );
      }
    } catch (e) {
      debugPrint('_sendSuggestionNotifications failed: $e');
    }
  }

  /// Detect event-based suggestions (game day, holidays)
  Future<void> checkEventSuggestions({
    String? eventName,
    DateTime? eventDate,
  }) async {
    try {
      if (eventName == null || eventDate == null) return;

      // Create event reminder suggestion
      final suggestion = SmartSuggestion(
        id: 'event_${eventName.toLowerCase().replaceAll(' ', '_')}_${eventDate.day}',
        type: SuggestionType.eventReminder,
        title: '$eventName is Tomorrow!',
        description: 'Your $eventName pattern is ready to use',
        createdAt: DateTime.now(),
        expiresAt: eventDate.add(const Duration(hours: 12)),
        actionData: {
          'event_name': eventName,
          'event_date': eventDate.toIso8601String(),
        },
        priority: 0.9,
      );

      await _userService.saveSuggestion(userId, suggestion.toJson());

      // Send notification
      await NotificationsService.showEventReminder(eventName);
    } catch (e) {
      debugPrint('checkEventSuggestions failed: $e');
    }
  }

  /// Suggest adding frequently used pattern to favorites
  Future<void> suggestAddingToFavorites(String patternName, int usageCount) async {
    try {
      if (usageCount < 5) return; // Need at least 5 uses

      final suggestion = SmartSuggestion(
        id: 'add_favorite_$patternName',
        type: SuggestionType.favorite,
        title: 'Add "$patternName" to Favorites?',
        description: 'You\'ve used this pattern $usageCount times',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        actionData: {
          'pattern_name': patternName,
          'usage_count': usageCount,
        },
        priority: 0.6,
      );

      await _userService.saveSuggestion(userId, suggestion.toJson());
    } catch (e) {
      debugPrint('suggestAddingToFavorites failed: $e');
    }
  }
}
