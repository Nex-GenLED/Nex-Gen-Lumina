// +110 package E2, item 4 — the multi-night plan becomes dated calendar
// entries, and the reply is composed from what actually happened.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_flags.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_persistence.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';

LuminaScheduleFlags _flags({
  int nights = 3,
  String start = 'sunset',
  String end = 'sunrise',
}) =>
    LuminaScheduleFlags.fromResponseJson({
      'isSchedule': true,
      'scheduleType': 'multi_day',
      'dayCount': nights,
      'patternName': 'Christmas — $nights-Night Schedule',
      'themeName': 'Christmas',
      'startTrigger': start,
      'endTrigger': end,
      'schedule': [
        for (int i = 0; i < nights; i++)
          {
            'dayIndex': i,
            'date': DateTime(2026, 12, 20 + i).toIso8601String(),
            'patternName': 'Christmas night ${i + 1}',
            'effectName': ['Twinkle', 'Breathe', 'Running'][i % 3],
            'startTrigger': start,
            'endTrigger': end,
            'colors': [
              {
                'name': 'Red',
                'rgb': [255, 0, 0, 0]
              }
            ],
            'wled': {
              'on': true,
              'bri': 255,
              'seg': [
                {
                  'fx': 43,
                  'col': [
                    [255, 0, 0, 0]
                  ]
                }
              ],
            },
          },
      ],
    })!;

void main() {
  group('plannedNightsOf', () {
    test('one night per plan entry, dated, with fallback clock times', () {
      final nights = plannedNightsOf(_flags());
      expect(nights.length, 3);
      expect(nights.first.dateKey, '2026-12-20');
      expect(nights.first.onTime, '20:00'); // no coordinates → fallback
      expect(nights.first.offTime, '06:00');
      expect(nights.first.brightnessPercent, 100);
      expect(nights[1].summary, 'Mon — Breathe');
    });

    test('uses real sun times when the account has coordinates', () {
      final nights = plannedNightsOf(_flags(),
          latitude: 39.1, longitude: -94.6); // Kansas City
      expect(nights.first.onTime, isNot('20:00'));
      expect(nights.first.onTime, matches(RegExp(r'^\d\d:\d\d$')));
      // A December sunset in Kansas City is around 5 pm local.
      final hour = int.parse(nights.first.onTime!.split(':').first);
      expect(hour, inInclusiveRange(15, 19));
    });

    test('a specific-time plan carries no hours, so no clock', () {
      final nights =
          plannedNightsOf(_flags(start: 'specificTime', end: 'specificTime'));
      expect(nights.first.hasClockTimes, isFalse);
      expect(calendarEntryForNight(nights.first, batchId: 'b'), isNull);
    });
  });

  group('calendarEntryForNight', () {
    test('a dated, Lumina-tagged autopilot entry with clock times', () {
      final night = plannedNightsOf(_flags()).first;
      final e = calendarEntryForNight(night, batchId: 'b1')!;
      expect(e.dateKey, '2026-12-20');
      expect(e.entryId, 'lumina_b1_0');
      expect(e.onTime, '20:00');
      expect(e.offTime, '06:00');
      expect(e.type, CalendarEntryType.autopilot);
      expect(e.sourceTag, kLuminaAiSourceTag);
      expect(e.patternName, 'Christmas night 1');
    });
  });

  group('composeScheduleReply', () {
    final nights = plannedNightsOf(_flags());

    test('every night landed', () {
      final text = composeScheduleReply(
        themeName: 'Christmas',
        appliedOk: true,
        nights: nights,
        outcome: const ScheduleNightsOutcome(requested: 3, persisted: 3),
      );
      expect(text, contains("Tonight's Christmas look is on your lights now."));
      expect(text, contains('other 2 nights are in your Schedule'));
      expect(text, contains('Mon — Breathe'));
      expect(text, isNot(contains("I've scheduled")));
    });

    test('nothing persisted → only tonight, said plainly', () {
      final text = composeScheduleReply(
        themeName: 'Christmas',
        appliedOk: true,
        nights: nights,
        outcome: const ScheduleNightsOutcome(
            requested: 3, persisted: 0, message: 'sign in first.'),
      );
      expect(text, contains('Only tonight was applied'));
      expect(text, contains('sign in first.'));
      expect(text, contains("won't run on their own"));
    });

    test('tonight failed to apply → leads with why', () {
      final text = composeScheduleReply(
        themeName: 'Christmas',
        appliedOk: false,
        applyMessage: 'No controller is set up yet.',
        nights: nights,
        outcome: const ScheduleNightsOutcome(requested: 3, persisted: 3),
      );
      expect(text, startsWith("I couldn't put tonight's Christmas look"));
      expect(text, contains('No controller is set up yet.'));
    });

    test('a one-night plan is just tonight', () {
      final text = composeScheduleReply(
        themeName: 'Christmas',
        appliedOk: true,
        nights: plannedNightsOf(_flags(nights: 1)),
        outcome: ScheduleNightsOutcome.nothingToPersist,
      );
      expect(text, "Tonight's Christmas look is on your lights now.");
    });
  });
}
