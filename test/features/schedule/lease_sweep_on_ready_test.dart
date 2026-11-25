// Build 133, fix 3 — the expiry sweep also runs when the controller becomes
// ready.
//
// The sweep used to run only at initialize() and every 5 minutes, and it
// skips (keeping the record) when the live-writes flag has not loaded, there
// is no repository, the phone is off the LAN, the timer table is unreadable
// or the write is not confirmed. An app session that is on the venue Wi-Fi for
// 10–27 seconds therefore never got a sweep that could land: initialize()
// came too early (flag still loading) and the 5-minute tick never came.
//
// Now the moment the repository can write /json/cfg on the LAN with the flag
// loaded is a "ready moment", and the sweep runs then too:
//   * after the controller has stayed ready for the settle window (2 s), so a
//     flapping connection does not start one per flap;
//   * at most once per spacing window (30 s); a ready moment inside it runs
//     one sweep when it ends;
//   * after initialize() and any sweep already running, so nothing is
//     written twice;
//   * its writes go through the one timer-table lock the schedule sync now
//     takes too, so a sweep never reads the table, lets a sync write it, and
//     writes the old rows back;
//   * every existing skip rule holds, and a write that is not confirmed keeps
//     the record for the next ready moment.
//
// Fake time (testWidgets) and an injected clock (nowProvider) throughout.

import 'dart:async';
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/served_game_day.dart'
    show ServedVerdict, servedGameDayEntryTestProvider;
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/timer_table_write_lock.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ControllerClockInfo;
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerDefaultsHealerProvider, ControllerHealReport;
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── A LAN controller that holds a timer table ───────────────────────────────

