// Relay eligibility (2026-09-30): the launch/resume ping is gated on a paired
// bridge; the pairing wizard's own ping is exempt.
//
//   • BridgeHealthService.check(hasPairedBridge: false) writes NOTHING and
//     answers notPaired.
//   • With a paired bridge it writes the fixed `bridge_health_check` doc as
//     before.
//   • writePairingPing writes whatever the registry says — it is the write
//     that proves a just-paired bridge.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/bridge_health_service.dart';
import 'package:nexgen_command/services/pairing_ping.dart';

void main() {
  Future<List<Map<String, dynamic>>> commands(
      FakeFirebaseFirestore fs, String uid) async {
    final snap =
        await fs.collection('users').doc(uid).collection('commands').get();
    return snap.docs.map((d) => d.data()).toList();
  }

  test('no paired bridge → no ping document, result notPaired', () async {
    final fs = FakeFirebaseFirestore();
    final health = await BridgeHealthService(firestore: fs).check(
      userId: 'u1',
      controllerIp: '192.0.2.37',
      hasPairedBridge: false,
    );
    expect(health, BridgeHealth.notPaired);
    expect(await commands(fs, 'u1'), isEmpty);
  });

  test('paired bridge → the ping is written under the fixed doc id', () async {
    final fs = FakeFirebaseFirestore();
    // Do not await: nothing answers the ping here, and the 15 s timeout is
    // real time. The write itself is synchronous with the call's first await.
    final pending = BridgeHealthService(firestore: fs).check(
      userId: 'u1',
      controllerIp: '192.0.2.150',
      hasPairedBridge: true,
    );
    await Future<void>.delayed(Duration.zero);
    final doc = await fs
        .collection('users')
        .doc('u1')
        .collection('commands')
        .doc(BridgeHealthService.pingDocId)
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['type'], 'ping');
    expect(doc.data()!['status'], 'pending');
    expect(doc.data()!['controllerIp'], '192.0.2.150');

    // A bridge answering flips the status; the check resolves alive.
    await doc.reference.update({'status': 'completed'});
    expect(await pending, BridgeHealth.alive);
  });

  test('the pairing ping is EXEMPT: written with no registry row at all',
      () async {
    final fs = FakeFirebaseFirestore();
    // Belt and braces: the gated service refuses…
    expect(
      await BridgeHealthService(firestore: fs).check(
        userId: 'u1',
        controllerIp: '',
        hasPairedBridge: false,
      ),
      BridgeHealth.notPaired,
    );
    expect(await commands(fs, 'u1'), isEmpty);

    // …and the wizard's ping still goes out, untargeted.
    final ref = await writePairingPing(fs, 'u1');
    final written = await commands(fs, 'u1');
    expect(written, hasLength(1));
    expect(written.single['type'], 'ping');
    expect(written.single['controllerId'], '');
    expect(written.single['controllerIp'], '');
    expect(written.single['status'], 'pending');
    expect(ref.id, isNot(BridgeHealthService.pingDocId),
        reason: 'the wizard ping is its own auto-id document');
  });

  test('isPairingPing recognises exactly the wizard shape', () {
    expect(isPairingPing({'type': 'ping', 'controllerIp': ''}), isTrue);
    expect(isPairingPing({'type': 'ping'}), isTrue);
    expect(isPairingPing({'type': 'ping', 'controllerIp': '192.0.2.150'}),
        isFalse, reason: 'the launch ping names a controller');
    expect(isPairingPing({'type': 'getState', 'controllerIp': ''}), isFalse);
  });
}
