// #187 — new buses take the canonical Skikbily outputs (FACTS T-X5): output
// 1 = GPIO 2, 2 = GPIO 14, 3 = GPIO 16, 4 = GPIO 18, never more than four.
//
// The hardware editor used to assign a NEW port from the Dig-Octa list
// 0,1,2,3,4,5,12,13 (a fourth port got GPIO 3, which matches no output on the
// installed units) and the Nex-Gen Standard push's own fallback was a
// different four. Only new buses change: a device's existing buses keep the
// pins they report. The push side is pinned in wled_config_pusher_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/hardware_config_screen.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';

const _on = [true, true, true, true, true, false, false, false];
const _counts = [100, 100, 100, 100, 50, 0, 0, 0];

void main() {
  test('the canonical outputs are 2, 14, 16, 18 — by position, four only', () {
    expect(kCanonicalOutputPins, [2, 14, 16, 18]);
    expect(kCanonicalOutputPins.length, 4);
  });

  test('editor ports default to the canonical outputs, then to no output', () {
    expect(defaultPortPins(8), [2, 14, 16, 18, -1, -1, -1, -1]);
    expect(defaultPortPins(4), [2, 14, 16, 18]);
    expect(defaultPortPins(2), [2, 14]);
    expect(kNoOutputPin, -1);
  });

  test('a NEW fifth port never becomes a bus; the first four take 2/14/16/18',
      () {
    final buses = buildHardwareConfigBuses(
      enabled: _on,
      counts: _counts,
      pins: defaultPortPins(8),
      ledType: 30,
    );
    expect(buses.length, 4, reason: 'port 5 is on with 50 LEDs but has no output');
    expect(buses.map((b) => (b['pin'] as List).first), [2, 14, 16, 18]);
    expect(buses.map((b) => b['start']), [0, 100, 200, 300]);
  });

  test('an existing fifth bus is kept on the pin the device reports', () {
    final device = [
      for (final p in const [2, 14, 16, 18, 21]) WledLedBus(pin: [p], len: 100),
    ];
    final buses = buildHardwareConfigBuses(
      enabled: _on,
      counts: _counts,
      pins: const [2, 14, 16, 18, 21, -1, -1, -1],
      ledType: 30,
      originalBuses: device,
    );
    expect(buses.map((b) => (b['pin'] as List).first), [2, 14, 16, 18, 21]);
  });

  test('an existing device is not migrated: its reported pins win over the '
      'defaults', () {
    // The screen copies each reported pin over the default for that port
    // (_applyHardwareConfig); the builder then writes what the device had.
    final device = [
      WledLedBus(pin: const [0], len: 162),
      WledLedBus(pin: const [1], len: 128),
    ];
    final pins = defaultPortPins(8);
    for (var i = 0; i < device.length; i++) {
      if (device[i].pin.isNotEmpty) pins[i] = device[i].pin.first;
    }
    final buses = buildHardwareConfigBuses(
      enabled: const [true, true, false, false, false, false, false, false],
      counts: const [162, 128, 0, 0, 0, 0, 0, 0],
      pins: pins,
      ledType: 30,
      originalBuses: device,
    );
    expect(buses.map((b) => (b['pin'] as List).first), [0, 1]);
    // A third port added later on that device would take output 3.
    expect(pins[2], 16);
  });
}
