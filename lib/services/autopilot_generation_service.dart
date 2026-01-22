import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/models/autopilot_profile.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/models/custom_holiday.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/calendar_event_service.dart';
import 'package:nexgen_command/services/hoa_compliance_service.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:uuid/uuid.dart';

/// Service responsible for generating autopilot schedule suggestions.
///
/// Uses a combination of:
/// - Calendar events (holidays, sports games)
/// - User preferences (teams, holidays, vibe level)
/// - HOA compliance rules
/// - Learned preferences from feedback
/// - Lumina AI for pattern generation
class AutopilotGenerationService {
  final Ref _ref;
  final _uuid = const Uuid();

  AutopilotGenerationService(this._ref);

  /// Generate a weekly schedule based on user profile.
  ///
  /// Returns a list of suggested schedule items for the next 7 days.
  Future<List<AutopilotScheduleItem>> generateWeeklySchedule({
    required UserModel profile,
    DateTime? weekStart,
  }) async {
    final start = weekStart ?? DateTime.now();
    final end = start.add(const Duration(days: 7));
    final suggestions = <AutopilotScheduleItem>[];

    // Always add a daily warm white sunset-to-sunrise schedule as the baseline
    final dailyWarmWhite = await _generateDailyWarmWhiteSchedule(profile);
    if (dailyWarmWhite != null) {
      suggestions.add(dailyWarmWhite);
    }

    // Get calendar events for the week
    final calendarService = _ref.read(calendarEventServiceProvider);
    final events = await calendarService.getEventsForDateRange(start, end, profile);

    // Get HOA compliance service
    final hoaService = _ref.read(hoaComplianceServiceProvider);

    // Determine the change tolerance
    final tolerance = ChangeToleranceLevel.fromValue(profile.changeToleranceLevel);

    // Track changes per day to respect tolerance
    final changesPerDay = <int, int>{};

    for (final event in events) {
      // Calculate which day this event is on
      final dayOfYear = _dayOfYear(event.date);

      // Check if we've hit the max changes for this day
      final currentChanges = changesPerDay[dayOfYear] ?? 0;
      if (tolerance.maxChangesPerDay > 0 && currentChanges >= tolerance.maxChangesPerDay) {
        continue;
      }

      // Calculate scheduled time (usually sunset for most events)
      DateTime scheduledTime = event.date;
      if (profile.latitude != null && profile.longitude != null) {
        final sunset = SunUtils.sunsetLocal(
          profile.latitude!,
          profile.longitude!,
          event.date,
        );
        if (sunset != null) {
          scheduledTime = sunset;
        }
      }

      // Check HOA compliance
      if (!hoaService.isTimeAllowed(scheduledTime, profile)) {
        // Try to adjust to start of allowed window
        scheduledTime = hoaService.getNextAllowedTime(scheduledTime, profile);
      }

      // Check if colors are allowed for this date
      final colorsAllowed = hoaService.areColorsAllowed(event.date, profile);

      // Generate pattern suggestion
      final suggestion = await _generateSuggestionForEvent(
        event: event,
        profile: profile,
        scheduledTime: scheduledTime,
        colorsAllowed: colorsAllowed,
      );

      if (suggestion != null) {
        suggestions.add(suggestion);
        changesPerDay[dayOfYear] = currentChanges + 1;
      }
    }

    // Add default daily patterns if tolerance allows
    if (tolerance.maxChangesPerDay >= 1) {
      final dailyDefaults = await _generateDailyDefaults(
        profile: profile,
        start: start,
        end: end,
        existingSuggestions: suggestions,
        tolerance: tolerance,
        hoaService: hoaService,
      );
      suggestions.addAll(dailyDefaults);
    }

    // Sort by scheduled time
    suggestions.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    return suggestions;
  }

