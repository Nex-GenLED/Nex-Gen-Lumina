// A scheduled catalog pattern must be psaved as one segment per BUS, not as
// the tuner's single id-less segment (which the firmware applies to segment 0
// only, and `psave` then snapshots the rest as they were — U7).
//
// Drives the REAL ScheduleSyncService.syncAll through a fake WledService that
// answers the three device reads the sync makes: /json/cfg (the bus set — the
// same device truth the healer uses), /json/state (the live layout, which the
// geometry gate compares against the buses) and /presets.json. Fixtures:
// two-channel, three-channel, one-segment-after-restart (collapsed layout the
// gate re-provisions before the save), unknown facts (no cfg), a channel-scoped
// schedule and a My Design with per-channel ids (both must be untouched).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

class _FakeService extends WledService {
  _FakeService({
    required this.cfg,
    required this.state,
    this.provisionsTo,
  }) : super('http://mock');

  /// The controller's `/json/cfg` — null models a controller whose bus list
  /// cannot be read (relay, unreadable cfg): UNKNOWN facts.
  final WledHardwareConfig? cfg;

  /// The live `/json/state`. Mutable so a geometry re-provision can "land".
  Map<String, dynamic>? state;

  /// What `/json/state` reports after a successful bounds re-provision.
  final Map<String, dynamic>? provisionsTo;

  final Map<int, Map<String, dynamic>> savedStates = {};
  final List<int> savedPresetIds = [];
  final List<Map<String, dynamic>> geometryPosts = [];
  Map<String, dynamic>? _lastCfg;

  @override
  Future<WledHardwareConfig?> getConfig() async => cfg;

  @override
  Future<Map<String, dynamic>?> getState() async => state;

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => const {};

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    final ins = (_lastCfg?['timers'] as Map?)?['ins'];
    if (ins is List) {
      return ins.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return null;
  }

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
    savedPresetIds.add(presetId);
    savedStates[presetId] = Map<String, dynamic>.from(state);
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async => true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    _lastCfg = cfg;
    return true;
  }
}

final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _container(_FakeService repo) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseActiveTimersProvider.overrideWithValue(const LeaseLedgerEmpty()),
  ]);
  addTearDown(container.dispose);
  return container;
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
          {
            'id': i,
            'start': 100 * i,
            'stop': 100 * (i + 1),
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

/// The collapsed layout a reboot leaves: one segment over the whole strip.
Map<String, dynamic> _collapsed(int totalLeds) => {
      'on': true,
      'bri': 128,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': totalLeds,
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

/// The Explore tuner's hand-back: ONE segment, NO id (selector_payload.dart).
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

ScheduleItem _catalogSchedule({List<int>? channels}) => ScheduleItem(
      id: 'sch-1',
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: 'Pattern: Harvest Moon - Solid',
      enabled: true,
      wledPayload: const {
        'on': true,
        'bri': 255,
        'seg': [kTunerSeg],
      },
      channels: channels,
      controllerId: channels == null ? null : 'controller-under-test',
    );

Map<String, dynamic> _fanned(int id) => {'id': id, ...kTunerSeg, 'on': true};

void main() {
  setUp(resetRepairAttempts);

  const svc = ScheduleSyncService();

  test('two-channel controller: the pattern preset names both buses', () async {
    final repo = _FakeService(cfg: _buses(2), state: _liveSegments(2));
    final ref = _container(repo).read(_refProvider);

    final result = await svc.syncAll(ref, [_catalogSchedule()]);

    expect(result.success, isTrue, reason: result.error);
    final saved = repo.savedStates[10];
    expect(saved, isNotNull, reason: 'pattern preset psaved into slot 10');
    expect(saved!['on'], isTrue);
    expect(saved['ib'], isTrue);
    expect(saved['seg'], [_fanned(0), _fanned(1)],
        reason: 'one segment per bus, each carrying the design and on');
  });

  test('three-channel controller: the pattern preset names all three buses',
      () async {
    final repo = _FakeService(cfg: _buses(3), state: _liveSegments(3));
    final ref = _container(repo).read(_refProvider);

    await svc.syncAll(ref, [_catalogSchedule()]);

    expect(repo.savedStates[10]?['seg'], [_fanned(0), _fanned(1), _fanned(2)]);
  });

  test(
      'one segment after a restart: the gate re-provisions the buses first, '
      'and the preset still names every bus (not the one live segment)',
      () async {
    final repo = _FakeService(
      cfg: _buses(2),
      state: _collapsed(200),
      provisionsTo: _liveSegments(2),
    );
    final ref = _container(repo).read(_refProvider);

    final result = await svc.syncAll(ref, [_catalogSchedule()]);

    expect(result.success, isTrue, reason: result.error);
    expect(repo.geometryPosts, isNotEmpty,
        reason: 'the geometry gate re-provisioned the collapsed layout');
    expect(repo.savedStates[10]?['seg'], [_fanned(0), _fanned(1)],
        reason: 'the bus set, not the live segment count, decides the fan-out');
  });

  test('unknown facts (no cfg): the body is exactly what it was — one id-less segment',
      () async {
    final repo = _FakeService(cfg: null, state: _collapsed(200));
    final ref = _container(repo).read(_refProvider);

    await svc.syncAll(ref, [_catalogSchedule()]);

    final saved = repo.savedStates[10];
    expect(saved, isNotNull);
    expect(saved!['seg'], [kTunerSeg],
        reason: 'no bus facts ⇒ no fan-out ⇒ byte-identical to +121');
    expect(saved['on'], isTrue);
    expect(saved['bri'], 255);
    expect(saved['ib'], isTrue);
  });

  test('a channel-scoped schedule is untouched: the scope rule already names the census',
      () async {
    final repo = _FakeService(cfg: _buses(2), state: _liveSegments(2));
    final ref = _container(repo).read(_refProvider);

    await svc.syncAll(ref, [_catalogSchedule(channels: const [1])]);

    expect(repo.savedStates[10]?['seg'], [
      {'id': 0, 'on': false},
      {'id': 1, ...kTunerSeg, 'on': true},
    ]);
  });

  test('an effect-shaped My Design (per-channel ids) is untouched', () async {
    final repo = _FakeService(cfg: _buses(2), state: _liveSegments(2));
    final ref = _container(repo).read(_refProvider);
    final design = ScheduleItem(
      id: 'sch-2',
      timeLabel: '7:00 PM',
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: My Design',
      enabled: true,
      wledPayload: const {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 0, 0, 0]], 'grp': 1, 'spc': 0, 'pal': 5, 'sx': 128, 'ix': 128},
          {'id': 1, 'fx': 12, 'col': [[0, 0, 255, 0]], 'grp': 1, 'spc': 0, 'pal': 5, 'sx': 100, 'ix': 128},
        ],
      },
    );

    await svc.syncAll(ref, [design]);

    expect(repo.savedStates[10]?['seg'], design.wledPayload!['seg']);
  });
}
