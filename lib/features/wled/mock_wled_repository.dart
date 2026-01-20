import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

/// A mock repository that simulates a WLED device entirely in-memory.
class MockWledRepository implements WledRepository {
  bool _on = true;
  int _bri = 180; // 0-255
  int _speed = 128; // 0-255
  Color _color = const Color(0xFFFFFFFF);
  int _white = 0; // 0-255 warm white channel
  String? _lastLedMap;
  final List<String> _segNames = ['Segment 0', 'Segment 1', 'Segment 2'];

  final List<WledPreset> _presets = const [
    WledPreset(name: 'Warm White Architectural', json: {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'fx': 0, // Solid
          'pal': 0,
          'col': [
            [255, 244, 229, 0]
          ]
        }
      ]
    }),
    WledPreset(name: 'Candy Cane Motion', json: {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'fx': 12, // Chase
          'pal': 3, // Red/White
          'sx': 180,
          'ix': 200
        }
      ]
    }),
    WledPreset(name: 'July 4th Sparkle', json: {
      'on': true,
      'bri': 230,
      'seg': [
        {
          'id': 0,
          'fx': 120, // Sparkle
          'pal': 6, // Red/White/Blue
          'sx': 170,
          'ix': 180
        }
      ]
    }),
    WledPreset(name: 'Spooky Halloween Lightning', json: {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'fx': 76, // Lightning
          'pal': 5, // Purple/Orange
          'sx': 210,
          'ix': 200
        }
      ]
    }),
    WledPreset(name: 'Calm Ocean Wave', json: {
      'on': true,
      'bri': 170,
      'seg': [
        {
          'id': 0,
          'fx': 9, // Color Waves
          'pal': 11, // Blues
          'sx': 120,
          'ix': 140
        }
      ]
    }),
  ];

  @override
  Future<Map<String, dynamic>?> getState() async {
    // Simulate fast local update
    return {
      'on': _on,
      'bri': _bri,
      'seg': List.generate(_segNames.length, (i) => {
            'id': i,
            'n': _segNames[i],
            'sx': _speed,
            'col': [
              // Expose 4-tuple to mirror RGBW-capable device in demo
              [_color.red, _color.green, _color.blue, _white]
            ]
          })
    };
  }

  @override
  Future<bool> setState({bool? on, int? brightness, int? speed, Color? color, int? white, bool? forceRgbwZeroWhite}) async {
    if (on != null) _on = on;
    if (brightness != null) _bri = brightness.clamp(0, 255);
    if (speed != null) _speed = speed.clamp(0, 255);
    if (color != null) _color = color;
    // If forceRgbwZeroWhite is true, set white to 0 for pure RGB colors
    if (forceRgbwZeroWhite == true) {
      _white = 0;
    } else if (white != null) {
      _white = white.clamp(0, 255);
    }
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    // Best-effort: adopt known keys to update local state
    try {
      final on = payload['on'];
      if (on is bool) _on = on;
      final bri = payload['bri'];
      if (bri is int) _bri = bri.clamp(0, 255);
      // segments
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        for (final s in seg) {
          if (s is! Map) continue;
          final sid = s['id'];
          if (sid is num) {
            final i = sid.toInt();
            final n = s['n'];
            if (n is String && i >= 0 && i < _segNames.length) _segNames[i] = n;
          }
          final sx = s['sx'];
          if (sx is int) _speed = sx.clamp(0, 255);
          final col = s['col'];
          if (col is List && col.isNotEmpty && col.first is List) {
            final c = col.first as List;
            if (c.length >= 4) {
              _color = Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt());
              _white = (c[3] as num).toInt().clamp(0, 255);
            } else if (c.length >= 3) {
              _color = Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt());
            }
          }
        }
      }
      return true;
    } catch (_) {
      return true; // still succeed visually
    }
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    // Accept any config in mock. In a real device this hits /json/cfg.
    debugPrint('MockWLED applyConfig: ${cfg.keys.join(', ')}');
    return true;
  }

  @override
  Future<bool> uploadLedMapJson(String jsonContent) async {
    _lastLedMap = jsonContent;
    return true;
  }

  @override
  Future<bool> configureSyncReceiver() async => true;

  @override
  Future<bool> configureSyncSender({List<String> targets = const [], int ddpPort = 4048}) async => true;

  @override
  List<WledPreset> getPresets() => _presets;

  @override
  Future<bool> supportsRgbw() async => true;

  @override
  Future<List<WledSegment>> fetchSegments() async => List.generate(_segNames.length, (i) => WledSegment(id: i, name: _segNames[i]));

  @override
  Future<bool> renameSegment({required int id, required String name}) async {
    if (id < 0 || id >= _segNames.length) return false;
    _segNames[id] = name;
    return true;
  }

  @override
  Future<bool> applyToSegments({required List<int> ids, Color? color, int? white, int? fx, int? speed, int? intensity}) async {
    if (color != null) _color = color;
    if (white != null) _white = white.clamp(0, 255);
    if (speed != null) _speed = speed.clamp(0, 255);
    // ignore fx/intensity in mock
    return true;
  }
}
