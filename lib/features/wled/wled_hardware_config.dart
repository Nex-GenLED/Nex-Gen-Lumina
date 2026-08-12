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

/// Parse `hw.led` out of a raw `GET /json/cfg` map.
///
/// **One parser, two callers.** `WledService.getConfig` (which performs its own
/// cfg fetch, feeding `deviceHardwareConfigProvider`) and
/// `ControllerClockInfo.fromMaps` (which reuses the cfg the defaults healer has
/// already fetched) both come through here, so the bus list means the same
/// thing whichever path produced it. Extracted for the healer rewire — the
/// point of that change was to stop crossing a provider boundary, NOT to gain a
/// second implementation of this.
///
/// Returns **null** when `hw.led` is absent or the wrong shape — "we could not
/// read the hardware block". That is deliberately distinct from a config whose
/// `buses` list is empty, which means "we read it and this controller reports
/// no LED outputs". Collapsing the two is the defect class that produced #63:
/// `deviceHardwareConfigProvider` returns null for no-repo, unreachable,
/// parse-failed AND no-buses alike, so no caller can tell them apart.
WledHardwareConfig? hardwareConfigFromCfg(Map<String, dynamic>? cfg) {
  if (cfg == null) return null;
  final hw = cfg['hw'];
  if (hw is! Map) return null;
  final led = hw['led'];
  if (led is! Map) return null;

  final buses = <WledLedBus>[];
  final ins = led['ins'];
  if (ins is List) {
    for (final entry in ins) {
      if (entry is Map) {
        buses.add(WledLedBus.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
  }

  return WledHardwareConfig(
    totalLeds: (led['total'] is num) ? (led['total'] as num).toInt() : 0,
    maxPowerMw: (led['maxpwr'] is num) ? (led['maxpwr'] as num).toInt() : 30000,
    buses: buses,
  );
}
