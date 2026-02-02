import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/data/sports_teams.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a major sporting event (Super Bowl, World Series, etc.)
class BigEvent {
  /// Unique identifier for the event
  final String id;

  /// Display name for the event (e.g., "Super Bowl LIX", "World Series")
  final String name;

  /// Short display name for folder (e.g., "Big Game", "Championship")
  final String folderName;

  /// The two teams competing
  final SportsTeam team1;
  final SportsTeam team2;

  /// Event date and time
  final DateTime eventTime;

  /// League this event belongs to
  final String league;

  /// Estimated national audience (in millions) - used for prioritization
  final double estimatedAudience;

  /// Event type for categorization
  final BigEventType eventType;

  const BigEvent({
    required this.id,
    required this.name,
    required this.folderName,
    required this.team1,
    required this.team2,
    required this.eventTime,
    required this.league,
    required this.estimatedAudience,
    required this.eventType,
  });

  /// Check if this event is happening within the next 7 days
  bool get isUpcoming {
    final now = DateTime.now();
    final daysUntil = eventTime.difference(now).inDays;
    return daysUntil >= 0 && daysUntil <= 7;
  }

  /// Days until the event (negative if past)
  int get daysUntil => eventTime.difference(DateTime.now()).inDays;

  /// Combined team colors for merged designs
  List<Color> get combinedColors => [...team1.colors, ...team2.colors];

  @override
  String toString() => 'BigEvent($name: ${team1.displayName} vs ${team2.displayName})';
}

/// Types of big sporting events
enum BigEventType {
  superBowl,
  worldSeries,
  nbaFinals,
  stanleyCup,
  mlsCup,
  cfpChampionship,
  marchMadnessFinal,
  allStarGame,
  championship, // Generic championship
}

/// Service for managing major sporting events.
///
/// Features:
/// - Tracks upcoming major sporting events
/// - Auto-refreshes on Sunday at 9pm
/// - Prioritizes events by expected audience size
/// - Limited to 2 events at a time
class BigEventService {
  // ignore: unused_field - reserved for future API integration
  final Ref _ref;

  /// Maximum number of events to track
  static const int maxEvents = 2;

  /// Key for storing last refresh time
  static const String _lastRefreshKey = 'big_event_last_refresh';

  BigEventService(this._ref);

  /// Get the current list of upcoming major events.
  /// Returns up to [maxEvents] events, sorted by audience size (largest first).
  Future<List<BigEvent>> getUpcomingEvents() async {
    final allEvents = await _fetchCurrentEvents();

    // Filter to only upcoming events (within next 7 days)
    final upcoming = allEvents.where((e) => e.isUpcoming).toList();

    // Sort by estimated audience (highest first)
    upcoming.sort((a, b) => b.estimatedAudience.compareTo(a.estimatedAudience));

    // Return top events up to max
    return upcoming.take(maxEvents).toList();
  }

  /// Check if a refresh is needed (Sunday 9pm logic).
  /// Returns true if:
  /// - It's Sunday and after 9pm local time
  /// - AND we haven't refreshed since this Sunday's 9pm
  Future<bool> needsRefresh() async {
    final now = DateTime.now();

    // Calculate this Sunday's 9pm
    final daysSinceSunday = now.weekday % 7; // Sunday = 0
    final thisSunday9pm = DateTime(
      now.year,
      now.month,
      now.day - daysSinceSunday,
      21, // 9pm
      0,
    );

    // If we haven't passed this Sunday's 9pm yet, check last Sunday's
    final targetRefreshTime = now.isAfter(thisSunday9pm)
        ? thisSunday9pm
        : thisSunday9pm.subtract(const Duration(days: 7));

    // Get last refresh time from storage
    final prefs = await SharedPreferences.getInstance();
    final lastRefreshMs = prefs.getInt(_lastRefreshKey) ?? 0;
    final lastRefresh = DateTime.fromMillisecondsSinceEpoch(lastRefreshMs);

    return lastRefresh.isBefore(targetRefreshTime);
  }

  /// Mark that we've refreshed the events
  Future<void> markRefreshed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastRefreshKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Fetch current major events.
  ///
  /// In production, this would call a sports API. For now, we use
  /// a curated list based on the sports calendar.
  Future<List<BigEvent>> _fetchCurrentEvents() async {
    final events = <BigEvent>[];
    final now = DateTime.now();

    // Determine what events are relevant based on the current date
    events.addAll(_getSeasonalEvents(now));

    return events;
  }

