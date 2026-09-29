// P10 — the palette tuner (UX audit rows 22, 63).
//
//   • Catalog mode (Explore) no longer drives the house to full brightness:
//     neither the live preview nor Apply states a level.
//   • A design HANDED BACK to a destination still states the level it always
//     has, so stored schedule / Game Day / Favorites payloads are unchanged.
//   • A caller that names a destination gets SELECTION mode by default, even
//     without a callback — the design comes back as the route's result and
//     the lights are not touched.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/recording_wled_repository.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'test-user';
}

class _SeededWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => const WledStateModel(
        isOn: true,
        brightness: 90,
        speed: 128,
        intensity: 128,
        color: Color(0xFF0A141E),
        connected: true,
        warmWhite: 0,
        supportsRgbw: false,
        effectId: 0,
        paletteId: 0,
        colorGroupSize: 1,
        spacing: 0,
        colorSequence: [Color(0xFF0A141E)],
      );
}

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
    wledStateProvider.overrideWith(() => _SeededWledNotifier()),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    demoModeProvider.overrideWith((ref) => false),
    authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget home) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: home),
  ));
  await tester.pump();
}

/// The tuner animates forever, so a route push/pop is pumped for its
/// transition's length rather than settled.
Future<void> _routeTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('buildSelectorPayload', () {
    const base = SelectorState(
      effectId: 28,
      speed: 128,
      intensity: 128,
      colors: [
        [0, 102, 255, 0]
      ],
    );

    test('no brightness stated → no `bri`: the lights keep their level', () {
      expect(buildSelectorPayload(base).containsKey('bri'), isFalse);
    });

    test('a stated brightness is sent', () {
      expect(buildSelectorPayload(base.copyWith(brightness: 180))['bri'], 180);
    });

    test('the round trip keeps an absent level absent', () {
      final state = selectorStateFromPayload(buildSelectorPayload(base));
      expect(state.brightness, isNull);
    });
  });

  group('resolveSelectorMode', () {
    SelectorMode mode({
      bool callback = false,
      String? destination,
      bool edit = false,
      bool celebration = false,
    }) =>
        resolveSelectorMode(
          hasDesignCallback: callback,
          saveDestinationLabel: destination,
          isDesignEdit: edit,
          celebrationMode: celebration,
        );

    test('no destination → catalog', () {
      expect(mode(), SelectorMode.catalog);
    });

    test('a destination label alone → selection', () {
      expect(mode(destination: 'schedule'), SelectorMode.selection);
    });

    test('a callback alone → selection', () {
      expect(mode(callback: true), SelectorMode.selection);
    });

    test('celebration and design edit keep their own modes', () {
      expect(mode(callback: true, celebration: true), SelectorMode.celebration);
      expect(mode(edit: true, destination: 'x'), SelectorMode.designEdit);
    });
  });

  testWidgets('catalog Apply writes the look and leaves the brightness alone',
      (tester) async {
    final repo = RecordingWledRepository();
    final c = _container(repo);
    await _pump(tester, c,
        const Scaffold(body: ColorwayEffectSelectorPage(paletteNode: _palette)));

    await tester.tap(find.text('Apply'));
    await _settle(tester);

    expect(repo.applied, isNotEmpty);
    for (final payload in repo.applied) {
      expect(payload.containsKey('bri'), isFalse,
          reason: 'Explore must not drive the house to full brightness');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selection "Preview on lights" leaves the brightness alone, and '
      'the design handed back states its usual level', (tester) async {
    final repo = RecordingWledRepository();
    final c = _container(repo);
    LibraryDesignSelection? picked;
    await _pump(
      tester,
      c,
      Scaffold(
        body: ColorwayEffectSelectorPage(
          paletteNode: _palette,
          saveDestinationLabel: 'Game Day',
          onDesignSelected: (s) => picked = s,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('preview-on-lights')));
    await _settle(tester);
    expect(repo.applied, isNotEmpty);
    expect(repo.applied.first.containsKey('bri'), isFalse);

    await tester.tap(find.text('Save to Game Day'));
    await _settle(tester);
    expect(picked, isNotNull);
    expect(picked!.wledPayload['bri'], kHandedBackDesignBrightness,
        reason: 'stored payloads are unchanged');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a destination with no callback: selection mode, the design is '
      "the route's result, and the lights are never touched", (tester) async {
    final repo = RecordingWledRepository();
    final c = _container(repo);
    LibraryDesignSelection? result;
    var returned = false;

    await _pump(
      tester,
      c,
      Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result = await Navigator.of(ctx).push<LibraryDesignSelection>(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(
                    body: ColorwayEffectSelectorPage(
                      paletteNode: _palette,
                      saveDestinationLabel: 'schedule',
                    ),
                  ),
                ),
              );
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await _routeTransition(tester);

    expect(find.text('Apply'), findsNothing,
        reason: 'naming a destination is selection mode, not catalog');
    expect(find.text('Save to schedule'), findsOneWidget);

    await tester.tap(find.text('Save to schedule'));
    await _routeTransition(tester);

    expect(returned, isTrue);
    expect(result, isNotNull);
    expect(result!.paletteName, 'Ocean Breeze');
    expect(repo.writeCount, 0, reason: 'choosing a design touches nothing');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
