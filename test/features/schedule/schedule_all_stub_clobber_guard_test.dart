// test/features/schedule/schedule_all_stub_clobber_guard_test.dart
//
// ALL-STUB CLOBBER GUARD — audit/ALL_STUB_CLOBBER.md, audit/ALL_STUB_GUARD.md.
//
// BENCH-PROVEN 2026-08-03 on 192.168.1.150 (0.15.1, vid 2507300): pushing an
// 8-entry all-stub `timers.ins` WIPED both a real clock timer and a LEASE timer
// (macro 27) from general slots 0-7. Only the slot-8 solar sentinel survived,
// and only because an 8-entry push never reaches slot 8.
//
// The path that produces such a payload: every enabled schedule is refused in
// syncAll's arm-check loop (all-solar with the solar flag off is the live
// case), so `armable` is empty, buildCfgPayload returns nothing, and
// padTimersToMax degrades the push to pure stubs. The pre-existing empty-armed
// guard cannot catch it — it keys on `armedSchedules.isNotEmpty`, and
// everything was dropped BEFORE armable.
//
// This suite pins [ScheduleSyncService.shouldSkipClobberingWrite] against the
// four cases that must all hold. The third one — "user deleted their last
// schedule" — is the regression risk: clearing IS correct there, and a guard
// that blocked it would strand stale timers forever (the dow:0 accumulation
// that padTimersToMax exists to fix).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

void main() {
  Map<String, dynamic> stub() =>
      {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0};

  /// A real enabled clock timer (what a normal schedule builds).
  Map<String, dynamic> clock({int hour = 20, int macro = 1}) =>
      {'en': 1, 'hour': hour, 'min': 0, 'macro': macro, 'dow': 127};

  /// A merged lease timer. NOTE: leases occupy GENERAL slots — macro 26-41 is a
  /// preset-id convention, not a slot reservation (bench-proven).
  Map<String, dynamic> lease({int macro = 27}) =>
      {'en': 1, 'hour': 19, 'min': 10, 'macro': macro, 'dow': 16};

  /// The slot-8 solar sentinel. Deliberately NOT "real" (hour == 255), so it
  /// must not by itself make a payload look armable.
  Map<String, dynamic> solarSentinel() =>
      {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127};

  List<Map<String, dynamic>> padded(List<Map<String, dynamic>> real) =>
      ScheduleSyncService.padTimersToMax(real);

  group('shouldSkipClobberingWrite — the four cases', () {
    test('all-solar + no leases → REFUSE (the fix)', () {
      // Two enabled solar schedules refused by the solar gate; nothing merged.
      final ins = padded(const []);
      expect(ins.length, ScheduleSyncService.kMaxWledTimers);
      expect(ins.every((t) => t['en'] == 0), isTrue,
          reason: 'payload must be pure stubs for this case to be meaningful');

      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 2),
        isTrue,
        reason: 'an all-stub push would erase slots 0-7 and arm nothing',
      );
    });

    test('all-solar + active leases → POST (Chris\'s leases must still arm)',
        () {
      // Schedules all refused, but the lease manager merged live leases in.
      final ins = padded([lease(), lease(macro: 28)]);

      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 2),
        isFalse,
        reason: 'the payload carries real lease timers — refusing to POST '
            'would leave those leases unarmed',
      );
    });

    test('user deleted their last schedule → POST (clearing is correct)', () {
      // Identical payload to case 1 — byte-for-byte. refusedCount is the ONLY
      // thing that distinguishes them, which is the whole point of the flag.
      final ins = padded(const []);

      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 0),
        isFalse,
        reason: 'nothing was refused, so the empty payload is a genuine clear; '
            'blocking it would strand stale timers on the controller',
      );
    });

    test('normal sync → POST', () {
      final ins = padded([clock(), clock(hour: 23, macro: 2)]);

      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 0),
        isFalse,
      );
      // Still POSTs even if some OTHER schedule was refused alongside.
      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 3),
        isFalse,
        reason: 'a partially-refused sync still has real timers to arm',
      );
    });
  });

  group('real builder chain — an all-solar set really does degrade to stubs',
      () {
    const svc = ScheduleSyncService();

    ScheduleItem solarSched(String id) => ScheduleItem(
          id: id,
          timeLabel: 'Sunset',
          offTimeLabel: 'Sunrise',
          repeatDays: const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
          actionLabel: 'Pattern: $id',
          enabled: true,
          presetId: 11,
        );

    test('buildCfgPayload + padTimersToMax on Ellie\'s shape → all stubs → SKIP',
        () {
      // Ellie Cochran's live shape: two enabled Sunset→Sunrise schedules.
      // syncAll refuses both in the arm-check loop, so buildCfgPayload is
      // handed an EMPTY list (armable) — reproduced here directly.
      final schedules = [solarSched('a'), solarSched('b')];

      // What buildCfgPayload does with them while solar is off: nothing.
      final direct = ((svc.buildCfgPayload(schedules)['timers'] as Map)['ins']
              as List)
          .cast<Map<String, dynamic>>();
      expect(direct, isEmpty,
          reason: 'solar-labelled schedules build no timers with solar off');

      // And what syncAll then pushes.
      final ins = ScheduleSyncService.padTimersToMax(direct);
      expect(ins.length, ScheduleSyncService.kMaxWledTimers);
      expect(ins.any(isRealEnabledTimer), isFalse);

      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: schedules.length),
        isTrue,
        reason: 'this is the exact payload that wiped a lease on the bench',
      );
    });

    test('same shape but with a lease merged → POSTs', () {
      final ins = ScheduleSyncService.padTimersToMax([lease()]);
      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 2),
        isFalse,
      );
    });
  });

  group('shouldSkipClobberingWrite — edge cases', () {
    test('a global sunrise-off at slot 8 DOES make the write worth sending',
        () {
      // A user with the global sunrise-off and every schedule refused. The
      // payload's only content is the slot-8 sentinel — but writing it is how
      // every sync RE-ASSERTS that slot rather than leaving it to luck, so it
      // must not be skipped.
      //
      // This is why the guard uses _carriesAnyEnabledEntry and NOT
      // isRealEnabledTimer, which excludes hour==255. The first version of this
      // guard used isRealEnabledTimer and broke sunrise_off_preserve_test.
      final ins = [...padded(const []), solarSentinel(), stub()];

      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 1),
        isFalse,
        reason: 'the sunrise-off is real content; skipping would silently stop '
            'the slot-8 re-assertion',
      );
    });

    test('empty ins with refusals is still a skip', () {
      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: const [], refusedCount: 1),
        isTrue,
      );
    });

    test('empty ins with no refusals still POSTs', () {
      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: const [], refusedCount: 0),
        isFalse,
      );
    });

    test('a disabled real-looking entry does not rescue the payload', () {
      // en:0 → not real. Guards against a future stub shape that carries a
      // macro but stays disabled.
      final ins = [
        {'en': 0, 'hour': 20, 'min': 0, 'macro': 1, 'dow': 127},
        ...padded(const []),
      ];

      expect(
        ScheduleSyncService.shouldSkipClobberingWrite(
            ins: ins, refusedCount: 1),
        isTrue,
      );
    });
  });
}
