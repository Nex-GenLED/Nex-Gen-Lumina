import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/shared/write_result.dart';

/// Result of a provisioning attempt.
///
/// Row 67 (+110): the controller taking the Wi-Fi details, the account
/// recording it, and the controller showing up on the network are three
/// different facts. They used to be collapsed into "Device Connected!".
class ProvisionResult {
  final String ip;
  final String serial;

  /// Whether the controller record reached the account. On failure its
  /// message says why, in the customer's words.
  final WriteResult accountSave;

  /// Whether the controller answered on the home network after taking the
  /// Wi-Fi details. False means "credentials sent, not yet found": it may
  /// still be joining the network.
  final bool reachable;

  const ProvisionResult({
    required this.ip,
    required this.serial,
    required this.accountSave,
    required this.reachable,
  });

  bool get savedToAccount => accountSave.ok;
}

/// How the device-setup screen gets a [ProvisioningService] for an account.
/// Overridden in tests.
final provisioningServiceFactoryProvider =
    Provider<ProvisioningService Function(String targetUserId)>(
  (ref) => (targetUserId) => ProvisioningService(targetUserId: targetUserId),
);

/// Exception thrown during provisioning with additional context
class ProvisioningException implements Exception {
  final String message;
  final bool requiresManualIp;
  final bool canRetryManual;

  const ProvisioningException(
    this.message, {
    this.requiresManualIp = false,
    this.canRetryManual = false,
  });

  @override
  String toString() => 'ProvisioningException: $message';
}

/// Implements Improv Standard provisioning over BLE and hands off to Wi‑Fi
class ProvisioningService {
  /// The account the provisioned controller is saved under.
  ///
  /// #96 — REQUIRED, and deliberately not defaulted to
  /// `FirebaseAuth.currentUser`. This class has no Riverpod `ref`, so the uid is
  /// injected by its caller from [effectiveUserUidProvider]; an installer
  /// provisioning hardware from inside the Existing Customer flow must save it
  /// to the CUSTOMER's account. A nullable-with-fallback parameter would let a
  /// future caller silently reintroduce the defect by omitting it, so it is
  /// required — there is exactly one construction site
  /// (`device_setup_page.dart`) and it has a `ref`.
  final String targetUserId;

  ProvisioningService({required this.targetUserId, DeviceRepository? repository})
      : _repository = repository;

  final DeviceRepository? _repository;

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
      final saved = await saveController(ip: ip, serial: serial, ssid: ssid);
      return ProvisionResult(
          ip: ip, serial: serial, accountSave: saved, reachable: true);
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
      if (writeChar == null && improvService.characteristics.isNotEmpty) {
        writeChar = improvService.characteristics.firstWhere(
          (c) => (c.properties.write || c.properties.writeWithoutResponse),
          orElse: () => improvService.characteristics.first,
        );
      }
      if (writeChar == null) throw Exception('No writable characteristic found on device');
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

      // Persist to the account. The result is REPORTED, not swallowed: a
      // controller that took the Wi-Fi details but never reached the account
      // is not "set up".
      final saved = await saveController(ip: ip, serial: serial, ssid: ssid);

      // Disconnect BLE
      try {
        await device.disconnect();
      } catch (e) {
        debugPrint('ProvisioningService: disconnect failed: $e');
      }

      // Verify Wi‑Fi reachability. Not reachable yet means "credentials
      // sent, not yet found" — the caller says so instead of "Connected".
      final reachable = await verifyReachable(ip);

