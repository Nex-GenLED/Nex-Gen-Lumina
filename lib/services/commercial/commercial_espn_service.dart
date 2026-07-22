import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/sports_alerts/models/game_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';
import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';

/// Extends the existing ESPN integration with commercial-specific methods
/// for multi-team game lookups, sorted by priority rank.
class CommercialEspnService {
  final EspnApiService _espnApi;
  final GameScheduleService _scheduleService;

  CommercialEspnService({
    EspnApiService? espnApi,
    GameScheduleService? scheduleService,
  })  : _espnApi = espnApi ?? EspnApiService(),
        _scheduleService = scheduleService ?? GameScheduleService();

  /// Returns all games for [teams] occurring in the next 7 days, across all
  /// sports. Results are sorted by date, then by priority rank.
  Future<List<GameEvent>> getUpcomingGamesForTeams(
    List<CommercialTeamProfile> teams,
  ) async {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 7));
    final results = <_RankedGameEvent>[];

    // Group teams by sport to minimise API calls.
    final bySport = <SportType, List<CommercialTeamProfile>>{};
    for (final team in teams) {
      final sport = _parseSport(team.sport);
      if (sport == null) continue;
      bySport.putIfAbsent(sport, () => []).add(team);
    }

    for (final entry in bySport.entries) {
      final sport = entry.key;
      for (final team in entry.value) {
        try {
          final schedule =
              await _scheduleService.fetchSeasonSchedule(
            espnTeamId: team.teamId,
            sport: sport,
            season: now.year,
          );
          for (final game in schedule) {
            if (game.scheduledDate.isAfter(now) &&
                game.scheduledDate.isBefore(horizon)) {
              results.add(_RankedGameEvent(game, team.priorityRank));
            }
          }
        } catch (e) {
          debugPrint(
            'CommercialEspnService: fetchSchedule error for '
            '${team.teamName}: $e',
          );
        }
      }
    }

    // Sort by date first, then by priority rank for same-day games.
    results.sort((a, b) {
      final cmp = a.game.scheduledDate.compareTo(b.game.scheduledDate);
      if (cmp != 0) return cmp;
      return a.rank.compareTo(b.rank);
    });

    return results.map((r) => r.game).toList();
  }

  /// Whether a game is currently in progress for [team].
  Future<bool> isGameActiveNow(CommercialTeamProfile team) async {
    final sport = _parseSport(team.sport);
    if (sport == null) return false;

    try {
      final game =
          await _espnApi.fetchTeamGame(sport, team.teamId);
      if (game == null) return false;
      return game.status == GameStatus.inProgress ||
          game.status == GameStatus.halftime;
    } catch (e) {
      debugPrint(
        'CommercialEspnService: isGameActiveNow error for '
        '${team.teamName}: $e',
      );
      return false;
    }
  }

  /// Returns today's games for [teams], sorted by priority rank (lowest
  /// rank number first = highest priority).
  Future<List<GameEvent>> getTodaysGames(
    List<CommercialTeamProfile> teams,
  ) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final results = <_RankedGameEvent>[];

    final bySport = <SportType, List<CommercialTeamProfile>>{};
    for (final team in teams) {
      final sport = _parseSport(team.sport);
      if (sport == null) continue;
      bySport.putIfAbsent(sport, () => []).add(team);
    }

    for (final entry in bySport.entries) {
      final sport = entry.key;
      // Fetch today's scoreboard once per sport.
      try {
        final liveGames = await _espnApi.fetchLiveGames(sport);
        for (final team in entry.value) {
          for (final live in liveGames) {
            if (live.homeTeamId == team.teamId ||
                live.awayTeamId == team.teamId) {
              results.add(_RankedGameEvent(
                GameEvent(
                  gameId: live.gameId,
                  homeTeam: live.homeTeam,
                  awayTeam: live.awayTeam,
                  homeTeamId: live.homeTeamId,
                  awayTeamId: live.awayTeamId,
                  scheduledDate: live.lastUpdated,
                  isHome: live.homeTeamId == team.teamId,
                  sport: sport,
                  season: now.year,
                  status: live.status,
                ),
                team.priorityRank,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint(
          'CommercialEspnService: getTodaysGames error for '
          '${sport.displayName}: $e',
        );
      }
    }

    // Also check upcoming schedule for games later today not yet on scoreboard.
    for (final entry in bySport.entries) {
      final sport = entry.key;
      for (final team in entry.value) {
        // Skip if already found via live scoreboard.
        if (results.any((r) =>
            r.game.homeTeamId == team.teamId ||
            r.game.awayTeamId == team.teamId)) {
          continue;
        }
        try {
          final nextDate = await _scheduleService.fetchNextGameDate(
            team.teamId,
            sport,
          );
          if (nextDate != null &&
              nextDate.isAfter(todayStart) &&
              nextDate.isBefore(todayEnd)) {
            results.add(_RankedGameEvent(
              GameEvent(
                gameId: '${team.teamId}_${nextDate.millisecondsSinceEpoch}',
                homeTeam: team.teamName,
                awayTeam: 'TBD',
                homeTeamId: team.teamId,
                scheduledDate: nextDate,
                sport: sport,
                season: now.year,
              ),
              team.priorityRank,
            ));
          }
        } catch (e) {
          // Non-critical — skip silently.
        }
      }
    }

    results.sort((a, b) => a.rank.compareTo(b.rank));
    return results.map((r) => r.game).toList();
  }

  /// Parse sport string to [SportType], matching the format used in
  /// [CommercialTeamProfile.sport].
  static SportType? _parseSport(String sport) {
    try {
      return SportType.fromJson(sport);
    } catch (_) {
      return null;
    }
  }
}

/// Internal helper to carry priority rank alongside a [GameEvent].
class _RankedGameEvent {
  final GameEvent game;
  final int rank;
  const _RankedGameEvent(this.game, this.rank);
}
