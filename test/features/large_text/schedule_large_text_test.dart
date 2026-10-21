// +120 large-text slice, group 3: My Schedule's view-mode bar and week
// cells. The bar was a fixed 40 pt row of five chips that overflowed at
// 320 pt even at 1.0x; it now centres when it fits, scrolls sideways when it
// does not, and its app-bar slot grows with the text scale. The week cells
// were a fixed 118 pt; they now grow with the text they hold.

import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart'
    show selectedDeviceIpProvider;
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/wled/clock_health_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/large_text_matrix.dart';
import '../../helpers/recording_wled_repository.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

List<ScheduleItem> _schedules() => const [
      ScheduleItem(
        id: 's1',
        timeLabel: 'Sunset',
        offTimeLabel: '11:00 PM',
        repeatDays: _days,
        actionLabel: 'Pattern: Warm White Glow',
        enabled: true,
      ),
      ScheduleItem(
        id: 's2',
        timeLabel: '6:30 PM',
        offTimeLabel: '10:30 PM',
        repeatDays: ['Fri', 'Sat'],
        actionLabel: 'Pattern: Candy Cane Chase',
        enabled: true,
      ),
    ];

/// The week strip with one dated OFF night (the "Off" pill path) and one
/// dated pattern night, both inside the week the page opens on.
class _SeededCalendar extends CalendarScheduleNotifier {
  _SeededCalendar(Ref ref) : super(ref, null) {
    final now = DateTime.now();
    String key(int plusDays) =>
        calendarDateKey(DateTime(now.year, now.month, now.day + plusDays));
    state = CalendarEntrySet.fromEntries([
      CalendarEntry(
        dateKey: key(1),
        patternName: 'Lights Off',
        brightness: 0,
        onTime: '18:00',
        offTime: '23:00',
        type: CalendarEntryType.user,
      ),
      CalendarEntry(
        dateKey: key(2),
        patternName: 'Candy Cane Chase',
        onTime: '18:30',
        offTime: '22:30',
        type: CalendarEntryType.user,
      ),
    ]);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('My Schedule: no overflow across the matrix', (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => largeTextHost(
        overrides: [
          ...homeDashboardOverrides(repo: RecordingWledRepository()),
          calendarScheduleProvider.overrideWith((ref) => _SeededCalendar(ref)),
          userSchedulesStreamProvider
              .overrideWith((ref) => Stream.value(_schedules())),
          gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
          gameDayAutopilotConfigsProvider.overrideWith(
              (_) => Stream.value(const <GameDayAutopilotConfig>[])),
          solarSchedulingEnabledProvider
              .overrideWith((_) => Stream.value(false)),
          clockHealthProvider.overrideWith((_) async => null),
          selectedDeviceIpProvider.overrideWith((ref) => null),
        ],
        page: const MySchedulePage(),
        dock: 1,
      ),
      label: 'schedule',
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
  });
}
