// +110 package E2 — every Design Studio surface this package owns, in each
// state a customer sees, through the foundation's text-scale harness at
// 1.0x / 1.75x / 2.0x with Bold Text on (docs/ACCESSIBILITY_TEXT_SCALE_TESTING.md).
//
// Sheets and dialogs are opened, not just the screens: the three dialogs are
// hosted the way the app opens them (a post-frame showDialog with frames:).
//
// Run with --dart-define=LUMINA_TEXT_SCALE_INVENTORY=true to print instead
// of fail (the pre-fix inventory in the report was taken that way).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/screens/ai_design_studio_screen.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_presets_section.dart';
import 'package:nexgen_command/features/design/widgets/design_dialogs.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/text_scale_harness.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

final _now = DateTime(2026, 9, 29);
const _controller = ControllerInfo(id: 'ctl-a', ip: '192.0.2.10', name: 'House');
const _second = ControllerInfo(id: 'ctl-b', ip: '192.0.2.11', name: 'Shop');

const _channels = [
  DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 40, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Ch2', start: 40, stop: 70, gpioPin: 3),
];

RooflineConfiguration _config(List<RooflineSegment> segments) =>
    RooflineConfiguration(
      id: 'r', name: 'Roof', segments: segments,
      createdAt: _now, updatedAt: _now,
      totalChannelCount: 2, controllerId: 'ctl-a',
      channelPixelCounts: const {0: 40, 1: 30},
    );

RooflineConfiguration _unsegmented() => _config(const [
      RooflineSegment(id: 'a', name: 'Segment 1', pixelCount: 40, channelIndex: 0),
      RooflineSegment(id: 'b', name: 'Segment 2', pixelCount: 30, channelIndex: 1),
    ]);

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

ComposedPattern _composed() => ComposedPattern(
      name: 'Blue wash with red garage',
      colorGroups: const [
        LedColorGroup(startLed: 0, endLed: 39, color: [0, 0, 255, 0]),
        LedColorGroup(startLed: 40, endLed: 69, color: [255, 0, 0, 0]),
      ],
      wledPayload: const {'on': true},
      totalPixels: 70,
      composedAt: _now,
    );

const _question = ClarificationQuestion(
  id: 'q1',
  type: ClarificationType.colorAmbiguity,
  questionText: 'Which blue do you mean for the long run along the garage?',
  context: 'You said "blue" — there are a few that look different on a roofline.',
  options: [
    ClarificationOption(
        id: 'a',
        label: 'Royal blue',
        description: 'Deep and saturated, reads well from the street',
        isRecommended: true,
        colorSwatches: [Color(0xFF1A3FCC)]),
    ClarificationOption(
        id: 'b', label: 'Ice blue', description: 'Pale, almost white'),
    ClarificationOption(id: 'manual', label: 'Set manually'),
  ],
);

CustomDesign _detailDesign({bool motion = false, bool painted = false}) =>
    CustomDesign(
      id: 'd', name: 'Harvest glow along the roofline', ownerId: 'u',
      description: 'Warm amber runs with brighter corners for the porch.',
      createdAt: _now, updatedAt: _now, perPixel: painted,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Front roofline', ledCount: 40,
            effectId: 28, colorGroups: [
              LedColorGroup(startLed: 0, endLed: 39, color: [255, 140, 0, 0]),
            ]),
        ChannelDesign(channelId: 1, channelName: 'Garage', ledCount: 30,
            effectId: 28, colorGroups: [
              LedColorGroup(startLed: 0, endLed: 29, color: [255, 60, 0, 0]),
            ]),
      ],
      composedPattern: painted
          ? null
          : {'effect_id': motion ? 28 : 0, 'has_motion': motion, 'speed': 120},
    );

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _FakeZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [];
}

List<Override> _overrides({
  required Stream<RooflineConfiguration?> roofline,
  List<ControllerInfo> controllers = const [_controller],
  String? selectedId = 'ctl-a',
  String? selectedIp = '192.0.2.10',
  CustomDesign? detail,
}) =>
    [
      controllersStreamProvider.overrideWith((ref) => Stream.value(controllers)),
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
      wledRepositoryProvider.overrideWithValue(null),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
      zoneSegmentsProvider.overrideWith(() => _FakeZoneSegments()),
      if (detail != null)
        designByIdProvider('d').overrideWith((ref) async => detail),
    ];

