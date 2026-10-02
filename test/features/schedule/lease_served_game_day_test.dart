// +114 (plan §3.2) — the phone lease stands down for a server-run Game Day.
//
// What stops (served teams only): the lease entry point — every path (calendar
// write, sweep promotion, eviction, heir re-derivation) goes through it — so a
// served night gets NO preset save and NO cfg write. An already-armed lease for
// a night that becomes served is retracted on the next LAN sweep with ONE
// merged cfg write (presets stay; no pdel). Off the LAN nothing changes until
// the phone is home. Unserved nights are leased exactly as before.
//
// FIXED CLOCK: every entry is anchored to a Saturday noon via the manager's
// nowProvider, so these cannot fall into the #64 pre-midnight window.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/served_game_day.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _now = DateTime(2026, 10, 10, 12, 0); // Saturday noon

final _repoSwitch = StateProvider<WledRepository?>((_) => null);
final _served = StateProvider<ServedVerdict>((_) => ServedVerdict.notServed);
final _entries = StateProvider<List<CalendarEntry>>((_) => const []);

/// Sunday's game, inside the 48 h window from [_now].
CalendarEntry _gameDay({
  String date = '2026-10-11',
  CalendarEntryType type = CalendarEntryType.autopilot,
  String? tag = CalendarEntrySourceTag.gameDay,
}) =>
    CalendarEntry(
      dateKey: date,
      patternName: 'Team Night',
      color: const Color(0xFFE31837),
      onTime: '14:55',
      offTime: '19:55',
      brightness: 78,
      type: type,
      autopilot: true,
      note: 'Home Team vs Away Team — Game Day autopilot',
      sourceTag: tag,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({ProviderContainer c, CalendarEntryLeaseManager m, FakeFirebaseFirestore fs})
      harness({List<CalendarEntry> entries = const []}) {
    final fs = FakeFirebaseFirestore();
    final c = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => ref.watch(_repoSwitch)),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(true)),
      calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
      calendarLeaseEntriesProvider.overrideWith((ref) => ref.watch(_entries)),
      calendarLeaseSchedulesProvider.overrideWithValue(const []),
      calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider.overrideWith((_) => () async {}),
      // The served decision itself is pinned in served_game_day_test.dart;
      // here it is a switch: served iff tagged game_day and the switch is on.
      servedGameDayEntryTestProvider.overrideWith((ref) {
        final v = ref.watch(_served);
        return (e, _) => e.sourceTag == CalendarEntrySourceTag.gameDay
            ? v
            : ServedVerdict.notServed;
      }),
    ]);
    addTearDown(c.dispose);
    c.read(_entries.notifier).state = entries;
    final m = c.read(calendarEntryLeaseManagerProvider)..nowProvider = () => _now;
    return (c: c, m: m, fs: fs);
  }

  WledService lan(ProviderContainer c) {
    final s = WledService('http://mock');
    c.read(_repoSwitch.notifier).state = s;
    return s;
  }

  CloudRelayRepository bridge(ProviderContainer c, FakeFirebaseFirestore fs) {
    final r = CloudRelayRepository(
      userId: 'u1',
      controllerId: 'c1',
      controllerIp: '192.0.2.10',
      webhookUrl: '',
      firestore: fs,
      commandTimeout: const Duration(milliseconds: 300),
    );
    c.read(_repoSwitch.notifier).state = r;
    return r;
  }

  Future<int> commands(FakeFirebaseFirestore fs) async =>
      (await fs.collection('users').doc('u1').collection('commands').get())
          .docs
          .length;

  List<int> leaseMacros(WledService s) {
    final ins = ((s.lastSimulatedConfigPayload?['timers'] as Map?)?['ins']
            as List?) ??
        const [];
    return [
      for (final t in ins.cast<Map>())
        if ((t['en'] as num?) == 1 &&
            (t['macro'] as num) >= kFirstLeasePresetId &&
            (t['macro'] as num) <= kLastLeasePresetId)
          (t['macro'] as num).toInt(),
    ];
  }

  test('a SERVED Game Day night: no preset save, no cfg write, not registered',
      () async {
    final h = harness();
    final svc = lan(h.c);
    h.c.read(_served.notifier).state = ServedVerdict.served;
    await h.m.initialize();

    final r = await h.m.handleEntryCreated(_gameDay());

    expect(r.outcome, LeaseOutcome.servedByServer);
    expect(h.m.activeLeases, isEmpty);
    expect(svc.lastSimulatedPresetSave, isNull);
    expect(svc.lastSimulatedConfigPayload, isNull);
  });

  test('the identical night UNSERVED is leased exactly as before', () async {
    final h = harness();
    final svc = lan(h.c);
    await h.m.initialize();

    final r = await h.m.handleEntryCreated(_gameDay());

    expect(r.outcome, LeaseOutcome.leased);
    expect(h.m.activeLeases.single.dateKey, '2026-10-11');
    expect(svc.lastSimulatedPresetSave, isNotNull);
    expect(leaseMacros(svc), [h.m.activeLeases.single.presetId]);
  });

  test('a plain user night is never stood down, even with the account served',
      () async {
    final h = harness();
    lan(h.c);
    h.c.read(_served.notifier).state = ServedVerdict.served;
    await h.m.initialize();

    final r = await h.m.handleEntryCreated(
        _gameDay(type: CalendarEntryType.user, tag: null));

    expect(r.outcome, LeaseOutcome.leased);
  });

  test('holiday handling unchanged', () async {
    final h = harness();
    lan(h.c);
    h.c.read(_served.notifier).state = ServedVerdict.served;
    await h.m.initialize();
    final r = await h.m
        .handleEntryCreated(_gameDay(type: CalendarEntryType.holiday));
    expect(r.outcome, LeaseOutcome.outsideWindow);
  });

  test('the sweep does not promote a served night', () async {
    final h = harness(entries: [_gameDay()]);
    final svc = lan(h.c);
    h.c.read(_served.notifier).state = ServedVerdict.served;
    await h.m.initialize();
    await h.m.sweepExpiredLeases();
    expect(h.m.activeLeases, isEmpty);
    expect(svc.lastSimulatedPresetSave, isNull);
  });

  test('D4: an ARMED lease whose team becomes served is retracted on the next '
      'LAN sweep — one merged cfg write, the timer row gone', () async {
    final h = harness(entries: [_gameDay()]);
    final svc = lan(h.c);
    await h.m.initialize(); // promotes + arms the unserved night
    final armed = h.m.activeLeases.single;
    expect(leaseMacros(svc), [armed.presetId]);
    final savesBefore = svc.lastSimulatedPresetSave;

    h.c.read(_served.notifier).state = ServedVerdict.served;
    svc.lastSimulatedConfigPayload = null;
    await h.m.sweepExpiredLeases();

    expect(h.m.activeLeases, isEmpty);
    expect(svc.lastSimulatedConfigPayload, isNotNull,
        reason: 'the zero write went out');
    expect(leaseMacros(svc), isEmpty, reason: 'the lease timer row is gone');
    expect(identical(svc.lastSimulatedPresetSave, savesBefore), isTrue,
        reason: 'no new preset save; the preset itself is left in place');
  });

  test('D4 off the LAN: nothing is retracted and nothing is sent', () async {
    final h = harness(entries: [_gameDay()]);
    lan(h.c);
    await h.m.initialize();
    expect(h.m.activeLeases, hasLength(1));

    bridge(h.c, h.fs);
    h.c.read(_served.notifier).state = ServedVerdict.served;
    await h.m.sweepExpiredLeases();

    expect(h.m.activeLeases, hasLength(1),
        reason: 'the record must keep describing the armed timer');
    expect(await commands(h.fs), 0);
  });

  test('D4: a failed zero write keeps the records', () async {
    final h = harness(entries: [_gameDay()]);
    final svc = lan(h.c);
    await h.m.initialize();
    svc.simulateApplyConfigReturns = false;
    h.c.read(_served.notifier).state = ServedVerdict.served;
    await h.m.sweepExpiredLeases();
    expect(h.m.activeLeases, hasLength(1));
  });

  test('a calendar write for a now-served night retracts its armed lease at '
      'once', () async {
    final h = harness(entries: [_gameDay()]);
    final svc = lan(h.c);
    await h.m.initialize();
    expect(h.m.activeLeases, hasLength(1));

    h.c.read(_served.notifier).state = ServedVerdict.served;
    final r = await h.m.handleEntryCreated(_gameDay());

    expect(r.outcome, LeaseOutcome.servedByServer);
    expect(h.m.activeLeases, isEmpty);
    expect(leaseMacros(svc), isEmpty);
  });

  test('the server stops serving (stale heartbeat) → the next sweep leases the '
      'night again', () async {
    final h = harness(entries: [_gameDay()]);
    final svc = lan(h.c);
    h.c.read(_served.notifier).state = ServedVerdict.served;
    await h.m.initialize();
    expect(h.m.activeLeases, isEmpty);

    h.c.read(_served.notifier).state = ServedVerdict.notServed;
    await h.m.sweepExpiredLeases();

    expect(h.m.activeLeases, hasLength(1));
    expect(svc.lastSimulatedPresetSave, isNotNull);
  });

  test('LAUNCH RACE: status still loading → the lease WAITS; it resolves to '
      'served → no save, no cfg (no flash-then-retract)', () async {
    final h = harness();
    final svc = lan(h.c);
    await h.m.initialize();
    h.c.read(_served.notifier).state = ServedVerdict.unknown;
    h.m.servedStatusWait = const Duration(seconds: 5);

    final pending = h.m.handleEntryCreated(_gameDay());
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(svc.lastSimulatedPresetSave, isNull, reason: 'still waiting');
    h.c.read(_served.notifier).state = ServedVerdict.served;
    final r = await pending;

    expect(r.outcome, LeaseOutcome.servedByServer);
    expect(svc.lastSimulatedPresetSave, isNull);
    expect(svc.lastSimulatedConfigPayload, isNull);
  });

  test('LAUNCH RACE: still unknown after the bound → 112 behaviour (leased)',
      () async {
    final h = harness();
    final svc = lan(h.c);
    await h.m.initialize();
    h.c.read(_served.notifier).state = ServedVerdict.unknown;
    h.m.servedStatusWait = const Duration(milliseconds: 300);

    final r = await h.m.handleEntryCreated(_gameDay());

    expect(r.outcome, LeaseOutcome.leased);
    expect(svc.lastSimulatedPresetSave, isNotNull);
  });

  test('the retraction pass never waits: an unknown night is left armed for '
      'the next sweep', () async {
    final h = harness(entries: [_gameDay()]);
    lan(h.c);
    await h.m.initialize();
    expect(h.m.activeLeases, hasLength(1));
    h.c.read(_served.notifier).state = ServedVerdict.unknown;
    final sw = Stopwatch()..start();
    await h.m.sweepExpiredLeases();
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(h.m.activeLeases, hasLength(1));
  });

  test('a served check that throws reads as NOT served (phone path)', () async {
    final c = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => ref.watch(_repoSwitch)),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(true)),
      calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
      calendarLeaseEntriesProvider.overrideWithValue(const []),
      calendarLeaseSchedulesProvider.overrideWithValue(const []),
      calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider.overrideWith((_) => () async {}),
      servedGameDayEntryTestProvider.overrideWith(
          (_) => (_, __) => throw StateError('boom')),
    ]);
    addTearDown(c.dispose);
    final m = c.read(calendarEntryLeaseManagerProvider)..nowProvider = () => _now;
    lan(c);
    await m.initialize();
    expect((await m.handleEntryCreated(_gameDay())).outcome,
        LeaseOutcome.leased);
  });
}
