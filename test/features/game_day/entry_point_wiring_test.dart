// Entry-point wiring — every test here starts from the REAL entry control,
// never by pumping the new widget directly (device-verified misses on the
// 2.5.10+109 candidate, 2026-09-28).
//
//   1. The real Game Day screen's "Add a Team" opens the league-folder picker
//      (NFL and NCAA Football separate, in kGameDayPickerLeagueOrder).
//   2. The real My Favorites "+" opens the library in SAVE mode: the leaf
//      shows "Save to Favorites" (and no "Apply"); Save writes a favorite and
//      issues no controller command.
//   3. The real Game Day team card's "Alerts" row opens its sheet through the
//      branch navigator under the real dock, and the sheet's last row clears
//      the dock.
//   4. The Game Day design-picker route target runs the library in SAVE
//      mode ("Save to Game Day").
//
// What is faked: Firestore-backed data (teams, favorites, gate status,
// profile), the WLED repository (recording fake), the ESPN game stream, and
// the catalog tree behind the library browser (a three-level stub so the
// drill-down is short). Everything the user touches is the production widget.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    hide FavoritePattern;
import 'package:nexgen_command/models/usage_analytics_models.dart'
    show FavoritePattern;
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_design_save.dart';
import 'package:nexgen_command/features/game_day/game_day_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_screen.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/game_day/team_picker_folders.dart';
import 'package:nexgen_command/features/game_day/team_picker_sheet.dart';
import 'package:nexgen_command/features/installer/connection_method_resolver.dart';
import 'package:nexgen_command/features/installer/handoff_screen.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/neighborhood/widgets/game_day_setup_screen.dart';
import 'package:nexgen_command/features/site/connection_method.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/sports_alerts/services/team_registration_service.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/your_teams_screen.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';
import 'package:nexgen_command/widgets/navigation/nav_bar_inset.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kUid = 'test-user';
const kSlug = 'nfl_packers';
const double kSafeBottom = 34;
const Size kScreen = Size(390, 844);

class _FakeUser extends Fake implements User {
  @override
  String get uid => kUid;
}

/// Records every controller write; everything else is a no-op.
class _RecordingRepo implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  Future<Map<String, dynamic>?> getState() async => null;
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const [];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

class _SeededWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => const WledStateModel(
        isOn: true,
        brightness: 111,
        speed: 88,
        intensity: 99,
        color: Color(0xFF0A141E),
        connected: true,
        warmWhite: 0,
        supportsRgbw: false,
        effectId: 7,
        paletteId: 3,
        colorGroupSize: 2,
        spacing: 3,
        colorSequence: [Color(0xFF0A141E)],
      );
}

GameDayAutopilotConfig _packers({bool enabled = false}) =>
    GameDayAutopilotConfig(
      teamSlug: kSlug,
      teamName: 'Green Bay Packers',
      espnTeamId: '9',
      sport: SportType.nfl,
      primaryColorValue: 0xFF203731,
      secondaryColorValue: 0xFFFFB612,
      enabled: enabled,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

/// A three-level stub of the catalog: Sports → NFL → one palette. The real
/// browser, grid, cards and selector run on top of it.
const _sportsCat = LibraryNode(
  id: LibraryCategoryIds.sports,
  name: 'Game Day Fan Zone',
  nodeType: LibraryNodeType.category,
);
const _nflFolder = LibraryNode(
  id: LeagueFolderIds.nfl,
  name: 'NFL',
  nodeType: LibraryNodeType.folder,
  parentId: LibraryCategoryIds.sports,
);
const _packersPalette = LibraryNode(
  id: 'team_nfl_packers',
  name: 'Green Bay Packers',
  nodeType: LibraryNodeType.palette,
  parentId: LeagueFolderIds.nfl,
  themeColors: [Color(0xFF203731), Color(0xFFFFB612)],
);
const _byId = <String, LibraryNode>{
  LibraryCategoryIds.sports: _sportsCat,
  LeagueFolderIds.nfl: _nflFolder,
  'team_nfl_packers': _packersPalette,
};

List<Override> _libraryOverrides() => [
      libraryChildNodesProvider.overrideWith((ref, parentId) async {
        if (parentId == null) return const [_sportsCat];
        if (parentId == LibraryCategoryIds.sports) return const [_nflFolder];
        if (parentId == LeagueFolderIds.nfl) return const [_packersPalette];
        return const [];
      }),
      libraryNodeByIdProvider.overrideWith((ref, id) async => _byId[id]),
      libraryAncestorsProvider.overrideWith((ref, id) async => const []),
      designsStreamProvider.overrideWith((_) => Stream.value(const [])),
    ];

List<Override> _deviceOverrides(_RecordingRepo repo) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledStateProvider.overrideWith(_SeededWledNotifier.new),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
      demoModeProvider.overrideWith((ref) => false),
    ];

