// The pure rule behind item 2 (overnight_off_days_test.dart drives it
// end to end): which OFF falls on the next day, and the one-day mask shift.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

ScheduleItem s(String on, String? off) => ScheduleItem(
      id: 'x',
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: const ['Mon'],
      actionLabel: 'Turn On',
      enabled: true,
    );

void main() {
  test('nextDayDowMask shifts every day one forward and wraps Sunday', () {
    expect(nextDayDowMask(0x01), 0x02, reason: 'Mon → Tue');
    expect(nextDayDowMask(0x1F), 0x3E, reason: 'Mon–Fri → Tue–Sat');
    expect(nextDayDowMask(0x40), 0x01, reason: 'Sun → Mon');
    expect(nextDayDowMask(0x60), 0x41, reason: 'Sat+Sun → Sun+Mon');
    expect(nextDayDowMask(127), 127, reason: 'daily stays daily');
  });

  test('which OFF falls on the next day', () {
    final next = <(String, String)>[
      ('6:00 PM', '1:00 AM'),
      ('6:00 PM', '12:00 AM'),
      ('Sunset', 'Sunrise'),
      ('Sunset', '1:00 AM'),
      ('Sunset', '12:00 AM'),
      ('6:00 PM', 'Sunrise'),
      ('12:00 PM', 'Sunrise'),
    ];
    final same = <(String, String)>[
      ('6:00 PM', '11:00 PM'),
      ('12:00 AM', '1:00 AM'),
      ('Sunset', '11:00 PM'),
      ('Sunset', '12:30 PM'),
      ('12:01 AM', 'Sunrise'),
      ('5:00 AM', 'Sunrise'),
      ('Sunrise', '9:00 AM'),
      ('2:00 PM', 'Sunset'),
      ('Sunrise', 'Sunset'),
      ('7:00 PM', '7:00 PM'),
    ];
    for (final (on, off) in next) {
      expect(offFallsNextDay(s(on, off)), isTrue, reason: '$on → $off');
    }
    for (final (on, off) in same) {
      expect(offFallsNextDay(s(on, off)), isFalse, reason: '$on → $off');
    }
    expect(offFallsNextDay(s('Sunset', null)), isFalse, reason: 'no OFF');
  });

  test('offDowFor applies the shift only to an overnight OFF', () {
    expect(offDowFor(s('Sunset', 'Sunrise'), 0x1F), 0x3E);
    expect(offDowFor(s('6:00 PM', '11:00 PM'), 0x1F), 0x1F);
  });
}
