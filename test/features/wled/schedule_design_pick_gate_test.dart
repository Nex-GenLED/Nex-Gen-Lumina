// Roofline slice 2, A2 — the REAL picker (LibraryBrowserScreen) in the
// schedule's selection mode, pumped with a painted design in My Designs.
//
// FAIL-BEFORE on b4b09f2: the card builder returned row 92's "can't be chosen
// here" card for EVERY positional design before the hand-off ran, so no
// design-kind schedule could ever be created. Now a stamped, fitting design
// is handed to the handler once with the API body; an unstamped or
// non-fitting design shows the fit gate's own sentence in place and never
// calls the handler; every other destination keeps row 92's card exactly.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';

/// A direct-LAN service that answers the one device read the pick makes.
class _LanService extends WledService {
  _LanService() : super('http://mock');
  int infoReads = 0;

  @override
  Future<WledInfoResponse?> getInfo() async {
    infoReads++;
    return const WledInfoResponse(maxseg: 10, arch: 'esp32', ver: '0.15.4');
  }
}

const kThreeLive = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 16),
];

CustomDesign painted({DesignLayoutStamp? stamp, int buses = 3}) => CustomDesign(
      id: 'p1',
      name: 'Painted',
      createdAt: DateTime(2026, 11, 6),
      updatedAt: DateTime(2026, 11, 6),
      ownerId: 'customer-test',
      perPixel: true,
      brightness: 180,
      brightnessStated: true,
      layoutStamp: stamp,
      channels: [
        for (var id = 0; id < buses; id++)
          ChannelDesign(
            channelId: id,
            channelName: 'Channel ${id + 1}',
            ledCount: 100,
            colorGroups: const [
              LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
              LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
            ],
          ),
      ],
    );

const kFitting =
    DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);

List<Override> overrides({
  required List<CustomDesign> designs,
  required _LanService service,
}) =>
    [
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
      patternCategoriesProvider.overrideWith((_) async => const [
            PatternCategory(id: 'cat_holiday', name: 'Holidays', imageUrl: ''),
          ]),
      designsStreamProvider.overrideWith((ref) => Stream.value(designs)),
      wledRepositoryProvider.overrideWith((ref) => service),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      isRemoteModeProvider.overrideWithValue(false),
      deviceChannelsProvider.overrideWithValue(kThreeLive),
      selectedControllerIdProvider.overrideWithValue('ctl-a'),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
      userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    ];

Future<void> pumpPicker(
  WidgetTester tester, {
  required List<CustomDesign> designs,
  required _LanService service,
  required String? destination,
  required void Function(LibraryDesignSelection) onSelected,
}) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides(designs: designs, service: service),
    child: MaterialApp(
      home: LibraryBrowserScreen(
        nodeId: 'design_p1',
        saveDestinationLabel: destination,
        onDesignSelected: onSelected,
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a stamped, fitting painted design is handed to the handler '
      'ONCE with the API body (fail-before: never called on b4b09f2)',
      (tester) async {
    final received = <LibraryDesignSelection>[];
    final service = _LanService();
    await pumpPicker(tester,
        designs: [painted(stamp: kFitting)],
        service: service,
        destination: 'schedule',
        onSelected: received.add);

    expect(received, hasLength(1));
    final sel = received.single;
    expect(sel.designId, 'p1');
    expect(sel.name, 'Painted');
    expect(sel.presetKind, kSchedulePresetKindApi);
    expect(sel.wledPayload['o'], isTrue);
    expect(designApiPresetBodyProblem(sel.wledPayload), isNull,
        reason: 'the bounds-first body the sync will write');
    expect((sel.wledPayload['seg'] as List).take(3).map((s) => s['stop']),
        [100, 200, 300]);
    expect(service.infoReads, 1, reason: 'one firmware read, on the LAN');
    expect(find.byKey(const ValueKey('per-pixel-choose-another')),
        findsNothing);
  });

  testWidgets('an unstamped painted design: the gate\'s own sentence in '
      'place, the handler never called', (tester) async {
    var handedBack = 0;
    await pumpPicker(tester,
        designs: [painted(stamp: null)],
        service: _LanService(),
        destination: 'schedule',
        onSelected: (_) => handedBack++);

    expect(handedBack, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('"Painted" is a per-pixel design'), findsOneWidget);
    expect(find.textContaining('saved before Lumina recorded your roofline '
        'layout'), findsOneWidget);
    expect(find.byKey(const ValueKey('per-pixel-choose-another')),
        findsOneWidget);
  });

  testWidgets('a non-fitting design (stamped for two buses, three live): '
      'the fit gate\'s sentence, the handler never called', (tester) async {
    var handedBack = 0;
    await pumpPicker(tester,
        designs: [
          painted(
              stamp: const DesignLayoutStamp(
                  controllerId: 'ctl-a', busLengths: [100, 100]),
              buses: 2)
        ],
        service: _LanService(),
        destination: 'schedule',
        onSelected: (_) => handedBack++);

    expect(handedBack, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('was saved for 2 channels, but your '
        'controller has 3 now'), findsOneWidget);
    expect(find.byKey(const ValueKey('per-pixel-choose-another')),
        findsOneWidget);
  });

  testWidgets('every other destination keeps row 92\'s card exactly',
      (tester) async {
    var handedBack = 0;
    final service = _LanService();
    await pumpPicker(tester,
        designs: [painted(stamp: kFitting)],
        service: service,
        destination: 'Game Day',
        onSelected: (_) => handedBack++);

    expect(handedBack, 0);
    expect(find.text('"Painted" is a per-pixel design'), findsOneWidget);
    expect(find.textContaining("so this one can't be chosen here"),
        findsOneWidget);
    expect(find.byKey(const ValueKey('per-pixel-choose-another')),
        findsOneWidget);
    expect(service.infoReads, 0, reason: 'no gate, no device read');
  });
}
