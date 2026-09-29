// +110 E1 — the palette tuner (ColorwayEffectSelectorPage).
//
// Row 22: in catalog mode every tile writes live; Back now puts the house back
// (unless Apply was used). Row 93: a restore that fails is reported. Item D:
// a tile starts its effect at the curated roofline speed. Item C: a design
// opened from My Designs can be applied, not only saved.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

const _palette = LibraryNode(
  id: 'ocean_breeze',
  name: 'Ocean Breeze',
  nodeType: LibraryNodeType.palette,
  parentId: 'cat_water',
  themeColors: [Color(0xFF0066FF), Color(0xFFFFFFFF)],
);

ProviderContainer _container(RecordingWledRepository repo) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    demoModeProvider.overrideWith((ref) => false),
    authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// A home page with a button that pushes [page], so Back can pop it.
Future<void> _pumpPushed(
    WidgetTester tester, ProviderContainer c, Widget page) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(appBar: AppBar(), body: page))),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('OPEN'));
  await _frames(tester);
}

/// The tuner animates forever: pump frames rather than settle.
Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await _frames(tester);
}

/// A top-pick tile other than the seed (Solid). ("Chase" is also a motion
/// filter chip; Meteor appears once.)
String get _tile => WledEffectsCatalog.getName(76);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('row 22 — catalog mode', () {
    testWidgets('Back after a live preview puts the previous look back',
        (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo);
      await _pumpPushed(
          tester, c, const ColorwayEffectSelectorPage(paletteNode: _palette));

      await tester.tap(find.text(_tile));
      await _frames(tester, 4);
      expect(repo.applied, hasLength(1), reason: 'the tile previewed live');
      expect(repo.applied.single.containsKey('bri'), isFalse,
          reason: 'a catalog preview leaves the brightness alone');

      await _back(tester);

      expect(repo.applied, hasLength(2), reason: 'Back restored');
      final restore = repo.applied.last;
      final seg = (restore['seg'] as List).cast<Map>().first;
      expect(seg['fx'], kHomeLitState.effectId,
          reason: 'the look the house had before the preview');
      expect(restore['bri'], kHomeLitState.brightness);
    });

    testWidgets('Back without touching anything writes NOTHING', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo);
      await _pumpPushed(
          tester, c, const ColorwayEffectSelectorPage(paletteNode: _palette));
      await _back(tester);
      expect(repo.writeCount, 0);
    });

    testWidgets('after Apply, Back keeps what was applied', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo);
      await _pumpPushed(
          tester, c, const ColorwayEffectSelectorPage(paletteNode: _palette));

      await tester.tap(find.text(_tile));
      await _frames(tester, 4);
      await tester.tap(find.byKey(const ValueKey('apply-design')));
      await _frames(tester);
      final afterApply = repo.applied.length;

      await _back(tester);
      expect(repo.applied.length, afterApply, reason: 'no undo of an Apply');
    });

    testWidgets('item D: a tile starts its effect at the roofline speed',
        (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo);
      await _pumpPushed(
          tester, c, const ColorwayEffectSelectorPage(paletteNode: _palette));

      await tester.tap(find.text(_tile));
      await _frames(tester, 4);

      expect(c.read(selectorSpeedProvider), effectDefaultSpeed(76));
      final seg = (repo.applied.single['seg'] as List).cast<Map>().first;
      expect(seg['sx'], effectDefaultSpeed(76));
      await _back(tester);
    });
  });

  testWidgets('row 93 — a restore that fails says so', (tester) async {
    final repo = RecordingWledRepository();
    final c = _container(repo);
    await _pumpPushed(
      tester,
      c,
      ColorwayEffectSelectorPage(
        paletteNode: _palette,
        saveDestinationLabel: 'schedule',
        onDesignSelected: (_) {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('preview-on-lights')));
    await _frames(tester, 4);
    expect(repo.applied, isNotEmpty);
    repo.succeed = false; // away from home, the relay refuses the restore

    await tester.tap(find.byKey(const ValueKey('save-design')));
    await _frames(tester);

    expect(c.read(wledCommandFailureProvider)?.message, kRestoreFailedMessage);
  });

  testWidgets('item C — a design opened from My Designs has Apply; it '
      'applies the design and Back does not undo it', (tester) async {
    final repo = RecordingWledRepository();
    final c = _container(repo);
    final design = CustomDesign(
      id: 'd1',
      name: 'Blue Chase',
      createdAt: DateTime(2026, 9, 29),
      updatedAt: DateTime(2026, 9, 29),
      ownerId: 'customer-test',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [0, 0, 255, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
          grouping: 3,
          solidLayout: SolidLayout.blocks,
        ),
      ],
      brightness: 150,
      brightnessStated: true,
      tags: const [kPatternEditorDesignTag],
    );
    await _pumpPushed(
        tester, c, ColorwayEffectSelectorPage.forDesign(design: design));

    expect(find.byKey(const ValueKey('save-to-design')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('apply-design')));
    await _frames(tester);

    final sent = repo.applied.single;
    final seg = (sent['seg'] as List).cast<Map>().firstWhere((s) => s['fx'] != null);
    expect(seg['fx'], 28);
    expect(seg['sx'], 44);
    expect(seg['ix'], 90);
    expect(seg['grp'], 3);
    expect(sent['bri'], 150, reason: "the design's own stated level");
    expect(c.read(activePresetLabelProvider), 'Blue Chase');

    await _back(tester);
    expect(repo.applied, hasLength(1), reason: 'Apply is not undone');
  });
}
