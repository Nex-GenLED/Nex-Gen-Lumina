import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/hardware_config_screen.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

void main() {
  group('buildHardwareConfigBuses — bus rev preservation (config half of #3/#4)', () {
    test('preserves rev from original buses by port index', () {
      final original = [
        WledLedBus(pin: [2], len: 128, rev: true),
        WledLedBus(pin: [14], len: 10, rev: false),
      ];
      final buses = buildHardwareConfigBuses(
        enabled: const [true, true, false, false, false, false, false, false],
        counts: const [128, 10, 0, 0, 0, 0, 0, 0],
        pins: const [2, 14, 0, 0, 0, 0, 0, 0],
        ledType: 30,
        originalBuses: original,
      );

      expect(buses.length, 2);
      expect(buses[0]['rev'], true, reason: 'manual flip must survive save');
      expect(buses[1]['rev'], false);
    });

    test('new bus beyond the original config defaults to rev:false', () {
      final original = [WledLedBus(pin: [2], len: 100, rev: true)];
      final buses = buildHardwareConfigBuses(
        enabled: const [true, true, false, false, false, false, false, false],
        counts: const [100, 50, 0, 0, 0, 0, 0, 0],
        pins: const [2, 3, 0, 0, 0, 0, 0, 0],
        ledType: 30,
        originalBuses: original,
      );

      expect(buses[0]['rev'], true); // preserved
      expect(buses[1]['rev'], false); // port index >= original.length
    });

    test('null originalBuses (new device) → all rev:false, sane defaults', () {
      final buses = buildHardwareConfigBuses(
        enabled: const [true, false, false, false, false, false, false, false],
        counts: const [30, 0, 0, 0, 0, 0, 0, 0],
        pins: const [0, 1, 2, 3, 4, 5, 12, 13],
        ledType: 30,
        originalBuses: null,
      );

      expect(buses.length, 1);
      expect(buses[0]['rev'], false);
      expect(buses[0]['type'], 30);
      expect(buses[0]['order'], 1);
    });
  });
}
