import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/services/bridge_api_client.dart';

/// A Lumina Bridge discovered via mDNS.
class BridgeEndpoint {
  final String name;
  final InternetAddress address;
  final int port;

  const BridgeEndpoint({
    required this.name,
    required this.address,
    this.port = 80,
  });
}

/// Discovers Lumina Bridge devices on the local network via mDNS.
///
/// Only `_lumina._tcp.local` records are accepted, and each candidate
/// is verified with an `/api/info` probe that must report
/// `type == "bridge"`. Earlier loose fallbacks (`_http._tcp.local`
/// substring filter and a `lumina.local` hostname lookup) were removed
/// because they could match a WLED controller — leaking the controller's
/// IP into the bridge IP slot.
class BridgeDiscoveryService {
  static const _service = '_lumina._tcp.local';

  Future<List<BridgeEndpoint>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Simulation mode: return a mock bridge.
    if (kSimulationMode) {
      return [
        BridgeEndpoint(
          name: 'Lumina-MOCK',
          address: InternetAddress.loopbackIPv4,
        ),
      ];
    }

    final List<BridgeEndpoint> candidates = [];
    final client = MDnsClient();

    try {
      await client.start();

      // Query _lumina._tcp.local PTR → SRV → A records.
      await for (final ptr in client
          .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(_service))
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))) {
            candidates.add(BridgeEndpoint(
              name: ptr.domainName,
              address: ip.address,
              port: srv.port,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[BridgeDiscovery] mDNS error: $e');
    } finally {
      try {
        client.stop();
      } catch (e) {
        debugPrint('Error in BridgeDiscovery stopping mDNS client: $e');
      }
    }

    // Deduplicate candidates by IP before probing — avoids hitting the
    // same device twice when SRV/A records double-resolve.
    final seen = <String>{};
    final deduped = <BridgeEndpoint>[];
    for (final b in candidates) {
      final key = b.address.address;
      if (!seen.contains(key)) {
        seen.add(key);
        deduped.add(b);
      }
    }

    // Verify each candidate with /api/info. Only bridges whose firmware
    // self-reports type=="bridge" are returned. Probes run in parallel
    // so discovery latency is bounded by the single slowest probe, not
    // the sum.
    final verified = await Future.wait(deduped.map((b) async {
      try {
        final probe = BridgeApiClient.fromIp(b.address.address, port: b.port);
        final info = await probe.getInfo();
        if (info != null && info.type == 'bridge') {
          return b;
        }
        debugPrint(
            '[BridgeDiscovery] Rejected ${b.address.address}: not a bridge '
            '(type="${info?.type ?? "?"}")');
      } catch (e) {
        debugPrint(
            '[BridgeDiscovery] Probe failed for ${b.address.address}: $e');
      }
      return null;
    }));

    return verified.whereType<BridgeEndpoint>().toList();
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
