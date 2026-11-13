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
// Build 127 — OWNERSHIP (timer_table_ownership.dart). The lease writer no
// longer builds the schedules' rows from state at all: it reads the table the
// controller holds, keeps every row that is not a lease row byte for byte,
// and replaces only the lease rows. So the controller here HOLDS the table a
// schedule sync wrote for the customer's schedule (the 5:30 PM ON row in a
// general slot; the sunrise OFF as {en:1, hour:255, min:0, macro:2, dow:127}
// in slot 8; slot 9 an all-zero stub the readback drops), and every case
// asserts that the lease write sends those rows back unchanged with the lease
// row after them. The solar flag — loading, on or off — is irrelevant to this
// writer and the cases say so. The last group records what the sync provider
// (schedule sync's own read) answers while loading and after an error.

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

/// One controller that reports coordinates and HOLDS a timer table. Timer
/// tables carry no segment geometry, so nothing else is overridden.
class _Controller extends WledService {
  _Controller(this.held) : super('http://mock');

  /// What the controller reads back (compacted: no all-zero stubs).
  final List<Map<String, dynamic>> held;

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async =>
      [for (final t in held) Map<String, dynamic>.from(t)];

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async =>
      const ControllerClockInfo(latitude: 40.0, longitude: -95.0);
}

/// A general row as a 0.15.x controller reads it back.
Map<String, dynamic> heldRow({
  required int hour,
  required int min,
  required int macro,
  required int dow,
}) =>
    {
      'en': 1,
      'hour': hour,
      'min': min,
      'macro': macro,
      'dow': dow,
      'start': {'mon': 1, 'day': 1},
      'end': {'mon': 12, 'day': 31},
    };

/// The sunrise OFF a schedule sync wrote for [customerSchedule] (slot 8).
const Map<String, dynamic> heldSunriseOff = {
  'en': 1,
  'hour': 255,
  'min': 0,
  'macro': 2,
  'dow': 127,
};

/// What a schedule sync left on the controller for [customerSchedule].
List<Map<String, dynamic>> customerTable() => [
      heldRow(hour: 17, min: 30, macro: 3, dow: 127),
      Map<String, dynamic>.from(heldSunriseOff),
    ];

/// What a schedule sync left on the controller for [clockOnlySchedule].
List<Map<String, dynamic>> clockOnlyTable() => [
      heldRow(hour: 18, min: 0, macro: 3, dow: 127),
      heldRow(hour: 23, min: 0, macro: 2, dow: 127),
    ];

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
    List<Map<String, dynamic>> held = const [],
  }) {
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(_Controller(held)),
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
    final h = harness(
        schedules: const [customerSchedule],
        solarFlag: true,
        held: customerTable());
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(gameDayEntry());
    expect(result.outcome, LeaseOutcome.leased);
    expect(h.writes, hasLength(1), reason: 'one merged timer write');
    final ins = insOf(h.writes.single);

    // Slot 0: the schedule's clock ON — 5:30 PM, preset 3, every day — sent
    // back exactly as the controller held it (the date range included). The
    // general slots hold the kept rows first, then the leases.
    expect(ins[0], heldRow(hour: 17, min: 30, macro: 3, dow: 127),
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
    // preset 2, every day — exactly as the controller held it.
    expect(ins[8], heldSunriseOff,
        reason: 'the sunrise OFF lives in slot 8, enabled');
    // Slot 9: nothing owns sunset.
    expect(ins[9], stub, reason: 'slot 9 is an all-zero stub');
  });

  test('the sunrise OFF boundary is never rendered into the general slots',
      () async {
    final h = harness(
        schedules: const [customerSchedule],
        solarFlag: true,
        held: customerTable());
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
    expect(ins[8], heldSunriseOff, reason: 'slot 8 holds the sunrise OFF');
  });

  test(
      'the lease writer does not consult the solar flag: with it OFF the rows '
      'the controller holds are still kept', () async {
    // Build 127 — before, the writer rebuilt the schedules from state and
    // refused the sun-bounded one while the flag was off, so the lease write
    // erased its 5:30 PM row. The rows on the controller are not this
    // writer's to judge.
    final h = harness(
        schedules: const [customerSchedule],
        solarFlag: false,
        held: customerTable());
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(gameDayEntry());
    expect(result.outcome, LeaseOutcome.leased);
    final ins = insOf(h.writes.single);
    expect(ins[0], heldRow(hour: 17, min: 30, macro: 3, dow: 127),
        reason: 'the 5:30 PM row is kept, flag or no flag');
    expect(ins[8], heldSunriseOff,
        reason: 'the sunrise OFF is kept, flag or no flag');
  });

  test('nothing on the controller: slot 8 is the disabled placeholder',
      () async {
    final h = harness(schedules: const [customerSchedule], solarFlag: false);
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(gameDayEntry());
    expect(result.outcome, LeaseOutcome.leased);
    final ins = insOf(h.writes.single);
    expect(ins.where((r) => isRow(r, hour: 17, min: 30)), isEmpty,
        reason: 'the writer invents no schedule row');
    expect(ins[8], sunrisePlaceholder,
        reason: 'nothing owns sunrise: slot 8 is the disabled placeholder');
  });

  test('a clock-only schedule keeps both rows (regression guard)', () async {
    final h = harness(
        schedules: const [clockOnlySchedule],
        solarFlag: true,
        held: clockOnlyTable());
    await h.manager.initialize();
    await h.manager.handleEntryCreated(gameDayEntry());
    final ins = insOf(h.writes.single);
    expect(ins.where((r) => isRow(r, hour: 18, min: 0)), hasLength(1));
    expect(ins.where((r) => isRow(r, hour: 23, min: 0)), hasLength(1));
  });

  group('the stream solar flag while loading', () {
    // Build 127 — nothing in the lease write is built from the flag any
    // more, so a flag that has not answered holds nothing up: the write goes
    // out and keeps the rows the controller holds. (Before 127 the writer
    // deferred here, because a table built on a guessed flag would have
    // dropped a sun-bounded schedule's clock row.)

    test('LOADING: the write still goes out and keeps every held row',
        () async {
      final pending = StreamController<bool>(); // never answers
      // Nothing subscribes to it any more, so its close is not awaited (a
      // single-subscription controller nobody listened to never reports done).
      addTearDown(() {
        pending.close();
      });
      final h = harness(
        schedules: const [customerSchedule],
        solarFlag: false,
        solarFlagStream: pending.stream,
        held: customerTable(),
      );
      await h.manager.initialize();
      final result = await h.manager.handleEntryCreated(gameDayEntry());
      expect(result.outcome, LeaseOutcome.leased,
          reason: 'table written: ${tableOf(h.writes)}');
      final ins = insOf(h.writes.single);
      expect(ins[0], heldRow(hour: 17, min: 30, macro: 3, dow: 127));
      expect(ins[8], heldSunriseOff);
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