      return ProvisionResult(
        ip: ip,
        serial: serial,
        accountSave: saved,
        reachable: reachable,
      );
    } catch (e) {
      debugPrint('ProvisioningService: provision failed: $e');
      rethrow;
    } finally {
      try {
        await notifySub?.cancel();
      } catch (e) {
        debugPrint('Error in provision cancel notification subscription: $e');
      }
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
      } catch (e) {
        debugPrint('Error in _parseImprovResponse utf8 decode: $e');
      }
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

  /// Records the controller on [targetUserId]'s account.
  ///
  /// Row 67 (+110): this used to swallow every failure (and skip silently
  /// when there was no account id), so the setup screen said "Device
  /// Connected!" and left with no controller registered. It now says what
  /// happened. Also the retry the setup screen offers.
  Future<WriteResult> saveController({
    required String ip,
    required String serial,
    String? ssid,
  }) async {
    if (targetUserId.isEmpty) {
      return const WriteResult.blocked(
          "You're not signed in, so the controller couldn't be added to "
          'your account.');
    }
    try {
      await (_repository ?? DeviceRepository())
          .saveDevice(userId: targetUserId, serial: serial, ip: ip, ssid: ssid)
          .timeout(const Duration(seconds: 15));
      return const WriteResult.success();
    } on TimeoutException catch (e) {
      return WriteResult.failed(
        WriteFailureKind.unreachable,
        message: "Couldn't reach your account to save the controller. Check "
            'your connection and try again.',
        error: e,
      );
    } catch (e) {
      debugPrint('ProvisioningService: save repository failed: $e');
      return WriteResult.failed(
        WriteFailureKind.error,
        message: "The controller couldn't be added to your account ($e).",
        error: e,
      );
    }
  }

  /// Verify device reachable over Wi‑Fi by trying a quick HTTP request.
  Future<bool> verifyReachable(String ip) async {
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
    } catch (e) {
      debugPrint('Error in _verifyReachable mDNS fallback: $e');
    }
    return false;
  }

  /// Streamlined hybrid provisioning that eliminates manual Wi-Fi reconnection.
  ///
  /// Flow:
  /// 1) Send Wi-Fi credentials via BLE Improv RPC
  /// 2) Disconnect BLE immediately (no waiting for response)
  /// 3) Wait 45 seconds for controller to reboot and connect
  /// 4) Auto-discover via mDNS (3 attempts, 10s each)
  /// 5) If found → Verify and save
  /// 6) If not found → Throw exception with requiresManualIp flag
  ///
  /// The caller should handle the ProvisioningException and offer:
  /// - Manual IP entry (primary fallback)
  /// - Full manual setup flow (secondary fallback)
  Future<ProvisionResult> provisionDeviceHybrid({
    required BluetoothDevice device,
    required String ssid,
    required String password,
    void Function(String)? onStatusUpdate,
  }) async {
    // Simulation/Web shortcut
    if (kIsWeb || kSimulationMode) {
      onStatusUpdate?.call('Simulating provisioning...');
      await Future.delayed(const Duration(seconds: 2));
      final ip = '192.168.1.123';
      final serial = device.remoteId.str;
      final saved = await saveController(ip: ip, serial: serial, ssid: ssid);
      return ProvisionResult(
          ip: ip, serial: serial, accountSave: saved, reachable: true);
    }

    final serial = device.remoteId.str;

    try {
      // Step 1: Send credentials via BLE
      onStatusUpdate?.call('Sending Wi-Fi credentials...');
      await _sendCredentialsViaBle(device, ssid, password);

      // Step 2: Disconnect BLE immediately
      onStatusUpdate?.call('Disconnecting Bluetooth...');
      try {
        await device.disconnect();
      } catch (e) {
        debugPrint('ProvisioningService: disconnect warning: $e');
      }

      // Step 3: Wait for controller to reboot (45 seconds with countdown)
      for (int i = 45; i > 0; i--) {
        onStatusUpdate?.call('Waiting for controller to restart... ${i}s');
        await Future.delayed(const Duration(seconds: 1));
      }

      // Step 4: Auto-discover via mDNS (3 attempts)
      String? discoveredIp;
      for (int attempt = 1; attempt <= 3; attempt++) {
        onStatusUpdate?.call('Searching for controller... (Attempt $attempt/3)');

        try {
          final devices = await DeviceDiscoveryService()
              .discover(timeout: const Duration(seconds: 10));

          // Look for WLED/Nex-Gen device
          for (final d in devices) {
            final name = d.name.toLowerCase();
            if (name.contains('wled') || name.contains('nex-gen') || name.contains('nexgen')) {
              discoveredIp = d.address.address;
              break;
            }
          }

          // If we found one, verify it's reachable
          if (discoveredIp != null) {
            onStatusUpdate?.call('Verifying controller at $discoveredIp...');
            final reachable = await verifyReachable(discoveredIp);
            if (reachable) {
              break;
            } else {
              discoveredIp = null; // Not reachable, try again
            }
          }
        } catch (e) {
          debugPrint('ProvisioningService: discovery attempt $attempt failed: $e');
        }

        if (attempt < 3 && discoveredIp == null) {
          await Future.delayed(const Duration(seconds: 5));
        }
      }

      // Step 5: If found, save and return
      if (discoveredIp != null) {
        onStatusUpdate?.call('Controller found at $discoveredIp!');
        final saved = await saveController(
            ip: discoveredIp, serial: serial, ssid: ssid);
        return ProvisionResult(
            ip: discoveredIp,
            serial: serial,
            accountSave: saved,
            reachable: true);
      }

      // Step 6: Not found - throw exception for manual IP fallback
      throw const ProvisioningException(
        'Controller not found on network after 3 attempts.',
        requiresManualIp: true,
        canRetryManual: true,
      );
    } catch (e) {
      if (e is ProvisioningException) rethrow;
      debugPrint('ProvisioningService: hybrid provision failed: $e');
      throw ProvisioningException(
        'Provisioning failed: $e',
        requiresManualIp: true,
        canRetryManual: true,
      );
    }
  }

  /// Send Wi-Fi credentials via BLE without waiting for full provisioning.
  Future<void> _sendCredentialsViaBle(
    BluetoothDevice device,
    String ssid,
    String password,
  ) async {
    BluetoothCharacteristic? writeChar;

    try {
      // Connect if needed
      try {
        await (device as dynamic).connect();
      } catch (e) {
        debugPrint('ProvisioningService: connect skipped/failed: $e');
      }

      // Discover services
      final services = await device.discoverServices();
      final improvService = services.firstWhere(
        (s) => s.uuid == _improvUuid,
        orElse: () => services.firstWhere(
          (s) => s.characteristics.any((c) => c.uuid == _improvUuid),
          orElse: () => services.isNotEmpty ? services.first : throw Exception('No services on device'),
        ),
      );

      // Find write characteristic
      for (final c in improvService.characteristics) {
        if (c.uuid == _improvUuid && (c.properties.write || c.properties.writeWithoutResponse)) {
          writeChar = c;
          break;
        }
      }
      if (writeChar == null && improvService.characteristics.isNotEmpty) {
        writeChar = improvService.characteristics.firstWhere(
          (c) => (c.properties.write || c.properties.writeWithoutResponse),
          orElse: () => improvService.characteristics.first,
        );
      }
      if (writeChar == null) throw Exception('No writable characteristic found on device');

      // Build and send provision command
      final packet = _buildImprovProvisionPacket(ssid, password);
      debugPrint('ProvisioningService: writing ${packet.length} bytes (hybrid)');
      await writeChar.write(packet, withoutResponse: writeChar.properties.writeWithoutResponse);

      // Brief delay to ensure write completes
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('ProvisioningService: send credentials failed: $e');
      throw ProvisioningException('Failed to send Wi-Fi credentials: $e');
    }
  }

  /// Save a manually-entered IP address after failed auto-discovery.
  /// This is called by the UI when the user enters an IP manually.
  Future<ProvisionResult> saveManualIp({
    required String ip,
    required String serial,
    String? ssid,
  }) async {
    // Verify the IP is reachable first
    final reachable = await verifyReachable(ip);
    if (!reachable) {
      throw const ProvisioningException(
        'Controller at this IP is not responding. Please check the IP address.',
      );
    }

    // Save to repository
    final saved = await saveController(ip: ip, serial: serial, ssid: ssid);
    return ProvisionResult(
        ip: ip, serial: serial, accountSave: saved, reachable: true);
  }
}
