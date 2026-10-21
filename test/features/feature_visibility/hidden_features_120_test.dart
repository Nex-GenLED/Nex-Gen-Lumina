// Build 120 hides, on top of the 119 ones: features whose screens promise
// behaviour that has no working path yet are compiled out of reach without
// deleting code or data. Each constant in feature_visibility.dart says what
// must be true before it flips back. These tests pin the hidden (flag-off)
// rendering and the "returns later" path through the Provider twins.
//
// Synthetic accounts only ("customer A").

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    show favoritesFirestoreProvider;
import 'package:nexgen_command/features/feature_visibility.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_screen.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'customer-a';
}

GameDayAutopilotConfig _team(String slug, String name, int p, int s,
        {bool enabled = false}) =>
    GameDayAutopilotConfig(
      teamSlug: slug,
      teamName: name,
      espnTeamId: '9',
      sport: SportType.nfl,
      primaryColorValue: p,
      secondaryColorValue: s,
      enabled: enabled,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

List<GameDayTeamEntry> _teams() => [
      GameDayTeamEntry(
          config: _team('nfl_packers', 'Green Bay Packers', 0xFF203731, 0xFFFFB612,
              enabled: true)),
    ];

List<Override> _gameDay(List<GameDayTeamEntry> entries) {
  final db = FakeFirebaseFirestore();
  return [
    authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
    currentUserProfileProvider.overrideWith((_) => Stream.value(null)),
    favoritesFirestoreProvider.overrideWithValue(db),
    gameDayFirestoreProvider.overrideWithValue(db),
    ephemeralGameSessionServiceProvider.overrideWithValue(null),
    gameDayTeamsProvider.overrideWithValue(entries),
    gameDayAutopilotConfigsProvider
        .overrideWith((_) => Stream.value([for (final e in entries) e.config])),
    gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
    gameDayTeamPriorityProvider.overrideWithValue(const []),
    gameDayTeamPriorityHealProvider.overrideWithValue(null),
    upcomingGameProvider.overrideWith((ref, slug) => Stream.value(null)),
    wledRepositoryProvider.overrideWith((ref) => RecordingWledRepository()),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    demoModeProvider.overrideWith((ref) => false),
  ];
}

Future<void> _pump(WidgetTester tester, Widget page, List<Override> overrides,
    {Size size = const Size(390, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: nexGenPremiumDarkTheme,
      home: page,
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('build 120 visibility flags: defaults', () {
    test('every 120 constant is off and its provider twin reads the const',
        () {
      expect(kGameDayCrewsVisible, isFalse);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(gameDayCrewsVisibleProvider), kGameDayCrewsVisible);
    });
  });

  group('1. Game Day crews hidden', () {
    testWidgets('no Join a Crew card and no Create Crew row on the Game Day '
        'screen', (tester) async {
      await _pump(tester, const GameDayScreen(), _gameDay(_teams()));
      expect(tester.takeException(), isNull);
      // SectionHeader renders its title upper-cased.
      expect(find.text('JOIN A CREW'), findsNothing);
      expect(find.text('Have an invite code from a neighbor?'), findsNothing);
      expect(find.text('Share with neighbors'), findsNothing);
      expect(find.text('Create Crew'), findsNothing);
      // The headline Game Day paths stay: the team card and its switches.
      expect(find.textContaining('Green Bay Packers'), findsWidgets);
      expect(find.text('Autopilot'), findsWidgets);
      expect(find.text('Live Scoring'), findsWidgets);
    });

    testWidgets('returns later: with the twin true the card and row are back',
        (tester) async {
      await _pump(tester, const GameDayScreen(), [
        ..._gameDay(_teams()),
        gameDayCrewsVisibleProvider.overrideWithValue(true),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('JOIN A CREW'), findsOneWidget);
      expect(find.text('Have an invite code from a neighbor?'), findsOneWidget);
      expect(find.text('Create Crew'), findsOneWidget);
    });
  });
}
