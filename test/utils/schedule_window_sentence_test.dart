// +126 (g) — the plain-words line under the schedule editor's wheels.
//
// The helper takes the labels the editor would save and the firing side's own
// overnight answer (offFallsNextDay), so the sentence can never disagree with
// the timers about which day the lights go off.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/utils/time_format.dart';

/// The sentence as the editor builds it: offNextDay from the real rule.
String _sentence(String on, String? off, {String timeFormat = '12h'}) {
  final probe = ScheduleItem(
    id: 'p',
    timeLabel: on,
    offTimeLabel: off,
    repeatDays: const [],
    actionLabel: '',
    enabled: true,
  );
  return scheduleWindowSentence(
    onLabel: on,
    offLabel: off,
    offNextDay: offFallsNextDay(probe),
    timeFormat: timeFormat,
  );
}

void main() {
  group('scheduleWindowSentence', () {
    test('an overnight clock window says "the next morning"', () {
      expect(_sentence('5:00 PM', '6:00 AM'),
          'Lights on at 5:00 PM, off at 6:00 AM the next morning.');
    });

    test('a same-evening window says "this evening"', () {
      expect(_sentence('5:00 PM', '11:00 PM'),
          'Lights on at 5:00 PM, off at 11:00 PM this evening.');
    });

    test('a same-day daytime window follows the OFF hour', () {
      expect(_sentence('9:00 AM', '2:00 PM'),
          'Lights on at 9:00 AM, off at 2:00 PM this afternoon.');
      expect(_sentence('6:00 AM', '11:30 AM'),
          'Lights on at 6:00 AM, off at 11:30 AM this morning.');
    });

    test('AM/PM wording: noon and midnight read as 12:00 PM / 12:00 AM', () {
      expect(_sentence('12:00 PM', '12:00 AM'),
          'Lights on at 12:00 PM, off at 12:00 AM the next morning.');
    });

    test('solar labels read in lower case inside the sentence', () {
      expect(_sentence('Sunset', 'Sunrise'),
          'Lights on at sunset, off at sunrise the next morning.');
      expect(_sentence('Sunset', '11:00 PM'),
          'Lights on at sunset, off at 11:00 PM this evening.');
      expect(_sentence('Sunset', '1:00 AM'),
          'Lights on at sunset, off at 1:00 AM the next morning.');
      expect(_sentence('Sunrise', 'Sunset'),
          'Lights on at sunrise, off at sunset this evening.');
      expect(_sentence('6:00 PM', 'Sunrise'),
          'Lights on at 6:00 PM, off at sunrise the next morning.');
    });

    test('no off time: the lights stay on', () {
      expect(_sentence('5:00 PM', null),
          'Lights on at 5:00 PM and they stay on until you turn them off.');
      expect(_sentence('5:00 PM', ''),
          'Lights on at 5:00 PM and they stay on until you turn them off.');
    });

    test('24-hour accounts see 24-hour times', () {
      expect(_sentence('17:00', '06:00', timeFormat: '24h'),
          'Lights on at 17:00, off at 06:00 the next morning.');
      expect(_sentence('5:00 PM', '11:00 PM', timeFormat: '24h'),
          'Lights on at 17:00, off at 23:00 this evening.');
    });

    test('offNextDay is taken from the caller, never re-derived', () {
      // The same labels, both answers: the sentence follows the flag.
      expect(
          scheduleWindowSentence(
              onLabel: '5:00 PM', offLabel: '6:00 AM', offNextDay: true),
          contains('the next morning'));
      expect(
          scheduleWindowSentence(
              onLabel: '5:00 PM', offLabel: '6:00 AM', offNextDay: false),
          contains('this morning'));
    });
  });
}
