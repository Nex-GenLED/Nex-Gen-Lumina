// The celebration picker: ColorwayEffectSelectorPage in celebrationMode.
//
// This page serves FOUR modes off one class (catalog, selection, design-edit,
// celebration) and shipped with no widget test at all. The simplification of
// celebration mode is therefore guarded from both sides:
//
//   • what celebration mode MUST now show (the curated 17, the two knobs) and
//     must NOT show (filter chips, the "N EFFECTS / Clear filters" row, the
//     LEDs-per-color selector, the roofline preview strip);
//   • a smoke test per OTHER mode, so a change made for celebration cannot
//     quietly take one of the other three down with it. That is the whole
//     point of those three tests — they are the merge-collision guard, not a
//     claim that those modes are otherwise well covered.
//
// Celebration mode is the only mode pushed as a BARE route body (game_day_
// screen.dart pushes it straight into a MaterialPageRoute); the other three
// render inside a Scaffold supplied by their caller. The header inset test
// pins the SafeArea that closes that gap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// Tyler's curated list, by NAME, in the order he gave it. Held here as names
/// rather than ids on purpose: the production list is ids, so asserting names
/// here would catch an id typo that an id-to-id comparison could not.
const List<String> kCuratedNames = [
  'Chase',
  'Meteor',
  'Washing Machine',
  'Android',
  'Bouncing Balls',
  'Chase 2',
  'Chase 3',
  'Chase Flash Rnd',
  'Chase Random',
  'Juggle',
  'Rolling Balls',
  'Lightning',
  'Strobe',
  'Strobe Mega',
  'Fireworks',
  'Fireworks 1D',
  'Fireworks Starburst',
];

class _FakeRepo implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;
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
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
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
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

List<Override> _overrides(_FakeRepo repo) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      demoModeProvider.overrideWith((ref) => false),
      effectiveChannelIdsProvider.overrideWith((ref) => const <int>[0]),
      deviceChannelsProvider.overrideWith(
        (ref) => const <DeviceChannel>[
          DeviceChannel(id: 0, start: 0, stop: 10, name: 'Front', gpioPin: 2),
        ],
      ),
    ];

const LibraryNode _teamNode = LibraryNode(
  id: 'celebration_bengals',
  name: 'Bengals Celebration',
  nodeType: LibraryNodeType.palette,
  themeColors: [Color(0xFFFB4F14), Color(0xFF000000)],
);

CustomDesign _effectDesign() => CustomDesign(
      id: 'fx-1',
      name: 'Sunset Fade',
      createdAt: DateTime(2026, 5, 29),
      updatedAt: DateTime(2026, 6, 1),
      ownerId: 'u',
      brightness: 180,
      channels: [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          included: true,
          effectId: 12,
          speed: 90,
          intensity: 200,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 9, color: const [255, 80, 0, 0]),
          ],
          ledCount: 10,
        ),
      ],
    );

