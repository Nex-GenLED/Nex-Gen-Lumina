// Build 133, fix 2 — an expired lease is never sent to the controller again.
//
// Lease rows are dateless (an hour, a minute and a weekday mask), so a lease
// row left on the controller fires again the same weekday next week, whether
// or not there is anything on that night. The expiry sweep removes a lease
// once its night is over, but only when its own write lands (on the LAN, flag
// loaded, table readable, write confirmed). Until then the record stays, and
// the row builder used to put that record's row back into EVERY table write:
// the lease writes (composeLeaseWrite), the ledger the schedule sync merges
// (activeLeaseTimers) and therefore syncAll's own table.
//
// The builder now skips an expired lease using the sweep's own rule
// (CalendarEntryLease.isExpiredAt): a lease is over once the clock has
// reached its end time. At the end time itself it is over; one instant
// before, the night is still running and keeps its row.
//
// Every clock here is injected (manager.nowProvider). Fixtures are UTC
// instants, so nothing depends on the wall clock, the TZ or the time of day
// the suite runs at.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/served_game_day.dart'
    show ServedVerdict, servedGameDayEntryTestProvider;
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ControllerClockInfo;
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerDefaultsHealerProvider, ControllerHealReport;
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── A LAN controller that holds a timer table ───────────────────────────────

