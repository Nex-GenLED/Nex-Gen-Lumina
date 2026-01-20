import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Result of a provisioning attempt
class ProvisionResult {
  final String ip;
  final String serial;
  const ProvisionResult({required this.ip, required this.serial});
}

/// Implements Improv Standard provisioning over BLE and hands off to Wi‑Fi
class ProvisioningService {
  static final Guid _improvUuid = Guid('00000000-0090-0016-0128-633215502390');

  /// Provisions a device to the given Wi‑Fi network using Improv BLE RPC.
  ///
  /// Flow:
  /// 1) Discover Improv characteristics and write credentials
  /// 2) Listen for notify response with local IP
  /// 3) Save IP+serial to DeviceRepository
  /// 4) Disconnect BLE and verify the IP is reachable over Wi‑Fi
  Future<ProvisionResult> provisionDevice({
    required BluetoothDevice device,
    required String ssid,
    required String password,
  }) async {
    // Simulation/Web shortcut: fabricate a success result
    if (kIsWeb || kSimulationMode) {
      final ip = '192.168.1.123';
      final serial = device.remoteId.str; // best available identifier
      await _saveToRepository(ip: ip, serial: serial, ssid: ssid);
      return ProvisionResult(ip: ip, serial: serial);
    }

    BluetoothCharacteristic? writeChar;
    BluetoothCharacteristic? resultChar;
    StreamSubscription<List<int>>? notifySub;
    final completer = Completer<String?>();

    try {
      // Ensure connection; plugin throws if already connected — catch and continue
      try {
        await (device as dynamic).connect();
      } catch (e) {
        debugPrint('ProvisioningService: connect skipped/failed (continuing): $e');
      }

      final services = await device.discoverServices();
      final improvService = services.firstWhere(
        (s) => s.uuid == _improvUuid,
        orElse: () => services.firstWhere(
          (s) => s.characteristics.any((c) => c.uuid == _improvUuid),
          orElse: () => services.isNotEmpty ? services.first : throw Exception('No services on device'),
        ),
      );

      for (final c in improvService.characteristics) {
        if (c.uuid == _improvUuid && (c.properties.write || c.properties.writeWithoutResponse)) {
          writeChar = c;
        }
        if ((c.properties.read || c.properties.notify) && !(c.properties.write || c.properties.writeWithoutResponse)) {
          resultChar ??= c;
        }
      }
      writeChar ??= improvService.characteristics.firstWhere(
        (c) => (c.properties.write || c.properties.writeWithoutResponse),
        orElse: () => improvService.characteristics.first,
      );
      if (writeChar == null) {
        throw Exception('Improv characteristic not found');
      }

      // Subscribe to notifications on the write characteristic (common for Improv)
      try {
        await writeChar.setNotifyValue(true);
      } catch (e) {
        debugPrint('ProvisioningService: failed to enable notify on writeChar: $e');
      }
      notifySub = writeChar.onValueReceived.listen((data) {
        final ip = _parseImprovResponse(data);
        if (ip != null && !completer.isCompleted) completer.complete(ip);
      }, onError: (e) {
        debugPrint('ProvisioningService: notify error: $e');
        if (!completer.isCompleted) completer.complete(null);
      });

      // Build and send provision command
      final packet = _buildImprovProvisionPacket(ssid, password);
      debugPrint('ProvisioningService: writing ${packet.length} bytes');
      await writeChar.write(packet, withoutResponse: writeChar.properties.writeWithoutResponse);

      // Optional: read result characteristic once for immediate feedback
      if (resultChar != null) {
        try {
          final bytes = await resultChar.read();
          final ip = _parseImprovResponse(bytes);
          if (ip != null && !completer.isCompleted) completer.complete(ip);
        } catch (e) {
          debugPrint('ProvisioningService: read result char failed: $e');
        }
      }

      // Wait up to 20s for an IP
      final ip = await completer.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
      if (ip == null) {
        throw Exception('Provisioning timed out');
      }

      final serial = device.remoteId.str;

      // Persist to repository
      await _saveToRepository(ip: ip, serial: serial, ssid: ssid);

      // Disconnect BLE
      try {
        await device.disconnect();
      } catch (e) {
        debugPrint('ProvisioningService: disconnect failed: $e');
      }

      // Verify Wi‑Fi reachability
      final ok = await _verifyReachable(ip);
      if (!ok) {
        debugPrint('ProvisioningService: IP not reachable yet, will still return result.');
      }

      return ProvisionResult(ip: ip, serial: serial);
    } catch (e) {
      debugPrint('ProvisioningService: provision failed: $e');
      rethrow;
    } finally {
      try {
        await notifySub?.cancel();
      } catch (_) {}
    }
  }

  // Improv RPC framing (command 0x01 = Provision). Payload: SSID + 0x00 + Password (UTF‑8)
  List<int> _buildImprovProvisionPacket(String ssid, String password) {
    final ssidBytes = utf8.encode(ssid);
    final passBytes = utf8.encode(password);
    final payload = <int>[...ssidBytes, 0x00, ...passBytes];
    const cmd = 0x01; // Provision
    const version = 0x01;
    const type = 0x00; // command
    final payloadLen = payload.length;
    final len = 1 + 1 + payloadLen; // command + payload_len + payload
    return <int>[version, type, len, cmd, payloadLen, ...payload];
  }

  String? _parseImprovResponse(List<int> data) {
    if (data.isEmpty) return null;
    final code = data.first;
    // 0x02 = provision success with payload (URL or IP), 0x03 = in progress, 0x04 = error
    if (code == 0x02) {
      final payload = data.length > 1 ? data.sublist(1) : const <int>[];
      String text = '';
      try {
        text = utf8.decode(payload, allowMalformed: true);
      } catch (_) {}
      return _extractIp(text);
    }
    return null;
  }

  String? _extractIp(String text) {
    final uriMatch = RegExp(r'https?://([^\s/]+)').firstMatch(text);
    if (uriMatch != null) {
      final host = uriMatch.group(1)!;
      // Strict IP check (end-anchor should be $ not a literal dollar sign)
      final isIp = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$').hasMatch(host);
      if (isIp) return host;
    }
    return RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(text)?.group(1);
  }

  Future<void> _saveToRepository({required String ip, required String serial, String? ssid}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final repo = DeviceRepository();
      await repo.saveDevice(userId: user.uid, serial: serial, ip: ip, ssid: ssid);
    } catch (e) {
      debugPrint('ProvisioningService: save repository failed: $e');
    }
  }

  /// Verify device reachable over Wi‑Fi by trying a quick HTTP request.
  Future<bool> _verifyReachable(String ip) async {
    try {
      final uri = Uri.parse('http://$ip/json');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) return true;
    } catch (e) {
      debugPrint('ProvisioningService: verify reachability failed: $e');
    }
    // Fallback: attempt mDNS discovery quickly
    try {
      final list = await DeviceDiscoveryService().discover(timeout: const Duration(seconds: 3));
      return list.any((d) => d.address.address == ip);
    } catch (_) {}
    return false;
  }
}
