import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

void main() {
  group('buildSkikbilyBuses — bus rev preservation (config half of #3/#4)', () {
    test('preserves an existing bus rev:true (does NOT force false)', () {
      final cfg = WledHardwareConfig(totalLeds: 400, maxPowerMw: 20000, buses: [
        WledLedBus(pin: [16], start: 0, len: 100, type: 30, order: 1, rev: true),
        WledLedBus(pin: [3], start: 100, len: 100, type: 30, order: 1, rev: false),
      ]);
      final buses = buildSkikbilyBuses(cfg);

      expect(buses.length, 4);
      expect(buses[0]['rev'], true, reason: 'manual flip must survive re-sync');
      expect(buses[1]['rev'], false);
      // Channels the device hasn't populated default sanely.
      expect(buses[2]['rev'], false);
      expect(buses[3]['rev'], false);
    });

    test('preserves existing GPIO pins, defaults pins for new channels', () {
      final cfg = WledHardwareConfig(totalLeds: 100, buses: [
        WledLedBus(pin: [2], len: 100, rev: true),
      ]);
      final buses = buildSkikbilyBuses(cfg);

      expect(buses[0]['pin'], [2]); // preserved
      expect(buses[1]['pin'], [3]); // SKIKBILY default GPIO
    });

    test('null config (genuinely new device) → all rev:false, default pins', () {
      final buses = buildSkikbilyBuses(null);

      expect(buses.length, 4);
      expect(buses.every((b) => b['rev'] == false), true);
      expect(buses.map((b) => (b['pin'] as List).first).toList(), [16, 3, 1, 4]);
      expect(buses.every((b) => b['type'] == 30), true);
      expect(buses.every((b) => b['order'] == 1), true);
    });
  });

  group('buildLedConfig — gamma (gc) preservation', () {
    test('carries the device gc through verbatim when present', () {
      final led = buildLedConfig(
        total: 400,
        maxpwr: 20000,
        ins: const [],
        gc: {'col': 2.8, 'bri': 1.0},
      );
      expect(led['gc'], {'col': 2.8, 'bri': 1.0});
    });

    test('omits gc when the device has none (firmware unaffected)', () {
      final led = buildLedConfig(total: 400, maxpwr: 20000, ins: const [], gc: null);
      expect(led.containsKey('gc'), false);
      // Identical to the historical payload shape otherwise.
      expect(led.keys.toSet(), {'total', 'maxpwr', 'ins'});
    });
  });

  group('ledInsMatches — no-op Re-sync gate', () {
    final proposed = buildSkikbilyBuses(WledHardwareConfig(totalLeds: 400, buses: [
      WledLedBus(pin: [16], start: 0, len: 100, type: 30, order: 1, rev: true),
      WledLedBus(pin: [3], start: 100, len: 100, type: 30, order: 1, rev: false),
      WledLedBus(pin: [1], start: 200, len: 100, type: 30, order: 1, rev: false),
      WledLedBus(pin: [4], start: 300, len: 100, type: 30, order: 1, rev: false),
    ]));

    test('true when current matches proposed on every written field', () {
      final current = [
        WledLedBus(pin: [16], start: 0, len: 100, type: 30, order: 1, rev: true),
        WledLedBus(pin: [3], start: 100, len: 100, type: 30, order: 1, rev: false),
        WledLedBus(pin: [1], start: 200, len: 100, type: 30, order: 1, rev: false),
        WledLedBus(pin: [4], start: 300, len: 100, type: 30, order: 1, rev: false),
      ];
      expect(ledInsMatches(current, proposed), true);
    });

    test('false when a rev flag differs (so the gate does not skip)', () {
      final current = [
        WledLedBus(pin: [16], start: 0, len: 100, type: 30, order: 1, rev: false),
        WledLedBus(pin: [3], start: 100, len: 100, type: 30, order: 1, rev: false),
        WledLedBus(pin: [1], start: 200, len: 100, type: 30, order: 1, rev: false),
        WledLedBus(pin: [4], start: 300, len: 100, type: 30, order: 1, rev: false),
      ];
      expect(ledInsMatches(current, proposed), false);
    });

    test('false when bus count differs', () {
      expect(ledInsMatches(const [], proposed), false);
    });
  });
}
