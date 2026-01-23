import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // ==================== Auto-Favorites ====================

  /// Auto-populate favorites with most-used patterns
  Future<void> updateAutoFavorites({int topN = 5}) async {
    try {
      // Get current favorites
      final currentFavorites = await _userService.getFavorites(userId);
      final autoFavIds = currentFavorites
          .where((f) => f['auto_added'] == true)
          .map((f) => f['id'] as String)
          .toSet();

      // Get usage statistics
      final frequency = await _userService.getPatternFrequency(userId, days: 30);
      final recentUsage = await _userService.getRecentUsage(userId, days: 30);

      // Calculate scores for each pattern
      final patternScores = <String, PatternUsageStats>{};
      for (final entry in frequency.entries) {
        final patternName = entry.key;
        final usageCount = entry.value;

        // Find most recent usage
        final recentEvents = recentUsage.where((e) {
          final name = e['pattern_name'] as String?;
          final effectId = e['effect_id']?.toString();
          return name == patternName || 'effect_$effectId' == patternName;
        }).toList();

        if (recentEvents.isEmpty) continue;

        final lastUsed = (recentEvents.first['created_at'] as Timestamp).toDate();
        final firstUsed = (recentEvents.last['created_at'] as Timestamp).toDate();

        final stats = PatternUsageStats(
          patternId: patternName,
          patternName: patternName,
          usageCount: usageCount,
          lastUsed: lastUsed,
          firstUsed: firstUsed,
          sources: recentEvents
              .map((e) => e['source'] as String?)
              .whereType<String>()
              .toSet()
              .toList(),
          avgBrightness: recentEvents
                  .map((e) => e['brightness'] as num?)
                  .whereType<num>()
                  .fold<double>(0, (sum, b) => sum + b.toDouble()) /
              recentEvents.length.clamp(1, double.infinity),
        );

        patternScores[patternName] = stats;
      }

      // Rank patterns by favorite score
      final rankedPatterns = patternScores.values.toList()
        ..sort((a, b) => b.favoriteScore.compareTo(a.favoriteScore));

      // Get top N patterns that aren't already manually favorited
      final manualFavoriteNames = currentFavorites
          .where((f) => f['auto_added'] != true)
          .map((f) => f['pattern_name'] as String?)
          .whereType<String>()
          .toSet();

      final topPatterns = rankedPatterns
          .where((stats) => !manualFavoriteNames.contains(stats.patternName))
          .take(topN)
          .toList();

      // Remove old auto-favorites that are no longer in top N
      final topPatternNames = topPatterns.map((p) => p.patternName).toSet();
      for (final favId in autoFavIds) {
        final fav = currentFavorites.firstWhere((f) => f['id'] == favId);
        final favName = fav['pattern_name'] as String?;
        if (favName != null && !topPatternNames.contains(favName)) {
          await _userService.removeFavorite(userId, favId);
          debugPrint('🗑️ Removed outdated auto-favorite: $favName');
        }
      }

      // Add new auto-favorites
      for (final pattern in topPatterns) {
        // Check if already favorited
        final alreadyFavorited = currentFavorites.any(
          (f) => f['pattern_name'] == pattern.patternName,
        );

        if (!alreadyFavorited) {
          // Find a recent event to extract pattern data
          final recentEvent = recentUsage.firstWhere(
            (e) => e['pattern_name'] == pattern.patternName,
            orElse: () => <String, dynamic>{},
          );

          await _userService.addFavorite(userId, {
            'pattern_name': pattern.patternName,
            'pattern_data': recentEvent['wled'] ?? {},
            'auto_added': true,
          });

          debugPrint('⭐ Auto-added favorite: ${pattern.patternName}');
        }
      }
    } catch (e) {
      debugPrint('❌ updateAutoFavorites failed: $e');
    }
  }

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

      final key = patternName ?? 'effect_$effectId' ?? 'unknown';
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
