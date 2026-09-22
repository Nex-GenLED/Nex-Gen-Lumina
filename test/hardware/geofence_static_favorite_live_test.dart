// LIVE HARDWARE TEST — the Welcome Home geofence firing a STATIC (per-pixel)
// favorite against the bench controller at kBenchIp (2 channels: 0–128 and
// 128–290). NOT part of the normal suite: it performs real network I/O and
// changes what the lights show (never presets, never /json/cfg), then puts the
// look back. Without the define every test skips.
//
// Runs AFTER static_favorite_live_test.dart's export phase and the
// client-credential Firestore leg, in the same <dir>. It needs:
//   <dir>/from_firestore_static_fav.json — the favorite as REAL Firestore
//                                          returned it to the grid's own query
//   <dir>/live_static.json              — the frame the editor painted (T28)
//
//   flutter test test/hardware/geofence_static_favorite_live_test.dart \
//     --dart-define=RUN_HW=true --dart-define=FAV_RT_DIR=<dir>
//
// The monitor is the REAL GeofenceMonitor: real config parse, real
// enter-transition on a position fix, the real lookup (a fake Firestore seeded
// with the document above), the real applier, the real transport, the real
// controller. Only auth, the position stream and the notification plugin are
// replaced — none of them decides what reaches the lights. The frame buffer is
// read back over the controller's live-view WebSocket, not inferred from an
// HTTP 200.
//
// Numbering continues static_favorite_live_test.dart (T27–T29).

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kBenchIp = '192.168.1.150';
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);
const String kDir = String.fromEnvironment('FAV_RT_DIR');

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];

/// The same card hearted while ANIMATED, at a brightness that is neither the
/// Static favorite's 180 nor the scramble's 90 — the unchanged path, on
/// hardware, so a regression there would show too.
Map<String, dynamic> _animatedFavorite() => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [Color(0xFFE31837), Color(0xFFFFB81C)],
      effectId: 15,
      speed: 140,
      intensity: 128,
    ).copyWith(brightness: 96).toWledPayload(290);

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

ProviderContainer _container(WledRepository repo) => ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);

Future<List<List<List<int>>>> _frames(Duration duration) async {
  final ws = await WebSocket.connect('ws://$kBenchIp/ws');
  final frames = <List<List<int>>>[];
  final sub = ws.listen((msg) {
    if (msg is! List<int> || msg.isEmpty || msg[0] != 76 /* 'L' */) return;
    final off = msg[1] == 2 ? 4 : 2;
    frames.add([
      for (int i = off; i + 2 < msg.length; i += 3) [msg[i], msg[i + 1], msg[i + 2]],
    ]);
  });
  ws.add(jsonEncode({'lv': true}));
  await Future<void>.delayed(duration);
  ws.add(jsonEncode({'lv': false}));
  await sub.cancel();
  await ws.close();
  return frames;
}

Future<List<List<int>>> _frame() async {
  await Future<void>.delayed(const Duration(milliseconds: 1300)); // 700 ms crossfade
  return (await _frames(const Duration(milliseconds: 900))).last;
}

int _differing(List<List<int>> a, List<List<int>> b) => [
      for (int i = 0; i < 290; i++)
        if (a[i].join(',') != b[i].join(',')) i,
    ].length;

dynamic _fromRest(Map v) {
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
  if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('stringValue')) return v['stringValue'] as String;
  if (v.containsKey('timestampValue')) {
    return Timestamp.fromDate(DateTime.parse(v['timestampValue'] as String));
  }
  throw ArgumentError('unexpected Firestore value in a favorite: $v');
}

File _file(String name) => File('$kDir/$name');

/// The user's favorites: the Static one exactly as REAL Firestore returned it
/// (same id, same fields), plus an effect favorite through the real writer.
Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  final doc = jsonDecode(_file('from_firestore_static_fav.json').readAsStringSync())
      as Map<String, dynamic>;
  final id = (doc['name'] as String).split('/').last;
  await db.doc('users/u1/favorites/$id').set({
    for (final e in (doc['fields'] as Map).entries) '${e.key}': _fromRest(e.value as Map),
  });
  await writeFavorite(db.doc('users/u1/favorites/chiefs_animated'),
      patternName: 'Chiefs Animated', payload: _animatedFavorite());
  return db;
}

const double _lat = 30.0, _lng = -97.0;

