// Build 132, fix 3 — Home's Color Sequence says when only three colours light.
//
// A WLED segment has three colour slots. Home's Adjust Pattern panel let the
// customer build a sequence of any length and said nothing while colours 4
// and up never reached the lights. The panel now shows the same three-colour
// hint the Pattern Editor shows, and dims the colours past the limit. What
// is SENT does not change — pinned below through the real panel and the real
// WledService.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/patterns/color_sequence_builder.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hint = 'Your lights use the first 3 colors. Colors 4 and up are '
    'dimmed here.';

const _five = [
  [255, 0, 0],
  [0, 255, 0],
  [0, 0, 255],
  [255, 255, 0],
  [255, 0, 255],
];

Future<void> _pumpBuilder(WidgetTester tester, List<List<int>> seq,
    {ValueChanged<List<List<int>>>? onChanged}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: ColorSequenceBuilder(
          baseColors: const [
            [255, 0, 0]
          ],
          initialSequence: seq,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  ));
  await tester.pump();
}

Finder _slot(int i) => find
    .descendant(
        of: find.byType(ColorSequenceBuilder),
        matching: find.byType(GestureDetector))
    .at(i);

Finder _pastLimit(int i) =>
    find.byKey(ValueKey('color-sequence-slot-past-limit-$i'));

class _SeededWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => const WledStateModel(
        isOn: true,
        brightness: 120,
        speed: 128,
        intensity: 128,
        color: Color(0xFFFF0000),
        connected: true,
        warmWhite: 0,
        supportsRgbw: false,
        effectId: 28,
        paletteId: 5,
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the hint', () {
    testWidgets('five colours: the hint shows and colours 4 and 5 are dimmed',
        (tester) async {
      await _pumpBuilder(tester, _five);
      expect(find.text(_hint), findsOneWidget);
      for (final i in [0, 1, 2]) {
        expect(_pastLimit(i), findsNothing, reason: 'colour ${i + 1} lights');
      }
      for (final i in [3, 4]) {
        expect(_pastLimit(i), findsOneWidget,
            reason: 'colour ${i + 1} is past the limit');
      }
    });

    testWidgets('three colours: no hint, nothing dimmed', (tester) async {
      await _pumpBuilder(tester, _five.take(3).toList());
      expect(find.text(_hint), findsNothing);
      for (final i in [0, 1, 2]) {
        expect(_pastLimit(i), findsNothing);
      }
    });

    testWidgets('removing colours down to three clears it', (tester) async {
      await _pumpBuilder(tester, _five.take(4).toList());
      expect(find.text(_hint), findsOneWidget);
      await tester.longPress(_slot(3));
      await tester.pump();
      expect(find.text(_hint), findsNothing);
      expect(_pastLimit(3), findsNothing);
    });

    testWidgets('the builder still reports every colour — nothing is cut',
        (tester) async {
      List<List<int>>? reported;
      await _pumpBuilder(tester, _five, onChanged: (s) => reported = s);
      await tester.longPress(_slot(4));
      await tester.pump();
      expect(reported, _five.take(4).toList());
    });
  });

  testWidgets('Home still sends what it sent at build 131', (tester) async {
    final controller = WledService('http://mock');
    final c = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => controller),
      wledStateProvider.overrideWith(_SeededWledNotifier.new),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Front', start: 0, stop: 30, gpioPin: 2),
      ]),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
    ]);
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await c.read(wledConnectivityStatusProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PatternAdjustmentPanel(
              initialSpeed: 128,
              initialIntensity: 128,
              initialEffectId: 28,
              initialColors: _five,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // Long-press colour 5: the builder reports the four left.
    await tester.longPress(_slot(4));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump();

    // Captured at build 131: all four go out; the controller keeps three.
    expect(controller.simulatedStatePosts, hasLength(1));
    expect(
        jsonEncode(controller.simulatedStatePosts.single),
        '{"seg":[{"id":0,"col":[[255,0,0,0],[0,255,0,0],[0,0,255,0],'
        '[255,255,0,0]],"grp":1,"spc":0,"frz":false}]}');
  });
}
