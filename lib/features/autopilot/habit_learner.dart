import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Service for learning user behavior patterns and generating smart suggestions.
///
/// This service analyzes pattern usage data to:
/// - Detect recurring usage patterns (habits)
/// - Auto-populate favorites with most-used patterns
/// - Suggest schedules based on time-of-day patterns
/// - Generate contextual suggestions (sunset, game day, etc.)
class HabitLearner {
  final UserService _userService;
  final String userId;

  HabitLearner({
    required UserService userService,
    required this.userId,
  }) : _userService = userService;

  // ==================== Habit Detection ====================

  /// Analyze usage patterns and detect habits
  Future<List<DetectedHabit>> analyzeHabits({int daysToAnalyze = 30}) async {
    try {
      final habits = <DetectedHabit>[];

      // Detect time-of-day patterns
      final timeHabits = await _detectTimeOfDayHabits(daysToAnalyze);
      habits.addAll(timeHabits);

      // Detect recurring pattern preferences
      final preferenceHabits = await _detectPreferenceHabits(daysToAnalyze);
      habits.addAll(preferenceHabits);

      // Save detected habits to Firestore
      for (final habit in habits) {
        if (habit.confidence >= 0.7) {
          // Only save high-confidence habits
          await _userService.saveDetectedHabit(userId, habit.toJson());
        }
      }

      return habits;
    } catch (e) {
      debugPrint('❌ analyzeHabits failed: $e');
      return [];
    }
  }

  /// Detect consistent time-of-day usage patterns
  Future<List<DetectedHabit>> _detectTimeOfDayHabits(int days) async {
    try {
      final habits = <DetectedHabit>[];
      final usageByHour = await _userService.getUsageByHour(userId, days: days);

      // Look for hours with consistent usage (3+ occurrences)
      for (final entry in usageByHour.entries) {
        final hour = entry.key;
        final events = entry.value;

        if (events.length >= 3) {
          // Found a potential habit
          final confidence = (events.length / days).clamp(0.0, 1.0);

          // Determine the action (on/off, specific pattern)
          final mostCommonPattern = _findMostCommonPattern(events);

          habits.add(DetectedHabit(
            id: 'time_${hour}_${DateTime.now().millisecondsSinceEpoch}',
            type: HabitType.timeOfDay,
            description: _generateTimeHabitDescription(hour, mostCommonPattern, events.length, days),
            confidence: confidence,
            detectedAt: DateTime.now(),
            metadata: {
              'hour': hour,
              'occurrences': events.length,
              'days_analyzed': days,
              'pattern': mostCommonPattern,
            },
          ));
        }
      }

      return habits;
    } catch (e) {
      debugPrint('_detectTimeOfDayHabits failed: $e');
      return [];
    }
  }

