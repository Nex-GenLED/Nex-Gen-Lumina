import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';

/// A Lumina Bridge discovered via Firestore self-registration.
///
/// Pre-self-registration the app discovered bridges via mDNS and the
/// `address` was the only way to reach the bridge. With self-registration
/// the bridge writes its own document at `/bridge_registry/{deviceId}`,
/// so [deviceId] is the durable identifier and [address] is just an
/// optimization for same-network local commands.
class BridgeEndpoint {
  /// Display name (e.g. "Lumina-54B8"). Sourced from `deviceName` in the
  /// registry doc, or the mDNS PTR name on the legacy path.
  final String name;

  /// Stable per-chip identifier (MAC without colons). Null only on the
  /// legacy mDNS code path; populated for every Firestore-discovered bridge.
  final String? deviceId;

  /// Bridge LAN IP. Used for the optional fast-path local HTTP commands
  /// when the phone is on the same network. Not shown to the user.
  final InternetAddress address;

  final int port;

  /// `unpaired` | `paired` | `pairing`. Used by the wizard to decide
  /// whether to surface "Ready to pair" or "Already paired" to the user.
  final String? status;

  /// UID currently paired to this bridge, if any. Empty string when
  /// unpaired. Used by the wizard's hijack-detection step.
  final String? pairedUid;

  /// Firebase Auth email the bridge signs in with. Persisted to the
  /// user's `bridge_email` field on pair so Firestore rules can grant
  /// the bridge read/write on that user's commands.
  final String? bridgeEmail;

  const BridgeEndpoint({
    required this.name,
    required this.address,
    this.port = 80,
    this.deviceId,
    this.status,
    this.pairedUid,
    this.bridgeEmail,
  });
}

/// Discovers Lumina Bridge devices via Firestore self-registration.
///
/// The bridge writes `/bridge_registry/{deviceId}` on boot (and refreshes
/// every 30s). Discovery filters for unpaired bridges that have been seen
/// recently — the LAN scan / mDNS path that this replaces failed on iOS,
/// required the phone and bridge to be on the same WiFi at the same time,
/// and surfaced raw IPs to non-technical installers.
class BridgeDiscoveryService {
  /// Bridges whose `lastSeen` is older than this are treated as offline
  /// and excluded from discovery results. Matches the bridge's 30 s
  /// heartbeat with headroom for one missed cycle.
  static const _staleThreshold = Duration(minutes: 5);

  Future<List<BridgeEndpoint>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Simulation mode: return a mock bridge so the wizard renders in UI
    // development without Firestore. Mirrors the legacy mDNS simulator.
    if (kSimulationMode) {
      return [
        BridgeEndpoint(
          name: 'Lumina-MOCK',
          deviceId: 'MOCK000000',
          address: InternetAddress.loopbackIPv4,
          status: 'unpaired',
        ),
      ];
    }

    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(_staleThreshold),
    );

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bridge_registry')
          .where('status', isEqualTo: 'unpaired')
          .where('lastSeen', isGreaterThan: cutoff)
          .get()
          .timeout(timeout);

      final results = <BridgeEndpoint>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ip = (data['ip'] as String?) ?? '';
        // Skip docs without a usable IP — the registry write happens
        // before WiFi.localIP() reports, in rare boot orders. The bridge
        // self-corrects on the next heartbeat.
        if (ip.isEmpty) continue;

        InternetAddress? address;
        try {
          address = InternetAddress(ip);
        } catch (_) {
          // Malformed IP — skip rather than throw. The bridge will
          // self-correct on the next heartbeat.
          continue;
        }

        results.add(BridgeEndpoint(
          name: (data['deviceName'] as String?) ?? doc.id,
          deviceId: doc.id,
          address: address,
          status: (data['status'] as String?) ?? 'unpaired',
          pairedUid: (data['pairedUid'] as String?) ?? '',
          bridgeEmail: (data['bridgeEmail'] as String?) ?? '',
        ));
      }
      return results;
    } catch (e) {
      debugPrint('[BridgeDiscovery] Firestore query failed: $e');
      return [];
    }
  }

  /// Look up a single bridge by its `deviceId`. Used by the pairing flow
  /// when polling for the bridge's response to a pairing request.
  Future<BridgeEndpoint?> getById(String deviceId) async {
    if (kSimulationMode) {
      return BridgeEndpoint(
        name: 'Lumina-MOCK',
        deviceId: deviceId,
        address: InternetAddress.loopbackIPv4,
        status: 'paired',
      );
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('bridge_registry')
          .doc(deviceId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      final ip = (data['ip'] as String?) ?? '';
      InternetAddress address;
      try {
        address = InternetAddress(ip);
      } catch (_) {
        // Fall back to a placeholder so the caller can still surface
        // the deviceId/status; same-network fast path won't work.
        address = InternetAddress.loopbackIPv4;
      }
      return BridgeEndpoint(
        name: (data['deviceName'] as String?) ?? doc.id,
        deviceId: doc.id,
        address: address,
        status: (data['status'] as String?) ?? 'unpaired',
        pairedUid: (data['pairedUid'] as String?) ?? '',
        bridgeEmail: (data['bridgeEmail'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[BridgeDiscovery] getById($deviceId) failed: $e');
      return null;
    }
  }
}

/// Riverpod provider for bridge discovery service.
final bridgeDiscoveryServiceProvider =
    Provider<BridgeDiscoveryService>((ref) => BridgeDiscoveryService());

/// Async discovery provider that runs once on watch.
final discoveredBridgesProvider =
    FutureProvider<List<BridgeEndpoint>>((ref) async {
  final service = ref.watch(bridgeDiscoveryServiceProvider);
  return service.discover();
});
