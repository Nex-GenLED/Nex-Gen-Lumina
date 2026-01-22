import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/data/sports_teams.dart';
import 'package:nexgen_command/data/us_federal_holidays.dart';
import 'package:nexgen_command/models/custom_holiday.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/sports_schedule_service.dart';

/// Types of calendar events that can trigger autopilot.
enum CalendarEventType {
  holiday,
  sportGame,
  seasonal,
  custom,
}

/// Represents a calendar event that may trigger a lighting change.
class CalendarEvent {
  /// Display name of the event.
  final String name;

  /// Date/time of the event.
  final DateTime date;

  /// Type of event.
  final CalendarEventType type;

  /// Suggested colors for this event.
  final List<Color>? suggestedColors;

  /// Suggested WLED effect ID.
  final int? suggestedEffectId;

  /// Team name (for sports events).
  final String? teamName;

  /// Priority (lower = higher priority) for conflict resolution.
  final int priority;

  const CalendarEvent({
    required this.name,
    required this.date,
    required this.type,
    this.suggestedColors,
    this.suggestedEffectId,
    this.teamName,
    this.priority = 100,
  });

  @override
  String toString() => 'CalendarEvent($name, ${date.month}/${date.day}, type: $type)';
}

/// Service for aggregating calendar events from multiple sources.
///
/// Combines:
/// - US Federal Holidays
/// - Popular holidays
/// - Custom user-defined holidays
/// - Sports games for followed teams
/// - Seasonal events (equinoxes, solstices)
class CalendarEventService {
  final Ref _ref;

  CalendarEventService(this._ref);

