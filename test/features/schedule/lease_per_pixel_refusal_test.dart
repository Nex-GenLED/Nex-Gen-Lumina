// Roofline slice 2 — the one-night (lease) path refuses a painted design.
//
// FAIL-BEFORE (defect-style). The lease path is not a nightly design
// mechanism (audit §B.2): it psaves the entry's payload as live state into the
// 26–41 band with no layout, firmware, byte or read-back gate. On the
// unchanged code:
//   • composeDatedEntry builds a CalendarEntry carrying the picture, so the
//     editor's "Just this day" could store it (the editor now refuses first;
//     this is the pure backstop);
//   • CalendarEntryLeaseManager.handleEntryCreated psaves that body — a
//     per-pixel one stores no pixels and captures frz:true (fires dark); an
//     API-command one (`o:true`) would be stored by the controller as an API
//     preset with none of the slice's gates having run.
// After: composeDatedEntry throws PerPixelDesignRefused with the one-night
// sentence, and the lease manager returns invalidEntry with nothing written.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/per_pixel_payload_guard.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/dated_entry_compose.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kApiBody = {
  'o': true,
  'on': true,
  'bri': 180,
  'seg': [
    {
      'id': 0,
      'start': 0,
      'stop': 100,
      'on': true,
      'fx': 0,
      'i': [0, 100, [255, 0, 0, 0]],
    },
    {
      'id': 1,
      'start': 100,
      'stop': 200,
      'on': true,
      'fx': 0,
      'i': [0, 100, [0, 0, 255, 0]],
    },
  ],
};

/// The same picture without `o` (a design's toWledPayload).
Map<String, dynamic> perPixelBody() => Map<String, dynamic>.from(kApiBody)..remove('o');

const kCatalog = {
  'on': true,
  'bri': 255,
  'seg': [
    {
      'fx': 84,
      'col': [
        [255, 140, 0, 0]
      ]
    }
  ],
};

class _FakeService extends WledService {
  _FakeService() : super('http://mock');
  final Map<int, Map<String, dynamic>> savedStates = {};

  @override
  Future<WledHardwareConfig?> getConfig() async => WledHardwareConfig(
        totalLeds: 200,
        maxPowerMw: 30000,
        buses: [
          WledLedBus(pin: const [2], start: 0, len: 100, type: 30, order: 1),
          WledLedBus(pin: const [14], start: 100, len: 100, type: 30, order: 1),
        ],
      );

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': true,
        'bri': 128,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 100, 'on': true, 'fx': 0},
          {'id': 1, 'start': 100, 'stop': 200, 'on': true, 'fx': 0},
        ],
      };

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    savedStates[presetId] = Map<String, dynamic>.from(state);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('composeDatedEntry', () {
    final date = DateTime(2026, 11, 6);

    test('an API-command body is refused with the one-night sentence', () {
      expect(
        () => composeDatedEntry(
          date: date,
          action: DatedAction.runPattern,
          onHhmm: '19:00',
          offHhmm: '23:00',
          patternName: 'Porch stripes',
          patternPayload: kApiBody,
        ),
        throwsA(isA<PerPixelDesignRefused>().having(
            (e) => e.message, 'message', contains('"Porch stripes"'))),
      );
    });

    test('a per-pixel body (no o) is refused the same way', () {
      expect(
        () => composeDatedEntry(
          date: date,
          action: DatedAction.runPattern,
          onHhmm: '19:00',
          offHhmm: '23:00',
          patternName: 'Porch stripes',
          patternPayload: perPixelBody(),
        ),
        throwsA(isA<PerPixelDesignRefused>().having(
            (e) => e.message, 'message', contains('single night'))),
      );
    });

    test('a catalog pattern composes as before', () {
      final e = composeDatedEntry(
        date: date,
        action: DatedAction.runPattern,
        onHhmm: '19:00',
        offHhmm: '23:00',
        patternName: 'Harvest Moon',
        patternPayload: kCatalog,
      );
      expect(e.wledPayload, kCatalog);
      expect(e.patternName, 'Harvest Moon');
    });

    test('Off and Brightness never see a payload and are untouched', () {
      expect(
          composeDatedEntry(
                  date: date,
                  action: DatedAction.powerOff,
                  onHhmm: '23:00',
                  offHhmm: null)
              .patternName,
          'Off');
    });
  });

  group('CalendarEntryLeaseManager.handleEntryCreated', () {
    // D2 — a FIXED clock, injected through the manager's nowProvider: the
    // entries are 30 and 90 minutes after it on its own date, so the test
    // no longer flakes between 23:30 and midnight local (the on time used to
    // roll past midnight on today's date and the lease was already expired
    // before the refusal ran).
    final fixedNow = DateTime(2026, 11, 6, 10, 0);

    String dateKeyOf(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';

    CalendarEntry entry(Map<String, dynamic> payload) {
      return CalendarEntry(
        dateKey: dateKeyOf(fixedNow),
        patternName: 'Porch stripes',
        color: const Color(0xFFFF0000),
        onTime: hhmm(fixedNow.add(const Duration(minutes: 30))),
        offTime: hhmm(fixedNow.add(const Duration(minutes: 90))),
        brightness: 100,
        type: CalendarEntryType.user,
        autopilot: false,
        wledPayload: payload,
      );
    }

    ({_FakeService service, CalendarEntryLeaseManager manager}) harness() {
      final service = _FakeService();
      final container = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWithValue(service),
        calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
        calendarLeaseLiveWritesEnabledProvider
            .overrideWith((_) => Stream.value(true)),
        calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
        calendarLeaseEntriesProvider.overrideWithValue(const []),
        calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
        calendarLeaseSchedulesProvider.overrideWithValue(const []),
        calendarLeaseScheduleUpdaterProvider.overrideWith((_) => (_) async {}),
        calendarLeaseScheduleSyncTriggerProvider
            .overrideWith((_) => () async {}),
      ]);
      addTearDown(container.dispose);
      final manager = container.read(calendarEntryLeaseManagerProvider)
        ..nowProvider = () => fixedNow;
      return (service: service, manager: manager);
    }

    test('an API-command body: invalidEntry, nothing psaved', () async {
      final h = harness();
      await h.manager.initialize();
      final result = await h.manager.handleEntryCreated(entry(kApiBody));
      expect(result.outcome, LeaseOutcome.invalidEntry,
          reason: 'on the unchanged code this was leased and psaved');
      expect(result.errorMessage, contains('Porch stripes'));
      expect(h.service.savedStates, isEmpty);
    });

    test('a per-pixel body (no o): invalidEntry, nothing psaved', () async {
      final h = harness();
      await h.manager.initialize();
      final result = await h.manager.handleEntryCreated(entry(perPixelBody()));
      expect(result.outcome, LeaseOutcome.invalidEntry);
      expect(h.service.savedStates, isEmpty);
    });

    test('a catalog pattern still leases and psaves (unchanged)', () async {
      final h = harness();
      await h.manager.initialize();
      final result = await h.manager.handleEntryCreated(entry(kCatalog));
      expect(result.outcome, isNot(LeaseOutcome.invalidEntry));
      expect(h.service.savedStates, isNotEmpty);
    });
  });
}
