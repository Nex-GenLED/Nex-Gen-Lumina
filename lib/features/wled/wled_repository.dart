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

  /// Fetches the full hardware LED configuration from the device.
  /// Returns null if the device doesn't support this or the fetch fails.
  Future<WledHardwareConfig?> getConfig() async => null;

  /// Returns true if device supports RGBW (has a dedicated white channel)
  Future<bool> supportsRgbw() async => false;

  /// Reads segments from /json/state and returns a list of WledSegment items
  Future<List<WledSegment>> fetchSegments() async => const <WledSegment>[];

  /// Renames a segment by id. Best-effort using the `n` field supported by WLED.
  Future<bool> renameSegment({required int id, required String name}) async => false;

  /// Applies one payload (color/effect/speed) to multiple segments simultaneously.
  Future<bool> applyToSegments({required List<int> ids, Color? color, int? white, int? fx, int? speed, int? intensity}) async => false;

  /// Updates segment configuration (start, stop position and/or length).
  /// This is used to sync pixel counts from the app to the WLED device.
  /// Returns true on success.
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async => false;

  /// Gets the total LED count configured on the device.
  /// Returns null if unable to fetch.
  Future<int?> getTotalLedCount() async => null;

  /// Saves the given state as a preset on the device.
  /// [presetId] should be 1-250 (WLED supports up to 250 presets).
  /// [state] is the WLED JSON state to save (on, bri, seg, fx, etc.).
  /// [presetName] is optional human-readable name for the preset.
  /// Returns true on success.
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async => false;

  /// Loads a preset by ID, applying it immediately.
  /// Returns true on success.
  Future<bool> loadPreset(int presetId) async => false;

  /// Optional: presets for demo mode. Real implementations may return empty.
  List<WledPreset> getPresets() => const [];

  /// Fetches all preset names from the device via GET /json/presets.
  /// Returns a map of preset ID → preset name.
  /// Implementations should cache the result to avoid repeated fetches.
  Future<Map<int, String>> fetchPresetNames() async => const {};

  /// Clears any cached preset-name map so the next [fetchPresetNames] call
  /// refetches from the device. Call this after saving a new preset or when
  /// the user manually refreshes. Default is a no-op for implementations
  /// that don't cache.
  void invalidatePresetCache() {}

  /// Drops all cached device state (capability flags, preset names) and any
  /// stale connection-level resources so the next request re-establishes
  /// fresh state. Called on app resume to recover from sockets that iOS
  /// invalidated during suspend. Default is a no-op.
  void reset() {}
}

/// A single LED output bus (hardware channel) on the WLED controller.
/// Maps to one entry in the `hw.led.ins` array from GET /json/cfg.
class WledLedBus {
  final List<int> pin;   // GPIO pin(s) for this bus
  final int start;       // 0-based LED start index
  final int len;         // number of LEDs on this bus
  final int type;        // LED type (e.g. 30 = SK6812 RGBW)
  final int order;       // color order (e.g. 1 = GRB)
  final bool rev;        // reversed?
  final int skip;        // number of LEDs to skip at start

  const WledLedBus({
    required this.pin,
    this.start = 0,
    required this.len,
    this.type = 30,
    this.order = 1,
    this.rev = false,
    this.skip = 0,
  });

  factory WledLedBus.fromMap(Map<String, dynamic> m) {
    List<int> pin = [0];
    final rawPin = m['pin'];
    if (rawPin is List) {
      pin = rawPin.whereType<num>().map((n) => n.toInt()).toList();
    } else if (rawPin is num) {
      pin = [rawPin.toInt()];
    }
    return WledLedBus(
      pin: pin,
      start: (m['start'] is num) ? (m['start'] as num).toInt() : 0,
      len: (m['len'] is num) ? (m['len'] as num).toInt() : 0,
      type: (m['type'] is num) ? (m['type'] as num).toInt() : 30,
      order: (m['order'] is num) ? (m['order'] as num).toInt() : 1,
      rev: m['rev'] == true,
      skip: (m['skip'] is num) ? (m['skip'] as num).toInt() : 0,
    );
  }
}

/// Top-level hardware LED configuration from GET /json/cfg → hw.led.
class WledHardwareConfig {
  final int totalLeds;
  final int maxPowerMw;         // milliwatts (WLED's maxpwr field)
  final List<WledLedBus> buses; // hw.led.ins entries

  const WledHardwareConfig({
    required this.totalLeds,
    this.maxPowerMw = 30000,
    this.buses = const [],
  });
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
