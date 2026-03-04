import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/game_state.dart';
import '../models/sport_type.dart';

/// ESPN public scoreboard API base URL.
const kEspnBaseUrl = 'https://site.api.espn.com/apis/site/v2/sports';

/// Service that polls ESPN's unofficial scoreboard API for live scores.
///
/// No API key is required. All methods are resilient — they return empty
/// results on failure and never throw, since this runs as a background service.
class EspnApiService {
  EspnApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Fetch all live / today's games for a [sport].
  Future<List<GameState>> fetchLiveGames(SportType sport) async {
    final url = '$kEspnBaseUrl/${sport.espnSportPath}/scoreboard';
    final json = await _fetchJson(url);
    if (json == null) return const [];

    final events = json['events'] as List<dynamic>?;
    if (events == null) return const [];

    final games = <GameState>[];
    for (final event in events) {
      final game = _parseEvent(event as Map<String, dynamic>, sport);
      if (game != null) games.add(game);
    }
    return games;
  }

  /// Fetch a specific game by ESPN [gameId].
  Future<GameState?> fetchGame(SportType sport, String gameId) async {
    final url = '$kEspnBaseUrl/${sport.espnSportPath}/scoreboard/$gameId';
    final json = await _fetchJson(url);
    if (json == null) return null;

    // Single-event endpoint may nest differently; try both shapes.
    final events = json['events'] as List<dynamic>?;
    if (events != null && events.isNotEmpty) {
      return _parseEvent(events.first as Map<String, dynamic>, sport);
    }

    // Some endpoints return the event at top level.
    if (json.containsKey('competitions')) {
      return _parseEvent(json, sport);
    }

    return null;
  }

  /// Get today's game for a specific team identified by [espnTeamId].
  ///
  /// Returns the first matching game or `null` if the team isn't playing today.
  Future<GameState?> fetchTeamGame(
    SportType sport,
    String espnTeamId,
  ) async {
    final games = await fetchLiveGames(sport);
    for (final game in games) {
      if (game.homeTeamId == espnTeamId || game.awayTeamId == espnTeamId) {
        return game;
      }
    }
    return null;
  }

  /// Release underlying HTTP client resources.
  void dispose() {
    _client.close();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _fetchJson(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[EspnApiService] HTTP ${response.statusCode} for $url');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[EspnApiService] Error fetching $url: $e');
      return null;
    }
  }

  /// Parse a single ESPN "event" object into a [GameState].
  GameState? _parseEvent(Map<String, dynamic> event, SportType sport) {
    try {
      final gameId = event['id']?.toString() ?? '';

      final competitions =
          event['competitions'] as List<dynamic>?;
      if (competitions == null || competitions.isEmpty) return null;

      final competition = competitions[0] as Map<String, dynamic>;
      final competitors =
          competition['competitors'] as List<dynamic>?;
      if (competitors == null || competitors.length < 2) return null;

      // Identify home / away.
      Map<String, dynamic>? home;
      Map<String, dynamic>? away;
      for (final c in competitors) {
        final comp = c as Map<String, dynamic>;
        if (comp['homeAway'] == 'home') {
          home = comp;
        } else {
          away = comp;
        }
      }
      if (home == null || away == null) return null;

      final homeTeam = _teamName(home);
      final awayTeam = _teamName(away);
      final homeTeamId = _teamId(home);
      final awayTeamId = _teamId(away);
      final homeScore = int.tryParse(home['score']?.toString() ?? '') ?? 0;
      final awayScore = int.tryParse(away['score']?.toString() ?? '') ?? 0;

      // Status
      final statusMap = competition['status'] as Map<String, dynamic>?;
      final statusType =
          statusMap?['type'] as Map<String, dynamic>?;
      final statusName = statusType?['name']?.toString() ?? '';
      final gameStatus = _mapStatus(statusName);

      // Period & clock
      final period = statusMap?['period']?.toString();
      final clock = statusMap?['displayClock']?.toString();

      return GameState(
        gameId: gameId,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
        homeScore: homeScore,
        awayScore: awayScore,
        status: gameStatus,
        period: period,
        clock: clock,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[EspnApiService] Error parsing event: $e');
      return null;
    }
  }

  static String _teamName(Map<String, dynamic> competitor) {
    final team = competitor['team'] as Map<String, dynamic>?;
    return team?['displayName']?.toString() ??
        team?['shortDisplayName']?.toString() ??
        team?['abbreviation']?.toString() ??
        'Unknown';
  }

  static String _teamId(Map<String, dynamic> competitor) {
    final team = competitor['team'] as Map<String, dynamic>?;
    return team?['id']?.toString() ?? '';
  }

  static GameStatus _mapStatus(String espnStatus) => switch (espnStatus) {
        'STATUS_IN_PROGRESS' => GameStatus.inProgress,
        'STATUS_HALFTIME' => GameStatus.halftime,
        'STATUS_FINAL' || 'STATUS_FINAL_OT' => GameStatus.final_,
        _ => GameStatus.scheduled,
      };
}
