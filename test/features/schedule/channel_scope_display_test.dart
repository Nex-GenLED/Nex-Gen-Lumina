// Scheduling V3 D4 — channel scope in the display, and slot accounting.
//
// The conflict cases are the load-bearing ones: two events at the same minute
// on DISJOINT channels do not actually contend for any pixel, so calling them a
// conflict would be a warning about nothing. Overlapping sets — including the
// null-means-all case — still are.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/widgets/channel_scope_picker.dart';
import 'package:nexgen_command/features/schedule/widgets/timeline_row.dart';
import 'package:nexgen_command/features/schedule/widgets/timer_slot_meter.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';

const _date = '2026-09-13';

List<DeviceChannel> chans(int n) => [
      for (var i = 0; i < n; i++)
        DeviceChannel(
            id: i, name: 'Channel ${i + 1}', start: i * 50, stop: (i + 1) * 50,
            gpioPin: i),
    ];

CalendarEntry dated(String id, String on, {List<int>? ch, String? ctrl}) =>
    CalendarEntry(
      entryId: id,
      dateKey: _date,
      patternName: 'P-$id',
      onTime: on,
      offTime: '23:00',
      type: CalendarEntryType.user,
      channels: ch,
      controllerId: ctrl,
    );

ScheduleItem rec(String id, String on,
        {List<int>? ch, String? off = '6:00 AM', bool enabled = true}) =>
    ScheduleItem(
      id: id,
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: const ['Daily'],
      actionLabel: 'Pattern: Warm White',
      enabled: enabled,
      channels: ch,
    );

DayTimeline build({
  List<ScheduleItem> recurring = const [],
  List<CalendarEntry> datedEntries = const [],
}) =>
    resolveDayTimeline(
      DayTimelineInputs(
        dateKey: _date,
        recurringSchedules: recurring,
        datedEntries: datedEntries,
      ),
      kActiveSchedulePrecedence,
    );

