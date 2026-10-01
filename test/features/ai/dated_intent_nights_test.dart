// +112 (#121) — the chat's schedulingIntents as dated nights (pure half).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/dated_intent_nights.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_persistence.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';

void main() {
  final wed = DateTime(2026, 4, 1); // Wednesday

  group('nextDatesForDays', () {
    test('each repeat day → its next date within a week, today included', () {
      final d = nextDatesForDays(const ['Thu', 'Fri', 'Sat'], wed);
      expect(d, [DateTime(2026, 4, 2), DateTime(2026, 4, 3), DateTime(2026, 4, 4)]);
    });
    test('today counts; the week wraps; unknown labels ignored', () {
      final d = nextDatesForDays(const ['Wed', 'Mon', 'Someday'], wed);
      expect(d, [DateTime(2026, 4, 1), DateTime(2026, 4, 6)]);
    });
    test('all seven → the next seven nights', () {
      expect(nextDatesForDays(const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], wed).length, 7);
    });
  });

  group('plannedNightsFromIntents', () {
    const payload = <String, dynamic>{
      'on': true,
      'bri': 204,
      'seg': [
        {
          'fx': 52,
          'col': [
            [227, 24, 55, 0],
            [255, 184, 28, 0],
          ],
        },
      ],
    };

    test('clock times pass through, missing off time ends at sunrise', () {
      final nights = plannedNightsFromIntents(
        intents: const [
          SchedulingIntent(
            timeLabel: '19:00',
            repeatDays: ['Thu', 'Fri'],
            patternName: 'Chiefs Night',
          ),
        ],
        sharedPayload: payload,
        now: wed,
      );
      expect(nights.length, 2);
      expect(nights.first.onTime, '19:00');
      expect(nights.first.offTime, '06:00', reason: 'no coordinates → default sunrise');
      expect(nights.first.wled, payload, reason: 'the full look rides along');
      expect(nights.first.brightnessPercent, 80);
      expect(nights.first.color, isNotNull);
      expect(nights.map((n) => n.index), [0, 1]);
    });

    test('a 12-hour label is normalised and Sunset resolves with coordinates', () {
      final nights = plannedNightsFromIntents(
        intents: const [
          SchedulingIntent(
            timeLabel: 'Sunset',
            offTimeLabel: '11:30 PM',
            repeatDays: ['Thu'],
            patternName: 'x',
          ),
        ],
        now: wed,
        latitude: 39.0,
        longitude: -94.6,
      );
      expect(nights.single.offTime, '23:30');
      final h = int.parse(nights.single.onTime!.split(':')[0]);
      expect(h, inInclusiveRange(18, 21));
    });

    test('two intents on the same date: first claims it; sorted by date', () {
      final nights = plannedNightsFromIntents(
        intents: const [
          SchedulingIntent(timeLabel: '20:00', repeatDays: ['Sat'], patternName: 'b'),
          SchedulingIntent(timeLabel: '19:00', repeatDays: ['Thu', 'Sat'], patternName: 'a'),
        ],
        now: wed,
      );
      expect(nights.map((n) => n.date), [DateTime(2026, 4, 2), DateTime(2026, 4, 4)]);
      expect(nights.last.onTime, '20:00', reason: 'Saturday kept the first intent');
    });

    test('a per-intent wled beats the shared payload', () {
      final nights = plannedNightsFromIntents(
        intents: const [
          SchedulingIntent(
            timeLabel: '19:00',
            repeatDays: ['Thu'],
            patternName: 'x',
            wled: {'on': true, 'bri': 51, 'seg': []},
          ),
        ],
        sharedPayload: payload,
        now: wed,
      );
      expect(nights.single.brightnessPercent, 20);
    });
  });

  group('datedNightsReply', () {
    final nights = plannedNightsFromIntents(
      intents: const [
        SchedulingIntent(timeLabel: '19:00', repeatDays: ['Thu', 'Fri', 'Sat'], patternName: 'Chiefs Night'),
      ],
      now: wed,
    );

    test('all saved: names the nights and says they do not repeat', () {
      final r = datedNightsReply(
        themeName: 'Chiefs Night',
        nights: nights,
        outcome: const ScheduleNightsOutcome(requested: 3, persisted: 3, saved: [0, 1, 2]),
      );
      expect(r, contains('3 nights'));
      expect(r, contains('Thu, Fri, Sat'));
      expect(r, contains('every night'));
    });

    test('skips and a full pool are named', () {
      final r = datedNightsReply(
        themeName: 'Chiefs Night',
        nights: nights,
        outcome: const ScheduleNightsOutcome(
          requested: 3,
          persisted: 1,
          saved: [0],
          skipped: ['Skipped Fri — the Chiefs game already has that night.'],
          unfitted: 1,
        ),
      );
      expect(r, contains('runs that night only'));
      expect(r, contains('Chiefs game already has that night'));
      expect(r, contains("couldn't fit 1 night"));
    });

    test('nothing saved: says so, with the reason', () {
      final r = datedNightsReply(
        themeName: 'Chiefs Night',
        nights: nights,
        outcome: const ScheduleNightsOutcome(requested: 3, persisted: 0, message: 'the Schedule was offline.'),
      );
      expect(r, startsWith("I couldn't save"));
      expect(r, contains('offline'));
    });
  });
}
