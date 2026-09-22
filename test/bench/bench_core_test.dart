// Unit tests for the bench harness's pure assertion/diff logic (bench_core.dart)
// with canned fixtures modeled on this week's real /json/cfg + presets.json
// dumps. The HARDWARE commands (bench.dart) are the integration tests; this
// locks the logic that decides pass/fail so a green claim is trustworthy.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_cfg_gamma.dart';

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

  // ── 2026-09-22: restore fix — slot-aware restore, exact compare, pre-flight ──
  // Fixtures are the COMPACTED readback shape (what /json/cfg actually returns).
  const solar = {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127};
  const rowA = {
    'en': 1, 'hour': 19, 'min': 0, 'macro': 10, 'dow': 127,
    'start': {'mon': 1, 'day': 1}, 'end': {'mon': 12, 'day': 31},
  };
  const rowB = {
    'en': 1, 'hour': 7, 'min': 0, 'macro': 2, 'dow': 127,
    'start': {'mon': 1, 'day': 1}, 'end': {'mon': 12, 'day': 31},
  };
  const fixtureOn = {'en': 1, 'hour': 3, 'min': 15, 'macro': 1, 'dow': 17};
  const fixtureOff = {'en': 1, 'hour': 4, 'min': 20, 'macro': 2, 'dow': 17};
  const scratchFire = {'en': 1, 'hour': 13, 'min': 55, 'macro': 1, 'dow': 2};

  group('buildTimerRestoreIns (slot-aware restore body)', () {
    test('solar-only capture → 8 empty general rows, solar NOT re-posted', () {
      final body = buildTimerRestoreIns([solar]);
      expect(body, hasLength(kWledGeneralTimerSlots));
      expect(body.every((r) => r.toString() == kEmptyTimerRow.toString()),
          isTrue,
          reason: 'this is the 2026-09-22 shape: a solar-only capture used to '
              'produce a body that mentioned NO general slot, so the fixture '
              'rows in slots 0/1 survived');
      expect(body.any((r) => r['hour'] == 255), isFalse);
    });

    test('general rows are re-packed from index 0 with start/end intact, '
        'empties fill the rest', () {
      final body = buildTimerRestoreIns([solar, rowA, rowB]);
      expect(body[0], rowA);
      expect(body[1], rowB);
      expect(body[0]['start'], {'mon': 1, 'day': 1});
      for (var i = 2; i < 8; i++) {
        expect(body[i], kEmptyTimerRow, reason: 'slot $i must be cleared');
      }
    });

    test('empty capture → 8 empties (clears everything a run dirtied)', () {
      expect(buildTimerRestoreIns(const []),
          List.filled(kWledGeneralTimerSlots, kEmptyTimerRow));
    });

    test('kEmptyTimerRow is the WLED clear shape: macro, hour, min all 0', () {
      // serializeConfig skips a slot iff macro==0 && hour==0 && min==0 —
      // anything else stays visible (and hour 255 would jump to slot 8).
      expect(kEmptyTimerRow['macro'], 0);
      expect(kEmptyTimerRow['hour'], 0);
      expect(kEmptyTimerRow['min'], 0);
      expect(kEmptyTimerRow['en'], 0);
    });
  });

  group('timerTableDiff (EXACT restore verification)', () {
    test('identical tables → null', () {
      expect(timerTableDiff([rowA, solar], [rowA, solar]), isNull);
    });

    test('a surviving fixture row is EXTRA — containment would have passed', () {
      // The 2026-09-22 failure shape: capture [solar], readback [fixture×2, solar].
      final d = timerTableDiff([solar], [fixtureOn, fixtureOff, solar]);
      expect(d, isNotNull);
      expect(d, contains('EXTRA 2'));
      expect(d, contains('hour=3 min=15'));
    });

    test('a captured row that did not come back is MISSING', () {
      final d = timerTableDiff([rowA, rowB, solar], [rowA, solar]);
      expect(d, contains('MISSING 1'));
      expect(d, contains('hour=7'));
    });

    test('same rows, different order → reported (ordered comparison)', () {
      final d = timerTableDiff([rowA, rowB], [rowB, rowA]);
      expect(d, contains('DIFFERENT ORDER'));
    });

    test('en bool/int and absent start/end are canonicalised on both sides', () {
      final a = {'en': true, 'hour': 5, 'min': 0, 'macro': 1, 'dow': 1};
      final b = {'en': 1, 'hour': 5, 'min': 0, 'macro': 1, 'dow': 1};
      expect(timerTableDiff([a], [b]), isNull);
      expect(canonicalTimerRow(solar), contains('start=0/0 end=0/0'));
    });

    test('empty expected vs non-empty actual → EXTRA (no special branch)', () {
      final d = timerTableDiff(const [], [scratchFire]);
      expect(d, contains('EXTRA 1'));
    });
  });

  group('prepareCfgPayload (gamma carried on every harness cfg POST)', () {
    test('timers-only body gains the NGL light.gc', () {
      final out = prepareCfgPayload({
        'timers': {'ins': [kEmptyTimerRow]}
      });
      expect(out['light'], {'gc': kNglLightGammaConfig});
      expect(kNglLightGammaConfig['col'], 2.8);
      expect((out['timers'] as Map)['ins'], [kEmptyTimerRow]);
    });

    test('an explicit light.gc passes through unchanged', () {
      final out = prepareCfgPayload({
        'light': {'gc': {'bri': 1, 'col': 2.2, 'val': 2.2}},
      });
      expect((out['light'] as Map)['gc'], {'bri': 1, 'col': 2.2, 'val': 2.2});
    });
  });

  group('gamma helpers', () {
    test('gammaColIntact: col 2.8 → true, col 1 (the wipe) → false, absent → false',
        () {
      expect(gammaColIntact({'bri': 1, 'col': 2.8, 'val': 2.8}), isTrue);
      expect(gammaColIntact({'bri': 1, 'col': 1, 'val': 2.8}), isFalse);
      expect(gammaColIntact(null), isFalse);
    });

    test('gammaFromCfg reads light.gc, null when absent', () {
      expect(gammaFromCfg({'light': {'gc': {'col': 2.8}}}), {'col': 2.8});
      expect(gammaFromCfg({'light': {}}), isNull);
      expect(gammaFromCfg(null), isNull);
    });
  });

  group('detectDirtyState (pre-flight)', () {
    const cleanGc = {'bri': 1, 'col': 2.8, 'val': 2.8};
    const wipedGc = {'bri': 1, 'col': 1, 'val': 2.8};

    test('clean controller → no reasons', () {
      expect(
          detectDirtyState(
              timers: [rowA, rowB, solar],
              gc: cleanGc,
              inflightLedgerPresent: false),
          isEmpty);
    });

    test('wiped gamma → refused', () {
      final r = detectDirtyState(
          timers: [solar], gc: wipedGc, inflightLedgerPresent: false);
      expect(r, hasLength(1));
      expect(r.single, contains('WIPED'));
    });

    test('sync-sim fixture rows → refused, one reason per row', () {
      final r = detectDirtyState(
          timers: [fixtureOn, fixtureOff, solar],
          gc: cleanGc,
          inflightLedgerPresent: false);
      expect(r, hasLength(2));
      expect(r.every((x) => x.contains('harness scratch/fixture row')), isTrue);
    });

    test('cfg-truth scratch (3:33 m1 d2) → refused', () {
      final r = detectDirtyState(
          timers: [{'en': 1, 'hour': 3, 'min': 33, 'macro': 1, 'dow': 2}],
          gc: cleanGc,
          inflightLedgerPresent: false);
      expect(r, hasLength(1));
    });

    test('inflight ledger alone → refused (the killed-process case)', () {
      // fire-test's scratch has no fixed signature; the ledger is what
      // catches it after a process dies mid-wait.
      final r = detectDirtyState(
          timers: [scratchFire, solar],
          gc: cleanGc,
          inflightLedgerPresent: true);
      expect(r, hasLength(1));
      expect(r.single, contains('inflight'));
    });

    test('the real 2026-09-22 table → THREE reasons (ledger + gamma + fixture)',
        () {
      final r = detectDirtyState(
          timers: [scratchFire, fixtureOff, solar],
          gc: wipedGc,
          inflightLedgerPresent: true);
      expect(r, hasLength(3));
    });

    test('a genuine schedule with macro 1 is NOT a signature', () {
      // A user "Turn On 3:15 Mon+Fri" would collide with the fixture ON row —
      // accepted: that exact row is the fixture, and recover keeps everything
      // else. A different minute is not flagged.
      expect(isHarnessSignatureRow({'hour': 3, 'min': 16, 'macro': 1, 'dow': 17}),
          isFalse);
      expect(isHarnessSignatureRow(solar), isFalse);
      expect(isHarnessSignatureRow(scratchFire), isFalse);
    });
  });

  group('RunLedger (durable inflight record)', () {
    test('round-trips through json with timers, gamma, power and slots', () {
      final l = RunLedger(
        runId: 'r1',
        command: 'fire-test',
        ip: 'http://192.168.1.150',
        startedAt: '2026-09-22T13:52:00',
        capturedTimers: [solar],
        capturedGamma: const {'bri': 1, 'col': 2.8, 'val': 2.8},
        capturedOn: true,
        dirtiedSlots: {0},
      );
      final back = RunLedger.fromJson(l.toJson())!;
      expect(back.command, 'fire-test');
      expect(back.capturedTimers, [solar]);
      expect(back.capturedGamma, {'bri': 1, 'col': 2.8, 'val': 2.8});
      expect(back.capturedOn, isTrue);
      expect(back.dirtiedSlots, {0});
      expect(back.status, 'inflight');
    });

    test('a ledger without a timers list is rejected (never restore from junk)',
        () {
      expect(RunLedger.fromJson({'command': 'x'}), isNull);
    });

    test('restoring a ledger capture clears the dirtied slots and nothing else',
        () {
      final l = RunLedger(
        runId: 'r1', command: 'sync-sim', ip: '', startedAt: '',
        capturedTimers: [rowA, solar],
        capturedGamma: null, capturedOn: null, dirtiedSlots: {0, 1},
      );
      final body = buildTimerRestoreIns(l.capturedTimers);
      expect(body[0], rowA);
      expect(body.sublist(1), List.filled(7, kEmptyTimerRow));
    });
  });
}
