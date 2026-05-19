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

  /// Soft-success: the operation was a no-op because the inputs were
  /// missing. Surfaces the reason as a single warning so callers can log
  /// it but doesn't fail the parent flow.
  factory WledConfigPushResult.skipped(String reason) =>
      WledConfigPushResult(success: true, warnings: [reason]);

  /// Soft-success: the write succeeded but a post-write check flagged a
  /// concern (e.g. readback mismatch). Caller decides whether to retry.
  factory WledConfigPushResult.warning(String message) =>
      WledConfigPushResult(success: true, warnings: [message]);
}

/// Maps IANA timezone names to WLED's `if.ntp.tz` integer enum.
///
/// Source: WLED ntp.cpp TZ_TABLE. The list is intentionally narrow — only
/// continental-US + AK/HI/AZ are covered because that's where Lumina
/// installs go today. Anything outside this set falls back to
/// [kWledTzUtc]; the controller's clock will run on UTC and astronomical
/// events will be off by the local offset. Add new entries as install
/// regions expand; do not invent enum values that don't exist in the WLED
/// firmware's TZ_TABLE — the device silently ignores unknown indices.
const Map<String, int> kWledTzByIana = <String, int>{
  'America/New_York': 4, // TZ_US_EASTERN  (EST/EDT)
  'America/Chicago': 5, // TZ_US_CENTRAL  (CST/CDT)
  'America/Denver': 6, // TZ_US_MOUNTAIN (MST/MDT)
  'America/Phoenix': 7, // TZ_US_ARIZONA  (MST, no DST)
  'America/Los_Angeles': 8, // TZ_US_PACIFIC  (PST/PDT)
  'America/Anchorage': 20, // TZ_ANCHORAGE   (AKST/AKDT)
  'Pacific/Honolulu': 18, // TZ_HAWAII      (HST, no DST)
};

/// WLED's "no zone" / fallback index — clock runs on UTC.
const int kWledTzUtc = 0;

/// Resolves the WLED tz enum for an IANA name. Unknown names map to UTC.
int wledTzForIana(String? iana) => kWledTzByIana[iana] ?? kWledTzUtc;

/// Pushes NGL-standard WLED defaults for a given [ControllerType] to the
/// device at [controllerIp].
///
/// Only [ControllerType.skikbily] has an opinionated default profile today.
/// [ControllerType.digOcta] keeps its existing settings (configured via the
/// Dig-Octa web UI). [ControllerType.genericWled] is a no-op — generic units
/// are configured manually by the dealer.
Future<WledConfigPushResult> pushDefaultsForControllerType(
  String controllerIp,
  ControllerType type, {
  double? latitude,
  double? longitude,
  String? ianaTimezone,
}) async {
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
  // Unified with hardware_config_screen.dart (the manual editor) which uses
  // type 30. Per WLED busses.cpp, type 30 is SK6812 RGBW in current builds;
  // type 22 was the older SK6812 RGBW mapping the pusher used to ship.
  const int ledType = 30; // SK6812 RGBW
  // WLED standard color-order enum is 3-letter only (0=GRB, 1=RGB, 2=BRG,
  // 3=RBG, 4=BGR, 5=GBR). For RGBW bus types (22, 30, 31) WLED appends the
  // W channel automatically — so order=1 on a type-30 bus sends R→G→B→W,
  // which is the Lumina default ("RGB" in WLED's UI dropdown).
  const int colorOrder = 1; // RGB (W appended automatically on RGBW bus type)
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

  // 3.5. Push NTP + lat/lon so the controller's clock and astronomical
  //      events (sunrise/sunset/twilight schedules) are anchored to the
  //      customer's actual location. Failure is a warning — install
  //      continues. The push is a no-op when any of the three fields is
  //      null (e.g. legacy users completing onboarding before Phase 1).
  final tlResult = await pushTimeLocation(
    controllerIp,
    latitude: latitude,
    longitude: longitude,
    ianaTimezone: ianaTimezone,
  );
  if (!tlResult.success) {
    warnings.add('time/location push failed: ${tlResult.errorMessage}');
  } else if (tlResult.warnings.isNotEmpty) {
    warnings.addAll(tlResult.warnings);
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

/// Pushes the customer's home coordinates and WLED tz enum into the
/// controller's `if.ntp.*` block. Called as a step inside
/// [pushDefaultsForControllerType] during install, and as the body of the
/// "Re-sync Configuration" action on the Manage Controllers screen for
/// already-installed devices.
///
/// Returns [WledConfigPushResult.skipped] when any of lat/lon/iana is
/// null — the caller's parent flow continues unchanged.
///
/// CRITICAL: `if.ntp.offset` is ADDITIVE to the `tz` enum on the device.
/// We send offset:0 so the enum is the sole source of truth; stacking
/// them double-shifts the clock.
Future<WledConfigPushResult> pushTimeLocation(
  String controllerIp, {
  required double? latitude,
  required double? longitude,
  required String? ianaTimezone,
  bool verifyAfterWrite = true,
}) async {
  if (latitude == null || longitude == null || ianaTimezone == null) {
    return WledConfigPushResult.skipped('time/location data missing');
  }

  final tz = wledTzForIana(ianaTimezone);
  final payload = <String, dynamic>{
    'if': {
      'ntp': {
        'en': true,
        'host': '0.wled.pool.ntp.org',
        'tz': tz,
        'offset': 0,
        'ampm': false,
        'ln': longitude,
        'lt': latitude,
      },
    },
  };

  final result = await _postConfig(controllerIp, payload);
  if (!result.success) return result;

  if (!verifyAfterWrite) return result;

  // Best-effort readback. The write returned 2xx; if verification can't
  // reach the device or the device returns an unparseable body, we trust
  // the write and return success. Only a clear mismatch on the fields we
  // just set surfaces as a warning.
  try {
    final cfg = await _fetchRawConfig(controllerIp);
    if (cfg != null) {
      final ntp = (cfg['if'] as Map?)?['ntp'] as Map?;
      if (ntp == null ||
          ntp['tz'] != tz ||
          (ntp['lt'] as num?)?.toDouble() != latitude ||
          (ntp['ln'] as num?)?.toDouble() != longitude) {
        return WledConfigPushResult.warning(
          'time/location write reported success but readback mismatch',
        );
      }
    }
  } catch (_) {
    // Soft-fail — write already returned 2xx.
  }

  return result;
}

/// Fetches the raw `/json/cfg` Map from the controller. Used by
/// [pushTimeLocation] for readback verification of fields not exposed by
/// the typed [WledService.getConfig] (which only parses `hw.led.*`).
/// Returns null on any error.
Future<Map<String, dynamic>?> _fetchRawConfig(String ip) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final req = await client.getUrl(Uri.parse('http://$ip/json/cfg'));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    client.close(force: true);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(body) as Map<String, dynamic>;
    }
  } catch (e) {
    debugPrint('[WledConfig] _fetchRawConfig exception: $e');
  }
  return null;
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
