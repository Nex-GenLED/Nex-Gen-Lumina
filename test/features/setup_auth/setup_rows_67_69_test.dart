// +110 package G — rows 67, 68 and 69 of the 2026-09-25 UX defect audit,
// each driven from the real control.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/ble/device_setup_page.dart';
import 'package:nexgen_command/features/ble/provisioning_service.dart';
import 'package:nexgen_command/features/ble/wled_manual_setup.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/discovery/discovery_page.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/shared/write_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'setup_auth_fixtures.dart';

DeviceEndpoint _endpoint(String name, String ip) =>
    DeviceEndpoint(name: name, address: InternetAddress(ip));

class _StillWled extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

/// Provisioning that answers from the test, recording each call.
class _FakeProvisioning extends ProvisioningService {
  _FakeProvisioning({
    required this.firstSave,
    required this.reachableAfterSend,
    this.reachableOnRecheck = true,
  }) : super(targetUserId: kTestUid);

  final WriteResult firstSave;
  final bool reachableAfterSend;
  final bool reachableOnRecheck;
  final List<String> calls = [];

  @override
  Future<ProvisionResult> provisionDevice({
    required BluetoothDevice device,
    required String ssid,
    required String password,
  }) async {
    calls.add('provision:$ssid');
    return ProvisionResult(
      ip: '192.0.2.40',
      serial: 'test-serial',
      accountSave: firstSave,
      reachable: reachableAfterSend,
    );
  }

  @override
  Future<WriteResult> saveController({
    required String ip,
    required String serial,
    String? ssid,
  }) async {
    calls.add('save:$ip');
    return const WriteResult.success();
  }

  @override
  Future<bool> verifyReachable(String ip) async {
    calls.add('verify:$ip');
    return reachableOnRecheck;
  }
}

