import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:nexgen_command/app_providers.dart';

/// Represents a discovered device endpoint
class DeviceEndpoint {
  final String name;
  final InternetAddress address;
  const DeviceEndpoint({required this.name, required this.address});
}

/// Service for discovering WLED or specific device names via mDNS
class DeviceDiscoveryService {
  static const _service = '_wled._tcp.local';

  Future<List<DeviceEndpoint>> discover({Duration timeout = const Duration(seconds: 10)}) async {
    // Simulation mode: instantly return a virtual device and skip network.
    if (kSimulationMode) {
      return [
        DeviceEndpoint(name: 'Virtual Nex-Gen Home', address: InternetAddress.loopbackIPv4),
      ];
    }

    // Trigger iOS local network permission prompt.
    // iOS silently blocks mDNS until the user grants
    // "Allow to find devices on local network". A brief
    // socket attempt to any local address causes the prompt
    // to appear. Expected to fail — we only need the side effect.
    if (!kSimulationMode) {
      try {
        final sock = await Socket.connect(
          '192.168.50.1',
          80,
          timeout: const Duration(milliseconds: 200),
        );
        sock.destroy();
      } catch (_) {}
    }

    final List<DeviceEndpoint> results = [];
    // Initialize mDNS client with default constructor (rawDatagramFactory removed)
    final client = MDnsClient();
    try {
      await client.start();

      // Query _wled._tcp.local PTR records
      await for (final ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_service)).timeout(timeout, onTimeout: (sink) => sink.close())) {
        await for (final srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))) {
            results.add(DeviceEndpoint(name: ptr.domainName, address: ip.address));
          }
        }
      }

      // Also directly try common hostnames if not found
      if (results.isEmpty) {
        // Try various WLED hostname patterns
        for (final host in const [
          'wled.local',
          'wled-Dig-Octa-ESP32-8L-E.local',
          'nexgen-master.local',
        ]) {
          try {
            final ips = await InternetAddress.lookup(host);
            for (final ip in ips) {
              results.add(DeviceEndpoint(name: host, address: ip));
            }
          } catch (e) {
            debugPrint('Host lookup failed for $host: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('mDNS discovery error: $e');
    } finally {
      try {
        client.stop();
      } catch (e) {
        debugPrint('Error in DeviceDiscovery stopping mDNS client: $e');
      }
    }

    // Subnet scan fallback when mDNS turns up empty. Common on iOS when the
    // user has granted local network permission but mDNS multicast is being
    // dropped by the router or carrier-grade NAT.
    if (results.isEmpty) {
      debugPrint('mDNS returned no results — running subnet scan fallback');
      final subnetResults = await _subnetScan();
      results.addAll(subnetResults);
    }

    // Deduplicate by IP
    final seen = <String>{};
    final deduped = <DeviceEndpoint>[];
    for (final d in results) {
      final key = d.address.address;
      if (!seen.contains(key)) {
        seen.add(key);
        deduped.add(d);
      }
    }
    return deduped;
  }

  /// Brute-force subnet scan as an mDNS fallback. Reads the device's own
  /// IPv4 address to derive the /24 subnet, then probes every host on the
  /// subnet for a `/json/info` response that mentions WLED. Runs in
  /// batches of 20 to avoid overwhelming the network or the OS socket
  /// budget. Each probe has an 800 ms ceiling so a full /24 scan caps
  /// at roughly (254 / 20) × 800 ms ≈ 10 seconds.
  Future<List<DeviceEndpoint>> _subnetScan() async {
    try {
      // Get device IP to determine subnet
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      String? subnet;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4 && parts[0] != '127') {
            subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
            break;
          }
        }
        if (subnet != null) break;
      }

      if (subnet == null) return [];

      debugPrint('Subnet scan on $subnet.x');
      final results = <DeviceEndpoint>[];
      final futures = <Future>[];

      // Scan in batches of 20 to avoid overwhelming the network
      for (int i = 1; i <= 254; i++) {
        final ip = '$subnet.$i';
        futures.add(() async {
          try {
            final client = HttpClient()
              ..connectionTimeout = const Duration(milliseconds: 800);
            final req = await client.getUrl(Uri.parse('http://$ip/json/info'));
            final res = await req.close()
                .timeout(const Duration(milliseconds: 800));
            final body = await res.transform(utf8.decoder).join();
            client.close(force: true);
            if (res.statusCode == 200 && body.contains('WLED')) {
              results.add(DeviceEndpoint(
                name: 'WLED @ $ip',
                address: InternetAddress(ip),
              ));
              debugPrint('Found WLED device at $ip');
            }
          } catch (_) {}
        }());

        // Process in batches of 20
        if (futures.length >= 20 || i == 254) {
          await Future.wait(futures);
          futures.clear();
        }
      }

      return results;
    } catch (e) {
      debugPrint('Subnet scan error: $e');
      return [];
    }
  }
}

