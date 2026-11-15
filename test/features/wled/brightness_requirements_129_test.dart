// Build 129 follow-up — the owner's requirements, each backed here or by a
// named test elsewhere (see docs/release/build_129_candidate.md, "Checked
// against the requirements"):
//
//  a. "If a user wants to dim one light and have the next one bright, that's
//     part of the customization." — per light, on the strip.
//     Design Studio: test/features/design/pixel_brightness_129_test.dart
//     ("what the controller renders from the saved groups matches the
//     intended light"). A custom brightness tile: below.
//  c. "If a user wants it to gradiently change over 18 pixels instead of 9 it
//     shouldn't be a problem, or whatever... any level of customization." —
//     cycle length, brightest, dimmest, shape and offset: below.
//  e. The same tile on every channel (brightness_wave_cards_129_test checks
//     both home channels against the same levels), and the schedule / Game
//     Day pickers refuse a tile with the per-pixel wording every picker uses:
//     below.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/per_pixel_payload_guard.dart'
    show perPixelPickerRefusalMessage;
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/wled/brightness_tile.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/widgets/brightness_tile_controls.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';
import '../../helpers/wled_strip_simulator.dart';

const double kTolerancePp = 3.0;
const List<int> kWarmWhite = [255, 180, 107, 0];

/// What the controller lights, in %, when [tile] is painted in white along
/// [length] pixels — through the same span builder the app sends.
List<double> _lit(BrightnessTile tile, int length) {
  final i = <dynamic>[];
  for (final s in brightnessTileSpans(tile, kWarmWhite, length)) {
    i.addAll([s.start, s.end + 1, s.color]);
  }
  return lightLevels(const WledStripSimulator().render({'fx': 0, 'i': i}, length));
}

/// Absolute light, in % of the channel's full output: the simulator renders
/// post-gamma values, so the lit value over 255 IS the light fraction (the
/// strip-relative [lightLevels] reads the strip's own peak as 100).
List<double> _litAbsolute(BrightnessTile tile, int length) {
  final i = <dynamic>[];
  for (final s in brightnessTileSpans(tile, kWarmWhite, length)) {
    i.addAll([s.start, s.end + 1, s.color]);
  }
  final px = const WledStripSimulator().render({'fx': 0, 'i': i}, length);
  return [for (final p in px) p[0] / 255 * 100];
}

void _expectWithin(List<double> got, List<int> want, String what) {
  for (var p = 0; p < want.length; p++) {
    expect(got[p], closeTo(want[p], kTolerancePp), reason: '$what px $p');
  }
}

