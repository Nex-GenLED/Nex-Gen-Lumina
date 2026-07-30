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
      final r = checkEnTruthTable(
          intWriteLanded: true, storedForIntWrite: 1, storedForBoolWrite: 0);
      expect(r.pass, isTrue);
      expect(r.render(), startsWith('VERIFIED-BY-BENCH'));
    });

    test('int stored as 0 (regression) = FAIL', () {
      expect(
          checkEnTruthTable(
                  intWriteLanded: true,
                  storedForIntWrite: 0,
                  storedForBoolWrite: 0)
              .pass,
          isFalse);
    });

    test('bool stored as 1 (firmware changed) = FAIL', () {
      final r = checkEnTruthTable(
          intWriteLanded: true, storedForIntWrite: 1, storedForBoolWrite: 1);
      expect(r.pass, isFalse);
      expect(r.render(), startsWith('FAIL'));
    });

    test('bool compacted out (absent) = PASS — expected on this firmware', () {
      final r = checkEnTruthTable(
          intWriteLanded: true, storedForIntWrite: 1, storedForBoolWrite: null);
      expect(r.pass, isTrue);
      expect(r.evidence, contains('ABSENT'));
    });

    // AUDIT 2026-07-30 — REPLACES 'bool true normalizes like int 1'. That test
    // asserted the defect: it required the check to treat a bool `true`
    // readback as int 1, erasing the very type distinction the truth table
    // exists to detect. Type-strictness is the point.
    test('int write echoed back as bool true = FAIL (not type-strict)', () {
      final r = checkEnTruthTable(
          intWriteLanded: true, storedForIntWrite: true, storedForBoolWrite: 0);
      expect(r.pass, isFalse,
          reason: 'a bool readback for an int write is a DIFFERENT firmware '
              'behaviour and must not silently pass');
    });

    // AUDIT 2026-07-30 — the null-passes-the-bool-half hole.
    test('int control never landed = FAIL as INCONCLUSIVE', () {
      final r = checkEnTruthTable(
          intWriteLanded: false,
          storedForIntWrite: null,
          storedForBoolWrite: null);
      expect(r.pass, isFalse,
          reason: 'without a landed int control, a dead controller would have '
              'passed the bool half');
      expect(r.evidence, contains('INCONCLUSIVE'));
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

    // AUDIT 2026-07-30 — the fixtures below now carry ROOT `on`, because that
    // is what asserts master power. The OLD version of this test used
    // segment-only presets with NO root `on` and asserted they all PASS — i.e.
    // it encoded the exact broken shape found on the bench rig, which is why
    // the defect survived: the regression guard asserted the bug.
    test('ON presets assert root on, OFF preset 2 asserts root off → all pass',
        () {
      final presets = {
        1: {'on': true, 'seg': [{'id': 0, 'on': true}]},
        2: {'on': false, 'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': false}]},
        3: {'on': true, 'seg': [{'id': 0, 'on': true}]},
        4: {'on': true, 'seg': [{'id': 0, 'on': true}]},
        5: {'on': true, 'seg': [{'id': 0, 'on': true}]},
      };
      final results = checkPresetInvariants(presets);
      expect(results.every((r) => r.pass), isTrue,
          reason: results.where((r) => !r.pass).map((r) => r.name).join(', '));
    });

    // THE REGRESSION GUARD THAT WAS MISSING. This is the live bench-rig shape:
    // segments on, no root `on`. It must FAIL.
    test('ON preset with segs on but NO root on → FAIL (the 9158c00 shape)', () {
      final presets = {
        1: {'n': 'NGL On', 'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': true}]},
        2: {'on': false, 'seg': [{'id': 0, 'on': false}]},
      };
      final on1 = checkPresetInvariants(presets)
          .firstWhere((r) => r.name.contains('ON-preset 1'));
      expect(on1.pass, isFalse,
          reason: 'segment-level on does NOT assert master power — this preset '
              'loads into a dark strip');
      expect(on1.evidence, contains('DARK'));
    });

    test('stale OFF preset 2 left with a lit seg → FAIL (the +50 bug shape)', () {
      final presets = {
        2: {'on': false, 'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': true}]},
      };
      final off = checkPresetInvariants(presets)
          .firstWhere((r) => r.name.contains('OFF-preset 2'));
      expect(off.pass, isFalse);
    });

    test('OFF preset 2 with no seg lit but root on:true → FAIL', () {
      final presets = {
        2: {'on': true, 'seg': [{'id': 0, 'on': false}]},
      };
      final off = checkPresetInvariants(presets)
          .firstWhere((r) => r.name.contains('OFF-preset 2'));
      expect(off.pass, isFalse,
          reason: 'all-segments-off does not imply master off');
    });

    test('partially-synced controller: missing ON preset emits a FAIL, not silence',
        () {
      final presets = {
        1: {'on': true, 'seg': [{'id': 0, 'on': true}]},
        2: {'on': false, 'seg': [{'id': 0, 'on': false}]},
        // 3, 4, 5 absent
      };
      final results = checkPresetInvariants(presets);
      for (final id in [3, 4, 5]) {
        final r = results.firstWhere((x) => x.name.contains('ON-preset $id'));
        expect(r.pass, isFalse, reason: 'absent preset $id must not be silent');
      }
    });

    test('un-synced controller (no system presets) emits ONE explicit check', () {
      final results = checkPresetInvariants({251: {'on': true}});
      final synced =
          results.where((r) => r.name.contains('controller synced')).toList();
      expect(synced, hasLength(1));
      expect(synced.single.pass, isTrue);
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

    // AUDIT 2026-07-30 — REPLACES 'presetIsOn: per-segment on semantics'.
    // presetIsOn is gone: it claimed to test master power and tested segments,
    // which is the defect. The two concepts are now separate functions and the
    // distinction between them is what this test pins.
    test('presetAssertsMasterPower is ROOT-only and ignores segments', () {
      // The live bench-rig shape: segments on, no root on → NOT master power.
      expect(
          presetAssertsMasterPower(
              {'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': true}]}),
          isFalse);
      expect(presetAssertsMasterPower({'on': true}), isTrue);
      expect(presetAssertsMasterPower({'on': false, 'seg': [{'on': true}]}),
          isFalse);
      expect(presetAssertsMasterPower(const {}), isFalse);
    });

    test('presetAnySegmentOn is segment-only and never consulted for power', () {
      expect(
          presetAnySegmentOn(
              {'seg': [{'id': 0, 'on': false}, {'id': 1, 'on': true}]}),
          isTrue);
      expect(presetAnySegmentOn({'seg': [{'id': 0, 'on': false}]}), isFalse);
      // No seg list → false (it is NOT a root-on fallback; that was the bug).
      expect(presetAnySegmentOn({'on': true}), isFalse);
    });

    test('ib is never a signal — a healthy preset has no ib key', () {
      // WLED never writes `ib` back; it is a psave REQUEST flag. A preset that
      // asserts master power has root on:true and no ib, and must pass.
      final presets = {
        1: {'on': true, 'seg': [{'id': 0, 'on': true}]},
        2: {'on': false, 'seg': [{'id': 0, 'on': false}]},
        3: {'on': true, 'seg': [{'id': 0, 'on': true}]},
        4: {'on': true, 'seg': [{'id': 0, 'on': true}]},
        5: {'on': true, 'seg': [{'id': 0, 'on': true}]},
      };
      expect(presets.values.any((p) => p.containsKey('ib')), isFalse);
      expect(checkPresetInvariants(presets).every((r) => r.pass), isTrue);
    });
  });

  group('fire-test split (ps discriminator)', () {
    test('timer never fired → A fails, B explicitly NOT EVALUATED', () {
      final r = checkFireTestSplit(
          expectedMacro: 1, psBefore: -1, psAfter: -1, onAfter: false);
      expect(r[0].pass, isFalse);
      expect(r[0].evidence, contains('FIRMWARE'));
      expect(r[1].pass, isFalse);
      expect(r[1].evidence, contains('NOT EVALUATED'));
    });

    test('timer fired but preset dark → A passes, B fails as APP side', () {
      final r = checkFireTestSplit(
          expectedMacro: 1, psBefore: -1, psAfter: 1, onAfter: false);
      expect(r[0].pass, isTrue);
      expect(r[1].pass, isFalse);
      expect(r[1].evidence, contains('APP side'));
    });

    test('timer fired and strip lit → both pass', () {
      final r = checkFireTestSplit(
          expectedMacro: 1, psBefore: -1, psAfter: 1, onAfter: true);
      expect(r.every((c) => c.pass), isTrue);
    });
  });

  group('slot bands + lease integrity', () {
    test('stray slot in the 6-9 gap → FAIL', () {
      final r = checkPresetSlotBands({7: {'on': true}});
      expect(r.pass, isFalse);
      expect(r.evidence, contains('7'));
    });

    test('reserved bands are clean', () {
      final r = checkPresetSlotBands({
        1: {'on': true}, 12: {'on': true}, 27: {'on': true}, 104: {'on': true},
      });
      expect(r.pass, isTrue);
    });

    test('lease slot mutated during a run → FAIL (was hardcoded true)', () {
      final r = checkLeaseSlotsIntact(
        before: {26: {'n': 'Lease A', 'on': true}},
        after: {26: {'n': 'Lease B', 'on': true}},
      );
      expect(r.pass, isFalse);
      expect(r.evidence, contains('MUTATED'));
    });

    test('lease slot disappearing → FAIL', () {
      final r = checkLeaseSlotsIntact(
          before: {41: {'n': 'Lease X'}}, after: const {});
      expect(r.pass, isFalse);
      expect(r.evidence, contains('DISAPPEARED'));
    });
  });

  group('controller clock parsing', () {
    test('parses WLED non-padded info.time', () {
      final t = parseControllerTime('2026-7-30, 14:29:23');
      expect(t, DateTime(2026, 7, 30, 14, 29, 23));
    });

    test('null / malformed → null (caller falls back to host with a warning)', () {
      expect(parseControllerTime(null), isNull);
      expect(parseControllerTime('not a time'), isNull);
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
