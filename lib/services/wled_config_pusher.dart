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
  if (currentConfig != null) {
    debugPrint(
        '[WledConfig] Current config: total=${currentConfig.totalLeds} '
        'maxpwr=${currentConfig.maxPowerMw} '
        'buses=${currentConfig.buses.length}');
    for (var i = 0; i < currentConfig.buses.length; i++) {
      final b = currentConfig.buses[i];
      debugPrint('[WledConfig]   bus[$i]: pin=${b.pin} start=${b.start} '
          'len=${b.len} type=${b.type} order=${b.order}');
    }
  } else {
    debugPrint('[WledConfig] Current config: <unreadable>');
  }

  const int pixelsPerChannel = 100;
  const int channelCount = 4;
  const int ledType = 22; // SK6812 RGBW
  const int colorOrder = 6; // GRBW — required for SK6812 RGBW (LED type 22)
  // SKIKBILY hardware always has 4 channels. A fresh WLED ships with one
  // default bus, so we can't size the new config from the old one — we
  // always emit 4 buses. Pin assignments come from the existing config
  // when present (preserves manual installer overrides) and fall back to
  // the SKIKBILY default GPIOs for any slot the device hasn't populated.
  const defaultPins = [16, 3, 1, 4];

  final List<Map<String, dynamic>> buses = [];
  int startAddress = 0;
  for (int i = 0; i < channelCount; i++) {
    List<int> pins;
    if (currentConfig != null && i < currentConfig.buses.length) {
      pins = currentConfig.buses[i].pin;
    } else {
      pins = [defaultPins[i]];
    }
    buses.add({
      'start': startAddress,
      'len': pixelsPerChannel,
      'pin': pins,
      'type': ledType,
      'order': colorOrder,
      'rev': false,
      'skip': 0,
    });
    startAddress += pixelsPerChannel;
  }

  // 2. Derive mDNS name from MAC address (last 4 hex chars).
  final info = await service.getInfo();
  final mac = info?.raw['mac'] as String? ?? '';
  final last4 =
      mac.length >= 4
          ? mac.substring(mac.length - 4).toLowerCase()
          : 'xxxx';

  // 3. POST the config in two parts. WLED 0.15.x on the ESP32_Ethernet
  //    build returns HTTP 413 on combined hw + id POSTs because its
  //    AsyncJsonHandler chokes on chunked transfer encoding (which Dart's
  //    HttpClient uses by default when Content-Length is unset). Splitting
  //    the payload, plus setting Content-Length explicitly in _postConfig,
  //    keeps each request small enough to land in the parser's pre-allocated
  //    buffer and avoids the chunked path entirely.
  //
  //    Power limit: 5 000 mA × 4 channels = 20 000 mA → 20 000 mW at ~1 V
  //    but WLED expects milliwatts at the configured voltage. For 5 V strips
  //    20 000 mW ≈ 4 A (safe for LRS-350-24 supplies). We specify 20 000 as
  //    the per-controller cap — the same value used on existing installs.
  final hwPayload = {
    'hw': {
      'led': {
        'total': startAddress,
        'maxpwr': 20000,
        'ins': buses,
      },
    },
  };
  final hwResult = await _postConfig(controllerIp, hwPayload);
  if (!hwResult.success) return hwResult;

  // mDNS rename is cosmetic — failure is a warning, not a rollback.
  final warnings = <String>[];
  final idPayload = {
    'id': {
      'mdns': 'ngl-skikbily-$last4',
    },
  };
  final idResult = await _postConfig(controllerIp, idPayload);
  if (!idResult.success) {
    warnings.add('mDNS rename failed: ${idResult.errorMessage}');
  }

  // 4. Apply state-level defaults (brightness cap + sync off).
  //    Each call is isolated so one failure doesn't block the other.
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
///
/// Sets `Content-Length` explicitly to keep the request unchunked. WLED
/// 0.15.x's AsyncJsonHandler returns 413 on Transfer-Encoding: chunked
/// requests for /json/cfg, even when the payload is small.
Future<WledConfigPushResult> _postConfig(
  String ip,
  Map<String, dynamic> data,
) async {
  try {
    final body = jsonEncode(data);
    final bodyBytes = utf8.encode(body);
    debugPrint('[WledConfig] Sending to /json/cfg: $body');
    debugPrint(
        '[WledConfig]   bytes=${bodyBytes.length} target=$ip');

    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final req = await client.postUrl(Uri.parse('http://$ip/json/cfg'));
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.contentLength = bodyBytes.length;
    req.add(bodyBytes);
    final res = await req.close().timeout(const Duration(seconds: 15));
    final resBody = await res.transform(utf8.decoder).join();
    client.close(force: true);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      debugPrint('[WledConfig] /json/cfg → ${res.statusCode} OK');
      return const WledConfigPushResult(success: true);
    }

    debugPrint('[WledConfig] /json/cfg → ${res.statusCode}: $resBody');
    return WledConfigPushResult(
      success: false,
      errorMessage: 'Config push failed — HTTP ${res.statusCode}',
    );
  } catch (e) {
    debugPrint('[WledConfig] /json/cfg exception: $e');
    return WledConfigPushResult(
      success: false,
      errorMessage: 'Config push failed — $e',
    );
  }
}
