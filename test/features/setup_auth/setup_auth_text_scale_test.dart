// +110 package G — every screen this package owns, in each state a customer
// sees, run through the shared text-scale harness
// (test/helpers/text_scale_harness.dart) at 1.0x, 1.75x and 2.0x with Bold
// Text on. See docs/ACCESSIBILITY_TEXT_SCALE_TESTING.md.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/features/auth/forced_password_reset_screen.dart';
import 'package:nexgen_command/features/auth/forgot_password_page.dart';
import 'package:nexgen_command/features/auth/join_with_code_screen.dart';
import 'package:nexgen_command/features/auth/link_account_screen.dart';
import 'package:nexgen_command/features/auth/login_page.dart';
import 'package:nexgen_command/features/auth/staff_pin_screen.dart';
import 'package:nexgen_command/features/ble/controller_setup_wizard.dart';
import 'package:nexgen_command/features/ble/device_setup_page.dart';
import 'package:nexgen_command/features/ble/provisioning_service.dart';
import 'package:nexgen_command/features/ble/wled_manual_setup.dart';
import 'package:nexgen_command/features/dashboard/main_scaffold.dart'
    show showDemoExitSheet;
import 'package:nexgen_command/features/demo/demo_completion_screen.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/design/refine/refine_roofline_screen.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/roofline_setup_wizard.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/discovery/discovery_page.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';
import 'package:nexgen_command/features/onboarding/first_run_screen.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/roofline_editor_screen.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:nexgen_command/shared/write_result.dart';
import 'package:nexgen_command/widgets/house_photo_uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/text_scale_harness.dart';
import 'setup_auth_fixtures.dart';

const _front =
    ControllerInfo(id: 'ctrl-a', ip: '192.0.2.10', name: 'Front House');
const _back =
    ControllerInfo(id: 'ctrl-b', ip: '192.0.2.11', name: 'Back House');

class _ActiveInstaller extends InstallerModeNotifier {
  _ActiveInstaller(super.ref) {
    state = true;
  }
}

class _StillWled extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

Future<void> _screen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Duration settle = const Duration(milliseconds: 500),
  int frames = 1,
  bool pumpAndSettle = false,
}) {
  return expectNoTextScaleDefectsAcrossMatrix(
    tester,
    ProviderScope(overrides: overrides, child: screen),
    host: TextScaleHost.screen,
    settle: settle,
    frames: frames,
    pumpAndSettle: pumpAndSettle,
  );
}

/// For screens that use go_router (`context.go`, `GoRouter.of`) at build.
Future<void> _routed(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  String path = '/screen',
}) {
  final router = GoRouter(initialLocation: path, routes: [
    GoRoute(path: path, builder: (_, __) => screen),
    GoRoute(path: AppRoutes.dashboard, builder: (_, __) => const SizedBox()),
    GoRoute(path: AppRoutes.welcome, builder: (_, __) => const SizedBox()),
  ]);
  return expectNoTextScaleDefectsAcrossMatrix(
    tester,
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: nexGenPremiumDarkTheme,
        builder: TextScaleClamp.appBuilder,
        routerConfig: router,
      ),
    ),
    host: TextScaleHost.none,
  );
}

List<Override> _rooflineOverrides({
  List<ControllerInfo> controllers = const [_front],
}) {
  final fs = FakeFirebaseFirestore();
  seedPixelMap(fs, twoChannelRoofline());
  return [
    effectiveUserUidProvider.overrideWith((ref) => kTestUid),
    controllersStreamProvider.overrideWith((ref) => Stream.value(controllers)),
    rooflineConfigServiceProvider
        .overrideWithValue(RooflineConfigService(firestore: fs)),
    currentRooflineConfigProvider
        .overrideWith((ref) => Stream.value(twoChannelRoofline())),
    deviceChannelsProvider.overrideWith((ref) => const []),
    selectedDeviceIpProvider.overrideWith((ref) => null),
    controllerRepositoryProvider.overrideWith((ref, target) => null),
    houseImageUrlProvider.overrideWith((ref) => null),
    useStockImageProvider.overrideWith((ref) => true),
    rooflineMaskProvider.overrideWith((ref) => null),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
  ];
}

/// Opens the demo exit sheet as soon as it is on screen.
class _DemoExitSheetOpener extends ConsumerStatefulWidget {
  const _DemoExitSheetOpener();
  @override
  ConsumerState<_DemoExitSheetOpener> createState() => _DemoExitSheetState();
}