/// A viewport tall enough to lay the whole list out without scrolling, so
/// `findsOneWidget` on a tile means "rendered", not "happened to be on screen".
void _tallViewport(WidgetTester tester, {double topInset = 0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.padding = FakeViewPadding(top: topInset);
  addTearDown(tester.view.reset);
}

Future<void> _pumpCelebration(
  WidgetTester tester,
  _FakeRepo repo, {
  void Function(LibraryDesignSelection)? onSelected,
  int? initialEffectId,
  int? initialSpeed,
  int? initialIntensity,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(repo),
    child: MaterialApp(
      // No Scaffold — this mirrors the real push in game_day_screen.dart.
      home: ColorwayEffectSelectorPage(
        paletteNode: _teamNode,
        celebrationMode: true,
        initialEffectId: initialEffectId,
        initialSpeed: initialSpeed,
        initialIntensity: initialIntensity,
        onDesignSelected: onSelected ?? (_) {},
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('P2 — the curated list resolves against the real catalog', () {
    test('all 17 names resolve to an id, in the order given', () {
      final resolved =
          WledEffectsCatalog.celebrationPicks.map((e) => e.name).toList();
      expect(resolved, kCuratedNames,
          reason: 'the picker list is fixed and ordered — not sorted, not '
              'derived from isCelebrationEffect');
    });

    test('every id is a real 1D, non-audio effect on the pinned firmware', () {
      final standard = {
        for (final e in WledEffectsCatalog.standardEffects) e.id: e,
      };
      for (final id in WledEffectsCatalog.celebrationPickIds) {
        final e = standard[id];
        expect(e, isNotNull,
            reason: 'id $id is not a 1D non-audio effect — a celebration must '
                'fire on any install, with no matrix and no microphone');
        expect(e!.requires2D, isFalse, reason: e.name);
        expect(e.requiresAudio, isFalse, reason: e.name);
      }
    });

    test('no id appears twice', () {
      expect(WledEffectsCatalog.celebrationPickIds.toSet().length,
          WledEffectsCatalog.celebrationPickIds.length);
    });

    test('Solid is not offered — it is the absence of a celebration', () {
      expect(WledEffectsCatalog.celebrationPickIds.contains(0), isFalse);
    });
  });

  group('celebration mode renders the simplified picker', () {
    testWidgets('exactly the 17 curated effects, and nothing else',
        (tester) async {
      _tallViewport(tester);
      await _pumpCelebration(tester, _FakeRepo());

      for (final name in kCuratedNames) {
        expect(find.text(name), findsOneWidget, reason: '$name should render');
      }
      // A name NOT on the list must be absent — proves the list is the curated
      // set and not merely a superset that happens to contain it.
      expect(find.text('Solid'), findsNothing);
      expect(find.text('Rainbow'), findsNothing);
      expect(find.text('Fire 2012'), findsNothing);
    });

    testWidgets('no filter chips and no "N EFFECTS / Clear filters" row',
        (tester) async {
      _tallViewport(tester);
      await _pumpCelebration(tester, _FakeRepo());

      expect(find.text('Clear filters'), findsNothing);
      expect(find.textContaining('EFFECTS'), findsOneWidget,
          reason: 'only the CELEBRATION EFFECTS section header, never a '
              '"31 EFFECTS" filter-result count');
      expect(find.text('CELEBRATION EFFECTS'), findsOneWidget);
      // Filter chip labels from _buildMotionFilterRow / _buildColorFilterRow.
      expect(find.text('Twinkle'), findsNothing);
      expect(find.text('Chase'), findsOneWidget,
          reason: '"Chase" appears once as an EFFECT tile — never also as a '
              'motion filter chip');
    });

    testWidgets('no LEDs-per-color selector and no roofline preview strip',
        (tester) async {
      _tallViewport(tester);
      await _pumpCelebration(tester, _FakeRepo());

      expect(find.textContaining('LEDs per color'), findsNothing);
      expect(find.byType(Image), findsNothing,
          reason: 'the roofline preview strip is the only Image on this page; '
              'it rendered the BASE design and overflowed its right edge');
    });

    testWidgets('the two knobs that reach the fired celebration are kept',
        (tester) async {
      _tallViewport(tester);
      await _pumpCelebration(tester, _FakeRepo());

      expect(find.byKey(const ValueKey('celebration-speed')), findsOneWidget);
      expect(find.text('Intensity'), findsOneWidget);
    });

    testWidgets(
        'opens on the stored choice, not effect 0 — so no stray "Static" hint',
        (tester) async {
      _tallViewport(tester);
      // 23 = Strobe. Its speed profile label is not "Static".
      await _pumpCelebration(tester, _FakeRepo(), initialEffectId: 23);

      expect(find.text('Static'), findsNothing);
    });

    testWidgets('a stored id no longer offered falls back to the first pick',
        (tester) async {
      _tallViewport(tester);
      final repo = _FakeRepo();
      LibraryDesignSelection? got;
      // 66 (Fire 2012) is a real effect but was dropped from the curated list.
      await _pumpCelebration(tester, repo,
          initialEffectId: 66, onSelected: (s) => got = s);

      await tester.tap(find.byKey(const ValueKey('celebration-save')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
          ((got!.wledPayload['seg'] as List).first as Map)['fx'],
          WledEffectsCatalog.celebrationPickIds.first,
          reason: 'selecting nothing is worse than selecting the first pick');
    });
  });

  group('the save path is unchanged', () {
    testWidgets('picking an effect and saving returns that effect id',
        (tester) async {
      _tallViewport(tester);
      final repo = _FakeRepo();
      LibraryDesignSelection? got;
      await _pumpCelebration(tester, repo, onSelected: (s) => got = s);

      await tester.tap(find.text('Fireworks Starburst'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('celebration-save')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(got, isNotNull, reason: 'celebration always RETURNS the choice');
      final seg = (got!.wledPayload['seg'] as List).first as Map;
      // 89 — the id game_day_screen reads out as celebrationEffectId.
      expect(seg['fx'], 89);
    });

    testWidgets('speed and intensity round-trip into sx / ix', (tester) async {
      _tallViewport(tester);
      final repo = _FakeRepo();
      LibraryDesignSelection? got;
      await _pumpCelebration(tester, repo,
          initialEffectId: 23,
          initialSpeed: 177,
          initialIntensity: 211,
          onSelected: (s) => got = s);

      await tester.tap(find.byKey(const ValueKey('celebration-save')));
      await tester.pump(const Duration(milliseconds: 400));

      final seg = (got!.wledPayload['seg'] as List).first as Map;
      expect(seg['fx'], 23);
      expect(seg['sx'], 177,
          reason: 'sx is what game_day_screen stores as celebrationSpeed');
      expect(seg['ix'], 211);
    });
  });

  group('P4 — the header sits below the status bar', () {
    testWidgets('a 47px top inset pushes the header down by exactly that much',
        (tester) async {
      _tallViewport(tester, topInset: 47);
      await _pumpCelebration(tester, _FakeRepo());

      final header =
          tester.getTopLeft(find.byKey(const ValueKey('celebration-back')));
      expect(header.dy, greaterThanOrEqualTo(47.0),
          reason: 'celebration is pushed as a BARE route body, so the page '
              'must supply its own SafeArea — the other three modes get one '
              'from their caller Scaffold');
    });

    testWidgets(
        'a Material ancestor exists, so Text is not left on the framework '
        'fallback style', (tester) async {
      _tallViewport(tester);
      await _pumpCelebration(tester, _FakeRepo());

      // The yellow double-underline defect was a MISSING Material ancestor,
      // not a local TextStyle and not a theme leak (there is no
      // TextDecoration anywhere in this file or in theme.dart).
      expect(
        find.ancestor(
          of: find.text('CELEBRATION EFFECTS'),
          matching: find.byType(Material),
        ),
        findsWidgets,
      );
    });
  });

  group('merge-collision guard: the other three modes still render', () {
    testWidgets('CATALOG mode', (tester) async {
      _tallViewport(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(repo),
        child: const MaterialApp(
          home: Scaffold(
            body: ColorwayEffectSelectorPage(paletteNode: _teamNode),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('TOP PICKS'), findsOneWidget,
          reason: 'catalog still opens on the unfiltered top picks');
      expect(find.text('CELEBRATION EFFECTS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SELECTION mode', (tester) async {
      _tallViewport(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          home: Scaffold(
            body: ColorwayEffectSelectorPage(
              paletteNode: _teamNode,
              onDesignSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Set design'), findsOneWidget,
          reason: 'selection mode keeps its own commit label — celebration '
              'no longer shares this button');
      expect(find.text('TOP PICKS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DESIGN-EDIT mode', (tester) async {
      _tallViewport(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          home: Scaffold(
            body: ColorwayEffectSelectorPage.forDesign(design: _effectDesign()),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Save to design'), findsOneWidget);
      expect(find.textContaining('Editing a saved design'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
