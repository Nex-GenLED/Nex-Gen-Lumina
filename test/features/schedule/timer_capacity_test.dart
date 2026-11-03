// Capacity (fix/122-timer-table, item 3): a schedule arms only if ALL of its
// rows fit, the customer is told in plain words when one does not, and a
// one-night is refused rather than cut when the rows are full.
//
// Drives the real ScheduleSyncService.syncAll and CalendarEntryLeaseManager,
// and runs what they send through firmware models transcribed from WLED
// source (support/wled_timer_firmware.dart — not bench-verified, hence "per
// WLED source"). Sun times: sunrise 06:46, sunset 17:14.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ControllerClockInfo;
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerDefaultsHealerProvider, ControllerHealReport;
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'arm_check_harness.dart';
import 'support/wled_timer_firmware.dart';

/// Four evening schedules with on AND off clock times: 8 rows, a full table.
List<ScheduleItem> fourClockPairs() => [
      for (final (i, on, off) in [
        (11, '6:00 PM', '7:00 PM'),
        (12, '7:30 PM', '8:00 PM'),
        (13, '8:30 PM', '9:00 PM'),
        (14, '9:30 PM', '10:00 PM'),
      ])
        patternSchedule(
            on: on, off: off, label: 'Pattern: look $i', presetId: i),
    ];

const List<String> kFourPairsDay = [
  '18:00 → 11',
  '19:00 → 2',
  '19:30 → 12',
  '20:00 → 2',
  '20:30 → 13',
  '21:00 → 2',
  '21:30 → 14',
  '22:00 → 2',
];

List<String> day(WledTimerFirmware fw) => [
      for (final e in runDays(fw, days: 1, startWeekday: 3))
        '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')} → ${e.preset}',
    ];

/// syncAll with an explicit lease ledger (the arm-check harness pins Empty).
Future<ScheduleSyncResult> sync(
  FaithfulController repo,
  List<ScheduleItem> schedules, {
  LeaseLedgerState leases = const LeaseLedgerEmpty(),
}) async {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseActiveTimersProvider.overrideWithValue(leases),
    solarSchedulingEnabledSyncProvider.overrideWithValue(true),
    globalSunriseOffTimerProvider.overrideWithValue(null),
    controllerDefaultsHealerProvider.overrideWithValue(
        () async => ControllerHealReport()..reachable = false),
  ]);
  addTearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.dispose();
  });
  return const ScheduleSyncService()
      .syncAll(c.read(armCheckRefProvider), schedules);
}

final firmwares = <String, WledTimerFirmware Function()>{
  '0.15.x': Wled015Timers.new,
  '16.0.1': Wled16Timers.new,
};

class _TwoChannelController extends WledService {
  _TwoChannelController() : super('http://mock');

  @override
  Future<WledHardwareConfig?> getConfig() async => WledHardwareConfig(
        totalLeds: 200,
        maxPowerMw: 30000,
        buses: [
          WledLedBus(pin: [0], start: 0, len: 100, type: 30, order: 1),
          WledLedBus(pin: [1], start: 100, len: 100, type: 30, order: 1),
        ],
      );

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': false,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 100},
          {'id': 1, 'start': 100, 'stop': 200},
        ],
      };

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      true;

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async =>
      const ControllerClockInfo(latitude: 40.0, longitude: -95.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetRepairAttempts();
  });

  for (final MapEntry(key: name, value: make) in firmwares.entries) {
    group('per WLED source, $name', () {
      test(
          'a full table plus "Sunset → 11 PM": the sunset schedule is not '
          'armed at all (it used to come on at sunset with no 11 PM row), '
          'and the customer is told why', () async {
        final repo = FaithfulController();
        final r = await sync(repo, [
          ...fourClockPairs(),
          patternSchedule(
              on: 'Sunset',
              off: '11:00 PM',
              label: 'Pattern: evening',
              presetId: 10),
        ]);
        expect(r.success, isTrue, reason: '${r.error}');
        final fw = make()..post(repo.lastIns);
        expect(day(fw), kFourPairsDay,
            reason: 'no ON may ever arm without its OFF');
        expect(
            r.presetErrors,
            contains('"Pattern: evening" is not on your controller: it needs '
                '1 timer slot and only 0 are free. Turn off or delete '
                'another schedule, then tap Sync.'));
      });

      test(
          'a one-night holding a row plus a schedule that only half fits: '
          'the one-night still fires (its row used to be cut), the schedule '
          'waits, and the message says what holds the slot', () async {
        final repo = FaithfulController();
        final r = await sync(
          repo,
          [
            ...fourClockPairs().take(3),
            patternSchedule(
                on: '10:15 PM',
                off: '10:30 PM',
                label: 'Pattern: late',
                presetId: 15),
          ],
          leases: const LeaseLedgerReady([
            {'en': 1, 'hour': 22, 'min': 45, 'macro': 30, 'dow': 127},
          ]),
        );
        expect(r.success, isTrue, reason: '${r.error}');
        final fw = make()..post(repo.lastIns);
        expect(day(fw), [...kFourPairsDay.take(6), '22:45 → 30']);
        expect(
            r.presetErrors,
            contains('"Pattern: late" is not on your controller: it needs 2 '
                'timer slots and only 1 is free (1 is held by one-night or '
                'Game Day nights). Turn off or delete another schedule, '
                'then tap Sync.'));
      });
    });
  }

  test('a schedule that does not fit no longer stops the ones after it',
      () {
    final r = ScheduleSyncService.splitByTimerCapacity(
      [
        ...fourClockPairs().take(3), // 6 rows
        patternSchedule(on: '10:15 PM', off: '10:30 PM', presetId: 15), // 2
        patternSchedule(on: '5:00 AM', presetId: 16), // 1 (no OFF)
      ],
      maxSlots: 7,
    );
    expect(r.overflowed, isTrue);
    expect(r.armed.map((s) => s.presetId), [11, 12, 13, 16]);
  });

  test(
      'two-channel controller with four clock pairs (8 rows): a one-night is '
      'refused honestly — it used to be given a slot and then cut', () async {
    final schedules = fourClockPairs();
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(_TwoChannelController()),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(true)),
      calendarLeaseEntriesProvider.overrideWithValue(const []),
      calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
      calendarLeaseSchedulesProvider.overrideWithValue(schedules),
      calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider
          .overrideWith((_) => () async {}),
      solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(true)),
      solarSchedulingEnabledSyncProvider.overrideWithValue(true),
      globalSunriseOffTimerProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    final manager = container.read(calendarEntryLeaseManagerProvider);
    manager.cfgPushFn = (repo, payload, ins) async => CfgPushOutcome.confirmed;
    await manager.initialize();

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final r = await manager.handleEntryCreated(CalendarEntry(
      dateKey: '${tomorrow.year.toString().padLeft(4, '0')}-'
          '${tomorrow.month.toString().padLeft(2, '0')}-'
          '${tomorrow.day.toString().padLeft(2, '0')}',
      patternName: 'Harvest Moon - Solid',
      color: const Color(0xFFFF8C00),
      onTime: '22:45',
      offTime: '23:30',
      brightness: 100,
      type: CalendarEntryType.user,
      autopilot: false,
    ));

    expect(r.outcome, LeaseOutcome.noFreeSlots,
        reason: 'the screen then says the timer slots are full, truthfully');
  });
}
