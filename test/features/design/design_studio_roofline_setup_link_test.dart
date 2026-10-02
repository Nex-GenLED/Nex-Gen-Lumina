// +113 (owner decision 2026-10-01) — Design Studio's "Roofline setup" opens
// the customer walkthrough (Mark Your Roofline), not the installer-only
// Segment Setup editor.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_studio_feature_flag.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/screens/ai_design_studio_screen.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
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
      designStudioRequireSegmentationProvider
          .overrideWith((ref) => Stream.value(false)),
      controllersStreamProvider.overrideWith((ref) => Stream.value(const [
            ControllerInfo(id: 'ctl-a', ip: '192.0.2.10', name: 'House'),
          ])),
      selectedControllerIdProvider.overrideWithValue('ctl-a'),
      selectedDeviceIpProvider.overrideWith((ref) => '192.0.2.10'),
      designsStreamProvider
          .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('u'),
      currentRooflineConfigProvider
          .overrideWith((ref) => Stream.value(_segmented())),
      // The walkthrough loads through the service; keep it off real Firestore.
      rooflineConfigServiceProvider.overrideWithValue(
          RooflineConfigService(firestore: FakeFirebaseFirestore())),
      controllerRepositoryProvider.overrideWith((ref, target) => null),
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
  testWidgets('"Roofline setup" opens Mark Your Roofline, not Segment Setup',
      (tester) async {
    await _pump(tester);
    expect(find.text('Roofline setup'), findsOneWidget);

    await tester.tap(find.text('Roofline setup'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RooflineFeatureWalkthroughScreen), findsOneWidget);
    expect(find.text('Mark Your Roofline'), findsOneWidget);
    expect(find.byType(SegmentSetupScreen), findsNothing);
  });
}
