// test/utils/schedule_window_format_test.dart
//
// COMMIT 1 (SCHEDULE CLARITY PAIR) — the schedule card must render BOTH
// boundaries when an off time exists, so the silent sunrise-OFF is visible.
// formatScheduleWindow is the single source of truth for the "X → off at Y"
// phrasing used by the My Schedule card and the dashboard Tonight card.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/utils/time_format.dart';

void main() {
  group('formatScheduleWindow', () {
    test('solar on + solar off → both boundaries, off rendered as word', () {
      expect(
        formatScheduleWindow('Sunset', 'Sunrise'),
        'Sunset → off at Sunrise',
      );
    });

    test('clock on + clock off (12h) → both boundaries with "off at"', () {
      expect(
        formatScheduleWindow('7:00 PM', '11:00 PM', timeFormat: kTimeFormat12h),
        '7:00 PM → off at 11:00 PM',
      );
    });

    test('24h off boundary normalizes to the preferred format', () {
      expect(
        formatScheduleWindow('Sunset', '23:00', timeFormat: kTimeFormat12h),
        'Sunset → off at 11:00 PM',
      );
    });

    test('no off boundary → ON only (never fabricates an off)', () {
      expect(formatScheduleWindow('Sunset', null), 'Sunset');
      expect(formatScheduleWindow('7:00 PM', ''), '7:00 PM');
    });
  });
}
