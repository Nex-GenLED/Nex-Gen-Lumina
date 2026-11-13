// Build 127 — table ownership: a writer changes only the rows it owns and
// keeps every other row the controller already holds, byte for byte.
//
// Written FIRST, against bd29c38 (build 126), where every case below fails:
// each writer rebuilt the whole timer table from the account's stored
// schedules, and a stored schedule that resolves to no macro ("Pattern: …",
// a Lumina-chat label, an Autopilot label — 29 of the 30 enabled schedules
// in the fleet) was silently left out of the table that went to the device.
//
// The fixtures are the audit's real cases (timer rows as a 0.15.x controller
// reads them back: the armed rows plus the hour-255 sunrise placeholder, each
// general row carrying the `start`/`end` date range the firmware serialises;
// all-zero stubs are dropped). The schedules are stored the way the fleet
// stores them: a design payload, no `presetId`.
//
//   (a) Ellie — a 17:00 ON row (macro 10, role schedule), a 07:00 OFF row
//       (macro 2) and the daily sunrise-off, with a one-night lease
//       promotion;
//   (b) the same table with a lease expiry zeroing;
//   (c) the same table with the Settings sunrise-off toggle flipped;
//   (d) syncAll for a painted-design schedule whose read-back mismatches,
//       and one whose read-back is unreadable, with that schedule's rows
//       already on the device and the sunrise-off keeping the table
//       "not empty" for the clobber guard;
//   (e) Stegall — a "Deep Blue" schedule (a Lumina-chat label) at 17:12 on
//       and 06:51 off, with a Game Day entry edit.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/game_day/served_game_day.dart'
    show ServedVerdict, servedGameDayEntryTestProvider;
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/schedule/timer_table.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ControllerClockInfo;
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerDefaultsHealerProvider, ControllerHealReport;
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── A controller that HOLDS a timer table ─────────────────────────────────

/// The date range a 0.15.x controller serialises on every general row.
const Map<String, dynamic> kFullYearStart = {'mon': 1, 'day': 1};
const Map<String, dynamic> kFullYearEnd = {'mon': 12, 'day': 31};

Map<String, dynamic> _deep(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// What the controller reads back for the rows it was sent: WLED drops every
/// all-zero row (cfg.cpp: `macro == 0 && hour == 0 && min == 0` → skipped)
/// and serialises `start`/`end` on slots 0–7.
List<Map<String, dynamic>> _readbackOf(List<Map<String, dynamic>> sent) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < sent.length; i++) {
    final t = _deep(sent[i]);
    int f(String k) => (t[k] is num) ? (t[k] as num).toInt() : 0;
    if (f('macro') == 0 && f('hour') == 0 && f('min') == 0) continue;
    if (i < 8) {
      t.putIfAbsent('start', () => _deep(kFullYearStart));
      t.putIfAbsent('end', () => _deep(kFullYearEnd));
    }
    out.add(t);
  }
  return out;
}

class _Device extends WledService {
  _Device({
    required List<Map<String, dynamic>> table,
    Map<int, Map<String, dynamic>>? presets,
    this.storeMutation,
  })  : table = [for (final t in table) _deep(t)],
        device = {...?presets},
        super('http://mock');

  /// The controller's timer table, readback shape.
  List<Map<String, dynamic>> table;

  /// Every timer table written, in order (the exact `ins` sent).
  final List<List<Map<String, dynamic>>> writes = [];

  /// presets.json as the controller holds it, updated by every psave.
  final Map<int, Map<String, dynamic>> device;

  /// Applied to the stored copy of a psave: a controller that did not store
  /// what it was sent.
  final void Function(Map<String, dynamic> stored)? storeMutation;

  /// Scripted `readPresets` outcomes (true = readable); exhausted → readable.
  final List<bool> readOutcomes = [];

  final List<int> savedPresetIds = [];

