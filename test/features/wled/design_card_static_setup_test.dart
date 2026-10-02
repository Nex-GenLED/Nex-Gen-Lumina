// The design card (ColorwayEffectSelectorPage) — its Static setup
// (Blocks | Alternating) and "LEDs per color" row live in the card's own
// state, independent of the effect being previewed.
//
// Field report 2026-10-02: (a) the grouping row showed under Blocks, where it
// means nothing; (b) previewing Chase or Glitter removed the chips and the
// numbers, and with the Solid tile filtered out of the list the only way back
// was to close the card. The rule is now `staticSetupControls`
// (solid_palette_blocks.dart); this file drives the real card through every
// transition and checks what reached the lights and the hero.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';
import '../../helpers/text_scale_harness.dart';

/// Accepts every write; nothing here reads the device.
class _AcceptingRepo implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// No polling — the real notifier's timers would outlive the test.
class _StillNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

const _tri = LibraryNode(
  id: 'pal_tri',
  name: 'Tri',
  nodeType: LibraryNodeType.palette,
  themeColors: [Colors.red, Colors.white, Colors.blue],
);

const _duo = LibraryNode(
  id: 'pal_duo',
  name: 'Duo',
  nodeType: LibraryNodeType.palette,
  themeColors: [Colors.red, Colors.blue],
);

/// A three-colour design, Solid or otherwise, with a stored layout and
/// grouping — the shape that seeds the card in design-edit mode.
CustomDesign _design({
  int effectId = 0,
  SolidLayout layout = SolidLayout.blocks,
  int grouping = 1,
}) =>
    CustomDesign(
      id: 'design-tri',
      name: 'Tricolour',
      createdAt: DateTime(2026, 10, 2),
      updatedAt: DateTime(2026, 10, 2),
      ownerId: 'u',
      brightness: 180,
      channels: [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          included: true,
          effectId: effectId,
          speed: 128,
          intensity: 128,
          grouping: grouping,
          solidLayout: layout,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: const [255, 0, 0, 0]),
            LedColorGroup(
                startLed: 1, endLed: 1, color: const [255, 255, 255, 0]),
            LedColorGroup(startLed: 2, endLed: 2, color: const [0, 0, 255, 0]),
          ],
        ),
      ],
    );

List<Override> _overrides(_AcceptingRepo repo) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      demoModeProvider.overrideWith((ref) => false),
      effectiveChannelIdsProvider.overrideWith((ref) => const <int>[0]),
      deviceChannelsProvider.overrideWith(
        (ref) => const <DeviceChannel>[
          DeviceChannel(id: 0, start: 0, stop: 10, name: 'Front', gpioPin: 2),
        ],
      ),
      wledStateProvider.overrideWith(() => _StillNotifier()),
      updateDesignProvider.overrideWithValue((design) async => true),
    ];

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// The card animates forever and the preview is debounced: pump frames.
Future<void> _settle(WidgetTester tester, [int frames = 3]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// A tall viewport so the whole card and the effect list lay out at once.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 7000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<GlobalKey<NavigatorState>> _shell(
    WidgetTester tester, List<Override> overrides) async {
  _tall(tester);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
        navigatorKey: nav, home: const Scaffold(body: SizedBox())),
  ));
  return nav;
}

Future<void> _openCatalog(WidgetTester tester, GlobalKey<NavigatorState> nav,
    {LibraryNode palette = _tri, int? initialEffectId}) async {
  nav.currentState!.push(MaterialPageRoute(
    builder: (_) => Scaffold(
      body: ColorwayEffectSelectorPage(
        paletteNode: palette,
        initialEffectId: initialEffectId,
      ),
    ),
  ));
  await _settle(tester, 6);
}

Future<void> _openDesign(WidgetTester tester, GlobalKey<NavigatorState> nav,
    CustomDesign design) async {
  nav.currentState!.push(MaterialPageRoute(
    builder: (_) =>
        Scaffold(body: ColorwayEffectSelectorPage.forDesign(design: design)),
  ));
  await _settle(tester, 6);
}

// ── Finders ─────────────────────────────────────────────────────────────────

Finder _chip(SolidLayout layout) =>
    find.byKey(ValueKey('static-setup-${layout.name}'));
Finder _grouping(int value) => find.byKey(ValueKey('leds-per-color-$value'));
final Finder _hint = find.byKey(const ValueKey('static-setup-hint'));
final Finder _spacingRow = find.text('Dark LEDs between');

/// The effect tile (an InkWell) — not the motion filter chip of the same name.
Finder _tile(int effectId) =>
    find.widgetWithText(InkWell, WledEffectsCatalog.getName(effectId));

