// An installer opens a customer's account (Existing Customer) and then adds or
// changes that customer's controller, all in one session. Owner report
// (customer A, 2026-10-14): the screen went grey at each step; after signing
// out and in again the controller showed as connected.
//
// A grey full screen in a release build is Flutter's ErrorWidget: something
// threw while a widget was building. This test runs the same sequence against
// the REAL providers (effective uid, controllers stream, the controller
// selection, auto-connect, the bus-change watch, the Which-controller prompt)
// and the REAL Home screen, with the network and Firestore replaced by plain
// values, and fails on any exception Flutter reports.
//
// Synthetic accounts and documentation addresses only — no real account,
// customer or device.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controller_choice_prompt.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? get email => null;
  @override
  bool get isAnonymous => false;
}

const _installer = 'installer-i';
const _customer = 'customer-c';
final _ctlA = ControllerInfo(id: 'ctl-a', ip: '192.0.2.31', name: 'Front');
final _ctlB = ControllerInfo(id: 'ctl-b', ip: '192.0.2.32', name: 'Garage');

/// What the shell (MainScaffold.build) does with the controller selection,
/// then the real Home screen under it.
class _FlipWled extends SeededWledNotifier {
  _FlipWled() : super(kHomeLitState);
  void setConnected(bool v) => state = state.copyWith(connected: v);
}

class _ShellProbe extends ConsumerWidget {
  const _ShellProbe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoConnectControllerProvider);
    ref.watch(ladderBusChangeWatchProvider);
    ref.watch(controllerConnectionStampProvider);
    listenForControllerChoice(ref, context);
    return const WledDashboardPage();
  }
}