  static const int kBusLen = 100;

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async =>
      [for (final t in table) _deep(t)];

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    final ins = (cfg['timers'] as Map?)?['ins'];
    if (ins is List) {
      final sent = ins.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      writes.add([for (final t in sent) _deep(t)]);
      table = _readbackOf(sent);
    }
    return true;
  }

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => ControllerClockInfo(
        latitude: 38.99,
        longitude: -94.25,
        timerRows: [for (final t in table) _deep(t)],
      );

  @override
  Future<WledHardwareConfig?> getConfig() async => WledHardwareConfig(
        totalLeds: kBusLen,
        maxPowerMw: 30000,
        buses: [
          WledLedBus(pin: [0], start: 0, len: kBusLen, type: 30, order: 1),
        ],
      );

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': false,
        'bri': 128,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': kBusLen,
            'on': true,
            'fx': 0,
            'col': [
              [255, 160, 0, 0],
              [0, 0, 0, 0],
              [0, 0, 0, 0]
            ],
          },
        ],
      };

  @override
  Future<WledInfoResponse?> getInfo() async =>
      const WledInfoResponse(maxseg: 10, arch: 'esp32', ver: '0.15.4');

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async =>
      {for (final e in device.entries) e.key: _deep(e.value)};

  @override
  Future<PresetsRead> readPresets() async {
    final readable = readOutcomes.isEmpty ? true : readOutcomes.removeAt(0);
    if (!readable) return const PresetsRead.unreadable('scripted');
    if (device.isEmpty) return const PresetsRead.deviceEmpty();
    return PresetsRead.available(await fetchPresets());
  }

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    savedPresetIds.add(presetId);
    final stored = _deep(state)
      ..remove('o')
      ..remove('psave')
      ..remove('ib');
    if (presetName != null && presetName.isNotEmpty) stored['n'] = presetName;
    storeMutation?.call(stored);
    device[presetId] = stored;
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async {
    device.remove(presetId);
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => true;
}

// ─── Fixtures ──────────────────────────────────────────────────────────────

