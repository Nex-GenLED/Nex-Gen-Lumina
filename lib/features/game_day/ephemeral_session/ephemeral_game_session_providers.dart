// lib/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart
//
// Riverpod wiring for the ephemeral one-shot Game Day session service.
// Per-user instance — disposed when the user signs out.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../sports_alerts/services/espn_api_service.dart';
import '../../sports_alerts/services/game_schedule_service.dart';
import 'ephemeral_game_session.dart';
import 'ephemeral_game_session_service.dart';

final _ephemeralEspnApiProvider = Provider<EspnApiService>((ref) {
  final svc = EspnApiService();
  ref.onDispose(svc.dispose);
  return svc;
});

final _ephemeralScheduleServiceProvider = Provider<GameScheduleService>((ref) {
  final svc = GameScheduleService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Per-user ephemeral game session service. Returns null until the user
/// is authenticated.
final ephemeralGameSessionServiceProvider =
    Provider<EphemeralGameSessionService?>((ref) {
  final user = ref.watch(authStateProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );
  if (user == null) return null;

  final svc = EphemeralGameSessionService(
    firestore: FirebaseFirestore.instance,
    ref: ref,
    userId: user.uid,
    espnApi: ref.watch(_ephemeralEspnApiProvider),
    scheduleService: ref.watch(_ephemeralScheduleServiceProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Stream of active (non-completed) ephemeral sessions for the current user.
/// Surfaces empty list when the user is not authenticated.
final activeEphemeralSessionsProvider =
    StreamProvider<List<EphemeralGameSession>>((ref) {
  final svc = ref.watch(ephemeralGameSessionServiceProvider);
  if (svc == null) return Stream.value(const []);
  return svc.watchActiveSessions();
});

/// Item #51 Prompt 4 — the single ephemeral session currently in an active
/// phase ([EphemeralSessionPhase.preGame], [EphemeralSessionPhase.liveGame],
/// or [EphemeralSessionPhase.postGame]). Returns null otherwise (no
/// sessions, or all sessions are still idle waiting for game time).
///
/// At most one session is in active phase at a time per Item #51 design:
/// doubleheader sessions for the same team are scheduled hours apart so
/// they cannot overlap. Used by the home dashboard Game Day button to
/// decide its color treatment and tap target.
final activePhaseSessionProvider = Provider<EphemeralGameSession?>((ref) {
  final sessions = ref.watch(activeEphemeralSessionsProvider).valueOrNull ??
      const <EphemeralGameSession>[];
  for (final session in sessions) {
    if (session.phase == EphemeralSessionPhase.preGame ||
        session.phase == EphemeralSessionPhase.liveGame ||
        session.phase == EphemeralSessionPhase.postGame) {
      return session;
    }
  }
  return null;
});
