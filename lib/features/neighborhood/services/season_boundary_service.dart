import '../../sports_alerts/models/sport_type.dart';
import '../../sports_alerts/services/game_schedule_service.dart';
import '../models/sync_event.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SEASON BOUNDARY SERVICE
// ═════════════════════════════════════════════════════════════════════════════
//
// Handles season transition logic:
//  - Detects when a season is ending (no more upcoming home games)
//  - Determines the next season year
//  - Provides renewal info for UI prompts
//  - Creates a renewed SyncEvent for the next season
// ═════════════════════════════════════════════════════════════════════════════

/// Status of a season schedule.
enum SeasonStatus {
  /// Season is ongoing with upcoming games.
  active,

  /// All games have been played; season is over.
  ended,

  /// Season is ending soon (last game within 14 days).
  endingSoon,

  /// Could not determine status (e.g., no schedule data).
  unknown,
}

/// Info about the current state of a season schedule.
class SeasonBoundaryInfo {
  final SeasonStatus status;
  final int currentSeason;
  final int? nextSeason;
  final SportType sport;
  final String teamName;
  final int remainingGames;
  final DateTime? lastGameDate;
  final DateTime? nextSeasonStart;

  const SeasonBoundaryInfo({
    required this.status,
    required this.currentSeason,
    this.nextSeason,
    required this.sport,
    required this.teamName,
    this.remainingGames = 0,
    this.lastGameDate,
    this.nextSeasonStart,
  });

  bool get needsRenewal =>
      status == SeasonStatus.ended || status == SeasonStatus.endingSoon;
}

/// Check the boundary status for a season schedule sync event.
Future<SeasonBoundaryInfo> checkSeasonBoundary({
  required SyncEvent event,
  required GameScheduleService scheduleService,
}) async {
  if (!event.isSeasonSchedule ||
      event.espnTeamId == null ||
      event.sportLeague == null ||
      event.seasonYear == null) {
    return SeasonBoundaryInfo(
      status: SeasonStatus.unknown,
      currentSeason: event.seasonYear ?? DateTime.now().year,
      sport: _parseSport(event.sportLeague),
      teamName: event.name,
    );
  }

  final sport = _parseSport(event.sportLeague);
  final games = await scheduleService.fetchSeasonSchedule(
    espnTeamId: event.espnTeamId!,
    sport: sport,
    season: event.seasonYear!,
    homeGamesOnly: true,
  );

  if (games.isEmpty) {
    return SeasonBoundaryInfo(
      status: SeasonStatus.unknown,
      currentSeason: event.seasonYear!,
      sport: sport,
      teamName: event.name,
    );
  }

  final upcomingGames = games.where((g) => g.isUpcoming).toList();
  final now = DateTime.now();

  if (upcomingGames.isEmpty) {
    // All games played — season is over
    final nextSeason = _nextSeasonYear(sport, event.seasonYear!);
    return SeasonBoundaryInfo(
      status: SeasonStatus.ended,
      currentSeason: event.seasonYear!,
      nextSeason: nextSeason,
      sport: sport,
      teamName: event.name,
      remainingGames: 0,
      lastGameDate: games.last.scheduledDate,
    );
  }

  // Check if the season is ending soon (last game within 14 days)
  final lastUpcoming = upcomingGames.last;
  final daysToLastGame = lastUpcoming.scheduledDate.difference(now).inDays;

  if (daysToLastGame <= 14 && upcomingGames.length <= 2) {
    final nextSeason = _nextSeasonYear(sport, event.seasonYear!);
    return SeasonBoundaryInfo(
      status: SeasonStatus.endingSoon,
      currentSeason: event.seasonYear!,
      nextSeason: nextSeason,
      sport: sport,
      teamName: event.name,
      remainingGames: upcomingGames.length,
      lastGameDate: lastUpcoming.scheduledDate,
    );
  }

  return SeasonBoundaryInfo(
    status: SeasonStatus.active,
    currentSeason: event.seasonYear!,
    sport: sport,
    teamName: event.name,
    remainingGames: upcomingGames.length,
    lastGameDate: lastUpcoming.scheduledDate,
  );
}

/// Create a renewed SyncEvent for the next season.
/// Copies all settings from the current event but updates the season year
/// and clears the excluded game list.
SyncEvent renewForNextSeason({
  required SyncEvent currentEvent,
  required int nextSeason,
  List<String> excludedGameIds = const [],
}) {
  return currentEvent.copyWith(
    id: '', // Will get a new ID when created
    seasonYear: nextSeason,
    excludedGameIds: excludedGameIds,
    lastScheduleReconciliation: null,
    createdAt: DateTime.now(),
    isEnabled: true,
    name: _updateSeasonInName(currentEvent.name, nextSeason),
  );
}

/// Attempt to update the season year in an event name.
/// e.g., "Chiefs Game Day 2025" → "Chiefs Game Day 2026"
String _updateSeasonInName(String name, int newSeason) {
  // Try to find and replace a 4-digit year in the name
  final yearRegex = RegExp(r'\b20\d{2}\b');
  if (yearRegex.hasMatch(name)) {
    return name.replaceFirst(yearRegex, '$newSeason');
  }
  return name;
}

/// Calculate the next season year for a sport.
int _nextSeasonYear(SportType sport, int currentSeason) {
  return currentSeason + 1;
}

SportType _parseSport(String? league) {
  if (league == null) return SportType.nfl;
  switch (league.toUpperCase()) {
    case 'NFL':
      return SportType.nfl;
    case 'NBA':
      return SportType.nba;
    case 'MLB':
      return SportType.mlb;
    case 'NHL':
      return SportType.nhl;
    case 'MLS':
      return SportType.mls;
    default:
      return SportType.nfl;
  }
}
