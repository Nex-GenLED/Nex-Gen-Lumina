// +126 (d) — after the pattern psaves, the sync reads /presets.json back
// ONCE, before the live-state restore, and compares each written slot with
// presetSatisfies. A slot that reads back different, or a presets.json that
// cannot be read twice, is reported as unconverged: still armed (option ii),
// recorded, shown. Driven through the real ScheduleSyncService.syncAll
// against a fake controller that stores what it is sent — or a corrupted
// copy of it — and scripts its presets.json reads.

import 'dart:convert';

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
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService extends WledService {
  _FakeService({this.storeMutation, List<bool>? readOutcomes})
      : readOutcomes = readOutcomes ?? [],
        super('http://mock');

  /// Applied to the stored copy of a psave (models a controller that did
  /// not store what it was sent).
  final void Function(int id, Map<String, dynamic> stored)? storeMutation;

  /// Scripted outcomes for successive readPresets calls (the sync's opening
  /// read first, then the read-back attempts): true = readable. Exhausted →
  /// readable.
  final List<bool> readOutcomes;

  final Map<int, Map<String, dynamic>> device = {};

  /// Every controller call in order, so the test can assert the read-back
  /// came BEFORE the live-state restore.
  final List<String> log = [];

  @override
  Future<WledHardwareConfig?> getConfig() async => null;

  @override
  Future<WledInfoResponse?> getInfo() async => null;

  @override
  Future<Map<String, dynamic>?> getState() async {
    log.add('getState');
    return {
      'on': false,
      'bri': 128,
      'seg': [
        {'id': 0, 'start': 0, 'stop': 100, 'on': true, 'fx': 0}
      ],
    };
  }

  @override
  Future<PresetsRead> readPresets() async {
    log.add('readPresets');
    final readable = readOutcomes.isEmpty ? true : readOutcomes.removeAt(0);
    if (!readable) return const PresetsRead.unreadable('scripted');
    if (device.isEmpty) return const PresetsRead.deviceEmpty();
    return PresetsRead.available(
        {for (final e in device.entries) e.key: Map.of(e.value)});
  }

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async =>
      {for (final e in device.entries) e.key: Map.of(e.value)};

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    final ins = (lastCfg?['timers'] as Map?)?['ins'];
    if (ins is List) {
      return ins.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return null;
  }

  Map<String, dynamic>? lastCfg;

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    log.add('psave $presetId');
    // Deep copy: the schedule's payload is const, and a mutation must act on
    // the controller's copy, never the app's.
    final stored = <String, dynamic>{
      ...(jsonDecode(jsonEncode(state)) as Map<String, dynamic>),
      if (presetName != null) 'n': presetName
    }..remove('ib');
    storeMutation?.call(presetId, stored);
    device[presetId] = stored;
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async {
    device.remove(presetId);
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    log.add(payload['transition'] == 0 ? 'restore' : 'applyJson');
    return true;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    log.add('cfg');
    lastCfg = cfg;
    return true;
  }

  List<int> get armedMacros {
    final ins = (lastCfg?['timers'] as Map?)?['ins'];
    if (ins is! List) return const [];
    return [
      for (final t in ins)
        if (t is Map && t['en'] == 1 && t['macro'] is int && t['macro'] > 0)
          t['macro'] as int,
    ];
  }
}

final _refProvider = Provider<Ref>((ref) => ref);

Ref _ref(_FakeService repo) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseActiveTimersProvider.overrideWithValue(const LeaseLedgerEmpty()),
  ]);
  addTearDown(container.dispose);
  return container.read(_refProvider);
}

