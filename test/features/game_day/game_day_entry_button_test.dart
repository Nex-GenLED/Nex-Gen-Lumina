// The home-screen Game Day tile must never be blocked by a stale session.
//
// Device, 2026-09-25: tapping Game Day opened a "Post-Game" sheet for a
// bench game from the night before, and the Game Day screen (team selector)
// was unreachable from the home screen. These pin the three parts of the fix:
//
//   1. an expired session does not route the tile to the sheet;
//   2. the sheet, when it IS shown, links on to the Game Day screen and
//      offers "End session", which clears the persisted state;
//   3. an expired session found at launch is ignored by the UI and finalised
//      by the service without applying its revert payload.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/active_session_sheet.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_entry_button.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kUid = 'test-user';
const kSlug = 'nfl_packers';

/// The next morning after the bench game.
final kNow = DateTime(2026, 9, 25, 9, 0);

class _FakeUser extends Fake implements User {
  @override
  String get uid => kUid;
}

/// No network in tests: the live phase asks ESPN and gets "no game".
class _OfflineEspn extends EspnApiService {
  @override
  Future<GameState?> fetchTeamGame(SportType sport, String espnTeamId) async =>
      null;
}

/// The bench session: kicked off 7:15 pm on the 24th, final noticed 10:40 pm,
/// countdown to 11:10 pm — and nothing ever cleared it.
EphemeralGameSession stalePostGame() => EphemeralGameSession(
      sessionId: 's-stale',
      teamSlug: kSlug,
      gameId: 'g-stale',
      gameStart: DateTime(2026, 9, 24, 19, 15),
      gameEnd: DateTime(2026, 9, 24, 22, 40),
      revertWledPayload: const {'on': true, 'bri': 90},
      revertLabel: 'Normal Blue',
      createdAt: DateTime(2026, 9, 24, 18, 0),
      phase: EphemeralSessionPhase.postGame,
      countdownEnd: DateTime(2026, 9, 24, 23, 10),
    );

/// A game in progress right now.
EphemeralGameSession liveNow() => EphemeralGameSession(
      sessionId: 's-live',
      teamSlug: kSlug,
      gameId: 'g-live',
      gameStart: kNow.subtract(const Duration(hours: 1)),
      revertWledPayload: const {'on': true, 'bri': 90},
      revertLabel: 'Normal Blue',
      createdAt: kNow.subtract(const Duration(hours: 2)),
      phase: EphemeralSessionPhase.liveGame,
    );

/// A tiny app: the tile on /dashboard, a placeholder selector on
/// /dashboard/game-day (AppRoutes.gameDay).
GoRouter _router() => GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(
            body: Row(children: [GameDayEntryButton()]),
          ),
          routes: [
            GoRoute(
              path: 'game-day',
              builder: (_, __) => const Scaffold(body: Text('SELECTOR')),
            ),
          ],
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ephemeralSessionClockProvider.overrideWithValue(() => kNow),
      ...overrides,
    ],
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await tester.pumpAndSettle();
}

DocumentReference<Map<String, dynamic>> _doc(
        FakeFirebaseFirestore db, String id) =>
    db
        .collection('users')
        .doc(kUid)
        .collection('ephemeral_game_sessions')
        .doc(id);

Future<void> _seed(FakeFirebaseFirestore db, EphemeralGameSession s) =>
    _doc(db, s.sessionId).set(UserService.sanitizeForFirestore(s.toJson()));

