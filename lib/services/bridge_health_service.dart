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
/// TODO(firmware): The ESP32 bridge should write a continuous heartbeat
/// document to `/users/{uid}/bridge_status` every 30 seconds containing
/// `{ "lastSeen": <server timestamp>, "ip": "<local IP>" }`.
/// This would allow the app to verify bridge liveness without sending a
/// ping command, and enable a passive "last seen X seconds ago" indicator.
/// Until this is implemented, the app relies on explicit ping round-trips.
class BridgeHealthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Timeout before declaring the bridge unreachable.
  static const _timeout = Duration(seconds: 15);

  /// Runs the health check and returns the result.
  ///
  /// [userId] — authenticated Firebase UID.
  /// [controllerIp] — IP of the target controller (written into the doc so
  ///   the bridge knows which device is being pinged).
  Future<BridgeHealth> check({
    required String userId,
    required String controllerIp,
  }) async {
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('commands')
        .doc('bridge_health_check');

    // Write the ping document.
    await docRef.set({
      'type': 'ping',
      'controllerIp': controllerIp,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final sw = Stopwatch()..start();
    debugPrint('BridgeHealth: ping written → docId=bridge_health_check, '
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
}
