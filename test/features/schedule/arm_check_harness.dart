// Shared harness for the arm-check tests (2026-11-02): a FAITHFUL fake
// controller driven through the real `ScheduleSyncService.syncAll`, with the
// real predicate (`presetSatisfies`) and the real builders.
//
// "Faithful" = it stores exactly what `savePreset` writes (minus `ib`, which
// WLED never persists) under the name it was given, so a re-read returns the
// builder's own output. That is the best case for any predicate: a check that
// cannot pass here cannot pass on hardware. `storeRootOn: false` models the
// opposite — a controller that drops root `on`, so the stored preset can
// NEVER satisfy the builder and the non-convergence guard must still fire.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerDefaultsHealerProvider, ControllerHealReport;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// The empty-armed guard's customer-facing text (schedule_sync.dart).
const String kArmCheckBanner =
    'Your schedules are saved but could not be armed on the controller. Try '
    'syncing again — if this keeps happening, contact support.';

class FaithfulController extends WledService {
  FaithfulController({
    Map<int, Map<String, dynamic>>? presets,
    this.hasCoords = true,
    this.storeRootOn = true,
    this.state = const {
      'on': true,
      'bri': 128,
      'seg': [
        {
          'id': 0,
          'col': [
            [255, 160, 0, 0]
          ]
        }
      ],
    },
  })  : presets = presets ?? {},
        super('http://mock');

  /// What the controller HOLDS (mutated by savePreset / deletePreset).
  final Map<int, Map<String, dynamic>> presets;
  final bool hasCoords;
  final bool storeRootOn;
  final Map<String, dynamic>? state;

  final List<int> saved = [];
  final Map<int, Map<String, dynamic>> lastWritten = {};
  int applyConfigCalls = 0;
  int timerCfgWrites = 0;
  int applyJsonCalls = 0;
  Map<String, dynamic>? lastCfg;

  List<Map<String, dynamic>> get lastIns =>
      ((lastCfg!['timers'] as Map)['ins'] as List)
          .cast<Map<String, dynamic>>();

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => {
        for (final e in presets.entries)
          e.key: Map<String, dynamic>.from(e.value),
      };

  @override
  Future<Map<String, dynamic>?> getState() async => state;

  // syncAll reads coordinates through ClockInfoSource; the sim-mode base
  // returns null, which would silently turn the solar gate off.
  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => hasCoords
      ? const ControllerClockInfo(latitude: 38.99, longitude: -94.25)
      : const ControllerClockInfo(latitude: 0, longitude: 0);

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    saved.add(presetId);
    lastWritten[presetId] = Map<String, dynamic>.from(state);
    final stored = Map<String, dynamic>.from(state)..remove('ib');
    if (!storeRootOn) stored.remove('on');
    if (presetName != null) stored['n'] = presetName;
    presets[presetId] = stored;
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async {
    presets.remove(presetId);
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls++;
    return true;
  }

  // Only TIMER-TABLE writes count: the on-connect defaults healer (started by
  // the WledNotifier that syncAll pauses) also POSTs a gamma/fps cfg here.
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    applyConfigCalls++;
    if (cfg['timers'] != null) {
      timerCfgWrites++;
      lastCfg = cfg;
    }
    return true;
  }

  // Echo what we last wrote so the 2xx readback confirms without the
  // minutes-long patient-verify poll.
  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    final ins = (lastCfg?['timers'] as Map?)?['ins'];
    if (ins is List) {
      return ins
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return null;
  }
}

final armCheckRefProvider = Provider<Ref>((ref) => ref);

/// The global "Turn lights off at sunrise daily" row exactly as the app arms
/// it (slot 8, hour:255 marker, macro 2 = NGL Off).
Map<String, dynamic> sunriseOffRow() =>
    {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127};

ProviderContainer armCheckContainer(
  FaithfulController repo, {
  required bool solarFlag,
  bool sunriseOffOn = false,
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseActiveTimersProvider
        .overrideWithValue(const LeaseLedgerEmpty()),
    solarSchedulingEnabledSyncProvider.overrideWithValue(solarFlag),
    globalSunriseOffTimerProvider
        .overrideWithValue(sunriseOffOn ? sunriseOffRow() : null),
    // syncAll pauses the WledNotifier, whose build fires the on-connect
    // defaults healer. That healer is unrelated to arming, does its own cfg
    // writes, and keeps reading providers after an early-exit test has
    // disposed the container. Neutralise it.
    controllerDefaultsHealerProvider.overrideWithValue(
        () async => ControllerHealReport()..reachable = false),
  ]);
  // The notifier schedules a fire-and-forget microtask on build; let it drain
  // before the container goes away.
  addTearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.dispose();
  });
  return c;
}

const List<String> kDaily = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The one-segment design the Explore tuner hands a schedule.
const Map<String, dynamic> kOneSegmentDesign = {
  'on': true,
  'bri': 200,
  'seg': [
    {
      'id': 0,
      'fx': 0,
      'pal': 5,
      'sx': 28,
      'ix': 0,
      'col': [
        [255, 160, 0, 0]
      ]
    }
  ],
};

/// A pattern schedule in the shape the editor saves: a design payload, the
/// `Pattern: name` label, no stored slot (syncAll assigns 10).
ScheduleItem patternSchedule({
  required String on,
  String? off,
  String label = 'Pattern: overnight',
  int? presetId,
  DateTime? disabledUntil,
  List<String> repeatDays = kDaily,
  Map<String, dynamic> payload = kOneSegmentDesign,
}) =>
    ScheduleItem(
      id: 'sched-$label-$on',
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: repeatDays,
      actionLabel: label,
      enabled: true,
      presetId: presetId,
      disabledUntil: disabledUntil,
      wledPayload: payload,
    );