Map<String, dynamic> _deep(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

class _Device extends WledService {
  _Device(List<Map<String, dynamic>> table)
      : table = [for (final t in table) _deep(t)],
        super('http://mock');

  /// The controller's timer table, readback shape (all-zero stubs dropped).
  List<Map<String, dynamic>> table;

  /// Every timer table written, in order.
  final List<List<Map<String, dynamic>>> writes = [];

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async =>
      [for (final t in table) _deep(t)];

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    final ins = (cfg['timers'] as Map?)?['ins'];
    if (ins is List) {
      final sent = [for (final t in ins.cast<Map>()) _deep(t.cast())];
      writes.add(sent);
      table = [
        for (final t in sent)
          if (!((t['macro'] ?? 0) == 0 &&
              (t['hour'] ?? 0) == 0 &&
              (t['min'] ?? 0) == 0))
            t,
      ];
    }
    return true;
  }

  // syncAll's reads and psave path — every one answered here, so nothing
  // reaches the real HTTP client.
  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => const {};
  @override
  Future<PresetsRead> readPresets() async => const PresetsRead.deviceEmpty();
  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => ControllerClockInfo(
        latitude: 38.99,
        longitude: -94.25,
        timerRows: [for (final t in table) _deep(t)],
      );
  @override
  Future<WledHardwareConfig?> getConfig() async => const WledHardwareConfig(
        totalLeds: 100,
        maxPowerMw: 30000,
        buses: [WledLedBus(pin: [0], start: 0, len: 100, type: 30, order: 1)],
      );
  @override
  Future<WledInfoResponse?> getInfo() async =>
      const WledInfoResponse(maxseg: 10, arch: 'esp32', ver: '0.15.4');
  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': true,
        'seg': [
          {'id': 0}
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
  Future<bool> deletePreset(int presetId) async => true;
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;
}

// ── Fixtures (synthetic, UTC) ───────────────────────────────────────────────

/// A Tuesday, far from any DST change.
final DateTime kNightDay = DateTime.utc(2026, 2, 10);

/// The night's end: 23:00 UTC on [kNightDay].
final DateTime kEnd = DateTime.utc(2026, 2, 10, 23, 0);

Map<String, dynamic> _row(int hour, int min, int macro, int dow) => {
      'en': 1,
      'hour': hour,
      'min': min,
      'macro': macro,
      'dow': dow,
      'start': {'mon': 1, 'day': 1},
      'end': {'mon': 12, 'day': 31},
    };

/// A schedule's own rows (not lease rows): ON 17:00, OFF 07:00, daily.
final kSchedOn = _row(17, 0, 10, 127);
final kSchedOff = _row(7, 0, 2, 127);

String _key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A lease for [day], on at 18:00, ending at [end].
CalendarEntryLease _lease({
  required DateTime day,
  required DateTime end,
  int macro = 30,
  int slot = 2,
}) =>
    CalendarEntryLease(
      dateKey: _key(day),
      slotIndex: slot,
      presetId: macro,
      leasedAt: day.subtract(const Duration(hours: 6)),
      expiresAt: end,
      wledPayload: const {'on': true, 'bri': 200},
      patternName: 'Night $macro',
      wledHour: 18,
      wledMin: 0,
      dowMask: wledDowMaskForWeekday(day.weekday),
    );

/// The night ending at [kEnd].
CalendarEntryLease _tonight() => _lease(day: kNightDay, end: kEnd);

/// A night a week later.
CalendarEntryLease _nextWeek() => _lease(
      day: kNightDay.add(const Duration(days: 7)),
      end: kEnd.add(const Duration(days: 7)),
      macro: 31,
      slot: 3,
    );

Map<String, dynamic> _rowOf(CalendarEntryLease l) =>
    _row(l.wledHour, l.wledMin, l.presetId, l.dowMask);

Set<int> _leaseMacros(Iterable<Map<String, dynamic>> ins) => {
      for (final t in ins)
        if (t['en'] == 1 &&
            (t['macro'] as num) >= kFirstLeasePresetId &&
            (t['macro'] as num) <= kLastLeasePresetId)
          (t['macro'] as num).toInt(),
    };

// ── Harness ─────────────────────────────────────────────────────────────────

final _refProvider = Provider<Ref>((ref) => ref);

class _Rig {
  _Rig(this.container, this.manager, this.device);
  final ProviderContainer container;
  final CalendarEntryLeaseManager manager;
  final _Device device;
  Ref get ref => container.read(_refProvider);

  /// Sets the clock the manager reads (the "phone's" clock).
  set now(DateTime t) => manager.nowProvider = () => t;

  /// The lease rows the builder puts into every table write.
  List<Map<String, dynamic>> get builtRows =>
      ((manager.buildLeaseTimersPayloadForTest()['timers'] as Map)['ins']
              as List)
          .cast<Map<String, dynamic>>();
}

/// Fresh manager over [device], initialized at [now], holding [leases].
/// The verified push is the device's own 2xx + readback (confirmed at once):
/// no verify delay can run.
Future<_Rig> _rig(
  WidgetTester tester, {
  required DateTime now,
  List<CalendarEntryLease> leases = const [],
  List<Map<String, dynamic>>? table,
}) async {
  SharedPreferences.setMockInitialValues({});
  final device = _Device(table ?? [kSchedOn, kSchedOff]);
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(device),
    calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
    calendarLeaseLiveWritesEnabledProvider
        .overrideWith((_) => Stream.value(true)),
    calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 2),
    calendarLeaseEntriesProvider.overrideWithValue(const []),
    calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
    calendarLeaseSchedulesProvider.overrideWithValue(const []),
    calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
    calendarLeaseScheduleSyncTriggerProvider.overrideWith((_) => () async {}),
    servedGameDayEntryTestProvider
        .overrideWithValue((_, __) => ServedVerdict.notServed),
    controllerDefaultsHealerProvider.overrideWithValue(
        () async => ControllerHealReport()..reachable = false),
  ]);
  container.listen(calendarLeaseLiveWritesEnabledProvider, (_, __) {});
  final manager = container.read(calendarEntryLeaseManagerProvider);
  manager.nowProvider = () => now;
  manager.cfgPushFn = (repo, payload, ins) async {
    final ok = await repo.applyConfig(payload);
    return ok ? CfgPushOutcome.confirmed : CfgPushOutcome.notConfirmed;
  };
  await _settle(tester, manager.initialize());
  for (final l in leases) {
    manager.injectLeaseForTest(l);
  }
  return _Rig(container, manager, device);
}