Map<String, dynamic> _general({
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
      'start': _deep(kFullYearStart),
      'end': _deep(kFullYearEnd),
    };

/// The daily sunrise-off exactly as the app arms it (slot 8).
Map<String, dynamic> _sunriseOffRow() =>
    {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127};

/// Ellie: ON 17:00 (macro 10, role schedule), OFF 07:00 (macro 2), daily.
final Map<String, dynamic> kEllieOn =
    _general(hour: 17, min: 0, macro: 10, dow: 127);
final Map<String, dynamic> kEllieOff =
    _general(hour: 7, min: 0, macro: 2, dow: 127);

/// Ellie's stored schedule, as the fleet stores it: no presetId.
const ScheduleItem kEllieSchedule = ScheduleItem(
  id: 'ellie-christmas',
  timeLabel: '5:00 PM',
  offTimeLabel: '7:00 AM',
  repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  actionLabel: 'Pattern: Classic Christmas 2',
  enabled: true,
  wledPayload: {
    'on': true,
    'bri': 255,
    'seg': [
      {'id': 0, 'fx': 84, 'pal': 5}
    ],
  },
);

/// Stegall: "Deep Blue" (a Lumina-chat label) ON 17:12, OFF 06:51, daily.
final Map<String, dynamic> kStegallOn =
    _general(hour: 17, min: 12, macro: 10, dow: 127);
final Map<String, dynamic> kStegallOff =
    _general(hour: 6, min: 51, macro: 2, dow: 127);

const ScheduleItem kStegallSchedule = ScheduleItem(
  id: 'stegall-deep-blue',
  timeLabel: '5:12 PM',
  offTimeLabel: '6:51 AM',
  repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  actionLabel: 'Deep Blue',
  enabled: true,
  wledPayload: {
    'on': true,
    'bri': 220,
    'seg': [
      {
        'id': 0,
        'fx': 0,
        'col': [
          [0, 32, 160, 0]
        ]
      }
    ],
  },
);

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A fixed "now": Thursday 2026-11-12 12:00 local.
final DateTime kNow = DateTime(2026, 11, 12, 12, 0);
final DateTime kTomorrow = kNow.add(const Duration(days: 1));
final String kTomorrowKey = _dateKey(kTomorrow);
final int kTomorrowDow = wledDowMaskForWeekday(kTomorrow.weekday);

CalendarEntry _gameDayTomorrow({String onTime = '14:55'}) => CalendarEntry(
      dateKey: kTomorrowKey,
      patternName: 'Game Day',
      color: const Color(0xFFE31837),
      onTime: onTime,
      offTime: '19:55',
      brightness: 85,
      type: CalendarEntryType.user,
      autopilot: false,
    );

const Map<String, dynamic> kLeasePayload = {
  'on': true,
  'bri': 217,
  'seg': [
    {
      'fx': 0,
      'col': [
        [227, 24, 55, 0]
      ]
    }
  ],
};

/// A registered, armed lease for tomorrow's Game Day at [hour]:[min].
CalendarEntryLease _leaseTomorrow({int hour = 14, int min = 55, int macro = 31}) =>
    CalendarEntryLease(
      dateKey: kTomorrowKey,
      slotIndex: 2,
      presetId: macro,
      leasedAt: kNow.subtract(const Duration(hours: 1)),
      expiresAt: DateTime(kTomorrow.year, kTomorrow.month, kTomorrow.day, 19, 55),
      wledPayload: kLeasePayload,
      patternName: 'Game Day',
      wledHour: hour,
      wledMin: min,
      dowMask: kTomorrowDow,
    );

/// A lease whose night is over (expired at 21:30 yesterday).
CalendarEntryLease _leaseExpired({int macro = 30}) {
  final y = kNow.subtract(const Duration(days: 1));
  return CalendarEntryLease(
    dateKey: _dateKey(y),
    slotIndex: 2,
    presetId: macro,
    leasedAt: y.subtract(const Duration(hours: 6)),
    expiresAt: DateTime(y.year, y.month, y.day, 21, 30),
    wledPayload: kLeasePayload,
    patternName: 'Harvest Moon',
    wledHour: 20,
    wledMin: 30,
    dowMask: wledDowMaskForWeekday(y.weekday),
  );
}

// ─── Assertions ────────────────────────────────────────────────────────────

/// Structural equality of two JSON-shaped values (maps, lists, scalars).
bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_sameJson(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

/// The row, exactly as the controller held it, is somewhere in [ins].
void expectKept(List<Map<String, dynamic>> ins, Map<String, dynamic> row,
    {required String what}) {
  expect(ins.any((t) => _sameJson(t, row)), isTrue,
      reason: '$what must be kept byte-for-byte: expected $row in\n'
          '${ins.map((t) => '  $t').join('\n')}');
}

List<Map<String, dynamic>> _leaseRows(List<Map<String, dynamic>> ins) => [
      for (final t in ins)
        if (t['en'] == 1 &&
            (t['macro'] as num) >= kFirstLeasePresetId &&
            (t['macro'] as num) <= kLastLeasePresetId)
          t,
    ];

// ─── Harnesses ─────────────────────────────────────────────────────────────

final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _leaseContainer(
  _Device device, {
  required List<ScheduleItem> schedules,
  bool sunriseOffOn = false,
}) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(device),
    calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
    calendarLeaseLiveWritesEnabledProvider
        .overrideWith((_) => Stream.value(true)),
    calendarLeaseScheduleSlotDemandProvider.overrideWith((_) =>
        schedules.fold<int>(
            0, (n, s) => n + generalRowsFor(s, solarEnabled: false))),
    calendarLeaseEntriesProvider.overrideWithValue(const []),
    calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
    calendarLeaseSchedulesProvider.overrideWithValue(schedules),
    calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
    calendarLeaseScheduleSyncTriggerProvider.overrideWith((_) => () async {}),
    solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(false)),
    solarSchedulingEnabledSyncProvider.overrideWithValue(false),
    globalSunriseOffTimerProvider
        .overrideWithValue(sunriseOffOn ? _sunriseOffRow() : null),
    servedGameDayEntryTestProvider
        .overrideWithValue((_, __) => ServedVerdict.notServed),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<CalendarEntryLeaseManager> _manager(ProviderContainer c) async {
  final m = c.read(calendarEntryLeaseManagerProvider);
  m.nowProvider = () => kNow;
  await m.initialize();
  return m;
}

ProviderContainer _toggleContainer(_Device device,
    {required List<ScheduleItem> schedules}) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(device),
    calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
    calendarLeaseSchedulesProvider.overrideWithValue(schedules),
    calendarLeaseActiveTimersProvider
        .overrideWithValue(const LeaseLedgerEmpty()),
    solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(false)),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// A satisfying NGL Off preset (root on:false, every segment off, the name),
