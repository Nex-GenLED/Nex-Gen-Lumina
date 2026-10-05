// #118 — the selection as the app runs it: the resolver over the real auth,
// controllers and repository providers, with the saved choice, the
// "which answers" probe and setup flows.

import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/bridge_pairing.dart';
import 'package:nexgen_command/services/connectivity_service.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? get email => null;
}

class _MemoryStore implements ControllerSelectionStore {
  final selected = <String, String?>{};
  final connected = <String, Map<String, DateTime>>{};
  @override
  Future<String?> readSelected(String uid) async => selected[uid];
  @override
  Future<void> writeSelected(String uid, String? id) async =>
      selected[uid] = id;
  @override
  Future<Map<String, DateTime>> readConnected(String uid) async =>
      Map.of(connected[uid] ?? const {});
  @override
  Future<void> writeConnected(String uid, Map<String, DateTime> s) async =>
      connected[uid] = Map.of(s);
}

// Synthetic accounts, plain record ids, documentation addresses.
const _a = 'account-a';
const _b = 'account-b';
const _front = ControllerInfo(id: 'front', ip: '192.0.2.10', name: 'Front');
const _back = ControllerInfo(id: 'back', ip: '192.0.2.11', name: 'Back');
const _bHome = ControllerInfo(id: 'b-home', ip: '192.0.2.20', name: 'Home');

class _App {
  _App(this.c, this.auth, this.lists, this.store, this.probed);
  final ProviderContainer c;
  final StreamController<User?> auth;
  final Map<String, StreamController<List<ControllerInfo>>> lists;
  final _MemoryStore store;
  final List<String> probed;

  ControllerSelectionNotifier get notifier =>
      c.read(controllerSelectionProvider.notifier);
  ControllerSelection get selection => c.read(controllerSelectionProvider);
  String? get ip => c.read(selectedDeviceIpProvider);
  String? get id => c.read(selectedControllerIdProvider);

  void emit(String uid, List<ControllerInfo> records) =>
      lists[uid]!.add(records);

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

Future<_App> _app({
  _MemoryStore? store,
  Map<String, bool> answers = const {},
  bool shell = true,
}) async {
  final auth = StreamController<User?>.broadcast();
  final lists = {
    for (final uid in [_a, _b])
      uid: StreamController<List<ControllerInfo>>.broadcast(),
  };
  final probed = <String>[];
  final s = store ?? _MemoryStore();
  final c = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => auth.stream),
    controllersStreamProvider.overrideWith((ref) {
      final uid = ref.watch(effectiveUserUidProvider);
      if (uid == null || !lists.containsKey(uid)) return const Stream.empty();
      return lists[uid]!.stream;
    }),
    controllerSelectionStoreProvider.overrideWithValue(s),
    controllerReachabilityProbeProvider.overrideWithValue((ip) async {
      probed.add(ip);
      return answers[ip] ?? false;
    }),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    currentUserProfileProvider
        .overrideWith((ref) => Stream<UserModel?>.value(null)),
    pairedBridgeProvider
        .overrideWith((ref) => Stream.value(const PairedBridgeLookup.none())),
  ]);
  final app = _App(c, auth, lists, s, probed);
  addTearDown(() async {
    c.dispose();
    await auth.close();
    for (final l in lists.values) {
      await l.close();
    }
  });
  if (shell) {
    c.listen(autoConnectControllerProvider, (_, __) {}, fireImmediately: true);
  }
  c.listen(selectedDeviceIpProvider, (_, __) {}, fireImmediately: true);
  c.listen(selectedControllerIdProvider, (_, __) {}, fireImmediately: true);
  await app.settle();
  return app;
}

Future<void> _signIn(_App app, String uid, List<ControllerInfo> records) async {
  app.auth.add(_User(uid));
  await app.settle();
  app.emit(uid, records);
  await app.settle();
}

