// Roofline slice 2 — the sync's design-kind branch, driven through the REAL
// ScheduleSyncService.syncAll against a fake WledService that answers the
// device reads the sync makes (/json/cfg for the bus set, /json/state for the
// live layout, /json/info for the firmware version, /presets.json for what
// the controller holds) and stores a psave the way WLED stores an API-command
// preset (the request minus `o`/`psave`, with `n`).
//
// FAIL-BEFORE (defect-style), on the unchanged sync:
//   • STRAY — a per-pixel payload that reached a schedule by any path other
//     than the editor's My Designs pick (Lumina chat, a calendar intent, an
//     older build; modelled as a schedule with the design's toWledPayload and
//     no preset_kind) was psaved into the 10–25 band as live state. WLED
//     stores no pixels and captures frz:true for such a body, so the timer
//     fires DARK (audit §B.1). Now it is refused at the builder with a plain
//     sentence, not written, not armed.
//   • DESIGN KIND — a schedule carrying an API-command body (`o:true`) was
//     treated like a catalog pattern: `ib:true` was spliced in and the body
//     was psaved on every sync (alwaysWrite) with no layout, firmware, byte or
//     read-back check. Now it goes through the owner's gates, is written only
//     when the stored hash differs, and is read back after the write.
//
// Everything else here is new behaviour: the gate matrix at write time, the
// hash skip, the read-back mismatch, the per-sync count cap, the scope bypass.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
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
    this.firmware = '0.15.4',
    this.arch = 'esp32',
    Map<int, Map<String, dynamic>>? presets,
    this.storeMutation,
  })  : device = {...?presets},
        super('http://mock');

  final WledHardwareConfig? cfg;
  Map<String, dynamic>? state;
  final Map<String, dynamic>? provisionsTo;

  /// What `/json/info` reports as `ver`; null models an unreachable read.
  final String? firmware;

  /// What `/json/info` reports as `arch` ('' models the key missing).
  final String arch;

  /// presets.json as the controller holds it, updated by every psave.
  final Map<int, Map<String, dynamic>> device;

  /// Applied to the stored copy of a psave: models a controller that did not
  /// store what it was sent (a truncated `i`, a stray byte).
  final void Function(Map<String, dynamic> stored)? storeMutation;

  final List<int> savedPresetIds = [];
  final Map<int, Map<String, dynamic>> savedStates = {};
  final List<int> deletedPresetIds = [];
  final List<Map<String, dynamic>> geometryPosts = [];
  Map<String, dynamic>? lastCfg;

  @override
  Future<WledHardwareConfig?> getConfig() async => cfg;

  @override
  Future<Map<String, dynamic>?> getState() async => state;

  @override
  Future<WledInfoResponse?> getInfo() async => firmware == null
      ? null
      : WledInfoResponse(maxseg: 10, arch: arch, ver: firmware!);

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async =>
      {for (final e in device.entries) e.key: Map.of(e.value)};

  /// C2 — scripted outcomes for successive `readPresets` calls (the sync's
  /// opening read, then each read-back attempt): true = readable, false =
  /// unreadable. Exhausted → readable. Every call is counted.
  final List<bool> readOutcomes = [];
  int presetReads = 0;

  @override
  Future<PresetsRead> readPresets() async {
    presetReads++;
    final readable = readOutcomes.isEmpty ? true : readOutcomes.removeAt(0);
    if (!readable) return const PresetsRead.unreadable('scripted');
    if (device.isEmpty) return const PresetsRead.deviceEmpty();
    return PresetsRead.available(await fetchPresets());
  }

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    final ins = (lastCfg?['timers'] as Map?)?['ins'];
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
    // WLED's API-preset store: the request minus o/psave, name defaulted.
    final stored = Map<String, dynamic>.from(state)
      ..remove('o')
      ..remove('psave');
    if (presetName != null && presetName.isNotEmpty) stored['n'] = presetName;
    storeMutation?.call(stored);
    device[presetId] = stored;
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async {
    deletedPresetIds.add(presetId);
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

  /// Macros armed by the last cfg write (the timer rows with a macro > 0).
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

WledHardwareConfig _buses(List<int> lengths) {
  var start = 0;
  final buses = <WledLedBus>[];
  for (var i = 0; i < lengths.length; i++) {
    buses.add(WledLedBus(
        pin: [i], start: start, len: lengths[i], type: 30, order: 1));
    start += lengths[i];
  }
  return WledHardwareConfig(
      totalLeds: start, maxPowerMw: 30000, buses: buses);
}

Map<String, dynamic> _live(List<int> lengths) {
  var start = 0;
  final seg = <Map<String, dynamic>>[];
  for (var i = 0; i < lengths.length; i++) {
    seg.add({
      'id': i,
      'start': start,
      'stop': start + lengths[i],
      'on': true,
      'fx': 0,
      'col': [
        [255, 160, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ],
    });
    start += lengths[i];
  }
  return {'on': true, 'bri': 128, 'seg': seg};
}

final _now = DateTime(2026, 11, 5);
const kRed = [255, 0, 0, 0];
const kBlue = [0, 0, 255, 0];

CustomDesign _design(List<int> lengths, {bool dense = false}) => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 180,
      brightnessStated: true,
      layoutStamp: DesignLayoutStamp(controllerId: 'ctl-a', busLengths: lengths),
      channels: [
        for (var id = 0; id < lengths.length; id++)
          ChannelDesign(
            channelId: id,
            channelName: 'Channel ${id + 1}',
            ledCount: lengths[id],
            colorGroups: dense
                ? [
                    for (var led = 0; led < lengths[id]; led++)
                      LedColorGroup(
                          startLed: led,
                          endLed: led,
                          color: [
                            [255, 0, 0, 0],
                            [0, 255, 0, 0],
                            [0, 0, 255, 0]
                          ][led % 3]),
                  ]
                : [
                    LedColorGroup(
                        startLed: 0, endLed: lengths[id] ~/ 2 - 1, color: kRed),
                    LedColorGroup(
                        startLed: lengths[id] ~/ 2,
                        endLed: lengths[id] - 1,
                        color: kBlue),
                  ],
          ),
      ],
    );

const kThree = [100, 120, 100];
const kName = 'Pattern: Porch stripes';

/// The editor's My Designs pick: the API body stored with design_id and
/// preset_kind.
ScheduleItem _designSchedule(Map<String, dynamic> body,
        {String id = 'sch-design', List<int>? channels}) =>
    ScheduleItem(
      id: id,
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: kName,
      enabled: true,
      wledPayload: body,
      designId: 'd1',
      presetKind: kSchedulePresetKindApi,
      channels: channels,
      controllerId: channels == null ? null : 'ctl-a',
    );

/// Any OTHER path: the design's raw per-pixel payload (toWledPayload) with
/// no preset_kind — Lumina chat, a calendar intent, an older build.
ScheduleItem _straySchedule(CustomDesign d) => ScheduleItem(
      id: 'sch-stray',
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: kName,
      enabled: true,
      wledPayload: d.toWledPayload(),
    );

Map<String, dynamic> _body(List<int> lengths, {bool dense = false}) =>
    buildDesignApiPresetBody(_design(lengths, dense: dense))!;

/// What the controller holds after a successful save of [body] under [name].
Map<String, dynamic> _storedCopy(Map<String, dynamic> body, String name) =>
    (jsonDecode(jsonEncode(body)) as Map<String, dynamic>)
      ..remove('o')
      ..['n'] = name;

void main() {
  setUp(resetRepairAttempts);
  const svc = ScheduleSyncService(
      paceDelay: Duration.zero, readBackSettle: Duration.zero);

  group('stray per-pixel payload (any other path) is refused at the builder',
      () {
    test('not psaved, a plain sentence, not armed', () async {
      final repo = _FakeService(cfg: _buses(kThree), state: _live(kThree));
      final design = _design(kThree);
      expect(design.toWledPayload()['seg'][0].containsKey('i'), isTrue);

      final result = await svc.syncAll(_ref(repo), [_straySchedule(design)]);

      expect(repo.savedStates.keys.where((id) => id >= 10 && id <= 25), isEmpty,
          reason: 'on the unchanged code the picture was psaved into slot 10 '
              'and would fire dark');
      expect(result.presetErrors.join('\n'), contains('"Porch stripes"'));
      expect(result.presetErrors.join('\n'),
          contains('without being checked against your controller'));
      expect(result.presetErrors.join('\n'),
          isNot(contains('has no saved design')),
          reason: 'one sentence, not two');
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty,
          reason: 'no timer points at a design preset');
    });
  });

  group('design kind — all gates pass', () {
    test('the API body is psaved as stored (o:true, bounds, name), then armed',
        () async {
      final repo = _FakeService(cfg: _buses(kThree), state: _live(kThree));
      final body = _body(kThree);

      final result = await svc.syncAll(_ref(repo), [_designSchedule(body)]);

      expect(result.success, isTrue, reason: result.error);
      final saved = repo.savedStates[10];
      expect(saved, isNotNull, reason: 'the design preset took slot 10');
      expect(saved!['o'], isTrue);
      expect(saved['n'], kName);
      expect(saved['seg'], body['seg'],
          reason: 'no scope, no fan-out, no normalisation');
      expect(saved.containsKey('ib'), isFalse,
          reason: 'on the unchanged code the pattern path spliced ib:true in');
      expect(saved['bri'], 180);
      expect(repo.armedMacros, contains(10));
      expect(result.presetErrors, isEmpty);
    });

    test('a channel scope on a design schedule is ignored: the body is saved whole',
        () async {
      final repo = _FakeService(cfg: _buses(kThree), state: _live(kThree));
      final body = _body(kThree);

      await svc.syncAll(_ref(repo), [_designSchedule(body, channels: const [1])]);

      expect(repo.savedStates[10]?['seg'], body['seg']);
    });

    test('a collapsed layout is re-provisioned by the gate first, then saved',
        () async {
      final repo = _FakeService(
        cfg: _buses(kThree),
        state: {
          'on': true,
          'bri': 128,
          'seg': [
            {'id': 0, 'start': 0, 'stop': 320, 'on': true, 'fx': 0}
          ],
        },
        provisionsTo: _live(kThree),
      );
      await svc.syncAll(_ref(repo), [_designSchedule(_body(kThree))]);
      expect(repo.geometryPosts, isNotEmpty);
      expect(repo.savedStates[10], isNotNull);
    });
  });

  group('design kind — flash safety', () {
    test('a stored copy with the same hash is NOT re-written, and still armed',
        () async {
      final body = _body(kThree);
      final repo = _FakeService(
        cfg: _buses(kThree),
        state: _live(kThree),
        presets: {10: _storedCopy(body, kName)},
      );

      final result = await svc.syncAll(_ref(repo),
          [_designSchedule(body).copyWith(presetId: 10)]);

      expect(repo.savedPresetIds, isNot(contains(10)),
          reason: 'equal hash → no psave');
      expect(repo.deletedPresetIds, isNot(contains(10)));
      expect(repo.armedMacros, contains(10));
      expect(result.presetErrors, isEmpty);
    });

    test('a stored copy with a different picture IS re-written once', () async {
      final body = _body(kThree);
      final stale = _storedCopy(body, kName);
      // seg[0..2] are the bounds group; seg[3] is bus 0's paint entry (A1).
      (stale['seg'][3]['i'] as List)[2] = [254, 0, 0, 0];
      final repo = _FakeService(
        cfg: _buses(kThree),
        state: _live(kThree),
        presets: {10: stale},
      );

      await svc.syncAll(_ref(repo), [_designSchedule(body).copyWith(presetId: 10)]);

      expect(repo.savedPresetIds.where((id) => id >= 10 && id <= 25), [10],
          reason: 'one write (the ladder presets 1-5 are written too on an '
              'empty controller, outside the band)');
      expect(repo.armedMacros, contains(10));
    });

    test('a read-back that does not match is a failure: sentence, not armed',
        () async {
      final body = _body(kThree);
      final repo = _FakeService(
        cfg: _buses(kThree),
        state: _live(kThree),
        // Only a painted body is corrupted; the ladder presets have no `i`.
        storeMutation: (stored) {
          // The first PAINT entry (the bounds group carries no `i`, A1).
          final seg = stored['seg'];
          final paint = seg is List
              ? seg.cast<Map>().where((s) => s['i'] is List).firstOrNull
              : null;
          final i = paint?['i'];
          if (i is List) i[2] = [0, 0, 0, 0];
        },
      );

      final result = await svc.syncAll(_ref(repo), [_designSchedule(body)]);

      expect(repo.savedPresetIds.where((id) => id >= 10 && id <= 25), [10],
          reason: 'one write, then the read-back');
      expect(result.presetErrors.join('\n'),
          contains("didn't land on your controller as written"));
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty);
    });
  });

  group('design kind — refusals (nothing written, a plain sentence, not armed)',
      () {
    Future<ScheduleSyncResult> refuse(
      _FakeService repo,
      ScheduleItem item, {
      required String saying,
    }) async {
      final result = await svc.syncAll(_ref(repo), [item]);
      expect(repo.savedStates.keys.where((id) => id >= 10 && id <= 25), isEmpty,
          reason: 'no design preset written');
      expect(result.presetErrors.join('\n'), contains(saying));
      expect(result.presetErrors.join('\n'), contains('"Porch stripes"'));
      expect(result.presetErrors.join('\n'),
          isNot(contains('has no saved design')));
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty);
      return result;
    }

    test('firmware unproven (0.15.1)', () async {
      await refuse(
        _FakeService(cfg: _buses(kThree), state: _live(kThree), firmware: '0.15.1'),
        _designSchedule(_body(kThree)),
        saying: 'WLED 0.15.1',
      );
    });

    test('firmware unreadable — a transient "could not verify" (C1)', () async {
      await refuse(
        _FakeService(cfg: _buses(kThree), state: _live(kThree), firmware: null),
        _designSchedule(_body(kThree)),
        saying: "couldn't check",
      );
    });

    // B4 — the controller model from the same /json/info read; only the
    // classic ESP32 ("esp32", as the spare reported) is proven.
    test('arch unknown (esp32s3): refused as an unproven model', () async {
      final result = await refuse(
        _FakeService(cfg: _buses(kThree), state: _live(kThree), arch: 'esp32s3'),
        _designSchedule(_body(kThree)),
        saying: 'This controller model is not proven for roofline schedules',
      );
      expect(result.presetErrors.join('\n'), contains('esp32s3'));
    });

    test('arch missing from /json/info: refused as an unproven model', () async {
      await refuse(
        _FakeService(cfg: _buses(kThree), state: _live(kThree), arch: ''),
        _designSchedule(_body(kThree)),
        saying: 'This controller model is not proven for roofline schedules',
      );
    });

    test('layout unread (no cfg): never write while the layout is unread — '
        'a transient "could not verify" (C1)', () async {
      await refuse(
        _FakeService(cfg: null, state: _live(kThree)),
        _designSchedule(_body(kThree)),
        saying: "couldn't check",
      );
    });

    test('layout changed: the body is bounded 100/100/100, the buses are 100/120/100',
        () async {
      await refuse(
        _FakeService(cfg: _buses(kThree), state: _live(kThree)),
        _designSchedule(_body(const [100, 100, 100])),
        saying: 'roofline layout no longer matches',
      );
    });

    test('over the byte cap', () async {
      const dense = [150, 150, 150];
      await refuse(
        _FakeService(cfg: _buses(dense), state: _live(dense)),
        _designSchedule(_body(dense, dense: true)),
        saying: '4,000 bytes',
      );
    });

    test('malformed stored body (o:true but no bounds)', () async {
      final body = _body(kThree);
      for (final s in body['seg'] as List) {
        (s as Map).remove('start');
      }
      await refuse(
        _FakeService(cfg: _buses(kThree), state: _live(kThree)),
        _designSchedule(body),
        saying: "can't be saved to your controller as it is stored",
      );
    });

    test('a fifth painted design in one account is refused; four are written',
        () async {
      final repo = _FakeService(cfg: _buses(kThree), state: _live(kThree));
      final body = _body(kThree);
      final five = [
        for (var k = 0; k < 5; k++) _designSchedule(body, id: 'sch-$k'),
      ];

      final result = await svc.syncAll(_ref(repo), five);

      expect(repo.savedStates.keys.where((id) => id >= 10 && id <= 25).length, 4);
      expect(result.presetErrors.join('\n'), contains('4 painted designs'));
    });
  });

  // C1 — a device read that fails is TRANSIENT: the slot, its stored copy,
  // its hash record and its timer row stay exactly as they were, no repair
  // attempt is counted, and the owner reads "checked again on the next
  // sync". Only a schedule that is gone, or a PERSISTENT refusal, purges.
  group('C1 — transient failures leave a landed design alone', () {
    /// A good sync first: slot 10 written and armed; the controller's
    /// presets.json then holds the stored copy.
    Future<Map<int, Map<String, dynamic>>> landed() async {
      final first = _FakeService(cfg: _buses(kThree), state: _live(kThree));
      final r = await svc.syncAll(_ref(first), [_designSchedule(_body(kThree))]);
      expect(r.presetErrors, isEmpty);
      expect(first.device.containsKey(10), isTrue);
      expect(first.armedMacros, contains(10));
      return first.device;
    }

    test('an info timeout on the next sync: no pdel, the timer row stays, '
        '"checked again", no repair attempt', () async {
      final device = await landed();
      final attemptsBefore = await repairAttempts.attempts(10);
      final repo = _FakeService(
          cfg: _buses(kThree), state: _live(kThree), firmware: null, presets: device);

      final result = await svc.syncAll(
          _ref(repo), [_designSchedule(_body(kThree)).copyWith(presetId: 10)]);

      expect(repo.deletedPresetIds, isNot(contains(10)),
          reason: 'on b4b09f2 the refused design left the saved set and the '
              'orphan purge sent pdel for its slot');
      expect(repo.device.containsKey(10), isTrue);
      expect(repo.savedPresetIds, isNot(contains(10)), reason: 'no rewrite');
      expect(repo.armedMacros, contains(10), reason: 'the timer row stays');
      expect(result.presetErrors.join('\n'),
          contains('checked again on the next sync'));
      expect(await repairAttempts.attempts(10), attemptsBefore,
          reason: 'a transient failure is not a repair attempt');
    });

    test('an unreadable cfg (layout unread) on the next sync: same', () async {
      final device = await landed();
      final repo = _FakeService(cfg: null, state: _live(kThree), presets: device);

      final result = await svc.syncAll(
          _ref(repo), [_designSchedule(_body(kThree)).copyWith(presetId: 10)]);

      expect(repo.deletedPresetIds, isNot(contains(10)));
      expect(repo.armedMacros, contains(10));
      expect(result.presetErrors.join('\n'), contains("couldn't check"));
    });

    test('a transient failure before anything landed: not armed, nothing to '
        'purge, no repair attempt', () async {
      final repo =
          _FakeService(cfg: _buses(kThree), state: _live(kThree), firmware: null);

      final result = await svc.syncAll(_ref(repo), [_designSchedule(_body(kThree))]);

      expect(repo.savedStates.keys.where((id) => id >= 10 && id <= 25), isEmpty);
      expect(repo.deletedPresetIds, isEmpty);
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty);
      expect(result.presetErrors.join('\n'), contains("couldn't check"));
      expect(await repairAttempts.attempts(10), 0);
    });

    test('a deleted schedule still purges its slot', () async {
      final device = await landed();
      final repo =
          _FakeService(cfg: _buses(kThree), state: _live(kThree), presets: device);

      await svc.syncAll(_ref(repo), const []);

      expect(repo.deletedPresetIds, contains(10));
    });

    test('a persistent refusal (layout changed) still refuses and purges',
        () async {
      final device = await landed(); // the body is bounded 100/120/100
      const other = [100, 100, 100];
      final repo =
          _FakeService(cfg: _buses(other), state: _live(other), presets: device);

      final result = await svc.syncAll(
          _ref(repo), [_designSchedule(_body(kThree)).copyWith(presetId: 10)]);

      expect(result.presetErrors.join('\n'),
          contains('roofline layout no longer matches'));
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty);
      expect(repo.deletedPresetIds, contains(10));
    });
  });

  // C2 — the read-back after a write: an unreadable presets.json gets one
  // retry after a settle; unreadable twice is "written, not verified" (not
  // armed, not purged, no attempt counted); only a READABLE mismatch advances
  // the non-convergence counter. The scripted outcomes cover the sync's
  // opening read first, then each read-back attempt.
  group('C2 — the read-back after a design preset write', () {
    test('unreadable, then readable on the retry: landed, armed, no attempt',
        () async {
      final repo = _FakeService(cfg: _buses(kThree), state: _live(kThree))
        ..readOutcomes.addAll([true, false, true]);

      final result = await svc.syncAll(_ref(repo), [_designSchedule(_body(kThree))]);

      expect(repo.savedPresetIds, contains(10), reason: 'one write');
      expect(repo.presetReads, 3, reason: 'opening read, failed read-back, retry');
      expect(repo.armedMacros, contains(10));
      expect(result.presetErrors, isEmpty);
      expect(await repairAttempts.attempts(10), 0,
          reason: 'landed clears the counter');
    });

    test('unreadable twice: written, not verified — not armed, not purged, '
        'no attempt; the next sync arms it without rewriting', () async {
      final body = _body(kThree);
      final stale = _storedCopy(body, kName);
      (stale['seg'][3]['i'] as List)[2] = [254, 0, 0, 0];
      final repo = _FakeService(
        cfg: _buses(kThree),
        state: _live(kThree),
        presets: {10: stale},
      )..readOutcomes.addAll([true, false, false]);

      final first = await svc.syncAll(
          _ref(repo), [_designSchedule(body).copyWith(presetId: 10)]);

      expect(repo.savedPresetIds.where((id) => id >= 10 && id <= 25), [10],
          reason: 'written once (the ladder presets 1-5 are outside the band)');
      expect(repo.presetReads, 3);
      expect(repo.deletedPresetIds, isNot(contains(10)),
          reason: 'a slot written this sync is never purged');
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty,
          reason: 'not armed until a later sync reads it back');
      expect(first.presetErrors.join('\n'),
          contains("couldn't be read back yet"));
      expect(first.presetErrors.join('\n'),
          isNot(contains("didn't land on your controller as written")));
      expect(await repairAttempts.attempts(10), 0,
          reason: 'unreadable is not a repair attempt');

      // The device now holds the written copy; the next sync reads it.
      final next = _FakeService(
          cfg: _buses(kThree), state: _live(kThree), presets: repo.device);
      final second = await svc.syncAll(
          _ref(next), [_designSchedule(body).copyWith(presetId: 10)]);

      expect(next.savedPresetIds, isNot(contains(10)), reason: 'no rewrite');
      expect(next.armedMacros, contains(10));
      expect(second.presetErrors, isEmpty);
    });

    test('a readable mismatch advances the counter and is not armed', () async {
      final repo = _FakeService(
        cfg: _buses(kThree),
        state: _live(kThree),
        storeMutation: (stored) {
          final seg = stored['seg'];
          final paint = seg is List
              ? seg.cast<Map>().where((s) => s['i'] is List).firstOrNull
              : null;
          final i = paint?['i'];
          if (i is List) i[2] = [0, 0, 0, 0];
        },
      );

      final result = await svc.syncAll(_ref(repo), [_designSchedule(_body(kThree))]);

      expect(repo.presetReads, 2, reason: 'opening read, one read-back');
      expect(result.presetErrors.join('\n'),
          contains("didn't land on your controller as written"));
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty);
      expect(await repairAttempts.attempts(10), 1,
          reason: 'the one outcome that counts');
    });
  });
}
