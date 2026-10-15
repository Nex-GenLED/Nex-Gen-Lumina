// Grey screen on build 117 (installer opens a customer; a controller is added):
// three device records of Riverpod's ConcurrentModificationError, thrown
// inside the provider scheduler's refresh while a provider walked its own
// dependency map three flushes deep — the shape left by a callback that
// ref.reads (flushes) a provider that is itself mid-rebuild.
//
// This harness puts the four listeners that read providers synchronously
// (controllerConnectionStampProvider, ladderBusChangeWatchProvider, the
// ControllerSelectionNotifier's own listeners, and WledNotifier's repository
// listener with its healer read) in ONE frame with an account switch, a
// controller-stream emission and a connection-state flip, in every order, on
// the REAL providers (the real WledNotifier build, the real hardware-config
// provider, the real selection and repository). It fails if any variant
// throws, naming the variant.
//
// Synthetic accounts and documentation addresses only.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controller_choice_prompt.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
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

/// The REAL WledNotifier (its build registers the repository listener that
/// reads the healer), plus a hook to flip the connection flag the way a poll
/// result does.
class RealFlipWledNotifier extends WledNotifier {
  void setConnected(bool v) => state = state.copyWith(connected: v);
}

const _installer = 'installer-i';
const _customer = 'customer-c';
final _ctlA = ControllerInfo(id: 'ctl-a', ip: '192.0.2.31', name: 'Front');
final _ctlB = ControllerInfo(id: 'ctl-b', ip: '192.0.2.32', name: 'Garage');

/// What MainScaffold.build does with the selection, then the real Home.
class _Shell extends ConsumerWidget {
  const _Shell();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoConnectControllerProvider);
    ref.watch(ladderBusChangeWatchProvider);
    ref.watch(controllerConnectionStampProvider);
    listenForControllerChoice(ref, context);
    return const WledDashboardPage();
  }
}

Future<void> _addRecord(FakeFirebaseFirestore fs, ControllerInfo r) => fs
    .collection('users')
    .doc(_customer)
    .collection('controllers')
    .doc(r.id)
    .set({'ip': r.ip, 'name': r.name, 'createdAt': Timestamp.now()});

/// One run of the shell on the real graph. [syncStream] replaces Firestore
/// with a stream that delivers its list synchronously on listen (the harshest
/// shape: the list lands INSIDE controllersStreamProvider's own rebuild).
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeFirebaseFirestore fs,
  required String authUid,
  List<ControllerInfo> Function(String? uid)? syncStream,
}) async {
  SharedPreferences.setMockInitialValues({});
  final c = ProviderContainer(overrides: [
    ...homeDashboardOverrides(
      repo: RecordingWledRepository(),
      user: _User(authUid),
      profile: null,
      realIdentity: true,
      realWled: true,
    ),
    wledStateProvider.overrideWith(RealFlipWledNotifier.new),
    controllersFirestoreProvider.overrideWithValue(fs),
    if (syncStream != null)
      controllersStreamProvider.overrideWith((ref) {
        final uid = ref.watch(effectiveUserUidProvider);
        final ctl = StreamController<List<ControllerInfo>>(sync: true);
        ctl.onListen = () => ctl.add(syncStream(uid));
        ref.onDispose(ctl.close);
        return ctl.stream;
      }),
    controllerReachabilityProbeProvider
        .overrideWithValue((ip) async => ip == _ctlA.ip || ip == _ctlB.ip),
    // deviceHardwareConfigProvider is REAL: it watches the repository.
  ]);
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: _Shell())),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return c;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Every exception Flutter reported while settling, as strings.
Future<List<String>> _drain(WidgetTester tester) async {
  final out = <String>[];
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
    for (var e = tester.takeException(); e != null; e = tester.takeException()) {
      out.add(e.toString());
    }
  }
  return out;
}

Future<void> _teardown(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  try {
    c.dispose();
  } catch (_) {}
  await tester.pump();
}

/// The mutations one frame can carry, in the order [steps] lists them:
///   open   installer opens the customer account (effective uid changes)
///   emit   the customer's controller list changes (second record saved)
///   point  the add page points the selection at the new address
///   inval  the add page invalidates the controller list and area ips
///   up     the connection comes up (poll result)
///   down   the connection drops
const _allOrders = <List<String>>[
  ['open', 'up'],
  ['up', 'open'],
  ['open', 'emit', 'up'],
  ['open', 'up', 'emit'],
  ['up', 'open', 'emit'],
  ['down', 'open', 'up'],
  ['open', 'down', 'up'],
  ['emit', 'point', 'inval', 'up'],
  ['point', 'inval', 'emit', 'up'],
  ['up', 'point', 'inval', 'emit'],
  ['down', 'point', 'inval', 'emit', 'up'],
  ['open', 'emit', 'point', 'inval', 'up'],
  ['open', 'point', 'inval', 'emit', 'down', 'up'],
];

void main() {
  for (final sync in const [false, true]) {
    for (final order in _allOrders) {
      final label = '${sync ? 'SYNC-STREAM' : 'firestore'} ${order.join('>')}';
      testWidgets('one frame: $label', (tester) async {
        final fs = FakeFirebaseFirestore();
        var list = <ControllerInfo>[_ctlA];
        await _addRecord(fs, _ctlA);
        final opens = order.contains('open');
        final c = await _pump(tester,
            fs: fs,
            authUid: opens ? _installer : _customer,
            syncStream: sync ? (uid) => uid == _customer ? list : const [] : null);
        await _settle(tester);
        // A clean start: anything thrown here is not the sequence under test.
        expect(await _drain(tester), isEmpty, reason: 'before $label');
        final w = c.read(wledStateProvider.notifier) as RealFlipWledNotifier;

        // All of the frame's mutations, synchronously, then ONE pump.
        for (final s in order) {
          switch (s) {
            case 'open':
              c.read(installerAccessingCustomerProvider.notifier).state = _customer;
              c.read(installerAccessingCustomerNameProvider.notifier).state = 'Customer A';
            case 'emit':
              list = [_ctlA, _ctlB];
              if (!sync) await _addRecord(fs, _ctlB);
              if (sync) c.invalidate(controllersStreamProvider);
            case 'point':
              c.read(controllerSelectionProvider.notifier).pointAt(_ctlB.ip);
            case 'inval':
              c.invalidate(controllersStreamProvider);
              c.invalidate(activeAreaControllerIpsProvider);
            case 'up':
              w.setConnected(true);
            case 'down':
              w.setConnected(false);
          }
        }
        final thrown = await _drain(tester);
        await _teardown(tester, c);
        expect(thrown, isEmpty, reason: 'variant $label threw: $thrown');
      });
    }
  }
}
