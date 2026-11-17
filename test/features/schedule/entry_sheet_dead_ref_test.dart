// The entry detail sheet must act through a ref that lives as long as the
// sheet itself.
//
// WHAT WENT WRONG. The day sheet's row tap popped the day sheet and then handed
// that sheet's own `Consumer` ref into the entry detail sheet. By the time the
// customer confirmed Delete, that Consumer was disposed, so
// `ref.read(calendarScheduleProvider.notifier)` threw
// `StateError: Cannot use "ref" after the widget was disposed.` after the
// confirmation await — uncaught, so no snackbar, the sheet stayed open and
// nothing was written. The owner saw exactly this on 2026-11-17 (three
// identical StateErrors in users/{uid}/debug_errors on 2.5.10+129 while
// trying to delete that day's "Chiefs Fade"). Present since c9d56b8d
// (build-82); only the day-card tap on a single-row day passed a live ref.
//
// These tests drive the REAL My Schedule page through the real week strip,
// day sheet and detail sheet, with a calendar notifier that records the
// delete instead of writing Firestore or touching a lease. Written first and
// failing at a9cfc492 ("the day sheet path deletes" threw the StateError).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:nexgen_command/features/schedule/widgets/timeline_row.dart';
import 'package:nexgen_command/features/wled/clock_health_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/large_text_matrix.dart';
import '../../helpers/recording_wled_repository.dart';

const _kDelete = 'Delete This Entry';
const _kEdit = 'Edit This Day';
const _kChiefs = 'Chiefs Fade';
const _kChiefsId = 'lumina_1794403737068_6';
const _kHarvest = 'Harvest Moon';

String _today() => calendarDateKey(DateTime.now());

/// Today's "Chiefs Fade" as Lumina wrote it on the owner's phone: a user
/// entry carrying `autopilot: true` and the lumina_ai source tag.
CalendarEntry _chiefsFade() => CalendarEntry(
      entryId: _kChiefsId,
      dateKey: _today(),
      patternName: _kChiefs,
      color: const Color(0xFFE30000),
      onTime: '00:00',
      offTime: '23:59',
      brightness: 100,
      type: CalendarEntryType.user,
      autopilot: true,
      sourceTag: CalendarEntrySourceTag.luminaAi,
      note: 'Lumina: Fade',
    );

/// The second row the owner's nights carried, so the day holds TWO rows and
/// the hero card routes to the day sheet rather than straight to a detail.
CalendarEntry _harvestMoon() => CalendarEntry(
      entryId: 'primary',
      dateKey: _today(),
      patternName: _kHarvest,
      color: const Color(0xFFFF8C00),
      onTime: '17:05',
      offTime: '23:00',
      brightness: 85,
      type: CalendarEntryType.user,
      autopilot: true,
      sourceTag: CalendarEntrySourceTag.luminaAi,
    );

/// Records every delete; never reaches Firestore, a lease, or a controller.
class _RecordingCalendar extends CalendarScheduleNotifier {
  _RecordingCalendar(Ref ref, List<CalendarEntry> seed) : super(ref, null) {
    state = CalendarEntrySet.fromEntries(seed);
  }

  final List<(String dateKey, String entryId)> removed = [];

  @override
  Future<bool> removeEntryById(String dateKey, String entryId) async {
    removed.add((dateKey, entryId));
    state = state.removeEntryById(dateKey, entryId);
    return true;
  }
}

/// The My Schedule page exactly as the large-text suite hosts it: under the
/// glass dock, with every network-facing provider replaced by a fake.
Future<_RecordingCalendar> _pumpPage(
  WidgetTester tester,
  List<CalendarEntry> seed,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final appKey = GlobalKey();
  late _RecordingCalendar calendar;
  await tester.pumpWidget(KeyedSubtree(
    key: appKey,
    child: largeTextHost(
      overrides: [
        ...homeDashboardOverrides(repo: RecordingWledRepository()),
        calendarScheduleProvider.overrideWith((ref) {
          calendar = _RecordingCalendar(ref, seed);
          return calendar;
        }),
        userSchedulesStreamProvider
            .overrideWith((ref) => Stream.value(const <ScheduleItem>[])),
        gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
        gameDayAutopilotConfigsProvider.overrideWith(
            (_) => Stream.value(const <GameDayAutopilotConfig>[])),
        solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(false)),
        clockHealthProvider.overrideWith((_) async => null),
        selectedDeviceIpProvider.overrideWith((ref) => null),
      ],
      page: const MySchedulePage(),
      dock: 1,
    ),
  ));
  await _settle(tester);
  return calendar;
}