/// Ellie's schedule: Classic Christmas 2, one segment here.
ScheduleItem _christmas() => const ScheduleItem(
      id: 'sch-1',
      timeLabel: '5:00 PM',
      offTimeLabel: '7:00 AM',
      repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: 'Pattern: Classic Christmas 2',
      enabled: true,
      wledPayload: {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 84,
            'sx': 0,
            'ix': 0,
            'pal': 5,
            'grp': 1,
            'spc': 0,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
              [255, 203, 118, 0]
            ],
          }
        ],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Zero settle / budget: the read-back retry does not sleep in tests.
  const svc = ScheduleSyncService(
      readBackSettle: Duration.zero, readBackBudget: Duration.zero);

  setUp(() {
    resetRepairAttempts();
    SharedPreferences.setMockInitialValues({});
  });

  test('a pattern slot that reads back as sent: nothing reported, armed',
      () async {
    final repo = _FakeService();
    final result = await svc.syncAll(_ref(repo), [_christmas()]);
    expect(result.success, isTrue);
    expect(result.unconvergedPresetIds, isEmpty);
    expect(result.presetErrors.where((e) => e.contains('Classic')), isEmpty);
    expect(repo.armedMacros, contains(10));
  });

  test('the read-back happens AFTER the pattern psave and BEFORE the '
      'live-state restore', () async {
    final repo = _FakeService();
    await svc.syncAll(_ref(repo), [_christmas()]);
    final psave = repo.log.indexOf('psave 10');
    final restore = repo.log.indexOf('restore');
    expect(psave, greaterThanOrEqualTo(0));
    expect(restore, greaterThan(psave));
    final readBacks = [
      for (var i = 0; i < repo.log.length; i++)
        if (repo.log[i] == 'readPresets' && i > psave) i
    ];
    expect(readBacks, hasLength(1),
        reason: 'ONE read-back after the pattern writes');
    expect(readBacks.single, lessThan(restore),
        reason: 'the read-back comes before the restore');
  });

  test('the Classic Christmas shape — slot 10 holds another grouping — reads '
      'back as a MISMATCH: still armed, reported, flagged', () async {
    // The controller stores the old "2 on, 6 off" grouping instead.
    final repo = _FakeService(storeMutation: (id, stored) {
      if (id != 10) return;
      final seg = (stored['seg'] as List).first as Map<String, dynamic>;
      seg['grp'] = 2;
      seg['spc'] = 6;
    });
    final result = await svc.syncAll(_ref(repo), [_christmas()]);
    expect(result.success, isTrue, reason: 'the timers still confirmed');
    expect(result.unconvergedPresetIds, [10]);
    expect(result.presetErrors.join(' '),
        contains('did not save to your lights the way it was sent'));
    expect(repo.armedMacros, contains(10),
        reason: 'option (ii): armed, the app shows the failure');
  });

  test('a slot that is absent on read-back is a mismatch too', () async {
    final repo = _FakeService(storeMutation: (id, stored) {
      if (id == 10) stored['n'] = 'something else'; // name differs
    });
    final result = await svc.syncAll(_ref(repo), [_christmas()]);
    expect(result.unconvergedPresetIds, [10]);
  });

  test('presets.json unreadable on the read-back, once: the retry reads it '
      'and the slot lands', () async {
    // Opening read ok, first read-back attempt fails, retry ok.
    final repo = _FakeService(readOutcomes: [true, false, true]);
    final result = await svc.syncAll(_ref(repo), [_christmas()]);
    expect(result.unconvergedPresetIds, isEmpty);
    expect(repo.log.where((l) => l == 'readPresets').length, 3);
  });

  test('presets.json unreadable twice: written, not verified — still armed, '
      'reported as not confirmed', () async {
    final repo = _FakeService(readOutcomes: [true, false, false]);
    final result = await svc.syncAll(_ref(repo), [_christmas()]);
    expect(result.success, isTrue);
    expect(result.unconvergedPresetIds, [10]);
    expect(result.presetErrors.join(' '), contains('could not be confirmed'));
    expect(repo.armedMacros, contains(10));
  });

  test('a payload-less schedule (Turn Off) makes no pattern write and no '
      'read-back', () async {
    final repo = _FakeService();
    final off = const ScheduleItem(
      id: 'off',
      timeLabel: '11:00 PM',
      repeatDays: ['Mon'],
      actionLabel: 'Turn Off',
      enabled: true,
    );
    final result = await svc.syncAll(_ref(repo), [off]);
    expect(result.success, isTrue);
    expect(result.unconvergedPresetIds, isEmpty);
    final ladderLast = repo.log.lastIndexWhere((l) => l.startsWith('psave'));
    final readsAfter = repo.log
        .asMap()
        .entries
        .where((e) => e.key > ladderLast && e.value == 'readPresets');
    expect(readsAfter, isEmpty, reason: 'no pattern slot → no read-back');
  });
}