List<Override> _serviceOverrides(FakeFirebaseFirestore db) => [
      authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
      ephemeralSessionFirestoreProvider.overrideWithValue(db),
      ephemeralEspnApiProvider.overrideWithValue(_OfflineEspn()),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a stale post-game session', () {
    testWidgets('does not block navigation to the selector', (tester) async {
      await _pump(tester, [
        ephemeralGameSessionServiceProvider.overrideWithValue(null),
        activeEphemeralSessionsProvider
            .overrideWith((_) => Stream.value([stalePostGame()])),
      ]);

      await tester.tap(find.text('Game Day'));
      await tester.pumpAndSettle();

      expect(find.text('SELECTOR'), findsOneWidget,
          reason: 'the tile must open the Game Day screen, not a sheet for '
              'last night\'s game');
      expect(find.byType(ActiveSessionSheet), findsNothing);
    });

    testWidgets('does not paint the tile in team colours', (tester) async {
      await _pump(tester, [
        ephemeralGameSessionServiceProvider.overrideWithValue(null),
        activeEphemeralSessionsProvider
            .overrideWith((_) => Stream.value([stalePostGame()])),
      ]);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(GameDayEntryButton)));
      expect(container.read(activePhaseSessionProvider), isNull);
    });
  });

  group('a live session', () {
    testWidgets('shows the sheet, and the sheet reaches the selector',
        (tester) async {
      await _pump(tester, [
        ephemeralGameSessionServiceProvider.overrideWithValue(null),
        activeEphemeralSessionsProvider
            .overrideWith((_) => Stream.value([liveNow()])),
      ]);

      await tester.tap(find.text('Game Day'));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveSessionSheet), findsOneWidget);
      expect(find.text('End session'), findsOneWidget);
      expect(find.text('Open Game Day'), findsOneWidget);

      await tester.tap(find.text('Open Game Day'));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveSessionSheet), findsNothing);
      expect(find.text('SELECTOR'), findsOneWidget);
    });

    testWidgets('End session clears the persisted state', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, liveNow());
      // The background worker's arming for the team (the SharedPreferences
      // store "Light Up Now" writes) must go with the session.
      await registerManualGameDaySession(teamSlug: kSlug);
      expect((await loadGameDaySessions()).containsKey(kSlug), isTrue);

      await _pump(tester, _serviceOverrides(db));

      await tester.tap(find.text('Game Day'));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveSessionSheet), findsOneWidget);

      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();

      expect((await _doc(db, 's-live').get()).exists, isFalse,
          reason: 'the session document must be deleted');
      expect((await loadGameDaySessions()).containsKey(kSlug), isFalse,
          reason: 'the team must be disarmed for celebrations');
      expect(find.text('Session ended'), findsOneWidget);
      expect(find.byType(ActiveSessionSheet), findsNothing);

      // Tear the app down so the service's polling timer is cancelled.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('an expired session at launch', () {
    testWidgets('is ignored by the tile and finalised without a revert',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, stalePostGame());
      await registerManualGameDaySession(teamSlug: kSlug);

      await _pump(tester, _serviceOverrides(db));
      // Let the service bootstrap (fake Firestore resolves in microtasks).
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(GameDayEntryButton)));
      expect(container.read(activePhaseSessionProvider), isNull);

      expect((await _doc(db, 's-stale').get()).exists, isFalse,
          reason: 'bootstrap finalises an expired session instead of '
              'adopting it into the phase machine');
      expect((await loadGameDaySessions()).containsKey(kSlug), isFalse,
          reason: 'expiry disarms the team like a natural end does');

      await tester.tap(find.text('Game Day'));
      await tester.pumpAndSettle();
      expect(find.text('SELECTOR'), findsOneWidget);
      expect(find.byType(ActiveSessionSheet), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a CURRENT session at launch is adopted, not finalised',
        (tester) async {
      // The counter-case: expiry must not eat a session whose game is on.
      final db = FakeFirebaseFirestore();
      await _seed(db, liveNow());

      await _pump(tester, _serviceOverrides(db));
      await tester.pumpAndSettle();

      expect((await _doc(db, 's-live').get()).exists, isTrue);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(GameDayEntryButton)));
      expect(container.read(activePhaseSessionProvider)?.sessionId, 's-live');

      await tester.pumpWidget(const SizedBox());
    });
  });
}
