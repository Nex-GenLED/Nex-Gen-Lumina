// lib/features/schedule/data/legacy_array_schedule_repository.dart
//
// The default [ScheduleRepository] backend: schedules live as the `schedules`
// array field on the /users/{uid} document.
//
// The bodies below are EXTRACTED VERBATIM from UserService's former schedule
// methods (fetchSchedulesFromServer, saveSchedules, addSchedule, addSchedules,
// removeSchedule, updateSchedule, streamSchedules) plus their private helpers
// (_writeWithRetry, verifyServerWrite). Firestore behaviour — arrayUnion paths,
// UserService.sanitizeForFirestore usage, whole-array read-modify-write,
// best-effort server verification, retry/backoff — is byte-for-byte identical
// to prior releases.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/data/schedule_repository.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/services/user_service.dart';

class LegacyArrayScheduleRepository implements ScheduleRepository {
  LegacyArrayScheduleRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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
    final data = doc.data()!;
    return (data['schedules'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map((e) => ScheduleItem.fromJson(e))
            .toList() ??
        [];
  }

  @override
  Future<void> saveAll(String userId, List<ScheduleItem> schedules) async {
    await _writeWithRetry(() async {
      await _firestore.collection('users').doc(userId).update(
        UserService.sanitizeForFirestore({
          'schedules': schedules.map((e) => e.toJson()).toList(),
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
  }

  @override
  Future<void> remove(String userId, String scheduleId) async {
    await _writeWithRetry(() async {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final schedules = (data['schedules'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => ScheduleItem.fromJson(e))
              .where((s) => s.id != scheduleId)
              .toList() ??
          [];

      await _firestore.collection('users').doc(userId).update(
        UserService.sanitizeForFirestore({
          'schedules': schedules.map((e) => e.toJson()).toList(),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
    });
    debugPrint('✅ Schedule removed: $scheduleId');
  }

  @override
  Future<void> update(String userId, ScheduleItem schedule) async {
    await _writeWithRetry(() async {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final schedules = (data['schedules'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => ScheduleItem.fromJson(e))
              .map((s) => s.id == schedule.id ? schedule : s)
              .toList() ??
          [];

      await _firestore.collection('users').doc(userId).update(
        UserService.sanitizeForFirestore({
          'schedules': schedules.map((e) => e.toJson()).toList(),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
    });
    debugPrint('✅ Schedule updated: ${schedule.id}');
  }

  @override
  Stream<List<ScheduleItem>> streamSchedules(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return [];
      final data = doc.data()!;
      return (data['schedules'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => ScheduleItem.fromJson(e))
              .toList() ??
          [];
    });
  }
}
