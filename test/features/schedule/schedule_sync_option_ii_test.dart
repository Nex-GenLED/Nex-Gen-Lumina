// +126 (b) — option (ii), owner decision: a schedule whose pattern preset
// write did not land is STILL ARMED, and the sync reports the slot so the app
// records and shows the failure. Never disarmed (option iii).
//
// Driven through the real ScheduleSyncService.syncAll against a fake
// controller whose psave of the pattern slot fails while the ladder saves
// succeed and the cfg write confirms.

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
  _FakeService({required this.failingSlots}) : super('http://mock');

  /// Slots whose psave the controller refuses (returns false).
  final Set<int> failingSlots;
  final Map<int, Map<String, dynamic>> device = {};
  final List<int> savedPresetIds = [];
  Map<String, dynamic>? lastCfg;

  @override
  Future<WledHardwareConfig?> getConfig() async => null;

  @override
  Future<WledInfoResponse?> getInfo() async => null;

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': false,
        'bri': 128,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 100, 'on': true, 'fx': 0}
        ],
      };

  @override
  Future<PresetsRead> readPresets() async => device.isEmpty
      ? const PresetsRead.deviceEmpty()
      : PresetsRead.available({for (final e in device.entries) e.key: Map.of(e.value)});

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

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    savedPresetIds.add(presetId);
    if (failingSlots.contains(presetId)) return false;
    device[presetId] = {...state, if (presetName != null) 'n': presetName};
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async {
    device.remove(presetId);
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
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
  const svc = ScheduleSyncService();

  setUp(() {
    resetRepairAttempts();
    SharedPreferences.setMockInitialValues({});
  });

  test('a failed pattern psave: the schedule is STILL ARMED and the slot is '
      'reported as unconverged', () async {
    final repo = _FakeService(failingSlots: {10});
    final result = await svc.syncAll(_ref(repo), [_christmas()]);

    expect(repo.savedPresetIds, contains(10), reason: 'the write was attempted');
    expect(result.success, isTrue, reason: 'the timers were confirmed');
    expect(result.unconvergedPresetIds, [10]);
    expect(result.presetErrors.join(' '), contains('Failed to save preset 10'));
    expect(repo.armedMacros, contains(10),
        reason: 'option (ii): armed anyway — the controller keeps whatever '
            'slot 10 held, and the app shows the failure instead of going dark');
    expect(result.schedulesWithPresets.map((s) => s.id), contains('sch-1'));
  });

  test('a clean sync reports no unconverged slot', () async {
    final repo = _FakeService(failingSlots: const {});
    final result = await svc.syncAll(_ref(repo), [_christmas()]);
    expect(result.success, isTrue);
    expect(result.unconvergedPresetIds, isEmpty);
    expect(repo.armedMacros, contains(10));
  });
}
