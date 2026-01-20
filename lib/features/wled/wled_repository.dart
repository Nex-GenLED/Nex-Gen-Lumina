import 'package:flutter/material.dart';

/// Abstraction for controlling a WLED device.
/// Implementations: real network service and a mock for Demo Mode.
abstract class WledRepository {
  Future<Map<String, dynamic>?> getState();
  Future<bool> setState({bool? on, int? brightness, int? speed, Color? color, int? white, bool? forceRgbwZeroWhite});
  Future<bool> applyJson(Map<String, dynamic> payload);
  /// Posts configuration payloads to /json/cfg (e.g., timers)
  Future<bool> applyConfig(Map<String, dynamic> cfg);
  Future<bool> uploadLedMapJson(String jsonContent);
  Future<bool> configureSyncReceiver();
  Future<bool> configureSyncSender({List<String> targets = const [], int ddpPort = 4048});

  /// Returns true if device supports RGBW (has a dedicated white channel)
  Future<bool> supportsRgbw() async => false;

  /// Reads segments from /json/state and returns a list of WledSegment items
  Future<List<WledSegment>> fetchSegments() async => const <WledSegment>[];

  /// Renames a segment by id. Best-effort using the `n` field supported by WLED.
  Future<bool> renameSegment({required int id, required String name}) async => false;

  /// Applies one payload (color/effect/speed) to multiple segments simultaneously.
  Future<bool> applyToSegments({required List<int> ids, Color? color, int? white, int? fx, int? speed, int? intensity}) async => false;

  /// Optional: presets for demo mode. Real implementations may return empty.
  List<WledPreset> getPresets() => const [];
}

class WledPreset {
  final String name;
  final Map<String, dynamic> json;
  const WledPreset({required this.name, required this.json});
}

/// Channel/segment model used by Zone Control
/// In WLED terminology these are "segments", but we present them as "channels" to users.
class WledSegment {
  final int id;
  final String name;
  final int start; // 0-indexed first LED
  final int stop;  // 0-indexed last LED (exclusive, so length = stop - start)

  const WledSegment({
    required this.id,
    required this.name,
    this.start = 0,
    this.stop = 0,
  });

  /// Number of LEDs in this channel
  int get ledCount => (stop - start).clamp(0, 10000);

  factory WledSegment.fromMap(Map m, int fallbackIndex) {
    try {
      final id = (m['id'] is num) ? (m['id'] as num).toInt() : fallbackIndex;
      String name = 'Channel ${id + 1}'; // 1-indexed for user display
      final n = m['n'];
      if (n is String && n.trim().isNotEmpty) name = n.trim();

      // Parse LED range from WLED segment data
      final start = (m['start'] is num) ? (m['start'] as num).toInt() : 0;
      final stop = (m['stop'] is num) ? (m['stop'] as num).toInt() : 0;

      return WledSegment(id: id, name: name, start: start, stop: stop);
    } catch (_) {
      return WledSegment(id: fallbackIndex, name: 'Channel ${fallbackIndex + 1}');
    }
  }
}
