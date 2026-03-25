// lib/features/autopilot/game_day_autopilot_service.dart
//
// Core service for individual-user Game Day Autopilot.
//
// Responsibilities:
//   1. PRE-GAME: 30 min before game start, activate team-themed design.
//   2. LIVE GAME: Keep lights on team design; score celebrations fire via
//      existing ScoreMonitorService pipeline.
//   3. POST-GAME: Detect game end via ESPN API (primary) or estimated
//      duration fallback, then start 30-min countdown before resuming
//      normal schedule or turning off.
//
// Design selection priority:
//   1. User-saved design for this team
//   2. Auto-select from UserVarietyProfile (static → Solid, motion → Chase,
//      dynamic → Pulse/Twinkle)
//   3. Fallback: Solid in team primary color

import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../sports_alerts/models/game_state.dart';
import '../sports_alerts/services/espn_api_service.dart';
import '../sports_alerts/services/game_schedule_service.dart';
import 'game_day_autopilot_config.dart';

// ---------------------------------------------------------------------------
// Autopilot session state
// ---------------------------------------------------------------------------

/// Tracks the lifecycle of a single game day autopilot session.
enum AutopilotSessionPhase {
  /// Waiting for pre-game window (30 min before start).
  idle,

  /// Lights activated with team design; game hasn't started yet.
  preGame,

  /// Game is live; lights remain on team design.
  liveGame,

  /// Game ended; 30-min countdown running before turning off.
  postGame,

  /// Session complete — lights returned to normal schedule or off.
  completed,
}

/// Snapshot of the current autopilot session for a single team.
class AutopilotSession {
  final String teamSlug;
  final AutopilotSessionPhase phase;
  final DateTime? gameStart;
  final DateTime? gameEndDetected;
  final DateTime? countdownEnd;
  final String? activeGameId;
  final bool usedFallbackTimer;

  const AutopilotSession({
    required this.teamSlug,
    this.phase = AutopilotSessionPhase.idle,
    this.gameStart,
    this.gameEndDetected,
    this.countdownEnd,
    this.activeGameId,
    this.usedFallbackTimer = false,
  });

  AutopilotSession copyWith({
    AutopilotSessionPhase? phase,
    DateTime? gameStart,
    DateTime? gameEndDetected,
    DateTime? countdownEnd,
    String? activeGameId,
    bool? usedFallbackTimer,
  }) {
    return AutopilotSession(
      teamSlug: teamSlug,
      phase: phase ?? this.phase,
      gameStart: gameStart ?? this.gameStart,
      gameEndDetected: gameEndDetected ?? this.gameEndDetected,
      countdownEnd: countdownEnd ?? this.countdownEnd,
      activeGameId: activeGameId ?? this.activeGameId,
      usedFallbackTimer: usedFallbackTimer ?? this.usedFallbackTimer,
    );
  }

  bool get isActive =>
      phase == AutopilotSessionPhase.preGame ||
      phase == AutopilotSessionPhase.liveGame ||
      phase == AutopilotSessionPhase.postGame;

  @override
  String toString() => 'AutopilotSession($teamSlug, phase=$phase)';
}

// ---------------------------------------------------------------------------
// Design selection result
// ---------------------------------------------------------------------------

/// Result of the design selection algorithm.
class DesignSelection {
  final AutopilotDesignMode mode;
  final String designName;
  final int effectId;
  final int speed;
  final int intensity;
  final int brightness;
  final List<List<int>> colors;
  final Map<String, dynamic> wledPayload;

  const DesignSelection({
    required this.mode,
    required this.designName,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.brightness,
    required this.colors,
    required this.wledPayload,
  });

  @override
  String toString() => 'DesignSelection($designName, mode=$mode, fx=$effectId)';
}

// ---------------------------------------------------------------------------
// GameDayAutopilotService
// ---------------------------------------------------------------------------

class GameDayAutopilotService {
  final EspnApiService _espnApi;
  final GameScheduleService _scheduleService;

  /// Active sessions keyed by team slug.
  final Map<String, AutopilotSession> _sessions = {};

  /// Polling timer for post-game detection.
  Timer? _postGamePollTimer;