/// A chip is drawn selected with a bold label.
bool _chipSelected(WidgetTester tester, SolidLayout layout) {
  final text = tester.widget<Text>(
      find.descendant(of: _chip(layout), matching: find.byType(Text)).first);
  return text.style?.fontWeight == FontWeight.w600;
}

/// The design segment of the last write.
Map<dynamic, dynamic> _lastSeg(_AcceptingRepo repo) =>
    (repo.applyJsonCalls.last['seg'] as List)
        .cast<Map>()
        .firstWhere((s) => s.containsKey('fx'));

AnimatedRooflineOverlay _hero(WidgetTester tester) =>
    tester.widget<AnimatedRooflineOverlay>(find.byType(AnimatedRooflineOverlay));

/// Taps a tile, scrolling it into view first (the list is lazy).
Future<void> _tapTile(WidgetTester tester, int effectId) async {
  final tile = _tile(effectId);
  expect(tile, findsOneWidget, reason: 'tile for fx $effectId is listed');
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Static + Blocks', () {
    testWidgets('opens on Blocks with the chips and WITHOUT the grouping row',
        (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      await _openCatalog(tester, nav);

      expect(_chip(SolidLayout.blocks), findsOneWidget);
      expect(_chip(SolidLayout.alternating), findsOneWidget);
      expect(_chipSelected(tester, SolidLayout.blocks), isTrue);
      expect(_chipSelected(tester, SolidLayout.alternating), isFalse);
      expect(_grouping(1), findsNothing,
          reason: 'Blocks: the grouping control means nothing and is gone');
      expect(_hint, findsNothing, reason: 'Static is selected');
      expect(_spacingRow, findsOneWidget);
      expect(repo.applyJsonCalls, isEmpty, reason: 'opening writes nothing');
    });

    testWidgets('the hero draws Blocks (fx 83 + pal 5)', (tester) async {
      final nav = await _shell(tester, _overrides(_AcceptingRepo()));
      await _openCatalog(tester, nav);
      final hero = _hero(tester);
      expect(hero.previewEffectId, 83);
      expect(hero.previewPaletteId, 5);
    });
  });

  group('Static + Alternating', () {
    testWidgets('Alternating shows the row; every value goes out as grp on '
        'fx 84 ix 0, and the hero follows', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);

      await _tap(tester, _chip(SolidLayout.alternating));
      expect(_chipSelected(tester, SolidLayout.alternating), isTrue);
      expect(_chipSelected(tester, SolidLayout.blocks), isFalse);
      expect(_grouping(1), findsOneWidget, reason: 'Alternating shows grouping');
      expect(_lastSeg(repo)['fx'], 84);

      for (var value = 1; value <= 5; value++) {
        await _tap(tester, _grouping(value));
        expect(container.read(selectorColorGroupProvider), value);
        final seg = _lastSeg(repo);
        expect([seg['fx'], seg['ix'], seg['grp'], seg['pal']], [84, 0, value, 5],
            reason: 'value $value');
        final hero = _hero(tester);
        expect(hero.previewEffectId, 84);
        expect(hero.colorGroupSize, value, reason: 'the hero shows $value-wide bands');
        expect(container.read(selectorEffectIdProvider), 0,
            reason: 'still Static');
      }
    });

    testWidgets('two colours: Alternating is fx 83 pal 0 sx 0 ix 0 with grp',
        (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      await _openCatalog(tester, nav, palette: _duo);

      await _tap(tester, _chip(SolidLayout.alternating));
      await _tap(tester, _grouping(3));
      final seg = _lastSeg(repo);
      expect([seg['fx'], seg['pal'], seg['sx'], seg['ix'], seg['grp']],
          [83, 0, 0, 0, 3]);
    });
  });

  group('switching layouts', () {
    testWidgets('Alternating at 4 → Blocks hides the row and fires thirds; '
        'back to Alternating shows 4 again', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);

      await _tap(tester, _chip(SolidLayout.alternating));
      await _tap(tester, _grouping(4));
      expect(_lastSeg(repo)['grp'], 4);

      await _tap(tester, _chip(SolidLayout.blocks));
      expect(_grouping(4), findsNothing, reason: 'Blocks hides grouping');
      expect(_chipSelected(tester, SolidLayout.blocks), isTrue);
      final blocks = _lastSeg(repo);
      expect([blocks['fx'], blocks['pal']], [83, 5]);
      expect(container.read(selectorColorGroupProvider), 4,
          reason: 'hidden, not forgotten');

      await _tap(tester, _chip(SolidLayout.alternating));
      expect(_grouping(4), findsOneWidget);
      expect(container.read(selectorColorGroupProvider), 4);
      final alt = _lastSeg(repo);
      expect([alt['fx'], alt['grp']], [84, 4],
          reason: 'the previous grouping fires again');
    });
  });

  group('previewing an effect never removes the Static setup', () {
    testWidgets('Chase: the chips stay, unselected, with the hint; no row '
        '(Blocks remembered); Chase is what went to the lights',
        (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      await _openCatalog(tester, nav);

      await _tapTile(tester, 28);
      expect(_lastSeg(repo)['fx'], 28);
      expect(_chip(SolidLayout.blocks), findsOneWidget,
          reason: 'the chips used to vanish here');
      expect(_chip(SolidLayout.alternating), findsOneWidget);
      expect(_chipSelected(tester, SolidLayout.blocks), isFalse,
          reason: 'Chase is playing, not Blocks');
      expect(_chipSelected(tester, SolidLayout.alternating), isFalse);
      expect(_hint, findsOneWidget);
      expect(find.text(kStaticSetupReturnHint), findsOneWidget);
      expect(_grouping(1), findsNothing);
      expect(_spacingRow, findsNothing,
          reason: 'spacing describes the selected effect; Chase is not one');
      expect(_hero(tester).previewEffectId, 28, reason: 'the hero shows Chase');
    });

    testWidgets('tapping Blocks while Chase plays returns to Static as Blocks',
        (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);
      await _tapTile(tester, 28);

      await _tap(tester, _chip(SolidLayout.blocks));
      expect(container.read(selectorEffectIdProvider), 0);
      expect(container.read(selectorSolidLayoutProvider), SolidLayout.blocks);
      expect(_chipSelected(tester, SolidLayout.blocks), isTrue);
      expect(_hint, findsNothing);
      final seg = _lastSeg(repo);
      expect([seg['fx'], seg['pal']], [83, 5]);
      expect(_hero(tester).previewEffectId, 83);
    });

    testWidgets('Chase with Alternating at 3 remembered: chips AND row stay; '
        'a number returns to Static with that grouping', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);
      await _tap(tester, _chip(SolidLayout.alternating));
      await _tap(tester, _grouping(3));

      await _tapTile(tester, 28);
      expect(_lastSeg(repo)['fx'], 28);
      expect(_chip(SolidLayout.alternating), findsOneWidget);
      expect(_chipSelected(tester, SolidLayout.alternating), isFalse);
      expect(_grouping(3), findsOneWidget,
          reason: 'the row is Static setup: Alternating is remembered');
      expect(container.read(selectorColorGroupProvider), 3,
          reason: 'a preview never touches the grouping');

      await _tap(tester, _grouping(5));
      expect(container.read(selectorEffectIdProvider), 0,
          reason: 'Chase does not read grp: the tap is a return to Static');
      expect(_chipSelected(tester, SolidLayout.alternating), isTrue);
      final seg = _lastSeg(repo);
      expect([seg['fx'], seg['grp']], [84, 5]);
    });

    testWidgets('Glitter: chips unselected, the row stays for Glitter, and a '
        'number keeps Glitter', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);

      await _tapTile(tester, 87);
      expect(_lastSeg(repo)['fx'], 87);
      expect(_chip(SolidLayout.blocks), findsOneWidget);
      expect(_chipSelected(tester, SolidLayout.blocks), isFalse);
      expect(_hint, findsOneWidget);
      expect(_grouping(1), findsOneWidget, reason: 'Glitter bands are grp wide');
      expect(_spacingRow, findsOneWidget);

      await _tap(tester, _grouping(2));
      expect(container.read(selectorEffectIdProvider), 87,
          reason: 'the row drives Glitter here');
      final seg = _lastSeg(repo);
      expect([seg['fx'], seg['grp']], [87, 2]);
    });

    testWidgets('Solid tile after Glitter restores Alternating at 3: chip '
        'selected, row shows 3, lights get fx 84 grp 3', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);
      await _tap(tester, _chip(SolidLayout.alternating));
      await _tap(tester, _grouping(3));
      await _tapTile(tester, 87);
      expect(_chipSelected(tester, SolidLayout.alternating), isFalse);

      await _tapTile(tester, 0);
      expect(container.read(selectorEffectIdProvider), 0);
      expect(_chipSelected(tester, SolidLayout.alternating), isTrue);
      expect(_hint, findsNothing);
      expect(_grouping(3), findsOneWidget);
      expect(container.read(selectorColorGroupProvider), 3);
      final seg = _lastSeg(repo);
      expect([seg['fx'], seg['ix'], seg['grp']], [84, 0, 3]);
      final hero = _hero(tester);
      expect([hero.previewEffectId, hero.colorGroupSize], [84, 3]);
    });

    testWidgets('Meteor then the Alternating chip: back to Static as '
        'Alternating with the remembered grouping', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);
      await _tap(tester, _chip(SolidLayout.alternating));
      await _tap(tester, _grouping(2));
      await _tap(tester, _chip(SolidLayout.blocks));
      expect(_grouping(2), findsNothing);

      await _tapTile(tester, 76);
      expect(_lastSeg(repo)['fx'], 76);
      expect(_chipSelected(tester, SolidLayout.blocks), isFalse);

      await _tap(tester, _chip(SolidLayout.alternating));
      expect(container.read(selectorEffectIdProvider), 0);
      expect(_chipSelected(tester, SolidLayout.alternating), isTrue);
      expect(_grouping(2), findsOneWidget);
      final seg = _lastSeg(repo);
      expect([seg['fx'], seg['grp']], [84, 2]);
    });

    testWidgets('a motion filter that hides the Solid tile: the chips are '
        'still the way back', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openCatalog(tester, nav);

      container.read(selectorMotionTypeProvider.notifier).state =
          MotionType.chase;
      await _settle(tester);
      expect(_tile(0), findsNothing, reason: 'Solid is not a Chase effect');
      await _tapTile(tester, 28);
      expect(_chip(SolidLayout.blocks), findsOneWidget);

      await _tap(tester, _chip(SolidLayout.blocks));
      expect(container.read(selectorEffectIdProvider), 0);
      expect(_lastSeg(repo)['fx'], 83);
    });
  });

  group('design edit', () {
    testWidgets('a Solid design stored Alternating at 2 opens with the row '
        'showing 2', (tester) async {
      final nav = await _shell(tester, _overrides(_AcceptingRepo()));
      final container = _containerOf(tester);
      await _openDesign(
          tester, nav, _design(layout: SolidLayout.alternating, grouping: 2));

      expect(_chipSelected(tester, SolidLayout.alternating), isTrue);
      expect(_grouping(2), findsOneWidget);
      expect(container.read(selectorColorGroupProvider), 2);
      expect(_hint, findsNothing);
    });

    testWidgets('a Solid design stored Blocks opens without the row',
        (tester) async {
      final nav = await _shell(tester, _overrides(_AcceptingRepo()));
      await _openDesign(tester, nav, _design(layout: SolidLayout.blocks));
      expect(_chipSelected(tester, SolidLayout.blocks), isTrue);
      expect(_grouping(1), findsNothing);
    });

    testWidgets('a Chase design opens with the chips unselected and the hint; '
        'its stored Alternating keeps the row', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      await _openDesign(tester, nav,
          _design(effectId: 28, layout: SolidLayout.alternating, grouping: 3));

      expect(_chip(SolidLayout.blocks), findsOneWidget);
      expect(_chipSelected(tester, SolidLayout.alternating), isFalse);
      expect(_hint, findsOneWidget);
      expect(_grouping(3), findsOneWidget);
      expect(repo.applyJsonCalls, isEmpty, reason: 'opening a design is silent');

      await _tap(tester, _chip(SolidLayout.alternating));
      expect(container.read(selectorEffectIdProvider), 0);
      final seg = _lastSeg(repo);
      expect([seg['fx'], seg['grp']], [84, 3]);
    });
  });

  group('accessibility — 1.0 / 1.75 / 2.0 with Bold Text', () {
    List<Override> a11y() => [
          ...homeDashboardOverrides(repo: RecordingWledRepository()),
          designsStreamProvider
              .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
          updateDesignProvider.overrideWithValue((design) async => true),
        ];

    Widget scoped(Widget page) =>
        ProviderScope(overrides: a11y(), child: Scaffold(body: page));

    testWidgets('Static + Blocks (chips, no row)', (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
          tester, scoped(const ColorwayEffectSelectorPage(paletteNode: _tri)),
          host: TextScaleHost.screen);
    });

    testWidgets('Static + Alternating (chips + row), from a design',
        (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          scoped(ColorwayEffectSelectorPage.forDesign(
              design: _design(layout: SolidLayout.alternating, grouping: 3))),
          host: TextScaleHost.screen);
    });

    testWidgets('Chase previewed (chips unselected + hint)', (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          scoped(const ColorwayEffectSelectorPage(
              paletteNode: _tri, initialEffectId: 28)),
          host: TextScaleHost.screen);
    });

    testWidgets('Chase over a remembered Alternating (chips + hint + row)',
        (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          scoped(ColorwayEffectSelectorPage.forDesign(
              design: _design(
                  effectId: 28, layout: SolidLayout.alternating, grouping: 3))),
          host: TextScaleHost.screen);
    });
  });
}
