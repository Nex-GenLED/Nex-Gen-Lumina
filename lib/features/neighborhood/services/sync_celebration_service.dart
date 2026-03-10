import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sports_alerts/models/game_state.dart';
import '../../sports_alerts/models/score_alert_event.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../sports_alerts/services/espn_api_service.dart';
import '../models/sync_event.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';
import '../neighborhood_sync_engine.dart';
import 'autopilot_sync_trigger.dart' show syncEventServiceProvider;
import 'sync_event_service.dart';

/// Propagates live score celebrations to all participants in an active
/// Autopilot Sync session.
///
/// Monitors the ESPN API for score changes, fires celebration patterns
/// to all participants simultaneously, then returns to the base pattern.
class SyncCelebrationService {
  final Ref _ref;
  final SyncEventService _eventService;
  final EspnApiService _espnApi;

  Timer? _pollingTimer;
  Timer? _celebrationTimer;
  GameState? _lastKnownState;
  bool _isCelebrating = false;
  String? _activeGroupId;
  String? _activeSessionId;

  SyncCelebrationService(this._ref, this._eventService, this._espnApi);

  bool get isCelebrating => _isCelebrating;

  /// Start monitoring a game for score changes during an active session.
  void startMonitoring({
    required String groupId,
    required String sessionId,
    required SyncEvent event,
    required String gameId,
  }) {
    _activeGroupId = groupId;
    _activeSessionId = sessionId;

    final sport = _parseSportType(event.sportLeague ?? '');
    if (sport == null) return;

    debugPrint(
      '[SyncCelebrationService] Monitoring game $gameId for "${event.name}"',
    );

    // Poll at appropriate interval for this sport
    final intervalSeconds = sport.pollingIntervalSeconds;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _pollGameState(sport, gameId, event),
    );