  /// Detect pattern preferences (favorite effects, colors)
  Future<List<DetectedHabit>> _detectPreferenceHabits(int days) async {
    try {
      final habits = <DetectedHabit>[];
      final frequency = await _userService.getPatternFrequency(userId, days: days);

      // Find patterns used 5+ times (shows preference)
      final topPatterns = frequency.entries
          .where((e) => e.value >= 5)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in topPatterns.take(5)) {
        // Top 5 patterns
        final patternName = entry.key;
        final count = entry.value;
        final confidence = (count / (days * 2)).clamp(0.3, 1.0); // Used twice per day = 100%

        habits.add(DetectedHabit(
          id: 'preference_${patternName}_${DateTime.now().millisecondsSinceEpoch}',
          type: HabitType.preference,
          description: 'You use "$patternName" frequently ($count times in $days days)',
          confidence: confidence,
          detectedAt: DateTime.now(),
          metadata: {
            'pattern_name': patternName,
            'usage_count': count,
            'days_analyzed': days,
          },
        ));
      }

      return habits;
    } catch (e) {
      debugPrint('_detectPreferenceHabits failed: $e');
      return [];
    }
  }

  // ==================== Auto-Favorites — REMOVED (#164) ====================
  //
  // `updateAutoFavorites` wrote the top-5 most-used patterns into
  // users/{uid}/favorites with `auto_added: true` on every app resume (and
  // deleted the ones that fell out of the top 5). Since +110 every Explore
  // apply logs usage, so browsing patterns filled Home's My Favorites on its
  // own. A favorite is now only ever the customer's explicit choice, capped at
  // two (favorite_doc.dart). Usage history still feeds suggestions and Recent.

  // ==================== Smart Suggestions ====================

  /// Generate smart suggestions based on habits and context
  Future<List<SmartSuggestion>> generateSuggestions() async {
    try {
      final suggestions = <SmartSuggestion>[];

      // Suggest schedules for time-of-day habits
      final schedulesuggestions = await _generateScheduleSuggestions();
      suggestions.addAll(schedulesuggestions);

      // Suggest contextual patterns (sunset, events)
      final contextSuggestions = await _generateContextualSuggestions();
      suggestions.addAll(contextSuggestions);

      // Save suggestions to Firestore
      for (final suggestion in suggestions) {
        await _userService.saveSuggestion(userId, suggestion.toJson());
      }

      return suggestions;
    } catch (e) {
      debugPrint('❌ generateSuggestions failed: $e');
      return [];
    }
  }

  /// Generate schedule suggestions from time-of-day habits
  Future<List<SmartSuggestion>> _generateScheduleSuggestions() async {
    try {
      final suggestions = <SmartSuggestion>[];
      final habits = await _userService.getDetectedHabits(userId);

      for (final habitData in habits) {
        final habit = DetectedHabit.fromJson(habitData);

        if (habit.type == HabitType.timeOfDay && habit.confidence >= 0.7) {
          final hour = habit.metadata['hour'] as int?;
          final pattern = habit.metadata['pattern'] as String?;

          if (hour != null) {
            suggestions.add(SmartSuggestion(
              id: 'schedule_${habit.id}',
              type: SuggestionType.createSchedule,
              title: 'Create Schedule for ${_formatHour(hour)}?',
              description: habit.description,
              createdAt: DateTime.now(),
              expiresAt: DateTime.now().add(const Duration(days: 7)),
              actionData: {
                'hour': hour,
                'pattern': pattern,
                'habit_id': habit.id,
              },
              relatedHabitId: habit.id,
              priority: habit.confidence,
            ));
          }
        }
      }

      return suggestions;
    } catch (e) {
      debugPrint('_generateScheduleSuggestions failed: $e');
      return [];
    }
  }

  /// Generate contextual suggestions (sunset, game day, etc.)
  Future<List<SmartSuggestion>> _generateContextualSuggestions() async {
    try {
      final suggestions = <SmartSuggestion>[];
      final now = DateTime.now();
      final hour = now.hour;

      // Evening suggestion (after 5pm, before 8pm)
      if (hour >= 17 && hour < 20) {
        suggestions.add(SmartSuggestion(
          id: 'sunset_${now.day}',
          type: SuggestionType.applyPattern,
          title: 'Turn on Warm White for Evening',
          description: 'It\'s almost sunset - create a cozy ambiance?',
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 3)),
          actionData: {
            'pattern_name': 'Warm White Glow',
            'effect_id': 0,
            'brightness': 200,
          },
          priority: 0.8,
        ));
      }

      // Late night suggestion (after 10pm)
      if (hour >= 22 || hour < 6) {
        suggestions.add(SmartSuggestion(
          id: 'night_${now.day}',
          type: SuggestionType.createSchedule,
          title: 'Schedule Lights Off at ${_formatHour(23)}?',
          description: 'You usually turn off lights around this time',
          createdAt: now,
          expiresAt: now.add(const Duration(days: 1)),
          actionData: {
            'hour': 23,
            'action': 'off',
          },
          priority: 0.7,
        ));
      }

      return suggestions;
    } catch (e) {
      debugPrint('_generateContextualSuggestions failed: $e');
      return [];
    }
  }

  // ==================== Helper Methods ====================

  String _findMostCommonPattern(List<Map<String, dynamic>> events) {
    final patternCounts = <String, int>{};

    for (final event in events) {
      final patternName = event['pattern_name'] as String?;
      final effectId = event['effect_id']?.toString();

      final key = patternName ?? 'effect_$effectId';
      patternCounts[key] = (patternCounts[key] ?? 0) + 1;
    }

    if (patternCounts.isEmpty) return 'lights';

    return patternCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  String _generateTimeHabitDescription(
    int hour,
    String pattern,
    int occurrences,
    int days,
  ) {
    final timeStr = _formatHour(hour);
    final percentage = ((occurrences / days) * 100).round();

    return 'You usually use "$pattern" around $timeStr ($percentage% of days)';
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12:00 AM';
    if (hour < 12) return '$hour:00 AM';
    if (hour == 12) return '12:00 PM';
    return '${hour - 12}:00 PM';
  }
}
