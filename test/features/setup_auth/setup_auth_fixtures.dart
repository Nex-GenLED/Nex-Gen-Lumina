// Shared fakes for the sign-in, onboarding, device-setup and roofline tests
// (+110 package G). Addresses use the documentation-only range 192.0.2.0/24.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

const String kTestUid = 'uid-customer-a';
const String kTestEmail = 'customer@example.com';

/// An [AccountSession] the test drives by hand, recording every call.
class FakeAccountSession implements AccountSession {
  FakeAccountSession({
    this.uid = kTestUid,
    this.email = kTestEmail,
    this.displayName = 'Pat Customer',
    this.isSignedIn = true,
    this.isAnonymous = false,
  });

  @override
  String? uid;
  @override
  String? email;
  @override
  String? displayName;
  @override
  bool isSignedIn;
  @override
  bool isAnonymous;

  int signOutCalls = 0;
  int anonymousSignIns = 0;
  final List<String> calls = [];

  /// Thrown by [reauthenticate] when set.
  Object? reauthError;

  @override
  Future<String?> signInAnonymously() async {
    anonymousSignIns++;
    calls.add('signInAnonymously');
    isSignedIn = true;
    isAnonymous = true;
    uid = 'uid-anon';
    return uid;
  }

  @override
  Future<void> reauthenticate(String email, String password) async {
    calls.add('reauthenticate');
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    calls.add('sendPasswordResetEmail');
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    calls.add('signOut');
    isSignedIn = false;
    isAnonymous = false;
    uid = null;
  }
}

/// Discovery that returns a fixed list instead of touching the network.
class FakeDiscoveryService extends DeviceDiscoveryService {
  FakeDiscoveryService(this.devices);
  final List<DeviceEndpoint> devices;
  int calls = 0;

  @override
  Future<List<DeviceEndpoint>> discover(
      {Duration timeout = const Duration(seconds: 10)}) async {
    calls++;
    return devices;
  }
}

/// A two-channel roofline: channel 0 has an installer-mapped corner, peak and
/// run with anchors and no photo points; channel 1 has one traced run.
RooflineConfiguration twoChannelRoofline({String controllerId = 'ctrl-a'}) {
  final now = DateTime(2026, 9, 29);
  return RooflineConfiguration(
    id: controllerId,
    controllerId: controllerId,
    name: 'My Roofline',
    createdAt: now,
    updatedAt: now,
    totalChannelCount: 2,
    segments: const [
      RooflineSegment(
        id: 'ch0_run',
        name: 'Garage Run',
        pixelCount: 40,
        startPixel: 0,
        anchorPixels: [0, 38],
        channelIndex: 0,
        sortOrder: 0,
      ),
      RooflineSegment(
        id: 'ch0_corner',
        name: 'Corner',
        pixelCount: 2,
        startPixel: 40,
        type: SegmentType.corner,
        architecturalRole: ArchitecturalRole.corner,
        anchorPixels: [0],
        channelIndex: 0,
        sortOrder: 1,
      ),
      RooflineSegment(
        id: 'ch0_peak',
        name: 'Front Peak',
        pixelCount: 30,
        startPixel: 42,
        type: SegmentType.peak,
        architecturalRole: ArchitecturalRole.peak,
        anchorPixels: [14],
        channelIndex: 0,
        sortOrder: 2,
      ),
      RooflineSegment(
        id: 'ch1_traced',
        name: 'Back Eave',
        pixelCount: 50,
        startPixel: 0,
        channelIndex: 1,
        sortOrder: 3,
        points: [Offset(0.1, 0.2), Offset(0.5, 0.2), Offset(0.9, 0.25)],
      ),
    ],
  );
}

/// Writes [config] into [firestore] as the per-channel pixel map for
/// [controllerId] under [uid], exactly as the app stores it.
Future<void> seedPixelMap(
  FakeFirebaseFirestore firestore,
  RooflineConfiguration config, {
  String uid = kTestUid,
  String controllerId = 'ctrl-a',
}) async {
  final channels = splitConfigToPixelMapChannels(
    config,
    controllerId: controllerId,
    now: DateTime(2026, 9, 29),
  );
  for (final ch in channels) {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('controllers')
        .doc(controllerId)
        .collection('pixelMap')
        .doc('${ch.channelIndex}')
        .set(ch.toJson());
  }
}

/// Seeds `users/{uid}/controllers/{id}` records.
Future<void> seedControllers(
  FakeFirebaseFirestore firestore,
  Map<String, String> nameById, {
  String uid = kTestUid,
}) async {
  var octet = 10;
  for (final entry in nameById.entries) {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('controllers')
        .doc(entry.key)
        .set({'name': entry.value, 'ip': '192.0.2.${octet++}'});
  }
}

/// Completes only when the test says so — for writes that "hang" offline.
class HangingWrite {
  final Completer<void> completer = Completer<void>();
  int calls = 0;
  Future<void> call() {
    calls++;
    return completer.future;
  }
}

/// A signed-in Firebase user for screens that watch `authStateProvider`.
/// Only the members those screens read are real; everything else throws.
class FakeAuthUser implements fb.User {
  FakeAuthUser({
    this.uid = kTestUid,
    this.email = kTestEmail,
    this.displayName = 'Pat Customer',
  });

  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;
  @override
  String? get photoURL => null;
  @override
  bool get isAnonymous => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeAuthUser: ${invocation.memberName}');
}