void main() {
  group('CONFLICT respects channel scope', () {
    test('same minute, DISJOINT channels → NOT a conflict', () {
      final t = build(
        recurring: [rec('base', '8:00 PM', ch: const [0])],
        datedEntries: [dated('u1', '20:00', ch: const [1])],
      );
      expect(t.count, 2);
      expect(t.hasConflict, isFalse,
          reason: 'they never touch the same pixel — a warning here is noise');
    });

    test('same minute, OVERLAPPING channels → conflict', () {
      final t = build(
        recurring: [rec('base', '8:00 PM', ch: const [0, 1])],
        datedEntries: [dated('u1', '20:00', ch: const [1, 2])],
      );
      expect(t.hasConflict, isTrue);
    });

    test('same minute, one scoped and one all-channel → conflict', () {
      final t = build(
        recurring: [rec('base', '8:00 PM')], // null = all
        datedEntries: [dated('u1', '20:00', ch: const [1])],
      );
      expect(t.hasConflict, isTrue,
          reason: 'null means every channel, so it overlaps anything');
    });

    test('disjoint channels at DIFFERENT minutes still hand over', () {
      final t = build(
        recurring: [rec('base', '9:00 PM', ch: const [0])],
        datedEntries: [dated('u1', '20:00', ch: const [1])],
      );
      expect(t.hasConflict, isFalse);
      // Takeover is time-based and channel-blind in v1 — documented in
      // day_timeline_test case (f). A later event is still shown as taking over.
      expect(t.entries.first.takenOverAt, isNotNull);
    });
  });

  group('channelScopeLabel', () {
    test('all-channel is null — no chrome on the common case', () {
      expect(channelScopeLabel(null, chans(4)), isNull);
    });

    test('a single channel uses the device name', () {
      expect(channelScopeLabel(const [1], chans(4)), 'Channel 2');
    });

    test('a subset counts', () {
      expect(channelScopeLabel(const [0, 2], chans(4)), '2 of 4 channels');
    });

    test('every channel selected reads as all-channel', () {
      expect(channelScopeLabel(const [0, 1, 2, 3], chans(4)), isNull);
    });

    test('an empty list is stated, not silently treated as all', () {
      expect(channelScopeLabel(const [], chans(4)), 'No channels');
    });

    test('an unknown id degrades to a 1-based label', () {
      expect(channelScopeLabel(const [7], chans(4)), 'Channel 8');
    });
  });

  group('TimelineRowTile renders scope', () {
    Future<void> pump(WidgetTester t, Widget w) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: w)));

    testWidgets('a scoped row shows its channel', (tester) async {
      final t = build(datedEntries: [dated('u1', '19:00', ch: const [1])]);
      await pump(
        tester,
        DayTimelineList(
          timeline: t,
          scopeLabelFor: (e) =>
              channelScopeLabel(e.dated?.channels ?? e.recurring?.channels,
                  chans(4)),
        ),
      );
      expect(find.text('Channel 2'), findsOneWidget);
    });

    testWidgets('an all-channel row shows NO scope chrome', (tester) async {
      final t = build(datedEntries: [dated('u1', '19:00')]);
      await pump(
        tester,
        DayTimelineList(
          timeline: t,
          scopeLabelFor: (e) =>
              channelScopeLabel(e.dated?.channels, chans(4)),
        ),
      );
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
    });

    testWidgets('the controller name appears only when one is supplied',
        (tester) async {
      final t = build(
          datedEntries: [dated('u1', '19:00', ch: const [1], ctrl: 'ctrl-A')]);
      await pump(
        tester,
        DayTimelineList(
          timeline: t,
          scopeLabelFor: (e) => channelScopeLabel(e.dated?.channels, chans(4)),
          controllerLabelFor: (e) => 'Back Yard',
        ),
      );
      expect(find.text('Channel 2 · Back Yard'), findsOneWidget);
    });
  });

  group('slot accounting — per EVENT, not per channel (P4)', () {
    test('a scoped event costs the same as an all-channel one', () {
      final all = rec('a', '8:00 PM');
      final scoped = rec('b', '8:00 PM', ch: const [1]);
      expect(slotsForSchedule(all, solarEnabled: false),
          slotsForSchedule(scoped, solarEnabled: false));
    });

    test('on + off = two slots; on-only = one', () {
      expect(slotsForSchedule(rec('a', '8:00 PM'), solarEnabled: false), 2);
      expect(
          slotsForSchedule(rec('a', '8:00 PM', off: null), solarEnabled: false),
          1);
    });

    test('solar boundaries cost nothing when the flag is on', () {
      final s = ScheduleItem(
        id: 'solar',
        timeLabel: 'Sunset',
        offTimeLabel: 'Sunrise',
        repeatDays: const ['Daily'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
      );
      expect(slotsForSchedule(s, solarEnabled: true), 0,
          reason: 'they live in the dedicated slots 8/9');
      expect(slotsForSchedule(s, solarEnabled: false), 2,
          reason: 'flag off ⇒ refused as solar, but counted as clock demand');
    });

    test('a disabled schedule holds nothing', () {
      expect(
          slotsForSchedule(rec('a', '8:00 PM', enabled: false),
              solarEnabled: false),
          0);
    });

    test('leases shrink the budget, and holders are named', () {
      final usage = computeSlotUsage(
        schedules: [rec('a', '8:00 PM'), rec('b', '9:00 PM')],
        leaseCount: 2,
        solarEnabled: false,
      );
      expect(usage.used, 4);
      expect(usage.budget, 6, reason: '8 general slots minus 2 held by leases');
      expect(usage.holders.map((h) => h.slots), [2, 2]);
      // `displayActionLabel`, prefix intact: the dialog is a LIST of
      // schedules, which is the context that prefix is right for. The day
      // timeline strips it because there every row is already a schedule.
      expect(usage.holders.first.label, 'Pattern: Warm White');
    });

    test('the edited schedule is excluded from its own usage', () {
      final usage = computeSlotUsage(
        schedules: [rec('a', '8:00 PM'), rec('b', '9:00 PM')],
        leaseCount: 0,
        solarEnabled: false,
        excludingId: 'a',
      );
      expect(usage.used, 2);
      expect(usage.holders.single.id, 'b');
    });
  });
}
