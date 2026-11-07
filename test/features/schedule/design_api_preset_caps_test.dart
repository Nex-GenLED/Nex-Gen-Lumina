// Roofline slice 2, B3 — both caps (elements, the limit the firmware
// enforces; bytes, the backstop) judged on the exact wire body at compose
// time (the pick verdict) and at write time (the sync), one sentence, never
// simplified. Boundary tests at 1,700 / 1,701 elements and 6,000 / 6,001
// bytes through the shared pure question and at the sync's write gate; the
// pick verdict and the sync refusing a dense design with the same sentence;
// and the body the bench stored and fired (1,647 elements, 5,075 B on the
// wire) admitted by both gates, with the same shape at 1,701 refused.

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
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

const kName = 'Pattern: Porch stripes';

/// A one-bus bounds-first body whose paint `i` array is padded with scalar
/// entries (one element each) until the WIRE body counts exactly [elements].
Map<String, dynamic> bodyWithElements(int elements) {
  final i = <dynamic>[0, 100, [255, 0, 0, 0]];
  final body = <String, dynamic>{
    'o': true,
    'on': true,
    'bri': 180,
    'seg': [
      {'id': 0, 'start': 0, 'stop': 100},
      {
        'id': 0,
        'on': true,
        'fx': 0,
        'grp': 1,
        'spc': 0,
        'pal': 0,
        'col': [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ],
        'i': i,
      },
    ],
  };
  var n = designApiPresetWireElements(body, presetId: 10, presetName: kName);
  expect(n, lessThan(elements), reason: 'the base body is small');
  while (n < elements) {
    i.add(1);
    n++;
  }
  expect(designApiPresetWireElements(body, presetId: 10, presetName: kName),
      elements);
  return body;
}

/// The name under which the bench saved its step-8 body to slot 10.
const kBenchCapName = 'Pattern: Bench cap 1650';

/// The bench's step-8 body (bench-s2-results/results.md, 2026-11-06, the
/// spare .179, WLED 0.15.4, classic ESP32): the TYPICAL shape — three buses
/// of 100, the bounds group, then one paint entry per bus whose `i` is a
/// base run over the whole bus followed by single-LED accents with two-digit
/// indices and three-digit colours — grown one accent at a time until the
/// wire body (slot 10, [kBenchCapName]) counts at least [targetElements],
/// backing off one accent when it overshoots, exactly as the bench's
/// generator did (tools/genbf.py, `elements:1650`: 256 accents, 1,647
/// elements, 5,075 B on the wire). The spare stored that body (5,055 B) and
/// fired it by timer from master-off with 0/100 LEDs differing on every bus.
Map<String, dynamic> benchTypicalBody({int targetElements = 1650}) {
  const lens = [100, 100, 100];
  const base = [
    [60, 0, 0, 0],
    [0, 60, 0, 0],
    [0, 0, 60, 0],
  ];
  List<int> accent(int n) =>
      [(n * 37) % 200 + 30, (n * 53) % 200 + 30, (n * 71) % 200 + 30, 0];
  final paints = [
    for (var b = 0; b < 3; b++)
      <String, dynamic>{
        'id': b,
        'on': true,
        'fx': 0,
        'grp': 1,
        'spc': 0,
        'pal': 0,
        'col': [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ],
        'i': <dynamic>[0, lens[b], base[b]],
      },
  ];
  final body = <String, dynamic>{
    'o': true,
    'on': true,
    'bri': 180,
    'seg': <Map<String, dynamic>>[
      for (var b = 0; b < 3; b++)
        {'id': b, 'start': 100 * b, 'stop': 100 * (b + 1)},
      ...paints,
    ],
  };
  int measure() => designApiPresetWireElements(body,
      presetId: 10, presetName: kBenchCapName);
  var n = 0;
  while (measure() < targetElements) {
    final b = n % 3;
    (paints[b]['i'] as List).addAll([(n ~/ 3 * 7) % lens[b], accent(n)]);
    n++;
  }
  if (measure() > targetElements) {
    final i = paints[(n - 1) % 3]['i'] as List;
    i.removeRange(i.length - 2, i.length);
  }
  return body;
}

