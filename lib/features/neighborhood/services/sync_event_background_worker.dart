import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;

import '../../sports_alerts/models/game_state.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../sports_alerts/services/espn_api_service.dart';
import '../../sports_alerts/services/game_schedule_service.dart';
import '../../wled/wled_service.dart';
import 'season_schedule_reconciliation.dart';
import 'sync_event_background_persistence.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SYNC EVENT BACKGROUND WORKER
// ═════════════════════════════════════════════════════════════════════════════
//
// Runs inside the background service isolate. No Riverpod, no Firestore
// listeners. Reads from SharedPreferences and triggers sessions via
// Cloud Function HTTP call.
//
// Lifecycle:
//   1. On each poll cycle, loads sync event configs from SharedPreferences
//   2. Checks if any events should fire within the next 30 minutes
//   3. For scheduledTime triggers: fires at the exact scheduled time
//   4. For gameStart triggers: polls ESPN API for game status changes
//   5. When a trigger fires, calls the initiateSyncSession Cloud Function
//   6. Monitors active sessions for score celebrations (game day)
//   7. Communicates session state back to the UI via service.invoke()
// ═════════════════════════════════════════════════════════════════════════════

/// The core background worker for sync event monitoring.
class SyncEventBackgroundWorker {
  final ServiceInstance _service;
  final EspnApiService _espnApi;

  Timer? _pollTimer;
  final Map<String, Timer> _eventTimers = {};
  final Map<String, GameState> _lastKnownGameStates = {};
  bool _isMonitoring = false;
  List<String> _controllerIps = [];

  SyncEventBackgroundWorker(this._service, this._espnApi);