Map<String, dynamic> _deep(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

class _Device extends WledService {
  _Device(List<Map<String, dynamic>> table)
      : table = [for (final t in table) _deep(t)],
        super('http://mock');

  List<Map<String, dynamic>> table;
  final List<List<Map<String, dynamic>>> writes = [];

  /// False: the timer table cannot be read (`/json/cfg` GET fails).
  bool readable = true;

  /// When set, a preset save waits for it: a schedule sync caught mid-way.
  Completer<void>? saveGate;

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async =>
      readable ? [for (final t in table) _deep(t)] : null;

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

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    final gate = saveGate;
    if (gate != null) await gate.future;
    return true;
  }

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => const {};
  @override
  Future<PresetsRead> readPresets() async => const PresetsRead.deviceEmpty();
  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => ControllerClockInfo(
        latitude: 40.0,
        longitude: -100.0,
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
  Future<bool> deletePreset(int presetId) async => true;
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;
}

// ── Fixtures (synthetic, UTC) ───────────────────────────────────────────────

/// The phone's clock: a Wednesday afternoon.
final DateTime kNow = DateTime.utc(2026, 2, 11, 15, 0);

Map<String, dynamic> _row(int hour, int min, int macro, int dow) => {
      'en': 1,
      'hour': hour,
      'min': min,
      'macro': macro,
      'dow': dow,
      'start': {'mon': 1, 'day': 1},
      'end': {'mon': 12, 'day': 31},
    };

/// A schedule's own rows: ON 17:00 (macro 10), OFF 07:00 (macro 2), daily.
final kSchedOn = _row(17, 0, 10, 127);
final kSchedOff = _row(7, 0, 2, 127);

String _key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Last night's lease (ended 23:00 yesterday) — its record outlived it.
CalendarEntryLease _expired() {
  final y = DateTime.utc(2026, 2, 10);
  return CalendarEntryLease(
    dateKey: _key(y),
    slotIndex: 2,
    presetId: 30,
    leasedAt: y,
    expiresAt: DateTime.utc(2026, 2, 10, 23),
    wledPayload: const {'on': true, 'bri': 200},
    patternName: 'Last night',
    wledHour: 18,
    wledMin: 0,
    dowMask: wledDowMaskForWeekday(y.weekday),
  );
}

/// Tomorrow night's lease (still to come).
CalendarEntryLease _coming() {
  final t = DateTime.utc(2026, 2, 12);
  return CalendarEntryLease(
    dateKey: _key(t),
    slotIndex: 3,
    presetId: 31,
    leasedAt: kNow,
    expiresAt: DateTime.utc(2026, 2, 12, 23),
    wledPayload: const {'on': true, 'bri': 200},
    patternName: 'Tomorrow',
    wledHour: 18,
    wledMin: 0,
    dowMask: wledDowMaskForWeekday(t.weekday),
  );
}

Map<String, dynamic> _rowOf(CalendarEntryLease l) =>
    _row(l.wledHour, l.wledMin, l.presetId, l.dowMask);

Set<int> _macros(Iterable<Map<String, dynamic>> ins) =>
    {for (final t in ins) (t['macro'] as num).toInt()};

// ── Harness ─────────────────────────────────────────────────────────────────

final _repoSwitch = StateProvider<WledRepository?>((_) => null);
final _refProvider = Provider<Ref>((ref) => ref);

class _Rig {
  _Rig(this.container, this.manager, this.device, this.flag, this.fs);
  final ProviderContainer container;
  final CalendarEntryLeaseManager manager;
  final _Device device;
  final StreamController<bool> flag;
  final FakeFirebaseFirestore fs;

  /// The phone joins the venue Wi-Fi.
  void lan() => container.read(_repoSwitch.notifier).state = device;

  /// The phone is away: the bridge relay (cannot write /json/cfg).
  void bridge() => container.read(_repoSwitch.notifier).state =
      CloudRelayRepository(
        userId: 'u1',
        controllerId: 'c1',
        controllerIp: '192.0.2.10',
        webhookUrl: '',
        firestore: fs,
        commandTimeout: const Duration(milliseconds: 300),
      );

  /// No controller at all.
  void none() => container.read(_repoSwitch.notifier).state = null;

  /// The live-writes flag document arrives.
  void flagLoads([bool value = true]) => flag.add(value);

  /// The verified push: confirmed, or not.
  set confirms(bool yes) => manager.cfgPushFn = (repo, payload, ins) async {
        if (!yes) return CfgPushOutcome.notConfirmed;
        await repo.applyConfig(payload);
        return CfgPushOutcome.confirmed;
      };

  Ref get ref => container.read(_refProvider);
}

/// A manager the way the app starts one: no controller yet, flag still
/// loading. [initialize] has run (its own sweep found nothing to do or could
/// not write); [leases] are the records that outlived their nights.
Future<_Rig> _rig(
  WidgetTester tester, {
  List<CalendarEntryLease> leases = const [],
  List<Map<String, dynamic>>? table,
}) async {
  SharedPreferences.setMockInitialValues({});
  final fs = FakeFirebaseFirestore();
  final flag = StreamController<bool>();
  final device = _Device(table ?? [kSchedOn, kSchedOff, _rowOf(_expired())]);
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => ref.watch(_repoSwitch)),
    calendarLeaseLiveWritesEnabledProvider.overrideWith((_) => flag.stream),
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
  final manager = container.read(calendarEntryLeaseManagerProvider);
  manager.nowProvider = () => kNow;
  final rig = _Rig(container, manager, device, flag, fs)..confirms = true;
  await _settle(tester, manager.initialize());
  for (final l in leases) {
    manager.injectLeaseForTest(l);
  }
  return rig;
}

/// Completes [f] in fake time.
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

