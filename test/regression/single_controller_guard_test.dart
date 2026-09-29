// GUARD — an account with exactly ONE controller must not notice build +110's
// controller-targeting work.
//
// Drives the real apply, preset and schedule paths against a recording
// controller and compares everything that was sent, and where it was sent,
// with a golden captured from the release commit these changes started from.
//
// TWO LAYERS are recorded for every write:
//
//   boundary — the arguments handed to the repository. Must be byte-identical
//              to the golden. This is the controller-targeting guarantee.
//   wire     — the same payload after the shared wire pipeline
//              (normalize → participation expansion; for a preset, normalize →
//              freeze guard). Must equal the golden once the fields listed in
//              [_kCompletedKeys] are set aside — those are the segment fields
//              build +110 deliberately began stating (see
//              lib/shared/wled_segment_defaults.dart), and nothing else may
//              differ.
//
// REGENERATING THE GOLDEN is a deliberate act, done at the commit you want to
// compare against:
//
//   LUMINA_WRITE_GOLDEN=1 flutter test test/regression/single_controller_guard_test.dart
//
// This file uses only what exists at that commit, so it runs there unchanged.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/favorites/favorite_apply.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _goldenPath = 'test/regression/golden/single_controller_baseline.json';

/// Segment fields build +110 began stating at the wire. Set aside — and only
/// where the golden does not already carry them — when comparing the wire
/// layer.
const _kCompletedKeys = ['c1', 'c2', 'c3', 'o1', 'o2', 'o3', 'bri', 'sx', 'ix', 'pal'];

// Documentation address and a plain record id: nothing here is a real device.
const _ip = '192.0.2.10';
const _controllerId = 'controller-one';

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];

dynamic _copy(Object? v) => jsonDecode(jsonEncode(v));

/// A controller that records every write, at both layers. Subclasses
/// [WledService] on the simulated host because schedule sync reads presets
/// only from a [WledService].
class _RecordingController extends WledService {
  _RecordingController() : super('http://mock');

  final List<Map<String, dynamic>> log = [];
  Map<String, dynamic>? _lastCfg;

  Future<Map<String, dynamic>> _wire(Map<String, dynamic> payload) async =>
      expandForParticipation(
        normalizeWledPayload(payload),
        await getCachedParticipatingChannelsForGuard(),
      );

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    log.add({
      'call': 'applyJson',
      'boundary': _copy(payload),
      'wire': _copy(await _wire(payload)),
    });
    return true;
  }

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async {
    log.add({
      'call': 'setState',
      'boundary': {
        'on': on,
        'brightness': brightness,
        'speed': speed,
        // ignore: deprecated_member_use
        'color': color?.value,
        'white': white,
        'forceRgbwZeroWhite': forceRgbwZeroWhite,
      },
    });
    return true;
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async {
    log.add({'call': 'applyGeometryJson', 'boundary': _copy(payload)});
    return true;
  }

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    log.add({
      'call': 'savePreset',
      'boundary': {
        'presetId': presetId,
        'presetName': presetName,
        'state': _copy(state),
      },
      'wire': _copy(ensurePsaveClearsFreeze(
        normalizeWledPayload(state),
        await getCachedParticipatingChannelsForGuard(),
      )),
    });
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async {
    log.add({'call': 'deletePreset', 'boundary': presetId});
    return true;
  }

  @override
  Future<bool> loadPreset(int presetId) async {
    log.add({'call': 'loadPreset', 'boundary': presetId});
    return true;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    _lastCfg = cfg;
    log.add({'call': 'applyConfig', 'boundary': _copy(cfg)});
    return true;
  }

  // ── Reads: a healthy, empty two-channel controller ──────────────────────
  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => const {};

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    final ins = (_lastCfg?['timers'] as Map?)?['ins'];
    if (ins is List) {
      return ins
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': true,
        'bri': 128,
        'ps': -1,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': 100,
            'on': true,
            'fx': 0,
            'sx': 128,
            'ix': 128,
            'pal': 0,
            'grp': 1,
            'spc': 0,
            'col': [
              [255, 160, 0, 0],
              [0, 0, 0, 0],
              [0, 0, 0, 0]
            ],
          },
          {
            'id': 1,
            'start': 100,
            'stop': 200,
            'on': true,
            'fx': 0,
            'sx': 128,
            'ix': 128,
            'pal': 0,
            'grp': 1,
            'spc': 0,
            'col': [
              [255, 160, 0, 0],
              [0, 0, 0, 0],
              [0, 0, 0, 0]
            ],
          },
        ],
      };
}