  /// Start the sync event monitoring loop.
  /// Called from the background service's _onStart.
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    debugPrint('[SyncBgWorker] Starting sync event monitoring');
    _poll(); // Immediate first poll
  }

  /// Stop all monitoring and clean up timers.
  void stopMonitoring() {
    _isMonitoring = false;
    _pollTimer?.cancel();
    for (final timer in _eventTimers.values) {
      timer.cancel();
    }
    _eventTimers.clear();
    _lastKnownGameStates.clear();
    debugPrint('[SyncBgWorker] Stopped sync event monitoring');
  }

  /// Update controller IPs (received from UI isolate).
  void updateControllerIps(List<String> ips) {
    _controllerIps = ips;
  }

  /// Called by the sports alert pipeline when a [ScoreAlertEvent] fires.
  ///
  /// Checks if there's an active sync session whose team matches the event,
  /// and if so, fires a celebration on all sync participant controllers.
  /// This bridges the ScoreMonitorService → Neighborhood Sync pipeline.
  Future<void> onScoreAlertEvent(dynamic event) async {
    try {
      final teamSlug = event.teamSlug as String;
      final session = await loadActiveSession();
      if (session == null) return;

      // Find the config for this session and check team match
      final configs = await loadSyncEventsForBackground();
      final config =
          configs.where((c) => c.id == session.syncEventId).firstOrNull;
      if (config == null) return;

      // Match by team slug or ESPN team ID
      if (config.teamId != teamSlug) return;

      debugPrint('[SyncBgWorker] Score alert matches active session team '
          '$teamSlug — firing neighborhood celebration');

      await _fireCelebration(config);
    } catch (e) {
      debugPrint('[SyncBgWorker] onScoreAlertEvent error: $e');
    }
  }

  /// Main polling loop — checks for upcoming sync events.
  Future<void> _poll() async {
    try {
      final configs = await loadSyncEventsForBackground();
      final enabled = configs.where((c) => c.isEnabled && !c.isManual).toList();

      if (enabled.isEmpty) {
        // No sync events to monitor — schedule next check in 5 min
        _scheduleNextPoll(const Duration(minutes: 5));
        return;
      }

      // Load controller IPs if not yet received from UI
      if (_controllerIps.isEmpty) {
        _controllerIps = await loadSyncControllerIps();
      }

      // Daily season schedule reconciliation for "every home game" events
      await _runDailyReconciliation(enabled);

      // Check for active session (score monitoring)
      final activeSession = await loadActiveSession();
      if (activeSession != null) {
        await _monitorActiveSession(activeSession, enabled);
        _scheduleNextPoll(const Duration(seconds: 30));
        return;
      }

      // Check host failover — if we are backup host and grace window expired
      await _checkHostFailover(enabled);

      // Check each event for upcoming triggers
      var nextPollInterval = const Duration(minutes: 5);

      for (final config in enabled) {
        final interval = await _evaluateEvent(config);
        if (interval != null && interval < nextPollInterval) {
          nextPollInterval = interval;
        }
      }

      _scheduleNextPoll(nextPollInterval);
    } catch (e) {
      debugPrint('[SyncBgWorker] Poll error: $e');
      _scheduleNextPoll(const Duration(minutes: 2));
    }
  }

  /// Evaluate a single sync event and return the optimal poll interval.
  Future<Duration?> _evaluateEvent(BackgroundSyncEventConfig config) async {
    final now = DateTime.now();

    if (config.isScheduledTime) {
      return _evaluateScheduledTimeEvent(config, now);
    } else if (config.isGameStart) {
      return await _evaluateGameStartEvent(config, now);
    }
    return null;
  }

  /// Handle scheduled-time trigger events.
  Duration? _evaluateScheduledTimeEvent(
    BackgroundSyncEventConfig config,
    DateTime now,
  ) {
    final target = _nextOccurrence(config.scheduledTime, config.repeatDays);
    if (target == null) return null;

    final delay = target.difference(now);

    // Already past — trigger now if within 10 minute grace window
    if (delay.isNegative) {
      if (delay.inMinutes.abs() <= 10) {
        debugPrint(
          '[SyncBgWorker] Late trigger for "${config.name}" (${delay.inMinutes.abs()}m late)',
        );
        _triggerSession(config);
        return const Duration(minutes: 5);
      }
      return null; // Too late, skip
    }

    // Within 1 minute — set a precise timer
    if (delay.inMinutes <= 1) {
      _setEventTimer(config.id, delay, () => _triggerSession(config));
      return const Duration(seconds: 30);
    }

    // Within 30 minutes — poll more frequently
    if (delay.inMinutes <= 30) {
      return const Duration(minutes: 1);
    }

    return null;
  }

  /// Handle game-start trigger events.
  Future<Duration?> _evaluateGameStartEvent(
    BackgroundSyncEventConfig config,
    DateTime now,
  ) async {
    if (config.espnTeamId == null || config.sportLeague == null) return null;

    final sport = _parseSportType(config.sportLeague!);
    if (sport == null) return null;

    // If scheduled time exists, only start polling within 30 min of it
    if (config.scheduledTime != null) {
      final preGameWindow =
          config.scheduledTime!.subtract(const Duration(minutes: 30));
      if (now.isBefore(preGameWindow)) {
        final delay = preGameWindow.difference(now);
        return delay.inMinutes > 60 ? null : Duration(minutes: delay.inMinutes);
      }
    }

    // Poll ESPN for game status
    try {
      final game = await _espnApi.fetchTeamGame(sport, config.espnTeamId!);
      if (game == null) {
        // No game found — if past scheduled time, try fallback
        if (config.scheduledTime != null &&
            now.isAfter(config.scheduledTime!) &&
            now.difference(config.scheduledTime!).inMinutes < 30) {
          debugPrint(
            '[SyncBgWorker] API fallback: triggering "${config.name}" at scheduled time',
          );
          _triggerSession(config);
          return const Duration(minutes: 5);
        }
        return const Duration(minutes: 5);
      }

      // Check if this game is excluded from the season schedule
      if (config.isSeasonSchedule &&
          config.excludedGameIds.contains(game.gameId)) {
        debugPrint(
          '[SyncBgWorker] Game ${game.gameId} excluded from season schedule',
        );
        return null;
      }

      if (game.status == GameStatus.inProgress) {
        debugPrint('[SyncBgWorker] Game in progress for "${config.name}"!');
        _triggerSession(config, gameId: game.gameId);
        return const Duration(seconds: 30); // Switch to active monitoring
      }

      if (game.status == GameStatus.final_) {
        return null; // Game over, no trigger
      }

      // Game scheduled but not started — poll more frequently
      return const Duration(seconds: 30);
    } catch (e) {
      debugPrint('[SyncBgWorker] ESPN poll error for "${config.name}": $e');
      // Fallback to scheduled time on API failure
      if (config.scheduledTime != null &&
          now.isAfter(config.scheduledTime!) &&
          now.difference(config.scheduledTime!).inMinutes < 30) {
        _triggerSession(config);
        return const Duration(minutes: 5);
      }
      return const Duration(minutes: 2);
    }
  }

  // ── Season Schedule Reconciliation ──────────────────────────────────────

  /// Run daily reconciliation for season schedule events.
  /// Checks if ESPN schedule changed and notifies the UI.
  Future<void> _runDailyReconciliation(
    List<BackgroundSyncEventConfig> configs,
  ) async {
    final seasonConfigs = configs
        .where((c) => c.isSeasonSchedule && c.espnTeamId != null && c.sportLeague != null)
        .toList();

    if (seasonConfigs.isEmpty) return;

    final scheduleService = GameScheduleService();
    try {
      for (final config in seasonConfigs) {
        final sport = _parseSportType(config.sportLeague!);
        if (sport == null || config.seasonYear == null) continue;

        final result = await reconcileSeasonSchedule(
          syncEventId: config.id,
          espnTeamId: config.espnTeamId!,
          teamName: config.name,
          sport: sport,
          season: config.seasonYear!,
          scheduleService: scheduleService,
        );

        if (result != null && result.hasChanges) {
          debugPrint(
            '[SyncBgWorker] Schedule changes for "${config.name}": '
            '${result.changesSummary}',
          );
          // Notify UI about schedule changes
          _service.invoke('seasonScheduleChanged', {
            'eventId': config.id,
            'eventName': config.name,
            'summary': result.changesSummary,
            'addedCount': result.diff.added.length,
            'removedCount': result.diff.removed.length,
            'rescheduledCount': result.diff.rescheduled.length,
          });
        }
      }
    } finally {
      scheduleService.dispose();
    }
  }

  // ── Host Failover Check ──────────────────────────────────────────────────

  /// Check if we should take over as host because the primary host failed.
  /// The 2-minute grace window is tracked via SharedPreferences.
  Future<void> _checkHostFailover(
    List<BackgroundSyncEventConfig> configs,
  ) async {
    final failoverTs = await loadHostFailoverTimestamp();
    if (failoverTs == null) return; // No pending failover

    final now = DateTime.now();
    final elapsed = now.difference(failoverTs);

    if (elapsed < const Duration(minutes: 2)) {
      // Still within grace window — primary host may still initiate
      return;
    }

    // Grace window expired — check if a session was created
    final existing = await loadActiveSession();
    if (existing != null) {
      // Session was created during grace window — clear failover
      await clearHostFailoverTimestamp();
      return;
    }

    // No session exists — we need to take over
    debugPrint(
      '[SyncBgWorker] Host failover: grace window expired, taking over',
    );
    await clearHostFailoverTimestamp();

    // Try to call the failover Cloud Function
    final userUid = await loadSyncUserUid();
    final hostUid = await loadSyncHostUid();
    if (userUid == null || hostUid == null) return;

    // Find the event that should have triggered
    for (final config in configs) {
      if (config.isManual) continue;
      final target = _nextOccurrence(config.scheduledTime, config.repeatDays);
      if (target != null) {
        final diff = now.difference(target).inMinutes.abs();
        if (diff <= 12) {
          // This event was due — trigger it as backup host
          await _triggerSession(config);
          break;
        }
      }
    }
  }

  // ── Session Initiation ──────────────────────────────────────────────────

  /// Trigger a sync session — calls Cloud Function and applies local WLED.
  Future<void> _triggerSession(
    BackgroundSyncEventConfig config, {
    String? gameId,
  }) async {
    debugPrint(
      '[SyncBgWorker] Triggering session for "${config.name}" (gameId: $gameId)',
    );

    // Check if already active
    final existing = await loadActiveSession();
    if (existing != null) {
      debugPrint('[SyncBgWorker] Session already active, skipping');
      return;
    }

    final groupId = config.groupId.isNotEmpty
        ? config.groupId
        : await loadSyncGroupId();
    if (groupId == null) {
      debugPrint('[SyncBgWorker] No group ID available');
      return;
    }

    // Call Cloud Function to initiate session server-side
    // This handles participant resolution, FCM notifications, etc.
    final sessionId = await _callInitiateSessionFunction(
      groupId: groupId,
      eventId: config.id,
      gameId: gameId,
    );

    if (sessionId != null) {
      // Save active session locally
      await saveActiveSession(BackgroundActiveSession(
        sessionId: sessionId,
        syncEventId: config.id,
        groupId: groupId,
        gameId: gameId,
        startedAt: DateTime.now(),
      ));

      // Apply base pattern to local WLED controllers
      await _applyPatternToControllers(
        effectId: config.baseEffectId,
        colors: config.baseColors,
        speed: config.baseSpeed,
        intensity: config.baseIntensity,
        brightness: config.baseBrightness,
      );

      // Notify UI isolate that a session started
      _service.invoke('syncSessionStarted', {
        'sessionId': sessionId,
        'eventId': config.id,
        'eventName': config.name,
        'groupId': groupId,
        'gameId': gameId,
      });

      // Update notification
      _updateSyncNotification('Sync Active — ${config.name}');
    }
  }

  /// Call the initiateSyncSession Cloud Function via HTTP.
  /// Returns the session ID on success, null on failure.
  Future<String?> _callInitiateSessionFunction({
    required String groupId,
    required String eventId,
    String? gameId,
  }) async {
    try {
      // Use Firebase Cloud Functions callable URL
      // The background isolate can't use FirebaseFunctions SDK directly,
      // so we use a direct HTTP call with the user's ID token.
      final userUid = await loadSyncUserUid();
      if (userUid == null) {
        debugPrint('[SyncBgWorker] No user UID — cannot call Cloud Function');
        return null;
      }

      // Use Cloud Functions callable endpoint
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse(
            'https://us-central1-lumina-app.cloudfunctions.net/initiateSyncSession',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'data': {
              'groupId': groupId,
              'eventId': eventId,
              'gameId': gameId,
              'initiatorUid': userUid,
            },
          }),
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body) as Map<String, dynamic>;
          final data = result['result'] as Map<String, dynamic>?;
          return data?['sessionId'] as String?;
        } else {
          debugPrint(
            '[SyncBgWorker] Cloud Function error: ${response.statusCode}',
          );
          return null;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[SyncBgWorker] Cloud Function call failed: $e');
      return null;
    }
  }

  // ── Active Session Monitoring (Score Celebrations) ───────────────────────

  /// Monitor an active game-day session for score changes.
  Future<void> _monitorActiveSession(
    BackgroundActiveSession session,
    List<BackgroundSyncEventConfig> configs,
  ) async {
    if (session.gameId == null) return; // Not a game-day session

    final config = configs.where((c) => c.id == session.syncEventId);
    if (config.isEmpty) return;

    final eventConfig = config.first;
    if (eventConfig.espnTeamId == null || eventConfig.sportLeague == null) {
      return;
    }

    final sport = _parseSportType(eventConfig.sportLeague!);
    if (sport == null) return;

    try {
      final game = await _espnApi.fetchTeamGame(sport, eventConfig.espnTeamId!);
      if (game == null) return;

      // Game ended — trigger dissolution
      if (game.status == GameStatus.final_) {
        debugPrint('[SyncBgWorker] Game ended — triggering session dissolution');
        await _callEndSessionFunction(
          groupId: session.groupId,
          sessionId: session.sessionId,
        );
        await clearActiveSession();
            _lastKnownGameStates.clear();

        _updateSyncNotification('Sync session ended');
        _service.invoke('syncSessionEnded', {
          'sessionId': session.sessionId,
          'groupId': session.groupId,
        });
        return;
      }

      // Check for score changes
      final gameKey = session.gameId!;
      final previous = _lastKnownGameStates[gameKey];
      if (previous != null) {
        final isHome = game.homeTeamId == eventConfig.espnTeamId;
        final prevScore = isHome ? previous.homeScore : previous.awayScore;
        final currScore = isHome ? game.homeScore : game.awayScore;
        final delta = currScore - prevScore;

        if (delta > 0) {
          debugPrint('[SyncBgWorker] Score! +$delta — firing celebration');
          await _fireCelebration(eventConfig);
        }
      }

      _lastKnownGameStates[gameKey] = game;
    } catch (e) {
      debugPrint('[SyncBgWorker] Active session monitor error: $e');
    }
  }

  /// Fire a celebration pattern on local WLED controllers.
  Future<void> _fireCelebration(BackgroundSyncEventConfig config) async {
    // Apply celebration pattern
    await _applyPatternToControllers(
      effectId: config.celebrationEffectId,
      colors: config.celebrationColors,
      speed: 220,
      intensity: 255,
      brightness: 255,
    );

    _service.invoke('syncCelebration', {
      'eventName': config.name,
    });

    _updateSyncNotification('Score! Celebrating with the neighborhood!');

    // Return to base pattern after celebration duration
    _eventTimers['celebration']?.cancel();
    _eventTimers['celebration'] = Timer(
      Duration(seconds: config.celebrationDurationSeconds),
      () async {
        await _applyPatternToControllers(
          effectId: config.baseEffectId,
          colors: config.baseColors,
          speed: config.baseSpeed,
          intensity: config.baseIntensity,
          brightness: config.baseBrightness,
        );
        _updateSyncNotification('Sync Active — ${config.name}');
      },
    );
  }

  /// Call endSyncSession Cloud Function.
  Future<void> _callEndSessionFunction({
    required String groupId,
    required String sessionId,
  }) async {
    try {
      final userUid = await loadSyncUserUid();
      if (userUid == null) return;

      final client = http.Client();
      try {
        await client.post(
          Uri.parse(
            'https://us-central1-lumina-app.cloudfunctions.net/endSyncSession',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'data': {
              'groupId': groupId,
              'sessionId': sessionId,
              'initiatorUid': userUid,
            },
          }),
        ).timeout(const Duration(seconds: 20));
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[SyncBgWorker] End session call failed: $e');
    }
  }

  // ── WLED Pattern Application ────────────────────────────────────────────

  /// Apply a pattern to all configured WLED controllers.
  Future<void> _applyPatternToControllers({
    required int effectId,
    required List<int> colors,
    required int speed,
    required int intensity,
    required int brightness,
  }) async {
    if (_controllerIps.isEmpty) {
      _controllerIps = await loadSyncControllerIps();
    }

    for (final ip in _controllerIps) {
      try {
        final svc = WledService('http://$ip');
        // Build WLED color array (RGBW format)
        final colorSlots = <List<int>>[];
        for (var i = 0; i < 3; i++) {
          if (i < colors.length) {
            final c = colors[i];
            colorSlots.add([
              (c >> 16) & 0xFF, // R
              (c >> 8) & 0xFF, // G
              c & 0xFF, // B
              0, // W
            ]);
          } else {
            colorSlots.add([0, 0, 0, 0]);
          }
        }

        await svc.applyJson({
          'on': true,
          'bri': brightness,
          'seg': [
            {
              'id': 0,
              'fx': effectId,
              'sx': speed,
              'ix': intensity,
              'col': colorSlots,
            },
          ],
        });
      } catch (e) {
        debugPrint('[SyncBgWorker] WLED apply failed for $ip: $e');
      }
    }
  }

  // ── Timer Helpers ──────────────────────────────────────────────────────

  void _scheduleNextPoll(Duration interval) {
    _pollTimer?.cancel();
    _pollTimer = Timer(interval, _poll);
  }

  void _setEventTimer(String eventId, Duration delay, VoidCallback callback) {
    _eventTimers[eventId]?.cancel();
    _eventTimers[eventId] = Timer(delay, callback);
  }

  void _updateSyncNotification(String content) {
    final svc = _service;
    if (svc is AndroidServiceInstance) {
      svc.setForegroundNotificationInfo(
        title: 'Lumina Sync Active',
        content: content,
      );
    }
  }

  // ── Time Calculation ──────────────────────────────────────────────────

  /// Calculate the next occurrence for recurring events.
  DateTime? _nextOccurrence(DateTime? baseTime, List<int> repeatDays) {
    if (baseTime == null) return null;
    final now = DateTime.now();

    if (repeatDays.isEmpty) {
      // One-time event — allow 10 min grace window
      return baseTime.isAfter(now) ||
              now.difference(baseTime).inMinutes <= 10
          ? baseTime
          : null;
    }

    // Recurring — find next matching day
    for (int i = 0; i < 7; i++) {
      final candidate = DateTime(
        now.year,
        now.month,
        now.day + i,
        baseTime.hour,
        baseTime.minute,
      );
      if (repeatDays.contains(candidate.weekday) &&
          (candidate.isAfter(now) ||
              now.difference(candidate).inMinutes <= 10)) {
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
    _espnApi.dispose();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// iOS BACKGROUND FETCH HANDLER
// ═════════════════════════════════════════════════════════════════════════════

/// Quick sync event check for iOS background fetch (~15-20s window).
/// Checks if any sync event should trigger and fires the Cloud Function.
/// Cannot do extended polling — just a single pass.
Future<bool> performQuickSyncCheck() async {
  final espnApi = EspnApiService();
  try {
    final configs = await loadSyncEventsForBackground();
    final enabled = configs.where((c) => c.isEnabled && !c.isManual).toList();
    if (enabled.isEmpty) return true;

    final now = DateTime.now();
    final activeSession = await loadActiveSession();

    for (final config in enabled) {
      // Check scheduled time triggers (within 10 min grace)
      if (config.isScheduledTime && config.scheduledTime != null) {
        final diff = now.difference(config.scheduledTime!).inMinutes.abs();
        if (diff <= 10 && activeSession == null) {
          debugPrint(
            '[SyncBgQuick] Triggering scheduled event "${config.name}"',
          );
          await _quickTrigger(config);
          return true;
        }
      }

      // Check game start triggers
      if (config.isGameStart &&
          config.espnTeamId != null &&
          config.sportLeague != null) {
        final sport = _quickParseSport(config.sportLeague!);
        if (sport == null) continue;

        // Only check if within 30 min of scheduled time (or no scheduled time)
        if (config.scheduledTime != null) {
          final preGame =
              config.scheduledTime!.subtract(const Duration(minutes: 30));
          if (now.isBefore(preGame)) continue;
        }

        final game = await espnApi.fetchTeamGame(sport, config.espnTeamId!);
        if (game != null && game.status == GameStatus.inProgress) {
          if (activeSession == null) {
            debugPrint(
              '[SyncBgQuick] Game in progress — triggering "${config.name}"',
            );
            await _quickTrigger(config, gameId: game.gameId);
          } else if (activeSession.gameId != null) {
            // Active session — quick score check
            await _quickScoreCheck(config, game, activeSession);
          }
        }

        if (game != null && game.status == GameStatus.final_ && activeSession != null) {
          // Game ended — signal dissolution
          await _quickEndSession(activeSession);
        }
      }
    }

    return true;
  } catch (e) {
    debugPrint('[SyncBgQuick] Error: $e');
    return true;
  } finally {
    espnApi.dispose();
  }
}

/// Trigger session via Cloud Function in quick mode.
Future<void> _quickTrigger(
  BackgroundSyncEventConfig config, {
  String? gameId,
}) async {
  final userUid = await loadSyncUserUid();
  final groupId = config.groupId.isNotEmpty
      ? config.groupId
      : await loadSyncGroupId();
  if (userUid == null || groupId == null) return;

  try {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(
          'https://us-central1-lumina-app.cloudfunctions.net/initiateSyncSession',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {
            'groupId': groupId,
            'eventId': config.id,
            'gameId': gameId,
            'initiatorUid': userUid,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final data = result['result'] as Map<String, dynamic>?;
        final sessionId = data?['sessionId'] as String?;
        if (sessionId != null) {
          await saveActiveSession(BackgroundActiveSession(
            sessionId: sessionId,
            syncEventId: config.id,
            groupId: groupId,
            gameId: gameId,
            startedAt: DateTime.now(),
          ));
        }
      }
    } finally {
      client.close();
    }
  } catch (e) {
    debugPrint('[SyncBgQuick] Cloud Function call failed: $e');
  }
}

/// Quick score check during iOS background fetch.
Future<void> _quickScoreCheck(
  BackgroundSyncEventConfig config,
  GameState currentGame,
  BackgroundActiveSession session,
) async {
  // We can't track deltas without persistent last-known state in quick mode,
  // but we can apply the WLED pattern if we detect we're in a game.
  // The full background worker handles proper score diffing.
  // This is a best-effort pattern refresh for iOS.
  final ips = await loadSyncControllerIps();
  for (final ip in ips) {
    try {
      final svc = WledService('http://$ip');
      await svc.applyJson({
        'on': true,
        'bri': config.baseBrightness,
        'seg': [
          {
            'id': 0,
            'fx': config.baseEffectId,
            'sx': config.baseSpeed,
            'ix': config.baseIntensity,
          },
        ],
      });
    } catch (_) {}
  }
}

/// Quick session end during iOS background fetch.
Future<void> _quickEndSession(BackgroundActiveSession session) async {
  final userUid = await loadSyncUserUid();
  if (userUid == null) return;

  try {
    final client = http.Client();
    try {
      await client.post(
        Uri.parse(
          'https://us-central1-lumina-app.cloudfunctions.net/endSyncSession',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {
            'groupId': session.groupId,
            'sessionId': session.sessionId,
            'initiatorUid': userUid,
          },
        }),
      ).timeout(const Duration(seconds: 15));
    } finally {
      client.close();
    }
  } catch (e) {
    debugPrint('[SyncBgQuick] End session failed: $e');
  }
  await clearActiveSession();
}

SportType? _quickParseSport(String league) {
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
