// Relay eligibility (2026-09-30): the routing matrix.
//
//   local                     → WledService, whatever the registry says
//   remote + paired           → CloudRelayRepository
//   remote + paired + STALE   → CloudRelayRepository (regression: freshness
//                               never blocks routing)
//   remote + unpaired         → null (the apply gate then says "needs a
//                               Lumina Bridge", immediately)
//   remote + unknown          → CloudRelayRepository (fail open, exactly as
//                               before the gate existed)
//   remote + unpaired+webhook → CloudRelayRepository (webhook is a Cloud
//                               Function, not a bridge)
//   demo / reviewer           → DemoWledRepository, untouched
//
// Plus the launch-ping helper: the first known registry answer, with a short
// wait for a cold cache.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/bridge_pairing.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/reviewer_seed_service.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';

class _FakeUser extends Fake implements User {
  _FakeUser({this.uid = 'account', this.email = 'someone@example.com'});
  @override
  final String uid;
  @override
  final String? email;
}

ControllerRoute _route(
  ConnectivityStatus network, {
  PairedBridgeState paired = PairedBridgeState.unknown,
  String? webhookUrl,
}) =>
    ControllerRoute(
      ip: '192.0.2.10',
      controllerId: 'front',
      userId: 'account',
      connectivity: network,
      webhookUrl: webhookUrl,
      pairedBridge: paired,
    );

