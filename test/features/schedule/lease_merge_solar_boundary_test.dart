// +122 item 1 — the lease manager's merged timer write must carry the same
// solar decision the schedule sync carries.
//
// Arming or releasing a dated lease rewrites general timer slots 0–7 from
// `_buildMergedCfgPayload`, which renders the account's schedules through
// `buildCfgPayload`. It rendered them with the default `solarEnabled: false`,
// and under that default `buildCfgPayload` SKIPS every schedule that has a
// sunrise or sunset boundary — the schedule's CLOCK row included. The schedule
// sync itself passes the solar decision, so the controller held the clock row
// until the first lease write, which erased it.
//
// Field shape (an Android +116 account, read 2026-11-02): one repeating
// schedule, ON 5:30 PM (clock) / OFF Sunrise. After a Game Day lease the
// controller's published timer table held only a stale lease row and the
// sunrise-off row in slot 8; the 5:30 PM row was gone. That shape is the
// fixture here. Timer tables carry no segment geometry, so the two-channel and
// one-segment-after-restart fixtures of the other +122 items do not apply.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The customer's schedule: ON 5:30 PM by the clock, OFF at sunrise, every day.
const customerSchedule = ScheduleItem(
  id: 'evening-lights',
  timeLabel: '5:30 PM',
  offTimeLabel: 'Sunrise',
  repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  actionLabel: 'Warm White',
  enabled: true,
  presetId: 3,
);

/// A schedule with two clock boundaries, for the regression guard.
const clockOnlySchedule = ScheduleItem(
  id: 'porch',
  timeLabel: '6:00 PM',
  offTimeLabel: '11:00 PM',
  repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  actionLabel: 'Warm White',
  enabled: true,
  presetId: 3,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final today = DateTime.now();
  final noon = DateTime(today.year, today.month, today.day, 12);
  String two(int v) => v.toString().padLeft(2, '0');
  final todayKey = '${noon.year}-${two(noon.month)}-${two(noon.day)}';

  /// A dated entry inside today's window (12:30–13:30 with "now" pinned to
  /// noon): the Game Day lease shape.
  CalendarEntry gameDayEntry() => CalendarEntry(
        dateKey: todayKey,
        patternName: 'Game Day',
        color: const Color(0xFFE31837),
        onTime: '12:30',
        offTime: '13:30',
        brightness: 85,
        type: CalendarEntryType.user,
        autopilot: false,
      );

  ({CalendarEntryLeaseManager manager, List<Map<String, dynamic>> writes})
      harness({
    required List<ScheduleItem> schedules,
    required bool solarFlag,
  }) {
    final service = WledService('http://mock');
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(service),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(true)),
      calendarLeaseScheduleSlotDemandProvider
          .overrideWith((_) => schedules.length),
      calendarLeaseEntriesProvider.overrideWithValue(const []),
      calendarLeaseSchedulesProvider.overrideWithValue(schedules),
      calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider
          .overrideWith((_) => () async {}),
      solarSchedulingEnabledSyncProvider.overrideWithValue(solarFlag),
    ]);
    addTearDown(container.dispose);
    final manager = container.read(calendarEntryLeaseManagerProvider);
    manager.nowProvider = () => noon;
    final writes = <Map<String, dynamic>>[];
    manager.cfgPushFn = (repo, payload, ins) async {
      writes.add(payload);
      return CfgPushOutcome.confirmed;
    };
    return (manager: manager, writes: writes);
  }

  List<Map<String, dynamic>> insOf(Map<String, dynamic> payload) =>
      ((payload['timers'] as Map)['ins'] as List).cast<Map<String, dynamic>>();

  bool isRow(Map<String, dynamic> r, {required int hour, required int min}) =>
      r['en'] == 1 && r['hour'] == hour && r['min'] == min;

  test(
      'arming a lease keeps the 5:30 PM clock row of a sunrise-bounded '
      'repeating schedule', () async {
    final h = harness(schedules: const [customerSchedule], solarFlag: true);
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(gameDayEntry());
    expect(result.outcome, LeaseOutcome.leased);
    expect(h.writes, hasLength(1), reason: 'one merged timer write');
    final ins = insOf(h.writes.single);
    expect(ins, hasLength(8), reason: 'padded to every general slot');
    final clockRow = ins.where((r) => isRow(r, hour: 17, min: 30)).toList();
    expect(clockRow, hasLength(1),
        reason: "the customer's 5:30 PM ON row survives the lease write");
    expect(clockRow.single['macro'], 3);
    expect(clockRow.single['dow'], 127);
    final leaseRows = ins.where((r) => isRow(r, hour: 12, min: 30)).toList();
    expect(leaseRows, hasLength(1), reason: 'the lease row is there too');
  });

  test('the sunrise OFF boundary is never rendered into the general slots',
      () async {
    final h = harness(schedules: const [customerSchedule], solarFlag: true);
    await h.manager.initialize();
    await h.manager.handleEntryCreated(gameDayEntry());
    final ins = insOf(h.writes.single);
    expect(ins.where((r) => r['hour'] == 24 || r['hour'] == 25), isEmpty,
        reason: 'solar rows live in slots 8/9, written by the schedule sync');
  });

  test(
      'with the solar flag OFF the schedule is left out, exactly as the '
      'schedule sync leaves it out', () async {
    final h = harness(schedules: const [customerSchedule], solarFlag: false);
    await h.manager.initialize();
    await h.manager.handleEntryCreated(gameDayEntry());
    final ins = insOf(h.writes.single);
    expect(ins.where((r) => isRow(r, hour: 17, min: 30)), isEmpty);
  });

  test('a clock-only schedule keeps both rows (regression guard)', () async {
    final h = harness(schedules: const [clockOnlySchedule], solarFlag: true);
    await h.manager.initialize();
    await h.manager.handleEntryCreated(gameDayEntry());
    final ins = insOf(h.writes.single);
    expect(ins.where((r) => isRow(r, hour: 18, min: 0)), hasLength(1));
    expect(ins.where((r) => isRow(r, hour: 23, min: 0)), hasLength(1));
  });
}
