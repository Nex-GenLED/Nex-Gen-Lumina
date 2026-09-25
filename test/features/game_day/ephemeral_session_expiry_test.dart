// A Game Day session must end on its own.
//
// The bug (device, 2026-09-25): a bench "Light Up Now" session for a game
// on 2026-09-24 was still `postGame` the next morning. The phase machine
// only runs while the app is open, every timestamp it stores is "when the app
// noticed", and nothing bounded the session by the GAME. The home tile
// trusted the stored phase and opened the session sheet for a finished game.
//
// These pin the bound (ephemeral_session_expiry.dart) and the reader that
// applies it (activePhaseSessionProvider).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_session_expiry.dart';

/// The bench game: an NFL kickoff at 7:15 pm on the 24th.
final kKickoff = DateTime(2026, 9, 24, 19, 15);

/// The next morning, when the tile was tapped.
final kNextMorning = DateTime(2026, 9, 25, 9, 0);

EphemeralGameSession _session({
  String id = 's1',
  String slug = 'nfl_packers',
  DateTime? gameStart,
  DateTime? gameEnd,
  EphemeralSessionPhase phase = EphemeralSessionPhase.postGame,
  DateTime? countdownEnd,
}) =>
    EphemeralGameSession(
      sessionId: id,
      teamSlug: slug,
      gameId: 'g-$id',
      gameStart: gameStart ?? kKickoff,
      gameEnd: gameEnd,
      revertWledPayload: const {'on': true, 'bri': 128},
      revertLabel: 'Normal Blue',
      createdAt: (gameStart ?? kKickoff).subtract(const Duration(hours: 1)),
      phase: phase,
      countdownEnd: countdownEnd,
    );

void main() {
  group('the game-end estimate', () {
    // NFL: 3 h 30 estimated + the 60-minute live buffer → 11:45 pm.
    final scheduleEstimate = DateTime(2026, 9, 24, 23, 45);

    test('with no recorded end is start + estimated duration + buffer', () {
      expect(ephemeralGameEndEstimate(_session()), scheduleEstimate);
    });

    test('a recorded end EARLIER than the estimate wins (real-time final)',
        () {
      final finalWhistle = DateTime(2026, 9, 24, 22, 30);
      expect(ephemeralGameEndEstimate(_session(gameEnd: finalWhistle)),
          finalWhistle);
    });

    test('a recorded end LATER than the estimate is capped by it', () {
      // The app was closed at the whistle and only "noticed" the final on
      // the next launch. That timestamp is not when the game ended.
      final noticedNextMorning = DateTime(2026, 9, 25, 9, 0);
      expect(ephemeralGameEndEstimate(_session(gameEnd: noticedNextMorning)),
          scheduleEstimate);
    });

    test('an unknown slug still gets a finite estimate', () {
      final s = _session(slug: 'xyz_not_a_team');
      expect(
          ephemeralGameEndEstimate(s),
          kKickoff
              .add(kEphemeralUnknownSportDuration)
              .add(kEphemeralLiveGameBuffer));
    });
  });

  group('expiry', () {
    test('is the estimate plus the grace window', () {
      expect(ephemeralSessionExpiresAt(_session()),
          DateTime(2026, 9, 24, 23, 45).add(kEphemeralSessionGrace));
    });

    test('the grace is long enough for the designed post-game revert', () {
      expect(kEphemeralSessionGrace, greaterThan(kEphemeralPostGameCountdown));
    });

    test('a session is NOT expired during and shortly after its game', () {
      final s = _session(phase: EphemeralSessionPhase.liveGame);
      expect(isEphemeralSessionExpired(s, DateTime(2026, 9, 24, 21, 0)),
          isFalse);
      expect(isEphemeralSessionExpired(s, DateTime(2026, 9, 25, 0, 30)),
          isFalse);
    });

    test('a session IS expired the next morning — the reported bug', () {
      expect(isEphemeralSessionExpired(_session(), kNextMorning), isTrue);
    });

    test('the boundary is inclusive', () {
      final s = _session();
      final at = ephemeralSessionExpiresAt(s);
      expect(isEphemeralSessionExpired(s, at.subtract(const Duration(minutes: 1))),
          isFalse);
      expect(isEphemeralSessionExpired(s, at), isTrue);
    });
  });

  group('activePhaseSessionProvider', () {
    Future<EphemeralGameSession?> readAt(
      DateTime now,
      List<EphemeralGameSession> stored,
    ) async {
      final container = ProviderContainer(overrides: [
        ephemeralSessionClockProvider.overrideWithValue(() => now),
        activeEphemeralSessionsProvider
            .overrideWith((_) => Stream.value(stored)),
      ]);
      addTearDown(container.dispose);
      // Let the stream deliver before asking.
      await container.read(activeEphemeralSessionsProvider.future);
      return container.read(activePhaseSessionProvider);
    }

    test('ignores an expired postGame session (stored phase says active)',
        () async {
      expect(await readAt(kNextMorning, [_session()]), isNull);
    });

    test('ignores an expired liveGame session too', () async {
      expect(
          await readAt(kNextMorning,
              [_session(phase: EphemeralSessionPhase.liveGame)]),
          isNull);
    });

    test('returns a current active session', () async {
      final live = _session(phase: EphemeralSessionPhase.liveGame);
      final found = await readAt(DateTime(2026, 9, 24, 21, 0), [live]);
      expect(found?.sessionId, live.sessionId);
    });

    test('an idle session waiting for game time is not active', () async {
      expect(
          await readAt(DateTime(2026, 9, 24, 12, 0),
              [_session(phase: EphemeralSessionPhase.idle)]),
          isNull);
    });

    test('a stale session ahead of a current one does not shadow it',
        () async {
      final stale = _session(id: 'old');
      final tonight = _session(
        id: 'new',
        gameStart: DateTime(2026, 9, 25, 8, 0),
        phase: EphemeralSessionPhase.liveGame,
      );
      final found = await readAt(kNextMorning, [stale, tonight]);
      expect(found?.sessionId, 'new');
    });
  });
}
