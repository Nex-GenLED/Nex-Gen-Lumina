import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/models/controller_type.dart';

/// Parsed response from WLED GET /json/info.
class WledInfoResponse {
  /// Maximum number of segments the firmware supports (proxy for channel count).
  final int maxseg;

  /// Architecture string reported by the device (e.g. "esp32").
  final String arch;

  /// WLED firmware version string (e.g. "0.14.0").
  final String ver;

  /// The raw JSON map, kept for forward compatibility.
  final Map<String, dynamic> raw;

  const WledInfoResponse({
    required this.maxseg,
    required this.arch,
    required this.ver,
    this.raw = const {},
  });
}

/// Result of comparing a [WledInfoResponse] against an expected [ControllerType].
class ControllerValidationResult {
  /// Whether the reported capabilities match expectations.
  final bool isMatch;

  /// Human-readable warning when [isMatch] is false (null when matched).
  final String? warningMessage;

  /// Always `true` — mismatches are warnings, not blockers.
  final bool canProceed;

  const ControllerValidationResult({
    required this.isMatch,
    this.warningMessage,
    this.canProceed = true,
  });
}

/// Compares a live [WledInfoResponse] against the dealer-selected
/// [ControllerType] and returns a validation result.
///
/// This is a non-blocking check — [ControllerValidationResult.canProceed] is
/// always `true`.  Dealers may have intentionally mis-selected; the warning
/// lets them double-check.
ControllerValidationResult validateControllerMatch(
  WledInfoResponse info,
  ControllerType expected,
) {
  switch (expected) {
    case ControllerType.digOcta:
      if (info.maxseg < 8) {
        return ControllerValidationResult(
          isMatch: false,
          warningMessage:
              'This controller reports fewer than 8 channels '
              '(maxseg=${info.maxseg}). '
              'Verify hardware matches selection.',
        );
      }
      return const ControllerValidationResult(isMatch: true);

    case ControllerType.skikbily:
      if (info.maxseg < 4) {
        return ControllerValidationResult(
          isMatch: false,
          warningMessage:
              'This controller reports fewer than 4 channels '
              '(maxseg=${info.maxseg}). '
              'Verify hardware matches selection.',
        );
      }
      return const ControllerValidationResult(isMatch: true);

    case ControllerType.genericWled:
      return const ControllerValidationResult(isMatch: true);
  }
}

/// Converts an RGB color to RGBW format with auto-calculated white channel.
/// WLED handles GRB color order conversion internally when configured correctly.
/// We send standard [R, G, B, W] format.
///
/// [r], [g], [b]: Input RGB values (0-255)
/// [explicitWhite]: If provided, use this white value instead of auto-calculating
/// [forceZeroWhite]: If true, force W=0 (for pure saturated colors)
///
/// Note: WLED's "Use Gamma correction for color" setting should be enabled
/// on the device for accurate color rendering on RGBW LED strips.
///
/// Returns [R, G, B, W] array - WLED handles color order conversion
List<int> rgbToRgbw(int r, int g, int b, {int? explicitWhite, bool forceZeroWhite = false}) {
  int finalR = r;
  int finalG = g;
  int finalB = b;
  int finalW;

  if (explicitWhite != null) {
    // Explicit white value provided - use it directly
    finalW = explicitWhite.clamp(0, 255);
  } else if (forceZeroWhite) {
    // Force W=0 for pure saturated colors.
    // Color accuracy on RGBW strips is handled by WLED's gamma correction
    // (enabled in LED Preferences → "Use Gamma correction for color").
    finalW = 0;
  } else {
    // AUTO-CALCULATE W: Extract white component from RGB
    // W = min(R,G,B) - the "white" portion uses the dedicated W LED
    // Then subtract W from RGB to get the saturated color portion
    finalW = [r, g, b].reduce((a, b) => a < b ? a : b); // min(r, g, b)
    if (finalW > 0) {
      finalR = r - finalW;
      finalG = g - finalW;
      finalB = b - finalW;
    }
  }

  // Return standard [R, G, B, W] - WLED handles GRB conversion based on its config
  return [finalR, finalG, finalB, finalW];
}

class WledService implements WledRepository {
  final String baseUrl; // e.g., http://192.168.1.23
  late final bool _simulate;
  bool? _supportsRgbwCache;
  List<String> _simSegNames = ['Front', 'Roof', 'Garage'];

