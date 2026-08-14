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
import '../wled/wled_payload_utils.dart';
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

  bool _disposed = false;

  GameDayAutopilotBackgroundWorker({
    required EspnApiService espnApi,
    required GameScheduleService scheduleService,
  })  : _espnApi = espnApi,
        _scheduleService = scheduleService;

  /// Start monitoring. Loads any persisted sessions.
  Future<void> startMonitoring() async {
    debugPrint('[GameDayBg] startMonitoring');
    _sessions.clear();
    _sessions.addAll(await loadGameDaySessions());
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

  /// True when ANY team currently has an active session — scheduled or
  /// ephemeral. The background service arms score polling off this, so a
  /// mid-game "Light It Up Now" tap starts monitoring from that second.
  bool get hasActiveSession => _sessions.values.any((s) => s.isActive);

  /// Celebration refusals since process start, keyed by reason.
  ///
  /// The counter half of "every path out must increment something" (#68). A
  /// debugPrint alone vanishes in a release build, so the count is what makes a
  /// refusal inspectable after the fact; tests assert on this rather than on
  /// log scraping.
  final Map<String, int> celebrationSkips = <String, int>{};

  void _noteCelebrationSkip(String teamSlug, String reason) {
    celebrationSkips[reason] = (celebrationSkips[reason] ?? 0) + 1;
    debugPrint('[GameDayBg] celebration SKIPPED team=$teamSlug reason=$reason');
  }

  /// Register an already-running show with the worker's in-memory session map.
  ///
  /// THIS IS CELEBRATION BLOCKER (2). `onScoreAlertEvent` finds its session in
  /// `_sessions`, and `_sessions` was only ever populated by `evaluate()` —
  /// the scheduled path. "Light It Up Now" applied a pattern to the controllers
  /// and registered nothing, so every subsequent scoring event hit
  /// `session == null` and returned. A mid-game tap lit the house and armed
  /// nothing at all.
  ///
  /// Idempotent: re-tapping refreshes the game binding rather than stacking
  /// sessions, and an existing ACTIVE session for the team is preserved so a
  /// tap during a scheduled show does not restart it.
  void registerActiveSession({
    required String teamSlug,
    DateTime? gameStart,
    String? activeGameId,
    DateTime? activatedAt,
  }) {
    if (_disposed) return;
    final existing = _sessions[teamSlug];
    if (existing != null && existing.isActive) {
      // Keep the scheduled session; just bind the game id if we learned one.
      if (activeGameId != null && existing.activeGameId == null) {
        _sessions[teamSlug] = BackgroundAutopilotSession(
          teamSlug: teamSlug,
          phase: existing.phase,
          gameStart: existing.gameStart ?? gameStart,
          gameEndDetected: existing.gameEndDetected,
          countdownEnd: existing.countdownEnd,
          activeGameId: activeGameId,
          usedFallbackTimer: existing.usedFallbackTimer,
          activatedAt: existing.activatedAt,
        );
      }
      return;
    }
    _sessions[teamSlug] = BackgroundAutopilotSession(
      teamSlug: teamSlug,
      phase: 'inGame',
      gameStart: gameStart,
      gameEndDetected: null,
      countdownEnd: null,
      activeGameId: activeGameId,
      usedFallbackTimer: false,
      activatedAt: activatedAt ?? DateTime.now(),
    );
    debugPrint('[GameDayBg] registered active session for $teamSlug '
        '(ephemeral/manual start) — scoring armed');
    unawaited(_persistSessions());
  }

  /// Score celebration hook. Called by the sports background service
  /// when ScoreMonitorService emits an alert event. Only fires if there
  /// is an active Game Day session for the team.
  ///
  /// EVERY PATH OUT OF HERE IS LEGIBLE. This method used to have four bare
  /// `return`s and exactly one debugPrint (in the catch), so "the celebration
  /// did not fire" and "the celebration was never attempted" were the same
  /// observable: nothing. That is the same silent-skip class as #68, and it is
  /// why a fleet-wide "celebrations have never fired" could sit undetected —
  /// there was no absence to notice. Each refusal now names itself.
  Future<void> onScoreAlertEvent(dynamic event) async {
    if (_disposed) {
      _noteCelebrationSkip('(disposed)', 'worker_disposed');
      return;
    }

    try {
      final teamSlug = event.teamSlug as String?;
      if (teamSlug == null) {
        _noteCelebrationSkip('(null)', 'event_without_team');
        return;
      }

      final session = _sessions[teamSlug];
      if (session == null) {
        _noteCelebrationSkip(teamSlug, 'no_session_registered');
        return;
      }
      if (!session.isActive) {
        _noteCelebrationSkip(teamSlug, 'session_not_active:${session.phase}');
        return;
      }

      final configs = await loadGameDayConfigsForBackground();
      final config = configs
          .where((c) => c.teamSlug == teamSlug)
          .cast<BackgroundGameDayAutopilotConfig?>()
          .firstWhere((c) => c != null, orElse: () => null);
      if (config == null) {
        _noteCelebrationSkip(teamSlug, 'no_config');
        return;
      }
      if (!config.scoreCelebrationEnabled) {
        _noteCelebrationSkip(teamSlug, 'celebration_disabled');
        return;
      }

      // Build a flash pattern in team colors.
      final payload = buildCelebrationPayloadForTest(config);
      await _applyToControllers(payload);

      // After ~15 seconds, revert to base team pattern.
      unawaited(Future.delayed(const Duration(seconds: 15), () async {
        if (_disposed) return;
        final currentSession = _sessions[teamSlug];
        if (currentSession == null || !currentSession.isActive) return;
        final basePayload = buildBasePayloadForTest(config);
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

    final payload = buildBasePayloadForTest(config);
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

  @visibleForTesting
  static Map<String, dynamic> buildBasePayloadForTest(
    BackgroundGameDayAutopilotConfig config,
  ) {
    // Saved design wins. Routed through normalizeWledPayload so saved
    // blobs with a <3-slot col (or with grp/spc/of omitted) get the same
    // stale-slot defense the WledService chokepoint applies — the
    // background isolate can't reach that chokepoint at apply time.
    if (config.designMode == 'saved' && config.savedDesignPayload != null) {
      return expandForChannels(
        normalizeWledPayload(
          Map<String, dynamic>.from(config.savedDesignPayload!),
        ),
        config.participatingChannelIds,
      );
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

    // TeamDesignCatalog payloads carry a 2-slot col ([primary, secondary]).
    // Normalize pads to 3 so the device's third slot is overwritten
    // explicitly instead of holding the prior pattern's color. Team payloads
    // are RAW single-seg-no-id → expandForChannels fans them across the
    // participating channels (the #29 fix).
    return expandForChannels(
      normalizeWledPayload(Map<String, dynamic>.from(design.wledPayload)),
      config.participatingChannelIds,
    );
  }

  /// Expands a background Game Day payload to target the config's RESOLVED
  /// participating channels (#29). Mirrors the foreground fix
  /// (game_day_apply.dart:88) and the Class-1 raw-vs-prefiltered discriminator:
  ///   • null ids       → pass through (legacy single-seg; lights ch1 only —
  ///                      no worse than before).
  ///   • [] ids         → explicit opt-out: returns seg:[] so the dispatcher
  ///                      skip-applies (see [_applyToControllers]).
  ///   • RAW single-seg → applyChannelFilter to the participating set. No
  ///     (no id)          DeviceChannel list ⇒ no start/stop; WLED retains the
  ///                      install-time segment ranges (same contract as the
  ///                      sync worker / buildParticipatingSegArray).
  ///   • already multi- → pass through untouched (a saved design carries its
  ///     seg / id-bearing  own per-channel segs; re-filtering would template
  ///                      off seg.first and flatten it to bus 0).
  @visibleForTesting
  static Map<String, dynamic> expandForChannels(
    Map<String, dynamic> base,
    List<int>? participatingChannelIds,
  ) {
    if (participatingChannelIds == null) return base; // legacy fallback
    if (participatingChannelIds.isEmpty) {
      // Explicit opt-out — signal skip via an empty seg array.
      final r = Map<String, dynamic>.from(base);
      r['seg'] = const <Map<String, dynamic>>[];
      return r;
    }
    final seg = base['seg'];
    final isRaw = seg is List &&
        seg.length == 1 &&
        seg.first is Map &&
        !(seg.first as Map).containsKey('id');
    if (!isRaw) return base; // pre-filtered (saved design) — don't flatten
    return applyChannelFilter(base, participatingChannelIds);
  }

  /// Build a celebration flash payload in team colors.
  @visibleForTesting
  static Map<String, dynamic> buildCelebrationPayloadForTest(
    BackgroundGameDayAutopilotConfig config,
  ) {
    final primary = Color(config.primaryColorValue);
    final secondary = Color(config.secondaryColorValue);
    // RAW single-seg-no-id → expandForChannels fans the celebration flash
    // across the participating channels too (same #29 fix as the base show).
    return expandForChannels(
      normalizeWledPayload({
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
      }),
      config.participatingChannelIds,
    );
  }

  /// Dispatch a WLED payload to the user's controllers via the
  /// applySyncPattern Cloud Function. Server-side fanout enqueues commands
  /// in the bridge queue, so this works whether the user is on home WiFi
  /// or remote — no direct HTTP to controller IPs.
  Future<void> _applyToControllers(Map<String, dynamic> payload) async {
    // Skip-apply on an explicit-opt-out payload (empty seg array from
    // expandForChannels []-case) — never POST an empty seg. A top-level-only
    // payload like {'on': false} has no 'seg' key and is NOT skipped.
    final seg = payload['seg'];
    if (seg is List && seg.isEmpty) {
      debugPrint('[GameDayBg] skip-apply: no participating channels');
      return;
    }
    final hostUid = await loadGameDayUserUid();
    if (hostUid == null) {
      debugPrint('[GameDayBg] No user UID — cannot dispatch pattern');
      return;
    }
    final idToken = await loadSyncIdToken();
    if (idToken == null) {
      debugPrint(
        '[GameDayBg] No ID token persisted — skipping applySyncPattern',
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/applySyncPattern'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
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