  /// Generate a suggestion for a specific calendar event.
  Future<AutopilotScheduleItem?> _generateSuggestionForEvent({
    required CalendarEvent event,
    required UserModel profile,
    required DateTime scheduledTime,
    required bool colorsAllowed,
  }) async {
    try {
      // Build prompt for AI generation
      final prompt = _buildEventPrompt(event, profile, colorsAllowed);

      // Try to get AI-generated pattern
      Map<String, dynamic> wledPayload;
      String patternName;
      double confidence;

      try {
        // Use LuminaBrain to generate WLED JSON
        wledPayload = await LuminaBrain.generateWledJson(
          _ref as WidgetRef,
          prompt,
        );
        patternName = event.name;
        confidence = _calculateConfidence(event, profile);
      } catch (e) {
        debugPrint('AutopilotGeneration: AI generation failed, using fallback: $e');
        // Fallback to rule-based pattern
        final fallback = _getFallbackPattern(event, colorsAllowed);
        wledPayload = fallback['payload'] as Map<String, dynamic>;
        patternName = fallback['name'] as String;
        confidence = 0.5;
      }

      // Apply vibe level adjustments
      wledPayload = _applyVibeLevel(wledPayload, profile.vibeLevel ?? 0.5);

      return AutopilotScheduleItem(
        id: _uuid.v4(),
        scheduledTime: scheduledTime,
        repeatDays: const [],
        patternName: patternName,
        reason: _buildReason(event),
        trigger: _eventTypeToTrigger(event.type),
        confidenceScore: confidence,
        wledPayload: wledPayload,
        colors: event.suggestedColors?.map((c) => c.value).toList(),
        effectId: event.suggestedEffectId,
        createdAt: DateTime.now(),
        eventName: event.name,
      );
    } catch (e) {
      debugPrint('AutopilotGeneration: Failed to generate suggestion: $e');
      return null;
    }
  }

  /// Generate a recurring daily warm white sunset-to-sunrise schedule.
  /// This serves as the baseline lighting for all days.
  Future<AutopilotScheduleItem?> _generateDailyWarmWhiteSchedule(UserModel profile) async {
    try {
      // This is a repeating schedule that runs every day
      final now = DateTime.now();

      // Calculate sunset time for today
      DateTime scheduledTime = DateTime(now.year, now.month, now.day, 18, 0);
      if (profile.latitude != null && profile.longitude != null) {
        final sunset = SunUtils.sunsetLocal(
          profile.latitude!,
          profile.longitude!,
          now,
        );
        if (sunset != null) scheduledTime = sunset;
      }

      // Create a warm white payload
      final wledPayload = {
        'on': true,
        'bri': 180,
        'seg': [
          {
            'col': [[255, 250, 244, 0]], // Warm white
            'fx': 0, // Solid
          }
        ],
      };

      return AutopilotScheduleItem(
        id: _uuid.v4(),
        scheduledTime: scheduledTime,
        repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], // Every day
        patternName: 'Warm White',
        reason: 'Daily evening lighting',
        trigger: AutopilotTrigger.sunset,
        confidenceScore: 1.0,
        wledPayload: wledPayload,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('AutopilotGeneration: Failed to generate daily warm white: $e');
      return null;
    }
  }