  // Local simulation state (used when host is 'mock' or '127.0.0.1')
  bool _simOn = true;
  int _simBri = 180;
  int _simSpeed = 128;
  Color _simColor = const Color(0xFFFFFFFF);

  WledService(this.baseUrl) {
    try {
      final uri = Uri.parse(baseUrl);
      final host = uri.host;
      _simulate = host == 'mock' || host == '127.0.0.1' || host == 'localhost';
    } catch (_) {
      _simulate = false;
    }
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>?> getState() async {
    if (_simulate) {
      return {
        'on': _simOn,
        'bri': _simBri,
        'seg': List.generate(_simSegNames.length, (i) => {
              'id': i,
              'n': _simSegNames[i],
              'sx': _simSpeed,
              'col': [
                [_simColor.red, _simColor.green, _simColor.blue, 0]
              ]
            })
      };
    }
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(_uri('/json/state'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
      debugPrint('WLED getState status ${res.statusCode}: $body');
    } catch (e) {
      debugPrint('WLED getState error: $e');
    }
    return null;
  }

  /// Fetches device info from GET /json/info and returns a parsed
  /// [WledInfoResponse], or `null` on failure.
  ///
  /// Existing callers that only need RGBW support or LED count should continue
  /// to use [supportsRgbw] / [getTotalLedCount] — this method is for richer
  /// inspection during pairing.
  Future<WledInfoResponse?> getInfo() async {
    if (_simulate) {
      return const WledInfoResponse(
        maxseg: 10,
        arch: 'esp32',
        ver: '0.14.0-sim',
      );
    }
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(_uri('/json/info'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final info = jsonDecode(body) as Map<String, dynamic>;
        final leds = info['leds'];
        final maxseg =
            (leds is Map && leds['maxseg'] is num)
                ? (leds['maxseg'] as num).toInt()
                : 0;
        final arch = info['arch'] as String? ?? '';
        final ver = info['ver'] as String? ?? '';
        return WledInfoResponse(
          maxseg: maxseg,
          arch: arch,
          ver: ver,
          raw: info,
        );
      }
      debugPrint('WLED getInfo status ${res.statusCode}: $body');
    } catch (e) {
      debugPrint('WLED getInfo error: $e');
    }
    return null;
  }

  Future<bool> setState({bool? on, int? brightness, int? speed, Color? color, int? white, bool? forceRgbwZeroWhite}) async {
    if (_simulate) {
      if (on != null) _simOn = on;
      if (brightness != null) _simBri = brightness.clamp(0, 255);
      if (speed != null) _simSpeed = speed.clamp(0, 255);
      if (color != null) _simColor = color;
      return true;
    }
    final Map<String, dynamic> payload = {};
    if (on != null) payload['on'] = on;
    if (brightness != null) payload['bri'] = brightness.clamp(0, 255);

    // Build a single segment update that can include both speed and color/white.
    final Map<String, dynamic> segUpdate = {'id': 0};
    if (speed != null) segUpdate['sx'] = speed.clamp(0, 255);
    if (color != null || white != null) {
      final rgbw = rgbToRgbw(
        color?.red ?? 0,
        color?.green ?? 0,
        color?.blue ?? 0,
        explicitWhite: white,
        forceZeroWhite: forceRgbwZeroWhite == true,
      );
      segUpdate['col'] = [rgbw];
    }
    if (segUpdate.length > 1) {
      payload['seg'] = [segUpdate];
    }

    return _postJson(payload);
  }

  Future<bool> _postJson(Map<String, dynamic> data) async {
    if (_simulate) {
      // Best-effort: update local state from payload and pretend success.
      try {
        final on = data['on'];
        if (on is bool) _simOn = on;
        final bri = data['bri'];
        if (bri is int) _simBri = bri.clamp(0, 255);
        final seg = data['seg'];
        if (seg is List && seg.isNotEmpty) {
          for (final s in seg) {
            if (s is! Map) continue;
            final name = s['n'];
            final sid = s['id'];
            if (name is String && sid is num) {
              final idx = sid.toInt();
              if (idx >= 0 && idx < _simSegNames.length) _simSegNames[idx] = name;
            }
            final sx = s['sx'];
            if (sx is int) _simSpeed = sx.clamp(0, 255);
            final col = s['col'];
            if (col is List && col.isNotEmpty && col.first is List) {
              final c = col.first as List;
              if (c.length >= 3) {
                _simColor = Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt());
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error in WledService applyJson simulation color parse: $e');
      }
      return true;
    }

    // Use JSON API (POST /json/state) - same as WLED web interface
    try {
      final body = jsonEncode(data);
      debugPrint('📤 WLED POST /json/state');
      debugPrint('   Payload: $body');

      final response = await http.post(
        _uri('/json/state'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 WLED Response: ${response.statusCode}');
      debugPrint('   Body: ${response.body}');

      debugPrint('🔍 BridgeRouter: send result=${response.statusCode}, error=none');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ WLED JSON API success');
        return true;
      }
      debugPrint('❌ WLED JSON API error ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('🔍 BridgeRouter: send result=EXCEPTION, error=$e');
    }

    return false;
  }

  /// Public helper to send an arbitrary WLED JSON payload to /json
  Future<bool> applyJson(Map<String, dynamic> payload) =>
      _postJson(normalizeWledPayload(payload));

  Future<bool> _postConfig(Map<String, dynamic> data) async {
    if (_simulate) {
      // Accept and store nothing in simulation; just acknowledge success.
      debugPrint('📤 WLED /json/cfg (simulated): ${jsonEncode(data)}');
      return true;
    }
    try {
      final body = jsonEncode(data);
      debugPrint('📤 WLED POST /json/cfg');
      debugPrint('   Payload: $body');

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(_uri('/json/cfg'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final resBody = await res.transform(utf8.decoder).join();
      client.close(force: true);

      debugPrint('📥 WLED /json/cfg response: ${res.statusCode}');
      if (resBody.isNotEmpty) debugPrint('   Body: $resBody');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('✅ WLED /json/cfg success');
        return true;
      }
      debugPrint('❌ WLED /json/cfg error ${res.statusCode}: $resBody');
    } catch (e) {
      debugPrint('❌ WLED /json/cfg exception: $e');
    }
    return false;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) => _postConfig(cfg);

  @override
  Future<WledHardwareConfig?> getConfig() async {
    if (_simulate) {
      // Return a simulated 2-bus config
      return const WledHardwareConfig(
        totalLeds: 200,
        maxPowerMw: 30000,
        buses: [
          WledLedBus(pin: [0], start: 0, len: 100, type: 30, order: 1),
          WledLedBus(pin: [1], start: 100, len: 100, type: 30, order: 1),
        ],
      );
    }
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(_uri('/json/cfg'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final cfg = jsonDecode(body) as Map<String, dynamic>;
        final hw = cfg['hw'];
        if (hw is! Map) return null;
        final led = hw['led'];
        if (led is! Map) return null;

        final totalLeds = (led['total'] is num) ? (led['total'] as num).toInt() : 0;
        final maxPwr = (led['maxpwr'] is num) ? (led['maxpwr'] as num).toInt() : 30000;

        final ins = led['ins'];
        final List<WledLedBus> buses = [];
        if (ins is List) {
          for (final entry in ins) {
            if (entry is Map<String, dynamic>) {
              buses.add(WledLedBus.fromMap(entry));
            }
          }
        }

        return WledHardwareConfig(
          totalLeds: totalLeds,
          maxPowerMw: maxPwr,
          buses: buses,
        );
      }
      debugPrint('WLED getConfig status ${res.statusCode}: $body');
    } catch (e) {
      debugPrint('WLED getConfig error: $e');
    }
    return null;
  }

  /// Uploads a ledmap.json file to the device using the /edit API.
  /// Returns true on success.
  Future<bool> uploadLedMapJson(String jsonContent) async {
    if (_simulate) {
      return true;
    }
    try {
      final boundary = '----dart-ar-ledmap-${DateTime.now().millisecondsSinceEpoch}';
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(_uri('/edit'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');

      // Build multipart body manually: data (file) + path
      final builder = BytesBuilder();
      void write(String s) => builder.add(utf8.encode(s));

      // Part 1: data (file)
      write('--$boundary\r\n');
      write('Content-Disposition: form-data; name="data"; filename="ledmap.json"\r\n');
      write('Content-Type: application/json\r\n\r\n');
      write(jsonContent);
      write('\r\n');

      // Part 2: path
      write('--$boundary\r\n');
      write('Content-Disposition: form-data; name="path"\r\n\r\n');
      write('/ledmap.json');
      write('\r\n');

      // End
      write('--$boundary--\r\n');

      req.add(builder.takeBytes());
      final res = await req.close().timeout(const Duration(seconds: 15));
      client.close(force: true);
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      final body = await res.transform(utf8.decoder).join();
      debugPrint('WLED /edit upload error ${res.statusCode}: $body');
    } catch (e) {
      debugPrint('WLED /edit upload exception: $e');
    }
    return false;
  }

  /// Best-effort: enable receiving UDP/DDP sync on this device.
  /// Not all keys are supported across firmware; unknown keys are ignored by WLED.
  Future<bool> configureSyncReceiver() async {
    if (_simulate) return true;
    // WLED typically uses `udpn.recv` for UDP sync receive. We enable that here.
    final payload = {
      'udpn': {'recv': true}
    };
    final ok = await _postJson(payload);
    if (!ok) debugPrint('configureSyncReceiver failed for $baseUrl');
    return ok;
  }

  /// Best-effort: configure device to send DDP/UDP sync.
  /// If targets is empty we still enable broadcast sending.
  Future<bool> configureSyncSender({List<String> targets = const [], int ddpPort = 4048}) async {
    if (_simulate) return true;
    bool allOk = true;
    // 1) Enable UDP sync sending
    final udpOk = await _postJson({'udpn': {'send': true}});
    allOk = allOk && udpOk;

    // 2) Attempt to hint DDP settings (some builds honor this)
    final ddpPayload = {
      'ddp': {
        'en': true,
        'port': ddpPort,
        if (targets.isNotEmpty) 'targets': targets,
      }
    };
    final ddpOk = await _postJson(ddpPayload);
    allOk = allOk && ddpOk;

    if (!allOk) debugPrint('configureSyncSender had partial failure for $baseUrl');
    return allOk;
  }

  @override
  List<WledPreset> getPresets() => const [];

  /// Cached preset names from GET /json/presets. Cleared on dispose.
  Map<int, String>? _presetNamesCache;

  @override
  Future<Map<int, String>> fetchPresetNames() async {
    if (_presetNamesCache != null) return _presetNamesCache!;

    if (_simulate) {
      _presetNamesCache = {1: 'Warm White', 2: 'Chill', 3: 'Party'};
      return _presetNamesCache!;
    }

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(_uri('/json/presets'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final result = <int, String>{};
          for (final entry in decoded.entries) {
            final id = int.tryParse(entry.key.toString());
            if (id != null && id > 0 && entry.value is Map) {
              final name = entry.value['n'];
              if (name is String && name.trim().isNotEmpty) {
                result[id] = name.trim();
              }
            }
          }
          _presetNamesCache = result;
          debugPrint('📋 Fetched ${result.length} WLED preset names');
          return result;
        }
      }
      debugPrint('WLED fetchPresetNames status ${res.statusCode}');
    } catch (e) {
      debugPrint('WLED fetchPresetNames error: $e');
    }
    return const {};
  }

  @override
  void invalidatePresetCache() {
    _presetNamesCache = null;
  }

  @override
  void reset() {
    // Drop capability + preset caches so the next reconnect re-queries
    // the device. HttpClient instances are created per-request and already
    // closed with force:true, so there is no shared connection pool owned
    // by this service to tear down.
    _supportsRgbwCache = null;
    _presetNamesCache = null;
    debugPrint('🔄 WledService.reset(): caches cleared for $baseUrl');
  }

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    if (presetId < 1 || presetId > 250) {
      debugPrint('savePreset: Invalid preset ID $presetId (must be 1-250)');
      return false;
    }

    if (_simulate) {
      debugPrint('📤 WLED savePreset (simulated): preset $presetId');
      return true;
    }

    try {
      // WLED saves presets via /json/state with "psave" field
      // The "psave" field tells WLED to save the included state to that preset slot
      final payload = <String, dynamic>{
        ...state,
        'psave': presetId,
      };

      // Add preset name if provided (WLED stores this in the preset)
      if (presetName != null && presetName.isNotEmpty) {
        payload['n'] = presetName;
      }

      debugPrint('📤 WLED savePreset: Saving to preset $presetId');
      debugPrint('   Payload: ${jsonEncode(payload)}');

      final response = await http.post(
        _uri('/json/state'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 WLED savePreset response: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ WLED preset $presetId saved successfully');
        // Drop the cached preset-name map so the next Now Playing lookup
        // picks up the newly saved name.
        _presetNamesCache = null;
        return true;
      }
      debugPrint('❌ WLED savePreset error ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('❌ WLED savePreset exception: $e');
    }
    return false;
  }

  @override
  Future<bool> loadPreset(int presetId) async {
    if (presetId < 1 || presetId > 250) {
      debugPrint('loadPreset: Invalid preset ID $presetId (must be 1-250)');
      return false;
    }

    if (_simulate) {
      debugPrint('📤 WLED loadPreset (simulated): preset $presetId');
      return true;
    }

    try {
      // WLED loads presets via /json/state with "ps" field
      final payload = {'ps': presetId};

      debugPrint('📤 WLED loadPreset: Loading preset $presetId');

      final response = await http.post(
        _uri('/json/state'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ WLED preset $presetId loaded successfully');
        return true;
      }
      debugPrint('❌ WLED loadPreset error ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('❌ WLED loadPreset exception: $e');
    }
    return false;
  }

  @override
  Future<bool> supportsRgbw() async {
    if (_supportsRgbwCache != null) return _supportsRgbwCache!;
    if (_simulate) {
      _supportsRgbwCache = true;
      return true;
    }
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(_uri('/json/info'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final info = jsonDecode(body) as Map<String, dynamic>;
        final leds = info['leds'];
        bool rgbw = false;
        if (leds is Map) {
          final v = leds['rgbw'];
          if (v is bool) rgbw = v;
        }
        _supportsRgbwCache = rgbw;
        return rgbw;
      }
    } catch (e) {
      debugPrint('WLED supportsRgbw error: $e');
    }
    _supportsRgbwCache = false;
    return false;
  }

  @override
  Future<List<WledSegment>> fetchSegments() async {
    final data = await getState();
    final List<WledSegment> result = [];
    if (data == null) return result;
    try {
      final seg = data['seg'];
      if (seg is List) {
        for (var i = 0; i < seg.length; i++) {
          final m = seg[i];
          if (m is Map) result.add(WledSegment.fromMap(m, i));
        }
      } else if (seg is Map) {
        result.add(WledSegment.fromMap(seg, 0));
      }
    } catch (e) {
      debugPrint('fetchSegments parse error: $e');
    }
    return result;
  }

  @override
  Future<bool> renameSegment({required int id, required String name}) async {
    final payload = {
      'seg': [
        {'id': id, 'n': name}
      ]
    };
    return _postJson(payload);
  }

  @override
  Future<bool> applyToSegments({required List<int> ids, Color? color, int? white, int? fx, int? speed, int? intensity}) async {
    if (ids.isEmpty) return true;
    final List<Map<String, dynamic>> segs = [];
    for (final id in ids) {
      final m = <String, dynamic>{'id': id};
      if (fx != null) m['fx'] = fx;
      if (speed != null) m['sx'] = speed.clamp(0, 255);
      if (intensity != null) m['ix'] = intensity.clamp(0, 255);
      if (color != null) {
        // Use helper for RGBW conversion with auto-white calculation
        final rgbw = rgbToRgbw(color.red, color.green, color.blue, explicitWhite: white);
        m['col'] = [rgbw];
      }
      segs.add(m);
    }
    return _postJson(normalizeWledPayload({'seg': segs}));
  }

  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async {
    if (_simulate) {
      debugPrint('📤 WLED updateSegmentConfig (simulated): seg=$segmentId start=$start stop=$stop');
      return true;
    }

    // Build segment update payload
    // WLED uses 'start' and 'stop' for segment boundaries
    final Map<String, dynamic> segUpdate = {'id': segmentId};
    if (start != null) segUpdate['start'] = start;
    if (stop != null) segUpdate['stop'] = stop;

    if (segUpdate.length <= 1) {
      // Nothing to update
      return true;
    }

    final payload = {
      'seg': [segUpdate]
    };

    debugPrint('📤 WLED updateSegmentConfig: $payload');
    return _postJson(payload);
  }

  @override
  Future<int?> getTotalLedCount() async {
    if (_simulate) {
      // Return a simulated count
      return 200;
    }

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(_uri('/json/info'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final info = jsonDecode(body) as Map<String, dynamic>;
        final leds = info['leds'];
        if (leds is Map) {
          // WLED returns total LED count in leds.count
          final count = leds['count'];
          if (count is int) return count;
          if (count is num) return count.toInt();
        }
      }
    } catch (e) {
      debugPrint('WLED getTotalLedCount error: $e');
    }
    return null;
  }
}
