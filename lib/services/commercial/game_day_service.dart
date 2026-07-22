import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/sports_alerts/models/game_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';
import 'package:nexgen_command/models/commercial/commercial_teams_config.dart';
import 'package:nexgen_command/services/commercial/commercial_espn_service.dart';

/// Manages game-day lighting automation for commercial locations.
///
/// Responsibilities:
/// - Checks for today's games on app foreground resume and via periodic polling.
/// - When a priority-rank-1 team game is within the lead-time window, signals
///   that the CommercialSchedule should shift to the Game Day day-part.
/// - When the game ends, signals revert to the standard day-part.
/// - Fires scoring alerts through the existing [AlertTriggerService], applying
///   commercial [CommercialTeamProfile] intensity and channel scope settings.
/// - Respects [CommercialTeamsConfig.useBrandColorsForAlerts] to substitute
///   business brand colors when the flag is set.
class GameDayService {
  final CommercialEspnService _espnService;

  GameDayService({CommercialEspnService? espnService})
      : _espnService = espnService ?? CommercialEspnService();

  // ── State ──────────────────────────────────────────────────────────────

  Timer? _pollTimer;

  /// The game currently driving Game Day mode, if any.
  GameEvent? _activeGame;

  /// The team profile driving the active game.
  CommercialTeamProfile? _activeTeam;

  /// Callback invoked when Game Day mode should activate.
  /// The caller (e.g. a Riverpod notifier) provides the handler.
  void Function(CommercialTeamProfile team, GameEvent game)? onGameDayStart;

  /// Callback invoked when Game Day mode should deactivate.
  void Function()? onGameDayEnd;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Whether Game Day mode is currently active.
  bool get isGameDayActive => _activeGame != null;

  /// The active game event, if any.
  GameEvent? get activeGame => _activeGame;

  /// Start periodic polling (foreground). Uses an adaptive interval:
  /// 5 minutes when no game is active, 60 seconds during a game.
  void startPolling(CommercialTeamsConfig config) {
    _pollTimer?.cancel();
    _poll(config);
  }

  /// Stop periodic polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Call this on app foreground resume to immediately check for games.
  Future<void> checkOnResume(CommercialTeamsConfig config) async {
    await _evaluate(config);
  }

  /// Dispose resources.
  void dispose() {
    stopPolling();
    _activeGame = null;
    _activeTeam = null;
  }

  // ── Polling loop ───────────────────────────────────────────────────────

  void _poll(CommercialTeamsConfig config) {
    _pollTimer?.cancel();
    _evaluate(config).then((_) {
      final interval = _activeGame != null
          ? const Duration(seconds: 60)
          : const Duration(minutes: 5);
      _pollTimer = Timer(interval, () => _poll(config));
    });
  }

  Future<void> _evaluate(CommercialTeamsConfig config) async {
    if (config.teams.isEmpty) return;

    final todaysGames = await _espnService.getTodaysGames(config.teams);

    // Find the highest-priority team with a game today.
    GameEvent? candidateGame;
    CommercialTeamProfile? candidateTeam;

    for (final game in todaysGames) {
      final team = _matchTeam(config, game);
      if (team == null) continue;
      if (!team.gameDayAutoModeEnabled) continue;

      // Only auto-activate for the primary (rank 1) team.
      if (team.priorityRank != 1) continue;

      candidateGame = game;
      candidateTeam = team;
      break; // todaysGames is sorted by rank — first match wins
    }

    // ── Check if we should activate ──────────────────────────────────────
    if (candidateGame != null && candidateTeam != null) {
      final now = DateTime.now();
      final leadTime = Duration(minutes: candidateTeam.gameDayLeadTimeMinutes);
      final activateAt = candidateGame.scheduledDate.subtract(leadTime);

      if (now.isAfter(activateAt) && !candidateGame.isCompleted) {
        if (_activeGame?.gameId != candidateGame.gameId) {
          _activeGame = candidateGame;
          _activeTeam = candidateTeam;
          debugPrint(
            'GameDayService: activating Game Day for '
            '${candidateTeam.teamName} — ${candidateGame.homeTeam} vs '
            '${candidateGame.awayTeam}',
          );
          onGameDayStart?.call(candidateTeam, candidateGame);
        }
        return;
      }
    }

    // ── Check if active game has ended ───────────────────────────────────
    if (_activeGame != null && _activeTeam != null) {
      final stillActive =
          await _espnService.isGameActiveNow(_activeTeam!);
      if (!stillActive) {
        debugPrint(
          'GameDayService: game ended for ${_activeTeam!.teamName}, '
          'reverting to standard schedule',
        );
        _activeGame = null;
        _activeTeam = null;
        onGameDayEnd?.call();
      }
    }
  }

