// lib/features/game_day/ephemeral_session/ephemeral_game_session.dart
//
// Data model for one-shot, time-bounded "Mode 3" Game Day sessions.
//
// An ephemeral session lives only until the resolved game ends + 30-min
// countdown completes, then it's deleted from Firestore. Independent of
// GameDayAutopilotConfig — does NOT subscribe the user to all future games
// for the team and does NOT mutate the user profile's sports priority list.
//
// Persisted at /users/{uid}/ephemeral_game_sessions/{sessionId} so the
// phase machine resumes after app restart.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle phases for an ephemeral one-shot game session.
///
/// Structurally mirrors `AutopilotSessionPhase` in
/// `lib/features/autopilot/game_day_autopilot_service.dart`. Defined as a
/// parallel enum (rather than imported) so the two systems can evolve
/// independently. See Item #54 in MEMORY.md for future consolidation.
enum EphemeralSessionPhase {
  /// Session created; waiting for the pre-game window (30 min before start).
  idle,

  /// Within 30 min of game start. Lights are already on the team design
  /// (applied by the caller before session creation).
  preGame,

  /// ESPN reports the game is in progress (or halftime).
  liveGame,

  /// Game ended (ESPN final, or estimated-duration fallback). 30-min
  /// countdown is running before the revert payload is applied.
  postGame,

  /// Countdown elapsed; revert payload applied; session deleted from
  /// Firestore. This phase is rarely observed since the document is
  /// removed immediately on completion.
  completed;

  String toJson() => name;

  static EphemeralSessionPhase fromJson(String json) =>
      EphemeralSessionPhase.values.firstWhere(
        (e) => e.name == json,
        orElse: () => EphemeralSessionPhase.idle,
      );
}

/// Why a session reached [EphemeralSessionPhase.completed].
enum EphemeralCompletedReason {
  /// Game ended naturally (ESPN final or fallback timer).
  gameEnded,

  /// User explicitly cancelled the session.
  cancelledByUser,

  /// An error prevented normal completion.
  error;

  String toJson() => name;

  static EphemeralCompletedReason fromJson(String json) =>
      EphemeralCompletedReason.values.firstWhere(
        (e) => e.name == json,
        orElse: () => EphemeralCompletedReason.error,
      );
}

/// One-shot, time-bounded game session with an auto-revert payload.
class EphemeralGameSession {
  /// Firestore document ID. Auto-generated at creation time.
  final String sessionId;

  /// Team slug from `kTeamColors` (e.g. `mlb_royals`).
  final String teamSlug;

  /// ESPN event ID this session is pinned to.
  final String gameId;

  /// Scheduled game start time (UTC), resolved from ESPN at creation.
  final DateTime gameStart;

  /// Game end time (UTC) when known. Set when the phase machine detects
  /// the game has ended via ESPN final or the fallback timer.
  final DateTime? gameEnd;

  /// WLED JSON payload to apply when the game ends + countdown completes.
  final Map<String, dynamic> revertWledPayload;

  /// Display label for the revert state (e.g. "Normal Blue").
  final String revertLabel;

  /// When this session was created.
  final DateTime createdAt;

  /// Current phase in the session lifecycle.
  final EphemeralSessionPhase phase;

  /// When [phase] transitioned to [EphemeralSessionPhase.postGame], the
  /// 30-min countdown end-time. Null in earlier phases.
  final DateTime? countdownEnd;

  /// Why the session completed. Null until [phase] is [EphemeralSessionPhase.completed].
  final EphemeralCompletedReason? completedReason;

  /// When the session reached [EphemeralSessionPhase.completed].
  final DateTime? completedAt;

  const EphemeralGameSession({
    required this.sessionId,
    required this.teamSlug,
    required this.gameId,
    required this.gameStart,
    this.gameEnd,
    required this.revertWledPayload,
    required this.revertLabel,
    required this.createdAt,
    this.phase = EphemeralSessionPhase.idle,
    this.countdownEnd,
    this.completedReason,
    this.completedAt,
  });

