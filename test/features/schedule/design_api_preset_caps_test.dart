// Roofline slice 2, B3 — both caps (elements, the limit the firmware
// enforces; bytes, the sanity limit) judged on the exact wire body at compose
// time (the pick verdict) and at write time (the sync), one sentence, never
// simplified. Boundary tests at 1,700 / 1,701 elements and 4,000 / 4,001
// bytes through the shared pure question, plus the pick verdict and the sync
// refusing a dense design with the same sentence.

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

void main() {
  setUp(resetRepairAttempts);

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
      expect(msg, contains('4,000 bytes'));
      expect(msg, contains('simplify'));
      expect(
          designApiPresetWireBytes(body, presetId: 10, presetName: kName),
          lessThan(kDesignApiPresetMaxBytes),
          reason: 'this body is under the byte cap: the element cap alone refused');
    });
  });

  group('designApiPresetCapRefusal — the byte boundary', () {
    test('4,000 bytes is allowed; 4,001 is refused', () {
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
      expect(over, contains('4,001 bytes'));
      expect(over, contains('too detailed for your controller'));
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
      expect(v.message, contains('4,000 bytes'));
      expect(v.message, isNot(contains('simplified')),
          reason: 'never simplified for the customer');
    });
  });

  group('write time — the sync', () {
    test('a stored body over the element cap is refused by the sync with the '
        'same sentence, not written, not armed', () async {
      final repo = _FakeService();
      final body = bodyWithElements(kDesignApiPresetMaxElements + 1);
      final item = ScheduleItem(
        id: 'sch-dense',
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
        actionLabel: kName,
        enabled: true,
        wledPayload: body,
        designId: 'd',
        presetKind: kSchedulePresetKindApi,
      );
      const svc = ScheduleSyncService(paceDelay: Duration.zero);
      final result = await svc.syncAll(_ref(repo), [item]);
      expect(repo.savedStates.keys.where((id) => id >= 10 && id <= 25), isEmpty);
      expect(result.presetErrors.join('\n'),
          contains('too detailed for your controller'));
      expect(result.presetErrors.join('\n'), contains('1,701 details'));
      expect(repo.armedMacros.where((m) => m >= 10 && m <= 25), isEmpty);
    });
  });
}

class _FakeService extends WledService {
  _FakeService() : super('http://mock');

  final Map<int, Map<String, dynamic>> savedStates = {};
  Map<String, dynamic>? lastCfg;

  @override
  Future<WledHardwareConfig?> getConfig() async => WledHardwareConfig(
        totalLeds: 100,
        maxPowerMw: 30000,
        buses: [
          WledLedBus(pin: const [2], start: 0, len: 100, type: 30, order: 1),
        ],
      );

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': true,
        'bri': 128,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 100, 'on': true, 'fx': 0}
        ],
      };

  @override
  Future<WledInfoResponse?> getInfo() async =>
      const WledInfoResponse(maxseg: 10, arch: 'esp32', ver: '0.15.4');

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => {};

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
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async => true;

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