  /// Get all relevant events for a date range.
  Future<List<CalendarEvent>> getEventsForDateRange(
    DateTime start,
    DateTime end,
    UserModel profile,
  ) async {
    final events = <CalendarEvent>[];

    // Get federal and popular holidays
    final holidays = USFederalHolidays.getHolidaysInRange(start, end);
    for (final holiday in holidays) {
      // Only include if user has this holiday in favorites OR it's a major holiday
      final isFavorite = profile.favoriteHolidays.any(
        (fav) => holiday.name.toLowerCase().contains(fav.toLowerCase()) ||
            fav.toLowerCase().contains(holiday.name.toLowerCase()),
      );
      final isMajor = _isMajorHoliday(holiday.name);

      if (isFavorite || isMajor) {
        events.add(CalendarEvent(
          name: holiday.name,
          date: holiday.date,
          type: CalendarEventType.holiday,
          suggestedColors: holiday.suggestedColors,
          suggestedEffectId: holiday.suggestedEffectId,
          priority: isFavorite ? 10 : 20,
        ));
      }
    }

    // Add custom holidays from user profile
    for (final customHoliday in profile.customHolidays) {
      final occurrence = customHoliday.getNextOccurrence(start);
      if (occurrence != null && !occurrence.isAfter(end)) {
        events.add(CalendarEvent(
          name: customHoliday.name,
          date: occurrence,
          type: CalendarEventType.custom,
          suggestedColors: customHoliday.suggestedColors,
          suggestedEffectId: customHoliday.suggestedEffectId,
          priority: 5, // Custom holidays get high priority
        ));
      }
    }

    // Get sports games
    if (profile.sportsTeams.isNotEmpty) {
      final sportsService = _ref.read(sportsScheduleServiceProvider);
      final games = await sportsService.getGamesInRange(
        profile.sportsTeams,
        start,
        end,
      );

      for (final game in games) {
        // Calculate priority based on team order
        final teamPriority = profile.sportsTeamPriority.isNotEmpty
            ? profile.sportsTeamPriority
            : profile.sportsTeams;
        final priorityIndex = teamPriority.indexOf(game.teamName);
        final priority = priorityIndex >= 0 ? 30 + priorityIndex : 50;

        // Get team colors from sports_teams.dart
        final teamColors = _getTeamColors(game.teamName);

        events.add(CalendarEvent(
          name: '${game.teamName} vs ${game.opponent}',
          date: game.gameTime,
          type: CalendarEventType.sportGame,
          suggestedColors: teamColors,
          teamName: game.teamName,
          priority: priority,
        ));
      }
    }

    // Add seasonal events (equinoxes, solstices)
    final seasonalEvents = _getSeasonalEvents(start, end);
    events.addAll(seasonalEvents);

    // Sort by date, then by priority
    events.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.priority.compareTo(b.priority);
    });

    // Resolve conflicts (same day events)
    return _resolveConflicts(events, profile);
  }

  /// Get event for a specific date.
  Future<CalendarEvent?> getEventForDate(DateTime date, UserModel profile) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final events = await getEventsForDateRange(dayStart, dayEnd, profile);
    return events.isNotEmpty ? events.first : null;
  }

  /// Resolve conflicts when multiple events occur on the same day.
  ///
  /// Uses priority system:
  /// 1. Custom holidays (user explicitly added)
  /// 2. Favorite holidays
  /// 3. Primary team game days (index 0 in sportsTeamPriority)
  /// 4. Secondary team game days
  /// 5. Other events
  List<CalendarEvent> _resolveConflicts(
    List<CalendarEvent> events,
    UserModel profile,
  ) {
    final resolvedEvents = <CalendarEvent>[];
    final eventsByDay = <int, List<CalendarEvent>>{};

    // Group events by day
    for (final event in events) {
      final dayKey = _dayKey(event.date);
      eventsByDay.putIfAbsent(dayKey, () => []).add(event);
    }

    // For each day, select the highest priority event
    for (final dayEvents in eventsByDay.values) {
      if (dayEvents.length == 1) {
        resolvedEvents.add(dayEvents.first);
      } else {
        // Sort by priority and take the best one
        dayEvents.sort((a, b) => a.priority.compareTo(b.priority));

        // If it's a holiday + game day, we might want to include both
        // For now, take the highest priority
        resolvedEvents.add(dayEvents.first);

        // If there's both a holiday and a game, and they're within 5 priority points,
        // keep both as the user might want to toggle between them
        if (dayEvents.length > 1) {
          final second = dayEvents[1];
          if (dayEvents.first.type != second.type &&
              (second.priority - dayEvents.first.priority).abs() <= 5) {
            resolvedEvents.add(second);
          }
        }
      }
    }

    return resolvedEvents;
  }

  /// Get seasonal events (equinoxes and solstices).
  List<CalendarEvent> _getSeasonalEvents(DateTime start, DateTime end) {
    final events = <CalendarEvent>[];

    for (int year = start.year; year <= end.year; year++) {
      final seasonals = [
        CalendarEvent(
          name: 'Spring Equinox',
          date: DateTime(year, 3, 20), // Approximate
          type: CalendarEventType.seasonal,
          suggestedColors: [
            const Color(0xFF90EE90), // Light green
            const Color(0xFFFFB6C1), // Light pink
            const Color(0xFFFFFF00), // Yellow
          ],
          priority: 80,
        ),
        CalendarEvent(
          name: 'Summer Solstice',
          date: DateTime(year, 6, 21), // Approximate
          type: CalendarEventType.seasonal,
          suggestedColors: [
            const Color(0xFFFFD700), // Gold
            const Color(0xFFFF6600), // Orange
            const Color(0xFFFF0000), // Red
          ],
          priority: 80,
        ),
        CalendarEvent(
          name: 'Fall Equinox',
          date: DateTime(year, 9, 22), // Approximate
          type: CalendarEventType.seasonal,
          suggestedColors: [
            const Color(0xFFFF6600), // Orange
            const Color(0xFF8B4513), // Brown
            const Color(0xFFFFD700), // Gold
          ],
          priority: 80,
        ),
        CalendarEvent(
          name: 'Winter Solstice',
          date: DateTime(year, 12, 21), // Approximate
          type: CalendarEventType.seasonal,
          suggestedColors: [
            const Color(0xFF87CEEB), // Sky blue
            const Color(0xFFFFFFFF), // White
            const Color(0xFFC0C0C0), // Silver
          ],
          priority: 80,
        ),
      ];

      for (final event in seasonals) {
        if (!event.date.isBefore(start) && !event.date.isAfter(end)) {
          events.add(event);
        }
      }
    }

    return events;
  }

  /// Check if a holiday is a major one that should always be included.
  bool _isMajorHoliday(String name) {
    const majorHolidays = [
      'christmas',
      'thanksgiving',
      'independence day',
      'july 4',
      'halloween',
      "new year's",
      'easter',
    ];

    final lowerName = name.toLowerCase();
    return majorHolidays.any((h) => lowerName.contains(h));
  }

  /// Get team colors from the sports teams data.
  List<Color>? _getTeamColors(String teamName) {
    // Search through all teams in the database
    for (final team in SportsTeamsDatabase.allTeams) {
      if (team.name == teamName ||
          team.displayName == teamName ||
          team.name.contains(teamName) ||
          teamName.contains(team.name)) {
        return team.colors;
      }
    }

    return null;
  }

  /// Create a unique key for a day.
  int _dayKey(DateTime date) {
    return date.year * 10000 + date.month * 100 + date.day;
  }
}

/// Provider for the calendar event service.
final calendarEventServiceProvider = Provider<CalendarEventService>(
  (ref) => CalendarEventService(ref),
);
