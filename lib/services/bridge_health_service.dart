import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Startup check that verifies the ESP32 bridge is actively polling
/// Firestore for commands. Re-run on app resume to catch connectivity changes.
///
/// Writes a lightweight 'ping' document to the user's commands collection
/// and watches for the bridge to acknowledge it by changing the `status`
/// field away from `'pending'`.
///
/// RELAY ELIGIBILITY (2026-09-30). The ping is a relay command. When the
/// account has no `bridge_registry` row paired to it there is nothing to pick
/// the ping up, so [check] writes nothing and answers [BridgeHealth.notPaired].
/// The caller decides pairing (`hasPairedBridge`) from the registry, never
/// from `users/{uid}.bridge_paired`, which goes stale. The pairing wizard's
/// own verification ping does NOT go through here — see
/// `pairing_ping.dart` for why it is exempt.
///
/// TODO(firmware): The ESP32 bridge should write a continuous heartbeat
/// document to `/users/{uid}/bridge_status` every 30 seconds containing
/// `{ "lastSeen": <server timestamp>, "ip": "<local IP>" }`.
/// This would allow the app to verify bridge liveness without sending a
/// ping command, and enable a passive "last seen X seconds ago" indicator.
/// Until this is implemented, the app relies on explicit ping round-trips.
class BridgeHealthService {
  BridgeHealthService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Timeout before declaring the bridge unreachable.
  static const _timeout = Duration(seconds: 15);

  /// The fixed document id of the launch/resume ping. One per account; the
  /// write is a `set`, so a re-check replaces the previous ping.
  static const pingDocId = 'bridge_health_check';

  /// Runs the health check and returns the result.
  ///
  /// [userId] — authenticated Firebase UID.
  /// [controllerIp] — IP of the target controller (written into the doc so
  ///   the bridge knows which device is being pinged).
  /// [hasPairedBridge] — the registry's answer. False means "do not write":
  ///   the result is [BridgeHealth.notPaired] and Firestore is not touched.
  Future<BridgeHealth> check({
    required String userId,
    required String controllerIp,
    required bool hasPairedBridge,
  }) async {
    if (!hasPairedBridge) {
      debugPrint('BridgeHealth: no bridge paired to this account — ping '
          'skipped (nothing would pick it up)');
      return BridgeHealth.notPaired;
    }

    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('commands')
        .doc(pingDocId);

    // Write the ping document.
    await docRef.set({
      'type': 'ping',
      'controllerIp': controllerIp,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final sw = Stopwatch()..start();
    debugPrint('BridgeHealth: ping written → docId=$pingDocId, '
        'controllerIp=$controllerIp');

    // Watch for the bridge to update the status field.
    final completer = Completer<BridgeHealth>();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;

    sub = docRef.snapshots().listen((snap) {
      final status = snap.data()?['status'];
      if (status != null && status != 'pending') {
        final elapsed = sw.elapsedMilliseconds;
        sw.stop();
        debugPrint('BridgeHealth: ESP32 is ALIVE — responded in ${elapsed}ms');
        sub?.cancel();
        if (!completer.isCompleted) completer.complete(BridgeHealth.alive);
      }
    }, onError: (e) {
      debugPrint('BridgeHealth: snapshot listener error → $e');
      if (!completer.isCompleted) completer.complete(BridgeHealth.unreachable);
    });

    // Timeout fallback.
    Future.delayed(_timeout, () {
      if (!completer.isCompleted) {
        sw.stop();
        debugPrint('BridgeHealth: ESP32 is NOT POLLING — bridge may be offline');
        sub?.cancel();
        completer.complete(BridgeHealth.unreachable);
      }
    });

    return completer.future;
  }
}

/// Result of the one-time bridge health check.
enum BridgeHealth {
  /// Check is in progress.
  checking,

  /// ESP32 bridge acknowledged the ping.
  alive,

  /// Bridge did not respond within the timeout window.
  unreachable,

  /// No bridge is paired to this account; no ping was written.
  notPaired,
}
