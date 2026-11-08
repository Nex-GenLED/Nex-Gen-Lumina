// +123 item B — Dancing Shadows (WLED effect 112) starts one band slower.
//
// Trace (2026-11-07, this branch): the tile named "Dancing Shadows" sends its
// speed from the curated roofline table — kEffectDefaultSpeed[112] in
// lib/features/wled/pattern_effect_speeds.dart — through
// effectDefaultSpeedOr(112, current), whatever the slider held before (no
// slider memory), and the wire chokepoint passes it unchanged. On effect
// 112's own speed profile (effect_speed_profiles.dart: min 5, recommended max
// 100, logarithmic) the bands are Very Slow 5–47, Slow 48–67, Medium 68–81,
// Fast 82–91, Very Fast 92–100. The old 20 was already in Very Slow, the
// slowest band, so by the owner's rule it is halved, floor 5: 20 → 10.
//
// Pinned here: the table value, and the speed the tile actually sends from
// the two places a customer taps "Dancing Shadows" — the pattern library's
// tuner (Pulse filter → the tile) and the Home Tune panel's effect menu.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart'
    show selectorSpeedProvider;
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

const int kDancingShadows = 112;
const int kNewSpeed = 10;

String _band(int sx) {
  final p = getSpeedProfile(kDancingShadows);
  return p.speedLabel(p.mapRawToSlider(sx).position);
}

// ── The pattern library's tuner (harness as tuner_e1_test.dart) ────────────

const _palette = LibraryNode(
  id: 'ocean_breeze',
  name: 'Ocean Breeze',
  nodeType: LibraryNodeType.palette,
  parentId: 'cat_water',
  themeColors: [Color(0xFF0066FF), Color(0xFFFFFFFF)],
);

ProviderContainer _tunerContainer(RecordingWledRepository repo) {
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

/// The tuner animates forever: pump frames rather than settle.
Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ── The Home Tune panel (harness as pattern_adjustment_panel_power_test) ────

class _SeededPanelNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel(
        isOn: true,
        brightness: 120,
        speed: 128,
        intensity: 128,
        color: const Color(0xFFFF0000),
        connected: true,
        warmWhite: 0,
        supportsRgbw: false,
        effectId: 28,
        paletteId: 5,
        colorGroupSize: 1,
        spacing: 0,
        colorSequence: const [Color(0xFFFF0000), Color(0xFF0000FF)],
      );
}

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Front', start: 0, stop: 30, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Garage', start: 30, stop: 60, gpioPin: 14),
];

List<Map<String, dynamic>> _segs(Map<String, dynamic> body) =>
    (body['seg'] as List).cast<Map<String, dynamic>>();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the table starts Dancing Shadows at 10 — Very Slow, half the old 20',
      () {
    expect(WledEffectsCatalog.getName(kDancingShadows), 'Dancing Shadows');
    expect(kEffectDefaultSpeed[kDancingShadows], kNewSpeed);
    expect(effectDefaultSpeed(kDancingShadows), kNewSpeed);
    expect(_band(kNewSpeed), 'Very Slow');
    // No slider memory: whatever the slider held, selecting it starts at 10.
    for (final current in [0, 20, 128, 255]) {
      expect(effectDefaultSpeedOr(kDancingShadows, current), kNewSpeed);
    }
  });

  testWidgets('pattern library tuner: tapping the "Dancing Shadows" tile sends '
      'fx 112 at speed 10', (tester) async {
    final repo = RecordingWledRepository();
    final c = _tunerContainer(repo);
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await c.read(wledConnectivityStatusProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
            body: const ColorwayEffectSelectorPage(paletteNode: _palette)),
      ),
    ));
    await _frames(tester);

    // The tile is not a top pick: the customer opens the Pulse filter first.
    await tester.tap(find.text(MotionType.pulse.displayName).first);
    await _frames(tester, 4);
    await tester.tap(find.text('Dancing Shadows'));
    await _frames(tester, 4);

    expect(c.read(selectorSpeedProvider), kNewSpeed);
    final seg = _segs(repo.applied.last).first;
    expect(seg['fx'], kDancingShadows);
    expect(seg['sx'], kNewSpeed);
  });

  testWidgets('Home Tune panel: choosing "Dancing Shadows" in the effect menu '
      'sends fx 112 at speed 10 to the controller', (tester) async {
    final controller = WledService('http://mock');
    final c = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => controller),
      wledStateProvider.overrideWith(_SeededPanelNotifier.new),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(_twoChannels),
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
              initialColors: [
                [255, 0, 0, 0],
                [0, 0, 255, 0],
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dancing Shadows').last);
    await tester.pumpAndSettle();

    final seg = _segs(controller.simulatedStatePosts.last).first;
    expect(seg['fx'], kDancingShadows);
    expect(seg['sx'], kNewSpeed,
        reason: 'what the controller receives, after the wire chokepoint');
  });
}
