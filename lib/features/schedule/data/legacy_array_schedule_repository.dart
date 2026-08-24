// lib/features/schedule/data/legacy_array_schedule_repository.dart
//
// The default [ScheduleRepository] backend: schedules live as the `schedules`
// array field on the /users/{uid} document.
//
// Prompt 3 extracted the former UserService bodies here verbatim. Prompt 4
// makes two behavioural changes, both about correctness/convergence — never
// about what the caller observes:
//
//   1. remove() and update() are now transactional, per-user-serialized
//      read-modify-writes (applyArrayTxn) instead of a bare get-then-write.
//      This closes the lost-update race that was the whole reason the
//      subcollection migration exists. add/addAll (arrayUnion) and saveAll
//      (deliberate whole-array overwrite) are unchanged.
//
//   2. Every successful primary write mirrors its delta to the
//      /users/{uid}/schedules/{id} subcollection so both shapes converge
//      regardless of the schedules_subcollection flag. Mirrors are best-effort
//      (runMirror swallows failures). saveAll AWAITS its mirror so a following
//      read under the subcollection repo is deterministic; the single-item
//      mirrors are fire-and-forget (kept off the write hot path) but exposed
//      via [lastMirror] so tests can await convergence.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/data/schedule_repository.dart';
import 'package:nexgen_command/features/schedule/data/schedule_store_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/scope_sidecar.dart';
import 'package:nexgen_command/services/user_service.dart';

class LegacyArrayScheduleRepository implements ScheduleRepository {
  LegacyArrayScheduleRepository({
    FirebaseFirestore? firestore,
    FirebaseFirestore? mirrorFirestore,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _mirrorFirestore = mirrorFirestore ?? firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Firestore used for the subcollection mirror. Defaults to [_firestore];
  /// injectable so a test can point the mirror at a failing store to prove the
  /// primary write still succeeds.
  final FirebaseFirestore _mirrorFirestore;

  /// The most recent fire-and-forget mirror future. Non-blocking mirror paths
  /// (add/addAll/update/remove) assign it so tests can `await repo.lastMirror`
  /// to observe convergence deterministically. Never awaited in production.
  @visibleForTesting
  Future<void>? lastMirror;

  static const _retryDelays = [Duration(seconds: 2), Duration(seconds: 5)];

  /// Attempts a Firestore write with automatic retry on transient failure.
  /// Throws the LAST exception if all attempts fail — callers (and the
  /// schedule notifier) need the real cause to show users a meaningful
  /// error instead of a generic "check connection" snackbar.
  Future<void> _writeWithRetry(Future<void> Function() writeOp) async {
    Object? lastError;
    StackTrace? lastStack;

    try {
      await writeOp();
      return;
    } catch (e, stack) {
      lastError = e;
      lastStack = stack;
      debugPrint('❌ Schedule write failed (attempt 1): $e\n$stack');
    }

    for (int i = 0; i < _retryDelays.length; i++) {
      await Future.delayed(_retryDelays[i]);
      try {
        await writeOp();
        debugPrint('✅ Schedule write succeeded on retry ${i + 2}');
        return;
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;
        debugPrint('❌ Schedule write failed (attempt ${i + 2}): $e\n$stack');
      }
    }

    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  /// Verifies a schedule write reached the Firestore server by reading
  /// back with [Source.server] (bypasses local cache).
  Future<bool> _verifyServerWrite(String userId, int expectedCount) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      final serverSchedules = doc.data()?['schedules'] as List?;
      return serverSchedules != null && serverSchedules.length == expectedCount;
    } catch (e) {
      debugPrint('⚠️ Server verification failed (offline?): $e');
      return false;
    }
  }

  @override
  Future<List<ScheduleItem>> fetchSchedules(String userId) async {
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .get(const GetOptions(source: Source.server));
    if (!doc.exists) return [];
    return decodeScheduleArray(doc.data());
  }

  @override
  Future<void> saveAll(String userId, List<ScheduleItem> schedules) async {
    await _writeWithRetry(() async {
      await _firestore.collection('users').doc(userId).update(
        UserService.sanitizeForFirestore({
          'schedules': schedules.map((e) => e.toJson()).toList(),
          // D1 — the durable channel-scope sidecar. Written alongside the array
          // because an old build rewrites the array wholesale and would
          // otherwise silently un-scope every schedule in the account.
          kScheduleScopeField: scheduleScopeSidecar(schedules),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
    });

    // Verification is informational only. We log a warning on mismatch but
    // never fail the call — a stale/offline read shouldn't roll back a
    // successful Firestore write in the caller's eyes.
    final verified = await _verifyServerWrite(userId, schedules.length);
    if (!verified) {
      debugPrint('⚠️ saveSchedules: write accepted but server verification failed');
    } else {
      debugPrint('✅ Schedules saved and verified: ${schedules.length} items');
    }

    // AWAITED mirror: saveAll is the bulk path a cross-repo read commonly
    // follows, so we block on convergence here (Addition B).
    await runMirror(userId, 'legacy.saveAll->sub',
        () => subReplaceAll(_mirrorFirestore, userId, schedules));
  }

  @override
  Future<void> add(String userId, ScheduleItem schedule) async {
    await _writeWithRetry(() async {
      await _firestore.collection('users').doc(userId).update(
        UserService.sanitizeForFirestore({
          'schedules':
              FieldValue.arrayUnion([UserService.sanitizeForFirestore(schedule.toJson())]),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
    });
    debugPrint('✅ Schedule added: ${schedule.id}');
    lastMirror = runMirror(userId, 'legacy.add->sub',
        () => subUpsert(_mirrorFirestore, userId, schedule));
  }

  @override
  Future<void> addAll(String userId, List<ScheduleItem> items) async {
    if (items.isEmpty) return;
    await _writeWithRetry(() async {
      await _firestore.collection('users').doc(userId).update(
        UserService.sanitizeForFirestore({
          'schedules': FieldValue.arrayUnion(
            items.map((i) => UserService.sanitizeForFirestore(i.toJson())).toList(),
          ),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
    });
    debugPrint('✅ ${items.length} schedules added atomically: '
        '${items.map((i) => i.id).join(", ")}');
    lastMirror = runMirror(userId, 'legacy.addAll->sub',
        () => subUpsertAll(_mirrorFirestore, userId, items));
  }

  @override
  Future<void> remove(String userId, String scheduleId) async {
    // Transactional + per-user-serialized: closes the lost-update race a bare
    // get-then-write suffered when remove raced a concurrent update.
    await applyArrayTxn(_firestore, userId,
        (current) => current.where((s) => s.id != scheduleId).toList());
    debugPrint('✅ Schedule removed: $scheduleId');
    lastMirror = runMirror(userId, 'legacy.remove->sub',
        () => subDelete(_mirrorFirestore, userId, scheduleId));
  }

  @override
  Future<void> update(String userId, ScheduleItem schedule) async {
    // In-place update (unknown ids are a no-op, matching the former semantics).
    await applyArrayTxn(
      _firestore,
      userId,
      (current) =>
          current.map((s) => s.id == schedule.id ? schedule : s).toList(),
    );
    debugPrint('✅ Schedule updated: ${schedule.id}');
    lastMirror = runMirror(userId, 'legacy.update->sub',
        () => subUpsert(_mirrorFirestore, userId, schedule));
  }

  @override
  Stream<List<ScheduleItem>> streamSchedules(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? decodeScheduleArray(doc.data()) : <ScheduleItem>[]);
  }
}