List<Override> _accountOverrides(FakeFirebaseFirestore db) => [
      authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
      currentUserProfileProvider.overrideWith((_) => Stream.value(null)),
      favoritesFirestoreProvider.overrideWithValue(db),
      gameDayFirestoreProvider.overrideWithValue(db),
      ephemeralGameSessionServiceProvider.overrideWithValue(null),
    ];

List<Override> _gameDayOverrides(List<GameDayTeamEntry> entries) => [
      gameDayTeamsProvider.overrideWithValue(entries),
      gameDayAutopilotConfigsProvider.overrideWith(
          (_) => Stream.value([for (final e in entries) e.config])),
      gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
      gameDayTeamPriorityProvider.overrideWithValue(const []),
      gameDayTeamPriorityHealProvider.overrideWithValue(null),
      upcomingGameProvider.overrideWith((ref, slug) => Stream.value(null)),
    ];

void _useDevice(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = kScreen;
  tester.view.padding = const FakeViewPadding(bottom: kSafeBottom);
  tester.view.viewPadding = const FakeViewPadding(bottom: kSafeBottom);
  addTearDown(tester.view.reset);
}

/// A few explicit frames. Dock and catalog cards animate continuously, so
/// pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Mounts [page] the way MainScaffold mounts a tab: its own Navigator (the
/// branch navigator) under the real glass dock inside the shell inset.
Future<void> _pumpInShell(
    WidgetTester tester, ProviderContainer container, Widget page) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: NavBarInsetShell(
          navBar: GlassDockNavBar(index: 0, onTap: (_) {}),
          body: Navigator(
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => page),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: '"$text" must be on screen');
  await tester.ensureVisible(f.first);
  await tester.tap(f.first, warnIfMissed: false);
  await _settle(tester);
}

/// Unreachable-controller resolver for HandoffScreen (the same shape the
/// handoff verification tests use); the team section does not touch it.
class _NoControllersResolver implements ConnectionMethodResolver {
  @override
  Future<ConnectionMethod> probe(ControllerInfo c) async =>
      ConnectionMethod.unknown;
  @override
  Future<ConnectionMethod?> probeOrNull(ControllerInfo c) async => null;
  @override
  Future<ClockHealth?> probeClockOrNull(ControllerInfo c) async => null;
  @override
  Future<bool> disableWifi(ControllerInfo c) async => true;
  @override
  Future<bool> waitForOffline(ControllerInfo c,
          {Duration pollWindow = const Duration(seconds: 10)}) async =>
      true;
  @override
  Future<bool> isReachable(ControllerInfo c) async => false;
  @override
  Future<void> persist(ControllerInfo c, ConnectionMethod m) async {}
}

