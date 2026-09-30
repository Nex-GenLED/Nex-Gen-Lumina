// M3 (audit F1) — the control that SAYS "Manual controls" opens the manual
// editor. `_showManualControls` was written in four places and read in none.
//
// +110 E2: the studio is gated on a segmented roofline, so these tests now
// run on one (the gate itself is covered in design_studio_e2_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
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

final _now = DateTime(2026, 9, 29);

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

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      controllersStreamProvider.overrideWith((ref) => Stream.value(const [
            ControllerInfo(id: 'ctl-a', ip: '192.0.2.10', name: 'House'),
          ])),
      selectedControllerIdProvider.overrideWithValue('ctl-a'),
      selectedDeviceIpProvider.overrideWith((ref) => '192.0.2.10'),
      designsStreamProvider.overrideWith((ref) => Stream.value(const <CustomDesign>[])),
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
    ],
    child: const MaterialApp(home: AIDesignStudioScreen()),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the studio opens in AI mode — no paint editor yet', (tester) async {
    await _pump(tester);
    expect(find.byType(ManualDesignEditor), findsNothing);
    expect(find.byTooltip('Manual controls'), findsOneWidget);
  });

  testWidgets('"Manual controls" opens the paint editor', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Manual controls'));
    await tester.pump();
    expect(find.byType(ManualDesignEditor), findsOneWidget,
        reason: 'used to set a flag nothing reads');
    // Once there, the redundant door is gone; the title toggle shows the mode.
    expect(find.byTooltip('Manual controls'), findsNothing);
  });

  testWidgets('the AI | Manual title toggle is still the working entry point',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Manual'));
    await tester.pump();
    expect(find.byType(ManualDesignEditor), findsOneWidget);
    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(find.byType(ManualDesignEditor), findsNothing);
    expect(find.byTooltip('Manual controls'), findsOneWidget);
  });
}
