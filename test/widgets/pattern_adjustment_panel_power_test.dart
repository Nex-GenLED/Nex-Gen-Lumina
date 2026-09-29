// +110 E1 PRIORITY — Tune-panel adjustments never change any channel's power.
//
// From the foundation's customer walk (B1): with the channel bar narrowed to
// channel 1, a Tune-panel speed or intensity drag switched channel 2 OFF.
//
// ROOT CAUSE. Every Tune write — speed/intensity, grouping/spacing, colour
// sequence, effect — went through `applyChannelFilter`, the DESIGN-apply
// shape. It emits the full partition over the channel census: the targeted
// channels get the change plus `on: true`, and EVERY other channel gets
// `{id, on: false}`. So:
//   • narrowed to channel 1, a drag sent `{id: 1, on: false}` → channel 2 dark;
//   • a channel left out of shows got the same `on:false` even under "All";
//   • a channel switched off by hand was switched back ON by any drag.
//
// These tests drive the REAL controls of the REAL panel, into the REAL
// WledService (simulation mode) — normalizer, participation, geometry pin —
// and assert on every body that would have reached the controller.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/patterns/color_sequence_builder.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_payload.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_sender.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/recording_wled_repository.dart';

class _SeededWledNotifier extends WledNotifier {
  _SeededWledNotifier({this.grp = 1, this.spc = 0});
  final int grp;
  final int spc;

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
        colorGroupSize: grp,
        spacing: spc,
        colorSequence: const [Color(0xFFFF0000), Color(0xFF0000FF)],
      );
}

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Front', start: 0, stop: 30, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Garage', start: 30, stop: 60, gpioPin: 14),
];

