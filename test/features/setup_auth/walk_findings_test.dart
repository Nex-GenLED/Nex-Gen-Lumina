// +110 package G — the three findings from the first-time-customer walk:
//   1. Bluetooth setup's refusal. Lumina is professionally installed, so a
//      self-signup account adding its own controller stays refused; only
//      the family-member message was made clearer;
//   2. choosing a controller on discovery did not save it;
//   3. first run pointed at an "Auto-Pilot tab" that does not exist.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/features/auth/link_account_screen.dart';
import 'package:nexgen_command/features/ble/device_setup_page.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/discovery/discovery_page.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/onboarding/first_run_screen.dart';
import 'package:nexgen_command/features/site/connection_method.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'setup_auth_fixtures.dart';

class _StillWled extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _RefusingRepository extends DeviceRepository {
  _RefusingRepository() : super(firestore: FakeFirebaseFirestore());
  @override
  Future<void> saveDevice({
    required String userId,
    required String serial,
    required String ip,
    String? name,
    String? ssid,
    bool? wifiConfigured,
    ConnectionMethod connectionMethod = ConnectionMethod.unknown,
  }) async {
    throw StateError('permission-denied');
  }
}

DeviceEndpoint _endpoint(String name, String ip) =>
    DeviceEndpoint(name: name, address: InternetAddress(ip));

UserModel _profile(InstallationRole role) => UserModel(
      id: kTestUid,
      email: kTestEmail,
      displayName: 'Pat',
      ownerId: kTestUid,
      createdAt: DateTime.utc(2026, 9, 29),
      updatedAt: DateTime.utc(2026, 9, 29),
      installationRole: role,
    );