  EphemeralGameSession copyWith({
    DateTime? gameEnd,
    EphemeralSessionPhase? phase,
    DateTime? countdownEnd,
    EphemeralCompletedReason? completedReason,
    DateTime? completedAt,
  }) {
    return EphemeralGameSession(
      sessionId: sessionId,
      teamSlug: teamSlug,
      gameId: gameId,
      gameStart: gameStart,
      gameEnd: gameEnd ?? this.gameEnd,
      revertWledPayload: revertWledPayload,
      revertLabel: revertLabel,
      createdAt: createdAt,
      phase: phase ?? this.phase,
      countdownEnd: countdownEnd ?? this.countdownEnd,
      completedReason: completedReason ?? this.completedReason,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'team_slug': teamSlug,
        'game_id': gameId,
        'game_start': Timestamp.fromDate(gameStart),
        if (gameEnd != null) 'game_end': Timestamp.fromDate(gameEnd!),
        // JSON-STRING ENCODED — this field CRASHED THE APP natively.
        //
        // revertWledPayload is a verbatim `/json/state` read off the
        // controller, so it always contains `seg[].col: [[r,g,b,w], ...]` —
        // directly-nested arrays, which Firestore does not support. The iOS
        // SDK does not return an error for that: FSTUserDataReader raises
        // NSInvalidArgumentException -> objc_exception_throw -> abort, an
        // EXC_CRASH/SIGABRT that NO Dart try/catch and no Flutter error
        // handler can intercept. Confirmed by crash incident
        // 51AD90DC-5A9F-4F34-B34C-FB70F82D04B2 on 2.5.10(321).
        //
        // Encoding to an opaque String is the same treatment
        // `saved_design_payload` already uses (game_day_autopilot_config.dart)
        // and the pattern user_service.dart's sanitizer explicitly points at:
        // "Upstream fix is to jsonEncode the offending field."
        'revert_wled_payload': jsonEncode(revertWledPayload),
        'revert_label': revertLabel,
        'created_at': Timestamp.fromDate(createdAt),
        'phase': phase.toJson(),
        if (countdownEnd != null)
          'countdown_end': Timestamp.fromDate(countdownEnd!),
        if (completedReason != null)
          'completed_reason': completedReason!.toJson(),
        if (completedAt != null)
          'completed_at': Timestamp.fromDate(completedAt!),
      };

  factory EphemeralGameSession.fromJson(Map<String, dynamic> json) {
    return EphemeralGameSession(
      sessionId: json['session_id'] as String,
      teamSlug: json['team_slug'] as String,
      gameId: json['game_id'] as String,
      gameStart: (json['game_start'] as Timestamp).toDate(),
      gameEnd: (json['game_end'] as Timestamp?)?.toDate(),
      revertWledPayload: _decodeRevertPayload(json['revert_wled_payload']),
      revertLabel: json['revert_label'] as String,
      createdAt: (json['created_at'] as Timestamp).toDate(),
      phase: EphemeralSessionPhase.fromJson(
          json['phase'] as String? ?? 'idle'),
      countdownEnd: (json['countdown_end'] as Timestamp?)?.toDate(),
      completedReason: json['completed_reason'] != null
          ? EphemeralCompletedReason.fromJson(
              json['completed_reason'] as String)
          : null,
      completedAt: (json['completed_at'] as Timestamp?)?.toDate(),
    );
  }
}

/// Decodes `revert_wled_payload`, tolerating BOTH storage shapes.
///
/// NEW (post-crash-fix): a `jsonEncode`d String. See the note in [toJson].
///
/// LEGACY: a raw Map. Kept deliberately rather than assumed impossible — the
/// native abort that motivated this fix is the iOS Firestore codec's
/// behaviour, and a document written from a platform whose codec accepted the
/// nested array would still be a Map on read. A stored doc must never be able
/// to crash the reader.
///
/// Anything else (or malformed JSON) decodes to an empty map: the revert then
/// no-ops rather than throwing inside a session-restore path.
Map<String, dynamic> _decodeRevertPayload(Object? raw) {
  if (raw is String) {
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Fall through — a corrupt blob must not take out the session read.
    }
    return <String, dynamic>{};
  }
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}
