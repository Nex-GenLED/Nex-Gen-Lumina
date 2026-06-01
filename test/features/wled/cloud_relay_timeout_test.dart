import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';

/// Tests for the #52 false-timeout fix: command status is derived from
/// presence-of-result, the watchdog never blind-overwrites a populated-result
/// doc to 'timeout', and a genuine no-result command still times out.
void main() {
  const uid = 'u1';

  CollectionReference<Map<String, dynamic>> commandsOf(FakeFirebaseFirestore fs) =>
      fs.collection('users').doc(uid).collection('commands');

  CloudRelayRepository repoWith(FakeFirebaseFirestore fs, {Duration? timeout}) =>
      CloudRelayRepository(
        userId: uid,
        controllerId: 'c1',
        controllerIp: '10.0.0.32',
        webhookUrl: '',
        firestore: fs,
        commandTimeout: timeout ?? const Duration(milliseconds: 400),
      );

  /// Simulated bridge: wait for the pending command doc to appear, then write
  /// back a terminal status (mirrors firmware updateCommandStatus — result is
  /// a JSON *string*, completedAt a server-style timestamp).
  Future<void> bridgeRespond(
    FakeFirebaseFirestore fs, {
    required String status,
    Map<String, dynamic>? result,
  }) async {
    final col = commandsOf(fs);
    for (var i = 0; i < 100; i++) {
      final pending = await col.where('status', isEqualTo: 'pending').get();
      if (pending.docs.isNotEmpty) {
        await col.doc(pending.docs.first.id).update({
          'status': status,
          if (result != null) 'result': jsonEncode(result),
          'completedAt': Timestamp.now(),
        });
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('no pending command doc ever appeared');
  }

  group('result-derived success (listener path)', () {
    test('completed + result → getState returns the result (not null)', () async {
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs, timeout: const Duration(seconds: 5));

      final future = repo.getState();
      await bridgeRespond(fs, status: 'completed', result: {'on': true, 'bri': 200});
      final res = await future;

      expect(res, isNotNull);
      expect(res!['on'], true);
      expect(res['bri'], 200);

      // Doc must NOT have been marked timeout.
      final docs = await commandsOf(fs).get();
      expect(docs.docs.single.data()['status'], 'completed');
    });

    test('success path returns non-null result so the failure counter is not bumped',
        () async {
      // getState() returning non-null is exactly what stops
      // WledNotifier._consecutiveRemoteFailures from incrementing (and thus
      // the false "System Offline" downgrade). Guard the contract here.
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs, timeout: const Duration(seconds: 5));
      final future = repo.getState();
      await bridgeRespond(fs, status: 'completed', result: {'on': false});
      expect(await future, isNotNull);
    });
  });

  group('genuine timeout (no result ever arrives)', () {
    test('no bridge response → returns null AND stamps status:timeout, no result',
        () async {
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs, timeout: const Duration(milliseconds: 250));

      final res = await repo.getState();

      expect(res, isNull);
      final doc = (await commandsOf(fs).get()).docs.single;
      expect(doc.data()['status'], 'timeout');
      expect(doc.data().containsKey('result'), isFalse,
          reason: 'genuine timeout must have no result');
    });

    test('bridge failed (no result) → returns null and doc stays failed, NOT timeout',
        () async {
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs, timeout: const Duration(seconds: 5));

      final future = repo.getState();
      await bridgeRespond(fs, status: 'failed'); // no result
      final res = await future;

      expect(res, isNull);
      final doc = (await commandsOf(fs).get()).docs.single;
      expect(doc.data()['status'], 'failed',
          reason: 'an explicit bridge failure must not be relabeled timeout');
    });
  });

  group('reconcile-after-watchdog (blind-overwrite prevention, #52)', () {
    // These drive the reconcile transaction directly via the test hook,
    // because a working snapshots() listener resolves before the watchdog —
    // the reconcile path only matters when the listener silently died.

    test('result-after-watchdog resolves SUCCESS, never clobbers to timeout',
        () async {
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs);
      // Doc the listener "missed": result already populated, status still pending.
      final ref = await commandsOf(fs).add({
        'type': 'getState',
        'status': 'pending',
        'result': jsonEncode({'on': true, 'bri': 128}),
        'completedAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
      });

      final reconciled = await repo.debugReconcileAfterWatchdog(ref);

      expect(reconciled, isNotNull, reason: 'a populated result means success');
      expect(reconciled!.result?['bri'], 128);
      // The blind overwrite must NOT have happened.
      final after = await ref.get();
      expect(after.data()!['status'], isNot('timeout'));
      expect(after.data()!['status'], 'pending');
    });

    test('status already completed → success, no timeout write', () async {
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs);
      final ref = await commandsOf(fs).add({
        'type': 'getState',
        'status': 'completed',
        'result': jsonEncode({'on': false}),
        'createdAt': Timestamp.now(),
      });

      final reconciled = await repo.debugReconcileAfterWatchdog(ref);

      expect(reconciled, isNotNull);
      expect((await ref.get()).data()!['status'], 'completed');
    });

    test('pending + no result → genuine timeout: reconcile stamps timeout', () async {
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs);
      final ref = await commandsOf(fs).add({
        'type': 'getState',
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });

      final reconciled = await repo.debugReconcileAfterWatchdog(ref);

      expect(reconciled, isNull);
      expect((await ref.get()).data()!['status'], 'timeout');
    });

    test('explicit failed + no result → null, stays failed (no timeout stamp)',
        () async {
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs);
      final ref = await commandsOf(fs).add({
        'type': 'getState',
        'status': 'failed',
        'error': 'ERROR: HTTP -1',
        'createdAt': Timestamp.now(),
      });

      final reconciled = await repo.debugReconcileAfterWatchdog(ref);

      expect(reconciled, isNull);
      expect((await ref.get()).data()!['status'], 'failed');
    });

    test('a late bridge completion still wins on the persisted doc after a timeout',
        () async {
      // Proves we don't permanently lock a doc to timeout: if the bridge
      // writes completed+result after we stamped timeout, the doc self-heals.
      final fs = FakeFirebaseFirestore();
      final repo = repoWith(fs, timeout: const Duration(milliseconds: 200));
      await repo.getState(); // genuine timeout → doc stamped 'timeout'

      final ref = (await commandsOf(fs).get()).docs.single.reference;
      expect((await ref.get()).data()!['status'], 'timeout');

      // Late bridge writeback.
      await ref.update({'status': 'completed', 'result': jsonEncode({'on': true})});
      expect((await ref.get()).data()!['status'], 'completed');
    });
  });
}