/// Riverpod provider for discovery service
final deviceDiscoveryServiceProvider = Provider<DeviceDiscoveryService>((ref) => DeviceDiscoveryService());

/// Selected device IP provider (null until chosen)
final selectedDeviceIpProvider = StateProvider<String?>((ref) => null);

/// Async discovery provider that runs once on watch
final discoveredDevicesProvider = FutureProvider<List<DeviceEndpoint>>((ref) async {
  final service = ref.watch(deviceDiscoveryServiceProvider);
  final devices = await service.discover();
  // Prefer names containing nexgen-master or wled
  final preferred = devices.where((d) => d.name.toLowerCase().contains('nexgen-master') || d.name.toLowerCase().contains('wled')).toList();
  if (preferred.isNotEmpty) {
    ref.read(selectedDeviceIpProvider.notifier).state = preferred.first.address.address;
  } else if (devices.isNotEmpty) {
    ref.read(selectedDeviceIpProvider.notifier).state = devices.first.address.address;
  }
  return devices;
});

/// Repository for storing user's devices/controllers in Firestore
class DeviceRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Save or update a device under users/{uid}/controllers/{docId}
  /// Stores: serial, ip, name, ssid (optional), wifiConfigured, createdAt/updatedAt
  Future<void> saveDevice({
    required String userId,
    required String serial,
    required String ip,
    String? name,
    String? ssid,
    bool? wifiConfigured,
  }) async {
    try {
      final docId = serial.isNotEmpty ? serial.replaceAll(':', '_') : ip.replaceAll('.', '_');
      final docPath = 'users/$userId/controllers/$docId';

      debugPrint('📦 DeviceRepository: Saving to Firestore path: $docPath');
      debugPrint('   - serial: $serial');
      debugPrint('   - ip: $ip');
      debugPrint('   - name: ${name ?? 'Controller '+ip}');
      debugPrint('   - ssid: ${ssid ?? 'N/A'}');
      final resolvedWifiConfigured = wifiConfigured ?? (ssid != null && ssid.isNotEmpty);
      debugPrint('   - wifiConfigured: $resolvedWifiConfigured');

      final ref = _db.collection('users').doc(userId).collection('controllers').doc(docId);

      final data = {
        'serial': serial,
        'ip': ip,
        'name': name ?? 'Controller '+ip,
        if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
        'wifiConfigured': resolvedWifiConfigured,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Check if document exists to determine if we should set createdAt
      final doc = await ref.get();
      if (!doc.exists) {
        data['createdAt'] = FieldValue.serverTimestamp();
        debugPrint('📝 Creating new controller document');
      } else {
        debugPrint('🔄 Updating existing controller document');
      }

      await ref.set(data, SetOptions(merge: true));
      debugPrint('✅ DeviceRepository: Save successful!');
    } catch (e) {
      debugPrint('❌ DeviceRepository.saveDevice failed: $e');
      rethrow;
    }
  }
}