/// The participation cache the real wire pipeline reads. Cold in this guard
/// (no preference stored), which is a fresh install's state.
Future<List<int>?> getCachedParticipatingChannelsForGuard() async => null;

final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _container(_RecordingController controller) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => controller),
    wledConnectivityStatusProvider.overrideWith(
      (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
    ),
    deviceChannelsProvider.overrideWithValue(_twoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    calendarLeaseActiveTimersProvider
        .overrideWithValue(const LeaseLedgerEmpty()),
  ]);
  addTearDown(c.dispose);
  return c;
}

Map<String, dynamic> _chase() => {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'fx': 28,
          'sx': 160,
          'ix': 128,
          'pal': 5,
          'col': [
            [255, 0, 0, 0],
            [0, 0, 255, 0],
          ],
        },
      ],
    };

/// As-sent multi-segment payload with explicit ids: must pass through.
Map<String, dynamic> _prefiltered() => {
      'on': true,
      'bri': 180,
      'seg': [
        {
          'id': 0,
          'on': true,
          'fx': 12,
          'sx': 90,
          'ix': 128,
          'pal': 0,
          'grp': 1,
          'spc': 0,
          'col': [
            [0, 200, 80, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
          ],
        },
        {
          'id': 1,
          'on': true,
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 0,
          'grp': 2,
          'spc': 1,
          'col': [
            [255, 255, 255, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
          ],
        },
      ],
    };

List<ScheduleItem> _schedules() => const [
      ScheduleItem(
        id: 'evening',
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: ['Mon', 'Wed', 'Fri'],
        actionLabel: 'Pattern: Evening',
        enabled: true,
        presetId: 10,
        wledPayload: {
          'on': true,
          'bri': 160,
          'seg': [
            {
              'fx': 28,
              'sx': 140,
              'ix': 128,
              'pal': 5,
              'col': [
                [255, 120, 0, 0],
                [255, 255, 255, 0]
              ],
            }
          ],
        },
      ),
      ScheduleItem(
        id: 'weekend',
        timeLabel: '6:30 PM',
        repeatDays: ['Sat', 'Sun'],
        actionLabel: 'Turn On',
        enabled: true,
      ),
    ];

Future<List<Map<String, dynamic>>> _scenario(
  String name,
  Future<void> Function(ProviderContainer c) run,
) async {
  final controller = _RecordingController();
  final c = _container(controller);
  await c.read(wledConnectivityStatusProvider.future);
  await run(c);
  return [
    for (final entry in controller.log) {'scenario': name, ...entry},
  ];
}

Future<Map<String, dynamic>> _record() async {
  final writes = <Map<String, dynamic>>[];

  writes.addAll(await _scenario('apply: raw pattern', (c) async {
    await c
        .read(wledStateProvider.notifier)
        .applyToDevice(_chase(), labelHint: 'Chase');
  }));

  writes.addAll(await _scenario('apply: as-sent multi-segment', (c) async {
    await c
        .read(wledStateProvider.notifier)
        .applyToDevice(_prefiltered(), labelHint: 'Saved look');
  }));

  writes.addAll(await _scenario('apply: with label, no filter', (c) async {
    await c
        .read(wledStateProvider.notifier)
        .applyPayloadWithLabel(_chase(), labelHint: 'Chase');
  }));

  writes.addAll(await _scenario('apply: one channel selected', (c) async {
    c.read(selectedChannelIdsProvider.notifier).state = {1};
    await c
        .read(wledStateProvider.notifier)
        .applyToDevice(_chase(), labelHint: 'Chase');
  }));

  writes.addAll(await _scenario('controls', (c) async {
    final n = c.read(wledStateProvider.notifier);
    await n.togglePower(false);
    await n.togglePower(true);
    await n.setBrightness(128);
    await n.setSpeed(200);
    await n.setColor(const Color(0xFFFF0000));
    await n.setWarmWhite(100);
    await n.setChannelPower(1, false);
  }));

  writes.addAll(await _scenario('favourite', (c) async {
    await applyFavoritePayloadWith(c.read, _chase());
  }));

  writes.addAll(await _scenario('schedule sync', (c) async {
    resetRepairAttempts();
    await const ScheduleSyncService(paceDelay: Duration.zero)
        .syncAll(c.read(_refProvider), _schedules());
  }));

  return {
    'target': await _recordTarget(),
    'writes': writes,
  };
}

/// Where a one-controller account's commands go on the home network.
Future<Map<String, dynamic>> _recordTarget() async {
  final c = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    currentUserProfileProvider
        .overrideWith((ref) => Stream<UserModel?>.value(null)),
    controllersStreamProvider.overrideWith(
      (ref) => Stream.value(const [
        ControllerInfo(id: _controllerId, ip: _ip, name: 'Home'),
      ]),
    ),
    wledConnectivityStatusProvider.overrideWith(
      (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
    ),
  ]);
  addTearDown(c.dispose);
  c.read(selectedDeviceIpProvider.notifier).state = _ip;
  await c.read(wledConnectivityStatusProvider.future);
  await c.read(controllersStreamProvider.future);
  await c.read(authStateProvider.future);
  // Settled before the first read so the repository is built once.
  await c.read(currentUserProfileProvider.future);

  final repo = c.read(wledRepositoryProvider);
  return {
    'selectedControllerId': c.read(selectedControllerIdProvider),
    'type': repo.runtimeType.toString(),
    if (repo is WledService) ...{
      'baseUrl': repo.baseUrl,
      'expectedControllerId': repo.expectedControllerId,
      'recordsRouting': repo.recordsRouting,
    },
  };
}

/// [wire] with the +110 completion fields removed wherever [golden] does not
/// carry them, so the two can be compared for everything else.
dynamic _withoutCompletion(dynamic wire, dynamic golden) {
  if (wire is! Map || golden is! Map) return wire;
  final segs = wire['seg'];
  final goldSegs = golden['seg'];
  if (segs is! List || goldSegs is! List || segs.length != goldSegs.length) {
    return wire;
  }
  return {
    ...wire,
    'seg': [
      for (var i = 0; i < segs.length; i++)
        if (segs[i] is Map && goldSegs[i] is Map)
          {
            for (final e in (segs[i] as Map).entries)
              if (!_kCompletedKeys.contains(e.key) ||
                  (goldSegs[i] as Map).containsKey(e.key))
                e.key: e.value,
          }
        else
          segs[i],
    ],
  };
}

/// +110 E1, owner item B — applying a favourite no longer sends the level it
/// was stored with (only a level the customer saved on purpose is sent; the
/// golden's favourite carries an incidental `bri: 200`). The ONE intended
/// difference: [golden] minus its top-level `bri`, for the favourite scenario
/// only. Everything else about that write must still match byte for byte.
dynamic _goldenWithoutFavoriteBrightness(dynamic golden, Object? scenario) {
  if (scenario != 'favourite' || golden is! Map) return golden;
  return {
    for (final e in golden.entries)
      if (e.key != 'bri') e.key: e.value,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WledService.resetDeviceVerificationForTest();
  });

  test('one controller: every write and its target match the release baseline',
      () async {
    final recorded = _copy(await _record()) as Map<String, dynamic>;

    final file = File(_goldenPath);
    if (Platform.environment['LUMINA_WRITE_GOLDEN'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(recorded)}\n');
      // A run that only writes proves nothing — make that visible.
      markTestSkipped('golden written to $_goldenPath');
      return;
    }

    expect(file.existsSync(), isTrue, reason: 'golden missing: $_goldenPath');
    final golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    expect(recorded['target'], golden['target'],
        reason: 'commands must go to the same controller, the same way');

    final writes = recorded['writes'] as List;
    final goldenWrites = golden['writes'] as List;
    expect(
      [for (final w in writes) '${(w as Map)['scenario']} / ${w['call']}'],
      [for (final w in goldenWrites) '${(w as Map)['scenario']} / ${w['call']}'],
      reason: 'same writes, same order',
    );

    for (var i = 0; i < writes.length; i++) {
      final w = writes[i] as Map;
      final g = goldenWrites[i] as Map;
      final where = '#$i ${w['scenario']} / ${w['call']}';
      final goldBoundary =
          _goldenWithoutFavoriteBrightness(g['boundary'], w['scenario']);
      final goldWire = _goldenWithoutFavoriteBrightness(g['wire'], w['scenario']);
      if (w['scenario'] == 'favourite' && w['boundary'] is Map) {
        expect((w['boundary'] as Map).containsKey('bri'), isFalse,
            reason: "item B: a favourite applies at the house's own level");
      }
      expect(jsonEncode(w['boundary']), jsonEncode(goldBoundary),
          reason: 'boundary payload changed at $where');
      expect(
        _withoutCompletion(w['wire'], goldWire),
        equals(goldWire),
        reason: 'wire payload changed beyond the stated fields at $where',
      );
    }
  });
}