  /// Callback invoked when the service needs to apply a WLED payload.
  /// Set by the provider layer to bridge into the WLED notifier.
  void Function(Map<String, dynamic> payload)? onApplyPayload;

  /// Callback invoked when the service needs to resume normal schedule
  /// or turn lights off after the post-game countdown.
  void Function()? onResumeNormalSchedule;

  /// Callback invoked when the session phase changes (for UI updates).
  void Function(AutopilotSession session)? onSessionChanged;

  GameDayAutopilotService({
    required EspnApiService espnApi,
    required GameScheduleService scheduleService,
  })  : _espnApi = espnApi,
        _scheduleService = scheduleService;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Get the current session for a team (null if no active session).
  AutopilotSession? getSession(String teamSlug) => _sessions[teamSlug];

  /// All active sessions.
  Map<String, AutopilotSession> get activeSessions =>
      Map.unmodifiable(_sessions);

  /// Check all enabled autopilot configs and activate pre-game if within
  /// the 30-minute window. Called periodically by the provider layer.
  Future<void> evaluateConfigs(List<GameDayAutopilotConfig> configs) async {
    final now = DateTime.now();

    for (final config in configs) {
      if (!config.enabled) continue;

      final session = _sessions[config.teamSlug];

      // Skip completed or already-active sessions.
      if (session != null && session.phase == AutopilotSessionPhase.completed) {
        continue;
      }

      if (session != null && session.isActive) {
        // Already active — check for phase transitions.
        await _updateActiveSession(config, session, now);
        continue;
      }

      // Check if there's a game starting within 30 minutes.
      final hasGame = await _scheduleService.hasGameSoon(
        config.espnTeamId,
        config.sport,
        minutes: 30,
      );

      if (hasGame) {
        final nextGame = await _scheduleService.fetchNextGameDate(
          config.espnTeamId,
          config.sport,
        );
        debugPrint('[GameDayAutopilot] Game soon for ${config.teamName}, '
            'starting pre-game activation');
        await _activatePreGame(config, nextGame);
      }
    }
  }

  /// Force-activate autopilot for a team (e.g., manual trigger from UI).
  Future<void> forceActivate(
    GameDayAutopilotConfig config,
    DesignSelection design,
  ) async {
    _sessions[config.teamSlug] = AutopilotSession(
      teamSlug: config.teamSlug,
      phase: AutopilotSessionPhase.preGame,
      gameStart: DateTime.now(),
    );
    _applyDesign(design);
    _notifySessionChanged(config.teamSlug);
  }

  /// Cancel an active session for a team.
  void cancelSession(String teamSlug) {
    final session = _sessions.remove(teamSlug);
    if (session != null) {
      debugPrint('[GameDayAutopilot] Session cancelled for $teamSlug');
      onResumeNormalSchedule?.call();
    }
  }

  /// Select the appropriate design for a team based on config and user profile.
  ///
  /// [preferredStyles] comes from AutopilotProfile.preferredEffectStyles.
  DesignSelection selectDesign(
    GameDayAutopilotConfig config, {
    List<String> preferredStyles = const [],
  }) {
    final primaryRgb = _colorToRgbList(config.primaryColor);
    final secondaryRgb = _colorToRgbList(config.secondaryColor);
    final colors = [primaryRgb, secondaryRgb];

    // Priority 1: User has a saved design.
    if (config.designMode == AutopilotDesignMode.saved &&
        config.savedDesignPayload != null) {
      debugPrint('[GameDayAutopilot] Design branch: SAVED for ${config.teamSlug}');
      return DesignSelection(
        mode: AutopilotDesignMode.saved,
        designName: config.savedDesignName ?? 'Custom Design',
        effectId: config.effectId,
        speed: config.speed,
        intensity: config.intensity,
        brightness: config.brightness,
        colors: colors,
        wledPayload: config.savedDesignPayload!,
      );
    }

    // Priority 2: Auto-select from user style preferences.
    if (preferredStyles.isNotEmpty) {
      final styleCategory = _categorizeStyles(preferredStyles);
      debugPrint('[GameDayAutopilot] Design branch: AUTO-SELECT '
          '(style=$styleCategory) for ${config.teamSlug}');

      final (effectId, effectName, speed) = switch (styleCategory) {
        _StyleCategory.static_ => (0, 'Solid', 128),      // Solid
        _StyleCategory.motion  => (28, 'Chase', 180),      // Chase
        _StyleCategory.dynamic => (63, 'Twinkle', 150),    // Twinkle
      };

      return DesignSelection(
        mode: AutopilotDesignMode.autoSelected,
        designName: '$effectName in ${config.teamName} Colors',
        effectId: effectId,
        speed: speed,
        intensity: 180,
        brightness: config.brightness,
        colors: colors,
        wledPayload: _buildWledPayload(
          effectId: effectId,
          colors: colors,
          speed: speed,
          intensity: 180,
          brightness: config.brightness,
        ),
      );
    }

    // Priority 3: Fallback — Solid in team primary color.
    debugPrint('[GameDayAutopilot] Design branch: FALLBACK for ${config.teamSlug}');
    return DesignSelection(
      mode: AutopilotDesignMode.fallback,
      designName: '${config.teamName} Colors (Solid)',
      effectId: 0,
      speed: 128,
      intensity: 128,
      brightness: config.brightness,
      colors: colors,
      wledPayload: _buildWledPayload(
        effectId: 0,
        colors: colors,
        speed: 128,
        intensity: 128,
        brightness: config.brightness,
      ),
    );
  }

