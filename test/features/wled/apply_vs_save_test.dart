// Apply vs Save — the four contracts of the design library (2026-09-25).
//
//   (a) Save from Favorites "+" writes a favorite and issues NO controller
//       command.
//   (b) Game Day Save updates the plan, and the card's Design row shows the
//       saved name + effect derived from that plan.
//   (c) Game Day "Preview on lights" issues a controller command and leaves
//       the plan unchanged.
//   (d) Explore Apply issues a controller command and persists nothing.
//
// These drive the REAL ColorwayEffectSelectorPage with the recording fake
// repository the other selector tests use, and fake Firestore for the two
// persistence destinations. No live controller.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/favorites/favorites_picker.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_config_row.dart';
import 'package:nexgen_command/features/game_day/game_day_design_write.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kUid = 'test-user';
const kSlug = 'nfl_packers';

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
  _SeededWledNotifier(this._seed);
  final WledStateModel _seed;
  @override
  WledStateModel build() => _seed;
}

const _seed = WledStateModel(
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

const _palette = LibraryNode(
  id: 'ocean_breeze',
  name: 'Ocean Breeze',
  nodeType: LibraryNodeType.palette,
  parentId: 'cat_water',
  themeColors: [Color(0xFF0066FF)],
);

List<Override> _overrides(_RecordingRepo repo, FakeFirebaseFirestore db) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledStateProvider.overrideWith(() => _SeededWledNotifier(_seed)),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
      demoModeProvider.overrideWith((ref) => false),
      authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
      favoritesFirestoreProvider.overrideWithValue(db),
    ];

