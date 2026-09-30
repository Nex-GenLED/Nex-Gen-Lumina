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
      // SunUtils renders the sunset in the MACHINE's time zone (it uses
      // DateTime.timeZoneOffset), so compare the instant, not the clock face:
      // a Kansas City December sunset is about 22:58 UTC whatever zone the
      // test runs in (Codemagic's Mac is UTC; this PC is Central).
      final parts = nights.first.onTime!.split(':').map(int.parse).toList();
      final asUtc = DateTime(2026, 12, 20, parts[0], parts[1]).toUtc();
      expect(asUtc.hour, anyOf(22, 23),
          reason: 'sunset instant must be ~22:58Z regardless of machine zone');
    });

    test('a specific-time plan carries no hours, so no clock', () {
      final nights =
          plannedNightsOf(_flags(start: 'specificTime', end: 'specificTime'));
      expect(nights.first.hasClockTimes, isFalse);
      expect(calendarEntryForNight(nights.first, batchId: 'b'), isNull);
    });
  });

  group('calendarEntryForNight', () {
    test('a dated, Lumina-tagged USER entry (AI-generated) with clock times',
        () {
      final night = plannedNightsOf(_flags()).first;
      final e = calendarEntryForNight(night, batchId: 'b1')!;
      expect(e.dateKey, '2026-12-20');
      expect(e.entryId, 'lumina_b1_0');
      expect(e.onTime, '20:00');
      expect(e.offTime, '06:00');
      // D2 — the customer asked for it: theirs, marked AI-generated.
      expect(e.type, CalendarEntryType.user);
      expect(e.autopilot, isTrue);
      expect(e.sourceTag, kLuminaAiSourceTag);
      expect(e.patternName, 'Christmas night 1');
    });
  });

  group('D2 — planLuminaNightWrites never overwrites', () {
    final nights = plannedNightsOf(_flags()); // Sun 12-20, Mon 12-21, Tue 12-22

    CalendarEntry gameDay(String dateKey) => CalendarEntry(
          entryId: CalendarEntryId.gameDay('team-a'),
          dateKey: dateKey,
          patternName: 'Team A Colors',
          onTime: '19:00',
          offTime: '22:30',
          type: CalendarEntryType.autopilot,
          autopilot: true,
          sourceTag: CalendarEntrySourceTag.gameDay,
          note: 'Team A vs Team B — Game Day autopilot',
        );

    CalendarEntry mine(String dateKey) => CalendarEntry(
          entryId: 'user_1',
          dateKey: dateKey,
          patternName: 'Birthday Blue',
          onTime: '18:00',
          offTime: '23:00',
          type: CalendarEntryType.user,
          autopilot: false,
        );

    CalendarEntry holiday(String dateKey) => CalendarEntry(
          entryId: CalendarEntryId.holiday,
          dateKey: dateKey,
          patternName: 'Holiday',
          onTime: '17:30',
          offTime: '23:30',
          type: CalendarEntryType.holiday,
          autopilot: false,
        );

    test('an empty calendar → every night is written', () {
      final plan = planLuminaNightWrites(
          nights: nights, batchId: 'b', existingOn: (_) => const []);
      expect(plan.entries.length, 3);
      expect(plan.skipped, isEmpty);
      expect(plan.noClock, 0);
      expect(plan.entries.map((e) => e.entryId),
          ['lumina_b_0', 'lumina_b_1', 'lumina_b_2']);
    });

    test('a Game Day entry on a night → skipped, and the reply names the '
        'team', () {
      final plan = planLuminaNightWrites(
        nights: nights,
        batchId: 'b',
        existingOn: (k) => k == '2026-12-21' ? [gameDay(k)] : const [],
      );
      expect(plan.entries.map((e) => e.dateKey), ['2026-12-20', '2026-12-22']);
      expect(plan.skipped.single.reason, LuminaNightSkipReason.gameDay);
      expect(plan.skipped.single.reply,
          'Skipped Mon — the Team A game already has that night.');
    });

    test('an armed lease on a night → skipped', () {
      final plan = planLuminaNightWrites(
        nights: nights,
        batchId: 'b',
        existingOn: (_) => const [],
        leasedDateKeys: {'2026-12-22'},
      );
      expect(plan.entries.length, 2);
      expect(plan.skipped.single.reason, LuminaNightSkipReason.armed);
      expect(plan.skipped.single.reply, startsWith('Skipped Tue — '));
    });

    test('a user-authored entry on a night → skipped, named, never replaced '
        '(the A3 overwrite guard, without a prompt)', () {
      final plan = planLuminaNightWrites(
        nights: nights,
        batchId: 'b',
        existingOn: (k) => k == '2026-12-20' ? [mine(k)] : const [],
      );
      expect(plan.entries.length, 2);
      expect(plan.skipped.single.reason, LuminaNightSkipReason.userEntry);
      expect(plan.skipped.single.reply, contains('"Birthday Blue"'));
      expect(plan.skipped.single.reply, contains('Delete it in Schedule'));
    });

    test('a previous Lumina night is a user entry too, so it is not '
        'overwritten either', () {
      final earlier = calendarEntryForNight(nights[1], batchId: 'old')!;
      final plan = planLuminaNightWrites(
        nights: nights,
        batchId: 'new',
        existingOn: (k) => k == earlier.dateKey ? [earlier] : const [],
      );
      expect(plan.skipped.single.reason, LuminaNightSkipReason.userEntry);
    });

    test('a holiday default does not block a night', () {
      final plan = planLuminaNightWrites(
        nights: nights,
        batchId: 'b',
        existingOn: (k) => [holiday(k)],
      );
      expect(plan.entries.length, 3);
      expect(plan.skipped, isEmpty);
    });

    test('Game Day wins the sentence when several things share the night', () {
      final plan = planLuminaNightWrites(
        nights: nights,
        batchId: 'b',
        existingOn: (k) => k == '2026-12-21' ? [mine(k), gameDay(k)] : const [],
        leasedDateKeys: {'2026-12-21'},
      );
      expect(plan.skipped.single.reason, LuminaNightSkipReason.gameDay);
    });

    test('a night with no clock time is counted, not skipped', () {
      final plan = planLuminaNightWrites(
        nights: plannedNightsOf(_flags(start: 'specificTime', end: 'specificTime')),
        batchId: 'b',
        existingOn: (_) => const [],
      );
      expect(plan.entries, isEmpty);
      expect(plan.skipped, isEmpty);
      expect(plan.noClock, 3);
    });

    test('gameDayTeamNameOf reads the note the Game Day service writes', () {
      expect(gameDayTeamNameOf(gameDay('2026-12-21')), 'Team A');
      expect(
          gameDayTeamNameOf(gameDay('2026-12-21')
              .copyWith(note: 'Team C @ Team D — Game Day autopilot')),
          'Team C');
      expect(gameDayTeamNameOf(mine('2026-12-21')), isNull);
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

    // D2 — skips and a full timer pool are said, never claimed.
    test('a skipped night is named after the nights that were saved', () {
      final text = composeScheduleReply(
        themeName: 'Christmas',
        appliedOk: true,
        nights: nights,
        outcome: const ScheduleNightsOutcome(
          requested: 3,
          persisted: 2,
          saved: [0, 2],
          skipped: ['Skipped Mon — the Team A game already has that night.'],
        ),
      );
      expect(text, contains('I saved 1 of the other 2 nights to your Schedule: '
          'Tue — Running.'));
      expect(text, contains('Skipped Mon — the Team A game already has that night.'));
      expect(text, isNot(contains('Mon — Breathe')));
    });

    test('nights that did not fit are counted, in the decided words', () {
      final text = composeScheduleReply(
        themeName: 'Christmas',
        appliedOk: true,
        nights: nights,
        outcome: const ScheduleNightsOutcome(
          requested: 3,
          persisted: 1,
          saved: [0],
          unfitted: 2,
        ),
      );
      expect(text, contains("I couldn't fit 2 nights — your schedule is full."));
      expect(text, contains('none of the other 2 nights could be saved'));
      expect(text, isNot(contains("won't run on their own")));
    });

    test('every other night skipped → tonight only, with each reason', () {
      final text = composeScheduleReply(
        themeName: 'Christmas',
        appliedOk: true,
        nights: nights,
        outcome: const ScheduleNightsOutcome(
          requested: 3,
          persisted: 1,
          saved: [0],
          skipped: ['Skipped Mon — a.', 'Skipped Tue — b.'],
        ),
      );
      expect(text, contains('Only tonight was applied'));
      expect(text, contains('Skipped Mon — a. Skipped Tue — b.'));
    });
  });
}
