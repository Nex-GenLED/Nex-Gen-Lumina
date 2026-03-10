import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sports_alerts/models/game_state.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../sports_alerts/services/espn_api_service.dart';
import '../models/sync_event.dart';
import 'sync_event_service.dart';
import 'sync_session_manager.dart';

/// Autopilot Sync Trigger Engine.
///
/// Monitors pending SyncEvents and automatically initiates sessions when
/// trigger conditions are met (scheduled time or live game start).
class AutopilotSyncTrigger {
  final Ref _ref;
  final SyncEventService _eventService;
  final EspnApiService _espnApi;

  Timer? _scheduledTimer;
  Timer? _gamePollingTimer;
  final Map<String, Timer> _eventTimers = {};
  bool _isRunning = false;

  AutopilotSyncTrigger(this._ref, this._eventService, this._espnApi);

  bool get isRunning => _isRunning;

  /// Start monitoring all enabled sync events for a group.
  Future<void> startMonitoring(String groupId) async {
    if (_isRunning) return;
    _isRunning = true;
    debugPrint('[AutopilotSyncTrigger] Starting monitoring for group $groupId');

    final events = await _eventService.getEnabledSyncEvents(groupId);
    for (final event in events) {
      _scheduleEvent(groupId, event);
    }
  }

  /// Stop all monitoring.
  void stopMonitoring() {
    _isRunning = false;
    _scheduledTimer?.cancel();
    _gamePollingTimer?.cancel();
    for (final timer in _eventTimers.values) {
      timer.cancel();
    }
    _eventTimers.clear();
    debugPrint('[AutopilotSyncTrigger] Stopped monitoring');
  }

  /// Schedule or poll for a single sync event.
  void _scheduleEvent(String groupId, SyncEvent event) {
    switch (event.triggerType) {
      case SyncEventTriggerType.scheduledTime:
        _scheduleTimedEvent(groupId, event);
        break;
      case SyncEventTriggerType.gameStart:
        _scheduleGameStartEvent(groupId, event);
        break;
      case SyncEventTriggerType.manual:
        // Manual events are not auto-triggered
        break;
    }
  }

  /// Set a timer to fire at the scheduled time.
  void _scheduleTimedEvent(String groupId, SyncEvent event) {
    if (event.scheduledTime == null) return;

    final now = DateTime.now();
    final target = _nextOccurrence(event.scheduledTime!, event.repeatDays);
    if (target == null) return;

    final delay = target.difference(now);
    if (delay.isNegative) return;

    debugPrint(
      '[AutopilotSyncTrigger] Scheduling "${event.name}" in ${delay.inMinutes}m',
    );

    _eventTimers[event.id]?.cancel();
    _eventTimers[event.id] = Timer(delay, () {
      _initiateSession(groupId, event);
    });
  }

  /// Poll the ESPN API for game start, beginning 15 minutes before scheduled time.
  void _scheduleGameStartEvent(String groupId, SyncEvent event) {
    if (event.espnTeamId == null || event.sportLeague == null) return;

    final sport = _parseSportType(event.sportLeague!);
    if (sport == null) return;

    // If we have a scheduled time, wait until 15min before to start polling
    if (event.scheduledTime != null) {
      final preGameStart =
          event.scheduledTime!.subtract(const Duration(minutes: 15));
      final now = DateTime.now();
      final delay = preGameStart.difference(now);

      if (delay.isNegative) {
        // Already past pre-game window — start polling immediately
        _startGamePolling(groupId, event, sport);
      } else {
        debugPrint(
          '[AutopilotSyncTrigger] Will start polling "${event.name}" in ${delay.inMinutes}m',
        );
        _eventTimers[event.id]?.cancel();
        _eventTimers[event.id] = Timer(delay, () {
          _startGamePolling(groupId, event, sport);
        });
      }
    } else {
      // No scheduled time — poll immediately (assumes game is today)
      _startGamePolling(groupId, event, sport);
    }
  }

  /// Actively poll ESPN for game status changes.
  void _startGamePolling(String groupId, SyncEvent event, SportType sport) {
    debugPrint(
      '[AutopilotSyncTrigger] Starting game polling for "${event.name}"',
    );

    // Cancel any existing polling timer for this event
    _eventTimers['poll_${event.id}']?.cancel();

    _eventTimers['poll_${event.id}'] =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        final game = await _espnApi.fetchTeamGame(sport, event.espnTeamId!);
        if (game == null) return;

        if (game.status == GameStatus.inProgress) {
          debugPrint(
            '[AutopilotSyncTrigger] Game started for "${event.name}"!',
          );
          timer.cancel();
          _eventTimers.remove('poll_${event.id}');
          _initiateSession(groupId, event, gameId: game.gameId);
        } else if (game.status == GameStatus.final_) {
          // Game already over — don't trigger
          debugPrint(
            '[AutopilotSyncTrigger] Game already final for "${event.name}"',
          );
          timer.cancel();
          _eventTimers.remove('poll_${event.id}');
        }
      } catch (e) {
        debugPrint('[AutopilotSyncTrigger] Poll error: $e');
        // On API failure, fall back to scheduled time if available
        if (event.scheduledTime != null) {
          final now = DateTime.now();
          if (now.isAfter(event.scheduledTime!) &&
              now.difference(event.scheduledTime!).inMinutes < 30) {
            debugPrint(
              '[AutopilotSyncTrigger] API unreachable, falling back to scheduled time',
            );
            timer.cancel();
            _eventTimers.remove('poll_${event.id}');
            _initiateSession(groupId, event);
          }
        }
      }
    });
  }

  /// Initiate a sync session — the core trigger action.
  Future<void> _initiateSession(
    String groupId,
    SyncEvent event, {
    String? gameId,
  }) async {
    debugPrint('[AutopilotSyncTrigger] Initiating session for "${event.name}"');

    try {
      final sessionManager = _ref.read(syncSessionManagerProvider);
      await sessionManager.startSession(
        groupId: groupId,
        event: event,
        gameId: gameId,
      );
    } catch (e) {
      debugPrint('[AutopilotSyncTrigger] Failed to initiate session: $e');
    }
  }

  /// Calculate next occurrence for recurring events.
  DateTime? _nextOccurrence(DateTime baseTime, List<int> repeatDays) {
    final now = DateTime.now();
    // For one-time events
    if (repeatDays.isEmpty) {
      return baseTime.isAfter(now) ? baseTime : null;
    }

    // For recurring: find next matching day
    for (int i = 0; i < 7; i++) {
      final candidate = DateTime(
        now.year,
        now.month,
        now.day + i,
        baseTime.hour,
        baseTime.minute,
      );
      // DateTime.weekday: 1=Monday..7=Sunday
      if (repeatDays.contains(candidate.weekday) &&
          candidate.isAfter(now)) {
        return candidate;
      }
    }
    return null;
  }

  /// Parse a sport league string into a SportType.
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
      default:
        return null;
    }
  }

  void dispose() {
    stopMonitoring();
  }
}

/// Provider for the trigger engine.
final autopilotSyncTriggerProvider = Provider<AutopilotSyncTrigger>((ref) {
  final service = ref.watch(syncEventServiceProvider);
  final espnApi = EspnApiService();
  final trigger = AutopilotSyncTrigger(ref, service, espnApi);
  ref.onDispose(() => trigger.dispose());
  return trigger;
});

/// Provider for the SyncEventService.
final syncEventServiceProvider = Provider<SyncEventService>((ref) {
  return SyncEventService();
});