    // Also poll immediately
    _pollGameState(sport, gameId, event);
  }

  /// Stop monitoring.
  void stopMonitoring() {
    _pollingTimer?.cancel();
    _celebrationTimer?.cancel();
    _lastKnownState = null;
    _isCelebrating = false;
    _activeGroupId = null;
    _activeSessionId = null;
    debugPrint('[SyncCelebrationService] Stopped monitoring');
  }

  /// Poll ESPN for current game state and detect scoring events.
  Future<void> _pollGameState(
    SportType sport,
    String gameId,
    SyncEvent event,
  ) async {
    try {
      final currentState = await _espnApi.fetchGame(sport, gameId);
      if (currentState == null) return;

      // Check if game is over → trigger session end
      if (currentState.status == GameStatus.final_) {
        debugPrint('[SyncCelebrationService] Game is final');
        _pollingTimer?.cancel();
        // Session manager will handle dissolution via its own monitoring
        return;
      }

      // Compare scores to detect scoring events
      if (_lastKnownState != null) {
        _detectAndFireCelebrations(
          sport,
          _lastKnownState!,
          currentState,
          event,
        );
      }

      _lastKnownState = currentState;
    } catch (e) {
      debugPrint('[SyncCelebrationService] Poll error: $e');
    }
  }

  /// Compare game states and fire celebrations on score changes.
  void _detectAndFireCelebrations(
    SportType sport,
    GameState previous,
    GameState current,
    SyncEvent event,
  ) {
    final teamId = event.espnTeamId ?? '';

    // Determine if our team is home or away
    final isHome = current.homeTeamId == teamId;
    final previousScore = isHome ? previous.homeScore : previous.awayScore;
    final currentScore = isHome ? current.homeScore : current.awayScore;

    final scoreDelta = currentScore - previousScore;
    if (scoreDelta <= 0) return;

    // Score detected!
    debugPrint(
      '[SyncCelebrationService] Score! +$scoreDelta for ${event.teamId}',
    );

    final eventType = _classifyScoreEvent(sport, scoreDelta);
    _fireCelebration(event, eventType, scoreDelta);
  }

  /// Classify the type of scoring event by sport and points scored.
  AlertEventType _classifyScoreEvent(SportType sport, int points) {
    switch (sport) {
      case SportType.nfl:
      case SportType.ncaaFB:
        if (points >= 6) return AlertEventType.touchdown;
        if (points == 3) return AlertEventType.fieldGoal;
        if (points == 2) return AlertEventType.safety;
        return AlertEventType.fieldGoal;
      case SportType.nba:
      case SportType.ncaaMB:
        return AlertEventType.clutchBasket;
      case SportType.nhl:
        return AlertEventType.goal;
      case SportType.mls:
      case SportType.fifa:
      case SportType.championsLeague:
        return AlertEventType.soccerGoal;
      case SportType.mlb:
        return AlertEventType.run;
    }
  }

  /// Fire a celebration pattern to all active participants.
  Future<void> _fireCelebration(
    SyncEvent event,
    AlertEventType eventType,
    int scoreDelta,
  ) async {
    if (_activeGroupId == null || _activeSessionId == null) return;

    // If already celebrating, reset the timer (restart celebration)
    if (_isCelebrating) {
      debugPrint('[SyncCelebrationService] Resetting celebration timer');
      _celebrationTimer?.cancel();
    }

    _isCelebrating = true;

    // Mark session as celebrating
    await _eventService.setCelebrating(
      _activeGroupId!,
      _activeSessionId!,
      celebrating: true,
    );

    // Broadcast celebration pattern to all participants
    await _broadcastCelebrationPattern(event, eventType);

    // Schedule return to base pattern after celebration duration
    final duration = _celebrationDuration(event, eventType);
    _celebrationTimer = Timer(duration, () async {
      _isCelebrating = false;

      // Mark celebration ended
      await _eventService.setCelebrating(
        _activeGroupId!,
        _activeSessionId!,
        celebrating: false,
      );

      // Return to base pattern
      await _broadcastBasePattern(event);
      debugPrint('[SyncCelebrationService] Celebration ended, back to base');
    });
  }

  /// Broadcast the celebration pattern to all session participants.
  Future<void> _broadcastCelebrationPattern(
    SyncEvent event,
    AlertEventType eventType,
  ) async {
    final session = await _eventService.getActiveSession(_activeGroupId!);
    if (session == null) return;

    // Get active members, filtering out those with local overrides
    final members = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final activeMembers = members.where(
      (m) => session.activeParticipantUids.contains(m.oderId) && m.isOnline,
    );

    if (activeMembers.isEmpty) return;

    // Use the celebration pattern from the event
    final pattern = event.celebrationPattern;

    // Optionally differentiate intensity by event type
    final effectId = _celebrationEffectId(eventType, pattern.effectId);

    final allMembers = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final engine = _ref.read(neighborhoodSyncEngineProvider);

    final command = engine.createSyncCommand(
      groupId: _activeGroupId!,
      members: allMembers,
      effectId: effectId,
      colors: pattern.colors,
      speed: pattern.speed,
      intensity: pattern.intensity,
      brightness: pattern.brightness,
      timingConfig: const SyncTimingConfig(),
      syncType: SyncType.simultaneous,
      patternName: '${event.name} - Celebration!',
    );

    final notifier = _ref.read(neighborhoodNotifierProvider.notifier);
    await notifier.broadcastSync(command);

    debugPrint(
      '[SyncCelebrationService] Celebration broadcast to ${activeMembers.length} homes',
    );
  }

  /// Broadcast the base pattern (return from celebration).
  Future<void> _broadcastBasePattern(SyncEvent event) async {
    if (_activeGroupId == null) return;
    final pattern = event.basePattern;
    final allMembers = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final engine = _ref.read(neighborhoodSyncEngineProvider);

    final command = engine.createSyncCommand(
      groupId: _activeGroupId!,
      members: allMembers,
      effectId: pattern.effectId,
      colors: pattern.colors,
      speed: pattern.speed,
      intensity: pattern.intensity,
      brightness: pattern.brightness,
      timingConfig: const SyncTimingConfig(),
      syncType: SyncType.simultaneous,
      patternName: event.name,
    );

    final notifier = _ref.read(neighborhoodNotifierProvider.notifier);
    await notifier.broadcastSync(command);
  }

  /// Calculate celebration duration based on event type.
  Duration _celebrationDuration(SyncEvent event, AlertEventType eventType) {
    final baseDuration = event.celebrationDurationSeconds;

    // Optionally scale by event significance
    switch (eventType) {
      case AlertEventType.touchdown:
      case AlertEventType.goal:
      case AlertEventType.soccerGoal:
        return Duration(seconds: baseDuration);
      case AlertEventType.fieldGoal:
        return Duration(seconds: (baseDuration * 0.6).round());
      case AlertEventType.safety:
      case AlertEventType.run:
        return Duration(seconds: (baseDuration * 0.5).round());
      case AlertEventType.clutchBasket:
        return Duration(seconds: (baseDuration * 0.4).round());
      case AlertEventType.quarterEndWinning:
        return Duration(seconds: baseDuration);
      case AlertEventType.turnover:
        return Duration.zero;
    }
  }

  /// Select celebration effect ID based on event type.
  /// Falls back to the user-configured effect if not differentiated.
  int _celebrationEffectId(AlertEventType eventType, int defaultEffectId) {
    switch (eventType) {
      case AlertEventType.touchdown:
      case AlertEventType.goal:
      case AlertEventType.soccerGoal:
        return 88; // Fireworks effect — high-energy
      case AlertEventType.fieldGoal:
        return 2; // Breathe — moderate energy
      case AlertEventType.clutchBasket:
        return 11; // Rainbow — quick flash
      default:
        return defaultEffectId;
    }
  }

  SportType? _parseSportType(String league) {
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
      case 'FIFA':
      case 'FIFA WORLD CUP':
        return SportType.fifa;
      case 'CHAMPIONS LEAGUE':
      case 'UCL':
        return SportType.championsLeague;
      case 'NCAA FOOTBALL':
      case 'NCAAFB':
      case 'NCAA FB':
        return SportType.ncaaFB;
      case 'NCAA BASKETBALL':
      case 'NCAAMB':
      case 'NCAA MB':
        return SportType.ncaaMB;
      default:
        return null;
    }
  }

  void dispose() {
    stopMonitoring();
  }
}

/// Provider for the celebration service.
final syncCelebrationServiceProvider =
    Provider<SyncCelebrationService>((ref) {
  final service = ref.watch(syncEventServiceProvider);
  final espnApi = EspnApiService();
  final celebService = SyncCelebrationService(ref, service, espnApi);
  ref.onDispose(() => celebService.dispose());
  return celebService;
});
