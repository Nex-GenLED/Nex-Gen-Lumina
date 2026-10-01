// +112 (#121) — the one gate that decides recurring vs dated for every Lumina
// entry point. Phrase table in the E2 style: input → expected.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/recurring_request_phrases.dart';

void main() {
  group('explicitRecurringRequested — asks to repeat', () {
    const yes = <String>[
      'chiefs every friday',
      'warm white every night',
      'Every Night at sunset turn on the patio',
      'each evening from dusk to dawn',
      'nightly warm white',
      'daily at 7pm',
      'red and green weekly',
      'every weekday at 6pm',
      'every weeknight',
      'every weekend',
      'blue on fridays',
      'royals every mon and wed',
      'every thursday',
    ];
    for (final s in yes) {
      test('"$s" → recurring', () {
        expect(explicitRecurringRequested(s), isTrue);
      });
    }
  });

  group('explicitRecurringRequested — bounded or one-off (NOT recurring)', () {
    const no = <String>[
      'chiefs for the next three nights',
      'chiefs all week',
      'warm white every night this week',
      'every night next week',
      'next 3 nights',
      'this weekend',
      'all weekend',
      'through sunday',
      'the rest of the week',
      'tonight',
      'a night light look',
      'friday night lights',
      'chiefs on friday',
      'blue on december 25',
      'orange for halloween',
    ];
    for (final s in no) {
      test('"$s" → dated', () {
        expect(explicitRecurringRequested(s), isFalse);
      });
    }
  });

  group('explicitRecurringWeekdays', () {
    test('names the days', () {
      expect(explicitRecurringWeekdays('chiefs every friday'), {'Fri'});
      expect(explicitRecurringWeekdays('royals every mon and every wed'),
          {'Mon', 'Wed'});
      expect(explicitRecurringWeekdays('blue on fridays'), {'Fri'});
    });
    test('weekday / weekend shorthands expand', () {
      expect(explicitRecurringWeekdays('every weekday'),
          {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'});
      expect(explicitRecurringWeekdays('every weekend'), {'Sat', 'Sun'});
    });
    test('"every night" names no day (caller reads it as daily)', () {
      expect(explicitRecurringWeekdays('warm white every night'), isEmpty);
    });
  });
}