  /// Generate default daily patterns for days without events.
  Future<List<AutopilotScheduleItem>> _generateDailyDefaults({
    required UserModel profile,
    required DateTime start,
    required DateTime end,
    required List<AutopilotScheduleItem> existingSuggestions,
    required ChangeToleranceLevel tolerance,
    required HoaComplianceService hoaService,
  }) async {
    final defaults = <AutopilotScheduleItem>[];

    // Get days that already have suggestions
    final daysWithEvents = existingSuggestions
        .map((s) => _dayOfYear(s.scheduledTime))
        .toSet();

    // Only add defaults if tolerance is moderate or higher
    if (tolerance.value < 2) return defaults;

    for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
      final dayOfYear = _dayOfYear(day);

      // Skip days that already have events
      if (daysWithEvents.contains(dayOfYear)) continue;

      // Check minimum days between changes
      if (tolerance.minDaysBetweenChanges > 0) {
        bool tooClose = false;
        for (final existing in existingSuggestions) {
          final diff = day.difference(existing.scheduledTime).inDays.abs();
          if (diff < tolerance.minDaysBetweenChanges) {
            tooClose = true;
            break;
          }
        }
        if (tooClose) continue;
      }

      // Calculate sunset time for this day
      DateTime scheduledTime = DateTime(day.year, day.month, day.day, 18, 0);
      if (profile.latitude != null && profile.longitude != null) {
        final sunset = SunUtils.sunsetLocal(
          profile.latitude!,
          profile.longitude!,
          day,
        );
        if (sunset != null) scheduledTime = sunset;
      }

      // Check HOA compliance
      if (!hoaService.isTimeAllowed(scheduledTime, profile)) continue;

      // Check if colors are allowed
      final colorsAllowed = hoaService.areColorsAllowed(day, profile);

      // Determine if weekend or weeknight
      final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      final trigger = isWeekend ? AutopilotTrigger.weekend : AutopilotTrigger.weeknight;

      // Get appropriate default pattern
      final pattern = _getDefaultPattern(
        isWeekend: isWeekend,
        colorsAllowed: colorsAllowed,
        vibeLevel: profile.vibeLevel ?? 0.5,
      );

      defaults.add(AutopilotScheduleItem(
        id: _uuid.v4(),
        scheduledTime: scheduledTime,
        repeatDays: const [],
        patternName: pattern['name'] as String,
        reason: isWeekend ? 'Weekend ambiance' : 'Weeknight lighting',
        trigger: trigger,
        confidenceScore: 0.6,
        wledPayload: pattern['payload'] as Map<String, dynamic>,
        createdAt: DateTime.now(),
      ));
    }

