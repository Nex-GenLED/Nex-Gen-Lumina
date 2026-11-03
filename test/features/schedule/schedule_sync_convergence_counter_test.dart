// The non-convergence counter follows the real predicate on always-write
// slots (2026-11-02 arm-check).
//
// WHAT WAS WRONG. Pattern slots 10-25 are psaved with `alwaysWrite: true`
// (Option A: no idempotent skip). Inside `psaveIfChanged` that made the local
// satisfaction closure the constant `false`, and the non-convergence counter
// was keyed off that closure — so every pattern slot accrued one "failed"
// attempt per sync and the FOURTH sync of any app session refused it with
// "preset 10 (…) still fails its check after 3 saves — refusing to re-save …
// Predicate and builder are out of step". Literally true (the predicate in
// force was `() => false`), and a false alarm on every house: the stored
// preset satisfied `presetSatisfies` exactly.
//
// NOW: convergence is judged by `presetSatisfies` against the builder's own
// output. A stored definition that satisfies it clears the counter and is
// still re-written (Option A unchanged); one that never satisfies it still
// trips the guard after kMaxRepairAttempts writes.
//
// Fail-before at build-121: the 4th and 5th sync cases refused; the per-channel
// shape test passed (the predicate was never the problem).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

import 'arm_check_harness.dart';

