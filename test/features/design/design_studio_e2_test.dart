// +110 package E2 — Design Studio, from its real entry point
// (AIDesignStudioScreen, the widget every design-studio route builds).
//
//  item 1a  gated on a segmented roofline; the blocked state names what is
//           missing and opens the walkthrough; never a silent no-op;
//  item 1b  named features are the selection unit in the editor;
//  row 2    an orchestrator error shows its message, suggestions and a route
//           to roofline setup;
//  row 115  Start over; a fresh studio on entry;
//  row 116  Preview on lights sends the composed design;
//  row 117  the manual editor opens ON the composed design;
//  row 118  the detail screen says "Static (per-pixel)" / "(animated)".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_studio_gate.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/design/screens/ai_design_studio_screen.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

final _now = DateTime(2026, 9, 29);
const _ip = '192.0.2.10'; // documentation range
const _controller = ControllerInfo(id: 'ctl-a', ip: _ip, name: 'House');
const _second = ControllerInfo(id: 'ctl-b', ip: '192.0.2.11', name: 'Shop');

const _channels = [
  DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 40, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Ch2', start: 40, stop: 70, gpioPin: 3),
];

RooflineConfiguration _config(List<RooflineSegment> segments) =>
    RooflineConfiguration(
      id: 'r',
      name: 'Roof',
      segments: segments,
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 2,
      controllerId: 'ctl-a',
      channelPixelCounts: const {0: 40, 1: 30},
    );

/// Traced but never marked: what every production map looks like today.
RooflineConfiguration _unsegmented() => _config(const [
      RooflineSegment(id: 'a', name: 'Segment 1', pixelCount: 40, channelIndex: 0),
      RooflineSegment(id: 'b', name: 'Segment 2', pixelCount: 30, channelIndex: 1),
    ]);

/// Marked by the walkthrough: corners, a peak and the runs between.
RooflineConfiguration _segmented() => _config(const [
      RooflineSegment(id: 'c1', name: '', pixelCount: 4, startPixel: 0,
          type: SegmentType.corner, featureConfirmed: true, channelIndex: 0),
      RooflineSegment(id: 'r1', name: '', pixelCount: 14, startPixel: 4,
          type: SegmentType.run, featureConfirmed: true, channelIndex: 0),
      RooflineSegment(id: 'p1', name: '', pixelCount: 6, startPixel: 18,
          type: SegmentType.peak, featureConfirmed: true, channelIndex: 0),
      RooflineSegment(id: 'r2', name: '', pixelCount: 12, startPixel: 24,
          type: SegmentType.run, featureConfirmed: true, channelIndex: 0),
      RooflineSegment(id: 'c2', name: '', pixelCount: 4, startPixel: 36,
          type: SegmentType.corner, featureConfirmed: true, channelIndex: 0),
      RooflineSegment(id: 'r3', name: 'Garage run', pixelCount: 30, startPixel: 0,
          type: SegmentType.run, featureConfirmed: true, channelIndex: 1),
    ]);

ComposedPattern _composed({bool motion = false}) => ComposedPattern(
      name: motion ? 'Blue chase' : 'Blue wash',
      colorGroups: const [
        LedColorGroup(startLed: 0, endLed: 39, color: [0, 0, 255, 0]),
        LedColorGroup(startLed: 40, endLed: 69, color: [255, 0, 0, 0]),
      ],
      effectId: motion ? 28 : 0,
      hasMotion: motion,
      wledPayload: const {'on': true},
      totalPixels: 70,
      composedAt: _now,
    );

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _FakeZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [];
}

/// The walkthrough's editor notifier, without Firestore.
class _FakeEditor extends RooflineConfigEditorNotifier {
  _FakeEditor(super.ref);
  @override
  Future<void> initialize() async {}
}

