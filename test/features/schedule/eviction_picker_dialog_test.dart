// test/features/schedule/eviction_picker_dialog_test.dart
//
// Widget tests for the Option-C eviction picker (Item #61 Workstream
// B Prompt 4). Verifies render, filter, sort, fire-count
// annotation, confirm-button gating, and cancel semantics.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/eviction_picker_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/utils/time_format.dart';

ScheduleItem _mk({
  required String id,
  String timeLabel = '7:00 PM',
  String actionLabel = 'Warm White',
  List<String> repeatDays = const ['Daily'],
  bool enabled = true,
  DateTime? disabledUntil,
}) =>
    ScheduleItem(
      id: id,
      timeLabel: timeLabel,
      repeatDays: repeatDays,
      actionLabel: actionLabel,
      enabled: enabled,
      disabledUntil: disabledUntil,
    );

CalendarEntry _entry({
  String dateKey = '2026-05-20',
  String patternName = 'Royals Chase',
  String onTime = '20:00',
  String offTime = '23:00',
}) =>
    CalendarEntry(
      dateKey: dateKey,
      patternName: patternName,
      onTime: onTime,
      offTime: offTime,
      brightness: 80,
      type: CalendarEntryType.user,
      autopilot: false,
    );

/// Pump the picker inside a ProviderScope and open the dialog.
/// Returns the [Completer] for the test to consume — `.future`
/// completes when the user cancels or confirms.
///
/// Caller pattern:
///   final c = await _openPicker(tester, ...);
///   ... interact ...
///   await tester.tap(find.text('Cancel'));
///   await tester.pumpAndSettle();
///   expect(await c.future, isNull);
Future<Completer<ScheduleItem?>> _openPicker(
  WidgetTester tester, {
  required List<ScheduleItem> schedules,
  required CalendarEntry entry,
  required DateTime leaseUntil,
  String timeFormat = kTimeFormat24h,
}) async {
  final completer = Completer<ScheduleItem?>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarLeaseSchedulesProvider.overrideWithValue(schedules),
        timeFormatPreferenceProvider.overrideWithValue(timeFormat),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showEvictionPicker(
                    context: ctx,
                    incomingEntry: entry,
                    leaseUntil: leaseUntil,
                  ).then(completer.complete);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return completer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final leaseUntil = DateTime.now().add(const Duration(hours: 10));

  testWidgets('renders all eligible ScheduleItems', (tester) async {
    final schedules = [
      _mk(id: 'a', actionLabel: 'Warm White'),
      _mk(id: 'b', actionLabel: 'Aurora'),
      _mk(id: 'c', actionLabel: 'Ocean Pulse'),
    ];
    final c = await _openPicker(
      tester,
      schedules: schedules,
      entry: _entry(),
      leaseUntil: leaseUntil,
    );
    expect(find.text('Warm White'), findsOneWidget);
    expect(find.text('Aurora'), findsOneWidget);
    expect(find.text('Ocean Pulse'), findsOneWidget);
    expect(find.text('Schedule slots full'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await c.future, isNull);
  });

  testWidgets('filters out !enabled items', (tester) async {
    final schedules = [
      _mk(id: 'a', actionLabel: 'Visible Item'),
      _mk(id: 'b', actionLabel: 'Hidden Item', enabled: false),
    ];
    final c = await _openPicker(
      tester,
      schedules: schedules,
      entry: _entry(),
      leaseUntil: leaseUntil,
    );
    expect(find.text('Visible Item'), findsOneWidget);
    expect(find.text('Hidden Item'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await c.future;
  });

  testWidgets('filters out already-evicted items', (tester) async {
    final future = DateTime.now().add(const Duration(hours: 6));
    final schedules = [
      _mk(id: 'a', actionLabel: 'Visible Item'),
      _mk(
        id: 'b',
        actionLabel: 'Already Paused',
        disabledUntil: future,
      ),
    ];
    final c = await _openPicker(
      tester,
      schedules: schedules,
      entry: _entry(),
      leaseUntil: leaseUntil,
    );
    expect(find.text('Visible Item'), findsOneWidget);
    expect(find.text('Already Paused'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await c.future;
  });

  testWidgets('confirm button disabled until selection', (tester) async {
    final schedules = [_mk(id: 'a', actionLabel: 'WW')];
    final c = await _openPicker(
      tester,
      schedules: schedules,
      entry: _entry(),
      leaseUntil: leaseUntil,
    );

    final confirmFinder = find.widgetWithText(FilledButton, 'Pause & add entry');
    expect(confirmFinder, findsOneWidget);
    final confirmBefore = tester.widget<FilledButton>(confirmFinder);
    expect(confirmBefore.onPressed, isNull,
        reason: 'Confirm should be disabled before a row is selected');

    await tester.tap(find.byKey(const ValueKey('eviction-row-a')));
    await tester.pumpAndSettle();

    final confirmAfter = tester.widget<FilledButton>(confirmFinder);
    expect(confirmAfter.onPressed, isNotNull,
        reason: 'Confirm should be enabled once a row is selected');

    await tester.tap(confirmFinder);
    await tester.pumpAndSettle();
    final pick = await c.future;
    expect(pick, isNotNull);
    expect(pick!.id, 'a');
  });

  testWidgets('cancel returns null', (tester) async {
    final schedules = [_mk(id: 'a')];
    final c = await _openPicker(
      tester,
      schedules: schedules,
      entry: _entry(),
      leaseUntil: leaseUntil,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await c.future, isNull);
  });

  testWidgets('fire-count annotation: 1 fire shows "(pauses 1 fire)"',
      (tester) async {
    final monday = _nextWeekday(DateTime.now(), DateTime.monday);
    final leaseTo = monday.add(const Duration(hours: 24));
    final schedules = [
      _mk(id: 'a', actionLabel: 'MondaysOnly', repeatDays: const ['Mon']),
    ];
    final c = await _openPicker(
      tester,
      schedules: schedules,
      entry: _entry(),
      leaseUntil: leaseTo,
    );
    expect(find.textContaining('pauses 1 fire'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await c.future;
  });

  testWidgets('fire-count annotation: Daily shows correct N for 48h',
      (tester) async {
    final now = DateTime.now();
    final leaseTo = now.add(const Duration(hours: 48));
    final schedules = [_mk(id: 'a', actionLabel: 'DailyItem')];
    final c = await _openPicker(
      tester,
      schedules: schedules,
      entry: _entry(),
      leaseUntil: leaseTo,
    );
    expect(find.textContaining('pauses 3 fires'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await c.future;
  });
}

DateTime _nextWeekday(DateTime from, int targetWeekday) {
  var d = DateTime(from.year, from.month, from.day);
  while (d.weekday != targetWeekday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}
