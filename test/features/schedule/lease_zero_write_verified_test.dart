// Build 127 (iii) — a lease's registry record goes ONLY once the zero-write
// that clears its row is confirmed by the verify read.
//
// Before: the expired-lease sweep removed the record first and then called a
// zero-write that returned silently off the LAN, with no controller, with
// live writes off, or with the schedules not loaded — so the row stayed
// armed on the device with nothing in the app remembering it, and the "next
// sweep retries" comments were wrong because the record was already gone.
// Delete (release) and Game Day retraction had the same shape.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart'
    show CfgPushOutcome;
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A LAN controller that holds a timer table (readback shape).
class _Device extends WledService {
  _Device(List<Map<String, dynamic>> table)
      : table = [for (final t in table) Map<String, dynamic>.from(t)],
        super('http://mock');

  List<Map<String, dynamic>> table;
  bool readable = true;
  final List<List<Map<String, dynamic>>> writes = [];

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async => readable
      ? [for (final t in table) Map<String, dynamic>.from(t)]
      : null;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    final ins = (cfg['timers'] as Map?)?['ins'];
    if (ins is List) {
      final sent = ins.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      writes.add(sent);
      table = [
        for (final t in sent)
          if (!((t['macro'] ?? 0) == 0 &&
              (t['hour'] ?? 0) == 0 &&
              (t['min'] ?? 0) == 0))
            Map<String, dynamic>.from(t),
      ];
    }
    return true;
  }
}

final _repoSwitch = StateProvider<WledRepository?>((_) => null);

final DateTime kNow = DateTime(2026, 11, 12, 12, 0); // Thursday noon

Map<String, dynamic> _row(int hour, int min, int macro, int dow) => {
      'en': 1,
      'hour': hour,
      'min': min,
      'macro': macro,
      'dow': dow,
      'start': {'mon': 1, 'day': 1},
      'end': {'mon': 12, 'day': 31},
    };

/// Ellie's rows: a 17:00 ON (macro 10) and a 07:00 OFF (macro 2).
final kSchedOn = _row(17, 0, 10, 127);
final kSchedOff = _row(7, 0, 2, 127);

String _key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A lease that expired last night (21:30 yesterday).
CalendarEntryLease _expired({int macro = 30, int daysAgo = 1}) {
  final y = kNow.subtract(Duration(days: daysAgo));
  return CalendarEntryLease(
    dateKey: _key(y),
    slotIndex: 2,
    presetId: macro,
    leasedAt: y.subtract(const Duration(hours: 6)),
    expiresAt: DateTime(y.year, y.month, y.day, 21, 30),
    wledPayload: const {'on': true, 'bri': 200},
    patternName: 'Harvest Moon',
    wledHour: 20,
    wledMin: 30,
    dowMask: wledDowMaskForWeekday(y.weekday),
  );
}

/// A lease still to come (tomorrow night).
CalendarEntryLease _upcoming({int macro = 31}) {
  final t = kNow.add(const Duration(days: 1));
  return CalendarEntryLease(
    dateKey: _key(t),
    slotIndex: 3,
    presetId: macro,
    leasedAt: kNow,
    expiresAt: DateTime(t.year, t.month, t.day, 22, 0),
    wledPayload: const {'on': true, 'bri': 200},
    patternName: 'Game Day',
    wledHour: 18,
    wledMin: 0,
    dowMask: wledDowMaskForWeekday(t.weekday),
  );
}

Map<String, dynamic> _leaseRowOf(CalendarEntryLease l) =>
    _row(l.wledHour, l.wledMin, l.presetId, l.dowMask);

({ProviderContainer c, CalendarEntryLeaseManager m, FakeFirebaseFirestore fs})
    _harness({bool liveWrites = true}) {
  final fs = FakeFirebaseFirestore();
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => ref.watch(_repoSwitch)),
    calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(liveWrites),
    calendarLeaseLiveWritesEnabledProvider
        .overrideWith((_) => Stream.value(liveWrites)),
    calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 2),
    calendarLeaseEntriesProvider.overrideWithValue(const []),
    calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
    calendarLeaseSchedulesProvider.overrideWithValue(const []),
    calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
    calendarLeaseScheduleSyncTriggerProvider.overrideWith((_) => () async {}),
  ]);
  addTearDown(c.dispose);
  final m = c.read(calendarEntryLeaseManagerProvider)..nowProvider = () => kNow;
  return (c: c, m: m, fs: fs);
}

