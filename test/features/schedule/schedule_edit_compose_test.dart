import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart'
    show composeEditedSchedule;
import 'package:nexgen_command/features/schedule/schedule_models.dart';

// The schedule-editor SAVE write path (composeEditedSchedule). Edit reuses the
// create editor pre-filled; these pin the two invariants that make that safe:
// in-place id (no duplicate) and design-payload fidelity. Field pre-fill and
// the tap wiring live in the widget; the arming of a clock time is covered by
// schedule_solar_refuse_test + schedule_slot_reclaim_test.
void main() {
  ScheduleItem existing({
    String id = 'sch-1',
    String time = 'Sunset',
    String? off = 'Sunrise',
    Map<String, dynamic>? payload = const {'on': true, 'bri': 200},
    int? presetId = 11,
  }) =>
      ScheduleItem(
        id: id,
        timeLabel: time,
        offTimeLabel: off,
        repeatDays: const ['Mon', 'Wed', 'Fri'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
        wledPayload: payload,
        presetId: presetId,
      );

  group('in-place edit — no duplicate', () {
    test('editing keeps the existing id (caller passes editing.id)', () {
      final e = existing(id: 'sch-abc');
      final item = composeEditedSchedule(
        id: e.id,
        editing: e,
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        days: const ['Mon'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
        isRunPattern: true,
        useAudioReactive: false,
        pickedPayload: null,
      );
      expect(item.id, 'sch-abc', reason: 'same id → update replaces, no dupe');
      expect(item.presetId, 11, reason: 'preset slot preserved');
    });
  });

  group('solar → clock recovery (edit a refused solar schedule)', () {
    test('a solar schedule edited to a clock time stores the clock label', () {
      final solar = existing(time: 'Sunset', off: 'Sunrise');
      final item = composeEditedSchedule(
        id: solar.id,
        editing: solar,
        timeLabel: '6:30 PM', // user switched the ON trigger Solar → Time
        offTimeLabel: '10:00 PM', // and the OFF trigger too
        days: const ['Mon', 'Wed', 'Fri'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
        isRunPattern: true,
        useAudioReactive: false,
        pickedPayload: null,
      );
      expect(item.timeLabel, '6:30 PM');
      expect(item.offTimeLabel, '10:00 PM');
      // No longer solar → schedule_sync will arm it (see the refuse-guard tests).
    });
  });

  group('design fidelity', () {
    test('runPattern edit WITHOUT re-pick keeps the existing design', () {
      final e = existing(payload: const {'on': true, 'bri': 180, 'seg': []});
      final item = composeEditedSchedule(
        id: e.id,
        editing: e,
        timeLabel: '7:00 PM',
        offTimeLabel: null,
        days: const ['Mon'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
        isRunPattern: true,
        useAudioReactive: false,
        pickedPayload: null, // 'existing' hydration carries no payload
      );
      expect(item.wledPayload, e.wledPayload,
          reason: 'no re-pick must not blank the design');
    });

    test('runPattern edit WITH a re-pick uses the new design', () {
      final e = existing(payload: const {'on': true, 'bri': 180});
      const picked = {'on': true, 'bri': 255, 'seg': [<String, dynamic>{}]};
      final item = composeEditedSchedule(
        id: e.id,
        editing: e,
        timeLabel: '7:00 PM',
        offTimeLabel: null,
        days: const ['Mon'],
        actionLabel: 'Pattern: New',
        enabled: true,
        isRunPattern: true,
        useAudioReactive: false,
        pickedPayload: picked,
      );
      expect(item.wledPayload, picked);
    });

    test('audio-reactive carries existing payload, sets the flag (no leak)', () {
      final e = existing(payload: const {'on': true, 'bri': 180});
      const picked = {'on': true, 'bri': 255};
      final item = composeEditedSchedule(
        id: e.id,
        editing: e,
        timeLabel: '7:00 PM',
        offTimeLabel: null,
        days: const ['Mon'],
        actionLabel: 'React to Music',
        enabled: true,
        isRunPattern: true,
        useAudioReactive: true,
        pickedPayload: picked, // must be IGNORED for audio-reactive
      );
      expect(item.wledPayload, e.wledPayload,
          reason: 'audio branch builds state at sync time, not from a re-pick');
      expect(item.useAudioReactive, true);
    });

    test('brightness/power-off (not runPattern) never leaks a picked design',
        () {
      final e = existing(payload: const {'on': true, 'bri': 180});
      const picked = {'on': true, 'bri': 255};
      final item = composeEditedSchedule(
        id: e.id,
        editing: e,
        timeLabel: '7:00 PM',
        offTimeLabel: null,
        days: const ['Mon'],
        actionLabel: 'Brightness: 40%',
        enabled: true,
        isRunPattern: false,
        useAudioReactive: false,
        pickedPayload: picked, // ignored on the non-pattern path
      );
      expect(item.wledPayload, e.wledPayload);
      expect(item.useAudioReactive, isNull);
    });
  });

  group('enable toggle + new schedule', () {
    test('enable state round-trips', () {
      final e = existing();
      final off = composeEditedSchedule(
        id: e.id,
        editing: e,
        timeLabel: '7:00 PM',
        offTimeLabel: null,
        days: const ['Mon'],
        actionLabel: 'Pattern: Warm White',
        enabled: false,
        isRunPattern: true,
        useAudioReactive: false,
        pickedPayload: null,
      );
      expect(off.enabled, isFalse);
    });

    test('new schedule (editing null) uses the picked payload, no preset', () {
      const picked = {'on': true, 'bri': 200};
      final item = composeEditedSchedule(
        id: 'sch-new',
        editing: null,
        timeLabel: '7:00 PM',
        offTimeLabel: null,
        days: const ['Mon'],
        actionLabel: 'Pattern: New',
        enabled: true,
        isRunPattern: true,
        useAudioReactive: false,
        pickedPayload: picked,
      );
      expect(item.id, 'sch-new');
      expect(item.wledPayload, picked);
      expect(item.presetId, isNull);
    });
  });
}