Position _at(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _Rig {
  final GeofenceMonitor monitor;
  final List<String> notified;
  _Rig(this.monitor, this.notified);
}

/// The real monitor, configured for [actionName] through the real config parse.
Future<_Rig> _rig(
    ProviderContainer c, FakeFirebaseFirestore db, String actionName) async {
  final notified = <String>[];
  final m = c.read(geofenceMonitorProvider.notifier)
    ..uidForTest = 'u1'
    ..firestoreForTest = db
    ..welcomeHomeNotifier = (name) async => notified.add(name);
  final ref = db.doc('users/u1/geofences/welcome_home');
  await ref.set({
    'center_lat': _lat,
    'center_lng': _lng,
    'radius_m': 300,
    'action_name': actionName,
    'only_at_night': false,
  });
  final snap = await ref.get();
  m.startConfigForTest(() => Stream.value(snap));
  await pumpEventQueue();
  expect(m.configForTest?.actionName, actionName);
  return _Rig(m, notified);
}

/// An arrival: one fix ~2.2 km outside the 300 m fence, then one at its centre.
Future<void> _arrive(GeofenceMonitor m) async {
  await m.onPositionForTest(_at(_lat + 0.02, _lng));
  expect(m.state.isInside, isFalse);
  await m.onPositionForTest(_at(_lat, _lng));
  expect(m.state.isInside, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;
  final run = kRunHw && kDir.isNotEmpty;

  final wire = <String>[];
  final originalDebugPrint = debugPrint;

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test stubs HTTP with a 400
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // cloud_firestore captures its FieldValue factory on first use.
    FakeFirebaseFirestore();
    if (!run) return;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.contains('WLED POST /json/state')) {
        wire.add(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']}');
  });

  tearDownAll(() async {
    debugPrint = originalDebugPrint;
    if (!run) return;
    await restoreAfterFindLed(svc, prior);
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
  });

  /// A deliberately different look, brightness knocked off 180 — the state the
  /// house is in when the user drives up.
  Future<void> scramble() async {
    final r = await applyBaseAndSpansWith(_container(svc).read,
        baseRgbw: const [0, 0, 40, 0],
        spansByChannel: const {
          0: [PixelSpan(start: 0, end: 9, color: [0, 255, 0, 0])],
        });
    expect(r, SpineWriteResult.ok);
    expect(await svc.applyJson({'bri': 90}), isTrue);
  }

  test('T30 geofence — arriving home with a Static favorite as the Welcome '
      'Home action lands the SAME frame the editor painted, via the chunked '
      'spine, at the favorite brightness', () async {
    final db = await _seed();
    final c = _container(svc);
    addTearDown(c.dispose);
    final rig = await _rig(c, db, 'Kansas City Chiefs');

    await scramble();
    final scrambled = await _frame();

    wire.clear();
    await _arrive(rig.monitor);
    final requests = List<String>.of(wire);
    final got = await _frame();

    final live = [
      for (final l in jsonDecode(_file('live_static.json').readAsStringSync()) as List)
        (l as List).cast<int>(),
    ];
    final vsLive = _differing(got, live);
    final vsScramble = _differing(got, scrambled);
    final state = (await svc.getState())!;
    final segs = (state['seg'] as List).cast<Map>();
    // ignore: avoid_print
    print('T30 geofence frame vs the editor live frame: $vsLive/290 differ; vs '
        'the scramble it replaced: $vsScramble/290 differ. '
        'LEDs 0-5 = ${got.sublist(0, 6)}; LEDs 128-133 = ${got.sublist(128, 134)}');
    // ignore: avoid_print
    print('T30 device on=${state['on']} bri=${state['bri']} '
        'fx=${segs.map((s) => s['fx']).toList()} frz=${segs.map((s) => s['frz']).toList()} '
        '(favorite stores 180; was 90 before the arrival); notified=${rig.notified}');
    // ignore: avoid_print
    print('T30 wire: ${requests.length} requests —\n  ${requests.join('\n  ')}');

    expect(vsLive, 0);
    expect(vsScramble, greaterThan(250));
    expect(state['on'], isTrue);
    expect(state['bri'], 180);
    final paints = requests.where((r) => r.contains('per-pixel chunk')).toList();
    expect(paints.length, greaterThanOrEqualTo(2));
    expect(requests.length, greaterThanOrEqualTo(3));
    for (final p in paints) {
      final bytes = int.parse(RegExp(r'(\d+)B\)').firstMatch(p)!.group(1)!);
      expect(bytes, lessThan(6000));
    }
    expect(rig.notified, ['Kansas City Chiefs']);
  }, skip: !run);

  test('T31 geofence — an effect favorite as the action still lands as ONE '
      'channel-filtered write (the unchanged path), at its own brightness',
      () async {
    final db = await _seed();
    final c = _container(svc);
    addTearDown(c.dispose);
    final rig = await _rig(c, db, 'Chiefs Animated');

    wire.clear();
    await _arrive(rig.monitor);
    final requests = List<String>.of(wire);
    await Future<void>.delayed(const Duration(milliseconds: 1300));

    final state = (await svc.getState())!;
    final segs = (state['seg'] as List).cast<Map>();
    // ignore: avoid_print
    print('T31 device on=${state['on']} bri=${state['bri']} '
        'fx=${segs.map((s) => s['fx']).toList()} frz=${segs.map((s) => s['frz']).toList()} '
        'col0=${segs.map((s) => (s['col'] as List).first).toList()}; '
        'notified=${rig.notified}');
    // ignore: avoid_print
    print('T31 wire: ${requests.length} requests —\n  ${requests.join('\n  ')}');

    expect(requests, hasLength(1));
    expect(requests.single.contains('per-pixel chunk'), isFalse);
    expect(state['on'], isTrue);
    expect(state['bri'], 96);
    expect(segs.map((s) => s['fx']).toSet(), {15});
    expect(segs.map((s) => s['frz']).toSet(), {false});
    expect(rig.notified, ['Chiefs Animated']);
  }, skip: !run);
}
