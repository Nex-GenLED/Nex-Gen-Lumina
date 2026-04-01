import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:nexgen_command/app_providers.dart';

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
/// Queries for `_lumina._tcp.local` service records, then falls back to
/// direct hostname lookups for `lumina-*.local`.
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

    final List<BridgeEndpoint> results = [];
    final client = MDnsClient();

    try {
      await client.start();

      // Query _lumina._tcp.local PTR → SRV → A records
      await for (final ptr in client
          .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(_service))
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))) {
            results.add(BridgeEndpoint(
              name: ptr.domainName,
              address: ip.address,
              port: srv.port,
            ));
          }
        }
      }

      // Also try _http._tcp.local and filter for lumina
      if (results.isEmpty) {
        await for (final ptr in client
            .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer('_http._tcp.local'))
            .timeout(const Duration(seconds: 4),
                onTimeout: (sink) => sink.close())) {
          if (ptr.domainName.toLowerCase().contains('lumina')) {
            await for (final srv in client.lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(ptr.domainName))) {
              await for (final ip in client.lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(srv.target))) {
                results.add(BridgeEndpoint(
                  name: ptr.domainName,
                  address: ip.address,
                  port: srv.port,
                ));
              }
            }
          }
        }
      }

      // Fallback: direct hostname lookup
      if (results.isEmpty) {
        for (final host in const [
          'lumina.local',
        ]) {
          try {
            final ips = await InternetAddress.lookup(host);
            for (final ip in ips) {
              results.add(BridgeEndpoint(name: host, address: ip));
            }
          } catch (e) {
            debugPrint('[BridgeDiscovery] Host lookup failed for $host: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[BridgeDiscovery] mDNS error: $e');
    } finally {
      try {
        client.stop();
      } catch (_) {}
    }

    // Deduplicate by IP
    final seen = <String>{};
    final deduped = <BridgeEndpoint>[];
    for (final b in results) {
      final key = b.address.address;
      if (!seen.contains(key)) {
        seen.add(key);
        deduped.add(b);
      }
    }
    return deduped;
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
