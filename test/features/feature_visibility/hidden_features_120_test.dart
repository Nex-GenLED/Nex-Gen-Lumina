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
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    show favoritesFirestoreProvider;
import 'package:nexgen_command/features/feature_visibility.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_screen.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_screen.dart';
import 'package:nexgen_command/features/neighborhood/widgets/neighborhood_onboarding.dart';
import 'package:nexgen_command/features/neighborhood/widgets/game_day_setup_screen.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_game_day_snapshot.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
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

/// The real notifier arms a 5 s delayed evaluation and three periodic timers
/// in build(); the hide tests need its state, not its clock, so this twin
/// returns an empty session map and arms nothing.
class _QuietGameDayNotifier extends GameDayAutopilotNotifier {
  @override
  Map<String, AutopilotSession> build() => const {};
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
    gameDayAutopilotNotifierProvider.overrideWith(() => _QuietGameDayNotifier()),
    upcomingGameProvider.overrideWith((ref, slug) => Stream.value(null)),
    wledRepositoryProvider.overrideWith((ref) => RecordingWledRepository()),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    demoModeProvider.overrideWith((ref) => false),
  ];
}

List<NeighborhoodGroup> _groups() => [
      NeighborhoodGroup(
        id: 'grp-a',
        name: 'Walk Crew',
        inviteCode: 'TESTA1',
        creatorUid: 'customer-a',
        createdAt: DateTime(2026, 9, 1),
        memberUids: const ['customer-a', 'customer-b'],
      ),
    ];

/// The returning-user group list with one group and the onboarding done.
List<Override> _neighborhood({bool onboardingDone = true}) => [
      authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
      currentUserProfileProvider.overrideWith((_) => Stream.value(null)),
      syncEngineControllerProvider.overrideWith((ref) {}),
      userNeighborhoodsProvider.overrideWith((ref) => Stream.value(_groups())),
      neighborhoodMembersProvider
          .overrideWith((ref) => Stream.value(const <NeighborhoodMember>[])),
      activeNeighborhoodProvider.overrideWith((ref) => Stream.value(null)),
      currentUserMemberProvider.overrideWithValue(null),
      isGroupCreatorProvider.overrideWithValue(false),
      previousGroupsProvider.overrideWith((ref) async => const []),
      neighborhoodSyncOnboardingCompleteProvider
          .overrideWith((ref) async => onboardingDone),
    ];

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

/// Disposes the ProviderScope before the binding checks for pending timers:
/// the Game Day notifier and the setup sheet arm periodic timers that only
/// their dispose cancels.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('build 120 visibility flags: defaults', () {
    test('every 120 constant is off and its provider twin reads the const',
        () {
      expect(kGameDayCrewsVisible, isFalse);
      expect(kGroupGameDayBroadcastVisible, isFalse);
      expect(kNeighborhoodDiscoveryVisible, isFalse);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(gameDayCrewsVisibleProvider), kGameDayCrewsVisible);
      expect(c.read(groupGameDayBroadcastVisibleProvider),
          kGroupGameDayBroadcastVisible);
      expect(c.read(neighborhoodDiscoveryVisibleProvider),
          kNeighborhoodDiscoveryVisible);
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
      await _unmount(tester);
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
      await _unmount(tester);
    });
  });

  group('2. "Also broadcast to my neighborhood" hidden', () {
    List<Override> setup() => [
          ..._gameDay(_teams()),
          // One team in the picker so the test taps it without scrolling.
          gameDayFilteredTeamsProvider.overrideWithValue(
              [MapEntry('nfl_packers', kTeamColors['nfl_packers']!)]),
          // The tap resolves the team's Path 1 snapshot with a synchronous
          // read; nothing on step 1 has listened to the configs stream yet,
          // so resolve it directly instead of racing the stream.
          path1GameDaySnapshotResolutionProvider.overrideWith((ref, slug) =>
              Path1SnapshotReady(
                  Path1GameDaySnapshot.fromConfig(_teams().first.config))),
        ];

    Future<void> openStep2(WidgetTester tester, List<Override> ov) async {
      // The sheet is shown inside a Material bottom sheet in the app; pumped
      // bare, newer Flutter reports its ListTile's missing Material ancestor
      // as an error (3.47.5), so give it one here.
      await _pump(tester,
          const Material(child: GameDayPath2Screen(isHost: true)), ov,
          size: const Size(390, 1600));
      // The picker opens on league folders; a search shows flat team rows.
      await tester.enterText(find.byType(TextField).first, 'Packers');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Green Bay Packers').first);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('the host sees no broadcast checkbox on the setup sheet',
        (tester) async {
      await openStep2(tester, setup());
      expect(tester.takeException(), isNull);
      expect(find.text('Also broadcast to my neighborhood'), findsNothing);
      expect(find.text('Sets the group Game Day for opted-in neighbors.'),
          findsNothing);
      // The sheet itself still works: the team is selected.
      expect(find.text('Light it Up Now'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('returns later: with the twin true the checkbox is back',
        (tester) async {
      await openStep2(tester, [
        ...setup(),
        groupGameDayBroadcastVisibleProvider.overrideWithValue(true),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('Also broadcast to my neighborhood'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('3. public listing and Discover Nearby hidden', () {
    Widget onboarding() => NeighborhoodOnboarding(
          onCreateGroup: () {},
          onJoinGroup: () {},
          onFindNearby: () {},
        );

    Future<void> lastPage(WidgetTester tester) async {
      await tester.tap(find.text('Skip to Get Started'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('the onboarding\'s last page has no Discover button',
        (tester) async {
      await _pump(tester, onboarding(), _neighborhood(),
          size: const Size(390, 844));
      await lastPage(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Start a Block Party'), findsOneWidget);
      expect(find.text('Join the Party'), findsOneWidget);
      expect(find.text('Discover Nearby Groups'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('returns later: Discover is back with the twin true',
        (tester) async {
      await _pump(tester, onboarding(), [
        ..._neighborhood(),
        neighborhoodDiscoveryVisibleProvider.overrideWithValue(true),
      ], size: const Size(390, 844));
      await lastPage(tester);
      expect(find.text('Discover Nearby Groups'), findsOneWidget);
      await _unmount(tester);
    });

    Future<void> openCreateDialog(WidgetTester tester) async {
      await tester.tap(find.text('Start a Block Party'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('the create dialog has no Public Group toggle',
        (tester) async {
      await _pump(tester, const NeighborhoodSyncScreen(), _neighborhood(),
          size: const Size(390, 844));
      await openCreateDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Public Group'), findsNothing);
      expect(find.text('Allow nearby neighbors to find and request to join'),
          findsNothing);
      expect(
          find.text('Your approximate location will be used to help '
              'neighbors find your group.'),
          findsNothing);
      await _unmount(tester);
    });

    testWidgets('returns later: the toggle is back with the twin true',
        (tester) async {
      await _pump(tester, const NeighborhoodSyncScreen(), [
        ..._neighborhood(),
        neighborhoodDiscoveryVisibleProvider.overrideWithValue(true),
      ], size: const Size(390, 844));
      await openCreateDialog(tester);
      expect(find.text('Public Group'), findsOneWidget);
      await _unmount(tester);
    });
  });
}