void main() {
  setUp(resetRepairAttempts);
  const svc = ScheduleSyncService();

  group('a satisfied always-write slot never trips the refusal', () {
    test('five syncs in one process: slot 10 is re-written every time '
        '(Option A), the counter is clear after every sync, nothing refused',
        () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      final item = patternSchedule(on: '7:00 PM', off: '11:00 PM');

      for (var i = 1; i <= 5; i++) {
        final r = await svc.syncAll(ref, [item]);
        expect(r.success, isTrue, reason: 'sync $i');
        expect(r.presetErrors, isEmpty, reason: 'sync $i must not refuse');
        expect(repo.saved.where((id) => id == 10).length, i,
            reason: 'Option A: slot 10 written on every sync');
        if (i >= 2) {
          // From the second sync on the controller already holds the
          // builder's output, so the counter is cleared, not incremented.
          expect(await repairAttempts.attempts(10), 0,
              reason: 'sync $i: a satisfied slot clears the counter');
        }
      }
      expect(repo.timerCfgWrites, 5);
      // The stored preset really does satisfy the real predicate.
      expect(
          ScheduleSyncService.presetSatisfies(
              repo.presets[10]!, repo.lastWritten[10]!,
              expectedName: 'Pattern: overnight'),
          isTrue);
    });

    test('the ladder slots still converge: written once, then skipped',
        () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      for (var i = 0; i < 5; i++) {
        await svc.syncAll(ref, [patternSchedule(on: '7:00 PM')]);
      }
      expect(repo.saved.where((id) => id <= 5).length, 5);
      for (final id in [1, 2, 3, 4, 5]) {
        expect(await repairAttempts.attempts(id), 0);
      }
    });

    test('a correct preset held BEFORE the first sync starts with a clear '
        'counter', () async {
      final seed = FaithfulController();
      await svc.syncAll(
          armCheckContainer(seed, solarFlag: false).read(armCheckRefProvider),
          [patternSchedule(on: '7:00 PM')]);
      resetRepairAttempts();

      final repo = FaithfulController(
          presets: {10: Map<String, dynamic>.from(seed.presets[10]!)});
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      for (var i = 1; i <= 4; i++) {
        final r = await svc.syncAll(ref, [patternSchedule(on: '7:00 PM')]);
        expect(r.presetErrors, isEmpty, reason: 'sync $i');
        expect(await repairAttempts.attempts(10), 0, reason: 'sync $i');
      }
      expect(repo.saved.where((id) => id == 10).length, 4);
    });
  });

  group('a preset that truly fails is still refused after three saves', () {
    test('a controller that drops root `on`: syncs 1-3 write, sync 4 and 5 '
        'refuse with the non-convergence text, the schedule still arms',
        () async {
      final repo = FaithfulController(storeRootOn: false);
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      final item = patternSchedule(on: '7:00 PM', off: '11:00 PM');

      ScheduleSyncResult? last;
      for (var i = 1; i <= 5; i++) {
        last = await svc.syncAll(ref, [item]);
        if (i <= 3) {
          expect(last.presetErrors.where((e) => e.contains('preset 10')),
              isEmpty,
              reason: 'sync $i is still an attempt');
          expect(await repairAttempts.attempts(10), i);
        } else {
          final refusal = last.presetErrors.singleWhere(
              (e) => e.contains('preset 10 (Pattern: overnight)'));
          expect(
              refusal,
              allOf(
                contains('still fails its check after $kMaxRepairAttempts saves'),
                contains('refusing to re-save'),
              ),
              reason: 'sync $i');
        }
      }
      expect(repo.saved.where((id) => id == 10).length, kMaxRepairAttempts,
          reason: 'no fourth or fifth write of a slot that cannot converge');
      // The slot is "left alone deliberately, not lost": the timer still arms.
      expect(last!.success, isTrue);
      expect(repo.timerCfgWrites, 5);
      // And the real predicate agrees it never converged.
      expect(
          ScheduleSyncService.presetSatisfies(
              repo.presets[10]!, repo.lastWritten[10]!,
              expectedName: 'Pattern: overnight'),
          isFalse);
    });

    test('a satisfied sync in between resets the budget', () async {
      // Three failing writes, then the controller starts storing faithfully:
      // the next sync clears the counter instead of refusing forever.
      final bad = FaithfulController(storeRootOn: false);
      final badRef = armCheckContainer(bad, solarFlag: false)
          .read(armCheckRefProvider);
      for (var i = 0; i < 3; i++) {
        await svc.syncAll(badRef, [patternSchedule(on: '7:00 PM')]);
      }
      expect(await repairAttempts.attempts(10), 3);

      // Same process, same counter; a controller that now holds the
      // builder's output (as if the firmware was fixed or the preset repaired
      // by hand).
      final good = FaithfulController();
      final goodRef = armCheckContainer(good, solarFlag: false)
          .read(armCheckRefProvider);
      final first = await svc.syncAll(goodRef, [patternSchedule(on: '7:00 PM')]);
      // The first sync against the good controller finds NO preset 10 yet
      // (fresh fake) → not converged → counter is at the limit → refused.
      // (The ladder slots were also stored without root `on` by the bad
      // controller, so they are refused here too; only slot 10 is asserted.)
      expect(first.presetErrors.where((e) => e.contains('preset 10 (')),
          hasLength(1));
      // Seed it as the previous write would have, and the next sync clears.
      good.presets[10] = Map<String, dynamic>.from(bad.lastWritten[10]!)
        ..remove('ib')
        ..['n'] = 'Pattern: overnight';
      final second = await svc.syncAll(goodRef, [patternSchedule(on: '7:00 PM')]);
      expect(second.presetErrors.where((e) => e.contains('preset 10 (')),
          isEmpty);
      expect(await repairAttempts.attempts(10), 0);
    });
  });

  group('the predicate accepts the shapes the pattern path writes', () {
    // The per-channel shape `fanOutPatternPayloadToBuses` (fix/122-schedule-
    // presets) produces: one entry per bus id carrying the design, `on:true`
    // per entry, no bounds. WLED stores it back with ids, bounds and every
    // default key filled in. `presetSatisfies` indexes stored segments by id,
    // skips `start`/`stop`, the base-look keys and `ib`/`bri`, and compares
    // the rest.
    const perChannelBuilderOutput = <String, dynamic>{
      'on': true,
      'bri': 200,
      'ib': true,
      'seg': [
        {
          'id': 0,
          'fx': 0,
          'pal': 5,
          'sx': 28,
          'ix': 0,
          'col': [
            [255, 160, 0, 0]
          ],
          'on': true,
        },
        {
          'id': 1,
          'fx': 0,
          'pal': 5,
          'sx': 28,
          'ix': 0,
          'col': [
            [255, 160, 0, 0]
          ],
          'on': true,
        },
      ],
    };

    Map<String, dynamic> wledStored(int id, int start, int stop) => {
          'id': id,
          'start': start,
          'stop': stop,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'on': true,
          'frz': false,
          'bri': 255,
          'cct': 127,
          'set': 0,
          'col': [
            [255, 160, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
          ],
          'fx': 0,
          'sx': 28,
          'ix': 0,
          'pal': 5,
          'c1': 128,
          'c2': 128,
          'c3': 16,
          'sel': true,
          'rev': false,
          'mi': false,
          'o1': false,
          'o2': false,
          'o3': false,
          'si': 0,
          'm12': 0,
        };

    test('a faithfully stored per-channel preset satisfies', () {
      final stored = <String, dynamic>{
        'n': 'Pattern: overnight',
        'on': true,
        'bri': 200,
        'transition': 7,
        'mainseg': 0,
        'seg': [wledStored(0, 0, 100), wledStored(1, 100, 142)],
      };
      expect(
          ScheduleSyncService.presetSatisfies(stored, perChannelBuilderOutput,
              expectedName: 'Pattern: overnight'),
          isTrue);
    });

    test('a per-channel schedule through five syncs is never refused',
        () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      final item = patternSchedule(
          on: '7:00 PM',
          payload: Map<String, dynamic>.from(perChannelBuilderOutput)
            ..remove('ib'));
      for (var i = 1; i <= 5; i++) {
        final r = await svc.syncAll(ref, [item]);
        expect(r.presetErrors, isEmpty, reason: 'sync $i');
      }
      expect(repo.saved.where((id) => id == 10).length, 5);
    });

    test('the stored preset missing one of the two channels does NOT '
        'satisfy — a scoped expectation requires every named segment',
        () {
      final stored = <String, dynamic>{
        'n': 'Pattern: overnight',
        'on': true,
        'seg': [wledStored(0, 0, 100)],
      };
      expect(
          ScheduleSyncService.presetSatisfies(stored, perChannelBuilderOutput,
              expectedName: 'Pattern: overnight',
              requireAllExpectedSegments: true),
          isFalse);
      // …but an ALL-channel expectation tolerates the silence (unchanged).
      expect(
          ScheduleSyncService.presetSatisfies(stored, perChannelBuilderOutput,
              expectedName: 'Pattern: overnight'),
          isTrue);
    });

    test('a stored preset with the wrong root `on` never satisfies', () {
      final stored = <String, dynamic>{
        'n': 'Pattern: overnight',
        'seg': [wledStored(0, 0, 100), wledStored(1, 100, 142)],
      };
      expect(
          ScheduleSyncService.presetSatisfies(stored, perChannelBuilderOutput,
              expectedName: 'Pattern: overnight'),
          isFalse);
    });
  });
}
