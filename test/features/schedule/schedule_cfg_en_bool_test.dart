// Builder-level tests for the P0 en-must-be-bool fix (bench-proven 2026-07-21,
// WLED vid 2507300: the cfg parser is type-strict — an int en is silently
// treated as DISABLED). These are the tests that were missing when a8db4ba
// changed 'en': true → 'en': 1 and shipped disabled timers under a false green.
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

  group('buildCfgPayload emits en as a JSON BOOL (the P0)', () {
    test('enabled clock schedule → en === true (bool), correct fields', () {
      final ins = insFor([item(timeLabel: '10:40', presetId: 12)]);
      expect(ins.length, 1);
      final e = ins.single;
      // The whole point: a real JSON boolean, NOT int 1, NOT the string "true".
      expect(e['en'], isA<bool>(), reason: 'WLED requires a JSON bool');
      expect(e['en'], isTrue);
      expect(e['en'], isNot(1), reason: 'int 1 is silently disabled by WLED');
      expect(e['en'], isNot('true'));
      expect(e['hour'], 10);
      expect(e['min'], 40);
      expect(e['macro'], 12);
      expect(e['dow'], 127); // Daily
    });

    test('ON + OFF pair both emit en:true (bool); OFF macro is 2', () {
      final ins = insFor([item(timeLabel: '6:00 PM', offTimeLabel: '11:00 PM')]);
      expect(ins.length, 2);
      for (final e in ins) {
        expect(e['en'], isA<bool>());
        expect(e['en'], isTrue);
      }
      expect(ins[0]['macro'], 10); // ON → presetId
      expect(ins[1]['macro'], 2); // OFF → preset 2 convention
    });

    test('solar slot entry (buildSolarTimerEntry) also emits en:true (bool)', () {
      // The production solar path is the dedicated slot 8/9 entry (hour:255),
      // built by buildSolarTimerEntry — flag-gated in buildCfgPayload, so test
      // the builder directly. (:247)
      final e = ScheduleSyncService.buildSolarTimerEntry(
          offsetMinutes: 0, macro: 5, dow: 127);
      expect(e['en'], isA<bool>());
      expect(e['en'], isTrue);
      expect(e['hour'], 255);
    });
  });

  group('disabled / padding', () {
    test('disabled schedule is EXCLUDED from the built payload', () {
      expect(insFor([item(timeLabel: '10:40', enabled: false)]), isEmpty);
    });

    test('padTimersToMax fills empty slots with en:false (bool) stubs', () {
      final padded = ScheduleSyncService.padTimersToMax(const []);
      expect(padded.length, 8);
      for (final stub in padded) {
        expect(stub['en'], isA<bool>());
        expect(stub['en'], isFalse, reason: 'a stub must reliably disable');
        expect(stub['en'], isNot(0));
      }
    });

    test('one real timer + padding: real is en:true bool, rest en:false bool',
        () {
      final built = insFor([item(timeLabel: '10:40', presetId: 12)]);
      final padded = ScheduleSyncService.padTimersToMax(built);
      expect(padded.length, 8);
      expect(padded.first['en'], true);
      expect(padded.skip(1).every((s) => s['en'] == false), isTrue);
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