CloudRelayRepository _bridge(FakeFirebaseFirestore fs) => CloudRelayRepository(
      userId: 'u1',
      controllerId: 'c1',
      controllerIp: '192.0.2.10',
      webhookUrl: '',
      firestore: fs,
      commandTimeout: const Duration(milliseconds: 300),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the expired-lease sweep', () {
    test('confirmed zero-write → the row goes and so does the record; every '
        'other row is kept', () async {
      final expired = _expired();
      final device = _Device([kSchedOn, kSchedOff, _leaseRowOf(expired)]);
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.initialize();
      h.m.injectLeaseForTest(expired);

      await h.m.sweepExpiredLeases();

      expect(h.m.leaseFor(expired.dateKey), isNull);
      expect(device.writes, hasLength(1));
      expect(device.table.where((t) => t['macro'] == expired.presetId), isEmpty);
      expect(device.table, containsAll([kSchedOn, kSchedOff]));
    });

    test('UNCONFIRMED zero-write → the record stays for the next sweep', () async {
      final expired = _expired();
      final device = _Device([kSchedOn, kSchedOff, _leaseRowOf(expired)]);
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.initialize();
      h.m.injectLeaseForTest(expired);
      h.m.cfgPushFn = (_, __, ___) async => CfgPushOutcome.notConfirmed;

      await h.m.sweepExpiredLeases();
      expect(h.m.leaseFor(expired.dateKey), isNotNull,
          reason: 'not confirmed: the record stays');

      // The controller answers next time: the sweep clears both.
      h.m.cfgPushFn = (repo, payload, ins) async {
        await repo.applyConfig(payload);
        return CfgPushOutcome.confirmed;
      };
      await h.m.sweepExpiredLeases();
      expect(h.m.leaseFor(expired.dateKey), isNull);
      expect(device.table.where((t) => t['macro'] == expired.presetId), isEmpty);
    });

    test('off the LAN (bridge) → nothing written, the record stays; on the '
        'LAN the next sweep clears it', () async {
      final expired = _expired();
      final device = _Device([kSchedOn, kSchedOff, _leaseRowOf(expired)]);
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = _bridge(h.fs);
      await h.m.initialize();
      h.m.injectLeaseForTest(expired);

      await h.m.sweepExpiredLeases();
      expect(h.m.leaseFor(expired.dateKey), isNotNull, reason: 'off-LAN');
      final commands = await h.fs
          .collection('users')
          .doc('u1')
          .collection('commands')
          .get();
      expect(commands.docs, isEmpty, reason: 'no relay command either');

      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.sweepExpiredLeases();
      expect(h.m.leaseFor(expired.dateKey), isNull, reason: 'cleared on LAN');
      expect(device.table, containsAll([kSchedOn, kSchedOff]));
    });

    test('no controller → the record stays', () async {
      final expired = _expired();
      final h = _harness();
      await h.m.initialize();
      h.m.injectLeaseForTest(expired);
      await h.m.sweepExpiredLeases();
      expect(h.m.leaseFor(expired.dateKey), isNotNull);
    });

    test("the controller's table unreadable → nothing written, the record "
        'stays', () async {
      final expired = _expired();
      final device = _Device([kSchedOn, _leaseRowOf(expired)])..readable = false;
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.initialize();
      h.m.injectLeaseForTest(expired);
      await h.m.sweepExpiredLeases();
      expect(h.m.leaseFor(expired.dateKey), isNotNull);
      expect(device.writes, isEmpty, reason: 'an unknown table is never '
          'written over');
    });

    test('live writes OFF → a silent skip leaves the record', () async {
      final expired = _expired();
      final device = _Device([kSchedOn, _leaseRowOf(expired)]);
      final h = _harness(liveWrites: false);
      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.initialize();
      h.m.injectLeaseForTest(expired);
      await h.m.sweepExpiredLeases();
      expect(h.m.leaseFor(expired.dateKey), isNotNull);
      expect(device.writes, isEmpty);
    });

    test('several expired nights: ONE merged write; an upcoming lease keeps '
        'its row', () async {
      final a = _expired(macro: 30, daysAgo: 1);
      final b = _expired(macro: 29, daysAgo: 2);
      final up = _upcoming();
      final device = _Device([
        kSchedOn,
        kSchedOff,
        _leaseRowOf(a),
        _leaseRowOf(b),
        _leaseRowOf(up),
      ]);
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.initialize();
      h.m.injectLeaseForTest(a);
      h.m.injectLeaseForTest(b);
      h.m.injectLeaseForTest(up);

      await h.m.sweepExpiredLeases();

      expect(device.writes, hasLength(1), reason: 'one merged zero-write');
      expect(h.m.leaseFor(a.dateKey), isNull);
      expect(h.m.leaseFor(b.dateKey), isNull);
      expect(h.m.leaseFor(up.dateKey), isNotNull);
      final macros = device.table.map((t) => t['macro']).toList();
      expect(macros, isNot(contains(30)));
      expect(macros, isNot(contains(29)));
      expect(macros, contains(up.presetId));
      expect(device.table, containsAll([kSchedOn, kSchedOff]));
    });
  });

  group('deleting an entry (release)', () {
    test('confirmed → row and record go, other rows kept', () async {
      final up = _upcoming();
      final device = _Device([kSchedOn, kSchedOff, _leaseRowOf(up)]);
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.initialize();
      h.m.injectLeaseForTest(up);

      await h.m.handleEntryDeleted(up.dateKey);

      expect(h.m.leaseFor(up.dateKey), isNull);
      expect(device.table.where((t) => t['macro'] == up.presetId), isEmpty);
      expect(device.table, containsAll([kSchedOn, kSchedOff]));
    });

    test('unconfirmed → the record stays (the row is still armed)', () async {
      final up = _upcoming();
      final device = _Device([kSchedOn, _leaseRowOf(up)]);
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = device;
      await h.m.initialize();
      h.m.injectLeaseForTest(up);
      h.m.cfgPushFn = (_, __, ___) async => CfgPushOutcome.notConfirmed;

      await h.m.handleEntryDeleted(up.dateKey);

      expect(h.m.leaseFor(up.dateKey), isNotNull);
    });

    test('off the LAN → nothing written, the record stays', () async {
      final up = _upcoming();
      final h = _harness();
      h.c.read(_repoSwitch.notifier).state = _bridge(h.fs);
      await h.m.initialize();
      h.m.injectLeaseForTest(up);

      await h.m.handleEntryDeleted(up.dateKey);

      expect(h.m.leaseFor(up.dateKey), isNotNull);
    });
  });
}