  /// Get events based on the sports calendar.
  ///
  /// This uses the current date to determine which major events
  /// might be happening and creates placeholder matchups.
  /// In production, these would be fetched from an API.
  List<BigEvent> _getSeasonalEvents(DateTime now) {
    final events = <BigEvent>[];
    final month = now.month;
    final day = now.day;

    // Super Bowl (typically first Sunday of February)
    if (month == 2 && day <= 14) {
      // Get teams - in production this would come from an API
      // For now, use placeholder teams that can be configured
      final superBowlTeams = _getSuperBowlTeams(now.year);
      if (superBowlTeams != null) {
        events.add(BigEvent(
          id: 'superbowl_${now.year}',
          name: 'Super Bowl ${_toRoman(now.year - 1966 + 1)}',
          folderName: 'Big Game Designs',
          team1: superBowlTeams.$1,
          team2: superBowlTeams.$2,
          eventTime: _getFirstSundayOfFebruary(now.year),
          league: 'NFL',
          estimatedAudience: 115.0, // ~115 million viewers
          eventType: BigEventType.superBowl,
        ));
      }
    }

    // NBA Finals (June)
    if (month == 6) {
      final nbaFinalTeams = _getNbaFinalsTeams(now.year);
      if (nbaFinalTeams != null) {
        events.add(BigEvent(
          id: 'nba_finals_${now.year}',
          name: 'NBA Finals ${now.year}',
          folderName: 'NBA Finals',
          team1: nbaFinalTeams.$1,
          team2: nbaFinalTeams.$2,
          eventTime: DateTime(now.year, 6, 10), // Approximate
          league: 'NBA',
          estimatedAudience: 12.0, // ~12 million viewers
          eventType: BigEventType.nbaFinals,
        ));
      }
    }

    // World Series (October/November)
    if (month == 10 || (month == 11 && day <= 7)) {
      final worldSeriesTeams = _getWorldSeriesTeams(now.year);
      if (worldSeriesTeams != null) {
        events.add(BigEvent(
          id: 'world_series_${now.year}',
          name: 'World Series ${now.year}',
          folderName: 'World Series',
          team1: worldSeriesTeams.$1,
          team2: worldSeriesTeams.$2,
          eventTime: DateTime(now.year, 10, 28), // Approximate
          league: 'MLB',
          estimatedAudience: 11.0, // ~11 million viewers
          eventType: BigEventType.worldSeries,
        ));
      }
    }

    // Stanley Cup Finals (June)
    if (month == 6) {
      final stanleyCupTeams = _getStanleyCupTeams(now.year);
      if (stanleyCupTeams != null) {
        events.add(BigEvent(
          id: 'stanley_cup_${now.year}',
          name: 'Stanley Cup Finals ${now.year}',
          folderName: 'Stanley Cup',
          team1: stanleyCupTeams.$1,
          team2: stanleyCupTeams.$2,
          eventTime: DateTime(now.year, 6, 15), // Approximate
          league: 'NHL',
          estimatedAudience: 5.0, // ~5 million viewers
          eventType: BigEventType.stanleyCup,
        ));
      }
    }

    // College Football Playoff Championship (January)
    if (month == 1 && day <= 15) {
      final cfpTeams = _getCfpChampionshipTeams(now.year);
      if (cfpTeams != null) {
        events.add(BigEvent(
          id: 'cfp_championship_${now.year}',
          name: 'CFP National Championship',
          folderName: 'Championship Game',
          team1: cfpTeams.$1,
          team2: cfpTeams.$2,
          eventTime: DateTime(now.year, 1, 13), // Approximate
          league: 'NCAA',
          estimatedAudience: 25.0, // ~25 million viewers
          eventType: BigEventType.cfpChampionship,
        ));
      }
    }

    // March Madness Final (April)
    if (month == 4 && day <= 10) {
      final finalFourTeams = _getMarchMadnessFinalsTeams(now.year);
      if (finalFourTeams != null) {
        events.add(BigEvent(
          id: 'march_madness_final_${now.year}',
          name: 'NCAA Championship Game',
          folderName: 'March Madness Final',
          team1: finalFourTeams.$1,
          team2: finalFourTeams.$2,
          eventTime: DateTime(now.year, 4, 7), // Approximate
          league: 'NCAA',
          estimatedAudience: 18.0, // ~18 million viewers
          eventType: BigEventType.marchMadnessFinal,
        ));
      }
    }

    return events;
  }

