// lib/features/autopilot/game_day_autopilot_background_worker.dart
//
// Background worker for individual-user Game Day Autopilot. Runs inside
// the sports background service isolate (lib/features/sports_alerts/
// services/sports_background_service.dart).
//
// Responsibilities:
//   1. Load Game Day configs from SharedPreferences each polling cycle.
//   2. Evaluate each enabled config against ESPN:
//        - Within 30 min of a game? Activate pre-game.
//        - Active session in preGame? Check for game start.
//        - Active session in liveGame? Check for game end.
//        - Active session in postGame? Check countdown elapsed.
//   3. Apply WLED payloads directly via HTTP (no Riverpod, no Firestore).
//   4. Persist session state back to SharedPreferences so the foreground
//      UI can reflect what the background is doing.
//
// Priority coordination with Neighborhood Sync happens in D4.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/sun_utils.dart';
import '../sports_alerts/models/game_state.dart';
import '../sports_alerts/models/sport_type.dart';
import '../neighborhood/services/sync_event_background_persistence.dart';
import '../sports_alerts/services/espn_api_service.dart';
import '../sports_alerts/services/game_schedule_service.dart';
import 'game_day_background_persistence.dart';
import 'game_day_priority_resolver.dart';
import 'team_design_catalog.dart';

/// Duration of the post-game countdown before lights resume normal.
const _kPostGameCountdown = Duration(minutes: 30);

/// How far ahead to look for upcoming games.
const _kPreGameLeadTimeMinutes = 30;

/// Cloud Functions base URL for the active Firebase project. Mirrors the
/// constant in lib/features/neighborhood/services/sync_event_background_worker.dart.
const String _functionsBaseUrl =
    'https://us-central1-icrt6menwsv2d8all8oijs021b06s5'
    '.cloudfunctions.net';

class GameDayAutopilotBackgroundWorker {
  final EspnApiService _espnApi;
  final GameScheduleService _scheduleService;

  /// In-memory sessions map for this worker instance.
  /// Loaded from SharedPreferences on startMonitoring, saved back on
  /// every mutation.
  final Map<String, BackgroundAutopilotSession> _sessions = {};

  /// Controller IPs received from the UI isolate. No longer read directly
  /// — fanout now goes through the applySyncPattern Cloud Function, which
  /// resolves controllers from Firestore. Field retained because the
  /// cross-isolate updateControllerIps API is still wired in
  /// sports_background_service.dart.
  // ignore: unused_field
  List<String> _controllerIps = const [];

  bool _disposed = false;

  GameDayAutopilotBackgroundWorker({
    required EspnApiService espnApi,
    required GameScheduleService scheduleService,
  })  : _espnApi = espnApi,
        _scheduleService = scheduleService;

  /// Start monitoring. Loads any persisted sessions and controller IPs.
  Future<void> startMonitoring() async {
    debugPrint('[GameDayBg] startMonitoring');
    _sessions.clear();
    _sessions.addAll(await loadGameDaySessions());
    _controllerIps = await loadGameDayControllerIps();
  }

  /// Update controller IPs (called when the foreground sends an update
  /// via service.invoke('updateIps')).
  void updateControllerIps(List<String> ips) {
    _controllerIps = ips;
    unawaited(saveGameDayControllerIps(ips));
  }

  /// Whether this worker has any work to do. If false, sports background
  /// service may choose to stop when no sync events and no sports alerts
  /// are active either.
  Future<bool> hasActiveWorkload() async {
    final configs = await loadGameDayConfigsForBackground();
    final enabled = configs.where((c) => c.enabled).toList();
    if (enabled.isNotEmpty) return true;
    return _sessions.values.any((s) => s.isActive);
  }

