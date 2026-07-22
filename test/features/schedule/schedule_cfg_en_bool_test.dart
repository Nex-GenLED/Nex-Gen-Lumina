// Builder-level tests for the P0 en-must-be-INT fix (curl-proven 2026-07-22,
// WLED vid 2507300: the cfg parser reads en type-strictly as an int — a JSON
// bool is silently stored as 0/DISABLED. `{"en":true}`→en:0; `{"en":1}`→en:1).
// f781e68 had it backwards (int → bool) and shipped disabled timers under a
// false green; this reverts en to int and locks the direction with a test.
//
// Also covers the empty-armed guard's decision predicate (isRealEnabledTimer),
// which syncAll uses to refuse POSTing an all-stub payload that would false-green.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

void main() {
  const svc = ScheduleSyncService();

  ScheduleItem item({
    required String timeLabel,
    String? offTimeLabel,
    bool enabled = true,
    int? presetId = 10,
    List<String> repeatDays = const ['Daily'],
  }) =>
      ScheduleItem(
        id: 't',
        timeLabel: timeLabel,
        offTimeLabel: offTimeLabel,
        repeatDays: repeatDays,
        actionLabel: 'Pattern: Test',
        enabled: enabled,
        presetId: presetId,
      );

  List<Map<String, dynamic>> insFor(List<ScheduleItem> s) =>
      ((svc.buildCfgPayload(s)['timers'] as Map)['ins'] as List)
          .cast<Map<String, dynamic>>();

  group('buildCfgPayload emits en as a JSON INT (the P0)', () {
    test('enabled clock schedule → en === 1 (int), correct fields', () {
      final ins = insFor([item(timeLabel: '10:40', presetId: 12)]);
      expect(ins.length, 1);
      final e = ins.single;
      // The whole point: the integer 1, NOT a JSON bool, NOT the string "1".
      // Curl-proven 2026-07-22: WLED stores a bool en as 0 (disabled).
      expect(e['en'], isA<int>(), reason: 'WLED requires an int en');
      expect(e['en'], 1);
      expect(e['en'], isNot(true), reason: 'a JSON bool is silently disabled');
      expect(e['en'], isNot('1'));
      expect(e['hour'], 10);
      expect(e['min'], 40);
      expect(e['macro'], 12);
      expect(e['dow'], 127); // Daily
    });

    test('ON + OFF pair both emit en:1 (int); OFF macro is 2', () {
      final ins = insFor([item(timeLabel: '6:00 PM', offTimeLabel: '11:00 PM')]);
      expect(ins.length, 2);
      for (final e in ins) {
        expect(e['en'], isA<int>());
        expect(e['en'], 1);
      }
      expect(ins[0]['macro'], 10); // ON → presetId
      expect(ins[1]['macro'], 2); // OFF → preset 2 convention
    });

    test('solar slot entry (buildSolarTimerEntry) also emits en:1 (int)', () {
      // The production solar path is the dedicated slot 8/9 entry (hour:255),
      // built by buildSolarTimerEntry — flag-gated in buildCfgPayload, so test
      // the builder directly.
      final e = ScheduleSyncService.buildSolarTimerEntry(
          offsetMinutes: 0, macro: 5, dow: 127);
      expect(e['en'], isA<int>());
      expect(e['en'], 1);
      expect(e['hour'], 255);
    });
  });

  group('disabled / padding', () {
    test('disabled schedule is EXCLUDED from the built payload', () {
      expect(insFor([item(timeLabel: '10:40', enabled: false)]), isEmpty);
    });

    test('padTimersToMax fills empty slots with en:0 (int) stubs', () {
      final padded = ScheduleSyncService.padTimersToMax(const []);
      expect(padded.length, 8);
      for (final stub in padded) {
        expect(stub['en'], isA<int>());
        expect(stub['en'], 0, reason: 'a stub must reliably disable');
        expect(stub['en'], isNot(false));
      }
    });

    test('one real timer + padding: real is en:1 int, rest en:0 int', () {
      final built = insFor([item(timeLabel: '10:40', presetId: 12)]);
      final padded = ScheduleSyncService.padTimersToMax(built);
      expect(padded.length, 8);
      expect(padded.first['en'], 1);
      expect(padded.skip(1).every((s) => s['en'] == 0), isTrue);
    });
  });

  group('empty-armed guard predicate (isRealEnabledTimer)', () {
    Map<String, dynamic> t(Object en, {int hour = 10, int macro = 12}) =>
        {'en': en, 'hour': hour, 'min': 0, 'macro': macro, 'dow': 127};

    test('real enabled entry (bool true) → true', () {
      expect(isRealEnabledTimer(t(true)), isTrue);
    });
    test('legacy int en:1 still recognized → true (comparator back-compat)', () {
      expect(isRealEnabledTimer(t(1)), isTrue);
    });
    test('disabled stub (en:false) → false', () {
      expect(isRealEnabledTimer(t(false, hour: 0, macro: 0)), isFalse);
    });
    test('int en:0 → false', () {
      expect(isRealEnabledTimer(t(0, hour: 0, macro: 0)), isFalse);
    });
    test('solar sentinel (hour:255) → false', () {
      expect(isRealEnabledTimer(t(true, hour: 255, macro: 0)), isFalse);
    });
    test('enabled but macro:0 (off command / stub) → false', () {
      expect(isRealEnabledTimer(t(true, macro: 0)), isFalse);
    });

    test('guard decision: all-stub payload has NO real entries (guard fires)',
        () {
      final allStubs = ScheduleSyncService.padTimersToMax(const []);
      // syncAll aborts when armedSchedules.isNotEmpty && !ins.any(isRealEnabledTimer)
      expect(allStubs.any(isRealEnabledTimer), isFalse);
    });

    test('guard decision: a real entry present → guard passes', () {
      final built = insFor([item(timeLabel: '10:40')]);
      final padded = ScheduleSyncService.padTimersToMax(built);
      expect(padded.any(isRealEnabledTimer), isTrue);
    });
  });
}
