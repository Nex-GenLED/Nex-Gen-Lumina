// lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT — phase machine duplication notice:
//
// The phase machine in [_advanceSession] below structurally mirrors
// `GameDayAutopilotService._updateActiveSession` in
// `lib/features/autopilot/game_day_autopilot_service.dart`. This is intentional
// — the existing service is keyed on `teamSlug` only, uses a single shared
// `onResumeNormalSchedule` callback for all sessions, and is driven by a
// Firestore-backed orchestrator that can't accommodate transient one-shot
// sessions without invasive changes (see 2026-05-08 Path A architectural
// finding).
//
// This duplication is tracked as Item #54 in MEMORY.md for future
// consolidation. If the autopilot phase machine evolves (e.g. new transitions,
// different ESPN polling logic, doubleheader handling), keep this one in sync.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../autopilot/game_day_autopilot_config.dart' show estimatedGameDuration;
import '../../sports_alerts/data/team_colors.dart';
import '../../sports_alerts/models/game_state.dart';
import '../../sports_alerts/services/espn_api_service.dart';
import '../../sports_alerts/services/game_schedule_service.dart';
import '../../wled/wled_providers.dart';
import 'ephemeral_game_session.dart';

class EphemeralGameSessionService {
  EphemeralGameSessionService({
    required FirebaseFirestore firestore,
    required Ref ref,
    required String userId,
    required EspnApiService espnApi,
    required GameScheduleService scheduleService,
  })  : _firestore = firestore,
        _ref = ref,
        _userId = userId,
        _espnApi = espnApi,
        _scheduleService = scheduleService {
    // Resume tracking any sessions that were active before the app restarted.
    unawaited(_bootstrap());
  }

  final FirebaseFirestore _firestore;
  final Ref _ref;
  final String _userId;
  final EspnApiService _espnApi;
  final GameScheduleService _scheduleService;

  /// In-memory mirror of active sessions. Keyed by sessionId — multiple
  /// sessions for the same team can coexist (deliberate divergence from
  /// `GameDayAutopilotService` which keys on teamSlug).
  final Map<String, EphemeralGameSession> _sessions = {};

  /// Polling timer. Cadence mirrors `GameDayAutopilotService`'s evaluation
  /// loop (1 minute — see `game_day_autopilot_providers.dart:272`).
  Timer? _evaluationTimer;

  bool _disposed = false;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection('users')
      .doc(_userId)
      .collection('ephemeral_game_sessions');

  // ── Public API ─────────────────────────────────────────────────────────

  /// Create a new ephemeral session pinned to a specific game and persist
  /// it to Firestore. The session starts in [EphemeralSessionPhase.idle];
  /// call [startTracking] to begin the polling-driven phase machine.
  ///
  /// `gameStart` is resolved by fetching the team's season schedule and
  /// filtering to the requested `gameId`.
  ///
  /// Throws [ArgumentError] if `teamSlug` is unknown.
  /// Throws [StateError] if the gameId can't be found in the team's schedule.
  Future<EphemeralGameSession> createSession({
    required String teamSlug,
    required String gameId,
    required Map<String, dynamic> revertWledPayload,
    required String revertLabel,
  }) async {
    final teamInfo = kTeamColors[teamSlug];
    if (teamInfo == null) {
      throw ArgumentError.value(
          teamSlug, 'teamSlug', 'Unknown team slug — not in kTeamColors');
    }

    final games = await _scheduleService.fetchSeasonSchedule(
      espnTeamId: teamInfo.espnTeamId,
      sport: teamInfo.sport,
      season: DateTime.now().year,
      homeGamesOnly: false,
    );
    final game = games.where((g) => g.gameId == gameId).firstOrNull;
    if (game == null) {
      throw StateError(
          'Game $gameId not found in $teamSlug schedule for ${DateTime.now().year}');
    }

    final docRef = _collection.doc();
    final session = EphemeralGameSession(
      sessionId: docRef.id,
      teamSlug: teamSlug,
      gameId: gameId,
      gameStart: game.scheduledDate,
      revertWledPayload: revertWledPayload,
      revertLabel: revertLabel,
      createdAt: DateTime.now(),
    );

    await docRef.set(session.toJson());
    _sessions[session.sessionId] = session;
    debugPrint('[EphemeralSession] Created ${session.sessionId} for '
        '$teamSlug game $gameId starting ${game.scheduledDate}');
    return session;
  }

  /// Begin polling-driven phase tracking for `sessionId`. Idempotent —
  /// safe to call multiple times. After [createSession], the session is
  /// already in the active map; this call simply ensures the timer is up.
  Future<void> startTracking(String sessionId) async {
    if (_disposed) return;
    if (!_sessions.containsKey(sessionId)) {
      // Session not in memory — try to load from Firestore (handles the
      // case where the caller created the session in a previous app run).
      final loaded = await getSession(sessionId);
      if (loaded == null) {
        throw StateError('Session $sessionId not found');
      }
      if (loaded.phase != EphemeralSessionPhase.completed) {
        _sessions[sessionId] = loaded;
      } else {
        return;
      }
    }
    _ensureTimer();
  }