/// The page carries looping animations, so a fixed number of frames rather
/// than pumpAndSettle.
Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Finder _weekCell(String dateKey) => find.byWidgetPredicate((w) =>
    w.runtimeType.toString() == '_WeekDayCell' &&
    (w as dynamic).dateKey == dateKey);

Finder _heroCard() =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_DayHeroCard');

/// `TextButton.icon` builds a private TextButton subclass, so match by type
/// predicate rather than `find.byType`.
Finder _textButton(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is TextButton),
    );

/// Week strip -> day sheet -> the "Chiefs Fade" row -> its detail sheet.
Future<void> _openChiefsFromDaySheet(WidgetTester tester) async {
  final cell = _weekCell(_today());
  expect(cell, findsOneWidget, reason: 'today is in the week strip');
  await tester.ensureVisible(cell);
  await tester.tap(cell);
  await _settle(tester);

  // The hero card lists the day's rows too, so scope to the open sheet.
  final row = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.ancestor(
      of: find.text(_kChiefs),
      matching: find.byType(TimelineRowTile),
    ),
  );
  expect(row, findsOneWidget, reason: 'the day sheet lists the Chiefs row');
  await tester.tap(row);
  await _settle(tester);

  expect(_textButton(_kDelete), findsOneWidget,
      reason: 'the detail sheet for the row is open');
}

Future<void> _deleteAndConfirm(WidgetTester tester) async {
  await tester.tap(_textButton(_kDelete));
  await _settle(tester);
  expect(find.text('Delete this entry?'), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'the day sheet path deletes: week strip -> day sheet -> row -> '
      'Delete This Entry -> confirm removes that row and says so',
      (tester) async {
    final calendar = await _pumpPage(tester, [_harvestMoon(), _chiefsFade()]);
    await _openChiefsFromDaySheet(tester);
    await _deleteAndConfirm(tester);

    expect(calendar.removed, [(_today(), _kChiefsId)],
        reason: 'exactly the tapped row is removed, by its own identity');
    expect(_textButton(_kDelete), findsNothing,
        reason: 'the detail sheet closed');
    expect(find.text('Entry deleted'), findsOneWidget,
        reason: 'the snackbar confirms the delete');
  });

  testWidgets(
      'the day sheet path edits: Edit This Day closes the detail sheet and '
      'opens the entry editor', (tester) async {
    await _pumpPage(tester, [_harvestMoon(), _chiefsFade()]);
    await _openChiefsFromDaySheet(tester);

    await tester.tap(_textButton(_kEdit));
    await _settle(tester);

    expect(_textButton(_kDelete), findsNothing,
        reason: 'the detail sheet closed');
    expect(find.text('Save'), findsOneWidget,
        reason: 'the calendar entry editor is open');
  });

  testWidgets(
      'the day-card path keeps working: a single-row day opens its detail '
      'from the card, and Delete removes it', (tester) async {
    final calendar = await _pumpPage(tester, [_chiefsFade()]);

    final hero = _heroCard();
    expect(hero, findsOneWidget);
    await tester.ensureVisible(hero);
    await tester
        .tap(find.descendant(of: hero, matching: find.text(_kChiefs)).first);
    await _settle(tester);
    expect(_textButton(_kDelete), findsOneWidget,
        reason: 'a single-row day goes straight to the entry detail');

    await _deleteAndConfirm(tester);

    expect(calendar.removed, [(_today(), _kChiefsId)]);
    expect(_textButton(_kDelete), findsNothing);
    expect(find.text('Entry deleted'), findsOneWidget);
  });
}