/// Mounts the selector; [onDesignSelected] may need the widget's context, so
/// it is built inside the tree.
Future<void> _pumpSelector(
  WidgetTester tester,
  ProviderContainer container, {
  void Function(LibraryDesignSelection) Function(BuildContext)? save,
  String? destination,
  int? initialEffectId,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ColorwayEffectSelectorPage(
            paletteNode: _palette,
            onDesignSelected: save?.call(ctx),
            saveDestinationLabel: destination,
            initialEffectId: initialEffectId,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

GameDayAutopilotConfig _packers() => GameDayAutopilotConfig(
      teamSlug: kSlug,
      teamName: 'Green Bay Packers',
      espnTeamId: '9',
      sport: SportType.nfl,
      primaryColorValue: 0xFF203731,
      secondaryColorValue: 0xFFFFB612,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

DocumentReference<Map<String, dynamic>> _planDoc(FakeFirebaseFirestore db) =>
    db.collection('users').doc(kUid).collection('game_day_autopilot').doc(kSlug);

Future<int> _favoritesCount(FakeFirebaseFirestore db) async =>
    (await db.collection('users/$kUid/favorites').get()).size;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('(a) Save from Favorites "+" writes a favorite and issues no '
      'controller command', (tester) async {
    final repo = _RecordingRepo();
    final db = FakeFirebaseFirestore();
    final container = ProviderContainer(overrides: _overrides(repo, db));
    addTearDown(container.dispose);

    await _pumpSelector(tester, container,
        destination: 'Favorites',
        save: (ctx) => favoritesSaveHandler(ctx, container));

    expect(find.text('Save to Favorites'), findsOneWidget);
    expect(find.text('Apply'), findsNothing,
        reason: 'the Favorites picker is SAVE mode; Apply is not offered');

    await tester.tap(find.text('Save to Favorites'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await _favoritesCount(db), 1,
        reason: 'one favorite written');
    final fav =
        (await db.collection('users/$kUid/favorites').get()).docs.single;
    expect(fav.id, 'ocean_breeze_fx0');
    expect(fav.data()['pattern_name'], contains('Ocean Breeze'));
    expect(repo.applyJsonCalls, isEmpty,
        reason: 'saving a favorite must not touch the controller');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('(b) Game Day Save updates the plan and the card shows the '
      'saved name + effect', (tester) async {
    final repo = _RecordingRepo();
    final db = FakeFirebaseFirestore();
    await _planDoc(db).set(_packers().toFirestore());
    final container = ProviderContainer(overrides: _overrides(repo, db));
    addTearDown(container.dispose);

    // Before: the default plan reads "<Team> Running" (effect 52) while the
    // picker used to open on Solid — the reported mismatch.
    final before = GameDayAutopilotConfig.fromFirestore(
        (await _planDoc(db).get()).data()!);
    expect(before.designLabel, 'Green Bay Packers Running');

    await _pumpSelector(tester, container,
        destination: 'Game Day',
        save: (_) => (s) => writeGameDayDesign(db,
            uid: kUid,
            teamSlug: kSlug,
            designName: s.baseName,
            wledPayload: s.wledPayload));

    await tester.tap(find.text('Save to Game Day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final data = (await _planDoc(db).get()).data()!;
    expect(data['design_mode'], 'saved');
    expect(data['saved_design_name'], 'Ocean Breeze',
        reason: 'the palette name is stored WITHOUT an effect suffix');
    final after = GameDayAutopilotConfig.fromFirestore(data);
    expect(after.savedDesignPayload, isNotNull);
    // ONE representation: the summary effect equals the payload's fx.
    expect(after.effectId, after.effectiveEffectId);
    expect(after.designLabel, 'Ocean Breeze - Solid',
        reason: 'the label is derived from the stored payload');

    // The card's Design row renders that label.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GameDayConfigRow(
          icon: Icons.palette_outlined,
          label: 'Design',
          value: after.designLabel,
        ),
      ),
    ));
    expect(find.text('Ocean Breeze - Solid'), findsOneWidget);
    expect(find.text('Green Bay Packers Running'), findsNothing);
    expect(repo.applyJsonCalls, isEmpty,
        reason: 'saving to Game Day must not touch the controller');
  });

  testWidgets('(c) Game Day "Preview on lights" issues a controller command '
      'and leaves the plan unchanged', (tester) async {
    final repo = _RecordingRepo();
    final db = FakeFirebaseFirestore();
    await _planDoc(db).set(_packers().toFirestore());
    final planBefore = (await _planDoc(db).get()).data()!;
    final container = ProviderContainer(overrides: _overrides(repo, db));
    addTearDown(container.dispose);

    var saves = 0;
    await _pumpSelector(tester, container,
        destination: 'Game Day', save: (_) => (_) => saves++);

    await tester.tap(find.byKey(const ValueKey('preview-on-lights')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.applyJsonCalls, isNotEmpty,
        reason: 'the preview is the one control that writes to the device');
    expect(saves, 0);
    final planAfter = (await _planDoc(db).get()).data()!;
    expect(planAfter['saved_design_payload'],
        planBefore['saved_design_payload']);
    expect(planAfter['design_mode'], planBefore['design_mode']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('(d) Explore Apply issues a controller command and persists '
      'nothing', (tester) async {
    final repo = _RecordingRepo();
    final db = FakeFirebaseFirestore();
    await _planDoc(db).set(_packers().toFirestore());
    final container = ProviderContainer(overrides: _overrides(repo, db));
    addTearDown(container.dispose);

    await _pumpSelector(tester, container); // APPLY mode: no destination

    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Save…'), findsOneWidget,
        reason: 'Save is offered as the secondary action');

    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.applyJsonCalls, isNotEmpty);
    expect(await _favoritesCount(db), 0);
    final plan = (await _planDoc(db).get()).data()!;
    expect(plan['design_mode'], isNot('saved'));
    expect(plan['saved_design_payload'], isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('the plan write derives its summary fields from the payload', () {
    final update = gameDayDesignUpdate(
      designName: 'Ocean Breeze',
      wledPayload: {
        'on': true,
        'bri': 180,
        'seg': [
          {'fx': 83, 'sx': 40, 'ix': 200, 'col': [[0, 102, 255, 0]]},
        ],
      },
      // Overrides only fill gaps; they cannot contradict the payload.
      effectId: 0,
      speed: 128,
    );
    expect(update['effect_id'], 83);
    expect(update['speed'], 40);
    expect(update['intensity'], 200);
    expect(update['brightness'], 180);
    expect(update['saved_design_name'], 'Ocean Breeze');
  });

  test('a legacy "<palette> - <raw effect>" name yields a payload-true label',
      () {
    final config = _packers().copyWith(
      savedDesignName: 'Ocean Breeze - Solid',
      savedDesignPayload: {
        'seg': [
          {'fx': 83}
        ]
      },
    );
    expect(config.designLabel, 'Ocean Breeze - Pattern',
        reason: 'the stale " - Solid" suffix is replaced by the payload fx');
  });
}
