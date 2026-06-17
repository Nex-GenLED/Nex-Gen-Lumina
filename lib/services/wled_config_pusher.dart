import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
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

/// The NGL color-gamma standard, written to `cfg.light.gc`.
///
/// Matches the WLED firmware default that renders saturated colors correctly
/// on the Lumina SK6812/WS2814 RGBW strip: brightness gamma OFF (`bri:1`),
/// color gamma ON (`col:2.8`), exponent 2.8 (`val:2.8`). WLED stores gamma
/// here — NOT under `hw.led`. A `2.8`/`1`/`2.8` triple is what makes orange
/// render vivid instead of washed amber (gamma darkens the green midtone).
const Map<String, dynamic> kNglLightGammaConfig = <String, dynamic>{
  'bri': 1,
  'col': 2.8,
  'val': 2.8,
};

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

  // Build the SKIKBILY 4-bus profile, preserving each channel's existing
  // GPIO pins AND its manual reverse (rev) flag from the device. The pusher
  // used to hardcode rev:false, which silently undid an installer's
  // bus-direction flip on every Re-sync / re-apply (config half of #3/#4).
  // See buildSkikbilyBuses.
  final buses = buildSkikbilyBuses(currentConfig);
  final startAddress =
      buses.fold<int>(0, (sum, b) => sum + (b['len'] as int));

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
  // NOTE: gamma is NOT a hw.led concern. WLED stores it at cfg.light.gc, and
  // a hw.led bus rebuild does not touch it. The old code read/wrote
  // hw.led.gc — a path WLED never uses — so it was always a no-op. Gamma is
  // now asserted explicitly via pushGammaConfig() below (correct light.gc
  // path). Do NOT reintroduce gc into the hw.led payload.

  const int maxPwrMw = 20000;
  // No-op gate: when the device already matches the SKIKBILY profile exactly
  // (on every field we write), skip the hw.led push so we don't trigger a
  // WLED bus rebuild — which would needlessly drop unmodeled per-bus fields
  // (ref/rgbwm/freq/ledma). Gamma is unaffected either way (it lives at
  // light.gc, independent of hw.led) and is asserted separately below.
  final hwUnchanged = currentConfig != null &&
      currentConfig.totalLeds == startAddress &&
      currentConfig.maxPowerMw == maxPwrMw &&
      ledInsMatches(currentConfig.buses, buses);

  if (hwUnchanged) {
    debugPrint('[WledConfig] hw.led unchanged — skipping config push');
  } else {
    final hwPayload = {
      'hw': {
        'led': buildLedConfig(
          total: startAddress,
          maxpwr: maxPwrMw,
          ins: buses,
        ),
      },
    };
    final hwResult = await _postConfig(controllerIp, hwPayload);
    if (!hwResult.success) return hwResult;
  }

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

  // 3.6. Assert the NGL color-gamma standard (cfg.light.gc) and disable the
  //      realtime gamma bypass (cfg.if.live.no-gc) so saturated colors render
  //      correctly regardless of the controller's flash-time default, and so
  //      HTTP- and DDP/realtime-driven output match. A controller flashed,
  //      reset, or toggled with color gamma off otherwise renders flat, washed
  //      color (orange → amber) and nothing else restores it. Idempotent —
  //      pushGammaConfig skips the write when the device is already correct.
  //      Failure is a warning; install continues.
  final gammaResult = await pushGammaConfig(controllerIp);
  if (!gammaResult.success) {
    warnings.add('gamma push failed: ${gammaResult.errorMessage}');
  } else if (gammaResult.warnings.isNotEmpty) {
    warnings.addAll(gammaResult.warnings);
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

/// Builds the SKIKBILY default `hw.led.ins` bus array (4 channels × 100 px,
/// type 30 / order 1), preserving each channel's existing GPIO pins and
/// manual reverse (`rev`) flag from [currentConfig]. Channels the device
/// hasn't populated yet fall back to the SKIKBILY default GPIOs with
/// rev:false. Preserving rev stops a Re-sync / re-apply from silently
/// undoing an installer's bus-direction flip (config half of #3/#4).
@visibleForTesting
List<Map<String, dynamic>> buildSkikbilyBuses(
  WledHardwareConfig? currentConfig,
) {
  const int pixelsPerChannel = 100;
  const int defaultChannelCount = 4;
  // Per WLED busses.cpp, type 30 is SK6812 RGBW in current builds. Unified
  // with hardware_config_screen.dart (the manual editor). For RGBW bus types
  // WLED appends the W channel automatically, so order=1 sends R→G→B→W —
  // the Lumina default ("RGB" in WLED's UI dropdown).
  const int ledType = 30; // SK6812 RGBW
  const int colorOrder = 1; // RGB (W appended automatically on RGBW bus type)
  // Pins come from the existing config when present (preserves manual
  // installer overrides), else the SKIKBILY default GPIOs.
  const defaultPins = [16, 3, 1, 4];

  final existingBuses = currentConfig?.buses ?? const <WledLedBus>[];

  // PRESERVE-don't-overwrite the device's real bus count + per-bus pixel count
  // (#12, the `len` twin of the rev/gc clobber fixed in 625226f). A fresh WLED
  // ships with a single default bus; the moment Lumina (or an installer)
  // provisions the real channels it has ≥2 buses. So treat ≥2 buses as
  // "provisioned": keep its EXACT bus count and carry each bus's `len` through
  // unchanged. This function used to force 4 × 100 px unconditionally, which
  // overwrote a genuine 128/60 install to 100/100 on every install AND every
  // Re-sync (systemic — any install ≠ 100×4 got clobbered). A fresh /
  // unprovisioned device (null, or the lone WLED default bus) still gets the
  // full SKIKBILY 4-channel × 100 px profile so install provisions all
  // channels. len/pin/rev/skip are DEVICE-owned (preserve); type/order are
  // Lumina-asserted (override) — the same preserve-vs-assert split as 625226f.
  // (Deferred: unmodeled per-bus fields ref/rgbwm/freq/ledma still aren't
  // carried — they'd need a merge over the raw `hw.led.ins[]` rather than the
  // typed WledLedBus model. See report / #12 follow-up.)
  final bool provisioned = existingBuses.length >= 2;
  final int channelCount =
      provisioned ? existingBuses.length : defaultChannelCount;

  final List<Map<String, dynamic>> buses = [];
  int startAddress = 0;
  for (int i = 0; i < channelCount; i++) {
    final existing = i < existingBuses.length ? existingBuses[i] : null;
    // Preserve the device's real pixel count on a provisioned device; a fresh
    // bus has no meaningful len yet, so assert the SKIKBILY 100-px default.
    final int len =
        provisioned ? (existing?.len ?? pixelsPerChannel) : pixelsPerChannel;
    buses.add({
      'start': startAddress,
      'len': len,
      'pin': existing?.pin ?? [defaultPins[i]],
      'type': ledType,
      'order': colorOrder,
      'rev': existing?.rev ?? false, // PRESERVE manual bus direction (625226f)
      'skip': existing?.skip ?? 0, // PRESERVE manual skip
    });
    startAddress += len;
  }
  return buses;
}

/// Assembles the `hw.led` config object.
///
/// Gamma is intentionally NOT handled here. WLED stores gamma at
/// `cfg.light.gc`, never under `hw.led`, so a `gc` key in this payload would
/// be ignored by the firmware. Gamma is asserted separately by
/// [pushGammaConfig]. Do not reintroduce a `gc` parameter.
@visibleForTesting
Map<String, dynamic> buildLedConfig({
  required int total,
  required int maxpwr,
  required List<Map<String, dynamic>> ins,
}) {
  return {
    'total': total,
    'maxpwr': maxpwr,
    'ins': ins,
  };
}

/// True when the device's [current] bus list matches [proposed] on every
/// field Lumina writes (start/len/pin/type/order/rev/skip). Used to skip a
/// redundant hw.led push (and the WLED bus rebuild it triggers) on a no-op
/// Re-sync. Compares only written fields — unmodeled per-bus fields
/// (ref/rgbwm/freq/ledma) are intentionally ignored.
@visibleForTesting
bool ledInsMatches(
  List<WledLedBus> current,
  List<Map<String, dynamic>> proposed,
) {
  if (current.length != proposed.length) return false;
  for (var i = 0; i < current.length; i++) {
    final c = current[i];
    final p = proposed[i];
    if (c.start != p['start'] ||
        c.len != p['len'] ||
        c.type != p['type'] ||
        c.order != p['order'] ||
        c.skip != p['skip'] ||
        c.rev != p['rev']) {
      return false;
    }
    final pPin = (p['pin'] as List).map((e) => e as int).toList();
    if (c.pin.length != pPin.length) return false;
    for (var j = 0; j < pPin.length; j++) {
      if (c.pin[j] != pPin[j]) return false;
    }
  }
  return true;
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

/// The `/json/cfg` payload that asserts the NGL color-gamma standard
/// ([kNglLightGammaConfig] at `light.gc`) and disables the realtime gamma
/// bypass (`if.live.no-gc:false`). WLED deep-merges individual cfg keys, so
/// this leaves all other `light.*` and `if.live.*` fields untouched.
///
/// The `no-gc:false` half ensures DDP/Art-Net/realtime output (neighborhood
/// sync, multi-controller zones) is gamma-corrected too — otherwise a synced
/// house and a non-synced house would render the same color differently.
@visibleForTesting
Map<String, dynamic> buildGammaPayload() => <String, dynamic>{
      'light': {'gc': Map<String, dynamic>.from(kNglLightGammaConfig)},
      'if': {
        'live': {'no-gc': false},
      },
    };

/// True when [rawCfg] already has the NGL color-gamma standard AND the
/// realtime gamma bypass disabled — i.e. a Re-sync can skip the write.
/// Reads the CORRECT path (`light.gc`), not the legacy `hw.led.gc` fiction.
@visibleForTesting
bool gammaConfigSatisfied(Map<String, dynamic>? rawCfg) {
  final gc = (rawCfg?['light'] as Map?)?['gc'] as Map?;
  final noGc = ((rawCfg?['if'] as Map?)?['live'] as Map?)?['no-gc'];
  double? d(dynamic v) => (v as num?)?.toDouble();
  return gc != null &&
      d(gc['col']) == 2.8 &&
      d(gc['bri']) == 1.0 &&
      d(gc['val']) == 2.8 &&
      noGc == false;
}

/// Pushes the NGL color-gamma standard to `cfg.light.gc` and disables the
/// realtime gamma bypass (`cfg.if.live.no-gc`). Called during install and
/// Re-sync so every provisioned controller renders saturated colors correctly
/// regardless of its flash-time gamma default.
///
/// Idempotent: reads the current cfg first and skips the POST when the device
/// already matches ([gammaConfigSatisfied]), so a Re-sync of a correct device
/// writes nothing. On write, best-effort readback verifies `light.gc.col`.
Future<WledConfigPushResult> pushGammaConfig(
  String controllerIp, {
  bool verifyAfterWrite = true,
}) async {
  final cfg = await _fetchRawConfig(controllerIp);
  if (gammaConfigSatisfied(cfg)) {
    return WledConfigPushResult.skipped('color gamma already correct');
  }

  final result = await _postConfig(controllerIp, buildGammaPayload());
  if (!result.success) return result;
  if (!verifyAfterWrite) return result;

  // Best-effort readback on the field that matters for the wash-out (col).
  try {
    final after = await _fetchRawConfig(controllerIp);
    final col =
        (((after?['light'] as Map?)?['gc'] as Map?)?['col'] as num?)?.toDouble();
    if (col != 2.8) {
      return WledConfigPushResult.warning(
        'gamma write reported success but readback mismatch (light.gc.col=$col)',
      );
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