class _Repo implements WledRepository, PerPixelWriter {
  final json = <Map<String, dynamic>>[];
  final pixels = <int, List<PixelSpan>>{};
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return true;
  }

  @override
  Future<bool> applyPerPixel(
      {int segmentId = 0,
      required List<PixelSpan> spans,
      int chunkSize = kDefaultPixelChunkSize}) async {
    pixels[segmentId] = spans;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides({
  required Stream<RooflineConfiguration?> roofline,
  List<ControllerInfo> controllers = const [_controller],
  Stream<List<ControllerInfo>>? controllerStream,
  String? selectedId = 'ctl-a',
  String? selectedIp = _ip,
  _Repo? repo,
}) =>
    [
      controllersStreamProvider.overrideWith(
          (ref) => controllerStream ?? Stream.value(controllers)),
      selectedControllerIdProvider.overrideWithValue(selectedId),
      selectedDeviceIpProvider.overrideWith((ref) => selectedIp),
      currentRooflineConfigProvider.overrideWith((ref) => roofline),
      designsStreamProvider
          .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('u'),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(_channels),
      participatingChannelIdsProvider.overrideWithValue(null),
      authStateProvider.overrideWith((ref) => Stream.value(null)),
      demoModeProvider.overrideWith((ref) => false),
      wledRepositoryProvider.overrideWithValue(repo),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
      zoneSegmentsProvider.overrideWith(() => _FakeZoneSegments()),
      rooflineConfigEditorProvider.overrideWith((ref) => _FakeEditor(ref)),
      controllerRepositoryProvider.overrideWith((ref, target) => null),
    ];

Future<ProviderContainer> _pump(WidgetTester tester, List<Override> overrides,
    {Widget home = const AIDesignStudioScreen()}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: ProviderContainer(overrides: overrides),
    child: MaterialApp(key: key, home: home),
  ));
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(key.currentContext!);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('item 1a — the gate', () {
    testWidgets('an unsegmented roofline shows the gate, names what is '
        'missing, and reaches the walkthrough', (tester) async {
      await _pump(tester, _overrides(roofline: Stream.value(_unsegmented())));

      expect(find.byKey(const ValueKey('studio-gate')), findsOneWidget);
      expect(find.textContaining("corners and peaks aren't marked yet"),
          findsOneWidget);
      // The editor is not reachable behind the gate.
      expect(find.text('Create Design'), findsNothing);
      expect(find.text('Manual'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('studio-gate-walkthrough')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RooflineFeatureWalkthroughScreen), findsOneWidget);
    });

    testWidgets('no map at all → the gate says so and offers the walkthrough',
        (tester) async {
      await _pump(tester, _overrides(roofline: Stream.value(null)));

      expect(find.textContaining("roofline isn't mapped yet"), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-gate-walkthrough')), findsOneWidget);
    });

    testWidgets('partly marked → names the channel still to mark',
        (tester) async {
      final partly = _config([
        ..._segmented().segments.where((s) => s.channelIndex == 0),
        const RooflineSegment(
            id: 'x', name: 'Segment 2', pixelCount: 30, channelIndex: 1),
      ]);
      await _pump(tester, _overrides(roofline: Stream.value(partly)));

      expect(find.textContaining("Channel 2's corners and peaks aren't marked"),
          findsOneWidget);
      expect(find.text('Mark the rest'), findsOneWidget);
    });

    testWidgets('two controllers and none selected → choose, never guess',
        (tester) async {
      await _pump(
          tester,
          _overrides(
              roofline: Stream.value(_segmented()),
              controllers: const [_controller, _second],
              selectedId: null,
              selectedIp: null));

      expect(find.text('Choose a controller'), findsOneWidget);
      expect(find.text('Create Design'), findsNothing);
    });

    testWidgets('while the roofline loads: a spinner and a sentence, not a '
        'blank studio', (tester) async {
      final never = StreamController<RooflineConfiguration?>();
      addTearDown(never.close);
      await _pump(tester, _overrides(roofline: never.stream));

      expect(find.text('Checking your roofline…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a segmented roofline opens the studio', (tester) async {
      await _pump(tester, _overrides(roofline: Stream.value(_segmented())));

      expect(find.byKey(const ValueKey('studio-gate')), findsNothing);
      expect(find.text('Create Design'), findsOneWidget);
      expect(find.textContaining('2 corners · 1 peak · 3 runs'), findsOneWidget);
    });

    test('gateForSegmentation is pure and covers every state', () {
      expect(gateForSegmentation(RooflineSegmentation.none).state,
          DesignStudioGateState.noMap);
      expect(gateForSegmentation(assessRooflineSegmentation(_unsegmented())).state,
          DesignStudioGateState.unsegmented);
      expect(gateForSegmentation(assessRooflineSegmentation(_segmented())).state,
          DesignStudioGateState.ready);
    });
  });

  group('item 1b — sections are the selection unit', () {
    testWidgets('the editor lists the channel\'s sections; a tap selects it',
        (tester) async {
      await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      await tester.tap(find.text('Manual'));
      await tester.pump();

      expect(find.byKey(const ValueKey('editor-sections')), findsOneWidget);
      expect(find.textContaining('Corner 1'), findsOneWidget);
      expect(find.textContaining('Corner 2'), findsOneWidget);
      expect(find.textContaining('Peak'), findsOneWidget);
      expect(find.textContaining('Run 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('section-p1')));
      await tester.pump();
      // The peak is 6 lights (18–23): exactly those are selected.
      expect(find.textContaining('6 selected on Channel 1'), findsOneWidget);

      // Another section REPLACES the selection; a long-press ADDS.
      await tester.tap(find.byKey(const ValueKey('section-c1')));
      await tester.pump();
      expect(find.textContaining('4 selected on Channel 1'), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('section-p1')));
      await tester.pump();
      expect(find.textContaining('10 selected on Channel 1'), findsOneWidget);
    });

    testWidgets('the installer\'s own name wins over the generated one',
        (tester) async {
      await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      await tester.tap(find.text('Manual'));
      await tester.pump();
      await tester.tap(find.text('Channel 2'));
      await tester.pump();

      expect(find.textContaining('Garage run'), findsOneWidget);
    });

    testWidgets('an unmarked channel says so and offers the walkthrough '
        '(the editor is also reached from My Designs)', (tester) async {
      await _pump(tester, _overrides(roofline: Stream.value(_unsegmented())),
          home: const Scaffold(body: ManualDesignEditor()));

      expect(find.byKey(const ValueKey('editor-no-sections')), findsOneWidget);
      expect(find.text('Mark corners and peaks'), findsOneWidget);
    });
  });

  group('row 2 — the orchestrator\'s message is shown', () {
    testWidgets('a roofline error routes to roofline setup', (tester) async {
      final c = await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      c.read(designStudioLastErrorProvider.notifier).state =
          DesignStudioResult.error(
        'No roofline configuration found. Please set up your roofline first.',
        suggestions: const ['Go to Settings > Roofline Setup'],
      );
      c.read(designStudioStateProvider.notifier).state = DesignStudioStatus.error;
      await tester.pump();

      expect(find.byKey(const ValueKey('studio-error')), findsOneWidget);
      expect(find.textContaining('No roofline configuration found'), findsOneWidget);
      expect(find.textContaining('Go to Settings > Roofline Setup'), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-error-roofline')), findsOneWidget);
      // The prompt is still there: not a dead end.
      expect(find.text('Create Design'), findsOneWidget);
    });

    testWidgets('a composition failure shows its suggestions and the manual '
        'door', (tester) async {
      final c = await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      c.read(designStudioLastErrorProvider.notifier).state =
          DesignStudioResult.error(
        'That spacing does not fit on a 40-light run.',
        suggestions: const ['Try 1 on, 3 off'],
        recommendManual: true,
      );
      c.read(designStudioStateProvider.notifier).state = DesignStudioStatus.error;
      await tester.pump();

      expect(find.textContaining('Try 1 on, 3 off'), findsOneWidget);
      expect(find.text('Paint it by hand'), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-error-roofline')), findsNothing);
    });

    test('recordDesignStudioResultWith records an error and clears it on '
        'the next success', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      recordDesignStudioResultWith(c.read, DesignStudioResult.error('bad'));
      expect(c.read(designStudioLastErrorProvider)?.errorMessage, 'bad');
      expect(c.read(designStudioStateProvider), DesignStudioStatus.error);
      recordDesignStudioResultWith(
          c.read,
          DesignStudioResult.ready(
              intent: DesignIntentFixture.any, pattern: _composed()));
      expect(c.read(designStudioLastErrorProvider), isNull);
      expect(c.read(composedPatternProvider), isNotNull);
    });
  });

  group('row 115 — Start over, and a fresh studio on entry', () {
    testWidgets('a question left pending is gone on the next visit',
        (tester) async {
      final container = ProviderContainer(
          overrides: _overrides(roofline: Stream.value(_segmented())));
      addTearDown(container.dispose);
      container.read(pendingClarificationsProvider.notifier).state = const [
        ClarificationQuestion(
          id: 'q1',
          type: ClarificationType.colorAmbiguity,
          questionText: 'Which blue?',
          options: [ClarificationOption(id: 'a', label: 'Royal blue')],
        ),
      ];
      container.read(designStudioStateProvider.notifier).state =
          DesignStudioStatus.needsClarification;

      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AIDesignStudioScreen()),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Which blue?'), findsNothing);
      expect(container.read(designStudioStateProvider), DesignStudioStatus.idle);
      expect(find.text('Create Design'), findsOneWidget);
    });

    testWidgets('the clarification panel has Start over', (tester) async {
      final c = await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      c.read(pendingClarificationsProvider.notifier).state = const [
        ClarificationQuestion(
          id: 'q1',
          type: ClarificationType.colorAmbiguity,
          questionText: 'Which blue?',
          options: [ClarificationOption(id: 'a', label: 'Royal blue')],
        ),
      ];
      c.read(designStudioStateProvider.notifier).state =
          DesignStudioStatus.needsClarification;
      await tester.pump();
      expect(find.text('Which blue?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clarification-start-over')));
      await tester.pump();

      expect(find.text('Which blue?'), findsNothing);
      expect(c.read(designStudioStateProvider), DesignStudioStatus.idle);
      expect(find.text('Create Design'), findsOneWidget);
    });

    testWidgets('the app bar\'s Start over clears a composed design',
        (tester) async {
      final c = await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      c.read(composedPatternProvider.notifier).state = _composed();
      c.read(designStudioStateProvider.notifier).state = DesignStudioStatus.ready;
      await tester.pump();
      expect(find.text('Apply to Lights'), findsOneWidget);

      await tester.tap(find.byTooltip('Start over'));
      await tester.pump();

      expect(c.read(composedPatternProvider), isNull);
      expect(find.text('Apply to Lights'), findsNothing);
    });
  });

  group('row 116 — Preview on lights is wired', () {
    testWidgets('turning it on with a design sends the design', (tester) async {
      final repo = _Repo();
      final c = await _pump(
          tester, _overrides(roofline: Stream.value(_segmented()), repo: repo));
      c.read(composedPatternProvider.notifier).state = _composed();
      c.read(designStudioStateProvider.notifier).state = DesignStudioStatus.ready;
      await tester.pump();

      await tester.tap(find.byTooltip('Preview on lights: OFF'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(c.read(livePreviewEnabledProvider), isTrue);
      expect(repo.json, isNotEmpty, reason: 'the preview reached the lights');
      // With no live segment map the composed groups land on one channel.
      expect(repo.pixels, isNotEmpty);
      expect(find.byTooltip('Preview on lights: ON'), findsOneWidget);
    });

    testWidgets('a new design while it is on is previewed too', (tester) async {
      final repo = _Repo();
      final c = await _pump(
          tester, _overrides(roofline: Stream.value(_segmented()), repo: repo));
      c.read(livePreviewEnabledProvider.notifier).state = true;
      await tester.pump();

      c.read(composedPatternProvider.notifier).state = _composed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.json, isNotEmpty);
    });
  });

  group('row 117 — the manual editor opens on the composed design', () {
    testWidgets('tune icon → editor loaded with the design', (tester) async {
      final c = await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      c.read(composedPatternProvider.notifier).state = _composed();
      c.read(designStudioStateProvider.notifier).state = DesignStudioStatus.ready;
      await tester.pump();

      await tester.tap(find.byTooltip('Edit this design by hand'));
      await tester.pump();

      final editor = tester.widget<ManualDesignEditor>(find.byType(ManualDesignEditor));
      expect(editor.initialDesign, isNotNull);
      expect(editor.initialDesign!.name, 'Blue wash');
      expect(editor.initialDesign!.channels, isNotEmpty);
    });

    testWidgets('with no design the tooltip says Manual controls and the '
        'editor is blank', (tester) async {
      await _pump(tester, _overrides(roofline: Stream.value(_segmented())));
      await tester.tap(find.byTooltip('Manual controls'));
      await tester.pump();
      final editor = tester.widget<ManualDesignEditor>(find.byType(ManualDesignEditor));
      expect(editor.initialDesign, isNull);
    });
  });

  group('row 118 — the detail screen describes what Apply will do', () {
    CustomDesign design({bool motion = false, bool painted = false}) =>
        CustomDesign(
          id: 'd', name: 'D', ownerId: 'u', createdAt: _now, updatedAt: _now,
          perPixel: painted,
          channels: const [
            ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 40,
                effectId: 28, colorGroups: [
                  LedColorGroup(startLed: 0, endLed: 39, color: [0, 0, 255, 0]),
                ]),
          ],
          composedPattern: painted
              ? null
              : {'effect_id': motion ? 28 : 0, 'has_motion': motion, 'speed': 120},
        );

    Future<void> pumpDetail(WidgetTester tester, CustomDesign d) async {
      await _pump(
        tester,
        [
          ..._overrides(roofline: Stream.value(_segmented())),
          designByIdProvider('d').overrideWith((ref) async => d),
        ],
        home: const Scaffold(body: DesignDetailScreen(designId: 'd', embedded: true)),
      );
      await tester.pump();
    }

    testWidgets('a painted design is Static (per-pixel)', (tester) async {
      await pumpDetail(tester, design(painted: true));
      expect(find.text('Static (per-pixel)'), findsOneWidget);
      // Edit is available for every kind now (row 117).
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit')).onPressed,
          isNotNull);
    });

    testWidgets('an AI design without motion is Static (per-pixel)',
        (tester) async {
      await pumpDetail(tester, design());
      expect(find.text('Static (per-pixel)'), findsOneWidget);
    });

    testWidgets('an AI design with motion names its effect as animated',
        (tester) async {
      await pumpDetail(tester, design(motion: true));
      expect(find.textContaining('(animated)'), findsOneWidget);
      expect(find.text('Static (per-pixel)'), findsNothing);
    });
  });
}

/// A DesignIntent for the state-recording test; the intent's contents are
/// not read by the recorder.
class DesignIntentFixture {
  static const any = DesignIntent(originalPrompt: 'blue wash', layers: []);
}
