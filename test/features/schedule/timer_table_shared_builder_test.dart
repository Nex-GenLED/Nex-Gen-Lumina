// One timer table for every controller write (fix/122-timer-table, item 1).
//
// Each test drives a REAL writer — ScheduleSyncService.syncAll,
// CalendarEntryLeaseManager.handleEntryCreated, SunriseOffService.arm — feeds
// exactly what it sends into a model of the controller's firmware, and asserts
// what fires over a day. The firmware models are transcribed from WLED source
// (support/wled_timer_firmware.dart) and have NOT run on a controller; every
// test that depends on them says "per WLED source" in its name.
//
// Fixtures: 0.15.x (0.15.1 = 0.15.4) and 16.0.1; a two-channel controller for
// the lease write. Sun times: the bench location on Nov 3 2026, sunrise 06:46,
// sunset 17:14.

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
import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ControllerClockInfo;
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'arm_check_harness.dart';
import 'support/wled_timer_firmware.dart';

const int kEveningLook = 10;
const int kNightLook = 11;

ScheduleItem sunsetToEleven() => patternSchedule(
      on: 'Sunset',
      off: '11:00 PM',
      label: 'Pattern: evening',
      presetId: kEveningLook,
    );

ScheduleItem sixToSunrise() => patternSchedule(
      on: '6:00 PM',
      off: 'Sunrise',
      label: 'Pattern: night',
      presetId: kNightLook,
    );

ScheduleItem sunsetToSunrise() => patternSchedule(
      on: 'Sunset',
      off: 'Sunrise',
      label: 'Pattern: dusk to dawn',
      presetId: kEveningLook,
    );

/// What fires on one day of [weekday] (1 = Mon … 7 = Sun), as "HH:MM → preset".
List<String> day(WledTimerFirmware fw, int weekday) => [
      for (final e in runDays(fw, days: 1, startWeekday: weekday))
        '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')} → ${e.preset}',
    ];

/// The table schedule sync writes for [schedules] (solar flag on, coordinates
/// set), through the real syncAll.
Future<List<Map<String, dynamic>>> syncTable(
  List<ScheduleItem> schedules, {
  bool sunriseOff = false,
}) async {
  final repo = FaithfulController();
  final ref = armCheckContainer(repo, solarFlag: true, sunriseOffOn: sunriseOff)
      .read(armCheckRefProvider);
  final r = await const ScheduleSyncService().syncAll(ref, schedules);
  expect(r.success, isTrue, reason: 'sync: ${r.error} ${r.presetErrors}');
  return repo.lastIns;
}

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
        'bri': 128,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 100, 'on': true, 'fx': 0},
          {'id': 1, 'start': 100, 'stop': 200, 'on': true, 'fx': 0},
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

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A one-night entry for TOMORROW 20:30–21:30 — always inside the 48 h window,
/// never expired, and clear of the schedules' own minutes.
CalendarEntry tomorrowNight() => CalendarEntry(
      dateKey: _dateKey(DateTime.now().add(const Duration(days: 1))),
      patternName: 'Harvest Moon - Solid',
      color: const Color(0xFFFF8C00),
      onTime: '20:30',
      offTime: '21:30',
      brightness: 100,
      type: CalendarEntryType.user,
      autopilot: false,
      wledPayload: const {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 0,
            'col': [
              [255, 140, 0, 0]
            ]
          }
        ],
      },
    );

int get tomorrowWeekday =>
    DateTime.now().add(const Duration(days: 1)).weekday; // Dart: Mon = 1

/// The table the lease manager writes when it arms [tomorrowNight] on a
/// two-channel controller holding [schedules].
Future<({List<Map<String, dynamic>> ins, int leasePreset})> leaseTable(
    List<ScheduleItem> schedules) async {
  List<Map<String, dynamic>>? captured;
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(_TwoChannelController()),
    calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
    calendarLeaseLiveWritesEnabledProvider
        .overrideWith((_) => Stream.value(true)),
    calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
    calendarLeaseEntriesProvider.overrideWithValue(const []),
    calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
    calendarLeaseSchedulesProvider.overrideWithValue(schedules),
    calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
    calendarLeaseScheduleSyncTriggerProvider.overrideWith((_) => () async {}),
    solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(true)),
    solarSchedulingEnabledSyncProvider.overrideWithValue(true),
    globalSunriseOffTimerProvider.overrideWithValue(null),
  ]);
  addTearDown(container.dispose);
  final manager = container.read(calendarEntryLeaseManagerProvider);
  manager.cfgPushFn = (repo, payload, ins) async {
    captured = ins;
    return CfgPushOutcome.confirmed;
  };
  await manager.initialize();
  final r = await manager.handleEntryCreated(tomorrowNight());
  expect(r.outcome, LeaseOutcome.leased, reason: 'lease: ${r.outcome}');
  return (ins: captured!, leasePreset: r.lease!.presetId);
}

