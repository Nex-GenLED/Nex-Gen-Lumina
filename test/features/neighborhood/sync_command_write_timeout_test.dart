// SYNC START WINDOW (2026-11-02), item 5: the group command write is bounded.
//
// Before: `await docRef.set(...)` never completes while Firestore's write
// stream is down, the notifier hung in `loading`, and nothing was shown. Now:
//
//   * the write throws TimeoutException after kSyncCommandWriteTimeout
//     (injectable here), which broadcastSync reports as `write_timeout`;
//   * the group doc is NOT flipped to active — that update runs only after
//     the command write is acknowledged, so a timed-out Start never turns
//     the group on, even if the write lands later;
//   * a delete of the same document is queued behind the timed-out write so
//     a late flush (the SDK keeps the write, across restarts) nets to no
//     document instead of a surprise Start hours later.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/services/error_sink.dart';

const kGroup = 'g-write-timeout';

/// Holds the command write open (the stalled write stream) and records the
/// undo. Everything else is the real service over a fake store.
class _HangingWriteService extends NeighborhoodService {
  _HangingWriteService({required super.firestore, required super.auth});

  final Completer<void> writeGate = Completer<void>();
  final List<String> setIds = [];
  final List<String> deletedIds = [];
  Map<String, dynamic>? heldData;
  DocumentReference<Map<String, dynamic>>? heldRef;

  @override
  Future<void> setCommandDoc(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) {
    setIds.add(ref.id);
    heldRef = ref;
    heldData = data;
    return writeGate.future; // never completes until the test says so
  }

  @override
  Future<void> deleteCommandDoc(DocumentReference<Map<String, dynamic>> ref) async {
    deletedIds.add(ref.id);
  }

  @override
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) async =>
      const FanoutResult(ok: true, memberCount: 2, commandCount: 2, skipped: 0);
}

SyncCommand _cmd() => SyncCommand(
      id: '',
      groupId: kGroup,
      effectId: 28,
      colors: const [0xFF0000, 0x00FF00],
      speed: 128,
      intensity: 128,
      brightness: 200,
      startTimestamp: DateTime.utc(2026, 11, 2, 22, 35, 2),
      memberDelays: const {'u-host': 0, 'u-guest': 9800},
      timingConfig: const SyncTimingConfig(),
      patternName: 'Classic Christmas',
    );

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('neighborhoods').doc(kGroup).set({
    'name': 'w',
    'inviteCode': 'ABC123',
    'creatorUid': 'u-host',
    'memberUids': ['u-host', 'u-guest'],
    'isActive': false,
    'activePatternName': null,
  });
  return db;
}

class _SinkRecorder {
  final List<String> contexts = [];
  Future<void> call({
    required Object error,
    required StackTrace? stack,
    required String context,
  }) async {
    contexts.add(context);
  }
}

void main() {
  test('service: a write not acknowledged in time throws TimeoutException, '
      'queues its own delete, and does NOT flip the group', () async {
    final db = await _seed();
    final svc = _HangingWriteService(firestore: db, auth: _StubAuth(_StubUser('u-host')));

    await expectLater(
      svc.broadcastSyncCommand(_cmd(), writeTimeout: const Duration(milliseconds: 40)),
      throwsA(isA<TimeoutException>()),
    );

    expect(svc.setIds, hasLength(1));
    expect(svc.deletedIds, [svc.setIds.single], reason: 'the undo targets the same document');
    final group = await db.collection('neighborhoods').doc(kGroup).get();
    expect(group.data()!['isActive'], isFalse, reason: 'flip runs only after an acknowledged write');
    expect(group.data()!['activePatternName'], isNull);
  });

  test('service: the write landing LATE still does not flip the group (no surprise late Start)', () async {
    final db = await _seed();
    final svc = _HangingWriteService(firestore: db, auth: _StubAuth(_StubUser('u-host')));

    await expectLater(
      svc.broadcastSyncCommand(_cmd(), writeTimeout: const Duration(milliseconds: 40)),
      throwsA(isA<TimeoutException>()),
    );
    // The stalled write stream recovers: the SDK flushes the held write.
    svc.writeGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final group = await db.collection('neighborhoods').doc(kGroup).get();
    expect(group.data()!['isActive'], isFalse);
    // What the late flush would carry, and what the queued delete removes.
    expect(svc.heldData!['id'], svc.deletedIds.single);
  });

  test('notifier: the timeout is reported as write_timeout, recorded, nothing active', () async {
    final db = await _seed();
    final svc = _HangingWriteService(firestore: db, auth: _StubAuth(_StubUser('u-host')));
    final sink = _SinkRecorder();
    final c = ProviderContainer(overrides: [
      neighborhoodServiceProvider.overrideWithValue(svc),
      syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
      errorReporterProvider.overrideWithValue(sink.call),
    ]);
    addTearDown(c.dispose);

    final result = await c
        .read(neighborhoodNotifierProvider.notifier)
        .broadcastSync(_cmd(), writeTimeout: const Duration(milliseconds: 40));

    expect(result.commandWritten, isFalse);
    expect(result.failure?.reason, 'write_timeout');
    expect(result.failure?.error, isA<TimeoutException>());
    expect(sink.contexts, ['broadcastSync/write_timeout']);
    expect(c.read(neighborhoodNotifierProvider).hasError, isTrue);
  });

  test('a write that completes in time flips the group and reports written', () async {
    final db = await _seed();
    final svc = NeighborhoodService(firestore: db, auth: _StubAuth(_StubUser('u-host')));
    await svc.broadcastSyncCommand(_cmd(), writeTimeout: const Duration(seconds: 5));
    final group = await db.collection('neighborhoods').doc(kGroup).get();
    expect(group.data()!['isActive'], isTrue);
    expect(group.data()!['activePatternName'], 'Classic Christmas');
    final cmds = await db.collection('neighborhoods').doc(kGroup).collection('commands').get();
    expect(cmds.docs, hasLength(1));
  });
}

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

// ignore: subtype_of_sealed_class
class _StubUser implements User {
  _StubUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-id-token';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}
