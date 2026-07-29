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
// BUG 2 — _readModifyWrite indexed the /json/cfg `ins` response positionally.
//   WLED COMPACTS that array (omits fully-empty timers), verified on
//   192.168.1.150 (0.15.1 / vid 2507300): 8 empty general slots + 2 solar slots
//   came back as TWO entries. Positional indexing copied the solar entries into
//   general slots 0/1 and dropped the sunrise slot.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

class _FakeService extends WledService {
  _FakeService({
    this.existing,
    this.presets = const {},
    this.savePresetSucceeds = true,
  }) : super('http://mock');

  List<Map<String, dynamic>>? existing;
  Map<int, Map<String, dynamic>> presets;
  bool savePresetSucceeds;

  final List<({int id, Map<String, dynamic> state, String? name})> saved = [];

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async => existing;

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

({ProviderContainer container, _FakeService repo}) _harness(_FakeService repo) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
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

Map<String, dynamic> _solarEntry({int macro = 0}) => {
      'en': 1,
      'hour': ScheduleSyncService.kWledSolarHourMarker,
      'min': 0,
      'macro': macro,
      'dow': 127,
    };

Map<String, dynamic> _clockEntry(int macro, int hour) =>
    {'en': 1, 'hour': hour, 'min': 0, 'macro': macro, 'dow': 127};

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
      final h = _harness(_FakeService(existing: [], presets: const {}));

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
        existing: [],
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
        existing: [],
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
      final h = _harness(_FakeService(existing: [], presets: {
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
      final h = _harness(_FakeService(existing: [], presets: const {}));

      final result = await const SunriseOffService()
          .disarm(h.container.read(_refProvider));

      expect(result, SunriseOffWriteResult.confirmed);
      expect(h.repo.saved, isEmpty);
    });

    test('SINGLE SOURCE OF TRUTH — arm() saves the exact payload schedule sync '
        'seeds', () async {
      final h = _harness(_FakeService(existing: [], presets: const {}));
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

  group('BUG 2 — compacted ins response must still target slot 8', () {
    test('COMPACTED response (2 solar entries only, as .150 returns) → solar '
        'entries are NOT copied into general slots, sunrise-off lands at 8',
        () async {
      // Exactly what 192.168.1.150 returns: 8 empty general slots omitted.
      final h = _harness(_FakeService(
        existing: [_solarEntry(), _solarEntry()],
        presets: {2: _goodOffPresetDef()},
      ));

      await const SunriseOffService().arm(h.container.read(_refProvider));

      final ins = _pushedIns!;
      expect(ins.length, ScheduleSyncService.kWledTotalTimerSlots);
      // The positional bug put hour:255 entries in slots 0 and 1.
      for (var i = 0; i < ScheduleSyncService.kMaxWledTimers; i++) {
        expect(ins[i]['hour'], isNot(ScheduleSyncService.kWledSolarHourMarker),
            reason: 'general slot $i must never hold a solar entry — that is '
                'the compaction bug');
      }
      final slot8 = ins[ScheduleSyncService.kWledSunriseSlot];
      expect(slot8['macro'], kSunriseOffMacro);
      expect(slot8['en'], 1);
      expect(slot8['hour'], ScheduleSyncService.kWledSolarHourMarker);
    });

    test('COMPACTED response with real clock timers keeps them in slots 0-n '
        'and still lands slot 8', () async {
      final h = _harness(_FakeService(
        existing: [
          _clockEntry(10, 19), // a schedule
          _clockEntry(30, 18), // a lease
          _solarEntry(), // slot 8
          _solarEntry(macro: 7), // slot 9 (sunset)
        ],
        presets: {2: _goodOffPresetDef()},
      ));

      await const SunriseOffService().arm(h.container.read(_refProvider));

      final ins = _pushedIns!;
      expect(ins[0]['macro'], 10, reason: 'schedule preserved');
      expect(ins[1]['macro'], 30, reason: 'lease preserved (P0-3)');
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['macro'],
          kSunriseOffMacro);
      expect(ins[ScheduleSyncService.kWledSunsetSlot]['macro'], 7,
          reason: 'the existing sunset must survive');
    });

    test('FULL positional 10-entry response is handled identically', () async {
      final stub = ScheduleSyncService.disabledTimerStub();
      final h = _harness(_FakeService(
        existing: [
          _clockEntry(10, 19),
          for (var i = 0; i < 7; i++) Map<String, dynamic>.from(stub),
          _solarEntry(),
          _solarEntry(macro: 7),
        ],
        presets: {2: _goodOffPresetDef()},
      ));

      await const SunriseOffService().arm(h.container.read(_refProvider));

      final ins = _pushedIns!;
      expect(ins.length, 10);
      expect(ins[0]['macro'], 10);
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['macro'],
          kSunriseOffMacro);
      expect(ins[ScheduleSyncService.kWledSunsetSlot]['macro'], 7);
    });

    group('partitionTimerIns', () {
      test('classifies by the solar marker, not by array position', () {
        final p = SunriseOffService.partitionTimerIns([
          _solarEntry(macro: 4),
          _solarEntry(macro: 5),
        ]);
        expect(p.general, isEmpty,
            reason: 'both entries are solar — neither is a general timer');
        expect(p.sunrise!['macro'], 4, reason: 'first 255-entry is sunrise');
        expect(p.sunset!['macro'], 5, reason: 'second 255-entry is sunset');
      });

      test('null / empty response yields nothing', () {
        for (final input in [null, <Map<String, dynamic>>[]]) {
          final p = SunriseOffService.partitionTimerIns(input);
          expect(p.general, isEmpty);
          expect(p.sunrise, isNull);
          expect(p.sunset, isNull);
        }
      });

      test('general timers are capped at the 8-slot table', () {
        final p = SunriseOffService.partitionTimerIns(
            [for (var i = 0; i < 12; i++) _clockEntry(i, 6)]);
        expect(p.general.length, ScheduleSyncService.kMaxWledTimers);
      });
    });
  });
}
