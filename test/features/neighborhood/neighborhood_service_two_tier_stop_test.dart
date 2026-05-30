// Tests for Prompt 4 — two-tier stop on NeighborhoodService:
//   • selfLeaveSync: flips ONLY the caller's own member flag. Does not
//     touch g.isActive or any other member.
//   • endGroupSync: per-member fan-clear of isParticipating + group-doc
//     clear, with PER-MEMBER failure capture and partial-failure
//     surfacing via EndGroupSyncPartialFailure.
//
// Uses fake_cloud_firestore for happy paths. Partial-failure path
// subclasses NeighborhoodService and overrides the @visibleForTesting
// writeMemberStopFlag hook to inject a deterministic failure on one UID
// without standing up a Firestore mock that fails one path.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late _StubAuth auth;
  late NeighborhoodService service;

  const groupId = 'g1';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = _StubAuth(_StubUser('u1'));
    service = NeighborhoodService(firestore: firestore, auth: auth);
  });

  Future<void> seedGroup({
    required String creatorUid,
    required List<String> memberUids,
    bool isActiveStart = true,
  }) async {
    await firestore.collection('neighborhoods').doc(groupId).set({
      'name': 'Test',
      'inviteCode': 'ABC123',
      'creatorUid': creatorUid,
      'memberUids': memberUids,
      'isActive': isActiveStart,
      'activePatternName': isActiveStart ? 'Test Pattern' : null,
    });
    for (final uid in memberUids) {
      await firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc(uid)
          .set({
        'displayName': 'House $uid',
        'positionIndex': 0,
        'lastSeen': Timestamp.now(),
        'isParticipating': true,
      });
    }
  }

  group('selfLeaveSync — member self-flag clear', () {
    test('flips ONLY the caller\'s own isParticipating to false; '
        'other members and g.isActive untouched', () async {
      await seedGroup(
        creatorUid: 'owner_uid',
        memberUids: const ['u1', 'u2', 'u3'],
      );

      await service.selfLeaveSync(groupId);

      final me = await firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .get();
      expect(me.data()!['isParticipating'], isFalse,
          reason: 'own flag cleared');

      final other1 = await firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc('u2')
          .get();
      final other2 = await firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc('u3')
          .get();
      expect(other1.data()!['isParticipating'], isTrue,
          reason: 'u2 NOT touched');
      expect(other2.data()!['isParticipating'], isTrue,
          reason: 'u3 NOT touched');

      final group =
          await firestore.collection('neighborhoods').doc(groupId).get();
      expect(group.data()!['isActive'], isTrue,
          reason: 'group g.isActive NOT touched by member self-leave');
      expect(group.data()!['activePatternName'], 'Test Pattern',
          reason: 'group activePatternName NOT cleared');
    });

    test('no-op when not signed in', () async {
      await seedGroup(creatorUid: 'owner', memberUids: const ['u1']);
      final unsignedAuth = _StubAuth(null);
      final unsignedService =
          NeighborhoodService(firestore: firestore, auth: unsignedAuth);

      await unsignedService.selfLeaveSync(groupId);

      final m = await firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .get();
      expect(m.data()!['isParticipating'], isTrue,
          reason: 'no write attempted when uid is null');
    });
  });

  group('endGroupSync — owner end-of-group', () {
    test('happy path: flips g.isActive=false + every member flag=false '
        '+ clears activePattern*', () async {
      await seedGroup(
        creatorUid: 'u1',
        memberUids: const ['u1', 'u2', 'u3'],
      );

      await service.endGroupSync(groupId, ['u1', 'u2', 'u3']);

      for (final uid in const ['u1', 'u2', 'u3']) {
        final m = await firestore
            .collection('neighborhoods')
            .doc(groupId)
            .collection('members')
            .doc(uid)
            .get();
        expect(m.data()!['isParticipating'], isFalse,
            reason: '$uid flag cleared');
      }

      final group =
          await firestore.collection('neighborhoods').doc(groupId).get();
      expect(group.data()!['isActive'], isFalse);
      expect(group.data()!['activePatternId'], isNull);
      expect(group.data()!['activePatternName'], isNull);
    });

    test('PARTIAL FAILURE: one member write fails → throws '
        'EndGroupSyncPartialFailure with the failing UID, and '
        'g.isActive is LEFT untouched so owner can retry', () async {
      await seedGroup(
        creatorUid: 'u1',
        memberUids: const ['u1', 'u2', 'u3'],
      );

      final brokenService = _PartialFailureService(
        firestore: firestore,
        auth: auth,
        failOnUid: 'u2',
      );

      Object? thrown;
      try {
        await brokenService.endGroupSync(groupId, ['u1', 'u2', 'u3']);
      } catch (e) {
        thrown = e;
      }

      expect(thrown, isA<EndGroupSyncPartialFailure>(),
          reason: 'partial failure must surface, not swallow');
      final pf = thrown as EndGroupSyncPartialFailure;
      expect(pf.groupId, groupId);
      expect(pf.failures.keys, contains('u2'));
      expect(pf.failures.length, 1, reason: 'only u2 should fail');

      // u1 and u3 succeeded — those flags ARE cleared (we don't roll back
      // the per-member writes; the loud failure tells the owner to retry).
      final u1 = await firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .get();
      expect(u1.data()!['isParticipating'], isFalse);

      // CRITICAL: group doc must NOT be cleared — session remains "active"
      // so owner can retry without losing the session-active state.
      final group =
          await firestore.collection('neighborhoods').doc(groupId).get();
      expect(group.data()!['isActive'], isTrue,
          reason: 'g.isActive left active on partial failure (retry path)');
      expect(group.data()!['activePatternName'], 'Test Pattern',
          reason: 'activePatternName left set on partial failure');
    });

    test('empty member list: clears group doc immediately (no per-member '
        'writes to fail)', () async {
      await seedGroup(creatorUid: 'u1', memberUids: const []);

      await service.endGroupSync(groupId, const []);

      final group =
          await firestore.collection('neighborhoods').doc(groupId).get();
      expect(group.data()!['isActive'], isFalse);
    });
  });
}

/// Minimal FirebaseAuth stub. NeighborhoodService only reads
/// `_auth.currentUser?.uid`, so we only need `currentUser` to return a
/// User-shaped object (or null). noSuchMethod fallback rejects any
/// unexpected method call so the test surface stays tight.
// FirebaseAuth is sealed; subclassing for a scoped test fake is intentional.
// ignore: subtype_of_sealed_class
class _StubAuth implements FirebaseAuth {
  _StubAuth(this._user);
  final User? _user;
  @override
  User? get currentUser => _user;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

// User is sealed; same reasoning as _StubAuth.
// ignore: subtype_of_sealed_class
class _StubUser implements User {
  _StubUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

/// Test subclass that overrides the per-member write hook to throw for a
/// configured UID. Lets the partial-failure path be exercised without
/// standing up a fake Firestore that fails one specific doc path.
class _PartialFailureService extends NeighborhoodService {
  _PartialFailureService({
    required super.firestore,
    required super.auth,
    required this.failOnUid,
  });

  final String failOnUid;

  @override
  Future<void> writeMemberStopFlag(String groupId, String memberUid) async {
    if (memberUid == failOnUid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Simulated rule deny for $memberUid',
      );
    }
    return super.writeMemberStopFlag(groupId, memberUid);
  }
}