  /// Evaluate all configs. Called by the sports background service poll
  /// loop. Activates pre-game, transitions phases, applies payloads.
  Future<void> evaluate() async {
    if (_disposed) return;

    final configs = await loadGameDayConfigsForBackground();
    final enabled = configs.where((c) => c.enabled).toList();

    if (enabled.isEmpty && _sessions.isEmpty) return;

    final now = DateTime.now();

    // Update any sessions currently active.
    for (final config in enabled) {
      final session = _sessions[config.teamSlug];
      if (session == null) continue;

      if (session.phase == 'completed') continue;

      if (session.isActive) {
        await _updateActiveSession(config, session, now);
      }
    }

    // Check for new pre-game activations.
    for (final config in enabled) {
      final existing = _sessions[config.teamSlug];
      if (existing != null &&
          (existing.isActive || existing.phase == 'completed')) {
        continue;
      }

      final hasGame = await _scheduleService.hasGameSoon(
        config.espnTeamId,
        _parseSportType(config.sport),
        minutes: _kPreGameLeadTimeMinutes,
      );

      if (hasGame) {
        final nextGame = await _scheduleService.fetchNextGameDate(
          config.espnTeamId,
          _parseSportType(config.sport),
        );
        await _activatePreGame(config, nextGame);
      }
    }

    // Clean up completed sessions older than 6 hours.
    final expired = <String>[];
    _sessions.forEach((slug, session) {
      if (session.phase == 'completed' &&
          session.activatedAt
              .add(const Duration(hours: 6))
              .isBefore(now)) {
        expired.add(slug);
      }
    });
    for (final slug in expired) {
      _sessions.remove(slug);
    }

    await _persistSessions();
  }

