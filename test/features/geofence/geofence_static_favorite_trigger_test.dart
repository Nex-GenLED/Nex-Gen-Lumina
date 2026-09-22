// The Welcome Home geofence and a STATIC (per-pixel) favorite.
//
// geofence_monitor.dart lit a favorite recovered by name through
// applyToDevice, then a bare applyJson when that returned false. Both send the
// stored payload as ONE message, and applyJson refuses anything over 4 KB — a
// 290-LED Static favorite is ~16 KB. So the lights showed nothing and the
// Welcome Home notification fired anyway. Dormant while the lookup queried a
// field no favorite had (`name`); live since fix/geofence-favorites-lookup.
//
// The fix routes a per-pixel favorite through applyFavoritePayloadWith — the
// chunked spine My Designs and the dashboard's My Favorites use. Everything
// else — effect favorites, the cold-start net, the built-in fallbacks, the
// notification — must be exactly what it was.
//
// The monitor under test is the REAL GeofenceMonitor: real config parse, real
// enter-transition on a position fix, the real lookup against a fake Firestore
// holding documents written by the REAL favorite writer, the real applier.
// Only the controller is a recorder, and it enforces the production size rule
// so a test cannot pass by sending what the real transport would refuse.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/geofence/geofence_favorite_lookup.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];
const _editorChannels = [
  PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 128),
  PatternEditorChannel(id: 1, name: 'Channel 2', ledCount: 162),
];

EditablePattern _chiefs(int fx) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [Color(0xFFE31837), Color(0xFFFFB81C)],
      effectId: fx,
    ).copyWith(actionColors: const [
      Color(0xFFE31837),
      Color(0xFFFFB81C),
      Color(0xFFFFFFFF),
    ], brightness: 180);

/// What the Pattern Editor heart stores for the card in Static — 290 LEDs, no
/// two neighbours alike, so nothing range-compresses.
Map<String, dynamic> _staticFavorite() =>
    buildPerPixelFavoritePayload(customDesignFromEditablePattern(
      pattern: _chiefs(0),
      name: 'Kansas City Chiefs',
      ownerId: '',
      channels: _editorChannels,
    ));

/// The same card hearted while ANIMATED — an ordinary effect favorite.
Map<String, dynamic> _animatedFavorite() => _chiefs(15).toWledPayload(290);

/// A controller that enforces the production size rule on `applyJson` and
/// records per-pixel paints, so the test sees exactly what would be sent.
class _Repo implements WledRepository, PerPixelWriter {
  final json = <Map<String, dynamic>>[];
  final refused = <int>[];
  final pixels = <int, List<PixelSpan>>{};

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    final bytes = utf8.encode(jsonEncode(payload)).length;
    if (bytes > kMaxApplyPayloadBytes) {
      refused.add(bytes);
      return false;
    }
    json.add(payload);
    return true;
  }

  @override
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  }) async {
    pixels[segmentId] = spans;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

ProviderContainer _container(WledRepository? repo,
        {List<int> effective = const [0, 1]}) =>
    ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(effective),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);

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

/// ~2.2 km north of the fence centre (radius 300 m) — clearly outside.
final Position _outside = _at(_lat + 0.02, _lng);
final Position _inside = _at(_lat, _lng);

List<String> _spans(List<PixelSpan> l) =>
    [for (final s in l) '${s.start}-${s.end}:${s.color}'];

class _Rig {
  final GeofenceMonitor monitor;
  final List<String> notified;
  _Rig(this.monitor, this.notified);
}

/// The real monitor, configured (through the real config parse) for
/// [actionName], with auth + Firestore + the notification replaced.
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
  expect(m.state.enabled, isTrue);
  return _Rig(m, notified);
}