class _DemoExitSheetState extends ConsumerState<_DemoExitSheetOpener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showDemoExitSheet(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

UserModel _unlinkedProfile({String? dealerCode}) => UserModel(
      id: kTestUid,
      email: kTestEmail,
      displayName: 'Pat',
      ownerId: kTestUid,
      createdAt: DateTime.utc(2026, 9, 29),
      updatedAt: DateTime.utc(2026, 9, 29),
      installationRole: InstallationRole.unlinked,
      dealerCode: dealerCode,
    );

List<Override> _session([FakeAccountSession? s]) => [
      accountSessionProvider.overrideWithValue(s ?? FakeAccountSession()),
      accountFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    ];

List<Override> _deviceSetup() {
  // A system owner: the account Bluetooth setup accepts.
  final fs = FakeFirebaseFirestore();
  fs.collection('users').doc(kTestUid).set({
    'id': kTestUid,
    'owner_id': kTestUid,
    'installation_role': 'primary',
  });
  return [
    accountSessionProvider.overrideWithValue(FakeAccountSession()),
    accountFirestoreProvider.overrideWithValue(fs),
    effectiveUserUidProvider.overrideWith((ref) => kTestUid),
    wledStateProvider.overrideWith(_StillWled.new),
    provisioningServiceFactoryProvider
        .overrideWithValue((uid) => ProvisioningService(targetUserId: uid)),
  ];
}

const _outcomeNotSaved = ProvisionResult(
  ip: '192.0.2.40',
  serial: 'test-serial',
  accountSave: WriteResult.failed(WriteFailureKind.error,
      message: "The controller couldn't be added to your account "
          '(permission-denied).'),
  reachable: true,
);
const _outcomeJoining = ProvisionResult(
  ip: '192.0.2.40',
  serial: 'test-serial',
  accountSave: WriteResult.success(),
  reachable: false,
);

void main() {
  setUp(() =>
      SharedPreferences.setMockInitialValues({'welcome_completed_v1': true}));

  group('sign-in', () {
    testWidgets('login', (tester) async {
      await _screen(tester, const LoginScreen(), overrides: _session());
    });
    testWidgets('forgot password', (tester) async {
      await _screen(tester, const ForgotPasswordPage());
    });
    testWidgets('forced password reset', (tester) async {
      await _screen(tester, const ForcedPasswordResetScreen(),
          overrides: _session());
    });
    testWidgets('join with code', (tester) async {
      await _screen(tester, const JoinWithCodeScreen(), overrides: _session());
    });
    // Follow-up 3: the "Create an account" buttons came out of both.
    testWidgets('demo exit sheet', (tester) async {
      // Settles so the sheet is measured after it has slid up.
      await _screen(tester, const _DemoExitSheetOpener(),
          pumpAndSettle: true);
    });
    testWidgets('demo completion', (tester) async {
      await _screen(tester, const DemoCompletionScreen(), overrides: [
        demoExperienceActiveProvider.overrideWith((ref) => true),
        wledStateProvider.overrideWith(_StillWled.new),
      ]);
    });
    testWidgets('link account, contact is Nex-Gen LED', (tester) async {
      await _screen(tester, const LinkAccountScreen(), overrides: [
        ..._session(),
        currentUserProfileProvider
            .overrideWith((ref) => Stream.value(_unlinkedProfile())),
      ]);
    });
    testWidgets('link account, contact is the dealer', (tester) async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('dealers').doc('DLR-1').set({
        'companyName': 'Bright Homes LED of the Greater Metropolitan Area',
        'phone': '(555) 010-0100',
        'email': 'hello@example.com',
      });
      await _screen(tester, const LinkAccountScreen(), overrides: [
        accountSessionProvider.overrideWithValue(FakeAccountSession()),
        accountFirestoreProvider.overrideWithValue(fs),
        currentUserProfileProvider.overrideWith(
            (ref) => Stream.value(_unlinkedProfile(dealerCode: 'DLR-1'))),
      ]);
    });
    testWidgets('staff PIN', (tester) async {
      await _screen(tester, const StaffPinScreen(), overrides: _session());
    });
  });

  group('onboarding', () {
    for (final page in [0, 1, 2]) {
      testWidgets('first run, page ${page + 1}', (tester) async {
        await _screen(tester, FirstRunScreen(initialPage: page),
            overrides: _session());
      });
    }
    for (var i = 0; i < getDefaultTourSteps().length; i++) {
      final step = getDefaultTourSteps()[i];
      testWidgets('feature tour step ${i + 1} (${step.id})', (tester) async {
        await _screen(
          tester,
          const FeatureTourOverlay(child: SizedBox.expand()),
          overrides: [
            featureTourProvider.overrideWith((ref) => FeatureTourNotifier()
              ..startTour(getDefaultTourSteps())
              ..goToStep(i)),
          ],
        );
      });
    }
  });

  group('device setup', () {
    testWidgets('Bluetooth setup, nothing found', (tester) async {
      await _screen(tester, const DeviceSetupPage(testSkipScan: true),
          overrides: _deviceSetup());
    });
    testWidgets('Bluetooth setup, use current Wi-Fi?', (tester) async {
      await _screen(
        tester,
        DeviceSetupPage(
            testConnectedDevice: BluetoothDevice.fromId('test-device'),
            testShowWifiPrompt: true),
        overrides: _deviceSetup(),
      );
    });
    testWidgets('Bluetooth setup, Wi-Fi form', (tester) async {
      await _screen(
        tester,
        DeviceSetupPage(
            testConnectedDevice: BluetoothDevice.fromId('test-device')),
        overrides: _deviceSetup(),
      );
    });
    testWidgets('Bluetooth setup, not added to account', (tester) async {
      await _screen(
        tester,
        DeviceSetupPage(
            testConnectedDevice: BluetoothDevice.fromId('test-device'),
            testOutcome: _outcomeNotSaved),
        overrides: _deviceSetup(),
      );
    });
    testWidgets('Bluetooth setup, still joining the network', (tester) async {
      await _screen(
        tester,
        DeviceSetupPage(
            testConnectedDevice: BluetoothDevice.fromId('test-device'),
            testOutcome: _outcomeJoining),
        overrides: _deviceSetup(),
      );
    });
    for (final step in [0, 1, 2, 3, 4]) {
      testWidgets('manual controller setup, step $step', (tester) async {
        await _screen(
          tester,
          WledManualSetup(
            testInitialStep: step,
            testFound: [
              DeviceEndpoint(
                  name: 'WLED Front Roofline Controller',
                  address: InternetAddress('192.0.2.31')),
              DeviceEndpoint(
                  name: 'WLED @ 192.0.2.32',
                  address: InternetAddress('192.0.2.32')),
            ],
          ),
          overrides: [effectiveUserUidProvider.overrideWith((ref) => kTestUid)],
        );
      });
    }
    testWidgets('controller setup wizard', (tester) async {
      await _screen(tester, const ControllerSetupWizard());
    });
    testWidgets('discovery, nothing found', (tester) async {
      await _routed(
        tester,
        const DiscoveryPage(),
        path: AppRoutes.discovery,
        overrides: [
          deviceDiscoveryServiceProvider
              .overrideWithValue(FakeDiscoveryService(const [])),
          wledStateProvider.overrideWith(_StillWled.new),
          // A system owner, so the Bluetooth offer is on screen.
          currentUserProfileProvider.overrideWith((ref) => Stream.value(
                UserModel(
                  id: kTestUid,
                  email: kTestEmail,
                  displayName: 'Pat',
                  ownerId: kTestUid,
                  createdAt: DateTime.utc(2026, 9, 29),
                  updatedAt: DateTime.utc(2026, 9, 29),
                  installationRole: InstallationRole.primary,
                ),
              )),
        ],
      );
    });
    testWidgets('discovery, two controllers found', (tester) async {
      await _routed(
        tester,
        const DiscoveryPage(),
        path: AppRoutes.discovery,
        overrides: [
          deviceDiscoveryServiceProvider
              .overrideWithValue(FakeDiscoveryService([
            DeviceEndpoint(
                name: 'wled-front-roofline._wled._tcp.local',
                address: InternetAddress('192.0.2.21')),
            DeviceEndpoint(
                name: 'wled-back', address: InternetAddress('192.0.2.22')),
          ])),
          wledStateProvider.overrideWith(_StillWled.new),
        ],
      );
    });
  });

  group('roofline', () {
    testWidgets('roofline wizard, installer-only notice', (tester) async {
      await _screen(tester, const RooflineSetupWizard());
    });
    for (final step in [0, 1, 2, 3, 4]) {
      testWidgets('roofline wizard, step ${step + 1}', (tester) async {
        await _screen(tester, RooflineSetupWizard(initialStep: step),
            overrides: [
              ..._rooflineOverrides(),
              installerModeActiveProvider.overrideWith(_ActiveInstaller.new),
            ]);
      });
    }
    testWidgets('segment setup', (tester) async {
      await _screen(tester, const SegmentSetupScreen(),
          overrides: _rooflineOverrides());
    });
    testWidgets('segment setup, no controller chosen', (tester) async {
      await _screen(tester, const SegmentSetupScreen(),
          overrides: _rooflineOverrides(controllers: [_front, _back]));
    });
    testWidgets('refine roofline', (tester) async {
      await _screen(tester, const RefineRooflineScreen(),
          overrides: _rooflineOverrides());
    });
    testWidgets('trace roofline editor', (tester) async {
      await _screen(tester, const RooflineEditorScreen(),
          overrides: _rooflineOverrides());
    });
    testWidgets('feature walkthrough', (tester) async {
      await _screen(tester, const RooflineFeatureWalkthroughScreen(),
          overrides: _rooflineOverrides());
    });
    testWidgets('house photo card', (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        ProviderScope(
          overrides: _rooflineOverrides(),
          child: const SingleChildScrollView(child: HousePhotoUploader()),
        ),
      );
    });
  });
}
