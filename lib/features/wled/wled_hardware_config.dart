// Pure-Dart (no flutter / dart:ui) hardware-config data classes, extracted from
// wled_repository.dart so the bench/ CLI can parse GET /json/cfg → hw.led without
// pulling in the Flutter-coupled repository interface. wled_repository.dart
// re-exports these, so existing importers are unaffected.

/// A single LED output bus (hardware channel) on the WLED controller.
/// Maps to one entry in the `hw.led.ins` array from GET /json/cfg.
class WledLedBus {
  final List<int> pin; // GPIO pin(s) for this bus
  final int start; // 0-based LED start index
  final int len; // number of LEDs on this bus
  final int type; // LED type (e.g. 30 = SK6812 RGBW)
  final int order; // color order (e.g. 1 = GRB)
  final bool rev; // reversed?
  final int skip; // number of LEDs to skip at start

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
  final int maxPowerMw; // milliwatts (WLED's maxpwr field)
  final List<WledLedBus> buses; // hw.led.ins entries

  const WledHardwareConfig({
    required this.totalLeds,
    this.maxPowerMw = 30000,
    this.buses = const [],
  });
}
