// +112 (#123) — a lease that cannot be armed because the phone is off the
// home LAN (bridge mode) or has no controller at all is DEFERRED: nothing is
// written to the controller, the date is NOT registered, and the next sweep on
// the LAN arms it. Before this fix the date was registered "for a later
// retry", and the sweep's promotion loop skipped every registered date — so
// the retry never happened and the lease timer could still be merged into a
// later LAN schedule sync pointing at a preset that was never saved.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Switchable repository: the phone moves from cellular (bridge relay, cannot
/// write cfg) or no controller (null) to the home LAN (direct service).
final _repoSwitch = StateProvider<WledRepository?>((_) => null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  String todayDateKey() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  CalendarEntry insideWindowEntry() {
    final now = DateTime.now();
    return CalendarEntry(
      dateKey: todayDateKey(),
      patternName: 'Warm White',
      color: const Color(0xFFFFCC88),
      onTime: hhmm(now.add(const Duration(minutes: 30))),
      offTime: hhmm(now.add(const Duration(minutes: 90))),
      brightness: 75,
      type: CalendarEntryType.user,
      autopilot: false,
    );
  }

  /// A relay repo in BRIDGE mode (no webhook) — the shape that cannot carry
  /// a /json/cfg write. Commands it would send land in the fake Firestore.
  CloudRelayRepository bridgeRepo(FakeFirebaseFirestore fs) =>
      CloudRelayRepository(
        userId: 'u1',
        controllerId: 'c1',
        controllerIp: '192.0.2.10',
        webhookUrl: '',
        firestore: fs,
        commandTimeout: const Duration(milliseconds: 300),
      );

  ({
    ProviderContainer container,
    CalendarEntryLeaseManager manager,
    FakeFirebaseFirestore fs,
  }) harness({required CalendarEntry entry}) {
    final fs = FakeFirebaseFirestore();
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => ref.watch(_repoSwitch)),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(true)),
      calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
      calendarLeaseEntriesProvider.overrideWithValue([entry]),
      calendarLeaseSchedulesProvider.overrideWithValue(const []),
      calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider
          .overrideWith((_) => () async {}),
    ]);
    addTearDown(container.dispose);
    return (
      container: container,
      manager: container.read(calendarEntryLeaseManagerProvider),
      fs: fs,
    );
  }

  Future<int> commandCount(FakeFirebaseFirestore fs) async =>
      (await fs.collection('users').doc('u1').collection('commands').get())
          .docs
          .length;

  test('off-LAN (bridge): deferred, not registered, zero controller commands',
      () async {
    final entry = insideWindowEntry();
    final h = harness(entry: entry);
    h.container.read(_repoSwitch.notifier).state = bridgeRepo(h.fs);
    await h.manager.initialize();

    final result = await h.manager.handleEntryCreated(entry);

    expect(result.outcome, LeaseOutcome.deferred);
    expect(result.errorMessage, contains('home Wi-Fi'));
    expect(h.manager.activeLeases, isEmpty,
        reason: 'a deferred date must not be registered, or the sweep would '
            'never retry it');
    expect(await commandCount(h.fs), 0,
        reason: 'no savePreset and no applyConfig over the bridge');
  });

  test('no controller at all: deferred, not registered', () async {
    final entry = insideWindowEntry();
    final h = harness(entry: entry);
    await h.manager.initialize();

    final result = await h.manager.handleEntryCreated(entry);

    expect(result.outcome, LeaseOutcome.deferred);
    expect(h.manager.activeLeases, isEmpty);
  });

  test('a deferred lease is armed by the next sweep on the LAN', () async {
    final entry = insideWindowEntry();
    final h = harness(entry: entry);
    h.container.read(_repoSwitch.notifier).state = bridgeRepo(h.fs);
    await h.manager.initialize();

    // Cellular: deferred.
    final first = await h.manager.handleEntryCreated(entry);
    expect(first.outcome, LeaseOutcome.deferred);
    expect(h.manager.activeLeases, isEmpty);

    // Home: the sweep promotes the still-in-window entry and arms it.
    final service = WledService('http://mock');
    h.container.read(_repoSwitch.notifier).state = service;
    await h.manager.sweepExpiredLeases();

    expect(h.manager.activeLeases.length, 1,
        reason: 'the sweep re-promoted the unregistered date');
    expect(service.lastSimulatedPresetSave, isNotNull,
        reason: 'the lease preset reached the controller');
    expect(service.lastSimulatedConfigPayload, isNotNull,
        reason: 'the lease timer reached the controller');
    expect(await commandCount(h.fs), 0,
        reason: 'the earlier bridge phase still sent nothing');
  });

  test('an armed lease edited off-LAN keeps the ARMED record, reports deferred',
      () async {
    final entry = insideWindowEntry();
    final h = harness(entry: entry);
    final service = WledService('http://mock');
    h.container.read(_repoSwitch.notifier).state = service;
    await h.manager.initialize();

    // initialize() already swept and leased the in-window entry on the LAN;
    // calling again lands on the update path. Either way it is armed.
    final armed = await h.manager.handleEntryCreated(entry);
    expect(armed.outcome, isIn([LeaseOutcome.leased, LeaseOutcome.updated]));
    final before = h.manager.activeLeases.single;

    // Now on cellular, the customer edits the night's brightness.
    h.container.read(_repoSwitch.notifier).state = bridgeRepo(h.fs);
    final edited =
        await h.manager.handleEntryCreated(entry.copyWith(brightness: 20));

    expect(edited.outcome, LeaseOutcome.deferred);
    final after = h.manager.activeLeases.single;
    expect(after.wledPayload, before.wledPayload,
        reason: 'the registry describes what the controller still holds');
    expect(await commandCount(h.fs), 0);
  });
}