/// Completes [f] in fake time. Every path here resolves through microtasks;
/// the pumps are a guard, so a hidden timer would advance fake time rather
/// than sleep.
Future<T> _settle<T>(WidgetTester tester, Future<T> f) async {
  T? value;
  Object? error;
  StackTrace? trace;
  var done = false;
  f.then<void>((v) {
    value = v;
    done = true;
  }, onError: (Object e, StackTrace s) {
    error = e;
    trace = s;
    done = true;
  });
  for (var i = 0; i < 600 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  expect(done, isTrue, reason: 'did not finish in fake time');
  return value as T;
}

/// The lease manager's 5-minute sweep timer must be gone before testWidgets
/// checks for pending timers.
void _finish(_Rig rig) => rig.container.dispose();

void main() {
  // ── The one rule ──────────────────────────────────────────────────────────

  group('CalendarEntryLease.isExpiredAt — the expiry rule', () {
    final lease = _tonight();
    test('before the end time: not expired (the night is still running)', () {
      expect(lease.isExpiredAt(kEnd.subtract(const Duration(minutes: 1))),
          isFalse);
      expect(lease.isExpiredAt(kEnd.subtract(const Duration(microseconds: 1))),
          isFalse);
    });
    test('at the end time: expired', () {
      expect(lease.isExpiredAt(kEnd), isTrue);
    });
    test('after the end time: expired', () {
      expect(lease.isExpiredAt(kEnd.add(const Duration(microseconds: 1))),
          isTrue);
      expect(lease.isExpiredAt(kEnd.add(const Duration(days: 1))), isTrue);
    });
  });

  // ── The row builder at the boundaries ────────────────────────────────────

  group('the row builder (every table write starts here)', () {
    testWidgets('a night in progress keeps its row (one minute before the end)',
        (tester) async {
      final rig = await _rig(tester,
          now: kEnd.subtract(const Duration(minutes: 1)), leases: [_tonight()]);
      expect(rig.builtRows, [
        {'en': 1, 'hour': 18, 'min': 0, 'macro': 30, 'dow': _tonight().dowMask}
      ]);
      _finish(rig);
    });

    testWidgets('the night not started yet keeps its row', (tester) async {
      final rig = await _rig(tester,
          now: DateTime.utc(2026, 2, 10, 12), leases: [_tonight()]);
      expect(_leaseMacros(rig.builtRows), {30});
      _finish(rig);
    });

    testWidgets('AT the end time the night is over: no row', (tester) async {
      final rig = await _rig(tester, now: kEnd, leases: [_tonight()]);
      expect(rig.builtRows, isEmpty);
      _finish(rig);
    });

    testWidgets('after the end time: no row', (tester) async {
      final rig = await _rig(tester,
          now: kEnd.add(const Duration(minutes: 1)), leases: [_tonight()]);
      expect(rig.builtRows, isEmpty);
      _finish(rig);
    });

    testWidgets('an expired night and a coming one: only the coming one',
        (tester) async {
      final rig = await _rig(tester,
          now: kEnd.add(const Duration(hours: 1)),
          leases: [_tonight(), _nextWeek()]);
      expect(_leaseMacros(rig.builtRows), {31});
      _finish(rig);
    });
  });

  group('the builder and the sweep can never disagree', () {
    final offsets = <String, Duration>{
      'a day before': const Duration(days: -1),
      'a minute before': const Duration(minutes: -1),
      'one microsecond before': const Duration(microseconds: -1),
      'at the end time': Duration.zero,
      'one microsecond after': const Duration(microseconds: 1),
      'a minute after': const Duration(minutes: 1),
      'a day after': const Duration(days: 1),
    };
    for (final o in offsets.entries) {
      testWidgets('${o.key}: the row goes out exactly when the sweep keeps '
          'the record', (tester) async {
        final lease = _tonight();
        final rig = await _rig(tester,
            now: kEnd.add(o.value),
            leases: [lease],
            table: [kSchedOn, kSchedOff, _rowOf(lease)]);
        final rowSent = _leaseMacros(rig.builtRows).contains(lease.presetId);

        await _settle(tester, rig.manager.sweepExpiredLeases());
        final recordKept = rig.manager.leaseFor(lease.dateKey) != null;

        expect(rowSent, recordKept,
            reason: 'builder sent the row: $rowSent; sweep kept the record: '
                '$recordKept');
        expect(rowSent, o.value.isNegative,
            reason: 'live strictly before the end time, over from it on');
        _finish(rig);
      });
    }
  });

  // ── Each write path that used to re-send ─────────────────────────────────

  group('the schedule sync stops re-sending', () {
    testWidgets(
        'the ledger syncAll merges (calendarLeaseActiveTimersProvider) leaves '
        'an expired lease out', (tester) async {
      final rig = await _rig(tester,
          now: kEnd.add(const Duration(hours: 1)),
          leases: [_tonight(), _nextWeek()]);
      final state = rig.container.read(calendarLeaseActiveTimersProvider);
      expect(state, isA<LeaseLedgerReady>());
      expect(_leaseMacros(state.timers), {31});
      _finish(rig);
    });

    testWidgets('only expired leases → the ledger is EMPTY (nothing to merge)',
        (tester) async {
      final rig = await _rig(tester,
          now: kEnd.add(const Duration(hours: 1)), leases: [_tonight()]);
      expect(rig.manager.activeLeaseTimers(), isA<LeaseLedgerEmpty>());
      _finish(rig);
    });

    testWidgets(
        "syncAll's table carries the coming lease's row and not the expired "
        "one, whose record the sweep has not cleared yet", (tester) async {
      final expired = _tonight();
      final coming = _nextWeek();
      final rig = await _rig(tester,
          now: kEnd.add(const Duration(hours: 1)),
          leases: [expired, coming],
          table: [kSchedOn, kSchedOff, _rowOf(expired), _rowOf(coming)]);
      const schedule = ScheduleItem(
        id: 's1',
        timeLabel: '7:00 PM',
        repeatDays: ['Mon'],
        actionLabel: 'Pattern: s1',
        enabled: true,
        presetId: 10,
        wledPayload: {
          'on': true,
          'seg': [
            {
              'fx': 0,
              'col': [
                [10, 20, 30, 0]
              ]
            }
          ]
        },
      );

      final result = await _settle(tester,
          const ScheduleSyncService().syncAll(rig.ref, const [schedule]));

      expect(result.success, isTrue, reason: '${result.error}');
      expect(rig.device.writes, isNotEmpty);
      final macros = _leaseMacros(rig.device.writes.last);
      expect(macros, contains(coming.presetId));
      expect(macros, isNot(contains(expired.presetId)),
          reason: 'an expired lease row must not be armed again');
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull,
          reason: 'the record is the sweep\'s to clear, not the sync\'s');
      _finish(rig);
    });
  });

  group('the lease writes (composeLeaseWrite) stop re-sending', () {
    testWidgets(
        'releasing one night does not put another, expired night\'s row back',
        (tester) async {
      final expired = _tonight();
      final coming = _nextWeek();
      final rig = await _rig(tester,
          now: kEnd.add(const Duration(hours: 1)),
          leases: [expired, coming],
          table: [kSchedOn, kSchedOff, _rowOf(expired), _rowOf(coming)]);

      await _settle(tester, rig.manager.handleEntryDeleted(coming.dateKey));

      expect(rig.device.writes, hasLength(1));
      final ins = rig.device.writes.single;
      expect(_leaseMacros(ins), isEmpty,
          reason: 'neither the released row nor the expired one');
      expect(rig.device.table, containsAll([kSchedOn, kSchedOff]),
          reason: 'every row the writer does not own is kept');
      expect(rig.manager.leaseFor(coming.dateKey), isNull);
      _finish(rig);
    });
  });

  // ── Wrong clock ──────────────────────────────────────────────────────────

  group('a wrong clock', () {
    testWidgets(
        'the rows follow the clock the sweep reads (the phone\'s), not the '
        'wall clock: ended in 2001 by the wall clock, still running by the '
        'phone\'s → kept', (tester) async {
      final day = DateTime.utc(2001, 1, 1);
      final lease = _lease(day: day, end: DateTime.utc(2001, 1, 1, 23));
      final rig = await _rig(tester,
          now: DateTime.utc(2001, 1, 1, 22), leases: [lease]);
      expect(_leaseMacros(rig.builtRows), {30});
      _finish(rig);
    });

    testWidgets(
        'and the other way: still to come by the wall clock (2099), over by '
        'the phone\'s (2100) → dropped, and the sweep agrees', (tester) async {
      final day = DateTime.utc(2099, 6, 1);
      final lease = _lease(day: day, end: DateTime.utc(2099, 6, 1, 23));
      final rig = await _rig(tester,
          now: DateTime.utc(2100, 1, 1),
          leases: [lease],
          table: [kSchedOn, kSchedOff, _rowOf(lease)]);
      expect(rig.builtRows, isEmpty);
      await _settle(tester, rig.manager.sweepExpiredLeases());
      expect(rig.manager.leaseFor(lease.dateKey), isNull);
      _finish(rig);
    });

    testWidgets(
        'a clock that jumps back before the end restores the row: the rule is '
        'a pure function of the clock now, nothing is remembered',
        (tester) async {
      final rig = await _rig(tester,
          now: kEnd.add(const Duration(minutes: 5)), leases: [_tonight()]);
      expect(rig.builtRows, isEmpty);
      rig.now = kEnd.subtract(const Duration(minutes: 5));
      expect(_leaseMacros(rig.builtRows), {30});
      _finish(rig);
    });
  });
}