void main() {
  group('buildRoutedRepository × registry', () {
    test('home network → direct, whatever the registry says', () {
      for (final state in PairedBridgeState.values) {
        expect(
          buildRoutedRepository(_route(ConnectivityStatus.local, paired: state)),
          isA<WledService>(),
          reason: state.name,
        );
      }
    });

    test('away + paired → relay', () {
      final repo = buildRoutedRepository(
        _route(ConnectivityStatus.remote, paired: PairedBridgeState.paired),
        firestore: FakeFirebaseFirestore(),
      );
      expect(repo, isA<CloudRelayRepository>());
    });

    test('away + NO paired bridge → no repository (nothing could pick it up)',
        () {
      expect(
        buildRoutedRepository(
          _route(ConnectivityStatus.remote, paired: PairedBridgeState.none),
          firestore: FakeFirebaseFirestore(),
        ),
        isNull,
      );
    });

    test('away + registry not answered yet → relay, exactly as before', () {
      expect(
        buildRoutedRepository(
          _route(ConnectivityStatus.remote, paired: PairedBridgeState.unknown),
          firestore: FakeFirebaseFirestore(),
        ),
        isA<CloudRelayRepository>(),
      );
    });

    test('ControllerRoute defaults to unknown, so older callers are unchanged',
        () {
      const r = ControllerRoute(
        ip: '192.0.2.10',
        controllerId: 'front',
        userId: 'account',
        connectivity: ConnectivityStatus.remote,
        webhookUrl: null,
      );
      expect(r.pairedBridge, PairedBridgeState.unknown);
    });

    test('away + webhook mode → relay even with no bridge (Cloud Function path)',
        () {
      final repo = buildRoutedRepository(
        _route(
          ConnectivityStatus.remote,
          paired: PairedBridgeState.none,
          webhookUrl: 'https://home.example.duckdns.org:8080',
        ),
        firestore: FakeFirebaseFirestore(),
      );
      expect(repo, isA<CloudRelayRepository>());
      expect((repo as CloudRelayRepository).webhookUrl,
          'https://home.example.duckdns.org:8080');
    });
  });

  group('regression — a paired bridge with a stale lastSeen still relays', () {
    test('the provider chain: month-old heartbeat → paired → relay built',
        () async {
      // pairedBridgeStateProvider is derived from the lookup; lastSeen is not
      // part of the state at all, so it cannot influence the route.
      final stale = PairedBridge(
        deviceId: 'AA00000000A1',
        status: 'paired',
        lastSeen: DateTime.utc(2026, 8, 1),
        ip: '192.0.2.191',
      );
      final c = ProviderContainer(overrides: [
        pairedBridgeProvider.overrideWith((ref) =>
            Stream.value(PairedBridgeLookup(PairedBridgeState.paired, stale))),
      ]);
      addTearDown(c.dispose);
      await c.read(pairedBridgeProvider.future);
      expect(c.read(pairedBridgeStateProvider), PairedBridgeState.paired);
      expect(c.read(hasPairedBridgeProvider), isTrue);
      expect(
        buildRoutedRepository(
          _route(ConnectivityStatus.remote,
              paired: c.read(pairedBridgeStateProvider)),
          firestore: FakeFirebaseFirestore(),
        ),
        isA<CloudRelayRepository>(),
      );
      // Freshness is a messaging input only.
      expect(bridgeFreshness(stale, now: DateTime.utc(2026, 9, 30)),
          greaterThan(const Duration(days: 30)));
    });
  });

  group('wledRepositoryProvider — demo and reviewer stay on the demo path', () {
    ProviderContainer container({
      required bool demo,
      required User? user,
      PairedBridgeState paired = PairedBridgeState.none,
      ConnectivityStatus network = ConnectivityStatus.remote,
    }) {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(user)),
        wledConnectivityStatusProvider
            .overrideWith((ref) => Stream<ConnectivityStatus>.value(network)),
        controllersStreamProvider.overrideWith((ref) => Stream.value([
              ControllerInfo(id: 'front', ip: '192.0.2.10'),
            ])),
        currentUserProfileProvider
            .overrideWith((ref) => Stream<UserModel?>.value(null)),
        pairedBridgeProvider.overrideWith((ref) => Stream.value(
            paired == PairedBridgeState.paired
                ? const PairedBridgeLookup(PairedBridgeState.paired,
                    PairedBridge(
                        deviceId: 'X',
                        status: 'paired',
                        lastSeen: null,
                        ip: null))
                : paired == PairedBridgeState.none
                    ? const PairedBridgeLookup.none()
                    : const PairedBridgeLookup.unknown())),
      ]);
      addTearDown(c.dispose);
      c.read(demoModeProvider.notifier).state = demo;
      c.read(selectedDeviceIpProvider.notifier).state = '192.0.2.10';
      return c;
    }

    Future<void> settle(ProviderContainer c) async {
      await c.read(authStateProvider.future);
      await c.read(wledConnectivityStatusProvider.future);
      await c.read(controllersStreamProvider.future);
      await c.read(currentUserProfileProvider.future);
      await c.read(pairedBridgeProvider.future);
    }

    test('demo mode → DemoWledRepository, registry never consulted', () async {
      final c = container(demo: true, user: _FakeUser());
      await settle(c);
      expect(c.read(wledRepositoryProvider), isA<DemoWledRepository>());
    });

    test('reviewer account → DemoWledRepository, away, no bridge', () async {
      final c = container(
        demo: false,
        user: _FakeUser(uid: 'reviewer', email: ReviewerSeedService.reviewerEmail),
      );
      await settle(c);
      expect(c.read(wledRepositoryProvider), isA<DemoWledRepository>());
    });

    test('a customer away with no bridge → null + the plain-words reason',
        () async {
      final c = container(demo: false, user: _FakeUser());
      await settle(c);
      expect(c.read(wledRepositoryProvider), isNull);
      final reason = c.read(applyBlockedReasonProvider);
      expect(reason?.kind, ApplyBlock.noBridge);
      expect(reason?.message, kNoBridgeAwayMessage);
      expect(reason!.isTransient, isFalse);
    });

    test('a customer at home with no bridge → direct, no reason', () async {
      final c = container(
          demo: false, user: _FakeUser(), network: ConnectivityStatus.local);
      await settle(c);
      expect(c.read(wledRepositoryProvider), isA<WledService>());
    });
  });

  group('firstKnownPairedBridgeState (launch ping helper)', () {
    test('a known initial state is returned at once', () async {
      expect(
        await firstKnownPairedBridgeState(const Stream.empty(),
            initial: PairedBridgeState.none),
        PairedBridgeState.none,
      );
      expect(
        await firstKnownPairedBridgeState(const Stream.empty(),
            initial: PairedBridgeState.paired),
        PairedBridgeState.paired,
      );
    });

    test('unknown waits for the first known answer', () async {
      final ctrl = StreamController<PairedBridgeLookup>();
      final f = firstKnownPairedBridgeState(ctrl.stream,
          initial: PairedBridgeState.unknown);
      ctrl.add(const PairedBridgeLookup.unknown());
      ctrl.add(const PairedBridgeLookup.none());
      expect(await f, PairedBridgeState.none);
      await ctrl.close();
    });

    test('unknown with no answer inside the wait stays unknown (fail open)',
        () async {
      final ctrl = StreamController<PairedBridgeLookup>();
      addTearDown(ctrl.close);
      expect(
        await firstKnownPairedBridgeState(ctrl.stream,
            initial: PairedBridgeState.unknown,
            wait: const Duration(milliseconds: 20)),
        PairedBridgeState.unknown,
      );
    });
  });
}
