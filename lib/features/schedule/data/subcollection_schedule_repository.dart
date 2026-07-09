// lib/features/schedule/data/subcollection_schedule_repository.dart
//
// The subcollection [ScheduleRepository] backend: each schedule is its own
// document under /users/{uid}/schedules/{id}, keyed by ScheduleItem.id.
//
// DORMANT by default — only reachable when the schedules_subcollection feature
// flag is ON (it defaults false, and this foundation change never flips it).
// No migration/backfill is wired here.
//
// Serialization reuses ScheduleItem.toJson()/fromJson() unchanged; each item's
// encoded wledPayload String passes through verbatim (never decoded). Writes
// route their map through UserService.sanitizeForFirestore, matching the legacy
// backend's #84 hardening.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/data/schedule_repository.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/services/user_service.dart';

class SubcollectionScheduleRepository implements ScheduleRepository {
  SubcollectionScheduleRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _firestore.collection('users').doc(userId).collection('schedules');

  /// Firestore document IDs cannot contain '/'. ScheduleItem.id is expected to
  /// be a slash-free uuid; assert that in debug and fall back to a sanitized
  /// copy in release so a malformed id can never crash a write.
  String _safeDocId(String id) {
    assert(!id.contains('/'),
        'ScheduleItem.id must not contain "/" for subcollection doc id: $id');
    return id.replaceAll('/', '_');
  }

  @override
  Stream<List<ScheduleItem>> streamSchedules(String userId) {
    // Ordered by document id (== ScheduleItem.id) for a stable, deterministic
    // emission order. No sortKey field is added to ScheduleItem — ordering is
    // by the existing id.
    return _col(userId)
        .orderBy(FieldPath.documentId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ScheduleItem.fromJson(d.data()))
            .toList());
  }

  @override
  Future<List<ScheduleItem>> fetchSchedules(String userId) async {
    final snap = await _col(userId)
        .orderBy(FieldPath.documentId)
        .get(const GetOptions(source: Source.server));
    return snap.docs.map((d) => ScheduleItem.fromJson(d.data())).toList();
  }

  @override
  Future<void> saveAll(String userId, List<ScheduleItem> schedules) async {
    final col = _col(userId);
    // Faithful to the legacy "replace the entire set" semantics: delete any
    // existing doc whose id isn't in the incoming set, then upsert the rest.
    final existing = await col.get();
    final nextIds = schedules.map((s) => _safeDocId(s.id)).toSet();
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      if (!nextIds.contains(doc.id)) batch.delete(doc.reference);
    }
    for (final item in schedules) {
      batch.set(
        col.doc(_safeDocId(item.id)),
        UserService.sanitizeForFirestore(item.toJson()),
      );
    }
    await batch.commit();
    debugPrint('✅ Schedules saved (subcollection): ${schedules.length} items');
  }

  @override
  Future<void> add(String userId, ScheduleItem schedule) async {
    await _col(userId).doc(_safeDocId(schedule.id)).set(
          UserService.sanitizeForFirestore(schedule.toJson()),
        );
    debugPrint('✅ Schedule added (subcollection): ${schedule.id}');
  }

  @override
  Future<void> addAll(String userId, List<ScheduleItem> items) async {
    if (items.isEmpty) return;
    final col = _col(userId);
    final batch = _firestore.batch();
    for (final item in items) {
      batch.set(
        col.doc(_safeDocId(item.id)),
        UserService.sanitizeForFirestore(item.toJson()),
      );
    }
    await batch.commit();
    debugPrint('✅ ${items.length} schedules added atomically (subcollection): '
        '${items.map((i) => i.id).join(", ")}');
  }

  @override
  Future<void> remove(String userId, String scheduleId) async {
    await _col(userId).doc(_safeDocId(scheduleId)).delete();
    debugPrint('✅ Schedule removed (subcollection): $scheduleId');
  }

  @override
  Future<void> update(String userId, ScheduleItem schedule) async {
    await _col(userId).doc(_safeDocId(schedule.id)).set(
          UserService.sanitizeForFirestore(schedule.toJson()),
        );
    debugPrint('✅ Schedule updated (subcollection): ${schedule.id}');
  }
}
