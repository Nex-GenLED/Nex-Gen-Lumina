// The Blocks | Alternating chip follows the DESIGN, like the other nine
// selector providers — seeded from it on open, written to it on save, and put
// back on cancel.
//
// Before 2026-09-22 `selectorSolidLayoutProvider` was the one provider the
// tuner never seeded, snapshotted or restored: a design opened on whatever chip
// the previous visit had left, and Save dropped the chip entirely (the model
// had no field), so a design saved as Alternating fired as Blocks
// (audit/DESIGN_CARD_BLOCKS_LAYOUT_AUDIT_2026-09-22.md, Finding 2).

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
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

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

/// A three-colour Solid design (palette-shaped groups — one LED per colour),
/// which is exactly the shape that makes the Blocks | Alternating chip live.
CustomDesign _solidDesign(SolidLayout layout) => CustomDesign(
      id: 'solid-3',
      name: 'Tricolour',
      createdAt: DateTime(2026, 9, 22),
      updatedAt: DateTime(2026, 9, 22),
      ownerId: 'u',
      brightness: 180,
      channels: [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          included: true,
          effectId: 0,
          speed: 128,
          intensity: 128,
          solidLayout: layout,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: const [255, 0, 0, 0]),
            LedColorGroup(startLed: 1, endLed: 1, color: const [255, 255, 255, 0]),
            LedColorGroup(startLed: 2, endLed: 2, color: const [0, 0, 255, 0]),
          ],
        ),
      ],
    );

List<Override> _overrides(_AcceptingRepo repo,
        {Future<bool> Function(CustomDesign)? save}) =>
    [
      wledRepositoryProvider.overrideWith((ref) => repo),
      demoModeProvider.overrideWith((ref) => false),
      effectiveChannelIdsProvider.overrideWith((ref) => const <int>[0]),
      deviceChannelsProvider.overrideWith(
        (ref) => const <DeviceChannel>[
          DeviceChannel(id: 0, start: 0, stop: 10, name: 'Front', gpioPin: 2),
        ],
      ),
      wledStateProvider.overrideWith(() => _StillNotifier()),
      updateDesignProvider.overrideWithValue(save ?? (design) async => true),
    ];

/// The tree-owned container, so it is disposed with the tree (and with it the
/// selector notifiers) before flutter_test's pending-timer check.
ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

Future<void> _settle(WidgetTester tester, [int frames = 3]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Pumps the shell, returns the navigator key.
Future<GlobalKey<NavigatorState>> _shell(WidgetTester tester, List<Override> overrides) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(navigatorKey: nav, home: const Scaffold(body: SizedBox())),
  ));
  return nav;
}

void _openDesign(GlobalKey<NavigatorState> nav, CustomDesign design) {
  nav.currentState!.push(MaterialPageRoute(
    builder: (_) => Scaffold(body: ColorwayEffectSelectorPage.forDesign(design: design)),
  ));
}

