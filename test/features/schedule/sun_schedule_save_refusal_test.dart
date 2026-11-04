// The schedule editor's save-time refusals for sun times (item 4): a second
// sunset (or sunrise) look, and a Sunrise ON while "Turn lights off at sunrise
// daily" is on. Pure — the editor calls this before it saves anything.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/timer_table.dart';

ScheduleItem sched(String id, String on, String? off,
        {bool enabled = true, String label = 'Pattern: evening'}) =>
    ScheduleItem(
      id: id,
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: const ['Daily'],
      actionLabel: label,
      enabled: enabled,
    );

void main() {
  final evening = sched('a', 'Sunset', '11:00 PM');

  test('a second sunset look is refused, naming the one that has sunset', () {
    expect(
      sunScheduleSaveRefusal(
        candidate: sched('new', 'Sunset', 'Sunrise', label: 'Pattern: party'),
        schedules: [evening],
        sunriseOffOn: false,
      ),
      '"evening" already turns the lights on at sunset, and your controller '
      'can start only one look at sunset. Give this schedule a clock time, or '
      'change "evening".',
    );
  });

  test('a second sunrise look is refused the same way', () {
    expect(
      sunScheduleSaveRefusal(
        candidate: sched('new', 'Sunrise', '9:00 AM'),
        schedules: [sched('m', 'Sunrise', '8:00 AM', label: 'Turn On')],
        sunriseOffOn: false,
      ),
      contains('"Turn On" already turns the lights on at sunrise'),
    );
  });

  test('a Sunrise ON while the daily sunrise-off is on is refused', () {
    expect(
      sunScheduleSaveRefusal(
        candidate: sched('new', 'Sunrise', '9:00 AM'),
        schedules: const [],
        sunriseOffOn: true,
      ),
      'This schedule turns the lights on at sunrise, but "Turn lights off at '
      'sunrise daily" is on, and your controller cannot do both at sunrise. '
      'Give this schedule a clock time, or turn that setting off in System '
      'first.',
    );
  });

  test('nothing to refuse', () {
    // Editing the sunset schedule itself.
    expect(
        sunScheduleSaveRefusal(
            candidate: evening,
            schedules: [evening],
            editingId: 'a',
            sunriseOffOn: false),
        isNull);
    // The other sunset schedule is switched off.
    expect(
        sunScheduleSaveRefusal(
            candidate: sched('new', 'Sunset', 'Sunrise'),
            schedules: [sched('a', 'Sunset', '11:00 PM', enabled: false)],
            sunriseOffOn: false),
        isNull);
    // The candidate itself is switched off.
    expect(
        sunScheduleSaveRefusal(
            candidate: sched('new', 'Sunset', 'Sunrise', enabled: false),
            schedules: [evening],
            sunriseOffOn: false),
        isNull);
    // Clock-time ON.
    expect(
        sunScheduleSaveRefusal(
            candidate: sched('new', '6:00 PM', 'Sunrise'),
            schedules: [evening],
            sunriseOffOn: true),
        isNull);
    // OFFs at the same event share one row — never refused.
    expect(
        sunScheduleSaveRefusal(
            candidate: sched('new', '5:00 PM', 'Sunrise'),
            schedules: [sched('b', '6:00 PM', 'Sunrise')],
            sunriseOffOn: false),
        isNull);
  });
}
