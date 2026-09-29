// +110 E1 follow-ups on the Home Tune panel, from the package's own customer
// walk — every case driven from the real control.
//
//   2. House OFF: the sliders changed nothing visible and read as broken.
//      Chosen: DISABLE them, say why, and offer "Turn on". Not "an adjustment
//      turns the lights on" — the PRIORITY rule is that an adjustment never
//      changes power.
//   3. Away from home the direction control said "Connect to venue Wi-Fi"
//      (commercial copy) to homeowners.
//   4. Away from home a drag queued one slow relay command per pause. Now ONE
//      write when the drag settles; at home the lights still follow, with at
//      most one write in flight.
//   Strobe: Strobe Mega is gone from the effect menu; a Strobe speed drag
//      never sends more than 240.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_enforcement.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/wled/pattern_adjustment_pacer.dart';
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_sender.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/home_dashboard_harness.dart';
import '../helpers/recording_wled_repository.dart';

/// A repository whose writes wait until the test releases them — to see how
/// many are in flight at once.
class _GatedRepo extends RecordingWledRepository {
  final gates = <Completer<bool>>[];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) {
    super.applyJson(payload);
    final gate = Completer<bool>();
    gates.add(gate);
    return gate.future;
  }
}

ProviderContainer _container(
  RecordingWledRepository repo, {
  bool isOn = true,
  int effectId = 28,
  ConnectivityStatus status = ConnectivityStatus.local,
  SiteMode mode = SiteMode.residential,
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(
        kHomeLitState.copyWith(isOn: isOn, effectId: effectId))),
    wledConnectivityStatusProvider
        .overrideWith((ref) => Stream<ConnectivityStatus>.value(status)),
    deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    demoModeProvider.overrideWith((ref) => false),
    siteModeProvider.overrideWith((ref) => mode),
    // A manual power change reads the schedule-enforcement service, whose
    // periodic check is not what these tests are about.
    scheduleEnforcementModeProvider
        .overrideWith((ref) => ScheduleEnforcementMode.disabled),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _pumpPanel(WidgetTester tester, ProviderContainer c,
    {int effectId = 28, bool showEffectSelector = false}) async {
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
            showEffectSelector: showEffectSelector,
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

Future<void> _settle(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _speedSlider => find.descendant(
    of: find.byType(EffectSpeedSlider), matching: find.byType(Slider));
Finder get _intensitySlider => find.byType(Slider).at(1);

/// A drag in [steps] moves of [dx], pausing [pause] between them — longer
/// than the at-home debounce, shorter than the away settle.
Future<TestGesture> _dragInSteps(
  WidgetTester tester,
  Finder slider, {
  int steps = 5,
  double dx = 30,
  Duration pause = const Duration(milliseconds: 400),
}) async {
  final start = tester.getTopLeft(slider) + const Offset(40, 20);
  final g = await tester.startGesture(start);
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(dx, 0));
    await tester.pump(pause);
  }
  return g;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('item 2 — the house is OFF', () {
    testWidgets('the controls are disabled and say why; a drag sends nothing',
        (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, isOn: false);
      await _pumpPanel(tester, c);

      expect(find.byKey(const ValueKey('tune-lights-off')), findsOneWidget);
      expect(find.text('Your lights are off. Turn them on to adjust them.'),
          findsOneWidget);

      await tester.drag(_intensitySlider, const Offset(120, 0));
      await _settle(tester);
      expect(repo.writeCount, 0, reason: 'nothing to adjust while dark');
    });

    testWidgets('"Turn on" is the explicit way on — the house switches on and '
        'the controls come back', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, isOn: false);
      await _pumpPanel(tester, c);

      await tester.tap(find.byKey(const ValueKey('tune-turn-on')));
      await _settle(tester);

      expect(c.read(wledStateProvider).isOn, isTrue);
      expect(repo.writeCount, greaterThan(0), reason: 'a power-on was sent');
      expect(find.byKey(const ValueKey('tune-lights-off')), findsNothing);

      final before = repo.applied.length;
      await tester.drag(_intensitySlider, const Offset(120, 0));
      await _settle(tester);
      expect(repo.applied.length, before + 1);
    });

    testWidgets('lit: no notice', (tester) async {
      await _pumpPanel(tester, _container(RecordingWledRepository()));
      expect(find.byKey(const ValueKey('tune-lights-off')), findsNothing);
    });
  });

  group('item 3 — direction away from home', () {
    testWidgets('a homeowner reads home wording, never "venue"',
        (tester) async {
      final c = _container(RecordingWledRepository(),
          status: ConnectivityStatus.remote);
      await _pumpPanel(tester, c);

      final text = tester
          .widget<Text>(find.byKey(const ValueKey('tune-direction-away')))
          .data!;
      expect(text, directionLanOnlyMessage(SiteMode.residential));
      expect(text, contains('home Wi-Fi'));
      expect(text.toLowerCase(), isNot(contains('venue')));
    });

    testWidgets('a commercial site keeps the venue wording', (tester) async {
      final c = _container(RecordingWledRepository(),
          status: ConnectivityStatus.remote, mode: SiteMode.commercial);
      await _pumpPanel(tester, c);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('tune-direction-away')))
              .data,
          contains('venue'));
    });
  });

  group('item 4 — pacing a drag', () {
    testWidgets('AWAY: a drag sends nothing while it moves and ONE write when '
        'it settles, carrying the final value', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, status: ConnectivityStatus.remote);
      await _pumpPanel(tester, c);

      final g = await _dragInSteps(tester, _intensitySlider);
      expect(repo.applied, isEmpty,
          reason: 'five pauses longer than the at-home debounce — no writes');

      await g.up();
      await _settle(tester);

      expect(repo.applied, hasLength(1));
      final seg = (repo.applied.single['seg'] as List).cast<Map>().first;
      final shown = tester.widget<Slider>(_intensitySlider).value.round();
      expect(seg['ix'], shown, reason: 'the value the finger left it at');
    });

    testWidgets('AT HOME: the lights follow the drag, but never two writes in '
        'flight — what arrives meanwhile goes in ONE next write',
        (tester) async {
      final repo = _GatedRepo();
      final c = _container(repo);
      await _pumpPanel(tester, c);

      final g = await _dragInSteps(tester, _intensitySlider, steps: 1);
      expect(repo.applied, hasLength(1), reason: 'the lights follow');

      // Keep dragging while that write is still out.
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(repo.applied, hasLength(1), reason: 'one in flight, no queue');

      repo.gates.first.complete(true);
      await _settle(tester);
      expect(repo.applied, hasLength(2),
          reason: 'everything that arrived meanwhile, in one write');
      final seg = (repo.applied.last['seg'] as List).cast<Map>().first;
      expect(seg['ix'], tester.widget<Slider>(_intensitySlider).value.round());

      await g.up();
      for (final gate in repo.gates) {
        if (!gate.isCompleted) gate.complete(true);
      }
      await _settle(tester);
      expect(repo.applied, hasLength(2),
          reason: 'lifting the finger adds nothing already sent');
    });
  });

  group('the pacer itself', () {
    testWidgets('away: steps wait, the settle sends once', (tester) async {
      var sends = 0;
      final p = AdjustmentPacer(
          flush: () async => sends++, isRemote: () => true);
      for (var i = 0; i < 6; i++) {
        p.changed();
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(sends, 0);
      p.settled();
      await tester.pump();
      expect(sends, 1);
      p.dispose();
    });

    testWidgets('away, with no settle signal (a colour wheel): one send after '
        'the idle period', (tester) async {
      var sends = 0;
      final p = AdjustmentPacer(
          flush: () async => sends++, isRemote: () => true);
      p.changed();
      await tester.pump(const Duration(milliseconds: 1400));
      expect(sends, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sends, 1);
      p.dispose();
    });

    testWidgets('a discrete tap is not a drag: it goes after the short delay, '
        'even away', (tester) async {
      var sends = 0;
      final p = AdjustmentPacer(
          flush: () async => sends++, isRemote: () => true);
      p.changed(dragging: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(sends, 1);
      p.dispose();
    });

    testWidgets('dispose drops what is pending', (tester) async {
      var sends = 0;
      final p = AdjustmentPacer(
          flush: () async => sends++, isRemote: () => false);
      p.changed();
      p.dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(sends, 0);
    });
  });

  group('Strobe decision', () {
    testWidgets('the effect menu no longer offers Strobe Mega (Strobe stays)',
        (tester) async {
      final c = _container(RecordingWledRepository());
      await _pumpPanel(tester, c, showEffectSelector: true);

      await tester.tap(find.byType(DropdownButton<int>));
      await _settle(tester, 6);

      expect(find.text('Strobe Mega'), findsNothing);
      expect(find.text('Strobe'), findsWidgets);
    });

    testWidgets('a speed drag on a live Strobe never sends more than 240',
        (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, effectId: 23);
      await _pumpPanel(tester, c, effectId: 23);

      // Extended range, then all the way right.
      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.drag(_speedSlider, const Offset(2000, 0));
      await _settle(tester);

      final sx = [
        for (final body in repo.applied)
          for (final s in (body['seg'] as List).cast<Map>())
            if (s['sx'] != null) s['sx'] as int,
      ];
      expect(sx, isNotEmpty);
      expect(sx.every((v) => v <= kStrobeSpeedCap), isTrue, reason: '$sx');
    });
  });
}
