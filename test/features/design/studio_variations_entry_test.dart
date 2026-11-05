// Roofline slice 3 — the AI studio's "Variations of …" entry, from the
// screen every design-studio route builds (AIDesignStudioScreen).
//
//  * a STAMPED roofline design gets an entry; a painted design with no stamp
//    gets no entry and a plain line telling the owner to re-save it on the
//    roofline first; an effect design is not listed (owner decision 3);
//  * choosing one sets the session's base: the strip names the design, the
//    variation ideas replace the quick ideas, the prompt composes in the
//    design's colours over its stamped bus lengths;
//  * the strip's close and Start over both clear it.
//
// New behaviour. Harness as studio_manual_entry_test.dart (one bus of 40, a
// segmented map, no controller).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_studio_feature_flag.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/screens/ai_design_studio_screen.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 11, 5);

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _FakeZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [];
}

RooflineConfiguration _segmented() => RooflineConfiguration(
      id: 'r',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      totalChannelCount: 1,
      controllerId: 'ctl-a',
      channelPixelCounts: const {0: 40},
      segments: const [
        RooflineSegment(id: 'c1', name: '', pixelCount: 4, startPixel: 0,
            type: SegmentType.corner, featureConfirmed: true, channelIndex: 0),
        RooflineSegment(id: 'r1', name: '', pixelCount: 36, startPixel: 4,
            type: SegmentType.run, featureConfirmed: true, channelIndex: 0),
      ],
    );

/// Painted red / blue on the one bus of 40; stamped for it, or not.
CustomDesign _painted(String id, String name, {DesignLayoutStamp? stamp}) =>
    CustomDesign(
      id: id,
      name: name,
      ownerId: 'u',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: stamp,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Channel 1', ledCount: 40, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 19, color: [255, 0, 0, 0]),
          LedColorGroup(startLed: 20, endLed: 39, color: [0, 0, 255, 0]),
        ]),
      ],
    );

const _stamp = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [40]);

final _designs = <CustomDesign>[
  _painted('stamped', 'Porch stripes', stamp: _stamp),
  _painted('old', 'Old paint'),
  CustomDesign(
    id: 'fx', name: 'Warm look', ownerId: 'u', createdAt: _now, updatedAt: _now,
    channels: const [
      ChannelDesign(channelId: 0, channelName: 'Channel 1', ledCount: 40, effectId: 2,
          colorGroups: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 200, 120, 0])]),
    ],
  ),
];

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: ProviderContainer(overrides: [
      designStudioRequireSegmentationProvider
          .overrideWith((ref) => Stream.value(false)),
      controllersStreamProvider.overrideWith((ref) => Stream.value(const [
            ControllerInfo(id: 'ctl-a', ip: '192.0.2.10', name: 'House'),
          ])),
      selectedControllerIdProvider.overrideWithValue('ctl-a'),
      selectedDeviceIpProvider.overrideWith((ref) => '192.0.2.10'),
      designsStreamProvider.overrideWith((ref) => Stream.value(_designs)),
      effectiveUserUidProvider.overrideWithValue('u'),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(_segmented())),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 40, gpioPin: 2),
      ]),
      participatingChannelIdsProvider.overrideWithValue(null),
      authStateProvider.overrideWith((ref) => Stream.value(null)),
      demoModeProvider.overrideWith((ref) => false),
      wledRepositoryProvider.overrideWithValue(null),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
      zoneSegmentsProvider.overrideWith(() => _FakeZoneSegments()),
    ]),
    child: MaterialApp(key: key, home: const AIDesignStudioScreen()),
  ));
  // Three frames: the studio's reset on entry, the designs stream's first
  // value, and the rebuild that value causes.
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(key.currentContext!);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a stamped design gets an entry; an unstamped painted design gets '
      'the re-save line; an effect design is not listed', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('variation-entries')), findsOneWidget);
    expect(find.byKey(const ValueKey('variation-entry-stamped')), findsOneWidget);
    expect(find.text('Variations of Porch stripes'), findsOneWidget);

    expect(find.byKey(const ValueKey('variation-entry-old')), findsNothing);
    expect(find.byKey(const ValueKey('variation-unstamped-old')), findsOneWidget);
    expect(
        find.text('Re-save "Old paint" on your roofline first to make variations of it.'),
        findsOneWidget);

    expect(find.byKey(const ValueKey('variation-entry-fx')), findsNothing);
    expect(find.byKey(const ValueKey('variation-unstamped-fx')), findsNothing);
    expect(find.textContaining('Warm look'), findsNothing);

    // Nothing is chosen yet: no strip, no variation ideas.
    expect(find.byKey(const ValueKey('variation-base')), findsNothing);
    expect(find.text('Variations to try'), findsNothing);
  });

  testWidgets('choosing an entry sets the base, shows the strip and the '
      'variation ideas, and the prompt composes in the design\'s colours',
      (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('variation-entry-stamped')));
    await tester.pump();

    final base = c.read(variationBaseProvider);
    expect(base, isNotNull);
    expect(base!.stamp, _stamp);
    expect(base.design.name, 'Porch stripes');

    expect(find.byKey(const ValueKey('variation-base')), findsOneWidget);
    expect(find.text('Variations to try'), findsOneWidget);
    expect(find.text('Quick Ideas'), findsNothing);
    expect(find.byKey(const ValueKey('variation-entries')), findsNothing);
    expect(find.text('Describe the variation...'), findsOneWidget);

    // An arrangement with no colour named composes in red / blue.
    await tester.tap(find.byKey(const ValueKey('variation-idea-every-other')));
    await _settle(tester);
    final pattern = c.read(composedPatternProvider);
    expect(pattern, isNotNull, reason: c.read(designStudioLastErrorProvider)?.errorMessage);
    expect(pattern!.channelLengths, {0: 40});
    final lit = pattern.channelGroups[0]!
        .where((g) => g.color.any((v) => v > 0))
        .map((g) => g.color)
        .toSet();
    // The every-other rule lights its accent — this two-colour design's
    // first colour stands in (no third colour), never the parser's white.
    expect(lit, {[255, 0, 0, 0]});
    expect(find.text('Apply to Lights'), findsOneWidget);

    // The in-memory apply design carries the saved design's stamp.
    expect(c.read(composedDesignForApplyProvider)!.layoutStamp, _stamp);
  });

  testWidgets('the strip\'s close clears the base and brings the entries back',
      (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('variation-entry-stamped')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('variation-base-clear')));
    await tester.pump();
    expect(c.read(variationBaseProvider), isNull);
    expect(find.byKey(const ValueKey('variation-base')), findsNothing);
    expect(find.byKey(const ValueKey('variation-entries')), findsOneWidget);
  });

  testWidgets('Start over clears the base', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('variation-entry-stamped')));
    await tester.pump();
    expect(find.byTooltip('Start over'), findsOneWidget,
        reason: 'a chosen base is work in progress');
    await tester.tap(find.byTooltip('Start over'));
    await tester.pump();
    expect(c.read(variationBaseProvider), isNull);
    expect(find.byKey(const ValueKey('variation-base')), findsNothing);
  });
}
