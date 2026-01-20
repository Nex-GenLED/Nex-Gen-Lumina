import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nexgen_command/features/wled/wled_repository.dart';

/// Converts an RGB color to RGBW format with auto-calculated white channel.
/// WLED handles GRB color order conversion internally when configured correctly.
/// We send standard [R, G, B, W] format.
///
/// [r], [g], [b]: Input RGB values (0-255)
/// [explicitWhite]: If provided, use this white value instead of auto-calculating
/// [forceZeroWhite]: If true, force W=0 (for pure saturated colors)
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
    // Force W=0 for pure saturated colors
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
  String? _simLedMap;

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
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(_uri('/json/state'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 5));
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
      } catch (_) {}
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
      ).timeout(const Duration(seconds: 5));

      debugPrint('📥 WLED Response: ${response.statusCode}');
      debugPrint('   Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ WLED JSON API success');
        return true;
      }
      debugPrint('❌ WLED JSON API error ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('❌ WLED JSON API exception: $e');
    }

    return false;
  }

  /// Public helper to send an arbitrary WLED JSON payload to /json
  Future<bool> applyJson(Map<String, dynamic> payload) => _postJson(payload);

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

  /// Uploads a ledmap.json file to the device using the /edit API.
  /// Returns true on success.
  Future<bool> uploadLedMapJson(String jsonContent) async {
    if (_simulate) {
      _simLedMap = jsonContent;
      return true;
    }
    try {
      final boundary = '----dart-ar-ledmap-${DateTime.now().millisecondsSinceEpoch}';
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.postUrl(_uri('/edit'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');

      // Build multipart body manually: data (file) + path
      final builder = BytesBuilder();
      void write(String s) => builder.add(utf8.encode(s));
      void writeBytes(List<int> b) => builder.add(b);

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
      final res = await req.close().timeout(const Duration(seconds: 5));
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

  @override
  Future<bool> supportsRgbw() async {
    if (_supportsRgbwCache != null) return _supportsRgbwCache!;
    if (_simulate) {
      _supportsRgbwCache = true;
      return true;
    }
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(_uri('/json/info'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 5));
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
    return _postJson({'seg': segs});
  }
}
