// Store window (a): the Welcome Home position stream runs ONLY while a saved
// Welcome Home config exists for the account.
//
// GeofenceMonitor.start() used to open a best-accuracy GPS stream on every
// launch with location granted, then drop every fix in _onPosition when the
// account had no geofence. The stream is now owned by the config listener:
// on when /geofences/welcome_home exists, off when it is deleted or when the
// monitor stops.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DocumentReference<Map<String, dynamic>> docRef;
  late StreamController<DocumentSnapshot<Map<String, dynamic>>> config;
  late ProviderContainer container;
  late GeofenceMonitor monitor;
  late int positionSubscriptions;

  setUp(() {
    docRef = FakeFirebaseFirestore()
        .collection('users')
        .doc('u1')
        .collection('geofences')
        .doc('welcome_home');
    config = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
    container = ProviderContainer();
    addTearDown(container.dispose);
    monitor = container.read(geofenceMonitorProvider.notifier);
    positionSubscriptions = 0;
    monitor.positionStreamFactory = () {
      positionSubscriptions++;
      return StreamController<Position>().stream;
    };
  });

  tearDown(() => config.close());

  Future<void> emit() async {
    config.add(await docRef.get());
    await Future<void>.delayed(Duration.zero);
  }

  test('no saved config: no GPS stream', () async {
    monitor.startConfigForTest(() => config.stream);
    await emit(); // the doc does not exist
    expect(monitor.positionStreamActiveForTest, isFalse);
    expect(positionSubscriptions, 0);
  });

  test('a saved config starts it; deleting the config stops it', () async {
    monitor.startConfigForTest(() => config.stream);
    expect(monitor.positionStreamActiveForTest, isFalse,
        reason: 'starting the monitor alone must not open the GPS stream');

    await docRef.set({
      'center_lat': 30.0,
      'center_lng': -97.0,
      'radius_m': 300,
      'action_name': 'Welcome Home',
      'only_at_night': false,
    });
    await emit();
    expect(monitor.positionStreamActiveForTest, isTrue);

    await emit(); // a second emission of the same config
    expect(positionSubscriptions, 1, reason: 'never a second GPS stream');

    await docRef.delete();
    await emit();
    expect(monitor.positionStreamActiveForTest, isFalse);
  });

  test('stop() closes it', () async {
    monitor.startConfigForTest(() => config.stream);
    await docRef.set({'center_lat': 30.0, 'center_lng': -97.0});
    await emit();
    expect(monitor.positionStreamActiveForTest, isTrue);

    await monitor.stop();
    expect(monitor.positionStreamActiveForTest, isFalse);
  });
}