/// so arming the toggle needs no preset write.
Map<String, dynamic> _goodOffPreset() => {
      'n': ScheduleSyncService.kNglOffPresetName,
      'on': false,
      'seg': [
        {'id': 0, 'on': false}
      ],
    };

ProviderContainer _syncContainer(
  _Device device, {
  required bool sunriseOffOn,
  List<CustomDesign>? designs,
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(device),
    calendarLeaseActiveTimersProvider
        .overrideWithValue(const LeaseLedgerEmpty()),
    solarSchedulingEnabledSyncProvider.overrideWithValue(false),
    globalSunriseOffTimerProvider
        .overrideWithValue(sunriseOffOn ? _sunriseOffRow() : null),
    scheduleSyncDesignsProvider.overrideWithValue(() async => designs),
    controllerDefaultsHealerProvider.overrideWithValue(
        () async => ControllerHealReport()..reachable = false),
  ]);
  addTearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.dispose();
  });
  return c;
}

// ─── The painted design for (d) ────────────────────────────────────────────

final DateTime _designAt = DateTime(2026, 11, 5);

CustomDesign _porchStripes() => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'uid',
      createdAt: _designAt,
      updatedAt: _designAt,
      perPixel: true,
      brightness: 180,
      brightnessStated: true,
      layoutStamp: const DesignLayoutStamp(
          controllerId: 'ctl-a', busLengths: [_Device.kBusLen]),
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Channel 1',
          ledCount: _Device.kBusLen,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
          ],
        ),
      ],
    );

ScheduleItem _designSchedule(Map<String, dynamic> body) => ScheduleItem(
      id: 'sch-design',
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: 'Pattern: Porch stripes',
      enabled: true,
      wledPayload: body,
      designId: 'd1',
      presetKind: kSchedulePresetKindApi,
    );

final Map<String, dynamic> kDesignOn =
    _general(hour: 19, min: 0, macro: 10, dow: 127);
final Map<String, dynamic> kDesignOff =
    _general(hour: 23, min: 0, macro: 2, dow: 127);