/// Seeds the studio's state providers AFTER the screen's own reset on entry
/// (the screen resets them in initState, so a seeded container alone would
/// be wiped). Runs post-frame, then the harness measures on later frames.
class _StudioStateSeeder extends ConsumerStatefulWidget {
  const _StudioStateSeeder({required this.seed, required this.child});
  final void Function(WidgetRef ref) seed;
  final Widget child;
  @override
  ConsumerState<_StudioStateSeeder> createState() => _StudioStateSeederState();
}

class _StudioStateSeederState extends ConsumerState<_StudioStateSeeder> {
  @override
  void initState() {
    super.initState();
    // Two frames: the studio resets its state one frame after entry, and the
    // seed must land after that.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.seed(ref);
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens a dialog the way the app does — from a post-frame callback.
class _DialogHost extends StatefulWidget {
  const _DialogHost(this.open);
  final Future<void> Function(BuildContext context) open;
  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.open(context));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

const bool _inventoryOnly =
    bool.fromEnvironment('LUMINA_TEXT_SCALE_INVENTORY');

Future<void> _check(
  WidgetTester tester,
  String name,
  Widget widget, {
  TextScaleHost host = TextScaleHost.screen,
  bool opensRoute = false,
  bool seeded = false,
  List<Finder> allowEllipsis = const <Finder>[],
}) async {
  final settle = Duration(milliseconds: opensRoute ? 900 : 500);
  final frames = opensRoute || seeded ? 6 : 1;
  if (_inventoryOnly) {
    final reports = await pumpAcrossTextScaleMatrix(tester, widget,
        host: host,
        settle: settle,
        frames: frames,
        allowEllipsis: allowEllipsis);
    // ignore: avoid_print
    print('=== $name\n${describeTextScaleMatrixFailures(reports) ?? 'clean'}');
    return;
  }
  await expectNoTextScaleDefectsAcrossMatrix(tester, widget,
      host: host,
      settle: settle,
      frames: frames,
      allowEllipsis: allowEllipsis);
}

Widget _studio(List<Override> overrides, {void Function(WidgetRef)? seed}) =>
    ProviderScope(
      overrides: overrides,
      child: seed == null
          ? const AIDesignStudioScreen()
          : _StudioStateSeeder(seed: seed, child: const AIDesignStudioScreen()),
    );

Widget _dialogApp(List<Override> overrides,
        Future<void> Function(BuildContext) open) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: nexGenPremiumDarkTheme,
        builder: TextScaleClamp.appBuilder,
        home: _DialogHost(open),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Design Studio — gate', () {
    testWidgets('unsegmented roofline', (tester) async {
      await _check(tester, 'studio / gate / unsegmented',
          _studio(_overrides(roofline: Stream.value(_unsegmented()))));
    });

    testWidgets('no map', (tester) async {
      await _check(tester, 'studio / gate / no map',
          _studio(_overrides(roofline: Stream.value(null))));
    });

    testWidgets('choose a controller', (tester) async {
      await _check(
          tester,
          'studio / gate / choose controller',
          _studio(_overrides(
              roofline: Stream.value(_segmented()),
              controllers: const [_controller, _second],
              selectedId: null,
              selectedIp: null)));
    });

    testWidgets('loading', (tester) async {
      final never = StreamController<RooflineConfiguration?>();
      addTearDown(never.close);
      await _check(tester, 'studio / gate / loading',
          _studio(_overrides(roofline: never.stream)));
    });
  });

  group('Design Studio — AI mode', () {
    testWidgets('idle with quick ideas', (tester) async {
      await _check(tester, 'studio / ai / idle',
          _studio(_overrides(roofline: Stream.value(_segmented()))));
    });

    testWidgets('a composed design with Save and Apply', (tester) async {
      await _check(
        tester,
        'studio / ai / ready',
        _studio(_overrides(roofline: Stream.value(_segmented())), seed: (ref) {
          ref.read(composedPatternProvider.notifier).state = _composed();
          ref.read(currentDesignIntentProvider.notifier).setIntent(
              const DesignIntent(originalPrompt: 'blue wash', layers: []));
          ref.read(designStudioStateProvider.notifier).state =
              DesignStudioStatus.ready;
        }),
        seeded: true,
      );
    });

    testWidgets('a roofline error with suggestions', (tester) async {
      await _check(
        tester,
        'studio / ai / error',
        _studio(_overrides(roofline: Stream.value(_segmented())), seed: (ref) {
          recordDesignStudioResultWith(
            ref.read,
            DesignStudioResult.error(
              'That spacing does not fit on a 40-light run — the shortest '
              'repeat is 1 on, 3 off.',
              suggestions: const [
                'Try 1 on, 3 off',
                'Ask for the corners and peaks only'
              ],
              recommendManual: true,
            ),
          );
        }),
        seeded: true,
      );
    });

    testWidgets('a clarification question', (tester) async {
      await _check(
        tester,
        'studio / ai / clarifying',
        _studio(_overrides(roofline: Stream.value(_segmented())), seed: (ref) {
          ref.read(pendingClarificationsProvider.notifier).state = [_question];
          ref.read(currentQuestionIndexProvider.notifier).state = 0;
          ref.read(clarificationChoicesProvider.notifier).state = {
            'q1': _question.options.first
          };
          ref.read(designStudioStateProvider.notifier).state =
              DesignStudioStatus.needsClarification;
        }),
        seeded: true,
      );
    });
  });

  group('Manual editor', () {
    testWidgets('with sections', (tester) async {
      await _check(
        tester,
        'editor / sections',
        ProviderScope(
          overrides: _overrides(roofline: Stream.value(_segmented())),
          child: const ManualDesignEditor(),
        ),
        host: TextScaleHost.component,
      );
    });

    testWidgets('without sections', (tester) async {
      await _check(
        tester,
        'editor / no sections',
        ProviderScope(
          overrides: _overrides(roofline: Stream.value(_unsegmented())),
          child: const ManualDesignEditor(),
        ),
        host: TextScaleHost.component,
      );
    });

    testWidgets('opened on a design', (tester) async {
      await _check(
        tester,
        'editor / on a design',
        ProviderScope(
          overrides: _overrides(roofline: Stream.value(_segmented())),
          child: ManualDesignEditor(initialDesign: _detailDesign(painted: true)),
        ),
        host: TextScaleHost.component,
      );
    });
  });

  group('Design detail', () {
    for (final (name, design) in [
      ('painted', _detailDesign(painted: true)),
      ('ai, static', _detailDesign()),
      ('ai, animated', _detailDesign(motion: true)),
    ]) {
      testWidgets(name, (tester) async {
        await _check(
          tester,
          'detail / $name',
          ProviderScope(
            overrides: _overrides(roofline: Stream.value(_segmented()), detail: design),
            child: const DesignDetailScreen(designId: 'd'),
          ),
          // The app-bar title is the design's own name — customer data,
          // shown in full in the body below it (the allowance the guide
          // permits). The bar itself is a shared widget.
          allowEllipsis: [find.byType(GlassAppBar)],
        );
      });
    }
  });

  group('Dialogs', () {
    testWidgets('Name This Design', (tester) async {
      await _check(
        tester,
        'dialog / name design',
        _dialogApp(
            _overrides(roofline: Stream.value(_segmented())),
            (context) =>
                showNameDesignDialog(context, initialName: 'Custom Design 3')),
        host: TextScaleHost.none,
        opensRoute: true,
      );
    });

    testWidgets('Rename Design', (tester) async {
      await _check(
        tester,
        'dialog / rename design',
        _dialogApp(
            _overrides(roofline: Stream.value(_segmented())),
            (context) => showRenameDesignDialog(context,
                currentName: 'Harvest glow along the roofline')),
        host: TextScaleHost.none,
        opensRoute: true,
      );
    });

    testWidgets('On / off pattern', (tester) async {
      await _check(
        tester,
        'dialog / on-off pattern',
        _dialogApp(
            _overrides(roofline: Stream.value(_segmented())),
            (context) => showOnOffPatternDialog(context,
                length: 162, start: 0, end: 6, on: 1, off: 6)),
        host: TextScaleHost.none,
        opensRoute: true,
      );
    });
  });

  group('Smart Presets section (flagged off on Home; still a screen we own)', () {
    testWidgets('with a map', (tester) async {
      await _check(
        tester,
        'smart presets / with map',
        ProviderScope(
          overrides: _overrides(roofline: Stream.value(_segmented())),
          child: const SmartPresetsSection(),
        ),
        host: TextScaleHost.component,
      );
    });

    testWidgets('without a map', (tester) async {
      await _check(
        tester,
        'smart presets / no map',
        ProviderScope(
          overrides: _overrides(roofline: Stream.value(null)),
          child: const SmartPresetsSection(),
        ),
        host: TextScaleHost.component,
      );
    });
  });
}
