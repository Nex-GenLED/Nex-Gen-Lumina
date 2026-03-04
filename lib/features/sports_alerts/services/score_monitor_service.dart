import 'dart:async';

import '../data/team_colors.dart';
import '../models/game_state.dart';
import '../models/score_alert_config.dart';
import '../models/score_alert_event.dart';
import '../models/sport_type.dart';
import 'espn_api_service.dart';

/// Core diff engine that detects scoring events by comparing consecutive
/// ESPN polling snapshots.
///
/// Maintains an internal cache of last-known [GameState] per game and emits
/// [ScoreAlertEvent]s on [alertStream] when a user's team scores.
class ScoreMonitorService {
  ScoreMonitorService({EspnApiService? espnApi})
      : _espnApi = espnApi ?? EspnApiService();

  final EspnApiService _espnApi;

  /// Last-known game state keyed by ESPN gameId.
  final Map<String, GameState> _gameStateCache = {};

  /// De-duplication keys: "gameId|homeScore|awayScore|eventType".
  final Set<String> _emittedKeys = {};

  final StreamController<ScoreAlertEvent> _alertController =
      StreamController<ScoreAlertEvent>.broadcast();

  /// Stream of detected scoring events for downstream consumers
  /// (LED effect service, notification service, etc.).
  Stream<ScoreAlertEvent> get alertStream => _alertController.stream;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Run a single polling cycle for all [activeConfigs].
  ///
  /// Groups configs by sport to minimise ESPN API calls (one scoreboard
  /// fetch per sport), then diffs each relevant game against its cached state.
  Future<void> checkScores(List<ScoreAlertConfig> activeConfigs) async {
    if (activeConfigs.isEmpty) return;

    // Group configs by sport so we fetch each scoreboard only once.
    final bySport = <SportType, List<ScoreAlertConfig>>{};
    for (final cfg in activeConfigs) {
      if (!cfg.isEnabled) continue;
      bySport.putIfAbsent(cfg.sport, () => []).add(cfg);
    }

    for (final entry in bySport.entries) {
      await _pollSport(entry.key, entry.value);
    }
  }

  /// Clear all cached state. Useful on logout or config reset.
  void reset() {
    _gameStateCache.clear();
    _emittedKeys.clear();
  }