ProviderContainer _container(
  WledRepository repo, {
  Set<int>? selected,
  List<int>? participating,
  List<DeviceChannel> channels = _twoChannels,
  int grp = 1,
  int spc = 0,
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => _SeededWledNotifier(grp: grp, spc: spc)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(channels),
    participatingChannelIdsProvider.overrideWithValue(participating),
    demoModeProvider.overrideWith((ref) => false),
  ]);
  addTearDown(c.dispose);
  c.read(selectedChannelIdsProvider.notifier).state = selected;
  return c;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ProviderContainer c, {
  int effectId = 28,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PatternAdjustmentPanel(
            initialSpeed: 128,
            initialIntensity: 128,
            initialEffectId: effectId,
            initialColors: const [
              [255, 0, 0, 0],
              [0, 0, 255, 0],
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Lets the 200 ms debounce fire and the write complete.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  await tester.pump();
}

Finder get _speedSlider => find.descendant(
    of: find.byType(EffectSpeedSlider), matching: find.byType(Slider));

/// The intensity slider: the panel's second Slider (the speed slider's is
/// first in the column).
Finder get _intensitySlider => find.byType(Slider).at(1);

List<Map<String, dynamic>> _segs(Map<String, dynamic> body) =>
    [for (final s in body['seg'] as List) Map<String, dynamic>.from(s as Map)];

void _expectNoPowerChange(Map<String, dynamic> body) {
  expect(body.containsKey('on'), isFalse,
      reason: 'an adjustment must not switch the house on or off: $body');
  for (final s in _segs(body)) {
    expect(s.containsKey('on'), isFalse,
        reason: 'an adjustment must not switch channel ${s['id']} on or off: '
            '$body');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the payload shape (pure)', () {
    test('names only the targeted channels and carries no `on`', () {
      final p = buildChannelTweakPayload({'sx': 90, 'on': true}, const [0]);
      expect(p, {
        'seg': [
          {'id': 0, 'sx': 90}
        ]
      });
      expect(payloadTouchesPower(p), isFalse);
    });

    test('geometry and ids in the fields are dropped', () {
      final p = buildChannelTweakPayload(
          {'grp': 2, 'id': 9, 'start': 0, 'stop': 5, 'rev': true, 'mi': true},
          const [1, 0]);
      expect(p['seg'], [
        {'id': 0, 'grp': 2},
        {'id': 1, 'grp': 2},
      ]);
    });
  });

  group('narrowed to channel 1 of 2 — channel 2 is never touched', () {
    testWidgets('speed drag', (tester) async {
      final controller = WledService('http://mock');
      final c = _container(controller, selected: {0});
      await _pumpPanel(tester, c);

      await tester.drag(_speedSlider, const Offset(-120, 0));
      await _flush(tester);

      expect(controller.simulatedStatePosts, hasLength(1));
      final body = controller.simulatedStatePosts.single;
      _expectNoPowerChange(body);
      final segs = _segs(body);
      expect([for (final s in segs) s['id']], [0],
          reason: 'channel 2 (id 1) must not appear at all — no `on:false`');
      expect(segs.single.containsKey('sx'), isTrue);
    });

    testWidgets('intensity drag', (tester) async {
      final controller = WledService('http://mock');
      final c = _container(controller, selected: {0});
      await _pumpPanel(tester, c);

      await tester.drag(_intensitySlider, const Offset(80, 0));
      await _flush(tester);

      final body = controller.simulatedStatePosts.single;
      _expectNoPowerChange(body);
      expect([for (final s in _segs(body)) s['id']], [0]);
      expect(_segs(body).single['ix'], isNot(128));
    });

    testWidgets('effect menu', (tester) async {
      final controller = WledService('http://mock');
      final c = _container(controller, selected: {0});
      await _pumpPanel(tester, c);

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chunchun').last);
      await tester.pumpAndSettle();

      final body = controller.simulatedStatePosts.single;
      _expectNoPowerChange(body);
      final seg = _segs(body).single;
      expect(seg['id'], 0);
      expect(seg['fx'], 111);
      expect(seg['sx'], effectDefaultSpeed(111),
          reason: 'item D: a selected effect starts at its roofline speed');
    });

    testWidgets('colour sequence', (tester) async {
      final controller = WledService('http://mock');
      final c = _container(controller, selected: {0}, grp: 2, spc: 1);
      await _pumpPanel(tester, c);

      // Long-press a slot removes it — the builder then reports the sequence.
      await tester.longPress(find
          .descendant(
              of: find.byType(ColorSequenceBuilder),
              matching: find.byType(GestureDetector))
          .first);
      await _flush(tester);

      final body = controller.simulatedStatePosts.single;
      _expectNoPowerChange(body);
      final seg = _segs(body).single;
      expect(seg['id'], 0);
      expect(seg['grp'], 2,
          reason: 'the live grouping rides along — a colour tweak must not '
              'flatten a "1 On 2 Off" look to grp 1');
      expect(seg['spc'], 1);
    });
  });

  testWidgets('"All Channels", one channel left out of shows: the drag does '
      'not switch it off', (tester) async {
    final controller = WledService('http://mock');
    final c = _container(controller, selected: null, participating: const [0]);
    await _pumpPanel(tester, c);

    await tester.drag(_speedSlider, const Offset(-120, 0));
    await _flush(tester);

    final body = controller.simulatedStatePosts.single;
    _expectNoPowerChange(body);
    expect([for (final s in _segs(body)) s['id']], [0]);
  });

  testWidgets('"All Channels", every channel adjusted — and none relit',
      (tester) async {
    // A channel the customer switched off with its power icon must stay off:
    // the old path stamped `on:true` on every targeted channel.
    final controller = WledService('http://mock');
    final c = _container(controller, selected: null);
    await _pumpPanel(tester, c);

    await tester.drag(_speedSlider, const Offset(-120, 0));
    await _flush(tester);

    final body = controller.simulatedStatePosts.single;
    _expectNoPowerChange(body);
    expect([for (final s in _segs(body)) s['id']], [0, 1]);
  });

  group('row 80 — a refused adjustment says so and the slider goes back', () {
    testWidgets('speed', (tester) async {
      final repo = RecordingWledRepository(succeed: false);
      final c = _container(repo, selected: null);
      await _pumpPanel(tester, c);

      final before = tester.widget<Slider>(_speedSlider).value;
      await tester.drag(_speedSlider, const Offset(-120, 0));
      await _flush(tester);

      expect(repo.applied, hasLength(1));
      expect(payloadTouchesPower(repo.applied.single), isFalse);
      expect(c.read(wledCommandFailureProvider)?.message,
          kAdjustmentFailedMessage);
      expect(tester.widget<Slider>(_speedSlider).value, before,
          reason: 'the control shows what the lights are doing');
    });

    testWidgets('an accepted adjustment reaches the Home preview',
        (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, selected: null);
      await _pumpPanel(tester, c);

      await tester.drag(_intensitySlider, const Offset(80, 0));
      await _flush(tester);

      final sent = (_segs(repo.applied.single).first)['ix'] as int;
      expect(c.read(wledStateProvider).intensity, sent);
    });
  });

  testWidgets('row 1 — a closed gate is explained, nothing is sent',
      (tester) async {
    final repo = RecordingWledRepository();
    // Narrowed to a channel this controller does not have.
    final c = _container(repo, selected: {7});
    await _pumpPanel(tester, c);

    await tester.drag(_speedSlider, const Offset(-120, 0));
    await _flush(tester);

    expect(repo.writeCount, 0);
    expect(c.read(wledCommandFailureProvider)?.message,
        contains('No channels are selected'));
  });

  testWidgets('row 81 — a refused direction flips the toggle back',
      (tester) async {
    // RecordingWledRepository cannot state geometry (applyGeometryJson →
    // false), like the relay and demo transports.
    final repo = RecordingWledRepository();
    final c = _container(repo, selected: null);
    await _pumpPanel(tester, c);

    await tester.tap(find.text('R→L'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final toggle =
        tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(toggle.selected, {false}, reason: 'back to where the lights are');
    expect(c.read(wledCommandFailureProvider)?.message,
        contains("Direction couldn't be changed"));
  });
}
