import 'dart:async';
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

  Future<List<DeviceEndpoint>> discover({Duration timeout = const Duration(seconds: 5)}) async {
    // Simulation mode: instantly return a virtual device and skip network.
    if (kSimulationMode) {
      return [
        DeviceEndpoint(name: 'Virtual Nex-Gen Home', address: InternetAddress.loopbackIPv4),
      ];
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
      } catch (_) {}
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
  final preferred = devices.where((d) => d.name.toLowerCase().contains('nexgen-master') || d.name.toLowerCase().contains('wled'));
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
  }) async {
    try {
      final docId = serial.isNotEmpty ? serial.replaceAll(':', '_') : ip.replaceAll('.', '_');
      final docPath = 'users/$userId/controllers/$docId';

      debugPrint('📦 DeviceRepository: Saving to Firestore path: $docPath');
      debugPrint('   - serial: $serial');
      debugPrint('   - ip: $ip');
      debugPrint('   - name: ${name ?? 'Controller '+ip}');
      debugPrint('   - ssid: ${ssid ?? 'N/A'}');
      debugPrint('   - wifiConfigured: ${ssid != null && ssid.isNotEmpty}');

      final ref = _db.collection('users').doc(userId).collection('controllers').doc(docId);

      final data = {
        'serial': serial,
        'ip': ip,
        'name': name ?? 'Controller '+ip,
        if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
        'wifiConfigured': ssid != null && ssid.isNotEmpty,
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
