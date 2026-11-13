// test/features/schedule/sunrise_off_gating_test.dart
//
// The two defects that made the sunrise-off feature a SILENT NO-OP while
// reporting success — the worst failure mode, and the one that has bitten this
// area repeatedly (dead-macro schedules, unarmed lease timers, false-green cfg
// writes). Both are asserted here because both readback as "perfectly armed".
//
// BUG 1 — arm() assumed preset 2 (NGL Off) existed. Nothing outside
//   ScheduleSyncService.syncAll ever creates it, so on any controller where a
//   schedule sync had never run, arming wrote a timer pointing at a preset that
//   does not exist: WLED fires macro 2, loads nothing, lights stay on.
//
// BUG 2 — the toggle used to read the controller's table back and swap index 8.
//   WLED COMPACTS that readback (omits fully-empty timers), so the fix
//   classified rows by the 255 marker: first = sunrise. A LONE sunset row
//   ("Sunset → 11 PM") then read as the sunrise and was overwritten, and slot
//   9 was stubbed. Build 127 (ownership) reads the table back again — it is
//   the only way to keep the rows this toggle does not own — but classifies
//   every row by CONTENT: 254 is a sunset, 255 a sunrise, and a lone 255 row
//   with an ON macro is refused rather than guessed (timer_table_ownership.dart).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show
        calendarLeaseActiveTimersProvider,
        calendarLeaseSchedulesHydratedProvider,
        calendarLeaseSchedulesProvider,
        LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ControllerClockInfo;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

class _FakeService extends WledService {
  _FakeService({
    this.presets = const {},
    this.savePresetSucceeds = true,
  }) : super('http://mock');

  Map<int, Map<String, dynamic>> presets;
  bool savePresetSucceeds;
  int timerReads = 0;

  /// Build 127 — what the controller reads back (compacted).
  List<Map<String, dynamic>> table = [];

  final List<({int id, Map<String, dynamic> state, String? name})> saved = [];

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    timerReads++;
    return [for (final t in table) Map<String, dynamic>.from(t)];
  }

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async =>
      const ControllerClockInfo(latitude: 40.0, longitude: -95.0);

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => presets;

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': true,
        'seg': [
          {'id': 0},
          {'id': 1},
        ]
      };

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    saved.add((id: presetId, state: state, name: presetName));
    return savePresetSucceeds;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => true;
}

final _refProvider = Provider<Ref>((ref) => ref);

/// Order of operations across the whole write, so "preset BEFORE timer" and
/// "no timer at all on preset failure" are both observable.
final List<String> _events = [];
List<Map<String, dynamic>>? _pushedIns;

void _seam(CfgPushOutcome outcome) {
  SunriseOffService.cfgPushFn = (repo, payload, ins) async {
    _events.add('timer');
    _pushedIns = ins;
    return outcome;
  };
}

({ProviderContainer container, _FakeService repo}) _harness(
  _FakeService repo, {
  List<ScheduleItem> schedules = const [],
  bool solarFlag = false,
}) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
    calendarLeaseSchedulesProvider.overrideWithValue(schedules),
    calendarLeaseActiveTimersProvider
        .overrideWithValue(const LeaseLedgerEmpty()),
    solarSchedulingEnabledProvider
        .overrideWith((_) => Stream.value(solarFlag)),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

/// A stored preset def that SATISFIES the NGL Off bar (root on:false + segs off
/// + right name), i.e. what a controller that has run a schedule sync holds.
Map<String, dynamic> _goodOffPresetDef() => {
      'n': ScheduleSyncService.kNglOffPresetName,
      'on': false,
      'seg': [
        {'id': 0, 'on': false}
      ],
    };

