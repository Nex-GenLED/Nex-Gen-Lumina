// Relay eligibility (2026-09-30): `failed` and `expired` are terminal
// failures on the wire, so the relay's watchdog resolves on them and its
// reconcile never overwrites a server-written verdict with `timeout`.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/models/remote_command.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('parseCommandStatus', () {
    test('every wire status maps to its own value', () {
      expect(RemoteCommand.parseCommandStatus('pending'), CommandStatus.pending);
      expect(RemoteCommand.parseCommandStatus('executing'),
          CommandStatus.executing);
      expect(RemoteCommand.parseCommandStatus('completed'),
          CommandStatus.completed);
      expect(RemoteCommand.parseCommandStatus('failed'), CommandStatus.failed);
      expect(RemoteCommand.parseCommandStatus('timeout'), CommandStatus.timeout);
      expect(RemoteCommand.parseCommandStatus('expired'), CommandStatus.expired);
    });

    test('an unknown status still reads as pending (watchdog backstop)', () {
      expect(RemoteCommand.parseCommandStatus('bogus'), CommandStatus.pending);
      expect(RemoteCommand.parseCommandStatus(null), CommandStatus.pending);
    });

    test('failed and expired are terminal; pending and executing are not',
        () async {
      final fs = FakeFirebaseFirestore();
      Future<RemoteCommand> cmd(String status) async {
        final ref = await fs.collection('c').add({'status': status});
        return RemoteCommand.fromFirestore(await ref.get());
      }

      expect((await cmd('failed')).isComplete, isTrue);
      expect((await cmd('expired')).isComplete, isTrue);
      expect((await cmd('expired')).isSuccess, isFalse);
      expect((await cmd('timeout')).isComplete, isTrue);
      expect((await cmd('completed')).isComplete, isTrue);
      expect((await cmd('pending')).isComplete, isFalse);
      expect((await cmd('executing')).isComplete, isFalse);
      expect((await cmd('executing')).isPending, isTrue);
    });
  });

  group('CloudRelayRepository honours server-written terminal statuses', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      RoutingDiagnostics.resetForTest();
    });

    CloudRelayRepository repo(FakeFirebaseFirestore fs) => CloudRelayRepository(
          userId: 'u1',
          controllerId: 'c1',
          controllerIp: '192.0.2.32',
          webhookUrl: '',
          firestore: fs,
          commandTimeout: const Duration(milliseconds: 150),
        );

    Future<Map<String, dynamic>> only(FakeFirebaseFirestore fs) async {
      final snap =
          await fs.collection('users').doc('u1').collection('commands').get();
      expect(snap.docs, hasLength(1));
      return snap.docs.single.data();
    }

    // testWidgets runs the body on fake time: the repository's watchdog Timer
    // (commandTimeout, 150 ms here) can fire only when the test pumps time
    // forward. So a getState() that has resolved while no time has passed was
    // resolved by the server's failed status, never by the watchdog. Until
    // 2026-11-17 this test bounded a real Stopwatch at 150 ms instead; on a
    // loaded build Mac (Codemagic #366) it measured exactly 150 and failed a
    // run whose status arrived at 3 ms and whose result was right.
    testWidgets(
        'a server fail-fast (failed/no_bridge_paired) resolves at once as a '
        'failure and is not relabelled timeout', (tester) async {
      // The repository's own verdict lines: on a terminal status it logs
      // "send result=failed, error=<reason>"; every watchdog path ends in
      // "genuine timeout" or "post-watchdog reconcile".
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        final fs = FakeFirebaseFirestore();
        final r = repo(fs);
        final commands =
            fs.collection('users').doc('u1').collection('commands');
        // Play the Cloud Function: the moment a doc appears, fail it.
        final sub = commands.snapshots().listen((snap) async {
          for (final change in snap.docChanges) {
            if (change.doc.data()?['status'] == 'pending') {
              await change.doc.reference.update({
                'status': 'failed',
                'error': 'no_bridge_paired',
              });
            }
          }
        });
        addTearDown(sub.cancel);

        var resolved = false;
        Map<String, dynamic>? state;
        final pending = r.getState().then((s) {
          state = s;
          resolved = true;
        });
        // Run every pending microtask without moving the clock.
        await tester.pump();
        expect(resolved, isTrue,
            reason: 'resolved by the failed status, not by the watchdog: no '
                'time has passed, so the watchdog cannot have fired');
        await pending;
        expect(state, isNull);
        expect(logs,
            anyElement(contains('send result=failed, error=no_bridge_paired')),
            reason: 'the repository resolved on the server status and reason');
        final doc = await only(fs);
        expect(doc['status'], 'failed');
        expect(doc['error'], 'no_bridge_paired');

        // Past the watchdog's deadline: resolving cancelled it, so nothing
        // reconciles and nothing relabels the doc timeout.
        await tester.pump(const Duration(milliseconds: 300));
        expect(
            logs,
            everyElement(isNot(anyOf(
                contains('genuine timeout'), contains('post-watchdog')))));
        final after = await only(fs);
        expect(after['status'], 'failed');
        expect(after['error'], 'no_bridge_paired');
      } finally {
        debugPrint = originalDebugPrint;
      }
    });

    test('a sweeper expiry seen by the watchdog reconcile is kept as expired',
        () async {
      final fs = FakeFirebaseFirestore();
      final r = repo(fs);
      final commands =
          fs.collection('users').doc('u1').collection('commands');
      final sub = commands.snapshots().listen((snap) async {
        for (final change in snap.docChanges) {
          if (change.doc.data()?['status'] == 'pending') {
            await change.doc.reference.update({'status': 'expired'});
          }
        }
      });
      addTearDown(sub.cancel);

      expect(await r.getState(), isNull);
      final doc = await only(fs);
      expect(doc['status'], 'expired',
          reason: 'before 2026-09-30 expired parsed as pending and the '
              'reconcile transaction overwrote it with timeout');
    });

    test('a genuinely unanswered command is still stamped timeout', () async {
      final fs = FakeFirebaseFirestore();
      expect(await repo(fs).getState(), isNull);
      final doc = await only(fs);
      expect(doc['status'], 'timeout');
    });
  });
}
