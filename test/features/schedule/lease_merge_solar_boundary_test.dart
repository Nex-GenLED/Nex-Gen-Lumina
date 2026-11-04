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
//
// release/122-candidate follow-up: the merged lease manager now builds the
// SHARED 10-row table (timer_table.dart) through `resolveTimerTableContext`,
// which reads the STREAM solar flag and the controller's coordinates. The
// harness is set up the way the lease harness of
// timer_table_shared_builder_test.dart is — stream flag on, sync flag on, no
// global sunrise-off, a controller that reports coordinates — and every case
// asserts on rows (slot, hour, minute, days, macro, enabled), never on a
// length. Expected rows follow the builder's documented rules:
//   * slots 0–7 hold the schedules' clock rows, then the lease rows, then
//     all-zero stubs (assembleTable);
//   * a sunrise OFF of an armed schedule lives in slot 8 as
//     {en:1, hour:255, min:0, macro:2 (master off), dow}, where the OFF days
//     of an overnight night are shifted one day forward (offDowFor) and daily
//     (127) maps to itself;
//   * slot 9 is an all-zero stub when nothing owns sunset;
//   * with solar off the sun-bounded schedule is refused (timerArmRefusal) and
//     slot 8 is the DISABLED placeholder {en:0, hour:255, min:0, macro:0,
//     dow:0}.
// The last groups record what the manager does while the stream flag is still
// loading, and what the sync provider (schedule sync's own read) answers while
// loading and after an error. The error case for the manager is NOT here: against
// the current builder an erroring flag reads as off and a table is written (see
// the +122 candidate report); it is recorded there, not committed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ControllerClockInfo;
import 'package:nexgen_command/features/wled/wled_dow.dart';
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