void main() {
  setUp(() {
    _events.clear();
    _pushedIns = null;
    _seam(CfgPushOutcome.confirmed);
  });

  tearDown(() {
    SunriseOffService.cfgPushFn = (repo, payload, ins) =>
        pushCfgWithVerify(repo: repo, payload: payload, ins: ins);
  });

  group('BUG 1 — arm() must guarantee the NGL Off preset exists', () {
    test('controller WITHOUT preset 2 → preset is saved, THEN the timer arms',
        () async {
      final h = _harness(_FakeService(presets: const {}));

      final result =
          await const SunriseOffService().arm(h.container.read(_refProvider));

      expect(result, SunriseOffWriteResult.confirmed);
      expect(h.repo.saved.map((s) => s.id), contains(2),
          reason: 'a timer firing macro 2 needs preset 2 to exist');
      expect(h.repo.saved.single.name, ScheduleSyncService.kNglOffPresetName);
      expect(_events, contains('timer'));
    });

    test('savePreset FAILS → timer is NOT written, failure returned (never a '
        'false green)', () async {
      final h = _harness(_FakeService(
        presets: const {},
        savePresetSucceeds: false,
      ));

      final result =
          await const SunriseOffService().arm(h.container.read(_refProvider));

      expect(result, SunriseOffWriteResult.presetSaveFailed);
      expect(_events, isEmpty,
          reason: 'NO timer write may happen — an armed timer pointing at a '
              'missing preset is the silent no-op this guard prevents');
      expect(_pushedIns, isNull);
    });

    test('controller that ALREADY has a satisfying preset 2 → no needless '
        'psave (savePreset applies state, so it would blink the strip)',
        () async {
      final h = _harness(_FakeService(
        presets: {2: _goodOffPresetDef()},
      ));

      final result =
          await const SunriseOffService().arm(h.container.read(_refProvider));

      expect(result, SunriseOffWriteResult.confirmed);
      expect(h.repo.saved, isEmpty,
          reason: 'preset already correct — do not disturb the lights');
      expect(_events, contains('timer'));
    });

    test('a legacy segments-only preset 2 (no root on:false) is NOT accepted '
        '— it gets re-saved', () async {
      final h = _harness(_FakeService(presets: {
        2: {
          'n': ScheduleSyncService.kNglOffPresetName,
          'seg': [
            {'id': 0, 'on': false}
          ],
        }
      }));

      await const SunriseOffService().arm(h.container.read(_refProvider));

      expect(h.repo.saved.map((s) => s.id), contains(2),
          reason: 'without root on:false a preset load leaves master ON');
    });

    test('DISARM never touches presets — clearing a slot needs no preset',
        () async {
      final h = _harness(_FakeService(presets: const {}));

      final result = await const SunriseOffService()
          .disarm(h.container.read(_refProvider));

      expect(result, SunriseOffWriteResult.confirmed);
      expect(h.repo.saved, isEmpty);
    });

    test('SINGLE SOURCE OF TRUTH — arm() saves the exact payload schedule sync '
        'seeds', () async {
      final h = _harness(_FakeService(presets: const {}));
      await const SunriseOffService().arm(h.container.read(_refProvider));

      // The same live state the fake getState() returns.
      final expected = ScheduleSyncService.buildNglOffPresetState({
        'on': true,
        'seg': [
          {'id': 0},
          {'id': 1},
        ]
      });

      expect(h.repo.saved.single.state, equals(expected),
          reason: 'arm() and schedule sync must not drift into saving '
              'different "off" states under preset 2');
      expect(expected['on'], false);
      expect(expected['ib'], true,
          reason: 'ib persists root on:false so the load kills master power');
      expect((expected['seg'] as List).length, 2,
          reason: 'off-segs must cover the full strip, not just seg 0');
    });
  });

  group('BUG 2 — the readback is classified by content, never by position',
      () {
    /// "Sunset → 11 PM" as a schedule sync wrote it and the controller reads
    /// it back: the 11 PM OFF in a general slot, the sunset ON as a TH_SUNSET
    /// (254) row; slot 8's placeholder, when nothing owns sunrise.
    List<Map<String, dynamic>> sunsetToElevenTable({bool sunriseOff = false}) =>
        [
          {
            'en': 1,
            'hour': 23,
            'min': 0,
            'macro': 2,
            'dow': 127,
            'start': {'mon': 1, 'day': 1},
            'end': {'mon': 12, 'day': 31},
          },
          sunriseOff
              ? {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127}
              : {'en': 0, 'hour': 255, 'min': 0, 'macro': 0, 'dow': 0},
          {'en': 1, 'hour': 254, 'min': 0, 'macro': 10, 'dow': 127},
        ];

    test('a lone sunset schedule keeps its sunset row when the sunrise-off is '
        'switched ON (the readback used to take it for the sunrise)', () async {
      final h = _harness(
        _FakeService(presets: {2: _goodOffPresetDef()})
          ..table = sunsetToElevenTable(),
        solarFlag: true,
      );

      await const SunriseOffService().arm(h.container.read(_refProvider));

      final ins = _pushedIns!;
      expect(h.repo.timerReads, 1, reason: 'one read, to keep what is held');
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['macro'],
          kSunriseOffMacro);
      expect(ins[ScheduleSyncService.kWledSunsetSlot],
          {'en': 1, 'hour': 254, 'min': 0, 'macro': 10, 'dow': 127},
          reason: 'the sunset ON survives, as a TH_SUNSET row');
      expect(ins.take(8).where((t) => t['macro'] == 2 && t['hour'] == 23),
          hasLength(1), reason: 'its 11 PM OFF survives');
    });

    test('... and when it is switched OFF', () async {
      final h = _harness(
        _FakeService(presets: {2: _goodOffPresetDef()})
          ..table = sunsetToElevenTable(sunriseOff: true),
        solarFlag: true,
      );

      await const SunriseOffService().disarm(h.container.read(_refProvider));

      final ins = _pushedIns!;
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['en'], 0);
      expect(ins[ScheduleSyncService.kWledSunsetSlot]['macro'], 10);
      expect(ins[ScheduleSyncService.kWledSunsetSlot]['hour'], 254);
      expect(ins.take(8).where((t) => t['macro'] == 2 && t['hour'] == 23),
          hasLength(1), reason: 'its 11 PM OFF survives');
    });

    test('general slots never hold a sun row', () async {
      final h = _harness(
        _FakeService(presets: {2: _goodOffPresetDef()})
          ..table = sunsetToElevenTable(),
        solarFlag: true,
      );

      await const SunriseOffService().arm(h.container.read(_refProvider));

      final ins = _pushedIns!;
      expect(ins.length, ScheduleSyncService.kWledTotalTimerSlots);
      for (var i = 0; i < ScheduleSyncService.kMaxWledTimers; i++) {
        expect(ins[i]['hour'], lessThan(24),
            reason: 'general slot $i must never hold a sun row');
      }
    });
  });
}