  /// Check for overlapping games across all enabled configs.
  /// Returns pairs of team slugs that have games at the same time.
  Future<List<({String team1, String team2, DateTime gameTime})>>
      detectConflicts(List<GameDayAutopilotConfig> configs) async {
    final conflicts =
        <({String team1, String team2, DateTime gameTime})>[];

    final upcoming = <String, DateTime>{};
    for (final config in configs) {
      if (!config.enabled) continue;
      final nextGame = await _scheduleService.fetchNextGameDate(
        config.espnTeamId,
        config.sport,
      );
      if (nextGame != null) {
        upcoming[config.teamSlug] = nextGame;
      }
    }

    final slugs = upcoming.keys.toList();
    for (var i = 0; i < slugs.length; i++) {
      for (var j = i + 1; j < slugs.length; j++) {
        final time1 = upcoming[slugs[i]]!;
        final time2 = upcoming[slugs[j]]!;
        // Games within 4 hours of each other are considered overlapping.
        if (time1.difference(time2).abs() < const Duration(hours: 4)) {
          conflicts.add((
            team1: slugs[i],
            team2: slugs[j],
            gameTime: time1,
          ));
        }
      }
    }

    return conflicts;
  }

  void dispose() {
    _postGamePollTimer?.cancel();
    _sessions.clear();
  }

  // ── Internal: Pre-game activation ──────────────────────────────────────

  Future<void> _activatePreGame(
    GameDayAutopilotConfig config,
    DateTime? gameStart,
  ) async {
    _sessions[config.teamSlug] = AutopilotSession(
      teamSlug: config.teamSlug,
      phase: AutopilotSessionPhase.preGame,
      gameStart: gameStart,
    );

    // Select and apply design.
    final design = selectDesign(config);
    _applyDesign(design);
    _notifySessionChanged(config.teamSlug);

    debugPrint('[GameDayAutopilot] Pre-game activated for ${config.teamName}');
  }

  // ── Internal: Active session updates ───────────────────────────────────