/// A design schedule carrying [body] under [name] (the editor's My Designs
/// pick: the API body stored with design_id and preset_kind).
ScheduleItem designSchedule(Map<String, dynamic> body, {String name = kName}) =>
    ScheduleItem(
      id: 'sch-design',
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: name,
      enabled: true,
      wledPayload: body,
      designId: 'd',
      presetKind: kSchedulePresetKindApi,
    );

Iterable<int> scheduleBand(Iterable<int> ids) => ids
    .where((id) => id >= kFirstSchedulePresetId && id <= kLastSchedulePresetId);

void main() {
  setUp(resetRepairAttempts);
  const svc = ScheduleSyncService(
      paceDelay: Duration.zero, readBackSettle: Duration.zero);

  group('designApiPresetCapRefusal — the element boundary', () {
    test('1,700 elements is allowed', () {
      final body = bodyWithElements(kDesignApiPresetMaxElements);
      expect(
          designApiPresetCapRefusal(body,
              presetId: 10, presetName: kName, designName: 'Porch stripes'),
          isNull);
    });

    test('1,701 elements is refused as too detailed, naming both limits', () {
      final body = bodyWithElements(kDesignApiPresetMaxElements + 1);
      final msg = designApiPresetCapRefusal(body,
          presetId: 10, presetName: kName, designName: 'Porch stripes');
      expect(msg, isNotNull);
      expect(msg, contains('too detailed for your controller'));
      expect(msg, contains('1,701 details'));
      expect(msg, contains('1,700 details'));
      expect(msg, contains('6,000 bytes'));
      expect(msg, contains('simplify'));
      expect(
          designApiPresetWireBytes(body, presetId: 10, presetName: kName),
          lessThan(kDesignApiPresetMaxBytes),
          reason: 'this body is under the byte cap: the element cap alone refused');
    });
  });

  group('designApiPresetCapRefusal — the byte boundary', () {
    test('6,000 bytes is allowed; 6,001 is refused', () {
      final body = bodyWithElements(100);
      final base = designApiPresetWireBytes(body, presetId: 10, presetName: '');
      final pad = 'x' * (kDesignApiPresetMaxBytes - base);
      expect(designApiPresetWireBytes(body, presetId: 10, presetName: pad),
          kDesignApiPresetMaxBytes);
      expect(
          designApiPresetCapRefusal(body,
              presetId: 10, presetName: pad, designName: 'Porch stripes'),
          isNull);
      final over = designApiPresetCapRefusal(body,
          presetId: 10, presetName: '${pad}y', designName: 'Porch stripes');
      expect(over, isNotNull);
      expect(over, contains('6,001 bytes'));
      expect(over, contains('too detailed for your controller'));
    });
  });

  group("the bench's typical body — 1,647 elements, 5,075 B (step 8, 2026-11-06)",
      () {
    test('reproduces the record exactly, and is a well-formed bounds-first body',
        () {
      final body = benchTypicalBody();
      expect(
          designApiPresetWireElements(body,
              presetId: 10, presetName: kBenchCapName),
          1647);
      expect(
          designApiPresetWireBytes(body, presetId: 10, presetName: kBenchCapName),
          5075);
      expect(designApiPresetBodyProblem(body), isNull);
    });

    test('compose time: the shared question admits it at the pick-time slot '
        'and at slot 10 — the former 4,000-byte cap would have refused it', () {
      final body = benchTypicalBody();
      for (final slot in [kLastSchedulePresetId, 10]) {
        expect(
            designApiPresetCapRefusal(body,
                presetId: slot,
                presetName: kBenchCapName,
                designName: 'Bench cap 1650'),
            isNull,
            reason: 'slot $slot');
      }
      expect(
          designApiPresetWireBytes(body,
              presetId: kLastSchedulePresetId, presetName: kBenchCapName),
          greaterThan(4000));
    });

    test('write time: the sync writes it to slot 10, reads it back and arms it',
        () async {
      final repo = _FakeService(busLengths: const [100, 100, 100]);
      final result = await svc.syncAll(
          _ref(repo), [designSchedule(benchTypicalBody(), name: kBenchCapName)]);
      expect(scheduleBand(repo.savedStates.keys), [10]);
      expect(repo.device[10]?['n'], kBenchCapName);
      expect(result.presetErrors.join('\n'), isNot(contains('too detailed')));
      expect(repo.armedMacros, contains(10));
    });

    test('grown to 1,701 elements the same shape is refused by both gates — '
        'on the element cap alone, under the byte cap', () async {
      final body =
          benchTypicalBody(targetElements: kDesignApiPresetMaxElements + 1);
      expect(
          designApiPresetWireElements(body,
              presetId: 10, presetName: kBenchCapName),
          1701);
      expect(
          designApiPresetWireBytes(body, presetId: 10, presetName: kBenchCapName),
          lessThanOrEqualTo(kDesignApiPresetMaxBytes));
      final msg = designApiPresetCapRefusal(body,
          presetId: kLastSchedulePresetId,
          presetName: kBenchCapName,
          designName: 'Bench cap 1650');
      expect(msg, contains('1,701 details'));

      final repo = _FakeService(busLengths: const [100, 100, 100]);
      final result = await svc
          .syncAll(_ref(repo), [designSchedule(body, name: kBenchCapName)]);
      expect(scheduleBand(repo.savedStates.keys), isEmpty);
      expect(result.presetErrors.join('\n'), contains('1,701 details'));
      expect(scheduleBand(repo.armedMacros), isEmpty);
    });
  });

  group('compose time — the pick verdict', () {
    final now = DateTime(2026, 11, 6);
    const live = [
      DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 150, gpioPin: 2),
      DeviceChannel(id: 1, name: 'Channel 2', start: 150, stop: 300, gpioPin: 14),
      DeviceChannel(id: 2, name: 'Channel 3', start: 300, stop: 450, gpioPin: 16),
    ];
    CustomDesign dense() => CustomDesign(
          id: 'd',
          name: 'Porch stripes',
          ownerId: 'u',
          createdAt: now,
          updatedAt: now,
          perPixel: true,
          brightness: 180,
          brightnessStated: true,
          layoutStamp: const DesignLayoutStamp(
              controllerId: 'ctl-a', busLengths: [150, 150, 150]),
          channels: [
            for (var id = 0; id < 3; id++)
              ChannelDesign(
                  channelId: id,
                  channelName: 'Channel ${id + 1}',
                  ledCount: 150,
                  colorGroups: [
                    for (var led = 0; led < 150; led++)
                      LedColorGroup(
                          startLed: led,
                          endLed: led,
                          color: const [
                            [255, 0, 0, 0],
                            [0, 255, 0, 0],
                            [0, 0, 255, 0]
                          ][led % 3]),
                  ]),
          ],
        );

    test('a dense design is refused with the too-detailed sentence and offers '
        'the editor; nothing is stored', () {
      final v = designScheduleEligibility(
        design: dense(),
        onLan: true,
        liveChannels: live,
        liveControllerId: 'ctl-a',
        firmwareVersion: '0.15.4',
        architecture: 'esp32',
      );
      expect(v.verdict, DesignScheduleVerdict.tooLarge);
      expect(v.offersEditor, isTrue);
      expect(v.body, isNull);
      expect(v.message, contains('too detailed for your controller'));
      expect(v.message, contains('1,700 details'));
      expect(v.message, contains('6,000 bytes'));
      expect(v.message, isNot(contains('simplified')),
          reason: 'never simplified for the customer');
    });
  });

  group('write time — the sync', () {
    test('a stored body over the element cap is refused by the sync with the '
        'same sentence, not written, not armed', () async {
      final repo = _FakeService();
      final body = bodyWithElements(kDesignApiPresetMaxElements + 1);
      final result = await svc.syncAll(_ref(repo), [designSchedule(body)]);
      expect(scheduleBand(repo.savedStates.keys), isEmpty);
      expect(result.presetErrors.join('\n'),
          contains('too detailed for your controller'));
      expect(result.presetErrors.join('\n'), contains('1,701 details'));
      expect(scheduleBand(repo.armedMacros), isEmpty);
    });

    test('exactly 6,000 bytes is written and armed; 6,001 is refused with the '
        'sentence, not written, not armed', () async {
      // The sync measures the wire body with the slot it assigns (10) and
      // the schedule's own label as the preset name; grow the label until
      // the body lands exactly on the cap.
      final body = bodyWithElements(120);
      final base = designApiPresetWireBytes(body, presetId: 10, presetName: '');
      const prefix = 'Pattern: ';
      final at = '$prefix${'x' * (kDesignApiPresetMaxBytes - base - prefix.length)}';
      expect(designApiPresetWireBytes(body, presetId: 10, presetName: at),
          kDesignApiPresetMaxBytes);

      final okRepo = _FakeService();
      final ok = await svc.syncAll(_ref(okRepo), [designSchedule(body, name: at)]);
      expect(scheduleBand(okRepo.savedStates.keys), [10]);
      expect(ok.presetErrors.join('\n'), isNot(contains('too detailed')));
      expect(okRepo.armedMacros, contains(10));

      final overRepo = _FakeService();
      final over = await svc
          .syncAll(_ref(overRepo), [designSchedule(body, name: '${at}y')]);
      expect(scheduleBand(overRepo.savedStates.keys), isEmpty);
      expect(over.presetErrors.join('\n'), contains('6,001 bytes'));
      expect(over.presetErrors.join('\n'),
          contains('too detailed for your controller'));
      expect(scheduleBand(overRepo.armedMacros), isEmpty);
    });
  });
}

