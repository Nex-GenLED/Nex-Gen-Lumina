// A one-night entry's lease preset must apply to every bus of the controller,
// not only segment 0, and must honour the entry's channel scope.
//
// Drives the REAL CalendarEntryLeaseManager.handleEntryCreated through a fake
// WledService that answers /json/cfg (bus set), /json/state (live layout) and
// records the psaved body. Fixtures: two-channel, three-channel,
// one-segment-after-restart, unknown facts, and a channel-scoped entry.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService extends WledService {
  _FakeService({required this.cfg, required this.state, this.provisionsTo})
      : super('http://mock');

  final WledHardwareConfig? cfg;
  Map<String, dynamic>? state;
  final Map<String, dynamic>? provisionsTo;

  final Map<int, Map<String, dynamic>> savedStates = {};
  final List<Map<String, dynamic>> geometryPosts = [];

  @override
  Future<WledHardwareConfig?> getConfig() async => cfg;

  @override
  Future<Map<String, dynamic>?> getState() async => state;

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async {
    geometryPosts.add(payload);
    if (provisionsTo != null) state = provisionsTo;
    return true;
  }

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

WledHardwareConfig _buses(int n) => WledHardwareConfig(
      totalLeds: 100 * n,
      maxPowerMw: 30000,
      buses: [
        for (var i = 0; i < n; i++)
          WledLedBus(pin: [i], start: 100 * i, len: 100, type: 30, order: 1),
      ],
    );

Map<String, dynamic> _liveSegments(int n) => {
      'on': true,
      'bri': 128,
      'seg': [
        for (var i = 0; i < n; i++)
          {'id': i, 'start': 100 * i, 'stop': 100 * (i + 1), 'on': true, 'fx': 0},
      ],
    };

Map<String, dynamic> _collapsed(int totalLeds) => {
      'on': true,
      'bri': 128,
      'seg': [
        {'id': 0, 'start': 0, 'stop': totalLeds, 'on': true, 'fx': 0},
      ],
    };

/// The Explore tuner's hand-back as a one-night entry carries it.
const Map<String, dynamic> kTunerSeg = {
  'fx': 84,
  'sx': 0,
  'ix': 0,
  'pal': 5,
  'grp': 1,
  'spc': 0,
  'col': [
    [255, 140, 0, 0],
    [120, 0, 160, 0],
    [0, 90, 40, 0],
  ],
};
const Map<String, dynamic> kTunerPayload = {
  'on': true,
  'bri': 255,
  'seg': [kTunerSeg],
};

Map<String, dynamic> _fanned(int id) => {'id': id, ...kTunerSeg, 'on': true};

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

  CalendarEntry entry({List<int>? channels}) {
    final now = DateTime.now();
    return CalendarEntry(
      dateKey: todayDateKey(),
      patternName: 'Harvest Moon - Solid',
      color: const Color(0xFFFF8C00),
      onTime: hhmm(now.add(const Duration(minutes: 30))),
      offTime: hhmm(now.add(const Duration(minutes: 90))),
      brightness: 100,
      type: CalendarEntryType.user,
      autopilot: false,
      wledPayload: kTunerPayload,
      channels: channels,
      controllerId: channels == null ? null : 'controller-under-test',
    );
  }

  ({_FakeService service, CalendarEntryLeaseManager manager}) harness(
      _FakeService service) {
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
    return (
      service: service,
      manager: container.read(calendarEntryLeaseManagerProvider),
    );
  }

  Future<Map<String, dynamic>> leaseAndRead(
    _FakeService service, {
    List<int>? channels,
  }) async {
    final h = harness(service);
    await h.manager.initialize();
    final result = await h.manager.handleEntryCreated(entry(channels: channels));
    expect(result.outcome, isNot(LeaseOutcome.gateRefused),
        reason: 'the gate must not refuse: ${result.outcome}');
    expect(service.savedStates, isNotEmpty, reason: 'the lease preset was psaved');
    return service.savedStates.values.single;
  }

  test('two-channel controller: the lease preset names both buses', () async {
    final saved = await leaseAndRead(
        _FakeService(cfg: _buses(2), state: _liveSegments(2)));
    expect(saved['on'], isTrue);
    expect(saved['ib'], isTrue);
    expect(saved['bri'], 255, reason: "the entry's 100% wins");
    expect(saved['seg'], [_fanned(0), _fanned(1)]);
  });

  test('three-channel controller: the lease preset names all three buses',
      () async {
    final saved = await leaseAndRead(
        _FakeService(cfg: _buses(3), state: _liveSegments(3)));
    expect(saved['seg'], [_fanned(0), _fanned(1), _fanned(2)]);
  });

  test('one segment after a restart: re-provisioned first, then every bus named',
      () async {
    final service = _FakeService(
      cfg: _buses(2),
      state: _collapsed(200),
      provisionsTo: _liveSegments(2),
    );
    final saved = await leaseAndRead(service);
    expect(service.geometryPosts, isNotEmpty,
        reason: 'the geometry gate re-provisioned the collapsed layout');
    expect(saved['seg'], [_fanned(0), _fanned(1)]);
  });

  test('unknown facts (no cfg): the body is exactly what it was — one id-less segment',
      () async {
    final saved = await leaseAndRead(
        _FakeService(cfg: null, state: _collapsed(200)));
    expect(saved['seg'], [kTunerSeg],
        reason: 'no bus facts ⇒ no fan-out ⇒ byte-identical to +121');
    expect(saved['on'], isTrue);
    expect(saved['ib'], isTrue);
  });

  test('a channel-scoped entry fires scoped: the addressed bus lit, the other off',
      () async {
    final saved = await leaseAndRead(
        _FakeService(cfg: _buses(2), state: _liveSegments(2)),
        channels: const [1]);
    expect(saved['seg'], [
      {'id': 0, 'on': false},
      {'id': 1, ...kTunerSeg, 'on': true},
    ]);
  });
}