  /// Get Super Bowl teams for a given year.
  ///
  /// This would normally be fetched from an API.
  /// For demonstration, using configurable placeholder teams.
  (SportsTeam, SportsTeam)? _getSuperBowlTeams(int year) {
    // In production, fetch from sports API
    // For now, return placeholder teams based on year
    // These can be updated by the app as the playoffs progress

    // Example: 2025 Super Bowl (played Feb 2025 for 2024 season)
    // Using Seahawks vs Patriots as the example from the user's request
    final team1 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Seahawks' && t.league == 'NFL',
      orElse: () => SportsTeamsDatabase.allTeams.first,
    );
    final team2 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Patriots' && t.league == 'NFL',
      orElse: () => SportsTeamsDatabase.allTeams[1],
    );

    return (team1, team2);
  }

  (SportsTeam, SportsTeam)? _getNbaFinalsTeams(int year) {
    final team1 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Celtics' && t.league == 'NBA',
      orElse: () => SportsTeamsDatabase.allTeams.firstWhere((t) => t.league == 'NBA'),
    );
    final team2 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Lakers' && t.league == 'NBA',
      orElse: () => SportsTeamsDatabase.allTeams.where((t) => t.league == 'NBA').skip(1).first,
    );
    return (team1, team2);
  }

  (SportsTeam, SportsTeam)? _getWorldSeriesTeams(int year) {
    final team1 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Dodgers' && t.league == 'MLB',
      orElse: () => SportsTeamsDatabase.allTeams.firstWhere((t) => t.league == 'MLB'),
    );
    final team2 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Yankees' && t.league == 'MLB',
      orElse: () => SportsTeamsDatabase.allTeams.where((t) => t.league == 'MLB').skip(1).first,
    );
    return (team1, team2);
  }

  (SportsTeam, SportsTeam)? _getStanleyCupTeams(int year) {
    final team1 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Panthers' && t.league == 'NHL',
      orElse: () => SportsTeamsDatabase.allTeams.firstWhere((t) => t.league == 'NHL'),
    );
    final team2 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Oilers' && t.league == 'NHL',
      orElse: () => SportsTeamsDatabase.allTeams.where((t) => t.league == 'NHL').skip(1).first,
    );
    return (team1, team2);
  }

  (SportsTeam, SportsTeam)? _getCfpChampionshipTeams(int year) {
    final team1 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Buckeyes' && t.league == 'NCAA',
      orElse: () => SportsTeamsDatabase.allTeams.firstWhere((t) => t.league == 'NCAA'),
    );
    final team2 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Fighting Irish' && t.league == 'NCAA',
      orElse: () => SportsTeamsDatabase.allTeams.where((t) => t.league == 'NCAA').skip(1).first,
    );
    return (team1, team2);
  }

  (SportsTeam, SportsTeam)? _getMarchMadnessFinalsTeams(int year) {
    final team1 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Jayhawks' && t.league == 'NCAA',
      orElse: () => SportsTeamsDatabase.allTeams.firstWhere((t) => t.league == 'NCAA'),
    );
    final team2 = SportsTeamsDatabase.allTeams.firstWhere(
      (t) => t.name == 'Wildcats' && t.league == 'NCAA',
      orElse: () => SportsTeamsDatabase.allTeams.where((t) => t.league == 'NCAA').skip(1).first,
    );
    return (team1, team2);
  }

  /// Get the first Sunday of February for a given year.
  DateTime _getFirstSundayOfFebruary(int year) {
    var date = DateTime(year, 2, 1);
    while (date.weekday != DateTime.sunday) {
      date = date.add(const Duration(days: 1));
    }
    // Super Bowl is typically the second Sunday now
    return date.add(const Duration(days: 7));
  }

  /// Convert year to Roman numerals for Super Bowl naming.
  String _toRoman(int number) {
    const romanNumerals = [
      (1000, 'M'), (900, 'CM'), (500, 'D'), (400, 'CD'),
      (100, 'C'), (90, 'XC'), (50, 'L'), (40, 'XL'),
      (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I'),
    ];

    var result = '';
    var remaining = number;

    for (final (value, numeral) in romanNumerals) {
      while (remaining >= value) {
        result += numeral;
        remaining -= value;
      }
    }

    return result;
  }
}

/// Provider for the big event service
final bigEventServiceProvider = Provider<BigEventService>(
  (ref) => BigEventService(ref),
);

/// Provider for the current list of upcoming big events.
/// Automatically refreshes based on the Sunday 9pm schedule.
final upcomingBigEventsProvider = FutureProvider<List<BigEvent>>((ref) async {
  final service = ref.watch(bigEventServiceProvider);

  // Check if we need to refresh
  if (await service.needsRefresh()) {
    await service.markRefreshed();
  }

  return service.getUpcomingEvents();
});

/// Provider that triggers a refresh check periodically.
/// Call this on app start and when the app comes to foreground.
final bigEventRefreshCheckProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(bigEventServiceProvider);

  final needsRefresh = await service.needsRefresh();
  if (needsRefresh) {
    // Invalidate the events provider to trigger a refresh
    ref.invalidate(upcomingBigEventsProvider);
    await service.markRefreshed();
  }
});
