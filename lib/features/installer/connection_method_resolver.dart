import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/connection_method.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// Pure detection: derive a [ConnectionMethod] from a parsed /json/info
/// response, using the audit §9 heuristics (no `connected: true` flag —
/// WLED does not emit one). Returns `unknown` when [info] is null or
/// neither interface reports as active.
///
/// Heuristics:
///   WiFi active     : info['wifi'] is Map AND (signal != 0 OR rssi < 0
///                     OR bssid non-empty)
///   Ethernet active : info['ethernet'] is truthy/non-empty Map/non-zero num
ConnectionMethod detectConnectionMethod(WledInfoResponse? info) {
  if (info == null) return ConnectionMethod.unknown;
  final ethRaw = info.raw['ethernet'];
  final hasEthernet = ethRaw == true ||
      (ethRaw is Map && ethRaw.isNotEmpty) ||
      (ethRaw is num && ethRaw != 0);
  final wifiRaw = info.raw['wifi'];
  bool hasWifi = false;
  if (wifiRaw is Map) {
    final signal = wifiRaw['signal'];
    final rssi = wifiRaw['rssi'];
    final bssid = wifiRaw['bssid'];
    hasWifi = (signal is num && signal != 0) ||
        (rssi is num && rssi < 0) ||
        (bssid is String && bssid.isNotEmpty);
  }
  if (hasEthernet && hasWifi) return ConnectionMethod.ethernetWifiActive;
  if (hasEthernet) return ConnectionMethod.ethernet;
  if (hasWifi) return ConnectionMethod.wifi;
  return ConnectionMethod.unknown;
}

/// Service contract for the connection-method screen — wraps the HTTP and
/// Firestore side effects so widget tests can supply a fake.
abstract class ConnectionMethodResolver {
  /// Probes [controller] via /json/info and returns the detected method.
  /// Null result on unreachable controller maps to [ConnectionMethod.unknown].
  Future<ConnectionMethod> probe(ControllerInfo controller);

  /// Like [probe] but distinguishes "unreachable" from "unknown state":
  /// returns null when /json/info doesn't respond, otherwise the detected
  /// [ConnectionMethod] (which may still be `unknown` if both interfaces
  /// read as inactive). Used by the handoff verification sweep so the
  /// UI can render an "offline" failure separately from "unverified."
  Future<ConnectionMethod?> probeOrNull(ControllerInfo controller);

  /// Read-only clock-health probe for [controller] (BUG-CLOCK-1). Returns null
  /// when unreachable or the fields can't be read. Advisory only — the handoff
  /// surfaces this as a warn line, never a fail, so it can't block the install.
  Future<ClockHealth?> probeClockOrNull(ControllerInfo controller);

  /// Clears WiFi credentials and reboots [controller]. Returns true on the
  /// /json/cfg 2xx response; the actual ethernet-only confirmation is the
  /// caller's job (post-reboot re-poll).
  Future<bool> disableWifi(ControllerInfo controller);

  /// Waits for the controller at [controller.ip] to stop responding within
  /// [pollWindow]. Used after instructing the installer to unplug the
  /// Ethernet cable — the IP they had on Ethernet should go silent.
  Future<bool> waitForOffline(
    ControllerInfo controller, {
    Duration pollWindow = const Duration(seconds: 10),
  });

  /// Pings the controller and returns true if /json/state responds. Used
  /// to confirm a controller is still reachable on its WiFi IP after the
  /// installer unplugs the Ethernet cable, OR back on its Ethernet IP
  /// after a WiFi-disable reboot.
  Future<bool> isReachable(ControllerInfo controller);

  /// Persists the resolved method to /users/{uid}/controllers/{cid}.
  Future<void> persist(ControllerInfo controller, ConnectionMethod method);
}

/// Production implementation. Uses a fresh [WledService] per controller IP
/// and writes Firestore directly. Tests substitute a fake by overriding
/// [connectionMethodResolverProvider].
class FirebaseConnectionMethodResolver implements ConnectionMethodResolver {
  FirebaseConnectionMethodResolver({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    WledService Function(String baseUrl)? wledServiceFactory,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _wledFactory = wledServiceFactory ?? WledService.new;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final WledService Function(String baseUrl) _wledFactory;

  WledService _service(ControllerInfo c) => _wledFactory('http://${c.ip}');

  @override
  Future<ConnectionMethod> probe(ControllerInfo controller) async {
    final info = await _service(controller).getInfo().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
    return detectConnectionMethod(info);
  }

  @override
  Future<ConnectionMethod?> probeOrNull(ControllerInfo controller) async {
    final info = await _service(controller).getInfo().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
    if (info == null) return null;
    return detectConnectionMethod(info);
  }

  @override
  Future<ClockHealth?> probeClockOrNull(ControllerInfo controller) async {
    final clockInfo = await _service(controller).fetchClockInfo().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
    if (clockInfo == null) return null;
    final now = DateTime.now();
    return evaluateClockHealth(
      device: clockInfo,
      phoneNow: now,
      phoneUtcOffset: now.timeZoneOffset,
    );
  }

  @override
  Future<bool> disableWifi(ControllerInfo controller) {
    return _service(controller).clearWifiCredentials(reboot: true);
  }

  @override
  Future<bool> waitForOffline(
    ControllerInfo controller, {
    Duration pollWindow = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(pollWindow);
    while (DateTime.now().isBefore(deadline)) {
      final state = await _service(controller).getState().timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
      if (state == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  @override
  Future<bool> isReachable(ControllerInfo controller) async {
    final state = await _service(controller).getState().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
    return state != null;
  }

  @override
  Future<void> persist(
    ControllerInfo controller,
    ConnectionMethod method,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('ConnectionMethodResolver.persist: no auth uid, skipping');
      return;
    }
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('controllers')
        .doc(controller.id)
        .set(
      {
        'connectionMethod': connectionMethodToJson(method),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

/// Riverpod entry point. Override in tests with a fake [ConnectionMethodResolver].
final connectionMethodResolverProvider =
    Provider<ConnectionMethodResolver>((ref) {
  return FirebaseConnectionMethodResolver();
});