void main() {
  test('one record: selected silently by id, and saved for this account',
      () async {
    final app = await _app();
    await _signIn(app, _a, const [_front]);
    expect(app.ip, _front.ip);
    expect(app.id, 'front');
    expect(app.selection.needsChoice, isFalse);
    expect(app.probed, isEmpty, reason: 'one record needs no probe');
    expect(app.store.selected[_a], 'front');
  });

  test('cached-then-server snapshot: the old address first, then the current '
      'one — the selection and the repository follow', () async {
    final app = await _app();
    final repos = <WledRepository?>[];
    app.c.listen<WledRepository?>(wledRepositoryProvider, (_, n) => repos.add(n),
        fireImmediately: true);
    app.auth.add(_User(_a));
    await app.settle();
    app.emit(_a, const [ControllerInfo(id: 'front', ip: '192.0.2.40')]);
    await app.settle();
    expect(app.ip, '192.0.2.40');
    app.emit(_a, const [ControllerInfo(id: 'front', ip: '192.0.2.41')]);
    await app.settle();
    expect(app.ip, '192.0.2.41', reason: 'before #118 it stayed on the cache');
    expect(app.id, 'front');
    final repo = app.c.read(wledRepositoryProvider);
    expect(repo, isA<WledService>());
    final service = repo! as WledService;
    expect(service.baseUrl, 'http://192.0.2.41');
    expect(service.expectedControllerId, 'front');
  });

  test('the identity check keeps its expectation while the list reloads',
      () async {
    // The old IP-match lookup answered "no id" whenever the controllers list
    // was reloading, and the repository built in that gap carried no
    // identity expectation (and could not use the relay).
    final reload = StateProvider<int>((ref) => 0);
    final auth = StreamController<User?>.broadcast();
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth.stream),
      controllersStreamProvider.overrideWith((ref) async* {
        final n = ref.watch(reload);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (n >= 0) yield const [_front];
      }),
      controllerSelectionStoreProvider.overrideWithValue(_MemoryStore()),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      currentUserProfileProvider
          .overrideWith((ref) => Stream<UserModel?>.value(null)),
      pairedBridgeProvider
          .overrideWith((ref) => Stream.value(const PairedBridgeLookup.none())),
    ]);
    addTearDown(() async {
      c.dispose();
      await auth.close();
    });
    c.listen(autoConnectControllerProvider, (_, __) {}, fireImmediately: true);
    final expectations = <String?>[];
    c.listen<WledRepository?>(wledRepositoryProvider, (_, n) {
      if (n is WledService) expectations.add(n.expectedControllerId);
    }, fireImmediately: true);
    auth.add(_User(_a));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.read(selectedControllerIdProvider), 'front');
    c.read(reload.notifier).state++;
    // Mid-reload: the list is loading again.
    expect(c.read(controllersStreamProvider).isLoading, isTrue);
    expect(c.read(selectedControllerIdProvider), 'front');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(expectations, isNotEmpty);
    expect(expectations, everyElement('front'));
  });

  test('user switch: the previous account\'s selection does not survive; each '
      'account keeps its own saved choice', () async {
    final store = _MemoryStore()..selected[_a] = 'back';
    final app = await _app(store: store);
    await _signIn(app, _a, const [_front, _back]);
    expect(app.id, 'back', reason: 'A\'s saved choice, not the newest record');
    expect(app.probed, isEmpty);

    app.auth.add(_User(_b));
    await app.settle();
    expect(app.ip, isNull, reason: 'B\'s list has not arrived: nothing yet');
    app.emit(_b, const [_bHome]);
    await app.settle();
    expect(app.id, 'b-home');
    expect(store.selected[_b], 'b-home');
    expect(store.selected[_a], 'back', reason: 'A\'s choice is A\'s');

    app.auth.add(_User(_a));
    await app.settle();
    app.emit(_a, const [_front, _back]);
    await app.settle();
    expect(app.id, 'back', reason: 'back on A, A\'s own choice again');
  });

  test('several records, no saved choice: the most recently connected',
      () async {
    final store = _MemoryStore()
      ..connected[_a] = {'back': DateTime(2026, 10, 4)};
    final app = await _app(store: store);
    await _signIn(app, _a, const [_front, _back]);
    expect(app.id, 'back');
    expect(app.probed, isEmpty);
  });

  test('several records, no history, two answer → the customer chooses; the '
      'choice is used and saved', () async {
    final app = await _app(answers: {_front.ip: true, _back.ip: true});
    await _signIn(app, _a, const [_front, _back]);
    expect(app.probed, unorderedEquals([_front.ip, _back.ip]));
    expect(app.selection.needsChoice, isTrue);
    expect(app.selection.choices, ['front', 'back']);
    expect(app.ip, isNull, reason: 'nothing is driven until they choose');

    app.notifier.use('back');
    await app.settle();
    expect(app.id, 'back');
    expect(app.selection.needsChoice, isFalse);
    expect(app.store.selected[_a], 'back');
  });

  test('several records, no history, ONE answers → that one, no prompt',
      () async {
    final app = await _app(answers: {_back.ip: true});
    await _signIn(app, _a, const [_front, _back]);
    expect(app.id, 'back');
    expect(app.selection.needsChoice, isFalse);
  });

  test('several records, no history, none answers (away) → the newest, no '
      'prompt', () async {
    final app = await _app();
    await _signIn(app, _a, const [_front, _back]);
    expect(app.id, 'front');
    expect(app.selection.needsChoice, isFalse);
  });

  test('the empty-address newest record is skipped', () async {
    final app = await _app();
    await _signIn(app, _a, const [ControllerInfo(id: 'pending', ip: ''), _back]);
    expect(app.id, 'back');
  });

  test('a record whose address is cleared drops out of the selection',
      () async {
    final app = await _app();
    await _signIn(app, _a, const [_front]);
    app.emit(_a, const [ControllerInfo(id: 'front', ip: '')]);
    await app.settle();
    expect(app.ip, isNull);
    expect(app.id, isNull);
  });

  test('deleting the active controller moves to the next record', () async {
    final store = _MemoryStore()..selected[_a] = 'front';
    final app = await _app(store: store);
    await _signIn(app, _a, const [_front, _back]);
    expect(app.id, 'front');
    // The list has not caught up with the delete yet; the deleted set has.
    app.c.read(deletedControllerIdsProvider.notifier).state = {'front'};
    await app.settle();
    expect(app.id, 'back');
    expect(app.ip, _back.ip);
  });

  test('a transient address is kept during setup and released after',
      () async {
    final app = await _app();
    await _signIn(app, _a, const [_front]);
    expect(app.id, 'front');

    app.notifier.pointAt('192.0.2.77'); // a device being set up
    await app.settle();
    expect(app.ip, '192.0.2.77');
    expect(app.selection.transient, isTrue);
    expect(app.id, isNull, reason: 'no record at that address');

    // Records keep arriving while the device is being set up.
    app.emit(_a, const [_front, _back]);
    await app.settle();
    expect(app.ip, '192.0.2.77', reason: 'never pulled away mid-setup');

    app.notifier.release(ip: '192.0.2.77');
    await app.settle();
    expect(app.selection.transient, isFalse);
    expect(app.ip, isNot('192.0.2.77'));
    expect(app.id, isNotNull);
  });

  test('a transient address becomes the record once it is saved', () async {
    final app = await _app();
    await _signIn(app, _a, const [_front]);
    app.notifier.pointAt('192.0.2.77');
    await app.settle();
    app.emit(_a, const [
      ControllerInfo(id: 'new-one', ip: '192.0.2.77'),
      _front,
    ]);
    await app.settle();
    expect(app.selection.transient, isFalse);
    expect(app.id, 'new-one');
    expect(app.ip, '192.0.2.77');
    expect(app.store.selected[_a], 'new-one');
  });

  test('pointing at an existing record\'s address selects that record',
      () async {
    final app = await _app();
    await _signIn(app, _a, const [_front, _back]);
    app.notifier.pointAt(_back.ip);
    await app.settle();
    expect(app.selection.transient, isFalse);
    expect(app.id, 'back');
  });

  test('outside the app shell nothing is chosen on its own', () async {
    final app = await _app(shell: false);
    await _signIn(app, _a, const [_front]);
    expect(app.ip, isNull);
    app.notifier.use('front');
    await app.settle();
    expect(app.id, 'front');
  });

  test('an installer viewing a customer does not save a choice on this phone',
      () async {
    final app = await _app();
    app.auth.add(_User(_b)); // the installer's own sign-in
    await app.settle();
    app.emit(_b, const [_bHome]);
    await app.settle();
    expect(app.store.selected[_b], 'b-home');

    app.c.read(installerAccessingCustomerProvider.notifier).state = _a;
    await app.settle();
    app.emit(_a, const [_front]);
    await app.settle();
    expect(app.id, 'front');
    expect(app.store.selected.containsKey(_a), isFalse);
  });

  test('a connected selection is remembered as the most recent', () async {
    final app = await _app();
    await _signIn(app, _a, const [_front]);
    app.notifier.markConnected();
    expect(app.store.connected[_a]?.keys, contains('front'));
  });

  test('lib/ never writes selectedDeviceIpProvider directly — every choice '
      'goes through the resolver', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('selectedDeviceIpProvider.notifier')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