  /// Release resources.
  void dispose() {
    _alertController.close();
    _espnApi.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _pollSport(
    SportType sport,
    List<ScoreAlertConfig> configs,
  ) async {
    final games = await _espnApi.fetchLiveGames(sport);

    for (final config in configs) {
      final teamInfo = kTeamColors[config.teamSlug];
      if (teamInfo == null) continue;

      // Find this team's game in today's scoreboard.
      final game = _findTeamGame(games, teamInfo.espnTeamId);
      if (game == null) continue;

      // Skip games that haven't started.
      if (game.status == GameStatus.scheduled) continue;

      final isUserHome = game.homeTeamId == teamInfo.espnTeamId;
      final previous = _gameStateCache[game.gameId];

      if (previous != null) {
        final events = _diffGameState(previous, game, config, isUserHome);
        for (final event in events) {
          final dedupKey = _dedupKey(event, game);
          if (_emittedKeys.contains(dedupKey)) continue;
          _emittedKeys.add(dedupKey);
          _alertController.add(event);
        }
      }

      // Update cache.
      _gameStateCache[game.gameId] = game;

      // Clean up finished games.
      if (game.status == GameStatus.final_) {
        _gameStateCache.remove(game.gameId);
        _emittedKeys.removeWhere((k) => k.startsWith('${game.gameId}|'));
      }
    }
  }

  /// Find the game in [games] that involves the team with [espnTeamId].
  GameState? _findTeamGame(List<GameState> games, String espnTeamId) {
    for (final g in games) {
      if (g.homeTeamId == espnTeamId || g.awayTeamId == espnTeamId) {
        return g;
      }
    }
    return null;
  }

  /// Compare [previous] and [current] game states to produce scoring events.
  ///
  /// [isUserTeamHome] indicates whether the subscribed team is the home side.
  List<ScoreAlertEvent> _diffGameState(
    GameState previous,
    GameState current,
    ScoreAlertConfig config,
    bool isUserTeamHome,
  ) {
    final events = <ScoreAlertEvent>[];
    final now = DateTime.now();

    final userScorePrev =
        isUserTeamHome ? previous.homeScore : previous.awayScore;
    final userScoreCurr =
        isUserTeamHome ? current.homeScore : current.awayScore;
    final delta = userScoreCurr - userScorePrev;

    // --- Period transition: quarter/period end while winning ----------------
    final prevPeriod = int.tryParse(previous.period ?? '');
    final currPeriod = int.tryParse(current.period ?? '');
    if (prevPeriod != null &&
        currPeriod != null &&
        currPeriod > prevPeriod) {
      final opponentScore =
          isUserTeamHome ? current.awayScore : current.homeScore;
      if (userScoreCurr > opponentScore) {
        events.add(ScoreAlertEvent(
          teamSlug: config.teamSlug,
          sport: config.sport,
          eventType: AlertEventType.quarterEndWinning,
          pointsScored: 0,
          gameId: current.gameId,
          timestamp: now,
        ));
      }
    }

    // No score change — nothing else to emit.
    if (delta <= 0) return events;

    // --- Sport-specific scoring detection -----------------------------------
    switch (config.sport) {
      case SportType.nfl:
        events.addAll(_diffNfl(delta, config, current, now));

      case SportType.nba:
        events.addAll(
          _diffNba(delta, config, current, now, previous),
        );

      case SportType.mlb:
        events.add(ScoreAlertEvent(
          teamSlug: config.teamSlug,
          sport: config.sport,
          eventType: AlertEventType.run,
          pointsScored: delta,
          gameId: current.gameId,
          timestamp: now,
        ));

      case SportType.nhl:
      case SportType.mls:
        // Goals come in +1 increments; emit one event per goal.
        for (var i = 0; i < delta; i++) {
          events.add(ScoreAlertEvent(
            teamSlug: config.teamSlug,
            sport: config.sport,
            eventType: AlertEventType.goal,
            pointsScored: 1,
            gameId: current.gameId,
            timestamp: now,
          ));
        }
    }

    return _filterBySensitivity(events, config.sensitivity, current);
  }

  // ---------------------------------------------------------------------------
  // Sport-specific diff helpers
  // ---------------------------------------------------------------------------

  List<ScoreAlertEvent> _diffNfl(
    int delta,
    ScoreAlertConfig config,
    GameState current,
    DateTime now,
  ) {
    final AlertEventType type;
    switch (delta) {
      case 3:
        type = AlertEventType.fieldGoal;
      case 2:
        type = AlertEventType.safety;
      case 6:
      case 8: // TD + 2-pt conversion
      case 7: // TD + extra point (rare single-poll jump)
        type = AlertEventType.touchdown;
      default:
        // Any other positive delta — default to touchdown.
        type = AlertEventType.touchdown;
    }

    return [
      ScoreAlertEvent(
        teamSlug: config.teamSlug,
        sport: config.sport,
        eventType: type,
        pointsScored: delta,
        gameId: current.gameId,
        timestamp: now,
      ),
    ];
  }

  List<ScoreAlertEvent> _diffNba(
    int delta,
    ScoreAlertConfig config,
    GameState current,
    DateTime now,
    GameState previous,
  ) {
    // NBA normal mode: skip scoring events (too frequent).
    // Only emit during clutch time.
    if (!current.isClutchTime) return const [];

    return [
      ScoreAlertEvent(
        teamSlug: config.teamSlug,
        sport: config.sport,
        eventType: AlertEventType.clutchBasket,
        pointsScored: delta,
        gameId: current.gameId,
        timestamp: now,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Sensitivity filter
  // ---------------------------------------------------------------------------

  /// Filter events based on user's [AlertSensitivity] preference.
  List<ScoreAlertEvent> _filterBySensitivity(
    List<ScoreAlertEvent> events,
    AlertSensitivity sensitivity,
    GameState current,
  ) {
    if (sensitivity == AlertSensitivity.allEvents) return events;

    return events.where((e) {
      switch (sensitivity) {
        case AlertSensitivity.majorOnly:
          // Major events: touchdowns, goals, runs (not field goals / safeties
          // in non-clutch contexts, but we keep them as they're still notable).
          return e.eventType == AlertEventType.touchdown ||
              e.eventType == AlertEventType.goal ||
              e.eventType == AlertEventType.run ||
              e.eventType == AlertEventType.clutchBasket ||
              e.eventType == AlertEventType.quarterEndWinning;

        case AlertSensitivity.clutchOnly:
          // Only emit if the game is in a clutch situation.
          return current.isClutchTime ||
              e.eventType == AlertEventType.quarterEndWinning;

        case AlertSensitivity.allEvents:
          return true; // Already handled above.
      }
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Dedup
  // ---------------------------------------------------------------------------

  static String _dedupKey(ScoreAlertEvent event, GameState game) =>
      '${event.gameId}|${game.homeScore}|${game.awayScore}|${event.eventType.name}';
}
