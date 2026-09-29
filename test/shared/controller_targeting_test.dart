// P1 — controller targeting: the per-controller repository factory and the
// fan-out over the account's linked controllers.
//
// The Home power circle was the only control that reached every linked
// controller, and it did so with raw `WledService('http://<address>')`
// requests: they ignored whether the phone was home or away, skipped the
// identity check, and swallowed their own failures.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/controller_targeting.dart';
import 'package:nexgen_command/shared/write_result.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

import '../helpers/recording_wled_repository.dart';

// Documentation addresses and plain record ids — no real device.
const _front = ControllerInfo(id: 'front', ip: '192.0.2.10', name: 'Front');
const _back = ControllerInfo(id: 'back', ip: '192.0.2.11', name: 'Back');
const _shed = ControllerInfo(id: 'shed', ip: '192.0.2.12', name: 'Shed');
const _noAddress = ControllerInfo(id: 'pending', ip: '');

Future<ProviderContainer> _container({
  required List<ControllerInfo> controllers,
  String? selectedIp,
  Map<String, WledRepository?> repos = const {},
  Set<String> linked = const {},
  SiteMode mode = SiteMode.residential,
}) async {
  final c = ProviderContainer(overrides: [
    controllersStreamProvider.overrideWith((ref) => Stream.value(controllers)),
    controllerRepositoryProvider
        .overrideWith((ref, target) => repos[target.ip]),
  ]);
  addTearDown(c.dispose);
  c.read(selectedDeviceIpProvider.notifier).state = selectedIp;
  c.read(siteModeProvider.notifier).state = mode;
  c.read(linkedControllersProvider.notifier).setAll(linked);
  await c.read(controllersStreamProvider.future);
  return c;
}