  // ── Scoring alert bridge ───────────────────────────────────────────────

  /// Called by the scoring monitor when a [ScoreAlertEvent] fires.
  /// Applies commercial channel scope and intensity from [config].
  ///
  /// If [useBrandColors] is true, the caller should substitute
  /// [brandPrimaryHex]/[brandSecondaryHex] into the alert trigger.
  void handleScoringAlert(
    ScoreAlertEvent event,
    CommercialTeamsConfig config,
    AlertTriggerService triggerService, {
    String? brandPrimaryHex,
    String? brandSecondaryHex,
  }) {
    // Match the scoring event to a commercial team profile.
    final team = config.teams.cast<CommercialTeamProfile?>().firstWhere(
          (t) => t != null && _slugMatches(t, event.teamSlug),
          orElse: () => null,
        );
    if (team == null) return;

    // Map commercial intensity to existing AlertSensitivity.
    final sensitivity = _mapIntensity(team.alertIntensity);

    // Build a ScoreAlertConfig that carries the channel scope.
    final alertConfig = ScoreAlertConfig(
      id: 'commercial_${team.teamId}',
      teamSlug: event.teamSlug,
      sport: event.sport,
      isEnabled: true,
      assignedZoneIds: _resolveZoneIds(team),
      sensitivity: sensitivity,
    );

    triggerService.handleAlertEvent(event, alertConfig);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Match a [GameEvent] back to its [CommercialTeamProfile].
  CommercialTeamProfile? _matchTeam(
    CommercialTeamsConfig config,
    GameEvent game,
  ) {
    for (final team in config.teams) {
      if (team.teamId == game.homeTeamId ||
          team.teamId == game.awayTeamId) {
        return team;
      }
    }
    return null;
  }

  /// Check if a team profile matches a team slug (e.g. "nfl_chiefs").
  bool _slugMatches(CommercialTeamProfile team, String slug) {
    // Slug format is "sport_teamname" — compare team ID or derive.
    // Since the existing system uses slugs and we use ESPN IDs, we check
    // if the slug contains the sport and the team name fragments.
    final lower = slug.toLowerCase();
    final sportLower = team.sport.toLowerCase();
    final nameLower = team.teamName.toLowerCase();
    if (!lower.startsWith(sportLower)) return false;
    // Check if any significant word from team name appears in slug.
    final words = nameLower.split(' ');
    for (final word in words) {
      if (word.length > 3 && lower.contains(word)) return true;
    }
    return false;
  }

  /// Map [AlertIntensity] to existing [AlertSensitivity].
  AlertSensitivity _mapIntensity(AlertIntensity intensity) {
    switch (intensity) {
      case AlertIntensity.full:
        return AlertSensitivity.allEvents;
      case AlertIntensity.moderate:
        return AlertSensitivity.majorOnly;
      case AlertIntensity.subtle:
        return AlertSensitivity.clutchOnly;
    }
  }

  /// Resolve zone IDs based on channel scope.
  List<String> _resolveZoneIds(CommercialTeamProfile team) {
    switch (team.alertChannelScope) {
      case AlertChannelScope.selectedChannels:
        return team.selectedChannelIds;
      case AlertChannelScope.indoorOnly:
        // Caller should filter to indoor channels at the trigger level.
        // Return empty to signal "use indoor filter".
        return const [];
      case AlertChannelScope.allChannels:
        return const [];
    }
  }
}