/// Lets [d] of fake time pass, in small steps so every timer and microtask
/// along the way runs.
Future<void> _wait(WidgetTester tester, Duration d) async {
  final steps = d.inMilliseconds ~/ 100;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Every timer (settle, spacing, the 5-minute sweep, the poller) must be gone
/// before testWidgets checks for pending timers.
Future<void> _finish(WidgetTester tester, _Rig rig) async {
  // Riverpod schedules provider refreshes on a zero-length timer; a bare
  // pump() does not move fake time, so let 1 ms pass on each side.
  await tester.pump(const Duration(milliseconds: 1));
  rig.container.dispose();
  // Not awaited: once the provider's subscription is cancelled, close()'s
  // future need not complete.
  unawaited(rig.flag.close());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('a short session on the venue Wi-Fi', () {
    testWidgets(
        'a 10-second session runs the sweep: the expired row and record go, '
        'every other row stays', (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);

      // The app opens on the venue Wi-Fi; the flag document arrives.
      rig.lan();
      rig.flagLoads();
      await _wait(tester, const Duration(seconds: 10));
      rig.none(); // the session ends

      expect(rig.device.writes, hasLength(1), reason: 'one zero-write');
      expect(_macros(rig.device.table), isNot(contains(expired.presetId)));
      expect(rig.device.table, containsAll([kSchedOn, kSchedOff]));
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      expect(rig.manager.readySweepRunsForTest, 1);
      await _finish(tester, rig);
    });

    testWidgets('nothing expired → the ready moment writes nothing',
        (tester) async {
      final rig = await _rig(tester,
          leases: [_coming()],
          table: [kSchedOn, kSchedOff, _rowOf(_coming())]);
      rig.lan();
      rig.flagLoads();
      await _wait(tester, const Duration(seconds: 10));

      expect(rig.manager.readySweepRunsForTest, 1, reason: 'the sweep ran');
      expect(rig.device.writes, isEmpty, reason: 'and wrote nothing');
      expect(rig.manager.leaseFor(_coming().dateKey), isNotNull);
      await _finish(tester, rig);
    });

    testWidgets(
        'a flag that loads as OFF is not a ready moment (writes are off by '
        'design); the flip to ON is', (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);
      rig.lan();
      rig.flagLoads(false);
      await _wait(tester, const Duration(seconds: 5));
      expect(rig.manager.readySweepRunsForTest, 0);
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull);

      rig.flagLoads(true);
      await _wait(tester, const Duration(seconds: 5));
      expect(rig.manager.readySweepRunsForTest, 1);
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      await _finish(tester, rig);
    });
  });

  group('each skip keeps the record and retries at the next ready moment', () {
    testWidgets('the live-writes flag has not loaded', (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);
      rig.lan();
      // The 5-minute (or initialize) sweep while the flag is still loading.
      await _settle(tester, rig.manager.sweepExpiredLeases());
      expect(rig.device.writes, isEmpty);
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull);

      rig.flagLoads(); // ready
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      expect(rig.device.writes, hasLength(1));
      await _finish(tester, rig);
    });

    testWidgets('no repository', (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);
      rig.flagLoads();
      await _wait(tester, const Duration(seconds: 3));
      await _settle(tester, rig.manager.sweepExpiredLeases());
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull);

      rig.lan(); // ready
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      await _finish(tester, rig);
    });

    testWidgets('off the LAN (bridge): nothing written, nothing relayed',
        (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);
      rig.bridge();
      rig.flagLoads();
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.readySweepRunsForTest, 0,
          reason: 'the relay cannot write /json/cfg: not a ready moment');
      await _settle(tester, rig.manager.sweepExpiredLeases());
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull);
      final commands = await _settle(tester,
          rig.fs.collection('users').doc('u1').collection('commands').get());
      expect(commands.docs, isEmpty);

      rig.lan(); // ready
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      await _finish(tester, rig);
    });

    testWidgets('the timer table is unreadable', (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);
      rig.device.readable = false;
      rig.lan();
      rig.flagLoads();
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.readySweepRunsForTest, 1);
      expect(rig.device.writes, isEmpty,
          reason: 'an unknown table is never written over');
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull);

      // The session ends; the next one, the table reads.
      rig.none();
      await _wait(tester, const Duration(seconds: 40));
      rig.device.readable = true;
      rig.lan();
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.readySweepRunsForTest, 2);
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      await _finish(tester, rig);
    });

    testWidgets('the write is not confirmed', (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);
      rig.confirms = false;
      rig.lan();
      rig.flagLoads();
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.readySweepRunsForTest, 1);
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull,
          reason: 'not confirmed: the record stays');

      rig.none();
      await _wait(tester, const Duration(seconds: 40));
      rig.confirms = true;
      rig.lan();
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.readySweepRunsForTest, 2);
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      await _finish(tester, rig);
    });
  });

  group('debounce', () {
    testWidgets(
        'a connection that flaps faster than the settle window starts nothing '
        'until it holds', (tester) async {
      final rig = await _rig(tester, leases: [_expired()]);
      rig.flagLoads();
      for (var i = 0; i < 8; i++) {
        rig.lan();
        await _wait(tester, const Duration(seconds: 1));
        rig.none();
        await _wait(tester, const Duration(seconds: 1));
      }
      expect(rig.manager.readySweepRunsForTest, 0);
      rig.lan();
      await _wait(tester, const Duration(seconds: 3));
      expect(rig.manager.readySweepRunsForTest, 1);
      expect(rig.device.writes, hasLength(1));
      await _finish(tester, rig);
    });

    testWidgets(
        'a connection that flaps slower than the settle window does not '
        'repeat the sweep inside the spacing window', (tester) async {
      final expired = _expired();
      final rig = await _rig(tester, leases: [expired]);
      // Never confirmed, so every sweep would try the write again.
      rig.confirms = false;
      var attempts = 0;
      final unconfirmed = rig.manager.cfgPushFn;
      rig.manager.cfgPushFn = (repo, payload, ins) {
        attempts++;
        return unconfirmed(repo, payload, ins);
      };
      rig.flagLoads();
      // Ready for 3 s, away for 1 s, five times: 20 s in all.
      for (var i = 0; i < 5; i++) {
        rig.lan();
        await _wait(tester, const Duration(seconds: 3));
        rig.none();
        await _wait(tester, const Duration(seconds: 1));
      }
      expect(rig.manager.readySweepRunsForTest, 1);
      expect(attempts, 1, reason: 'one write attempt in the spacing window');

      // A ready moment that arrived inside the window runs once it ends.
      rig.lan();
      await _wait(tester, const Duration(seconds: 15));
      expect(rig.manager.readySweepRunsForTest, 2);
      expect(attempts, 2);
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull);
      await _finish(tester, rig);
    });
  });

  group('serialized with the schedule sync through the timer-table lock', () {
    testWidgets(
        'a sweep that comes due while a schedule sync is writing waits for '
        'it, and keeps the rows the sync armed', (tester) async {
      final expired = _expired();
      // The schedule's rows are missing from the controller: the sync is
      // about to put them back.
      final rig = await _rig(tester,
          leases: [expired], table: [_rowOf(expired)]);
      rig.lan();
      rig.flagLoads();
      // A sync starts before the ready moment settles and stops mid-way, in
      // its preset save.
      rig.device.saveGate = Completer<void>();
      const schedule = ScheduleItem(
        id: 's1',
        timeLabel: '5:00 PM',
        offTimeLabel: '7:00 AM',
        repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
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
      await tester.pump();
      ScheduleSyncResult? syncResult;
      const ScheduleSyncService()
          .syncAll(rig.ref, const [schedule]).then((r) => syncResult = r);
      await _wait(tester, const Duration(seconds: 5));

      expect(rig.manager.readySweepRunsForTest, 1, reason: 'the sweep is due');
      expect(rig.device.writes, isEmpty,
          reason: 'it may not touch the table while the sync holds it');
      expect(rig.manager.leaseFor(expired.dateKey), isNotNull);

      rig.device.saveGate!.complete();
      await _wait(tester, const Duration(seconds: 5));

      expect(syncResult?.success, isTrue, reason: '${syncResult?.error}');
      expect(rig.device.writes, hasLength(2), reason: 'the sync, then the sweep');
      expect(_macros(rig.device.writes.first), contains(10),
          reason: 'the sync wrote first');
      final table = rig.device.table;
      expect(_macros(table), contains(10),
          reason: "the sweep kept the sync's ON row");
      expect(_macros(table), isNot(contains(expired.presetId)));
      expect(rig.manager.leaseFor(expired.dateKey), isNull);
      await _finish(tester, rig);
    });

    testWidgets('the lease manager and the schedule sync share one lock',
        (tester) async {
      final rig = await _rig(tester);
      final lock = rig.container.read(timerTableWriteLockProvider);
      final held = Completer<void>();
      unawaited(lock.synchronized(() => held.future));
      final expired = _expired();
      rig.manager.injectLeaseForTest(expired);
      rig.lan();
      rig.flagLoads();
      await _wait(tester, const Duration(seconds: 5));
      expect(rig.device.writes, isEmpty, reason: 'waiting on the lock');
      held.complete();
      await _wait(tester, const Duration(seconds: 1));
      expect(rig.device.writes, hasLength(1));
      await _finish(tester, rig);
    });
  });
}