/// An arrival: one fix outside the fence, then one at its centre.
Future<void> _arrive(GeofenceMonitor m) async {
  await m.onPositionForTest(_outside);
  expect(m.state.isInside, isFalse);
  await m.onPositionForTest(_inside);
  expect(m.state.isInside, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // cloud_firestore captures its FieldValue factory in a static on FIRST use;
  // constructing the fake installs the mock factory before the real writer
  // builds a server timestamp.
  setUpAll(FakeFirebaseFirestore.new);

  late FakeFirebaseFirestore db;
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = FakeFirebaseFirestore();
    await writeFavorite(db.doc('users/u1/favorites/chiefs_static'),
        patternName: 'Kansas City Chiefs', payload: _staticFavorite());
    await writeFavorite(db.doc('users/u1/favorites/chiefs_animated'),
        patternName: 'Chiefs Animated', payload: _animatedFavorite());
  });

  test('the bug, pinned: the OLD trigger path sent a Static favorite as one '
      'message and was refused twice — nothing reached the lights', () async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    final payload = (await lookupGeofenceFavoritePayload(db,
        uid: 'u1', actionName: 'Kansas City Chiefs'))!;

    // What _triggerAction did with a recovered favorite before this change.
    final applied = await c
        .read(wledStateProvider.notifier)
        .applyToDevice(payload, labelHint: 'Kansas City Chiefs');
    expect(applied, isFalse);
    expect(await repo.applyJson(payload), isFalse);

    expect(repo.refused, hasLength(2));
    expect(repo.refused, everyElement(greaterThan(kMaxApplyPayloadBytes)));
    expect(repo.json, isEmpty);
    expect(repo.pixels, isEmpty);
  });

  test('arriving home with a Static favorite as the action paints it through '
      'the chunked spine — base write + per-channel pixels, nothing refused',
      () async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    final rig = await _rig(c, db, 'Kansas City Chiefs');

    await _arrive(rig.monitor);

    expect(repo.refused, isEmpty,
        reason: 'nothing over the ceiling was attempted');
    // The base: ONE write — black, at the favorite's brightness, every channel.
    expect(repo.json, hasLength(1));
    final base = repo.json.single;
    expect(base['on'], isTrue);
    expect(base['bri'], 180);
    final segs = (base['seg'] as List).cast<Map>();
    expect(segs.map((s) => s['id']).toSet(), {0, 1});
    for (final s in segs) {
      expect(s['fx'], 0);
      expect((s['col'] as List).first, [0, 0, 0, 0]);
    }
    // The pixels: exactly the spans My Designs paints for the same design.
    final want = customDesignToSpans(perPixelDesignOfFavorite(_staticFavorite())!);
    expect(repo.pixels.keys.toSet(), {0, 1});
    expect(repo.pixels[0], hasLength(128));
    expect(repo.pixels[1], hasLength(162));
    for (final ch in [0, 1]) {
      expect(_spans(repo.pixels[ch]!), _spans(want[ch]!));
    }
    expect(rig.notified, ['Kansas City Chiefs']);
  });

  test('an effect favorite still takes the path it always has — the single '
      'channel-filtered write applyToDevice makes, with the action as label',
      () async {
    final viaGeofence = _Repo();
    final c = _container(viaGeofence);
    addTearDown(c.dispose);
    final rig = await _rig(c, db, 'Chiefs Animated');
    await _arrive(rig.monitor);

    // The reference: the pre-change code, verbatim, on the same payload.
    final direct = _Repo();
    final c2 = _container(direct);
    addTearDown(c2.dispose);
    final payload = (await lookupGeofenceFavoritePayload(db,
        uid: 'u1', actionName: 'Chiefs Animated'))!;
    expect(
        await c2
            .read(wledStateProvider.notifier)
            .applyToDevice(payload, labelHint: 'Chiefs Animated'),
        isTrue);

    expect(viaGeofence.json, direct.json);
    expect(viaGeofence.json, hasLength(1));
    expect(
        (viaGeofence.json.single['seg'] as List)
            .map((s) => (s as Map)['fx'])
            .toSet(),
        {15});
    expect(viaGeofence.pixels, isEmpty);
    expect(viaGeofence.refused, isEmpty);
    expect(rig.notified, ['Chiefs Animated']);
  });

  group('cold start — no effective channels resolved yet', () {
    test('an effect favorite still gets the bare cold-start write (unchanged)',
        () async {
      final repo = _Repo();
      final c = _container(repo, effective: const []);
      addTearDown(c.dispose);
      final rig = await _rig(c, db, 'Chiefs Animated');

      await _arrive(rig.monitor);

      expect(repo.json, [_animatedFavorite()], reason: 'raw, unfiltered');
      expect(repo.pixels, isEmpty);
      expect(rig.notified, ['Chiefs Animated']);
    });

    test('a Static favorite is NOT posted raw — nothing over the ceiling is '
        'attempted; the notification still reports the trigger, as it always '
        'has', () async {
      final repo = _Repo();
      final c = _container(repo, effective: const []);
      addTearDown(c.dispose);
      final rig = await _rig(c, db, 'Kansas City Chiefs');

      await _arrive(rig.monitor);

      expect(repo.json, isEmpty);
      expect(repo.pixels, isEmpty);
      expect(repo.refused, isEmpty);
      expect(rig.notified, ['Kansas City Chiefs']);
    });
  });

  test('no favorite by that name → the built-in fallback still runs (Relax)',
      () async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    final rig = await _rig(c, db, 'Relax');

    await _arrive(rig.monitor);

    expect(repo.json, hasLength(1));
    expect(repo.json.single['bri'], 180);
    expect(repo.pixels, isEmpty);
    expect(rig.notified, ['Relax']);
  });
}
