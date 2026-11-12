// +126 (f) — the schedule editor re-opens on a 24-hour label.
//
// A 24-hour account's editor saves the label as "17:30" (formatTimeOfDay with
// the account's time format). The old hydration code matched AM/PM labels
// only, so editing that schedule opened the ON wheel on the 7:00 PM default
// and the OFF wheel on 11:00 PM — a customer who only changed the pattern and
// pressed Save moved their lights to 7:00 PM without knowing. The wheels must
// open on the saved times for both label forms.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart'
    show selectedDeviceIpProvider;
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/wled/clock_health_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

ScheduleItem _item({required String on, required String off}) => ScheduleItem(
      id: 's24',
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: _days,
      actionLabel: 'Pattern: Classic Christmas 2',
      enabled: true,
    );

/// A page with one button that opens the editor on [editing].
class _Opener extends ConsumerWidget {
  const _Opener(this.editing);
  final ScheduleItem editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showScheduleEditor(context, ref, editing: editing),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Widget _app(ScheduleItem editing) => ProviderScope(
      overrides: [
        ...homeDashboardOverrides(repo: RecordingWledRepository()),
        userSchedulesStreamProvider
            .overrideWith((ref) => Stream.value([editing])),
        gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
        gameDayAutopilotConfigsProvider
            .overrideWith((_) => Stream.value(const <GameDayAutopilotConfig>[])),
        solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(false)),
        clockHealthProvider.overrideWith((_) async => null),
        selectedDeviceIpProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: nexGenPremiumDarkTheme,
        home: _Opener(editing),
      ),
    );

/// The time the wheel under [key] opened on.
TimeOfDay _wheelTime(WidgetTester tester, String key) {
  final picker = tester.widget<CupertinoDatePicker>(find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(CupertinoDatePicker),
  ));
  final dt = picker.initialDateTime;
  return TimeOfDay(hour: dt.hour, minute: dt.minute);
}

Future<void> _open(WidgetTester tester, ScheduleItem editing) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(editing));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byKey(const ValueKey('on_time')), findsOneWidget,
      reason: 'the editor opened with the ON wheel on a clock time');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a 24-hour label ("17:30" / "06:00") opens the wheels on the '
      'saved times', (tester) async {
    await _open(tester, _item(on: '17:30', off: '06:00'));

    expect(_wheelTime(tester, 'on_time'), const TimeOfDay(hour: 17, minute: 30),
        reason: 'not the 7:00 PM default the old regex fell back to');
    expect(_wheelTime(tester, 'off_time'), const TimeOfDay(hour: 6, minute: 0),
        reason: 'not the 11:00 PM default');
  });

  testWidgets('a 12-hour label ("5:30 PM" / "6:00 AM") still opens on the '
      'saved times', (tester) async {
    await _open(tester, _item(on: '5:30 PM', off: '6:00 AM'));

    expect(_wheelTime(tester, 'on_time'), const TimeOfDay(hour: 17, minute: 30));
    expect(_wheelTime(tester, 'off_time'), const TimeOfDay(hour: 6, minute: 0));
  });
}