/// Asserts the shared picker's root is on screen: league folders in
/// kGameDayPickerLeagueOrder (NFL and NCAA Football separate and adjacent)
/// and none of the old sport chips.
void _expectLeagueFolderRoot(WidgetTester tester) {
  expect(find.byType(GameDayTeamPickerSheet), findsOneWidget);
  for (final old in ['Football', 'Basketball', 'Baseball', 'Hockey']) {
    expect(find.text(old), findsNothing, reason: 'old chip "$old"');
  }
  final ids = find
      .byWidgetPredicate((w) =>
          w is ListTile &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('folder_'))
      .evaluate()
      .map((e) => ((e.widget as ListTile).key as ValueKey<String>)
          .value
          .substring('folder_'.length))
      .toList();
  expect(ids, kGameDayPickerLeagueOrder);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. Game Day screen → "Add a Team"', () {
    testWidgets('opens the league-folder picker, NFL and NCAA Football apart',
        (tester) async {
      _useDevice(tester);
      final db = FakeFirebaseFirestore();
      final container = ProviderContainer(overrides: [
        ..._accountOverrides(db),
        ..._gameDayOverrides(const []),
        ..._deviceOverrides(_RecordingRepo()),
      ]);
      addTearDown(container.dispose);
      await _pumpInShell(tester, container, const GameDayScreen());

      // The real control on the real screen.
      await _tapText(tester, 'Add a Team');

      expect(find.byType(GameDayTeamPickerSheet), findsOneWidget,
          reason: '"Add a Team" must open the league-folder picker');
      // The flat sport chips are gone.
      for (final old in ['Football', 'Basketball', 'Baseball', 'Hockey']) {
        expect(find.text(old), findsNothing, reason: 'old chip "$old"');
      }
      // League folders, college beside pro, in kGameDayPickerLeagueOrder.
      final folderRows = find.byWidgetPredicate((w) =>
          w is ListTile && w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('folder_'));
      final ids = folderRows
          .evaluate()
          .map((e) => ((e.widget as ListTile).key as ValueKey<String>).value
              .substring('folder_'.length))
          .toList();
      expect(ids, kGameDayPickerLeagueOrder);
      expect(find.widgetWithText(ListTile, 'NFL'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'NCAA Football'), findsOneWidget);
      expect(ids.indexOf(LeagueFolderIds.ncaaFootball),
          ids.indexOf(LeagueFolderIds.nfl) + 1,
          reason: 'NCAA Football sits directly after NFL');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('2. My Favorites "+"', () {
    FavoritePattern seedFavorite() => FavoritePattern(
          id: 'existing',
          patternName: 'Existing',
          addedAt: DateTime(2026, 9, 1),
          usageCount: 1,
          patternData: const {'on': true},
        );

    Future<ProviderContainer> pumpFavorites(
        WidgetTester tester, _RecordingRepo repo, FakeFirebaseFirestore db,
        {required List<FavoritePattern> favorites}) async {
      final container = ProviderContainer(overrides: [
        ..._accountOverrides(db),
        ..._deviceOverrides(repo),
        ..._libraryOverrides(),
        favoriteWhiteSlotsProvider.overrideWith((_) => const []),
        userFavoritePatternsProvider
            .overrideWith((_) => Stream.value(favorites)),
      ]);
      addTearDown(container.dispose);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: FavoritesGrid())),
        ),
      ));
      await _settle(tester);
      return container;
    }

    /// From the "+" through the real browser, grid and card to the leaf.
    Future<void> drillToLeaf(WidgetTester tester) async {
      await _tapText(tester, 'Game Day Fan Zone');
      await _tapText(tester, 'NFL');
      await _tapText(tester, 'Green Bay Packers');
      await _settle(tester, 10);
      expect(find.byType(ColorwayEffectSelectorPage), findsOneWidget,
          reason: 'the palette leaf is the effect selector');
    }

    testWidgets('the "+" slot opens the library in SAVE-to-Favorites mode; '
        'Save writes a favorite and issues no controller command',
        (tester) async {
      final repo = _RecordingRepo();
      final db = FakeFirebaseFirestore();
      await pumpFavorites(tester, repo, db, favorites: [seedFavorite()]);

      // The real "+" tile — there is exactly ONE, whatever the number of
      // favourites (+110 E1, owner item A: no row of empty slots).
      final plus = find.byKey(const ValueKey('favorites-add-tile'));
      expect(plus, findsOneWidget);
      await tester.tap(plus);
      await _settle(tester);

      await drillToLeaf(tester);
      expect(find.text('Save to Favorites'), findsOneWidget);
      expect(find.text('Preview on lights'), findsOneWidget);
      expect(find.text('Apply'), findsNothing,
          reason: 'entered from "+", the leaf must not offer Apply');

      await _tapText(tester, 'Save to Favorites');
      await _settle(tester, 10);

      final favs = await db.collection('users/$kUid/favorites').get();
      expect(favs.size, 1, reason: 'the chosen design was saved');
      expect(favs.docs.single.data()['pattern_name'],
          contains('Green Bay Packers'));
      expect(repo.applyJsonCalls, isEmpty,
          reason: 'nothing may reach the controller on Save');
      expect(find.byType(ColorwayEffectSelectorPage), findsNothing,
          reason: 'Save returns');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with no favourites at all, the one "+" says what it does and '
        'opens the same SAVE-mode library', (tester) async {
      final repo = _RecordingRepo();
      final db = FakeFirebaseFirestore();
      await pumpFavorites(tester, repo, db, favorites: const []);

      await _tapText(tester, 'Add a favorite — pick any look from the library');
      await drillToLeaf(tester);
      expect(find.text('Save to Favorites'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
      expect(repo.applyJsonCalls, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('3. Game Day card → "Alerts" sheet', () {
    // Pinned on a large phone with a home indicator AND on the smallest
    // supported phone (375×667, no inset) at default and enlarged text. The
    // small phone is where the 9/16 modal-sheet cap, with the dock band
    // counted against it, used to paint the last option under the dock.
    const devices = <({String name, Size size, double safe, double text})>[
      (name: '390x844, 34 inset, 1.0x text', size: Size(390, 844), safe: 34, text: 1.0),
      (name: '375x667, no inset, 1.0x text', size: Size(375, 667), safe: 0, text: 1.0),
      (name: '375x667, no inset, 1.3x text', size: Size(375, 667), safe: 0, text: 1.3),
    ];
    for (final d in devices) {
      testWidgets(
          'opens under the real dock and its last option clears it '
          '(${d.name})', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = d.size;
        tester.view.padding = FakeViewPadding(bottom: d.safe);
        tester.view.viewPadding = FakeViewPadding(bottom: d.safe);
        tester.platformDispatcher.textScaleFactorTestValue = d.text;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final db = FakeFirebaseFirestore();
        final entry = GameDayTeamEntry(config: _packers(enabled: true));
        final container = ProviderContainer(overrides: [
          ..._accountOverrides(db),
          ..._gameDayOverrides([entry]),
          ..._deviceOverrides(_RecordingRepo()),
        ]);
        addTearDown(container.dispose);
        await _pumpInShell(tester, container, const GameDayScreen());

        // The dock's real top edge, as laid out on this device.
        final dockTop = tester.getRect(find.byType(GlassDockNavBar)).top;

        // The real row on the real card (autopilot enabled → Alerts shown).
        // Scroll it clear of the dock band first: the dock is above the page
        // in z-order, so a row left under it would hand the tap to the dock.
        final alerts = find.text('Alerts');
        // +114: the "who runs Game Day" banner now sits above the cards, so
        // on the smallest phone at 1.3x the row starts below the built area
        // of the lazy list. Scroll until it exists, then pin as before.
        for (var i = 0; i < 8 && alerts.evaluate().isEmpty; i++) {
          await tester.drag(
              find.byType(CustomScrollView), const Offset(0, -120));
          await _settle(tester, 2);
        }
        expect(alerts, findsOneWidget);
        await tester.ensureVisible(alerts);
        await _settle(tester, 3);
        for (var i = 0;
            i < 8 && tester.getRect(alerts).bottom > dockTop;
            i++) {
          await tester.drag(
              find.byType(CustomScrollView), const Offset(0, -120));
          await _settle(tester, 2);
        }
        expect(tester.getRect(alerts).bottom, lessThanOrEqualTo(dockTop));
        await tester.tap(alerts);
        await _settle(tester);

        expect(find.text('Alert Sensitivity'), findsOneWidget,
            reason: 'the sensitivity sheet is open');
        final lastRow = find.widgetWithText(ListTile, 'Clutch Only');
        expect(lastRow, findsOneWidget);
        expect(tester.getRect(lastRow).bottom,
            lessThanOrEqualTo(dockTop + 0.5),
            reason: 'the sheet\'s last option must sit fully above the dock');

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('4. Game Day design picker route target', () {
    testWidgets('runs the library in SAVE-to-Game-Day mode', (tester) async {
      final repo = _RecordingRepo();
      final db = FakeFirebaseFirestore();
      final container = ProviderContainer(overrides: [
        ..._accountOverrides(db),
        ..._deviceOverrides(repo),
        ..._libraryOverrides(),
        gameDayAutopilotConfigsProvider
            .overrideWith((_) => Stream.value([_packers()])),
      ]);
      addTearDown(container.dispose);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: GameDayDesignPickerScreen(
              nodeId: 'team_nfl_packers', teamSlug: kSlug),
        ),
      ));
      await _settle(tester, 10);

      expect(find.byType(ColorwayEffectSelectorPage), findsOneWidget);
      expect(find.text('Save to Game Day'), findsOneWidget);
      expect(find.text('Preview on lights'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
      expect(repo.applyJsonCalls, isEmpty,
          reason: 'opening the picker must not touch the controller');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('5. Installer handoff "Favorite Teams" → "Add a team"', () {
    testWidgets('opens the shared picker; a picked team becomes a chip whose '
        'name resolves exactly for the install commit', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          controllersStreamProvider
              .overrideWith((ref) => Stream.value(const <ControllerInfo>[])),
          installerSelectedControllersProvider
              .overrideWith((ref) => const <String>{}),
          installerConnectionMethodsProvider
              .overrideWith((ref) => const <String, ConnectionMethod>{}),
          installerConnectionMethodSkippedProvider
              .overrideWith((ref) => const <String>{}),
          connectionMethodResolverProvider
              .overrideWithValue(_NoControllersResolver()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: HandoffScreen()),
        ),
      ));
      await _settle(tester);

      // The real button in the real "Favorite Teams" section.
      final add = find.byKey(const ValueKey('installer-add-team'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await _settle(tester);
      _expectLeagueFolderRoot(tester);

      await _tapText(tester, 'NFL');
      await tester.tap(find.byKey(const ValueKey('team_nfl_packers')));
      await _settle(tester, 2);
      await tester.tap(find.byKey(const ValueKey('team-picker-done')));
      await _settle(tester);

      expect(find.byType(GameDayTeamPickerSheet), findsNothing);
      expect(
          find.byKey(const ValueKey('installer-team-Green Bay Packers')),
          findsOneWidget);
      // The install commit turns names into Game Day teams through this
      // resolver; a picked name must resolve to exactly the picked team.
      expect(
          TeamRegistrationService.resolveFreeTextToKTeamSlug(
              'Green Bay Packers'),
          kSlug);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('6. Commercial onboarding "Your Teams" → "Add a team"', () {
    testWidgets('opens the shared picker; a picked team joins the draft',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: YourTeamsScreen(onNext: () {})),
        ),
      ));
      await _settle(tester);
      bool hasPackers() => container
          .read(commercialOnboardingProvider)
          .teams
          .any((t) => t.teamName == 'Green Bay Packers');
      expect(hasPackers(), isFalse,
          reason: 'precondition: not among the location suggestions');

      final add = find.byKey(const ValueKey('commercial-add-team'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await _settle(tester);
      _expectLeagueFolderRoot(tester);

      await _tapText(tester, 'NFL');
      await tester.tap(find.byKey(const ValueKey('team_nfl_packers')));
      await _settle(tester, 2);
      await tester.tap(find.byKey(const ValueKey('team-picker-done')));
      await _settle(tester);

      expect(hasPackers(), isTrue);
      expect(find.text('Green Bay Packers'), findsOneWidget,
          reason: 'the team list renders the new team');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('7. Neighborhood Game Day setup, step 1', () {
    testWidgets('renders the shared picker instead of per-league chips',
        (tester) async {
      _useDevice(tester);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameDayPath2Screen()),
      ));
      await _settle(tester);
      _expectLeagueFolderRoot(tester);
      expect(find.text('ALL'), findsNothing, reason: 'old "ALL" chip');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