Widget _routerApp(Widget screen, List<Override> overrides,
    {String path = '/screen'}) {
  Widget stub(String name) => Scaffold(body: Center(child: Text('PAGE:$name')));
  final router = GoRouter(initialLocation: path, routes: [
    GoRoute(path: path, builder: (_, __) => screen),
    GoRoute(path: AppRoutes.dashboard, builder: (_, __) => stub('dashboard')),
    GoRoute(
        path: AppRoutes.controllersSettings,
        builder: (_, __) => stub('controllers')),
    GoRoute(path: AppRoutes.welcome, builder: (_, __) => stub('welcome')),
  ]);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  // ── Row 67 ───────────────────────────────────────────────────────────────
  group('row 67 — Bluetooth device setup reports what happened', () {
    Future<void> connectAndFinish(
        WidgetTester tester, _FakeProvisioning fake) async {
      await tester.pumpWidget(_routerApp(
        DeviceSetupPage(
            testConnectedDevice: BluetoothDevice.fromId('test-device')),
        [
          provisioningServiceFactoryProvider.overrideWithValue((_) => fake),
          effectiveUserUidProvider.overrideWith((ref) => kTestUid),
          wledStateProvider.overrideWith(() => _StillWled()),
        ],
      ));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('wifi-ssid')), 'HomeNet');
      await tester.enterText(find.byKey(const ValueKey('wifi-password')), 'pw');
      await tester.tap(find.text('Connect & Finish Setup'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a failed account save is reported; "Try again" saves only',
        (tester) async {
      final fake = _FakeProvisioning(
        firstSave: const WriteResult.failed(WriteFailureKind.error,
            message: "The controller couldn't be added to your account "
                '(permission-denied).'),
        reachableAfterSend: true,
      );
      await connectAndFinish(tester, fake);

      expect(find.text('Not added to your account'), findsOneWidget);
      expect(find.textContaining('permission-denied'), findsOneWidget);
      // The success overlay is present in the tree but must not be shown.
      final overlay = tester.widget<AnimatedOpacity>(find
          .ancestor(
              of: find.text('Device Connected!'),
              matching: find.byType(AnimatedOpacity))
          .first);
      expect(overlay.opacity, 0);

      await tester.ensureVisible(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(fake.calls, ['provision:HomeNet', 'save:192.0.2.40']);
      final shown = tester.widget<AnimatedOpacity>(find
          .ancestor(
              of: find.text('Device Connected!'),
              matching: find.byType(AnimatedOpacity))
          .first);
      expect(shown.opacity, 1);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('PAGE:dashboard'), findsOneWidget);
    });

    testWidgets(
        'saved but not on the network yet says "credentials sent, not yet '
        'found", not "Connected"', (tester) async {
      final fake = _FakeProvisioning(
        firstSave: const WriteResult.success(),
        reachableAfterSend: false,
        reachableOnRecheck: false,
      );
      await connectAndFinish(tester, fake);

      expect(find.text('Wi‑Fi details sent'), findsOneWidget);
      expect(find.textContaining("hasn't appeared on your network yet"),
          findsOneWidget);
      await tester.ensureVisible(find.text('Check again'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Check again'));
      await tester.pump();
      await tester.pump();
      expect(fake.calls.last, 'verify:192.0.2.40');
      expect(find.text('Wi‑Fi details sent'), findsOneWidget,
          reason: 'still not reachable — still honest');

      await tester.ensureVisible(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE:dashboard'), findsOneWidget);
    });

    test('saveController: no account id is blocked, a refusal is reported',
        () async {
      final blocked = await ProvisioningService(targetUserId: '')
          .saveController(ip: '192.0.2.41', serial: 's');
      expect(blocked.wasBlocked, isTrue);
      expect(blocked.message, contains("couldn't be added"));

      final fs = FakeFirebaseFirestore();
      final ok = await ProvisioningService(
        targetUserId: kTestUid,
        repository: DeviceRepository(firestore: fs),
      ).saveController(ip: '192.0.2.41', serial: 'aa:bb');
      expect(ok.ok, isTrue);
      final saved = await fs
          .collection('users')
          .doc(kTestUid)
          .collection('controllers')
          .get();
      expect(saved.docs.single.data()['ip'], '192.0.2.41');
    });
  });

  // ── Row 68 ───────────────────────────────────────────────────────────────
  group('row 68 — discovery never picks for the customer', () {
    test('two controllers found → nothing selected', () async {
      final container = ProviderContainer(overrides: [
        deviceDiscoveryServiceProvider.overrideWithValue(FakeDiscoveryService([
          _endpoint('wled-front', '192.0.2.21'),
          _endpoint('wled-back', '192.0.2.22'),
        ])),
      ]);
      addTearDown(container.dispose);
      await container.read(discoveredDevicesProvider.future);
      expect(container.read(selectedDeviceIpProvider), isNull);
    });

    test('exactly one found → selected; an existing selection is kept',
        () async {
      final container = ProviderContainer(overrides: [
        deviceDiscoveryServiceProvider.overrideWithValue(
            FakeDiscoveryService([_endpoint('wled-front', '192.0.2.21')])),
      ]);
      addTearDown(container.dispose);
      await container.read(discoveredDevicesProvider.future);
      expect(container.read(selectedDeviceIpProvider), '192.0.2.21');

      final kept = ProviderContainer(overrides: [
        deviceDiscoveryServiceProvider.overrideWithValue(
            FakeDiscoveryService([_endpoint('wled-front', '192.0.2.21')])),
      ]);
      addTearDown(kept.dispose);
      kept.read(selectedDeviceIpProvider.notifier).state = '192.0.2.99';
      await kept.read(discoveredDevicesProvider.future);
      expect(kept.read(selectedDeviceIpProvider), '192.0.2.99');
    });

    testWidgets(
        'with two controllers the page waits for a tap and the header says '
        'so; a tap chooses', (tester) async {
      SharedPreferences.setMockInitialValues({'welcome_completed_v1': true});
      await tester.pumpWidget(_routerApp(
        const DiscoveryPage(),
        [
          deviceDiscoveryServiceProvider
              .overrideWithValue(FakeDiscoveryService([
            _endpoint('wled-front', '192.0.2.21'),
            _endpoint('wled-back', '192.0.2.22'),
          ])),
          wledStateProvider.overrideWith(() => _StillWled()),
        ],
        path: AppRoutes.discovery,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Found 2 controllers — tap yours to continue'),
          findsOneWidget);
      expect(find.text('PAGE:dashboard'), findsNothing,
          reason: 'must not jump to the dashboard before a tap');

      await tester.tap(find.text('wled-back'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE:dashboard'), findsOneWidget);
    });

    test('the header reports the connection, not the selection', () {
      expect(
        discoveryHeader(
            scanning: false,
            found: 2,
            selectedIp: '192.0.2.21',
            connected: false),
        'Connecting to 192.0.2.21…',
      );
      expect(
        discoveryHeader(
            scanning: false,
            found: 2,
            selectedIp: '192.0.2.21',
            connected: true),
        'Connected to 192.0.2.21',
      );
      expect(
        discoveryHeader(
            scanning: false, found: 0, selectedIp: null, connected: false),
        'No controllers found yet',
      );
    });
  });

  // ── Row 69 ───────────────────────────────────────────────────────────────
  group('row 69 — manual setup saves the controller the customer taps', () {
    testWidgets('lists every controller found and saves only the tapped one',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      final probed = <String>[];
      await tester.pumpWidget(_routerApp(
        const WledManualSetup(),
        [
          deviceDiscoveryServiceProvider
              .overrideWithValue(FakeDiscoveryService([
            _endpoint('WLED @ 192.0.2.31', '192.0.2.31'),
            _endpoint('WLED @ 192.0.2.32', '192.0.2.32'),
          ])),
          controllerInfoProbeProvider.overrideWithValue((ip) async {
            probed.add(ip);
            return {
              'wifi': {'rssi': -50}
            };
          }),
          deviceRepositoryProvider
              .overrideWithValue(DeviceRepository(firestore: fs)),
          effectiveUserUidProvider.overrideWith((ref) => kTestUid),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Find My Controller'));
      await tester.tap(find.text('Find My Controller'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Choose your controller'), findsOneWidget);
      expect(find.text('192.0.2.31'), findsOneWidget);
      expect(find.text('192.0.2.32'), findsOneWidget);
      var saved = await fs
          .collection('users')
          .doc(kTestUid)
          .collection('controllers')
          .get();
      expect(saved.docs, isEmpty, reason: 'nothing is saved before a tap');

      await tester.tap(find.text('192.0.2.32'));
      await tester.pump();
      await tester.pump();

      expect(probed, ['192.0.2.32']);
      saved = await fs
          .collection('users')
          .doc(kTestUid)
          .collection('controllers')
          .get();
      expect(saved.docs.single.data()['ip'], '192.0.2.32');
      expect(find.text('Controller Added!'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });
}