  Future<void> _updateActiveSession(
    GameDayAutopilotConfig config,
    AutopilotSession session,
    DateTime now,
  ) async {
    switch (session.phase) {
      case AutopilotSessionPhase.preGame:
        // Check if game has started (ESPN shows in-progress).
        final gameState = await _espnApi.fetchTeamGame(
          config.sport,
          config.espnTeamId,
        );
        if (gameState != null &&
            (gameState.status == GameStatus.inProgress ||
                gameState.status == GameStatus.halftime)) {
          _sessions[config.teamSlug] = session.copyWith(
            phase: AutopilotSessionPhase.liveGame,
            activeGameId: gameState.gameId,
          );
          debugPrint('[GameDayAutopilot] Game started for ${config.teamName}');
          _notifySessionChanged(config.teamSlug);
        }

      case AutopilotSessionPhase.liveGame:
        // Primary: Check if game is final via ESPN.
        final gameState = await _espnApi.fetchTeamGame(
          config.sport,
          config.espnTeamId,
        );

        if (gameState != null && gameState.status == GameStatus.final_) {
          // Game ended — start 30-min countdown.
          final countdownEnd = now.add(const Duration(minutes: 30));
          _sessions[config.teamSlug] = session.copyWith(
            phase: AutopilotSessionPhase.postGame,
            gameEndDetected: now,
            countdownEnd: countdownEnd,
            usedFallbackTimer: false,
          );
          debugPrint('[GameDayAutopilot] Game FINAL for ${config.teamName}, '
              'starting 30-min countdown');
          _notifySessionChanged(config.teamSlug);
          return;
        }

        // Fallback: Check if estimated duration + 60 min buffer exceeded.
        if (session.gameStart != null) {
          final estimatedEnd = session.gameStart!
              .add(config.estimatedDuration)
              .add(const Duration(minutes: 60));
          if (now.isAfter(estimatedEnd)) {
            final countdownEnd = now.add(const Duration(minutes: 30));
            _sessions[config.teamSlug] = session.copyWith(
              phase: AutopilotSessionPhase.postGame,
              gameEndDetected: now,
              countdownEnd: countdownEnd,
              usedFallbackTimer: true,
            );
            debugPrint('[GameDayAutopilot] FALLBACK timer triggered for '
                '${config.teamName} — no live final detected within '
                '${config.estimatedDuration.inMinutes}min + 60min buffer');
            _notifySessionChanged(config.teamSlug);
          }
        }

      case AutopilotSessionPhase.postGame:
        // Check if 30-min countdown has elapsed.
        if (session.countdownEnd != null && now.isAfter(session.countdownEnd!)) {
          _sessions[config.teamSlug] = session.copyWith(
            phase: AutopilotSessionPhase.completed,
          );
          debugPrint('[GameDayAutopilot] Post-game countdown complete for '
              '${config.teamName}, resuming normal schedule');
          onResumeNormalSchedule?.call();
          _notifySessionChanged(config.teamSlug);
        }

      case AutopilotSessionPhase.idle:
      case AutopilotSessionPhase.completed:
        break;
    }
  }

  // ── Internal: WLED payload ─────────────────────────────────────────────

  void _applyDesign(DesignSelection design) {
    onApplyPayload?.call(design.wledPayload);
  }

  Map<String, dynamic> _buildWledPayload({
    required int effectId,
    required List<List<int>> colors,
    required int speed,
    required int intensity,
    required int brightness,
  }) {
    return {
      'on': true,
      'bri': brightness.clamp(0, 255),
      'seg': [
        {
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
          'pal': 0,
          'col': colors.map((c) => [...c, 0]).toList(), // Add W=0 for RGBW
        }
      ],
    };
  }

  void _notifySessionChanged(String teamSlug) {
    final session = _sessions[teamSlug];
    if (session != null) {
      onSessionChanged?.call(session);
    }
  }

  // ── Internal: Style categorization ─────────────────────────────────────

  /// Categorize a user's preferred effect styles into one of three buckets.
  _StyleCategory _categorizeStyles(List<String> styles) {
    int staticScore = 0;
    int motionScore = 0;
    int dynamicScore = 0;

    for (final style in styles) {
      switch (style.toLowerCase()) {
        case 'static':
        case 'solid':
          staticScore += 2;
        case 'animated':
        case 'chase':
        case 'wipe':
        case 'sweep':
          motionScore += 2;
        case 'twinkle':
        case 'pulse':
        case 'rainbow':
        case 'reactive':
          dynamicScore += 2;
        default:
          motionScore += 1; // Unknown styles lean toward motion.
      }
    }

    if (dynamicScore > motionScore && dynamicScore > staticScore) {
      return _StyleCategory.dynamic;
    }
    if (motionScore > staticScore) {
      return _StyleCategory.motion;
    }
    return _StyleCategory.static_;
  }

  List<int> _colorToRgbList(Color color) {
    return [
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
    ];
  }
}

enum _StyleCategory { static_, motion, dynamic }
