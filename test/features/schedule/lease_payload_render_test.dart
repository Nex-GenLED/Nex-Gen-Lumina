// +112 — a dated entry that carries a WLED payload is leased WITH that look
// (effect, palette, every colour), not collapsed to its first colour as a
// solid. Root on / bri / ib remain the lease's own.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  CalendarEntry insideWindowEntry({Map<String, dynamic>? payload}) {
    final now = DateTime.now();
    return CalendarEntry(
      dateKey: todayDateKey(),
      patternName: 'Team Night',
      color: const Color(0xFFE31837),
      onTime: hhmm(now.add(const Duration(minutes: 30))),
      offTime: hhmm(now.add(const Duration(minutes: 90))),
      brightness: 85,
      type: CalendarEntryType.user,
      autopilot: false,
      wledPayload: payload,
    );
  }

  ({WledService service, CalendarEntryLeaseManager manager}) harness() {
    final service = WledService('http://mock');
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(service),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(true)),
      calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
      calendarLeaseEntriesProvider.overrideWithValue(const []),
      calendarLeaseSchedulesProvider.overrideWithValue(const []),
      calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider
          .overrideWith((_) => () async {}),
    ]);
    addTearDown(container.dispose);
    return (
      service: service,
      manager: container.read(calendarEntryLeaseManagerProvider),
    );
  }

  const twoColourChase = <String, dynamic>{
    'on': true,
    'bri': 120,
    'transition': 7,
    'psave': 99,
    'n': 'stale name',
    'seg': [
      {
        'fx': 12,
        'sx': 40,
        'ix': 180,
        'pal': 5,
        'col': [
          [227, 24, 55, 0],
          [255, 184, 28, 0],
        ],
      },
    ],
  };

  test('the carried payload is what gets psaved — effect and both colours',
      () async {
    final h = harness();
    await h.manager.initialize();
    final result =
        await h.manager.handleEntryCreated(insideWindowEntry(payload: twoColourChase));
    expect(result.outcome, LeaseOutcome.leased);

    final saved = h.service.lastSimulatedPresetSave;
    expect(saved, isNotNull);
    final state = saved!.state;
    final seg = (state['seg'] as List).first as Map;
    expect(seg['fx'], 12, reason: 'motion kept');
    expect(seg['pal'], 5);
    // The LAN service pads `col` to WLED's three slots; the two we sent must
    // lead, unchanged.
    final col = seg['col'] as List;
    expect(col[0], [227, 24, 55, 0]);
    expect(col[1], [255, 184, 28, 0], reason: 'second colour kept');
    expect(state['on'], isTrue);
    expect(state['ib'], isTrue, reason: 'ib persists root on/bri');
    expect(state['bri'], 217, reason: "the ENTRY's 85% wins over the payload's bri");
    expect(state.containsKey('psave'), isFalse, reason: 'save keys stripped');
    expect(state.containsKey('transition'), isFalse);
  });

  test('without a payload the pre-112 solid render is unchanged', () async {
    final h = harness();
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(insideWindowEntry());
    expect(result.outcome, LeaseOutcome.leased);
    final state = h.service.lastSimulatedPresetSave!.state;
    final seg = (state['seg'] as List).first as Map;
    expect(seg['fx'], 0);
    final col = seg['col'] as List;
    expect(col[0], [227, 24, 55, 0], reason: 'the entry colour, as a solid');
    // Any padding slots the service adds are black, never a second colour.
    for (final extra in col.skip(1)) {
      expect(extra, [0, 0, 0, 0]);
    }
    expect(state['ib'], isTrue);
  });

  test('a payload without segments falls back to the solid render', () async {
    final h = harness();
    await h.manager.initialize();
    final result = await h.manager
        .handleEntryCreated(insideWindowEntry(payload: const {'on': true}));
    expect(result.outcome, LeaseOutcome.leased);
    final state = h.service.lastSimulatedPresetSave!.state;
    expect((state['seg'] as List).first['fx'], 0);
  });
}