/// One controller that reports coordinates: the `fetchClockInfo` form of the
/// lease controller in timer_table_shared_builder_test.dart. Timer tables
/// carry no segment geometry, so nothing else is overridden.
class _Controller extends WledService {
  _Controller() : super('http://mock');

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async =>
      const ControllerClockInfo(latitude: 40.0, longitude: -95.0);
}

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

  /// [solarFlag] drives the stream flag and the sync flag together (the sync
  /// provider mirrors the stream's value). [solarFlagStream] replaces the
  /// stream for the loading / error cases; the sync flag then reads false,
  /// which is the sync provider's own answer for both of those states.
  ({CalendarEntryLeaseManager manager, List<Map<String, dynamic>> writes})
      harness({
    required List<ScheduleItem> schedules,
    required bool solarFlag,
    Stream<bool>? solarFlagStream,
  }) {
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(_Controller()),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(true)),
      calendarLeaseScheduleSlotDemandProvider
          .overrideWith((_) => schedules.length),
      calendarLeaseEntriesProvider.overrideWithValue(const []),
      calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
      calendarLeaseSchedulesProvider.overrideWithValue(schedules),
      calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider
          .overrideWith((_) => () async {}),
      solarSchedulingEnabledProvider
          .overrideWith((_) => solarFlagStream ?? Stream.value(solarFlag)),
      solarSchedulingEnabledSyncProvider.overrideWithValue(solarFlag),
      globalSunriseOffTimerProvider.overrideWithValue(null),
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

  /// One row with every field: enabled, hour, minute, macro, days.
  Map<String, dynamic> row({
    required int en,
    required int hour,
    required int min,
    required int macro,
    required int dow,
  }) =>
      {'en': en, 'hour': hour, 'min': min, 'macro': macro, 'dow': dow};

  /// An all-zero clock stub (an unused general slot, or an unowned slot 9).
  const stub = {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0};

  /// Slot 8 when nothing owns sunrise: disabled, hour 255 so 0.15.x keeps the
  /// slot in cfg.json.
  const sunrisePlaceholder = {
    'en': 0,
    'hour': 255,
    'min': 0,
    'macro': 0,
    'dow': 0,
  };

  String tableOf(List<Map<String, dynamic>> writes) => [
        for (final w in writes)
          for (final (i, r) in insOf(w).indexed)
            'slot $i: hour ${r['hour']} min ${r['min']} dow ${r['dow']} '
                'macro ${r['macro']} en ${r['en']}',
      ].join('; ');

  test(
      'arming a lease keeps the 5:30 PM clock row of a sunrise-bounded '
      'repeating schedule', () async {
    final h = harness(schedules: const [customerSchedule], solarFlag: true);
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(gameDayEntry());
    expect(result.outcome, LeaseOutcome.leased);
    expect(h.writes, hasLength(1), reason: 'one merged timer write');
    final ins = insOf(h.writes.single);

    // Slot 0: the schedule's clock ON — 5:30 PM, preset 3, every day. The
    // general slots hold the schedules' clock rows first, then the leases.
    expect(ins[0], row(en: 1, hour: 17, min: 30, macro: 3, dow: 127),
        reason: "the customer's 5:30 PM ON row survives the lease write");
    // Slot 1: the lease row, after the schedule rows — 12:30 on the entry's
    // own day, firing the lease's preset.
    expect(
        ins[1],
        row(
          en: 1,
          hour: 12,
          min: 30,
          macro: result.lease!.presetId,
          dow: wledDowMaskForWeekday(noon.weekday),
        ),
        reason: 'the lease row follows the schedule rows');
    for (var slot = 2; slot <= 7; slot++) {
      expect(ins[slot], stub, reason: 'slot $slot is an all-zero stub');
    }
    // Slot 8: the schedule's sunrise OFF — enabled, hour 255, the master-off
    // preset 2; an evening ON ending at sunrise is an overnight night, so the
    // OFF days shift one day forward, and daily stays daily.
    expect(ins[8], row(en: 1, hour: 255, min: 0, macro: 2, dow: 127),
        reason: 'the sunrise OFF lives in slot 8, enabled');
    // Slot 9: nothing owns sunset.
    expect(ins[9], stub, reason: 'slot 9 is an all-zero stub');
  });

  test('the sunrise OFF boundary is never rendered into the general slots',
      () async {
    // The flag is explicitly ON: the schedule arms and its OFF has a home.
    final h = harness(schedules: const [customerSchedule], solarFlag: true);
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(gameDayEntry());
    expect(result.outcome, LeaseOutcome.leased);
    final ins = insOf(h.writes.single);
    final general = ins.sublist(0, 8);
    expect(general.where((r) => r['hour'] == 255 || r['hour'] == 254),
        isEmpty,
        reason: 'sun rows never sit in slots 0–7');
    expect(general.where((r) => r['hour'] == 24 || r['hour'] == 25), isEmpty,
        reason: 'nor does the old 24/25 encoding');
    expect(ins[8], row(en: 1, hour: 255, min: 0, macro: 2, dow: 127),
        reason: 'slot 8 holds the sunrise OFF');
  });

  test(
      'with the solar flag OFF the schedule is left out, exactly as the '
      'schedule sync leaves it out', () async {
    // The flag is explicitly OFF: stream false, sync false.
    final h = harness(schedules: const [customerSchedule], solarFlag: false);
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(gameDayEntry());
    expect(result.outcome, LeaseOutcome.leased);
    final ins = insOf(h.writes.single);
    expect(ins.where((r) => isRow(r, hour: 17, min: 30)), isEmpty,
        reason: 'a sun-bounded schedule is refused while solar is off');
    expect(ins[8], sunrisePlaceholder,
        reason: 'nothing owns sunrise: slot 8 is the disabled placeholder');
  });

  test('a clock-only schedule keeps both rows (regression guard)', () async {
    final h = harness(schedules: const [clockOnlySchedule], solarFlag: true);
    await h.manager.initialize();
    await h.manager.handleEntryCreated(gameDayEntry());
    final ins = insOf(h.writes.single);
    expect(ins.where((r) => isRow(r, hour: 18, min: 0)), hasLength(1));
    expect(ins.where((r) => isRow(r, hour: 23, min: 0)), hasLength(1));
  });

  group('the stream solar flag while loading and while in error', () {
    // While the stream has not answered, the sync provider reads false (its
    // own contract). A table built on that guess would write the sunrise
    // placeholder over a live sunrise row and drop a sun-bounded schedule's
    // clock row, so the manager must defer: write nothing and leave the
    // controller's table as it was.

    test('LOADING: the manager defers — writes nothing, table left as it was',
        () async {
      final pending = StreamController<bool>(); // never answers
      addTearDown(pending.close);
      final h = harness(
        schedules: const [customerSchedule],
        solarFlag: false,
        solarFlagStream: pending.stream,
      );
      await h.manager.initialize();
      final result = await h.manager.handleEntryCreated(gameDayEntry());
      expect(h.writes, isEmpty,
          reason: 'outcome ${result.outcome}; table written: '
              '${tableOf(h.writes)}');
      expect(result.outcome, isNot(LeaseOutcome.leased),
          reason: 'no lease is recorded without its timer write');
    });
  });

  group('solarSchedulingEnabledSyncProvider — what schedule sync reads', () {
    // schedule_sync.dart reads the SYNC provider (ref.read, no await), so this
    // is how its own flag read treats the same two states.

    test('while the stream is loading it reads OFF', () {
      final pending = StreamController<bool>();
      addTearDown(pending.close);
      final container = ProviderContainer(overrides: [
        solarSchedulingEnabledProvider.overrideWith((_) => pending.stream),
      ]);
      addTearDown(container.dispose);
      expect(container.read(solarSchedulingEnabledProvider).isLoading, isTrue);
      expect(container.read(solarSchedulingEnabledSyncProvider), isFalse);
    });

    test('after a stream error it reads OFF', () async {
      final container = ProviderContainer(overrides: [
        solarSchedulingEnabledProvider.overrideWith(
            (_) => Stream<bool>.error(StateError('flag read failed'))),
      ]);
      addTearDown(container.dispose);
      container.listen(solarSchedulingEnabledProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(solarSchedulingEnabledProvider).hasError, isTrue);
      expect(container.read(solarSchedulingEnabledSyncProvider), isFalse);
    });
  });
}