/// A direct-LAN controller with [busLengths] laid end to end, a live state of
/// one segment per bus, a proven firmware and model, and a presets.json
/// store that holds what each psave sent (minus `o`/`psave`, with `n`) so the
/// sync's read-back finds the copy it wrote.
class _FakeService extends WledService {
  _FakeService({this.busLengths = const [100]}) : super('http://mock');

  final List<int> busLengths;
  final Map<int, Map<String, dynamic>> savedStates = {};
  final Map<int, Map<String, dynamic>> device = {};
  Map<String, dynamic>? lastCfg;

  @override
  Future<WledHardwareConfig?> getConfig() async {
    var start = 0;
    final buses = <WledLedBus>[];
    for (var i = 0; i < busLengths.length; i++) {
      buses.add(WledLedBus(
          pin: [i], start: start, len: busLengths[i], type: 30, order: 1));
      start += busLengths[i];
    }
    return WledHardwareConfig(totalLeds: start, maxPowerMw: 30000, buses: buses);
  }

  @override
  Future<Map<String, dynamic>?> getState() async {
    var start = 0;
    final seg = <Map<String, dynamic>>[];
    for (var i = 0; i < busLengths.length; i++) {
      seg.add({
        'id': i,
        'start': start,
        'stop': start + busLengths[i],
        'on': true,
        'fx': 0,
      });
      start += busLengths[i];
    }
    return {'on': true, 'bri': 128, 'seg': seg};
  }

  @override
  Future<WledInfoResponse?> getInfo() async =>
      const WledInfoResponse(maxseg: 10, arch: 'esp32', ver: '0.15.4');

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async =>
      {for (final e in device.entries) e.key: Map.of(e.value)};

  @override
  Future<PresetsRead> readPresets() async {
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
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    savedStates[presetId] = Map<String, dynamic>.from(state);
    final stored = Map<String, dynamic>.from(state)
      ..remove('o')
      ..remove('psave');
    if (presetName != null && presetName.isNotEmpty) stored['n'] = presetName;
    device[presetId] = stored;
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
