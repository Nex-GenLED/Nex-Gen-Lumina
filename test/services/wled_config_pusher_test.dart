import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

void main() {
  group('buildSkikbilyBuses — bus rev preservation (config half of #3/#4)', () {
    test('preserves an existing bus rev:true (does NOT force false)', () {
      final cfg = WledHardwareConfig(totalLeds: 200, maxPowerMw: 20000, buses: [
        WledLedBus(pin: [16], start: 0, len: 100, type: 30, order: 1, rev: true),
        WledLedBus(pin: [3], start: 100, len: 100, type: 30, order: 1, rev: false),
      ]);
      final buses = buildSkikbilyBuses(cfg);

      // Provisioned device (≥2 buses): exact bus count is preserved now (#12);
      // it used to be force-expanded to 4. rev is still carried through.
      expect(buses.length, 2);
      expect(buses[0]['rev'], true, reason: 'manual flip must survive re-sync');
      expect(buses[1]['rev'], false);
    });

    test('preserves existing GPIO pins, defaults pins for new channels', () {
      // A lone bus = the WLED factory default (unprovisioned) → still expands
      // to the full 4-channel SKIKBILY profile so install provisions all buses.
      final cfg = WledHardwareConfig(totalLeds: 100, buses: [
        WledLedBus(pin: [2], len: 100, rev: true),
      ]);
      final buses = buildSkikbilyBuses(cfg);

      expect(buses.length, 4);
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
      // Fresh device asserts the SKIKBILY 100-px default on every channel.
      expect(buses.every((b) => b['len'] == 100), true);
    });
  });

  group('buildSkikbilyBuses — bus len preservation (#12, completes 625226f)', () {
    test('preserves a real 128/60 install — does NOT force 100/100', () {
      // The exact Tyler hardware: Bus 0 = 128 (Front Roofline), Bus 1 = 60
      // (Side Accent). Re-sync MUST leave these untouched.
      final cfg = WledHardwareConfig(totalLeds: 188, maxPowerMw: 20000, buses: [
        WledLedBus(pin: [16], start: 0, len: 128, type: 30, order: 1),
        WledLedBus(pin: [3], start: 128, len: 60, type: 30, order: 1),
      ]);
      final buses = buildSkikbilyBuses(cfg);

      expect(buses.length, 2, reason: 'does not invent phantom channels');
      expect(buses[0]['len'], 128, reason: 'front roofline NOT clobbered to 100');
      expect(buses[1]['len'], 60, reason: 'side accent NOT clobbered to 100');
      // start addresses follow the preserved lengths.
      expect(buses[0]['start'], 0);
      expect(buses[1]['start'], 128);
    });

    test('preserves an existing bus skip', () {
      final cfg = WledHardwareConfig(totalLeds: 188, buses: [
        WledLedBus(pin: [16], start: 0, len: 128, skip: 3),
        WledLedBus(pin: [3], start: 128, len: 60, skip: 0),
      ]);
      final buses = buildSkikbilyBuses(cfg);
      expect(buses[0]['skip'], 3);
      expect(buses[1]['skip'], 0);
    });

    test('a provisioned bus with no usable len falls back to the 100 default '
        'only for the genuinely-new channels', () {
      // 3-bus device, all real lengths preserved; no padding to 4.
      final cfg = WledHardwareConfig(totalLeds: 288, buses: [
        WledLedBus(pin: [16], start: 0, len: 128),
        WledLedBus(pin: [3], start: 128, len: 60),
        WledLedBus(pin: [1], start: 188, len: 100),
      ]);
      final buses = buildSkikbilyBuses(cfg);
      expect(buses.length, 3);
      expect(buses.map((b) => b['len']).toList(), [128, 60, 100]);
    });
  });

  group('Re-sync no-op gate — a preserved 128/60 device matches itself', () {
    test('ledInsMatches(device, buildSkikbilyBuses(device)) is true for 128/60',
        () {
      // After the len-preservation fix the proposed config equals the device's
      // own config, so the hwUnchanged gate in pushDefaultsForControllerType
      // skips the hw.led push entirely — Re-sync is a true no-op, not a clobber.
      final device = [
        WledLedBus(pin: [16], start: 0, len: 128, type: 30, order: 1),
        WledLedBus(pin: [3], start: 128, len: 60, type: 30, order: 1),
      ];
      final cfg = WledHardwareConfig(totalLeds: 188, maxPowerMw: 20000, buses: device);
      final proposed = buildSkikbilyBuses(cfg);

      expect(ledInsMatches(device, proposed), true);
      // And the derived total matches the device total (the other gate clause).
      final total = proposed.fold<int>(0, (s, b) => s + (b['len'] as int));
      expect(total, 188);
    });

    test('a 100×4 device still matches its own profile (no-op preserved)', () {
      final device = [
        WledLedBus(pin: [16], start: 0, len: 100, type: 30, order: 1),
        WledLedBus(pin: [3], start: 100, len: 100, type: 30, order: 1),
        WledLedBus(pin: [1], start: 200, len: 100, type: 30, order: 1),
        WledLedBus(pin: [4], start: 300, len: 100, type: 30, order: 1),
      ];
      final proposed =
          buildSkikbilyBuses(WledHardwareConfig(totalLeds: 400, buses: device));
      expect(ledInsMatches(device, proposed), true);
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
