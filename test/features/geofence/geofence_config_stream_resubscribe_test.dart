// Audit-2 S22 / #52 dead-listener class — geofence CONFIG stream onError.
//
// geofence_monitor.dart's config listener (/geofences/welcome_home) had no
// stream-level onError — only the inner parse was guarded. One stream error
// (transient Firestore disconnect / permission blip) killed the subscription
// permanently, so live enable/disable + radius edits stopped applying and
// automation ran on stale config until app relaunch.
//
// Fix: onError → log + debounced re-subscribe (mirrors the position stream and
// the engine's e005a02 pattern). These tests drive the config subscription off
// an injected stream factory (startConfigForTest) so a stream error can be
// simulated without a live backend, and prove:
//   1. a stream error does NOT permanently kill the listener (it re-subscribes);
//   2. config changes still apply after a simulated error;
//   3. the inner parse guard still swallows a bad doc (and the stream survives).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late DocumentReference<Map<String, dynamic>> docRef;
  late ProviderContainer container;
  late GeofenceMonitor monitor;

  // Each call hands the monitor a fresh controller, recorded so the test can
  // (a) count re-subscriptions and (b) push snapshots/errors onto the stream
  // the monitor is currently listening to.
  late List<StreamController<DocumentSnapshot<Map<String, dynamic>>>> controllers;
  Stream<DocumentSnapshot<Map<String, dynamic>>> factory() {
    final c = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
    controllers.add(c);
    return c.stream;
  }

  // Produce a REAL DocumentSnapshot with the given data via fake Firestore.
  Future<DocumentSnapshot<Map<String, dynamic>>> snap(
    Map<String, dynamic> data,
  ) async {
    await docRef.set(data);
    return docRef.get();
  }

  Map<String, dynamic> cfg({required double radius}) => {
        'center_lat': 30.0,
        'center_lng': -97.0,
        'radius_m': radius,
        'action_name': 'Welcome Home',
        'only_at_night': false,
      };

  setUp(() {
    firestore = FakeFirebaseFirestore();
    docRef = firestore
        .collection('users')
        .doc('u1')
        .collection('geofences')
        .doc('welcome_home');
    controllers = [];
    container = ProviderContainer();
    monitor = container.read(geofenceMonitorProvider.notifier);
    monitor.configResubscribeDelay = Duration.zero; // no real-time wait in tests
    addTearDown(container.dispose);
  });

  tearDown(() async {
    for (final c in controllers) {
      if (!c.isClosed) await c.close();
    }
  });

  test('a config-stream error does NOT permanently kill the listener — it '
      're-subscribes', () async {
    monitor.startConfigForTest(factory);
    expect(controllers, hasLength(1), reason: 'initial subscription');

    // Stream-level error (the case the missing onError used to drop on the
    // floor, silently ending the subscription).
    controllers.first.addError(Exception('transient firestore error'));
    await pumpEventQueue();

    expect(controllers.length, greaterThanOrEqualTo(2),
        reason: 'monitor re-subscribed after the error instead of dying');
  });

  test('config changes still apply after a simulated stream error', () async {
    monitor.startConfigForTest(factory);

    // Initial config on the first stream.
    controllers.first.add(await snap(cfg(radius: 100)));
    await pumpEventQueue();
    expect(monitor.configForTest?.radiusMeters, 100);
    expect(monitor.state.enabled, isTrue);

    // Stream dies → re-subscribe yields a new controller.
    controllers.first.addError(Exception('boom'));
    await pumpEventQueue();
    expect(controllers.length, 2);

    // A live radius edit arriving on the NEW subscription must still apply.
    controllers[1].add(await snap(cfg(radius: 250)));
    await pumpEventQueue();
    expect(monitor.configForTest?.radiusMeters, 250,
        reason: 'live config edit applied after the error/re-subscribe');
  });

  test('the inner parse guard still swallows a bad doc and the stream survives',
      () async {
    monitor.startConfigForTest(factory);

    // Malformed doc: missing center_lat → GeofenceConfig.fromMap throws; the
    // parse guard must catch it (no crash, config stays null), and crucially
    // the SAME subscription must remain alive (no re-subscribe triggered).
    await docRef.set({'radius_m': 50, 'action_name': 'x'});
    controllers.first.add(await docRef.get());
    await pumpEventQueue();
    expect(monitor.configForTest, isNull, reason: 'bad doc did not parse');
    expect(controllers, hasLength(1),
        reason: 'a parse error must NOT trigger a re-subscribe');

    // A subsequent good doc on the same stream still applies → listener alive.
    controllers.first.add(await snap(cfg(radius: 75)));
    await pumpEventQueue();
    expect(monitor.configForTest?.radiusMeters, 75);
  });
}
