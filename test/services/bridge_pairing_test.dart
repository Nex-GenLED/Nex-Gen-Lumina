// Relay eligibility (2026-09-30): the registry predicate and the freshness
// wording, kept apart.
//
//   • hasPairedBridge = a bridge_registry row with pairedUid == uid EXISTS.
//     lastSeen is not consulted — a paired bridge that is silent for a month
//     is still "paired".
//   • bridgeFreshness / relayUnreachableMessage choose WORDS only.
//   • An empty from-cache snapshot is "unknown", never "none".
//   • The user-doc flags (bridge_paired / bridge_ip) are never read.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/services/bridge_pairing.dart';

class _FakeUser extends Fake implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
}

Future<ProviderContainer> _container(FakeFirebaseFirestore fs, {String? uid}) async {
  final c = ProviderContainer(overrides: [
    bridgeRegistryFirestoreProvider.overrideWithValue(fs),
    authStateProvider.overrideWith(
        (ref) => Stream<User?>.value(uid == null ? null : _FakeUser(uid))),
  ]);
  addTearDown(c.dispose);
  await c.read(authStateProvider.future);
  return c;
}

void main() {
  final aMonthAgo = DateTime.utc(2026, 8, 30, 12);
  final now = DateTime.utc(2026, 9, 30, 12);

  group('reducePairedBridgeSnapshot (pure)', () {
    test('no rows from the server → none', () {
      final r = reducePairedBridgeSnapshot(rows: [], ids: [], fromCache: false);
      expect(r.state, PairedBridgeState.none);
      expect(r.bridge, isNull);
    });

    test('no rows from a cold cache → unknown, never none', () {
      final r = reducePairedBridgeSnapshot(rows: [], ids: [], fromCache: true);
      expect(r.state, PairedBridgeState.unknown,
          reason: 'an unseen query answers empty-from-cache before the server '
              'has been asked; that must not read as "no bridge"');
    });

    test('a paired row with a stale lastSeen is still paired', () {
      final r = reducePairedBridgeSnapshot(
        rows: [
          {'status': 'paired', 'lastSeen': Timestamp.fromDate(aMonthAgo)},
        ],
        ids: ['AA00000000A1'],
        fromCache: false,
      );
      expect(r.state, PairedBridgeState.paired);
      expect(r.bridge!.deviceId, 'AA00000000A1');
      // Timestamp.toDate() is local time; compare instants, not zones.
      expect(r.bridge!.lastSeen!.isAtSameMomentAs(aMonthAgo), isTrue);
    });

    test('a paired row that never heartbeated is still paired', () {
      final r = reducePairedBridgeSnapshot(
        rows: [
          {'status': 'paired'},
        ],
        ids: ['X'],
        fromCache: false,
      );
      expect(r.state, PairedBridgeState.paired);
      expect(r.bridge!.lastSeen, isNull);
    });

    test('a cached (non-empty) answer counts', () {
      final r = reducePairedBridgeSnapshot(
        rows: [
          {'status': 'paired'},
        ],
        ids: ['X'],
        fromCache: true,
      );
      expect(r.state, PairedBridgeState.paired);
    });

    test('two paired rows → the freshest heartbeat wins (replaced-bridge shape)',
        () {
      final r = reducePairedBridgeSnapshot(
        rows: [
          {'status': 'paired', 'lastSeen': Timestamp.fromDate(aMonthAgo)},
          {'status': 'paired', 'lastSeen': Timestamp.fromDate(now)},
          {'status': 'paired'},
        ],
        ids: ['OLD', 'LIVE', 'NEVER'],
        fromCache: false,
      );
      expect(r.state, PairedBridgeState.paired);
      expect(r.bridge!.deviceId, 'LIVE');
    });
  });

  group('pairedBridgeProvider (registry query)', () {
    test('signed out → none, no query', () async {
      final c = await _container(FakeFirebaseFirestore());
      final lookup = await c.read(pairedBridgeProvider.future);
      expect(lookup.state, PairedBridgeState.none);
    });

    test('no registry row for this uid → none', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('bridge_registry').doc('OTHER').set({
        'pairedUid': 'someone-else',
        'status': 'paired',
      });
      final c = await _container(fs, uid: 'u1');
      final lookup = await c.read(pairedBridgeProvider.future);
      expect(lookup.state, PairedBridgeState.none);
      expect(c.read(hasPairedBridgeProvider), isFalse);
      expect(c.read(pairedBridgeStateProvider), PairedBridgeState.none);
    });

    test('a row with pairedUid == uid → paired, whatever lastSeen says',
        () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('bridge_registry').doc('AA00000000B2').set({
        'pairedUid': 'u1',
        'status': 'paired',
        'ip': '192.0.2.199',
        'lastSeen': Timestamp.fromDate(aMonthAgo),
      });
      final c = await _container(fs, uid: 'u1');
      final lookup = await c.read(pairedBridgeProvider.future);
      expect(lookup.state, PairedBridgeState.paired);
      expect(c.read(hasPairedBridgeProvider), isTrue);
      expect(c.read(pairedBridgeInfoProvider)!.deviceId, 'AA00000000B2');
      expect(c.read(pairedBridgeInfoProvider)!.ip, '192.0.2.199');
    });

    test('the user doc flags are never consulted (stale bridge_paired shape)', () async {
      final fs = FakeFirebaseFirestore();
      // bridge_paired:true, bridge_ip set — and NO registry row.
      await fs.collection('users').doc('u1').set({
        'bridge_paired': true,
        'bridge_ip': '192.0.2.43',
        'bridge_email': 'bridge@example.com',
      });
      final c = await _container(fs, uid: 'u1');
      final lookup = await c.read(pairedBridgeProvider.future);
      expect(lookup.state, PairedBridgeState.none,
          reason: 'the registry row is the identity the bridge re-asserts; '
              'the user-doc copy went stale on 2026-09-18');
    });

    test('a pairing that lands while listening flips none → paired', () async {
      final fs = FakeFirebaseFirestore();
      final c = await _container(fs, uid: 'u1');
      expect((await c.read(pairedBridgeProvider.future)).state,
          PairedBridgeState.none);

      final seen = <PairedBridgeState>[];
      final sub = c.listen<AsyncValue<PairedBridgeLookup>>(
        pairedBridgeProvider,
        (_, next) => next.whenData((l) => seen.add(l.state)),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await fs.collection('bridge_registry').doc('NEW').set({
        'pairedUid': 'u1',
        'status': 'paired',
      });
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, PairedBridgeState.paired);
      expect(c.read(hasPairedBridgeProvider), isTrue);
    });

    test('loading gap reads as unknown, not none', () {
      final c = ProviderContainer(overrides: [
        pairedBridgeProvider
            .overrideWith((ref) => const Stream<PairedBridgeLookup>.empty()),
      ]);
      addTearDown(c.dispose);
      expect(c.read(pairedBridgeStateProvider), PairedBridgeState.unknown);
      expect(c.read(hasPairedBridgeProvider), isNull);
    });
  });

  group('freshness chooses words only', () {
    const fallback = "Couldn't reach your lights — check your connection";

    test('no bridge / never heartbeated → fallback', () {
      expect(bridgeFreshness(null), isNull);
      expect(
        relayUnreachableMessage(bridge: null, fallback: fallback),
        fallback,
      );
      const never = PairedBridge(
          deviceId: 'X', status: 'paired', lastSeen: null, ip: null);
      expect(
        relayUnreachableMessage(bridge: never, fallback: fallback),
        fallback,
      );
    });

    test('recent heartbeat → fallback', () {
      final fresh = PairedBridge(
        deviceId: 'X',
        status: 'paired',
        lastSeen: now.subtract(const Duration(minutes: 2)),
        ip: null,
      );
      expect(bridgeFreshness(fresh, now: now), const Duration(minutes: 2));
      expect(
        relayUnreachableMessage(bridge: fresh, fallback: fallback, now: now),
        fallback,
      );
    });

    test('silent for kBridgeStaleAfter or longer → names the bridge', () {
      final stale = PairedBridge(
        deviceId: 'X',
        status: 'paired',
        lastSeen: now.subtract(const Duration(hours: 3)),
        ip: null,
      );
      final msg =
          relayUnreachableMessage(bridge: stale, fallback: fallback, now: now);
      expect(msg, contains('Lumina Bridge'));
      expect(msg, contains('3 hours'));
      expect(msg, isNot(contains('192.')));
    });

    test('describeAge picks the coarsest unit that is at least 1', () {
      expect(describeAge(const Duration(seconds: 20)), '1 minute');
      expect(describeAge(const Duration(minutes: 11)), '11 minutes');
      expect(describeAge(const Duration(hours: 1, minutes: 59)), '1 hour');
      expect(describeAge(const Duration(days: 22, hours: 5)), '22 days');
    });
  });
}