void main() {
  group('the Blocks | Alternating chip is seeded from the design', () {
    testWidgets('a design stored as Blocks opens on Blocks, whatever the last '
        'visit left', (tester) async {
      final nav = await _shell(tester, _overrides(_AcceptingRepo()));
      final container = _containerOf(tester);
      // The previous visit left the chip on Alternating.
      container.read(selectorSolidLayoutProvider.notifier).state = SolidLayout.alternating;

      _openDesign(nav, _solidDesign(SolidLayout.blocks));
      await _settle(tester);

      expect(container.read(selectorSolidLayoutProvider), SolidLayout.blocks,
          reason: 'seeded from the channel, not inherited from the last visit');
      expect(container.read(selectorEffectIdProvider), 0,
          reason: 'the stored fx 0, never the substituted 83');
    });

    testWidgets('a design stored as Alternating opens on Alternating', (tester) async {
      final nav = await _shell(tester, _overrides(_AcceptingRepo()));
      final container = _containerOf(tester);
      expect(container.read(selectorSolidLayoutProvider), SolidLayout.blocks,
          reason: 'the provider default');

      _openDesign(nav, _solidDesign(SolidLayout.alternating));
      await _settle(tester);

      expect(container.read(selectorSolidLayoutProvider), SolidLayout.alternating);
    });

    testWidgets('cancel puts the chip back with the other nine', (tester) async {
      final repo = _AcceptingRepo();
      final nav = await _shell(tester, _overrides(repo));
      final container = _containerOf(tester);
      container.read(selectorSolidLayoutProvider.notifier).state = SolidLayout.alternating;
      // A control: the speed provider has always been restored this way.
      container.read(selectorSpeedProvider.notifier).state = 77;

      _openDesign(nav, _solidDesign(SolidLayout.blocks));
      await _settle(tester);
      expect(container.read(selectorSolidLayoutProvider), SolidLayout.blocks);
      expect(container.read(selectorSpeedProvider), 128, reason: 'seeded from the design');

      final writesBeforePop = repo.applyJsonCalls.length;
      nav.currentState!.pop();
      await _settle(tester, 6);

      expect(repo.applyJsonCalls.length, writesBeforePop + 1,
          reason: 'dispose ran: the cancel exit replayed the captured look once');
      expect(container.read(selectorSpeedProvider), 77,
          reason: 'control: the pre-edit speed comes back');
      expect(container.read(selectorSolidLayoutProvider), SolidLayout.alternating,
          reason: 'the pre-edit value, restored from dispose like the rest');
    });

    testWidgets('a catalog palette opens on Blocks, the documented default, '
        'instead of on whatever the last visit left', (tester) async {
      final nav = await _shell(tester, _overrides(_AcceptingRepo()));
      final container = _containerOf(tester);
      container.read(selectorSolidLayoutProvider.notifier).state = SolidLayout.alternating;

      nav.currentState!.push(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: ColorwayEffectSelectorPage(
            paletteNode: const LibraryNode(
              id: 'pal_tri',
              name: 'Tri',
              nodeType: LibraryNodeType.palette,
              themeColors: [Colors.red, Colors.white, Colors.blue],
            ),
          ),
        ),
      ));
      await _settle(tester);

      expect(container.read(selectorSolidLayoutProvider), SolidLayout.blocks);
    });
  });

  group('Save writes the chip to the design', () {
    testWidgets('choosing Alternating and saving stores Alternating on the '
        'included channel', (tester) async {
      final repo = _AcceptingRepo();
      CustomDesign? saved;

      // The tuner is a tall CustomScrollView; give it a viewport that lays the
      // chip row and the commit row out rather than scrolling to find them.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final nav = await _shell(tester, _overrides(repo, save: (d) async {
        saved = d;
        return true;
      }));
      final container = _containerOf(tester);

      _openDesign(nav, _solidDesign(SolidLayout.blocks));
      await _settle(tester, 6);
      expect(container.read(selectorSolidLayoutProvider), SolidLayout.blocks);

      final chip = find.text('Alternating');
      expect(chip, findsOneWidget,
          reason: 'three colours + Solid → the layout chips are on screen');
      await tester.tap(chip);
      await _settle(tester);
      expect(container.read(selectorSolidLayoutProvider), SolidLayout.alternating);
      // The live preview went out in the chosen layout (fx 84 for 3 colours).
      final lastSeg = (repo.applyJsonCalls.last['seg'] as List)
          .cast<Map>()
          .firstWhere((s) => s.containsKey('fx'));
      expect([lastSeg['fx'], lastSeg['ix']], [84, 0]);

      final save = find.text('Save to design');
      expect(save, findsOneWidget);
      await tester.tap(save);
      await _settle(tester);

      expect(saved, isNotNull, reason: 'updateDesign was called');
      final front = saved!.channels.firstWhere((c) => c.channelId == 0);
      expect(front.solidLayout, SolidLayout.alternating);
      expect(front.effectId, 0, reason: 'the stored truth stays 0');
      // And the saved design now FIRES as Alternating from every door.
      final seg = (saved!.toWledPayload()['seg'] as List).single as Map;
      expect([seg['fx'], seg['ix'], seg['sx']], [84, 0, 0]);
    });

    testWidgets('a non-Solid design keeps its stored layout untouched by the '
        'chip', (tester) async {
      CustomDesign? saved;

      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final nav = await _shell(tester, _overrides(_AcceptingRepo(), save: (d) async {
        saved = d;
        return true;
      }));
      final container = _containerOf(tester);

      // Stored as Alternating but running a chase — the chip does not apply.
      final base = _solidDesign(SolidLayout.alternating);
      final chase = base.copyWith(
        channels: [base.channels.single.copyWith(effectId: 28)],
      );
      _openDesign(nav, chase);
      await _settle(tester, 6);
      // Whatever the (irrelevant) chip says, Save must not stamp it.
      container.read(selectorSolidLayoutProvider.notifier).state = SolidLayout.blocks;
      await _settle(tester);

      await tester.tap(find.text('Save to design'));
      await _settle(tester);

      expect(saved!.channels.single.solidLayout, SolidLayout.alternating);
      expect(saved!.channels.single.effectId, 28);
    });
  });
}