/// A controller whose timer table IS the firmware model: the old sunrise-off
/// toggle read it back, the new one must not need to.
class _ModelController extends WledService {
  _ModelController(this.fw) : super('http://mock');
  final WledTimerFirmware fw;

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async =>
      fw.readback();

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => {
        2: {
          'n': ScheduleSyncService.kNglOffPresetName,
          'on': false,
          'seg': [
            {'id': 0, 'on': false}
          ],
        },
      };

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': false,
        'seg': [
          {'id': 0}
        ],
      };

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async =>
      const ControllerClockInfo(latitude: 40.0, longitude: -95.0);
}

final _refProvider = Provider<Ref>((ref) => ref);

/// The table the sunrise-off toggle writes when switched ON over [fw], with
/// [schedules] on the account.
Future<List<Map<String, dynamic>>> sunriseOffArmTable(
    WledTimerFirmware fw, List<ScheduleItem> schedules) async {
  List<Map<String, dynamic>>? captured;
  SunriseOffService.cfgPushFn = (repo, payload, ins) async {
    captured = ins;
    return CfgPushOutcome.confirmed;
  };
  addTearDown(() => SunriseOffService.cfgPushFn = (repo, payload, ins) =>
      pushCfgWithVerify(repo: repo, payload: payload, ins: ins));
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(_ModelController(fw)),
    calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
    calendarLeaseSchedulesProvider.overrideWithValue(schedules),
    calendarLeaseActiveTimersProvider
        .overrideWithValue(const LeaseLedgerEmpty()),
    solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(true)),
  ]);
  addTearDown(container.dispose);
  final result =
      await const SunriseOffService().arm(container.read(_refProvider));
  expect(result, SunriseOffWriteResult.confirmed);
  return captured!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetRepairAttempts();
  });

  group('a one-night lease write keeps sunrise/sunset schedules\' clock rows',
      () {
    test(
        'per WLED source, 0.15.x: after a lease arms on a two-channel '
        'controller, "Sunset → 11 PM" still goes off at 11 PM and "6 PM → '
        'Sunrise" still comes on at 6 PM', () async {
      final schedules = [sunsetToEleven(), sixToSunrise()];
      final fw = Wled015Timers()..post(await syncTable(schedules));
      final lease = await leaseTable(schedules);
      fw.post(lease.ins);

      expect(day(fw, tomorrowWeekday), [
        '06:46 → 2', // 6 PM → Sunrise ends
        '17:14 → $kEveningLook', // Sunset → 11 PM begins
        '18:00 → $kNightLook', // 6 PM → Sunrise begins
        '20:30 → ${lease.leasePreset}', // the one-night
        '23:00 → 2', // Sunset → 11 PM ends
      ]);
    });

    test(
        'per WLED source, 16.0.1: the same lease write keeps every row — the '
        '8-row write used to replace the whole list and delete the sun rows',
        () async {
      final schedules = [sunsetToEleven(), sixToSunrise()];
      final fw = Wled16Timers()..post(await syncTable(schedules));
      final lease = await leaseTable(schedules);
      fw.post(lease.ins);

      expect(day(fw, tomorrowWeekday), [
        '06:46 → 2',
        '17:14 → $kEveningLook',
        '18:00 → $kNightLook',
        '20:30 → ${lease.leasePreset}',
        '23:00 → 2',
      ]);
    });

    test('the lease write is the whole 10-row table', () async {
      final lease = await leaseTable([sunsetToEleven()]);
      expect(lease.ins, hasLength(10));
      expect(lease.ins[8], {'en': 0, 'hour': 255, 'min': 0, 'macro': 0, 'dow': 0},
          reason: 'nothing owns sunrise → the disabled placeholder');
      expect(lease.ins[9],
          {'en': 1, 'hour': 254, 'min': 0, 'macro': kEveningLook, 'dow': 127});
    });
  });

  group('a sunset row is a sunset on 16.0.1', () {
    test(
        'per WLED source, 16.0.1: "Sunset → Sunrise" comes on at sunset and '
        'goes off at sunrise (sent as 255/255 it came on at SUNRISE)',
        () async {
      final fw = Wled16Timers()..post(await syncTable([sunsetToSunrise()]));
      expect(day(fw, 3), ['06:46 → 2', '17:14 → $kEveningLook']);
    });

    test(
        'per WLED source, 16.0.1: "Sunset → 11 PM" comes on at sunset, not '
        'at sunrise', () async {
      final fw = Wled16Timers()..post(await syncTable([sunsetToEleven()]));
      expect(day(fw, 3), ['17:14 → $kEveningLook', '23:00 → 2']);
    });

    test('per WLED source, 0.15.x: the same tables still fire correctly',
        () async {
      final a = Wled015Timers()..post(await syncTable([sunsetToSunrise()]));
      expect(day(a, 3), ['06:46 → 2', '17:14 → $kEveningLook']);
      final b = Wled015Timers()..post(await syncTable([sunsetToEleven()]));
      expect(day(b, 3), ['17:14 → $kEveningLook', '23:00 → 2']);
    });
  });

  group('a reboot keeps a lone sunset a sunset', () {
    test(
        'per WLED source, 0.15.x: after a power cut "Sunset → 11 PM" still '
        'fires at sunset (a stubbed slot 8 was dropped from cfg.json, so the '
        'boot parse moved the sunset row into the sunrise slot)', () async {
      final fw = Wled015Timers()..post(await syncTable([sunsetToEleven()]));
      fw.reboot();
      expect(day(fw, 3), ['17:14 → $kEveningLook', '23:00 → 2']);
    });

    test('per WLED source, 16.0.1: the same, after a reboot', () async {
      final fw = Wled16Timers()..post(await syncTable([sunsetToEleven()]));
      fw.reboot();
      expect(day(fw, 3), ['17:14 → $kEveningLook', '23:00 → 2']);
    });

    test('per WLED source, 0.15.x: the boot file keeps slot 8 in place', () async {
      final fw = Wled015Timers()..post(await syncTable([sunsetToEleven()]));
      final file = fw.readback();
      expect(file.where((t) => t['hour'] == 255), hasLength(1),
          reason: 'the placeholder survives serialization');
      expect(file.indexWhere((t) => t['hour'] == 255),
          lessThan(file.indexWhere((t) => t['hour'] == 254)),
          reason: 'slot 8 precedes slot 9 in cfg.json');
    });
  });

  group('switching the daily sunrise-off on keeps a lone sunset row', () {
    test(
        'per WLED source, 0.15.x: "Sunset → 11 PM" still comes on at sunset '
        'after "Turn lights off at sunrise daily" is switched on', () async {
      final schedules = [sunsetToEleven()];
      final fw = Wled015Timers()..post(await syncTable(schedules));
      fw.post(await sunriseOffArmTable(fw, schedules));
      expect(day(fw, 3), [
        '06:46 → 2', // the daily sunrise-off
        '17:14 → $kEveningLook',
        '23:00 → 2',
      ]);
    });

    test('per WLED source, 16.0.1: the same', () async {
      final schedules = [sunsetToEleven()];
      final fw = Wled16Timers()..post(await syncTable(schedules));
      fw.post(await sunriseOffArmTable(fw, schedules));
      expect(day(fw, 3), ['06:46 → 2', '17:14 → $kEveningLook', '23:00 → 2']);
    });
  });

  group('the verify and the published boundaries read the new encoding', () {
    test(
        'per WLED source, 0.15.x and 16.0.1: the readback of the sync table '
        'verifies, and a sunset that came back as a second sunrise does not',
        () async {
      final sent = await syncTable([sunsetToEleven()]);
      for (final fw in [Wled015Timers(), Wled16Timers()]) {
        fw.post(sent);
        expect(solarTimersLanded(sent, fw.readback()), isTrue,
            reason: '${fw.runtimeType}');
        final asSunrise = [
          for (final r in fw.readback())
            r['hour'] == 254 ? {...r, 'hour': 255} : r,
        ];
        expect(solarTimersLanded(sent, asSunrise), isFalse,
            reason: 'a sunset stored as 255 is a sunrise on 16.0.1');
      }
    });

    test(
        'per WLED source, 0.15.x: a cold readback names the lone sunset row '
        'a sunset (it used to be "solar, direction unknown")', () async {
      final fw = Wled015Timers()..post(await syncTable([sunsetToEleven()]));
      final rows = extractBaseBoundaries(fw.readback())!;
      expect(rows.map((r) => r.kind), [kBoundaryKindClock, kBoundaryKindSunset]);
    });
  });
}