  /// Score celebration hook. Called by the sports background service
  /// when ScoreMonitorService emits an alert event. Only fires if there
  /// is an active Game Day session for the team.
  Future<void> onScoreAlertEvent(dynamic event) async {
    if (_disposed) return;

    try {
      final teamSlug = event.teamSlug as String?;
      if (teamSlug == null) return;

      final session = _sessions[teamSlug];
      if (session == null || !session.isActive) return;

      final configs = await loadGameDayConfigsForBackground();
      final config = configs
          .where((c) => c.teamSlug == teamSlug)
          .cast<BackgroundGameDayAutopilotConfig?>()
          .firstWhere((c) => c != null, orElse: () => null);
      if (config == null || !config.scoreCelebrationEnabled) return;

      // Build a flash pattern in team colors.
      final payload = _buildCelebrationPayload(config);
      await _applyToControllers(payload);

      // After ~15 seconds, revert to base team pattern.
      unawaited(Future.delayed(const Duration(seconds: 15), () async {
        if (_disposed) return;
        final currentSession = _sessions[teamSlug];
        if (currentSession == null || !currentSession.isActive) return;
        final basePayload = _buildBasePayload(config);
        await _applyToControllers(basePayload);
      }));
    } catch (e) {
      debugPrint('[GameDayBg] onScoreAlertEvent failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _sessions.clear();
  }

  // ── Phase transitions ────────────────────────────────────────────────

  Future<void> _activatePreGame(
    BackgroundGameDayAutopilotConfig config,
    DateTime? gameStart,
  ) async {
    // Daylight filter.
    if (config.skipDayGames && gameStart != null) {
      final location = await loadUserLocation();
      if (location != null) {
        final duration = _estimatedDuration(config.sport);
        final estimatedEnd = gameStart.add(duration);
        final sunset = SunUtils.sunsetLocal(
          location.latitude,
          location.longitude,
          gameStart,
        );
        if (sunset != null &&
            estimatedEnd.isBefore(
              sunset.subtract(const Duration(minutes: 30)),
            )) {
          debugPrint(
              '[GameDayBg] Skipping ${config.teamName} — daylight game');
          return;
        }
      }
    }

    // Priority check: defer to neighborhood sync for the same game.
    final decision = await _resolvePriorityForActivation(config, gameStart);
    if (!decision.shouldActivate) {
      debugPrint('[GameDayBg] Pre-game deferred: ${decision.reason}');
      return;
    }

    final session = BackgroundAutopilotSession(
      teamSlug: config.teamSlug,
      phase: 'preGame',
      gameStart: gameStart,
      activatedAt: DateTime.now(),
    );
    _sessions[config.teamSlug] = session;

    final payload = _buildBasePayload(config);
    await _applyToControllers(payload);
    await _persistSessions();

    debugPrint('[GameDayBg] Pre-game activated: ${config.teamName}');
  }

  /// Build the list of competing active events from persisted state,
  /// then resolve the priority decision for this config.
  Future<GameDayPriorityResult> _resolvePriorityForActivation(
    BackgroundGameDayAutopilotConfig config,
    DateTime? gameStart,
  ) async {
    final actives = <GameDayEventCandidate>[];

    // Collect active personal autopilot sessions (other than this one).
    for (final session in _sessions.values) {
      if (session.teamSlug == config.teamSlug) continue;
      if (!session.isActive) continue;

      final allConfigs = await loadGameDayConfigsForBackground();
      final sessionConfig = allConfigs
          .where((c) => c.teamSlug == session.teamSlug)
          .cast<BackgroundGameDayAutopilotConfig?>()
          .firstWhere((c) => c != null, orElse: () => null);
      if (sessionConfig == null) continue;

      actives.add(GameDayEventCandidate(
        id: session.teamSlug,
        source: GameDayEventSource.personalAutopilot,
        teamSlug: session.teamSlug,
        espnTeamId: sessionConfig.espnTeamId,
        activatedAt: session.activatedAt,
        gameId: session.activeGameId,
      ));
    }

    // Collect active neighborhood sync session.
    final syncSession = await loadActiveSession();
    if (syncSession != null) {
      actives.add(GameDayEventCandidate(
        id: syncSession.syncEventId,
        source: GameDayEventSource.neighborhoodSync,
        teamSlug: '',
        espnTeamId: '',
        activatedAt: syncSession.startedAt,
        gameId: syncSession.gameId,
      ));
    }

    // Build candidate for this config.
    final candidate = GameDayEventCandidate(
      id: config.teamSlug,
      source: GameDayEventSource.personalAutopilot,
      teamSlug: config.teamSlug,
      espnTeamId: config.espnTeamId,
      activatedAt: gameStart ?? DateTime.now(),
    );

    final teamPriority = await loadUserTeamPriority();

    return GameDayPriorityResolver.resolve(
      candidate: candidate,
      activeEvents: actives,
      teamPriority: teamPriority,
    );
  }

  Future<void> _updateActiveSession(
    BackgroundGameDayAutopilotConfig config,
    BackgroundAutopilotSession session,
    DateTime now,
  ) async {
    switch (session.phase) {
      case 'preGame':
        final gameState = await _espnApi.fetchTeamGame(
          _parseSportType(config.sport),
          config.espnTeamId,
        );
        if (gameState != null &&
            (gameState.status == GameStatus.inProgress ||
                gameState.status == GameStatus.halftime)) {
          _sessions[config.teamSlug] = BackgroundAutopilotSession(
            teamSlug: session.teamSlug,
            phase: 'liveGame',
            gameStart: session.gameStart,
            activeGameId: gameState.gameId,
            activatedAt: session.activatedAt,
          );
          debugPrint('[GameDayBg] Game started: ${config.teamName}');
        }

      case 'liveGame':
        final gameState = await _espnApi.fetchTeamGame(
          _parseSportType(config.sport),
          config.espnTeamId,
        );

        if (gameState != null && gameState.status == GameStatus.final_) {
          _sessions[config.teamSlug] = BackgroundAutopilotSession(
            teamSlug: session.teamSlug,
            phase: 'postGame',
            gameStart: session.gameStart,
            gameEndDetected: now,
            countdownEnd: now.add(_kPostGameCountdown),
            activeGameId: session.activeGameId,
            activatedAt: session.activatedAt,
          );
          debugPrint('[GameDayBg] Game final: ${config.teamName}');
          return;
        }

        // Fallback: game ran longer than estimated + 60 min buffer.
        if (session.gameStart != null) {
          final duration = _estimatedDuration(config.sport);
          final estimatedEnd = session.gameStart!
              .add(duration)
              .add(const Duration(minutes: 60));
          if (now.isAfter(estimatedEnd)) {
            _sessions[config.teamSlug] = BackgroundAutopilotSession(
              teamSlug: session.teamSlug,
              phase: 'postGame',
              gameStart: session.gameStart,
              gameEndDetected: now,
              countdownEnd: now.add(_kPostGameCountdown),
              activeGameId: session.activeGameId,
              usedFallbackTimer: true,
              activatedAt: session.activatedAt,
            );
            debugPrint(
                '[GameDayBg] Fallback timer: ${config.teamName}');
          }
        }

      case 'postGame':
        if (session.countdownEnd != null &&
            now.isAfter(session.countdownEnd!)) {
          _sessions[config.teamSlug] = BackgroundAutopilotSession(
            teamSlug: session.teamSlug,
            phase: 'completed',
            gameStart: session.gameStart,
            gameEndDetected: session.gameEndDetected,
            countdownEnd: session.countdownEnd,
            activeGameId: session.activeGameId,
            usedFallbackTimer: session.usedFallbackTimer,
            activatedAt: session.activatedAt,
          );

          // Check if there's a sync session to resume instead of
          // turning lights off blindly.
          final syncSession = await loadActiveSession();
          final syncGroupId = await loadSyncGroupId();
          if (syncSession != null && syncGroupId != null) {
            // Sync is still active — yield control. The sync worker
            // will reapply its pattern on its next poll cycle.
            debugPrint('[GameDayBg] Post-game: sync session active, '
                'yielding control to sync worker');
          } else {
            // No sync active — default behavior: turn off.
            await _applyToControllers({'on': false});
            debugPrint('[GameDayBg] Post-game countdown complete: '
                '${config.teamName}, lights off');
          }
        }
    }
  }

  // ── WLED payload building ───────────────────────────────────────────

  Map<String, dynamic> _buildBasePayload(
    BackgroundGameDayAutopilotConfig config,
  ) {
    // Saved design wins.
    if (config.designMode == 'saved' && config.savedDesignPayload != null) {
      return Map<String, dynamic>.from(config.savedDesignPayload!);
    }

    // Build from team colors via the design catalog.
    final primary = Color(config.primaryColorValue);
    final secondary = Color(config.secondaryColorValue);
    final catalog = TeamDesignCatalog.build(
      teamName: config.teamName,
      primary: primary,
      secondary: secondary,
      brightness: config.brightness,
    );

    final design = switch (config.designVariety) {
      'random' => TeamDesignCatalog.selectForRandom(
          catalog,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      'rotating' => TeamDesignCatalog.selectForRotation(
          catalog,
          DateTime.now().difference(DateTime(DateTime.now().year)).inDays,
        ),
      _ => catalog.first,
    };

    return Map<String, dynamic>.from(design.wledPayload);
  }

  /// Build a celebration flash payload in team colors.
  Map<String, dynamic> _buildCelebrationPayload(
    BackgroundGameDayAutopilotConfig config,
  ) {
    final primary = Color(config.primaryColorValue);
    final secondary = Color(config.secondaryColorValue);
    return {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'fx': 11, // Sparkle
          'sx': 240,
          'ix': 240,
          'pal': 0,
          'col': [
            [
              (primary.r * 255).round(),
              (primary.g * 255).round(),
              (primary.b * 255).round(),
              0,
            ],
            [
              (secondary.r * 255).round(),
              (secondary.g * 255).round(),
              (secondary.b * 255).round(),
              0,
            ],
          ],
        }
      ],
    };
  }

  /// Dispatch a WLED payload to the user's controllers via the
  /// applySyncPattern Cloud Function. Server-side fanout enqueues commands
  /// in the bridge queue, so this works whether the user is on home WiFi
  /// or remote — no direct HTTP to controller IPs.
  Future<void> _applyToControllers(Map<String, dynamic> payload) async {
    final hostUid = await loadGameDayUserUid();
    if (hostUid == null) {
      debugPrint('[GameDayBg] No user UID — cannot dispatch pattern');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/applySyncPattern'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {
            'groupId': '',
            'sessionId': '',
            'payload': payload,
            'initiatorUid': hostUid,
            'source': 'game_day',
          },
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          '[GameDayBg] applySyncPattern failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[GameDayBg] applySyncPattern error: $e');
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────

  Future<void> _persistSessions() async {
    await saveGameDaySessionsFromBackground(_sessions.values.toList());
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  SportType _parseSportType(String name) {
    return SportType.values.firstWhere(
      (s) => s.name == name,
      orElse: () => SportType.nfl,
    );
  }

  Duration _estimatedDuration(String sport) {
    return switch (sport) {
      'nfl' => const Duration(hours: 3, minutes: 30),
      'mlb' => const Duration(hours: 3),
      'nba' => const Duration(hours: 2, minutes: 30),
      'nhl' => const Duration(hours: 2, minutes: 30),
      'ncaaFb' => const Duration(hours: 3, minutes: 30),
      'ncaaMB' => const Duration(hours: 2, minutes: 30),
      'mls' => const Duration(hours: 2),
      'epl' => const Duration(hours: 2),
      _ => const Duration(hours: 3),
    };
  }
}