    return defaults;
  }

  /// Build the prompt for AI pattern generation.
  String _buildEventPrompt(CalendarEvent event, UserModel profile, bool colorsAllowed) {
    final buffer = StringBuffer();
    buffer.writeln('Generate a WLED lighting pattern for: ${event.name}');
    buffer.writeln();

    if (event.suggestedColors != null && event.suggestedColors!.isNotEmpty) {
      buffer.writeln('Suggested colors to use:');
      for (final color in event.suggestedColors!) {
        buffer.writeln('- RGB(${color.red}, ${color.green}, ${color.blue})');
      }
    }

    if (event.teamName != null) {
      buffer.writeln('This is for the ${event.teamName} team.');
    }

    buffer.writeln();
    buffer.writeln('User preferences:');
    buffer.writeln('- Vibe level: ${_vibeDescription(profile.vibeLevel ?? 0.5)}');

    if (profile.preferredEffectStyles.isNotEmpty) {
      buffer.writeln('- Preferred styles: ${profile.preferredEffectStyles.join(", ")}');
    }

    if (!colorsAllowed) {
      buffer.writeln('- IMPORTANT: Only use white/warm white colors (HOA restriction)');
    }

    if (profile.dislikes.isNotEmpty) {
      buffer.writeln('- AVOID: ${profile.dislikes.join(", ")}');
    }

    return buffer.toString();
  }

  /// Calculate confidence score for a suggestion.
  double _calculateConfidence(CalendarEvent event, UserModel profile) {
    double score = 0.5;

    // Boost for favorite holidays
    if (event.type == CalendarEventType.holiday) {
      if (profile.favoriteHolidays.any((h) =>
          event.name.toLowerCase().contains(h.toLowerCase()))) {
        score += 0.25;
      }
    }

    // Boost for sports teams
    if (event.type == CalendarEventType.sportGame && event.teamName != null) {
      final teamIndex = profile.sportsTeamPriority.indexOf(event.teamName!);
      if (teamIndex == 0) {
        score += 0.3; // Primary team
      } else if (teamIndex > 0) {
        score += 0.2; // Other followed team
      } else if (profile.sportsTeams.contains(event.teamName)) {
        score += 0.15;
      }
    }

    // Adjust for vibe level matching
    if (event.type == CalendarEventType.sportGame && (profile.vibeLevel ?? 0.5) > 0.7) {
      score += 0.1; // Bold users like game day patterns
    }

    return score.clamp(0.0, 1.0);
  }

  /// Get a fallback pattern when AI generation fails.
  Map<String, dynamic> _getFallbackPattern(CalendarEvent event, bool colorsAllowed) {
    if (!colorsAllowed) {
      return {
        'name': 'Architectural White',
        'payload': {
          'on': true,
          'bri': 180,
          'seg': [
            {
              'col': [[255, 250, 244]], // Warm white
              'fx': 0, // Solid
            }
          ],
        },
      };
    }

    // Use event colors if available
    if (event.suggestedColors != null && event.suggestedColors!.isNotEmpty) {
      final colors = event.suggestedColors!
          .take(3)
          .map((c) => [c.red, c.green, c.blue])
          .toList();

      return {
        'name': event.name,
        'payload': {
          'on': true,
          'bri': 200,
          'seg': [
            {
              'col': colors,
              'fx': 0, // Solid
            }
          ],
        },
      };
    }

    // Generic fallback
    return {
      'name': 'Ambient Glow',
      'payload': {
        'on': true,
        'bri': 180,
        'seg': [
          {
            'col': [[255, 180, 100]], // Warm amber
            'fx': 0,
          }
        ],
      },
    };
  }

  /// Get default pattern for days without events.
  Map<String, dynamic> _getDefaultPattern({
    required bool isWeekend,
    required bool colorsAllowed,
    required double vibeLevel,
  }) {
    if (!colorsAllowed) {
      return {
        'name': 'Architectural White',
        'payload': {
          'on': true,
          'bri': isWeekend ? 200 : 150,
          'seg': [
            {
              'col': [[255, 250, 244]],
              'fx': 0,
            }
          ],
        },
      };
    }

    if (isWeekend && vibeLevel > 0.5) {
      return {
        'name': 'Weekend Ambiance',
        'payload': {
          'on': true,
          'bri': 220,
          'seg': [
            {
              'col': [[255, 200, 150], [255, 180, 120]],
              'fx': 0,
            }
          ],
        },
      };
    }

    return {
      'name': 'Evening Glow',
      'payload': {
        'on': true,
        'bri': 150,
        'seg': [
          {
            'col': [[255, 220, 180]],
            'fx': 0,
          }
        ],
      },
    };
  }

  /// Apply vibe level adjustments to the WLED payload.
  Map<String, dynamic> _applyVibeLevel(Map<String, dynamic> payload, double vibeLevel) {
    final adjusted = Map<String, dynamic>.from(payload);

    // Adjust brightness based on vibe level
    if (adjusted.containsKey('bri')) {
      final baseBri = adjusted['bri'] as int;
      // Subtle (0.0) = 60% brightness, Bold (1.0) = 100%
      adjusted['bri'] = (baseBri * (0.6 + vibeLevel * 0.4)).round().clamp(10, 255);
    }

    // Could add effect speed/intensity adjustments here in the future

    return adjusted;
  }

  /// Build human-readable reason for a suggestion.
  String _buildReason(CalendarEvent event) {
    switch (event.type) {
      case CalendarEventType.holiday:
        return "It's ${event.name}!";
      case CalendarEventType.sportGame:
        if (event.teamName != null) {
          return '${event.teamName} game day';
        }
        return 'Game day';
      case CalendarEventType.seasonal:
        return 'Seasonal celebration';
      case CalendarEventType.custom:
        return event.name;
    }
  }

  /// Convert calendar event type to autopilot trigger.
  AutopilotTrigger _eventTypeToTrigger(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.holiday:
        return AutopilotTrigger.holiday;
      case CalendarEventType.sportGame:
        return AutopilotTrigger.gameDay;
      case CalendarEventType.seasonal:
        return AutopilotTrigger.seasonal;
      case CalendarEventType.custom:
        return AutopilotTrigger.custom;
    }
  }

  /// Get day of year for grouping.
  int _dayOfYear(DateTime date) {
    return date.difference(DateTime(date.year, 1, 1)).inDays;
  }

  /// Get vibe description for prompts.
  String _vibeDescription(double vibeLevel) {
    if (vibeLevel < 0.3) return 'Subtle and classy';
    if (vibeLevel < 0.5) return 'Moderate';
    if (vibeLevel < 0.7) return 'Vibrant';
    return 'Bold and energetic';
  }
}

/// Provider for the autopilot generation service.
final autopilotGenerationServiceProvider = Provider<AutopilotGenerationService>(
  (ref) => AutopilotGenerationService(ref),
);