void _breakStoredPaint(Map<String, dynamic> stored) {
  final seg = stored['seg'];
  if (seg is! List) return;
  for (final s in seg) {
    if (s is Map && s['i'] is List) {
      final i = s['i'] as List;
      if (i.length > 2) i[2] = [0, 0, 0, 0];
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetRepairAttempts();
  });

  group('(a) Ellie — a lease promotion keeps the schedule rows', () {
    test(
        'the table written to arm a one-night lease still holds the 17:00 ON, '
        'the 07:00 OFF and the sunrise-off, and adds the lease row', () async {
      final device = _Device(table: [kEllieOn, kEllieOff, _sunriseOffRow()]);
      final c = _leaseContainer(device,
          schedules: const [kEllieSchedule], sunriseOffOn: true);
      final m = await _manager(c);

      final r = await m.handleEntryCreated(_gameDayTomorrow());

      expect(r.outcome, LeaseOutcome.leased, reason: '${r.errorMessage}');
      expect(device.writes, isNotEmpty, reason: 'the lease write went out');
      final ins = device.writes.last;
      expect(ins.length, kTableSlots);
      expectKept(ins, kEllieOn, what: 'the 17:00 ON row (macro 10)');
      expectKept(ins, kEllieOff, what: 'the 07:00 OFF row (macro 2)');
      expect(ins[kTableSunriseSlot], _sunriseOffRow(),
          reason: 'the sunrise-off stays in slot 8');
      final leases = _leaseRows(ins);
      expect(leases, hasLength(1), reason: 'exactly one lease row');
      expect(leases.single['hour'], 14);
      expect(leases.single['min'], 55);
      expect(leases.single['dow'], kTomorrowDow);
      expect(leases.single['macro'], r.lease!.presetId);
    });
  });

  group('(b) Ellie — a lease expiry zeroing keeps the schedule rows', () {
    test(
        'the zero-write after the night drops the lease row and nothing else',
        () async {
      final expired = _leaseExpired();
      final device = _Device(table: [
        kEllieOn,
        kEllieOff,
        _general(
            hour: expired.wledHour,
            min: expired.wledMin,
            macro: expired.presetId,
            dow: expired.dowMask),
        _sunriseOffRow(),
      ]);
      final c = _leaseContainer(device,
          schedules: const [kEllieSchedule], sunriseOffOn: true);
      final m = await _manager(c);
      m.injectLeaseForTest(expired);

      await m.sweepExpiredLeases();

      expect(m.leaseFor(expired.dateKey), isNull, reason: 'swept');
      expect(device.writes, isNotEmpty, reason: 'the zero-write went out');
      final ins = device.writes.last;
      expectKept(ins, kEllieOn, what: 'the 17:00 ON row (macro 10)');
      expectKept(ins, kEllieOff, what: 'the 07:00 OFF row (macro 2)');
      expect(ins[kTableSunriseSlot], _sunriseOffRow());
      expect(_leaseRows(ins), isEmpty, reason: 'the expired lease row is gone');
    });
  });

  group('(c) Ellie — the Settings sunrise-off toggle keeps the schedule rows',
      () {
    test('switching the sunrise-off OFF clears slot 8 and keeps every other row',
        () async {
      final device = _Device(
          table: [kEllieOn, kEllieOff, _sunriseOffRow()],
          presets: {2: _goodOffPreset()});
      final c = _toggleContainer(device, schedules: const [kEllieSchedule]);

      final result =
          await const SunriseOffService().disarm(c.read(_refProvider));

      expect(result, SunriseOffWriteResult.confirmed);
      final ins = device.writes.last;
      expectKept(ins, kEllieOn, what: 'the 17:00 ON row (macro 10)');
      expectKept(ins, kEllieOff, what: 'the 07:00 OFF row (macro 2)');
      expect(ins[kTableSunriseSlot], sunrisePlaceholder(),
          reason: 'the toggle owns the system_off sunrise row: cleared');
    });

    test('switching the sunrise-off ON takes slot 8 and keeps every other row',
        () async {
      final device = _Device(
          table: [kEllieOn, kEllieOff, sunrisePlaceholder()],
          presets: {2: _goodOffPreset()});
      final c = _toggleContainer(device, schedules: const [kEllieSchedule]);

      final result = await const SunriseOffService().arm(c.read(_refProvider));

      expect(result, SunriseOffWriteResult.confirmed);
      final ins = device.writes.last;
      expectKept(ins, kEllieOn, what: 'the 17:00 ON row (macro 10)');
      expectKept(ins, kEllieOff, what: 'the 07:00 OFF row (macro 2)');
      expect(ins[kTableSunriseSlot], _sunriseOffRow());
    });
  });

  group('(d) syncAll keeps the rows of a schedule it could not rebuild', () {
    final svc = const ScheduleSyncService(
        paceDelay: Duration.zero, readBackSettle: Duration.zero);

    test('a painted design whose read-back MISMATCHES keeps its device rows',
        () async {
      final design = _porchStripes();
      final body = buildDesignApiPresetBody(design)!;
      final device = _Device(
        table: [kDesignOn, kDesignOff, _sunriseOffRow()],
        storeMutation: _breakStoredPaint,
      );
      final c = _syncContainer(device, sunriseOffOn: true, designs: [design]);

      final result =
          await svc.syncAll(c.read(_refProvider), [_designSchedule(body)]);

      expect(result.presetErrors.join('\n'),
          contains("didn't land on your controller as written"),
          reason: 'the read-back mismatch is reported');
      expect(device.table.any((t) => t['hour'] == 19 && t['macro'] == 10),
          isTrue,
          reason: 'the 19:00 ON row (macro 10) is still on the controller — '
              'device table now: ${device.table}');
      expect(device.table.any((t) => t['hour'] == 23 && t['macro'] == 2),
          isTrue,
          reason: 'the 23:00 OFF row is still on the controller');
      for (final w in device.writes) {
        expectKept(w, kDesignOn, what: 'the 19:00 ON row, in every write');
        expectKept(w, kDesignOff, what: 'the 23:00 OFF row, in every write');
      }
    });

    test('a painted design whose read-back is UNREADABLE keeps its device rows',
        () async {
      final design = _porchStripes();
      final body = buildDesignApiPresetBody(design)!;
      final device = _Device(table: [kDesignOn, kDesignOff, _sunriseOffRow()]);
      // Opening read readable; both read-back reads unreadable.
      device.readOutcomes.addAll([true, false, false]);
      final c = _syncContainer(device, sunriseOffOn: true, designs: [design]);

      final result =
          await svc.syncAll(c.read(_refProvider), [_designSchedule(body)]);

      expect(result.presetErrors.join('\n'), contains("couldn't be read back"),
          reason: 'written, not verified, is reported');
      expect(device.table.any((t) => t['hour'] == 19 && t['macro'] == 10),
          isTrue,
          reason: 'the 19:00 ON row (macro 10) is still on the controller — '
              'device table now: ${device.table}');
      expect(device.table.any((t) => t['hour'] == 23 && t['macro'] == 2),
          isTrue,
          reason: 'the 23:00 OFF row is still on the controller');
    });
  });

  group('(e) Stegall — a Game Day entry edit keeps the "Deep Blue" rows', () {
    test(
        'updating an armed lease replaces only the lease row; the 17:12 ON and '
        '06:51 OFF rows of a Lumina-chat schedule stay byte-for-byte',
        () async {
      final armed = _leaseTomorrow();
      final device = _Device(table: [
        kStegallOn,
        kStegallOff,
        _general(
            hour: armed.wledHour,
            min: armed.wledMin,
            macro: armed.presetId,
            dow: armed.dowMask),
      ]);
      final c = _leaseContainer(device, schedules: const [kStegallSchedule]);
      final m = await _manager(c);
      m.injectLeaseForTest(armed);

      final r = await m.handleEntryCreated(_gameDayTomorrow(onTime: '15:00'));

      expect(r.outcome, LeaseOutcome.updated, reason: '${r.errorMessage}');
      final ins = device.writes.last;
      expectKept(ins, kStegallOn, what: 'the 17:12 "Deep Blue" ON row');
      expectKept(ins, kStegallOff, what: 'the 06:51 "Deep Blue" OFF row');
      final leases = _leaseRows(ins);
      expect(leases, hasLength(1), reason: 'the one lease, updated in place');
      expect(leases.single['macro'], armed.presetId);
      expect(leases.single['hour'], 15);
      expect(leases.single['min'], 0);
    });
  });
}
