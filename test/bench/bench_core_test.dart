// Unit tests for the bench harness's pure assertion/diff logic (bench_core.dart)
// with canned fixtures modeled on this week's real /json/cfg + presets.json
// dumps. The HARDWARE commands (bench.dart) are the integration tests; this
// locks the logic that decides pass/fail so a green claim is trustworthy.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';

import '../../bench/src/bench_core.dart';

void main() {
  group('parseHwLedFromCfg', () {
    test('parses hw.led.ins into buses + total (current bench layout)', () {
      final cfg = {
        'hw': {
          'led': {
            'total': 290,
            'ins': [
              {'pin': [2], 'start': 0, 'len': 128},
              {'pin': [1], 'start': 128, 'len': 162},
            ],
          },
        },
      };
      final c = parseHwLedFromCfg(cfg);
      expect(c.totalLeds, 290);
      expect(c.buses.length, 2);
      expect(c.buses[1].start, 128);
      expect(c.buses[1].len, 162);
    });

    test('missing keys → empty, total falls back to sum', () {
      expect(parseHwLedFromCfg(const {}).buses, isEmpty);
    });
  });

  group('detectLayoutDrift (P1-42)', () {
    final known = const WledHardwareConfig(totalLeds: 290, buses: [
      WledLedBus(pin: [2], start: 0, len: 128),
      WledLedBus(pin: [1], start: 128, len: 162),
    ]);

    test('identical → no drift', () {
      expect(detectLayoutDrift(known, known), isNull);
    });

    test('real ch2 resize (73→162) → drift with bus detail', () {
      final stale = const WledHardwareConfig(totalLeds: 201, buses: [
        WledLedBus(pin: [2], start: 0, len: 128),
        WledLedBus(pin: [1], start: 128, len: 73),
      ]);
      final d = detectLayoutDrift(stale, known);
      expect(d, isNotNull);
      expect(d!.summary, contains('total 201→290'));
      expect(d.summary, contains('bus1 [128,73]→[128,162]'));
    });

    test('bus count change → drift', () {
      final oneBus = const WledHardwareConfig(
          totalLeds: 128, buses: [WledLedBus(pin: [2], start: 0, len: 128)]);
      expect(detectLayoutDrift(oneBus, known)!.summary, contains('bus count 1→2'));
    });

    test('layout round-trips through json', () {
      final j = layoutToJson(known);
      final back = layoutFromJson(j);
      expect(detectLayoutDrift(known, back), isNull);
    });
  });

  group('checkEnTruthTable (curl-proven polarity)', () {
    test('int→1, bool→0 = PASS', () {
      final r = checkEnTruthTable(storedForIntWrite: 1, storedForBoolWrite: 0);
      expect(r.pass, isTrue);
      expect(r.render(), startsWith('VERIFIED-BY-BENCH'));
    });

    test('int stored as 0 (regression) = FAIL', () {
      expect(
          checkEnTruthTable(storedForIntWrite: 0, storedForBoolWrite: 0).pass,
          isFalse);
    });

    test('bool stored as 1 (firmware changed) = FAIL', () {
      final r = checkEnTruthTable(storedForIntWrite: 1, storedForBoolWrite: 1);
      expect(r.pass, isFalse);
      expect(r.render(), startsWith('FAIL'));
    });

    test('bool true normalizes like int 1', () {
      // If the controller echoed the bool back as `true` for the int write, that
      // still counts as enabled=1.
      expect(
          checkEnTruthTable(storedForIntWrite: true, storedForBoolWrite: 0).pass,
          isTrue);
    });
  });

  group('presets: parse + invariants', () {
    test('parsePresets drops slot 0, keeps the rest', () {
      final body = {
        '0': {'n': 'bootloader'},
        '1': {'n': 'NGL On', 'seg': [{'id': 0, 'on': true}]},
        '2': {'n': 'NGL Off', 'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': false}]},
      };
      final p = parsePresets(body);
      expect(p.containsKey(0), isFalse);
      expect(p.keys.toSet(), {1, 2});
    });

    test('ON presets read on, OFF preset 2 reads off → all pass', () {
      final presets = {
        1: {'seg': [{'id': 0, 'on': true}]},
        2: {'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': false}]},
        3: {'seg': [{'id': 0, 'on': true}]},
        4: {'seg': [{'id': 0, 'on': true}]},
        5: {'seg': [{'id': 0, 'on': true}]},
      };
      final results = checkPresetInvariants(presets);
      expect(results.every((r) => r.pass), isTrue,
          reason: results.where((r) => !r.pass).map((r) => r.name).join(', '));
    });

    test('stale OFF preset 2 left with a lit seg → FAIL (the +50 bug shape)', () {
      final presets = {
        2: {'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': true}]}, // seg1 lit
      };
      final off = checkPresetInvariants(presets)
          .firstWhere((r) => r.name.contains('OFF-preset 2'));
      expect(off.pass, isFalse);
    });

    test('preset id over 250 ceiling → FAIL', () {
      final presets = {
        1: {'seg': [{'id': 0, 'on': true}]},
        251: {'seg': [{'id': 0, 'on': true}]},
      };
      final ceiling = checkPresetInvariants(presets)
          .firstWhere((r) => r.name.contains('≤ $kWledPresetCeiling'));
      expect(ceiling.pass, isFalse);
      expect(ceiling.evidence, contains('251'));
    });

    test('presetIsOn: per-segment on semantics', () {
      expect(presetIsOn({'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': true}]}), isTrue);
      expect(presetIsOn({'seg': [{'id': 0, 'on': false}]}), isFalse);
      expect(presetIsOn({'on': true}), isTrue); // fallback
    });
  });

  group('timerInsFrom + CheckResult.render', () {
    test('extracts timers.ins', () {
      final ins = timerInsFrom({'timers': {'ins': [{'en': 1, 'hour': 3}]}});
      expect(ins, hasLength(1));
      expect(ins.first['hour'], 3);
    });

    test('missing timers → empty', () {
      expect(timerInsFrom(const {}), isEmpty);
    });

    test('render formats pass/fail with evidence', () {
      expect(const CheckResult('x', true, 'ev').render(),
          'VERIFIED-BY-BENCH: x — ev');
      expect(const CheckResult('x', false, 'ev').render(), 'FAIL: x — ev');
    });
  });

  group('dow helper', () {
    test('Monday=bit0 .. Sunday=bit6', () {
      expect(dowBitForMondayZeroIndex(0), 1); // Mon
      expect(dowBitForMondayZeroIndex(4), 16); // Fri
      expect(dowBitForMondayZeroIndex(6), 64); // Sun
    });
  });
}