ProviderContainer _container(RecordingWledRepository repo) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
    demoModeProvider.overrideWith((ref) => false),
    userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
  ]);
  addTearDown(c.dispose);
  c.read(selectedChannelIdsProvider.notifier).state = null;
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget body) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: Scaffold(body: body)),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('(a) one light dim, the next bright — the setting is per light', () {
    test('a custom tile 100/20/100/60/40/100 lights every pixel at its own level', () {
      final tile = BrightnessTile(levels: const [100, 20, 100, 60, 40, 100]);
      final lit = _lit(tile, 18);
      _expectWithin(lit, [100, 20, 100, 60, 40, 100, 100, 20, 100, 60, 40, 100], 'custom');
      // Neighbours differ: light 1 vs light 2, light 4 vs light 5.
      expect((lit[0] - lit[1]).abs(), greaterThan(70));
      expect((lit[3] - lit[4]).abs(), greaterThan(15));
    });

    test('a tile with every light at a different level keeps all of them', () {
      final tile = BrightnessTile(levels: const [100, 90, 80, 70, 60, 50, 40, 30, 20, 10]);
      _expectWithin(_lit(tile, 10), tile.levels, 'ten distinct');
      expect(tile.distinctLevelCount, 10);
    });
  });

  group('(c) any cycle length, brightest, dimmest, shape and offset', () {
    for (final n in [6, 9, 18, 30, 60]) {
      test('a wave over $n lights: 100 at light 1, 40 in the middle, back to bright, then again', () {
        final tile = BrightnessTile.triangle(brightest: 100, dimmest: 40, cycle: n);
        expect(tile.cycleLength, n);
        final lit = _lit(tile, 2 * n);
        final m = n ~/ 2;
        expect(lit[0], closeTo(100, kTolerancePp));
        expect(lit[m], closeTo(40, kTolerancePp), reason: 'the trough is a real light at the dimmest');
        expect(lit[n], closeTo(100, kTolerancePp), reason: 'the cycle restarts');
        for (var p = 1; p <= m; p++) {
          expect(lit[p], lessThan(lit[p - 1]), reason: 'falling at px $p');
        }
        for (var p = m + 1; p < n; p++) {
          expect(lit[p], greaterThan(lit[p - 1]), reason: 'rising at px $p');
        }
        if (n.isEven) {
          for (var p = 1; p < m; p++) {
            expect(lit[p], closeTo(lit[n - p], kTolerancePp), reason: 'symmetric at px $p');
          }
        }
        expect(lit.sublist(0, n), lit.sublist(n, 2 * n), reason: 'cycle 2 = cycle 1');
      });
    }

    test('the two presets are only two points on that range', () {
      expect(brightnessPatternPresetById('wave6')!.tile,
          BrightnessTile.triangle(brightest: 100, dimmest: 40, cycle: 6));
      expect(brightnessPatternPresetById('wave18')!.tile,
          BrightnessTile.triangle(brightest: 100, dimmest: 40, cycle: 18));
      expect(brightnessPatternPresetById('wave6')!.tile.levels, [100, 80, 60, 40, 60, 80]);
    });

    test('brightest and dimmest are free: 90 down to 10 over 12 lights', () {
      final tile = BrightnessTile.triangle(brightest: 90, dimmest: 10, cycle: 12);
      final lit = _litAbsolute(tile, 12);
      expect(lit[0], closeTo(90, kTolerancePp));
      expect(lit[6], closeTo(10, kTolerancePp));
      expect(tile.brightest, 90);
      expect(tile.dimmest, 10);
    });

    test('shapes: ramp falls once then restarts; steps hold each level for the band width', () {
      final ramp = BrightnessTile.ramp(brightest: 100, dimmest: 40, cycle: 6);
      final litRamp = _lit(ramp, 12);
      for (var p = 1; p < 6; p++) {
        expect(litRamp[p], lessThan(litRamp[p - 1]), reason: 'ramp px $p');
      }
      expect(litRamp[6], closeTo(100, kTolerancePp), reason: 'ramp restarts bright');

      final steps = BrightnessTile.steps(const [100, 60, 30], bandWidth: 3);
      expect(steps.cycleLength, 9);
      _expectWithin(_lit(steps, 9), [100, 100, 100, 60, 60, 60, 30, 30, 30], 'steps');
    });

    test('the start offset rotates where the cycle begins on the run', () {
      final wave = BrightnessTile.triangle(brightest: 100, dimmest: 40, cycle: 6);
      final shifted = wave.copyWith(offset: 2);
      expect(shifted.levelsForRun(6), [60, 40, 60, 80, 100, 80]);
      _expectWithin(_lit(shifted, 6), [60, 40, 60, 80, 100, 80], 'offset 2');
    });

    testWidgets('the Adjust controls offer the cycle up to 60 lights, brightest, dimmest, '
        'four shapes and the offset', (tester) async {
      BrightnessTile? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BrightnessTileControls(
              tile: brightnessPatternPresetById('wave6')!.tile,
              baseColor: const Color(0xFFFFB46B),
              onTileChanged: (t) => changed = t,
            ),
          ),
        ),
      ));
      await tester.pump();
      Slider sliderUnder(String key) => tester.widget<Slider>(find.byKey(ValueKey(key)));
      final cycle = sliderUnder('tile-cycle');
      expect(cycle.min, 2);
      expect(cycle.max, 60, reason: 'well beyond the 18-light preset');
      expect(sliderUnder('tile-brightest').max, 100);
      expect(sliderUnder('tile-dimmest').min, 0);
      expect(find.byKey(const ValueKey('tile-offset')), findsOneWidget);
      for (final shape in ['triangle', 'ramp', 'steps', 'custom']) {
        expect(find.byKey(ValueKey('tile-shape-$shape')), findsOneWidget, reason: shape);
      }
      // Moving the cycle slider to its end yields a 60-light wave.
      await tester.drag(find.byKey(const ValueKey('tile-cycle')), const Offset(2000, 0));
      await tester.pump();
      expect(changed, isNotNull);
      expect(changed!.cycleLength, 60);
      expect(changed!.shape, BrightnessShape.triangle);
    });
  });

  group('(e) the schedule and Game Day pickers refuse a brightness tile', () {
    for (final destination in ['Schedule', 'Game Day']) {
      testWidgets('$destination picker: Save shows the per-pixel refusal, hands nothing back, '
          'writes nothing', (tester) async {
        final repo = PatternRepository();
        final node = (await repo.getNodeById('arch_k3000_gradients_wave6'))!;
        final wledRepo = RecordingWledRepository();
        final c = _container(wledRepo);
        var handedBack = 0;
        await _pump(
          tester,
          c,
          ColorwayEffectSelectorPage(
            paletteNode: node,
            onDesignSelected: (_) => handedBack++,
            saveDestinationLabel: destination,
          ),
        );
        await _settle(tester);
        expect(find.byType(BrightnessTileControls), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('save-design')));
        await _settle(tester);
        final snack = find.byKey(const ValueKey('brightness-tile-refused'));
        expect(snack, findsOneWidget);
        final text = tester.widget<Text>(
            find.descendant(of: snack, matching: find.byType(Text)));
        expect(text.data,
            perPixelPickerRefusalMessage('${node.name} (brightness pattern)', destination));
        expect(handedBack, 0, reason: 'nothing is handed to the picker');
        expect(wledRepo.applied, isEmpty, reason: 'nothing reaches the lights');
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      });
    }
  });
}
