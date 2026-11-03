// The empty-armed guard counts a schedule's own solar rows, and soft-evicted
// schedules are neither armed nor refused (2026-11-02 arm-check).
//
// WHAT WAS WRONG. `syncAll` refused to write the timer table when
// `armedSchedules` was non-empty but no row in `scheduleIns` passed
// `isRealEnabledTimer`, which EXCLUDES `hour:255`. While solar was refused
// upstream that was unreachable for solar shapes; once the solar flag went
// live, a dusk-to-dawn schedule put its boundaries in slots 8/9 and nothing in
// 0-7, the guard called that "zero real timers", returned before the POST, and
// the customer saw "could not be armed… Try syncing again" on every sync for a
// correct schedule. Separately, a soft-evicted schedule passed the arm loop but
// was dropped by `buildCfgPayload`, which produced the same banner for an
// account where nothing was wrong.
//
// Every case below drives the REAL `syncAll` with the real builders.
// Fail-before at build-121: the Sunset→Sunrise, Sunset-only, Sunrise-only and
// evicted cases all returned the banner with no timer write.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

import 'arm_check_harness.dart';

void main() {
  setUp(resetRepairAttempts);
  const svc = ScheduleSyncService();

  group('solar-only shapes arm through slots 8/9', () {
    test('Sunset → Sunrise with the global sunrise-off ON: one timer write, '
        'slot 9 = sunset ON, slot 8 = the global sunrise-off, no banner',
        () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: true)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(
          ref, [patternSchedule(on: 'Sunset', off: 'Sunrise')]);

      expect(r.success, isTrue);
      expect(r.error, isNull);
      expect(r.presetErrors, isEmpty);
      expect(repo.timerCfgWrites, 1);
      final ins = repo.lastIns;
      expect(ins, hasLength(10), reason: 'solar-aware 10-slot assembly');
      expect(ins[9]['macro'], 10, reason: 'slot 9 = sunset ON → pattern slot');
      expect(ins[9]['hour'], 254, reason: 'sunset = TH_SUNSET');
      expect(ins[8]['macro'], 2, reason: 'slot 8 = global sunrise-off');
      // Nothing in the general slots — that was the whole problem.
      for (var i = 0; i < 8; i++) {
        expect(ins[i]['macro'], 0, reason: 'slot $i is a stub');
      }
      expect(repo.saved, contains(10), reason: 'the design was psaved');
    });

    test('Sunset → Sunrise with the global sunrise-off OFF: the schedule\'s own '
        'sunrise OFF takes slot 8', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: false)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(
          ref, [patternSchedule(on: 'Sunset', off: 'Sunrise')]);
      expect(r.success, isTrue);
      expect(repo.timerCfgWrites, 1);
      expect(repo.lastIns[9]['macro'], 10);
      expect(repo.lastIns[8]['macro'], 2, reason: 'schedule OFF = NGL Off');
    });

    test('Sunset only (no OFF): slot 9 armed, slot 8 left as a stub', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(ref, [patternSchedule(on: 'Sunset')]);
      expect(r.success, isTrue);
      expect(r.error, isNull);
      expect(repo.timerCfgWrites, 1);
      expect(repo.lastIns[9]['macro'], 10);
      expect(repo.lastIns[8]['macro'], 0);
    });

    test('Sunrise only (no OFF), sunrise-off OFF: slot 8 armed', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: false)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(ref, [patternSchedule(on: 'Sunrise')]);
      expect(r.success, isTrue);
      expect(r.error, isNull);
      expect(repo.timerCfgWrites, 1);
      expect(repo.lastIns[8]['macro'], 10);
      expect(repo.lastIns[9]['macro'], 0);
    });

    test('Sunrise only with the global sunrise-off ON is the existing specific '
        'refusal (conflict), never the generic banner', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: true)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(ref, [patternSchedule(on: 'Sunrise')]);
      expect(r.error, isNot(kArmCheckBanner));
      expect(r.presetErrors.single, contains('conflicts with'));
      // The global sunrise-off row is content, so the write still goes out
      // (shouldSkipClobberingWrite) and slot 8 is the global one.
      expect(repo.timerCfgWrites, 1);
      expect(repo.lastIns[8]['macro'], 2);
    });

    test('the 2026-11-02 screenshot shape, four syncs in one process: every '
        'sync writes the table, no banner, no warning', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: true)
          .read(armCheckRefProvider);
      final item = patternSchedule(on: 'Sunset', off: 'Sunrise');
      for (var i = 0; i < 4; i++) {
        final r = await svc.syncAll(ref, [item]);
        expect(r.success, isTrue, reason: 'sync ${i + 1}');
        expect(r.presetErrors, isEmpty, reason: 'sync ${i + 1}');
      }
      expect(repo.timerCfgWrites, 4);
      expect(repo.lastIns[9]['macro'], 10);
    });
  });

  group('one clock boundary passes through (unchanged behaviour)', () {
    test('Sunset → 12:00 AM: slot 0 = clock OFF, slot 9 = sunset ON', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: true)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(
          ref, [patternSchedule(on: 'Sunset', off: '12:00 AM')]);
      expect(r.success, isTrue);
      expect(repo.timerCfgWrites, 1);
      expect(repo.lastIns[0]['macro'], 2);
      expect(repo.lastIns[0]['hour'], 0);
      expect(repo.lastIns[9]['macro'], 10);
    });

    test('5:30 PM → Sunrise (the customer\'s stored shape): slot 0 = clock ON, '
        'slot 8 = the global sunrise-off supersedes the schedule\'s own',
        () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: true)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(
          ref, [patternSchedule(on: '5:30 PM', off: 'Sunrise')]);
      expect(r.success, isTrue);
      expect(repo.timerCfgWrites, 1);
      expect(repo.lastIns[0]['macro'], 10);
      expect(repo.lastIns[0]['hour'], 17);
      expect(repo.lastIns[0]['min'], 30);
      expect(repo.lastIns[8]['macro'], 2);
      expect(repo.lastIns[9]['macro'], 0);
    });

    test('a plain clock pair still arms two rows', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(
          ref, [patternSchedule(on: '7:00 PM', off: '11:00 PM')]);
      expect(r.success, isTrue);
      expect(repo.lastIns, hasLength(10),
          reason: 'every write is the whole table, solar in play or not');
      expect(repo.lastIns[0]['macro'], 10);
      expect(repo.lastIns[1]['macro'], 2);
      expect(repo.lastIns[8],
          {'en': 0, 'hour': 255, 'min': 0, 'macro': 0, 'dow': 0},
          reason: 'slot 8 = the disabled placeholder');
      expect(repo.lastIns[9]['macro'], 0, reason: 'slot 9 = a stub');
    });
  });

  group('soft-evicted schedules are neither armed nor refused', () {
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    test('an evicted clock schedule alone: no banner, the clearing write goes '
        'out with no row for it, its preset is still kept ready', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(ref, [
        patternSchedule(
            on: '7:00 PM', off: '11:00 PM', disabledUntil: tomorrow),
      ]);
      expect(r.success, isTrue);
      expect(r.error, isNull);
      expect(r.presetErrors, isEmpty);
      expect(repo.timerCfgWrites, 1, reason: 'the padded clearing write');
      expect(repo.lastIns.where(carriesAnyEnabledEntry), isEmpty);
      expect(r.schedulesWithPresets, isEmpty, reason: 'not counted as armed');
      expect(repo.saved, contains(10), reason: 'preset written for later');
    });

    test('an evicted solar schedule takes no slot-8/9 row either — the row '
        'builders now agree with buildCfgPayload', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: false)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(ref, [
        patternSchedule(on: 'Sunset', off: 'Sunrise', disabledUntil: tomorrow),
      ]);
      expect(r.success, isTrue);
      expect(r.error, isNull);
      expect(repo.timerCfgWrites, 1);
      expect(repo.lastIns[8]['macro'], 0);
      expect(repo.lastIns[9]['macro'], 0);
    });

    test('an evicted schedule next to a live one: only the live one is armed '
        'and the evicted one does not consume capacity', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(ref, [
        patternSchedule(
            on: '6:00 PM', off: '10:00 PM', label: 'Pattern: paused',
            disabledUntil: tomorrow),
        patternSchedule(on: '7:00 PM', off: '11:00 PM', label: 'Pattern: live'),
      ]);
      expect(r.success, isTrue);
      expect(r.schedulesWithPresets.map((s) => s.actionLabel),
          ['Pattern: live']);
      final live = repo.lastIns.where(carriesAnyEnabledEntry).toList();
      expect(live, hasLength(2), reason: 'ON + OFF of the live schedule only');
      expect(live.first['hour'], 19);
    });
  });

  group('specific refusals are unchanged', () {
    test('solar flag OFF: the solar message and the clobber guard, not the '
        'banner', () async {
      final repo = FaithfulController();
      final ref = armCheckContainer(repo, solarFlag: false)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(
          ref, [patternSchedule(on: 'Sunset', off: 'Sunrise')]);
      expect(r.success, isFalse);
      expect(r.error, isNot(kArmCheckBanner));
      expect(r.presetErrors.single, contains('uses sunrise/sunset timing'));
      expect(repo.timerCfgWrites, 0);
    });

    test('coordinates missing on the controller: the location message, not '
        'the banner', () async {
      final repo = FaithfulController(hasCoords: false);
      final ref = armCheckContainer(repo, solarFlag: true)
          .read(armCheckRefProvider);
      final r = await svc.syncAll(
          ref, [patternSchedule(on: 'Sunset', off: 'Sunrise')]);
      expect(r.error, isNot(kArmCheckBanner));
      expect(r.presetErrors.single,
          contains('needs your location set on the controller'));
    });
  });
}
