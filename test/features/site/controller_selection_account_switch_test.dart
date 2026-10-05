// #118 — the selected controller belongs to the account that chose it.
//
// Owner report (builds 112–115): after signing out of one account and into
// another on the same phone (test, reviewer and installer accounts), the app
// did nothing until "Set as Active" was pressed. The selection is an
// in-memory address, and nothing let go of it when the account changed:
// auto-connect only fills an EMPTY selection, so account B kept account A's
// address. On the home network that address got a repository with no identity
// expectation (B has no record at A's address), so a write could reach A's
// controller.
//
// These tests drive the real providers — auth stream, controllers stream over
// a fake Firestore, auto-connect, the routed repository — and record every
// selection, controller id and repository the app produced. After A signs out,
// none of them may ever point at A again.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/bridge_pairing.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? get email => null;
}

// Synthetic accounts and documentation addresses — no real account or device.
const _a = 'account-a';
const _b = 'account-b';
const _installer = 'installer-i';
const _customer = 'customer-c';
const _aId = 'ctl-a';
const _aIp = '192.0.2.11';
const _a2Id = 'ctl-a-second';
const _a2Ip = '192.0.2.13';
const _bId = 'ctl-b';
const _bIp = '192.0.2.12';
const _iId = 'ctl-installer';
const _iIp = '192.0.2.21';
const _cId = 'ctl-customer';
const _cIp = '192.0.2.31';

class _Harness {
  _Harness(this.c, this.auth, this.db);
  final ProviderContainer c;
  final StreamController<User?> auth;
  final FakeFirebaseFirestore db;

  final selections = <String?>[];
  final ids = <String?>[];
  final repos = <WledRepository?>[];

  /// Index into the recordings from which [_aIp] / [_aId] must never appear.
  int sealedSelections = 0, sealedIds = 0, sealedRepos = 0;

  void seal() {
    sealedSelections = selections.length;
    sealedIds = ids.length;
    sealedRepos = repos.length;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  String? get selected => c.read(selectedDeviceIpProvider);
  String? get selectedId => c.read(selectedControllerIdProvider);
  String? get repoUrl {
    final r = c.read(wledRepositoryProvider);
    return r is WledService ? r.baseUrl : null;
  }

  /// Nothing recorded since [seal] targets [ip] / [id].
  void expectNeverAgain({required String ip, required String id}) {
    expect(selections.skip(sealedSelections), isNot(contains(ip)),
        reason: 'a later selection still held the previous address');
    expect(ids.skip(sealedIds), isNot(contains(id)),
        reason: 'a later selection still resolved to the previous record');
    for (final r in repos.skip(sealedRepos)) {
      if (r is WledService) {
        expect(r.baseUrl, isNot(contains(ip)),
            reason: 'a repository was built for the previous address');
      }
    }
  }
}

Future<void> _addController(FakeFirebaseFirestore db, String uid, String id,
    String ip, DateTime created) {
  return db.doc('users/$uid/controllers/$id').set({
    'ip': ip,
    'name': 'Controller $id',
    'createdAt': Timestamp.fromDate(created),
  });
}

Future<_Harness> _harness() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final db = FakeFirebaseFirestore();
  await _addController(db, _a, _aId, _aIp, DateTime(2026, 1, 2));
  await _addController(db, _b, _bId, _bIp, DateTime(2026, 1, 2));
  await _addController(db, _installer, _iId, _iIp, DateTime(2026, 1, 2));
  await _addController(db, _customer, _cId, _cIp, DateTime(2026, 1, 2));
  final auth = StreamController<User?>.broadcast();
  final c = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => auth.stream),
    controllersFirestoreProvider.overrideWithValue(db),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    currentUserProfileProvider
        .overrideWith((ref) => Stream<UserModel?>.value(null)),
    pairedBridgeProvider
        .overrideWith((ref) => Stream.value(const PairedBridgeLookup.none())),
    // No network in tests: nothing answers, so with several records and no
    // saved choice the newest record is selected (#118 rule 8).
    controllerReachabilityProbeProvider.overrideWithValue((ip) async => false),
  ]);
  final h = _Harness(c, auth, db);
  addTearDown(() async {
    c.dispose();
    await auth.close();
  });
  // MainScaffold keeps auto-connect alive for the whole signed-in session.
  c.listen(autoConnectControllerProvider, (_, __) {}, fireImmediately: true);
  c.listen<String?>(selectedDeviceIpProvider, (_, n) => h.selections.add(n),
      fireImmediately: true);
  c.listen<String?>(selectedControllerIdProvider, (_, n) => h.ids.add(n),
      fireImmediately: true);
  c.listen<WledRepository?>(wledRepositoryProvider, (_, n) => h.repos.add(n),
      fireImmediately: true);
  await h.settle();
  return h;
}