final _store = StateProvider<Map<String, List<ControllerInfo>>>((ref) => {});

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Set<String> answering,
  bool realWled = false,
  bool flip = false,
  String authUid = _installer,
}) async {
  SharedPreferences.setMockInitialValues({});
  final base = homeDashboardOverrides(
    repo: RecordingWledRepository(),
    user: _User(authUid),
    profile: null, // the installer has no customer profile of its own
    realIdentity: true,
    realWled: realWled,
  );
  final overrides = [
    ...base,
    if (flip) wledStateProvider.overrideWith(() => _FlipWled()),
    controllersStreamProvider.overrideWith((ref) {
      final uid = ref.watch(effectiveUserUidProvider);
      final store = ref.watch(_store);
      return Stream.value(store[uid] ?? const <ControllerInfo>[]);
    }),
    controllerReachabilityProbeProvider
        .overrideWithValue((ip) async => answering.contains(ip)),
    deviceHardwareConfigProvider.overrideWith((ref) async => null),
  ];
  final c = ProviderContainer(overrides: overrides);
  addTearDown(() {
    try {
      c.dispose();
    } catch (_) {}
  });
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: _ShellProbe())),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return c;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('installer opens a customer, then the customer gains a controller',
      (tester) async {
    final c = await _pump(tester, answering: {_ctlA.ip});
    c.read(_store.notifier).state = {
      _customer: [_ctlA],
    };
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'installer, no customer yet');

    // Existing Customer -> _accessCustomer(): two provider writes, then the
    // router goes to the dashboard.
    c.read(installerAccessingCustomerProvider.notifier).state = _customer;
    c.read(installerAccessingCustomerNameProvider.notifier).state = 'Customer A';
    await _settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'after opening the customer account');
    expect(c.read(controllerSelectionProvider).controllerId, _ctlA.id);

    // The customer gains a second controller while the installer is in the
    // account (the add / change-controller step).
    c.read(_store.notifier).state = {
      _customer: [_ctlA, _ctlB],
    };
    await _settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'after the customer gained a controller');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('both controllers answer: the Which-controller prompt opens',
      (tester) async {
    final c = await _pump(tester, answering: {_ctlA.ip, _ctlB.ip});
    c.read(_store.notifier).state = {
      _customer: [_ctlA, _ctlB],
    };
    await _settle(tester);
    c.read(installerAccessingCustomerProvider.notifier).state = _customer;
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Which controller should this phone use?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('controller-choice-use-ctl-b')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(c.read(controllerSelectionProvider).controllerId, _ctlB.id);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'REAL repository and state: installer opens a customer, then a controller is added',
      (tester) async {
    final c = await _pump(tester, answering: {_ctlA.ip, _ctlB.ip}, realWled: true);
    c.read(_store.notifier).state = {_customer: [_ctlA]};
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'installer, nothing selected');

    c.read(installerAccessingCustomerProvider.notifier).state = _customer;
    c.read(installerAccessingCustomerNameProvider.notifier).state = 'Customer A';
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'after opening the customer account');

    // The add step: select the new address, refresh the lists, then the record
    // arrives (device_setup_page / discovery_page order).
    c.read(controllerSelectionProvider.notifier).pointAt(_ctlB.ip);
    c.invalidate(controllersStreamProvider);
    c.invalidate(activeAreaControllerIpsProvider);
    c.read(_store.notifier).state = {_customer: [_ctlA, _ctlB]};
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'after the controller was added');

    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump();
  });

  testWidgets(
      'REAL repository and state: the customer signed in as themselves adds a controller',
      (tester) async {
    final c = await _pump(tester,
        answering: {_ctlA.ip, _ctlB.ip}, realWled: true, authUid: _customer);
    c.read(_store.notifier).state = {_customer: [_ctlA]};
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'customer signed in');
    expect(c.read(controllerSelectionProvider).controllerId, _ctlA.id);

    c.read(controllerSelectionProvider.notifier).pointAt(_ctlB.ip);
    c.invalidate(controllersStreamProvider);
    c.invalidate(activeAreaControllerIpsProvider);
    c.read(_store.notifier).state = {_customer: [_ctlA, _ctlB]};
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'after the controller was added');

    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump();
  });

  for (final flipAt in const ['before-open', 'at-open', 'after-open', 'at-add', 'after-add']) {
    testWidgets('connected flips $flipAt (real repository, installer then add)',
        (tester) async {
      final c = await _pump(tester,
          answering: {_ctlA.ip, _ctlB.ip}, realWled: true, flip: true);
      final w = c.read(wledStateProvider.notifier) as _FlipWled;
      c.read(_store.notifier).state = {_customer: [_ctlA]};
      await _settle(tester);
      if (flipAt == 'before-open') { w.setConnected(false); w.setConnected(true); }
      c.read(installerAccessingCustomerProvider.notifier).state = _customer;
      if (flipAt == 'at-open') { w.setConnected(false); w.setConnected(true); }
      await _settle(tester);
      if (flipAt == 'after-open') { w.setConnected(false); await tester.pump(); w.setConnected(true); }
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'open ($flipAt)');
      c.read(controllerSelectionProvider.notifier).pointAt(_ctlB.ip);
      if (flipAt == 'at-add') { w.setConnected(false); w.setConnected(true); }
      c.invalidate(controllersStreamProvider);
      c.read(_store.notifier).state = {_customer: [_ctlA, _ctlB]};
      if (flipAt == 'after-add') { w.setConnected(false); w.setConnected(true); }
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'add ($flipAt)');
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.pump();
    });
  }

  // ── The shape the device record shows: the customer's old controller is gone,
  // and the NEW record arrives while the app is open. Real Firestore stream
  // (over a fake store), real delete, real selection, real repository.
  Future<ProviderContainer> pumpFs(WidgetTester tester, FakeFirebaseFirestore fs,
      {required String authUid}) async {
    SharedPreferences.setMockInitialValues({});
    final base = homeDashboardOverrides(
      repo: RecordingWledRepository(),
      user: _User(authUid),
      profile: null,
      realIdentity: true,
      realWled: true,
    );
    final c = ProviderContainer(overrides: [
      ...base,
      controllersFirestoreProvider.overrideWithValue(fs),
      controllerReachabilityProbeProvider
          .overrideWithValue((ip) async => ip == _ctlA.ip || ip == _ctlB.ip),
      deviceHardwareConfigProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(() {
      try {
        c.dispose();
      } catch (_) {}
    });
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: _ShellProbe())),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    return c;
  }

  Future<void> addRecord(FakeFirebaseFirestore fs, ControllerInfo r) => fs
      .collection('users')
      .doc(_customer)
      .collection('controllers')
      .doc(r.id)
      .set({'ip': r.ip, 'name': r.name, 'createdAt': Timestamp.now()});

  for (final mode in const ['installer', 'customer']) {
    for (final startsWithOld in const [true, false]) {
      testWidgets(
          'FIRESTORE stream, $mode session, ${startsWithOld ? "old controller removed, then" : "no controller, then"} a new one is added',
          (tester) async {
        final fs = FakeFirebaseFirestore();
        if (startsWithOld) await addRecord(fs, _ctlA);
        final c = await pumpFs(tester, fs,
            authUid: mode == 'installer' ? _installer : _customer);
        await _settle(tester);
        if (mode == 'installer') {
          c.read(installerAccessingCustomerProvider.notifier).state = _customer;
          c.read(installerAccessingCustomerNameProvider.notifier).state = 'Customer A';
        }
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: 'opened ($mode)');

        if (startsWithOld) {
          // The old controller is removed (Settings -> Controllers -> delete).
          expect(await c.read(deleteControllerProvider)(_ctlA.id), isTrue);
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: 'old controller deleted');
        }

        // The add step, in the order the add pages do it: the record is saved,
        // the address is selected, the lists are refreshed, the app goes Home.
        await addRecord(fs, _ctlB);
        c.read(controllerSelectionProvider.notifier).pointAt(_ctlB.ip);
        c.invalidate(controllersStreamProvider);
        c.invalidate(activeAreaControllerIpsProvider);
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: 'new controller added');
        expect(c.read(controllerSelectionProvider).controllerId, _ctlB.id);

        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        await tester.pump();
      });
    }
  }
}