  /// User-initiated cancel. Stops phase-machine tracking for this session
  /// and deletes the Firestore document. Does NOT apply the revert payload.
  Future<void> cancelSession(
    String sessionId, {
    EphemeralCompletedReason reason = EphemeralCompletedReason.cancelledByUser,
  }) async {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      // Still attempt the delete in case the session exists in Firestore
      // but isn't in our in-memory map.
      try {
        await _collection.doc(sessionId).delete();
      } catch (e) {
        debugPrint('[EphemeralSession] cancel: delete miss for $sessionId: $e');
      }
      return;
    }
    try {
      await _collection.doc(sessionId).delete();
    } catch (e) {
      debugPrint('[EphemeralSession] cancel: delete failed for $sessionId: $e');
    }
    debugPrint('[EphemeralSession] Cancelled $sessionId (reason=${reason.name})');
    if (_sessions.isEmpty) {
      _evaluationTimer?.cancel();
      _evaluationTimer = null;
    }
  }

  /// Stream of all non-completed sessions for the current user, sourced
  /// from Firestore so it's consistent with disk-persisted state.
  Stream<List<EphemeralGameSession>> watchActiveSessions() {
    return _collection
        .where('phase',
            isNotEqualTo: EphemeralSessionPhase.completed.toJson())
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) {
              try {
                return EphemeralGameSession.fromJson(doc.data());
              } catch (e) {
                debugPrint(
                    '[EphemeralSession] watch: parse failed for ${doc.id}: $e');
                return null;
              }
            })
            .whereType<EphemeralGameSession>()
            .toList());
  }

  /// One-shot fetch of a session by ID. Returns null if not found.
  Future<EphemeralGameSession?> getSession(String sessionId) async {
    final doc = await _collection.doc(sessionId).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    try {
      return EphemeralGameSession.fromJson(data);
    } catch (e) {
      debugPrint(
          '[EphemeralSession] getSession parse failed for $sessionId: $e');
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _evaluationTimer?.cancel();
    _evaluationTimer = null;
    _sessions.clear();
  }

  // ── Internal: bootstrap from Firestore on app start ─────────────────────

  Future<void> _bootstrap() async {
    try {
      final snap = await _collection
          .where('phase',
              isNotEqualTo: EphemeralSessionPhase.completed.toJson())
          .get();
      for (final doc in snap.docs) {
        try {
          final session = EphemeralGameSession.fromJson(doc.data());
          _sessions[session.sessionId] = session;
        } catch (e) {
          debugPrint(
              '[EphemeralSession] bootstrap: parse failed for ${doc.id}: $e');
        }
      }
      if (_sessions.isNotEmpty) {
        debugPrint(
            '[EphemeralSession] Bootstrapped ${_sessions.length} active session(s)');
        _ensureTimer();
      }
    } catch (e) {
      debugPrint('[EphemeralSession] Bootstrap failed: $e');
    }
  }

  // ── Internal: phase machine ─────────────────────────────────────────────

  void _ensureTimer() {
    if (_disposed) return;
    if (_evaluationTimer?.isActive == true) return;
    _evaluationTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _evaluate());
    debugPrint('[EphemeralSession] Polling timer started (1-min cadence)');
  }

  Future<void> _evaluate() async {
    if (_disposed) return;
    if (_sessions.isEmpty) {
      _evaluationTimer?.cancel();
      _evaluationTimer = null;
      return;
    }
    final now = DateTime.now();
    // Snapshot the values to a list so concurrent mutations during
    // _advanceSession don't break iteration.
    for (final session in List.of(_sessions.values)) {
      if (session.phase == EphemeralSessionPhase.completed) continue;
      try {
        await _advanceSession(session, now);
      } catch (e) {
        debugPrint(
            '[EphemeralSession] _advanceSession failed for ${session.sessionId}: $e');
      }
    }
  }

  /// Single phase-machine step for one session.
  ///
  /// Mirrors `GameDayAutopilotService._updateActiveSession` (see file header).
  Future<void> _advanceSession(
      EphemeralGameSession session, DateTime now) async {
    final teamInfo = kTeamColors[session.teamSlug];
    if (teamInfo == null) return;

    switch (session.phase) {
      case EphemeralSessionPhase.idle:
        // Transition to preGame once we're within 30 min of game start.
        // If game start has already passed (session created mid-game), poll
        // ESPN to see if the game is live or already final.
        final preGameWindowStart =
            session.gameStart.subtract(const Duration(minutes: 30));
        if (!now.isAfter(preGameWindowStart)) return;

        if (now.isAfter(session.gameStart)) {
          final gameState = await _espnApi.fetchTeamGame(
            teamInfo.sport,
            teamInfo.espnTeamId,
          );
          if (gameState != null &&
              gameState.status == GameStatus.final_) {
            await _updatePhase(
              session,
              EphemeralSessionPhase.postGame,
              gameEnd: now,
              countdownEnd: now.add(const Duration(minutes: 30)),
            );
            return;
          }
          if (gameState != null &&
              (gameState.status == GameStatus.inProgress ||
                  gameState.status == GameStatus.halftime)) {
            await _updatePhase(session, EphemeralSessionPhase.liveGame);
            return;
          }
        }
        await _updatePhase(session, EphemeralSessionPhase.preGame);

      case EphemeralSessionPhase.preGame:
        final gameState = await _espnApi.fetchTeamGame(
          teamInfo.sport,
          teamInfo.espnTeamId,
        );
        if (gameState != null &&
            (gameState.status == GameStatus.inProgress ||
                gameState.status == GameStatus.halftime)) {
          await _updatePhase(session, EphemeralSessionPhase.liveGame);
        }

      case EphemeralSessionPhase.liveGame:
        // Primary: ESPN final detection.
        final gameState = await _espnApi.fetchTeamGame(
          teamInfo.sport,
          teamInfo.espnTeamId,
        );
        if (gameState != null && gameState.status == GameStatus.final_) {
          await _updatePhase(
            session,
            EphemeralSessionPhase.postGame,
            gameEnd: now,
            countdownEnd: now.add(const Duration(minutes: 30)),
          );
          return;
        }
        // Fallback: estimated duration + 60-min buffer past game start.
        final estimatedEnd = session.gameStart
            .add(estimatedGameDuration(teamInfo.sport))
            .add(const Duration(minutes: 60));
        if (now.isAfter(estimatedEnd)) {
          await _updatePhase(
            session,
            EphemeralSessionPhase.postGame,
            gameEnd: now,
            countdownEnd: now.add(const Duration(minutes: 30)),
          );
        }

      case EphemeralSessionPhase.postGame:
        if (session.countdownEnd != null &&
            now.isAfter(session.countdownEnd!)) {
          await _handleGameEnd(session.sessionId);
        }

      case EphemeralSessionPhase.completed:
        break;
    }
  }

  /// Persist a phase transition to Firestore and update the in-memory cache.
  Future<void> _updatePhase(
    EphemeralGameSession session,
    EphemeralSessionPhase newPhase, {
    DateTime? gameEnd,
    DateTime? countdownEnd,
  }) async {
    final updated = session.copyWith(
      phase: newPhase,
      gameEnd: gameEnd,
      countdownEnd: countdownEnd,
    );
    _sessions[session.sessionId] = updated;
    try {
      await _collection.doc(session.sessionId).set(updated.toJson());
      debugPrint(
          '[EphemeralSession] ${session.sessionId} ${session.phase.name} → ${newPhase.name}');
    } catch (e) {
      debugPrint(
          '[EphemeralSession] Phase write failed for ${session.sessionId}: $e');
    }
  }

  /// Apply the revert payload, set the active preset label, mark completed,
  /// and delete the session document. Called from the phase machine when the
  /// post-game countdown elapses.
  Future<void> _handleGameEnd(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    // Apply the revert WLED payload.
    try {
      final repo = _ref.read(wledRepositoryProvider);
      if (repo != null) {
        await repo.applyJson(session.revertWledPayload);
        debugPrint(
            '[EphemeralSession] Applied revert payload for $sessionId');
      } else {
        debugPrint(
            '[EphemeralSession] No WLED repo for revert ($sessionId)');
      }
    } catch (e) {
      debugPrint(
          '[EphemeralSession] Revert apply failed for $sessionId: $e');
    }

    // Update the Now Playing label.
    try {
      _ref.read(activePresetLabelProvider.notifier).state =
          session.revertLabel;
    } catch (e) {
      debugPrint(
          '[EphemeralSession] Label set failed for $sessionId: $e');
    }

    // Remove from in-memory cache and delete from Firestore. If delete
    // fails, fall back to writing the completed-state document so the
    // session isn't left dangling in postGame phase forever.
    _sessions.remove(sessionId);
    try {
      await _collection.doc(sessionId).delete();
      debugPrint('[EphemeralSession] Completed and deleted $sessionId');
    } catch (e) {
      debugPrint(
          '[EphemeralSession] Delete failed for $sessionId, falling back to completed-state write: $e');
      try {
        final completed = session.copyWith(
          phase: EphemeralSessionPhase.completed,
          completedReason: EphemeralCompletedReason.gameEnded,
          completedAt: DateTime.now(),
        );
        await _collection.doc(sessionId).set(completed.toJson());
      } catch (e2) {
        debugPrint(
            '[EphemeralSession] Completed-state fallback write also failed: $e2');
      }
    }

    if (_sessions.isEmpty) {
      _evaluationTimer?.cancel();
      _evaluationTimer = null;
    }
  }
}