void main() {
  test('A signs out, B signs in: nothing of A is selected, and no repository '
      'ever targets A again', () async {
    final h = await _harness();

    h.auth.add(_User(_a));
    await h.settle();
    expect(h.selected, _aIp);
    expect(h.selectedId, _aId);
    expect(h.repoUrl, 'http://$_aIp');

    h.seal();
    h.auth.add(null); // sign out
    await h.settle();
    expect(h.selected, isNull, reason: 'signed out — nothing may stay selected');
    expect(h.c.read(wledRepositoryProvider), isNull);

    h.auth.add(_User(_b));
    await h.settle();
    expect(h.selected, _bIp);
    expect(h.selectedId, _bId);
    expect(h.repoUrl, 'http://$_bIp');
    h.expectNeverAgain(ip: _aIp, id: _aId);
  });

  test('A → B with no sign-out in between (account switch): B gets B\'s '
      'controller, never A\'s address', () async {
    final h = await _harness();

    h.auth.add(_User(_a));
    await h.settle();
    expect(h.selected, _aIp);

    h.seal();
    h.auth.add(_User(_b));
    await h.settle();
    expect(h.selected, _bIp);
    expect(h.selectedId, _bId);
    expect(h.repoUrl, 'http://$_bIp');
    h.expectNeverAgain(ip: _aIp, id: _aId);
  });

  test('B shares no record with A: the old address would have resolved to no '
      'id — the case where the identity check was skipped', () async {
    final h = await _harness();
    h.auth.add(_User(_a));
    await h.settle();
    h.seal();
    h.auth.add(_User(_b));
    await h.settle();
    for (final r in h.repos.skip(h.sealedRepos)) {
      if (r is WledService) {
        // Every repository built for B carries B's record id, so #92's
        // identity check runs before its first write.
        expect(r.expectedControllerId, _bId);
      }
    }
  });

  test('installer opens a customer and exits: the customer\'s controller does '
      'not stay selected', () async {
    final h = await _harness();
    h.auth.add(_User(_installer));
    await h.settle();
    expect(h.selected, _iIp);

    h.seal();
    h.c.read(installerAccessingCustomerProvider.notifier).state = _customer;
    await h.settle();
    expect(h.selected, _cIp, reason: 'impersonating — the customer\'s record');
    h.expectNeverAgain(ip: _iIp, id: _iId);

    h.seal();
    h.c.read(installerAccessingCustomerProvider.notifier).state = null;
    await h.settle();
    expect(h.selected, _iIp, reason: 'impersonation exit — back to own record');
    h.expectNeverAgain(ip: _cIp, id: _cId);
  });

  test('signing in on a fresh launch keeps what is already chosen (no previous '
      'account to clear)', () async {
    final h = await _harness();
    // Before auth answers there is no account; a selection made then is not
    // a previous account's and is left alone when the first user arrives.
    h.c.read(selectedDeviceIpProvider.notifier).state = _aIp;
    h.auth.add(_User(_a));
    await h.settle();
    expect(h.selected, _aIp);
  });

  test('deleting the active controller lets go of its address and moves to '
      'the next record', () async {
    final h = await _harness();
    await _addController(h.db, _a, _a2Id, _a2Ip, DateTime(2026, 1, 1));
    h.auth.add(_User(_a));
    await h.settle();
    expect(h.selected, _aIp, reason: 'newest record first');

    h.seal();
    final ok = await h.c.read(deleteControllerProvider)(_aId);
    expect(ok, isTrue);
    await h.settle();
    expect(h.selected, _a2Ip);
    expect(h.selectedId, _a2Id);
    h.expectNeverAgain(ip: _aIp, id: _aId);
  });

  test('deleting a controller that is NOT active leaves the selection alone',
      () async {
    final h = await _harness();
    await _addController(h.db, _a, _a2Id, _a2Ip, DateTime(2026, 1, 1));
    h.auth.add(_User(_a));
    await h.settle();
    expect(h.selected, _aIp);

    final ok = await h.c.read(deleteControllerProvider)(_a2Id);
    expect(ok, isTrue);
    await h.settle();
    expect(h.selected, _aIp);
    expect(h.selectedId, _aId);
  });
}
