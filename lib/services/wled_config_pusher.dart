import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/models/controller_type.dart';

/// Outcome of a config-push operation, including the HTTP status code on
/// failure so dealers can troubleshoot on-site.
class WledConfigPushResult {
  final bool success;
  final String? errorMessage;
  final List<String> warnings;

  const WledConfigPushResult({
    required this.success,
    this.errorMessage,
    this.warnings = const [],
  });
}

/// Pushes NGL-standard WLED defaults for a given [ControllerType] to the
/// device at [controllerIp].
///
/// Only [ControllerType.skikbily] has an opinionated default profile today.
/// [ControllerType.digOcta] keeps its existing settings (configured via the
/// Dig-Octa web UI). [ControllerType.genericWled] is a no-op — generic units
/// are configured manually by the dealer.
Future<WledConfigPushResult> pushDefaultsForControllerType(
  String controllerIp,
  ControllerType type,
) async {
  // The SKIKBILY profile (SK6812 RGBW / GRBW / 100 px per channel) is the
  // Lumina standard — we now apply it across all controller types. Existing
  // GPIO pin assignments are preserved by reading the device's current
  // hardware config first.
  final service = WledService('http://$controllerIp');

  // 1. Read current hardware config to preserve existing GPIO pin
  //    assignments. We only overwrite LED type, order, and pixel count.
  final currentConfig = await service.getConfig();
  final List<Map<String, dynamic>> buses = [];
  int startAddress = 0;
  const int pixelsPerChannel = 100;
  const int channelCount = 4;
  const int ledType = 22; // SK6812 RGBW
  const int colorOrder = 6; // GRBW — required for SK6812 RGBW (LED type 22)

  if (currentConfig != null && currentConfig.buses.isNotEmpty) {
    final busCount =
        currentConfig.buses.length < channelCount
            ? currentConfig.buses.length
            : channelCount;
    for (int i = 0; i < busCount; i++) {
      buses.add({
        'start': startAddress,
        'len': pixelsPerChannel,
        'pin': currentConfig.buses[i].pin,
        'type': ledType,
        'order': colorOrder,
        'rev': false,
        'skip': 0,
      });
      startAddress += pixelsPerChannel;
    }
  } else {
    // No existing config readable — fall back to common SKIKBILY GPIOs.
    const defaultPins = [16, 3, 1, 4];
    for (int i = 0; i < channelCount; i++) {
      buses.add({
        'start': startAddress,
        'len': pixelsPerChannel,
        'pin': [defaultPins[i]],
        'type': ledType,
        'order': colorOrder,
        'rev': false,
        'skip': 0,
      });
      startAddress += pixelsPerChannel;
    }
  }

  // 2. Derive mDNS name from MAC address (last 4 hex chars).
  final info = await service.getInfo();
  final mac = info?.raw['mac'] as String? ?? '';
  final last4 =
      mac.length >= 4
          ? mac.substring(mac.length - 4).toLowerCase()
          : 'xxxx';

  // 3. Build and POST the /json/cfg payload.
  //    Power limit: 5 000 mA × 4 channels = 20 000 mA → 20 000 mW at ~1 V
  //    but WLED expects milliwatts at the configured voltage. For 5 V strips
  //    20 000 mW ≈ 4 A (safe for LRS-350-24 supplies).  We specify 20 000 as
  //    the per-controller cap — the same value used on existing installs.
  final cfgPayload = {
    'hw': {
      'led': {
        'total': startAddress,
        'maxpwr': 20000,
        'ins': buses,
      },
    },
    'id': {
      'mdns': 'ngl-skikbily-$last4',
    },
  };

  // Direct POST so we can capture the HTTP status code for the dealer.
  final cfgResult = await _postConfig(controllerIp, cfgPayload);
  if (!cfgResult.success) return cfgResult;

  // 4. Apply state-level defaults (brightness cap + sync off).
  //    Each call is isolated so one failure doesn't block the other.
  final warnings = <String>[];
  try {
    await service.setState(brightness: 212); // 70 % of 255
  } catch (e) {
    warnings.add('Brightness cap (70%) not applied: $e');
    debugPrint('SKIKBILY: setState brightness failed: $e');
  }
  try {
    await service.applyJson({
      'udpn': {'send': false, 'recv': false},
    });
  } catch (e) {
    warnings.add('UDP sync disable failed: $e');
    debugPrint('SKIKBILY: UDP sync disable failed: $e');
  }

  return WledConfigPushResult(success: true, warnings: warnings);
}

/// Posts a JSON config payload to `/json/cfg` and returns a
/// [WledConfigPushResult] that includes the HTTP status code on failure.
Future<WledConfigPushResult> _postConfig(
  String ip,
  Map<String, dynamic> data,
) async {
  try {
    final body = jsonEncode(data);
    debugPrint('📤 ConfigPusher POST /json/cfg to $ip');
    debugPrint('   Payload: $body');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final req = await client.postUrl(Uri.parse('http://$ip/json/cfg'));
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.add(utf8.encode(body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final resBody = await res.transform(utf8.decoder).join();
    client.close(force: true);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      debugPrint('✅ ConfigPusher /json/cfg success');
      return const WledConfigPushResult(success: true);
    }

    debugPrint('❌ ConfigPusher /json/cfg error ${res.statusCode}: $resBody');
    return WledConfigPushResult(
      success: false,
      errorMessage: 'Config push failed — HTTP ${res.statusCode}',
    );
  } catch (e) {
    debugPrint('❌ ConfigPusher /json/cfg exception: $e');
    return WledConfigPushResult(
      success: false,
      errorMessage: 'Config push failed — $e',
    );
  }
}
