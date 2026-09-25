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
import 'ephemeral_session_expiry.dart';

/// ESPN client the session phase machine polls. Public so tests can stub the
/// network away; production never overrides it.
final ephemeralEspnApiProvider = Provider<EspnApiService>((ref) {
  final svc = EspnApiService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Season-schedule client used to resolve a game id at session creation.
final ephemeralScheduleServiceProvider = Provider<GameScheduleService>((ref) {
  final svc = GameScheduleService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// The Firestore instance the session documents live in. The body only runs
/// when read, so a test that overrides it never touches Firebase.
final ephemeralSessionFirestoreProvider =
    Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);

/// The clock every ephemeral-session reader uses. Overridden in tests so
/// "is this session stale?" can be asked at a chosen instant.
final ephemeralSessionClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);

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
    firestore: ref.watch(ephemeralSessionFirestoreProvider),
    ref: ref,
    userId: user.uid,
    espnApi: ref.watch(ephemeralEspnApiProvider),
    scheduleService: ref.watch(ephemeralScheduleServiceProvider),
    now: ref.watch(ephemeralSessionClockProvider),
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
/// A session past its expiry (ephemeral_session_expiry.dart) is never
/// returned, whatever its stored phase says: a stored `postGame` from last
/// night's game is not an active session, and the home-screen Game Day
/// button must route to the Game Day screen, not to a sheet for it. The
/// service finalises such a session on its next sweep; until then the UI
/// simply does not see it.
///
/// At most one session is in active phase at a time per Item #51 design:
/// doubleheader sessions for the same team are scheduled hours apart so
/// they cannot overlap. Used by the home dashboard Game Day button to
/// decide its color treatment and tap target.
final activePhaseSessionProvider = Provider<EphemeralGameSession?>((ref) {
  final now = ref.watch(ephemeralSessionClockProvider)();
  final sessions = ref.watch(activeEphemeralSessionsProvider).valueOrNull ??
      const <EphemeralGameSession>[];
  for (final session in sessions) {
    if (!session.phase.isActive) continue;
    if (isEphemeralSessionExpired(session, now)) continue;
    return session;
  }
  return null;
});
