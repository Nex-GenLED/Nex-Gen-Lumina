// +126 (g) — the sentence under the editor's wheels follows the wheels.
//
// Opens the real editor on a schedule, reads the line, then turns the ON
// hour wheel one notch and expects the line to say the new time. Also checks
// the overnight wording flips when the OFF time crosses the ON time, and that
// switching OFF to Solar is reflected.

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
const _sentenceKey = ValueKey('schedule-window-sentence');

ScheduleItem _item({required String on, required String off}) => ScheduleItem(
      id: 's1',
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: _days,
      actionLabel: 'Pattern: Classic Christmas 2',
      enabled: true,
    );

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
        solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(true)),
        clockHealthProvider.overrideWith((_) async => null),
        selectedDeviceIpProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: nexGenPremiumDarkTheme,
        home: _Opener(editing),
      ),
    );

String _sentence(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_sentenceKey)).data!;

Future<void> _open(WidgetTester tester, ScheduleItem editing) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(editing));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byKey(_sentenceKey), findsOneWidget);
}

/// Turns the hour column of the wheel under [wheelKey] by [notches]
/// (negative = earlier). A Cupertino time wheel's first column is the hour.
Future<void> _turnHour(WidgetTester tester, String wheelKey, int notches) async {
  final column = find
      .descendant(
          of: find.byKey(ValueKey(wheelKey)),
          matching: find.byType(CupertinoPicker))
      .first;
  // Each item is 32 pt tall; a drag of one item height moves one notch.
  await tester.drag(column, Offset(0, -32.0 * notches));
  await tester.pumpAndSettle();
}

void main() {
  // A solar label makes SchedulesNotifier run its one-time solar cleanup — a
  // real sync whose verification poll would leave timers pending. Already
  // done for the test account.
  setUp(() => SharedPreferences.setMockInitialValues(
      {'solar_cleanup_done_customer-test': true}));

  testWidgets('the line reads the saved window, and follows the ON wheel',
      (tester) async {
    await _open(tester, _item(on: '5:00 PM', off: '6:00 AM'));
    expect(_sentence(tester),
        'Lights on at 5:00 PM, off at 6:00 AM the next morning.');

    await _turnHour(tester, 'on_time', 1);
    expect(_sentence(tester),
        'Lights on at 6:00 PM, off at 6:00 AM the next morning.',
        reason: 'one notch later on the ON hour wheel');
  });

  testWidgets('the overnight wording flips when the OFF wheel crosses the ON '
      'time', (tester) async {
    await _open(tester, _item(on: '5:00 PM', off: '11:00 PM'));
    expect(_sentence(tester),
        'Lights on at 5:00 PM, off at 11:00 PM this evening.');

    // 11 PM → 12 AM: now earlier than 5 PM, so it is the next morning.
    await _turnHour(tester, 'off_time', 1);
    expect(_sentence(tester),
        'Lights on at 5:00 PM, off at 12:00 AM the next morning.');
  });

  testWidgets('a solar OFF reads as "sunrise the next morning"',
      (tester) async {
    await _open(tester, _item(on: '5:00 PM', off: 'Sunrise'));
    expect(_sentence(tester),
        'Lights on at 5:00 PM, off at sunrise the next morning.');
    await tester.pumpAndSettle();
  });
}
