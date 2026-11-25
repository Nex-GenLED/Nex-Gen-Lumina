// The overload banner's "Clean Up" sheet must finish its deletes through
// notifiers it holds, not through a ref whose widget may be gone.
//
// THE SHAPE. `_CleanupSheet` was handed the banner's WidgetRef and read
// `calendarScheduleProvider.notifier` through it only AFTER the awaited
// recurring-schedule deletes. Each of those deletes is a Firestore write with
// retries (seconds on a weak connection, longer offline), and the sheet sits
// under the glass dock, so the app can leave the schedule tab's shell while
// they run (sign-out, or any route outside the shell). The banner is disposed
// with the page, and the read after the loop threw
// `StateError: Cannot use "ref" after the widget was disposed.` — uncaught,
// so the holiday conflicts the customer had selected were never removed.
//
// The test drives the REAL My Schedule page under the dock: banner -> Clean
// Up -> Select All -> Delete Selected -> Delete. The recurring delete is held
// open, the dock body (inner Navigator, page, banner and sheet) is torn down
// while the provider container stays, and then the delete is released. A
// recording calendar notifier stands in for Firestore and the lease manager.
// Written first and failing at 0a364ce0 with that StateError.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_theme.dart';
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
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';
import 'package:nexgen_command/widgets/navigation/nav_bar_inset.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

String _today() => calendarDateKey(DateTime.now());

/// Nine enabled evening schedules on the same days and hours: over the
/// banner's threshold of eight, and every one overlaps every other.
List<ScheduleItem> _overloaded() => [
      for (var i = 0; i < 9; i++)
        ScheduleItem(
          id: 'sched-$i',
          timeLabel: '7:00 PM',
          offTimeLabel: '11:00 PM',
          repeatDays: const ['Daily'],
          actionLabel: 'Evening Look $i',
          enabled: true,
        ),
    ];

/// A dated entry tonight inside those hours, so the sheet lists a holiday
/// conflict as well and the calendar delete runs after the recurring ones.
CalendarEntry _tonight() => CalendarEntry(
      entryId: 'primary',
      dateKey: _today(),
      patternName: 'Harvest Moon',
      color: const Color(0xFFFF8C00),
      onTime: '19:30',
      offTime: '22:00',
      brightness: 85,
      type: CalendarEntryType.user,
    );

/// Recurring deletes wait on [gate], the way a Firestore write with retries
/// keeps the loop open. Never reaches Firestore or a controller.
class _GatedSchedules extends SchedulesNotifier {
  _GatedSchedules(super.ref, List<ScheduleItem> seed) {
    state = seed;
  }

  final gate = Completer<void>();
  final List<String> started = [];
  final List<String> removed = [];

  @override
  Future<void> remove(String id) async {
    started.add(id);
    await gate.future;
    removed.add(id);
    state = state.where((s) => s.id != id).toList();
  }
}

/// Records each date delete; never reaches Firestore or a lease.
class _RecordingCalendar extends CalendarScheduleNotifier {
  _RecordingCalendar(Ref ref, List<CalendarEntry> seed) : super(ref, null) {
    state = CalendarEntrySet.fromEntries(seed);
  }

  final List<String> removedDates = [];

  @override
  Future<bool> removeEntry(String dateKey) async {
    removedDates.add(dateKey);
    state = state.removeDate(dateKey);
    return true;
  }
}

/// The large-text host (extendBody Scaffold, NavBarInsetShell, the real
/// GlassDockNavBar, the page in its own Navigator), except that the dock body
/// can be dropped: [shellGone] stands in for the app leaving the shell, which
/// disposes the inner Navigator with the page, the banner and the sheet while
/// the provider container lives on.
class _Host extends StatelessWidget {
  const _Host({required this.shellGone, required this.page});

  final ValueListenable<bool> shellGone;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: nexGenPremiumDarkTheme,
      builder: TextScaleClamp.appBuilder,
      home: Scaffold(
        extendBody: true,
        body: ValueListenableBuilder<bool>(
          valueListenable: shellGone,
          builder: (_, gone, __) => gone
              ? const SizedBox.expand()
              : NavBarInsetShell(
                  navBar: GlassDockNavBar(index: 1, onTap: (_) {}),
                  body: Navigator(
                    onGenerateRoute: (_) =>
                        MaterialPageRoute<void>(builder: (_) => page),
                  ),
                ),
        ),
      ),
    );
  }
}

/// The page carries looping animations, so a fixed number of frames rather
/// than pumpAndSettle.
Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'Clean Up finishes its deletes when the schedule shell is torn down '
      'mid-delete', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late _GatedSchedules schedules;
    late _RecordingCalendar calendar;
    final shellGone = ValueNotifier<bool>(false);
    addTearDown(shellGone.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...homeDashboardOverrides(repo: RecordingWledRepository()),
        schedulesProvider.overrideWith((ref) {
          schedules = _GatedSchedules(ref, _overloaded());
          return schedules;
        }),
        calendarScheduleProvider.overrideWith((ref) {
          calendar = _RecordingCalendar(ref, [_tonight()]);
          return calendar;
        }),
        // Never emits, so the seeded list above is never overwritten.
        userSchedulesStreamProvider
            .overrideWith((ref) => const Stream<List<ScheduleItem>>.empty()),
        gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
        gameDayAutopilotConfigsProvider.overrideWith(
            (_) => Stream.value(const <GameDayAutopilotConfig>[])),
        solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(false)),
        clockHealthProvider.overrideWith((_) async => null),
        selectedDeviceIpProvider.overrideWith((ref) => null),
      ],
      child: _Host(shellGone: shellGone, page: const MySchedulePage()),
    ));
    await _settle(tester);

    // Banner -> Clean Up sheet -> Select All -> Delete Selected -> Delete.
    final cleanUp = find.text('Clean Up');
    expect(cleanUp, findsOneWidget, reason: 'the overload banner shows');
    await tester.tap(cleanUp);
    await _settle(tester);
    expect(find.text('Holiday Conflicts'), findsOneWidget,
        reason: 'tonight\'s entry is listed as a conflict');

    await tester.tap(find.text('Select All'));
    await tester.pump();
    final deleteSelected = find.text('Delete Selected (10)');
    expect(deleteSelected, findsOneWidget,
        reason: 'nine recurring schedules and one dated entry selected');
    await tester.ensureVisible(deleteSelected);
    await tester.tap(deleteSelected);
    await _settle(tester, frames: 4);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();

    expect(schedules.started, ['sched-0'],
        reason: 'the first recurring delete is in flight');
    expect(calendar.removedDates, isEmpty);

    // The app leaves the shell while that write is still out.
    shellGone.value = true;
    await _settle(tester, frames: 4);
    expect(find.byType(MySchedulePage), findsNothing);
    expect(find.text('Resolve Schedule Conflicts'), findsNothing);

    // The write lands; the loop carries on without the page.
    schedules.gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(schedules.removed, [for (var i = 0; i < 9; i++) 'sched-$i']);
    expect(calendar.removedDates, [_today()],
        reason: 'the selected holiday conflict is removed too');
    expect(tester.takeException(), isNull);
  });
}