void main() {
  group('buildRoutedRepository — one transport decision for every controller',
      () {
    ControllerRoute route(ConnectivityStatus network,
            {String? userId = 'account', String? controllerId = 'front'}) =>
        ControllerRoute(
          ip: '192.0.2.10',
          controllerId: controllerId,
          userId: userId,
          connectivity: network,
          webhookUrl: null,
        );

    test('home network → direct, identity-checked, counted as routed', () {
      final repo = buildRoutedRepository(route(ConnectivityStatus.local));
      expect(repo, isA<WledService>());
      repo as WledService;
      expect(repo.baseUrl, 'http://192.0.2.10');
      expect(repo.expectedControllerId, 'front');
      expect(repo.recordsRouting, isTrue);
    });

    test('away from home → relayed to THAT controller', () {
      final repo = buildRoutedRepository(
        route(ConnectivityStatus.remote),
        firestore: FakeFirebaseFirestore(),
      );
      expect(repo, isA<CloudRelayRepository>());
      repo as CloudRelayRepository;
      expect(repo.userId, 'account');
      expect(repo.controllerId, 'front');
      expect(repo.controllerIp, '192.0.2.10');
    });

    test('away from home with no account record → nothing to relay through',
        () {
      expect(
        buildRoutedRepository(
            route(ConnectivityStatus.remote, controllerId: null)),
        isNull,
      );
      expect(
        buildRoutedRepository(route(ConnectivityStatus.remote, userId: null)),
        isNull,
      );
    });

    test('offline → no repository', () {
      expect(buildRoutedRepository(route(ConnectivityStatus.offline)), isNull);
    });
  });

  group('controllerRepositoryProvider — the per-controller factory', () {
    Future<ProviderContainer> real({required ConnectivityStatus network}) async {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        currentUserProfileProvider
            .overrideWith((ref) => Stream<UserModel?>.value(null)),
        controllersStreamProvider
            .overrideWith((ref) => Stream.value(const [_front, _back])),
        wledConnectivityStatusProvider
            .overrideWith((ref) => Stream<ConnectivityStatus>.value(network)),
      ]);
      addTearDown(c.dispose);
      c.read(selectedDeviceIpProvider.notifier).state = _front.ip;
      await c.read(wledConnectivityStatusProvider.future);
      await c.read(controllersStreamProvider.future);
      await c.read(authStateProvider.future);
  // Settled before the first read so the repository is built once.
  await c.read(currentUserProfileProvider.future);
      return c;
    }

    test('the selected controller is served by the ONE routed instance',
        () async {
      final c = await real(network: ConnectivityStatus.local);
      final selected = c.read(controllerRepositoryProvider(
          ControllerTarget(ip: _front.ip, controllerId: _front.id)));
      expect(identical(selected, c.read(wledRepositoryProvider)), isTrue);
    });

    test('another controller gets its own, routed the same way', () async {
      final c = await real(network: ConnectivityStatus.local);
      final other = c.read(controllerRepositoryProvider(
          ControllerTarget(ip: _back.ip, controllerId: _back.id)));
      expect(other, isA<WledService>());
      other as WledService;
      expect(other.baseUrl, 'http://${_back.ip}');
      expect(other.expectedControllerId, _back.id);
      expect(identical(other, c.read(wledRepositoryProvider)), isFalse);
    });

    test('the same controller is not rebuilt on every call', () async {
      final c = await real(network: ConnectivityStatus.local);
      final target = ControllerTarget(ip: _back.ip, controllerId: _back.id);
      expect(
        identical(c.read(controllerRepositoryProvider(target)),
            c.read(controllerRepositoryProvider(target))),
        isTrue,
      );
    });

    test('offline → no repository for anyone', () async {
      final c = await real(network: ConnectivityStatus.offline);
      expect(
        c.read(controllerRepositoryProvider(
            ControllerTarget(ip: _back.ip, controllerId: _back.id))),
        isNull,
      );
    });

    test('a controller with no address cannot be targeted', () async {
      final c = await real(network: ConnectivityStatus.local);
      expect(
        c.read(controllerRepositoryProvider(
            const ControllerTarget(ip: '', controllerId: 'pending'))),
        isNull,
      );
    });
  });

  group('linkedControllerTargetsProvider', () {
    test('no linked set → every registered controller with an address',
        () async {
      final c = await _container(controllers: [_front, _back, _noAddress]);
      expect(c.read(linkedControllerTargetsProvider).map((t) => t.controllerId),
          ['front', 'back']);
    });

    test('residential with a linked set → only the linked ones', () async {
      final c = await _container(
        controllers: [_front, _back, _shed],
        linked: {'front', 'shed'},
      );
      expect(c.read(linkedControllerTargetsProvider).map((t) => t.controllerId),
          ['front', 'shed']);
    });

    test('commercial ignores the residential linked set', () async {
      final c = await _container(
        controllers: [_front, _back],
        linked: {'front'},
        mode: SiteMode.commercial,
      );
      expect(c.read(linkedControllerTargetsProvider), hasLength(2));
    });

    test('no registered controllers → the selected device alone', () async {
      final c = await _container(controllers: [], selectedIp: '192.0.2.50');
      final targets = c.read(linkedControllerTargetsProvider);
      expect(targets.single.ip, '192.0.2.50');
      expect(targets.single.controllerId, isNull);
    });

    test('nothing registered and nothing selected → nothing to target',
        () async {
      final c = await _container(controllers: []);
      expect(c.read(linkedControllerTargetsProvider), isEmpty);
    });

    test('matches what the Home power circle used to target', () async {
      for (final linked in [<String>{}, {'back'}, {'gone'}]) {
        final c = await _container(
          controllers: [_front, _back, _noAddress],
          linked: linked,
        );
        expect(
          c.read(linkedControllerTargetsProvider).map((t) => t.ip).toList(),
          c.read(activeAreaControllerIpsProvider),
          reason: 'linked=$linked',
        );
      }
    });
  });

  group('forEachLinkedController', () {
    test('reaches every linked controller through its own repository',
        () async {
      final front = RecordingWledRepository();
      final back = RecordingWledRepository();
      final c = await _container(
        controllers: [_front, _back],
        selectedIp: _front.ip,
        repos: {_front.ip: front, _back.ip: back},
      );

      final outcomes = await forEachLinkedController(
          c.read, (repo, _) => repo.setState(on: false));

      expect(outcomes.map((o) => o.target.controllerId), ['front', 'back']);
      expect(outcomes.every((o) => o.result.ok), isTrue);
      expect(front.setStates, [
        {'on': false}
      ]);
      expect(back.setStates, [
        {'on': false}
      ]);
    });

    test('includeSelected:false leaves the selected controller to the notifier',
        () async {
      final front = RecordingWledRepository();
      final back = RecordingWledRepository();
      final c = await _container(
        controllers: [_front, _back],
        selectedIp: _front.ip,
        repos: {_front.ip: front, _back.ip: back},
      );

      final outcomes = await forEachLinkedController(
        c.read,
        (repo, _) => repo.setState(on: true),
        includeSelected: false,
      );

      expect(outcomes.map((o) => o.target.controllerId), ['back']);
      expect(front.writeCount, 0);
      expect(back.setStates, hasLength(1));
    });

    test('ONE controller: the fan-out beyond the selected one is empty',
        () async {
      final front = RecordingWledRepository();
      final c = await _container(
        controllers: [_front],
        selectedIp: _front.ip,
        repos: {_front.ip: front},
      );

      final outcomes = await forEachLinkedController(
        c.read,
        (repo, _) => repo.setState(on: true),
        includeSelected: false,
      );

      expect(outcomes, isEmpty);
      expect(front.writeCount, 0);
      expect(summarizeFanOut(outcomes).ok, isTrue);
    });

    test('one controller failing does not stop the others, and is reported',
        () async {
      final back = RecordingWledRepository(succeed: false);
      final shed = RecordingWledRepository();
      final c = await _container(
        controllers: [_front, _back, _shed],
        selectedIp: _front.ip,
        repos: {_back.ip: back, _shed.ip: shed},
      );

      final outcomes = await forEachLinkedController(
        c.read,
        (repo, _) => repo.setState(on: true),
        includeSelected: false,
      );

      expect(outcomes.map((o) => o.result.ok), [false, true]);
      expect(shed.setStates, hasLength(1));
      final summary = summarizeFanOut(outcomes);
      expect(summary.ok, isFalse);
      expect(summary.message, contains('1 of your other 2'));
    });

    test('a controller that throws is a failure, not an unhandled error',
        () async {
      final back = RecordingWledRepository(throwOnWrite: true);
      final c = await _container(
        controllers: [_front, _back],
        selectedIp: _front.ip,
        repos: {_back.ip: back},
      );

      final outcomes = await forEachLinkedController(
        c.read,
        (repo, _) => repo.setState(on: true),
        includeSelected: false,
      );

      expect(outcomes.single.result.failure, WriteFailureKind.error);
    });

    test('a controller that cannot be routed is reported, not skipped',
        () async {
      final c = await _container(
        controllers: [_front, _back],
        selectedIp: _front.ip,
        repos: {_back.ip: null},
      );

      final outcomes = await forEachLinkedController(
        c.read,
        (repo, _) => repo.setState(on: true),
        includeSelected: false,
      );

      expect(outcomes.single.result.failure, WriteFailureKind.blocked);
      expect(summarizeFanOut(outcomes).ok, isFalse);
    });
  });

  test('the Home power circle no longer builds its own per-address requests',
      () {
    // Source guard: the raw fan-out must not quietly come back.
    final source =
        File('lib/features/dashboard/wled_dashboard_page.dart').readAsStringSync();
    expect(source.contains("WledService('http://"), isFalse);
    expect(source.contains('forEachLinkedController'), isTrue);
  });
}