/// [screen] at `/screen`, pushed from a stub home so `pop` has somewhere to
/// go, with stub pages for every place the screens send the customer.
Widget _app(Widget screen, List<Override> overrides, {bool pushed = true}) {
  Widget stub(String name) => Scaffold(body: Center(child: Text('PAGE:$name')));
  final router = GoRouter(
    initialLocation: pushed ? '/' : '/screen',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/screen'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/screen', builder: (_, __) => screen),
      GoRoute(path: AppRoutes.dashboard, builder: (_, __) => stub('dashboard')),
      GoRoute(path: AppRoutes.discovery, builder: (_, __) => stub('discovery')),
      GoRoute(
          path: AppRoutes.deviceSetup,
          builder: (_, __) => stub('device-setup')),
      GoRoute(path: AppRoutes.welcome, builder: (_, __) => stub('welcome')),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() =>
      SharedPreferences.setMockInitialValues({'welcome_completed_v1': true}));

  // ── 1. Bluetooth setup: owners and installers only ──────────────────────
  group('1 — Bluetooth setup admits only installers and system owners', () {
    test(
        'who may pair: an installer session, a primary or an installer '
        'account; nobody else', () {
      PairingDecision decide(String? role) => controllerPairingDecision(
            signedIn: true,
            installerSession: false,
            profileExists: true,
            role: role,
          );
      expect(decide('primary'), PairingDecision.allowed);
      expect(decide('installer'), PairingDecision.allowed);
      expect(decide('unlinked'), PairingDecision.notOwner,
          reason: 'a self-signup account never pairs its own controller');
      expect(decide(null), PairingDecision.notOwner);
      expect(decide('admin'), PairingDecision.notOwner,
          reason: 'the pre-+110 rule: primary or installer only');
      expect(decide('subUser'), PairingDecision.familyMember);
      expect(
          controllerPairingDecision(
              signedIn: false,
              installerSession: false,
              profileExists: false,
              role: null),
          PairingDecision.notSignedIn);
      expect(
          controllerPairingDecision(
              signedIn: true,
              installerSession: true,
              profileExists: false,
              role: 'unlinked'),
          PairingDecision.allowed);
      expect(pairingRefusalMessage(PairingDecision.notOwner),
          'Only system owners can add new controllers.');
    });

    Future<void> openSetup(WidgetTester tester, String role) async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('users').doc(kTestUid).set({
        'id': kTestUid,
        'owner_id': kTestUid,
        'installation_role': role,
      });
      await tester.pumpWidget(_app(
        const DeviceSetupPage(testSkipScan: true),
        [
          accountSessionProvider.overrideWithValue(FakeAccountSession()),
          accountFirestoreProvider.overrideWithValue(fs),
          effectiveUserUidProvider.overrideWith((ref) => kTestUid),
          wledStateProvider.overrideWith(_StillWled.new),
        ],
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }

    testWidgets(
        'a self-signup (unlinked) account is turned away: "Only system '
        'owners can add new controllers."', (tester) async {
      await openSetup(tester, 'unlinked');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Only system owners can add new controllers.'),
          findsOneWidget);
      expect(find.text('open'), findsOneWidget, reason: 'popped back');
    });

    testWidgets('a system owner stays in Bluetooth setup', (tester) async {
      await openSetup(tester, 'primary');
      expect(find.text('Device Setup'), findsOneWidget);
      expect(find.textContaining('Only system owners'), findsNothing);
      await tester.pump(const Duration(seconds: 10)); // radar settle timer
    });

    testWidgets("a family member is turned away, and told why", (tester) async {
      await openSetup(tester, 'subUser');
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining("someone else's lighting system"),
          findsOneWidget);
      expect(find.text('open'), findsOneWidget, reason: 'popped back');
    });

    testWidgets('link account offers no way to set up a controller yourself',
        (tester) async {
      await tester.pumpWidget(_app(
        const LinkAccountScreen(),
        [accountSessionProvider.overrideWithValue(FakeAccountSession())],
        pushed: false,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-setup-own-controller')),
          findsNothing);
      expect(find.textContaining('Set up my own controller'), findsNothing);
      expect(find.text('I have an invitation code'), findsOneWidget);
    });

    Future<void> openEmptyDiscovery(
        WidgetTester tester, UserModel? profile) async {
      await tester.pumpWidget(_app(
        const DiscoveryPage(),
        [
          deviceDiscoveryServiceProvider
              .overrideWithValue(FakeDiscoveryService(const [])),
          wledStateProvider.overrideWith(_StillWled.new),
          currentUserProfileProvider
              .overrideWith((ref) => Stream.value(profile)),
        ],
        pushed: false,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'discovery with nothing found offers Bluetooth setup to a system '
        'owner', (tester) async {
      await openEmptyDiscovery(tester, _profile(InstallationRole.primary));
      await tester.tap(find.byKey(const ValueKey('discovery-bluetooth-setup')));
      await tester.pumpAndSettle();
      expect(find.text('PAGE:device-setup'), findsOneWidget);
    });

    for (final role in [InstallationRole.subUser, InstallationRole.unlinked]) {
      testWidgets(
          'discovery with nothing found makes no Bluetooth offer to '
          '${role.name}', (tester) async {
        await openEmptyDiscovery(tester, _profile(role));
        expect(find.byKey(const ValueKey('discovery-bluetooth-setup')),
            findsNothing);
        expect(find.text('No controllers found'), findsOneWidget);
      });
    }
  });

  // ── 2. Choosing on discovery saves the controller ───────────────────────
  group('2 — discovery saves the chosen controller to the account', () {
    List<Override> discovery(
      FakeFirebaseFirestore fs,
      List<DeviceEndpoint> found, {
      DeviceRepository? repository,
    }) =>
        [
          deviceDiscoveryServiceProvider
              .overrideWithValue(FakeDiscoveryService(found)),
          wledStateProvider.overrideWith(_StillWled.new),
          effectiveUserUidProvider.overrideWith((ref) => kTestUid),
          controllersFirestoreProvider.overrideWithValue(fs),
          deviceRepositoryProvider
              .overrideWithValue(repository ?? DeviceRepository(firestore: fs)),
        ];

    Future<List<Map<String, dynamic>>> saved(FakeFirebaseFirestore fs) async =>
        (await fs
                .collection('users')
                .doc(kTestUid)
                .collection('controllers')
                .get())
            .docs
            .map((d) => d.data())
            .toList();

    testWidgets(
        'a tap saves the controller; on the next launch the app selects that '
        'saved record', (tester) async {
      final fs = FakeFirebaseFirestore();
      await tester.pumpWidget(_app(
        const DiscoveryPage(),
        discovery(fs, [
          _endpoint('wled-front._wled._tcp.local', '192.0.2.21'),
          _endpoint('wled-back._wled._tcp.local', '192.0.2.22'),
        ]),
        pushed: false,
      ));
      await tester.pumpAndSettle();
      expect(await saved(fs), isEmpty, reason: 'nothing saved before a tap');

      await tester.tap(find.text('wled-back._wled._tcp.local'));
      await tester.pumpAndSettle();

      expect(find.text('PAGE:dashboard'), findsOneWidget);
      final records = await saved(fs);
      expect(records.single['ip'], '192.0.2.22');
      expect(records.single['name'], 'wled-back');

      // Next launch: a fresh app with nothing in memory, reading the account
      // through the app's own controller stream and auto-connect. (Real
      // async: the store's snapshot stream does not run in fake time.)
      await tester.runAsync(() async {
        final nextLaunch = ProviderContainer(overrides: [
          effectiveUserUidProvider.overrideWith((ref) => kTestUid),
          controllersFirestoreProvider.overrideWithValue(fs),
        ]);
        expect(nextLaunch.read(selectedDeviceIpProvider), isNull);
        final sub =
            nextLaunch.listen(autoConnectControllerProvider, (_, __) {});
        final list = await nextLaunch
            .read(controllersStreamProvider.future)
            .timeout(const Duration(seconds: 5));
        expect(list.single.ip, '192.0.2.22');
        nextLaunch.read(autoConnectControllerProvider);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(nextLaunch.read(selectedDeviceIpProvider), '192.0.2.22');
        sub.close();
        nextLaunch.dispose();
      });
    });

    testWidgets('the one-controller auto-select is saved too', (tester) async {
      final fs = FakeFirebaseFirestore();
      await tester.pumpWidget(_app(
        const DiscoveryPage(),
        discovery(fs, [_endpoint('WLED @ 192.0.2.23', '192.0.2.23')]),
        pushed: false,
      ));
      await tester.pumpAndSettle();
      expect(find.text('PAGE:dashboard'), findsOneWidget);
      final records = await saved(fs);
      expect(records.single['ip'], '192.0.2.23');
      expect(records.single['name'], 'Controller 192.0.2.23');
    });

    testWidgets('a controller already on the account is not added twice',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('users')
          .doc(kTestUid)
          .collection('controllers')
          .doc('existing-record')
          .set({'ip': '192.0.2.24', 'name': 'Front House'});
      await tester.pumpWidget(_app(
        const DiscoveryPage(),
        discovery(fs, [
          _endpoint('wled-a', '192.0.2.24'),
          _endpoint('wled-b', '192.0.2.25'),
        ]),
        pushed: false,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('wled-a'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE:dashboard'), findsOneWidget);
      expect((await saved(fs)).length, 1);
    });

    testWidgets('a refused save is shown; the app does not move on',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await tester.pumpWidget(_app(
        const DiscoveryPage(),
        discovery(
          fs,
          [
            _endpoint('wled-a', '192.0.2.26'),
            _endpoint('wled-b', '192.0.2.27')
          ],
          repository: _RefusingRepository(),
        ),
        pushed: false,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('wled-a'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE:dashboard'), findsNothing);
      expect(
          find.textContaining("Couldn't save this controller"), findsOneWidget);
    });
  });

  // ── 3. First run names controls that exist ─────────────────────────────
  group('3 — first run copy', () {
    for (final page in [0, 2]) {
      testWidgets(
          'page ${page + 1} points at the Lumina AI card on the '
          'Schedule tab, not an "Auto-Pilot tab"', (tester) async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            accountSessionProvider.overrideWithValue(FakeAccountSession()),
            currentUserProfileProvider
                .overrideWith((ref) => Stream.value(null)),
          ],
          child: MaterialApp(home: FirstRunScreen(initialPage: page)),
        ));
        await tester.pumpAndSettle();
        final copy = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ');
        expect(copy, isNot(contains('Auto-Pilot tab')));
        expect(copy, contains('Lumina AI card in the Schedule tab'));
      });
    }
  });
}
