// lib/features/schedule/data/subcollection_schedule_repository.dart
//
// The subcollection [ScheduleRepository] backend: each schedule is its own
// document under /users/{uid}/schedules/{id}, keyed by scheduleSubDocId(id).
//
// Reachable only when the schedules_subcollection feature flag is ON (default
// false — this migration never flips it). No backfill is wired here.
//
// Every successful primary write mirrors back into the legacy `schedules`
// array so both shapes converge regardless of flag state. The array mirror
// reuses applyArrayTxn (the same transactional, per-user-serialized helper the
// legacy repo's remove/update use). Mirrors are best-effort (runMirror). saveAll
// AWAITS its array mirror so a following read under the legacy repo is
// deterministic (Addition B); single-item mirrors are fire-and-forget but
// exposed via [lastMirror] for tests.
//
// Serialization reuses ScheduleItem.toJson()/fromJson() unchanged; each item's
// encoded wledPayload String passes through verbatim (never decoded).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/data/schedule_repository.dart';
import 'package:nexgen_command/features/schedule/data/schedule_store_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/scope_sidecar.dart';
import 'package:nexgen_command/services/user_service.dart';

class SubcollectionScheduleRepository implements ScheduleRepository {
  SubcollectionScheduleRepository({
    FirebaseFirestore? firestore,
    FirebaseFirestore? mirrorFirestore,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _mirrorFirestore = mirrorFirestore ?? firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Firestore used for the array mirror. Defaults to [_firestore]; injectable
  /// so a test can point the mirror at a failing store.
  final FirebaseFirestore _mirrorFirestore;

  /// Most recent fire-and-forget mirror future — see
  /// LegacyArrayScheduleRepository.lastMirror for the rationale.
  @visibleForTesting
  Future<void>? lastMirror;

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _firestore.collection('users').doc(userId).collection('schedules');

  /// D1 — the durable channel scope for THIS backend lives on the USER doc,
  /// not on the per-schedule doc.
  ///
  /// ⚠️ THE OBVIOUS PLACE DOES NOT WORK. A sidecar field on the schedule's own
  /// document would be wiped by the very thing it defends against: an old build
  /// writes a schedule with `.set(item.toJson())`, and `set` without merge
  /// REPLACES the whole document, taking any sibling field with it. That is the
  /// opposite of the array store, where the sidecar survives because
  /// `update({'schedules': …})` names one field and leaves the rest alone.
  ///
  /// So both backends share ONE durable location: `users/{uid}.schedule_scope`.
  /// It costs a user-doc read per fetch, which is why it is a single read here
  /// rather than a per-document join.
  Future<Map<String, dynamic>?> _scopeSidecar(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final raw = doc.data()?[kScheduleScopeField];
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (e) {
      // A sidecar read failure must never cost the user their schedules; the
      // items still load, just without recovered scope.
      debugPrint('⚠️ schedule scope sidecar read failed: $e');
      return null;
    }
  }

  static List<ScheduleItem> _applyScope(
      List<ScheduleItem> items, Map<String, dynamic>? sidecar) {
    if (sidecar == null || sidecar.isEmpty) return items;
    return [
      for (final i in items)
        if (i.channels != null)
          i
        else
          () {
            final sc = decodeScopeEntry(sidecar, i.id);
            return sc.isScoped
                ? i.copyWith(channels: sc.channels, controllerId: sc.controllerId)
                : i;
          }(),
    ];
  }


  @override
  Stream<List<ScheduleItem>> streamSchedules(String userId) {
    // A-5-prime: ordered by the monotonic `sortKey` so this backend's read
    // order reproduces the legacy array's insertion order (documentId order
    // — the prior key — diverged from insertion order and changed which WLED
    // timers armed / which schedule won findCurrentSchedule ties).
    return _col(userId).orderBy('sortKey').snapshots().asyncMap((snap) async {
      final items =
          snap.docs.map((d) => ScheduleItem.fromJson(d.data())).toList();
      // Only pay for the sidecar read when something actually lost its scope.
      if (items.every((i) => i.channels != null)) return items;
      return _applyScope(items, await _scopeSidecar(userId));
    });
  }

  @override
  Future<List<ScheduleItem>> fetchSchedules(String userId) async {
    final snap = await _col(userId)
        .orderBy('sortKey')
        .get(const GetOptions(source: Source.server));
    final items =
        snap.docs.map((d) => ScheduleItem.fromJson(d.data())).toList();
    if (items.every((i) => i.channels != null)) return items;
    return _applyScope(items, await _scopeSidecar(userId));
  }

  @override
  Future<void> saveAll(String userId, List<ScheduleItem> schedules) async {
    final col = _col(userId);
    // Faithful to "replace the entire set": delete any existing doc whose id
    // isn't in the incoming set, then upsert the rest.
    final existing = await col.get();
    final nextIds = schedules.map((s) => scheduleSubDocId(s.id)).toSet();
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      if (!nextIds.contains(doc.id)) batch.delete(doc.reference);
    }
    for (final item in schedules) {
      batch.set(col.doc(scheduleSubDocId(item.id)),
          UserService.sanitizeForFirestore(item.toJson()));
    }
    await batch.commit();
    debugPrint('✅ Schedules saved (subcollection): ${schedules.length} items');

    // AWAITED mirror (Addition B).
    await runMirror(userId, 'sub.saveAll->array',
        () => overwriteArray(_mirrorFirestore, userId, schedules));
  }

  @override
  Future<void> add(String userId, ScheduleItem schedule) async {
    await _col(userId).doc(scheduleSubDocId(schedule.id)).set(
          UserService.sanitizeForFirestore(schedule.toJson()),
        );
    debugPrint('✅ Schedule added (subcollection): ${schedule.id}');
    lastMirror = runMirror(
        userId,
        'sub.add->array',
        () => applyArrayTxn(_mirrorFirestore, userId,
            (current) => upsertInto(current, schedule)));
  }

  @override
  Future<void> addAll(String userId, List<ScheduleItem> items) async {
    if (items.isEmpty) return;
    final col = _col(userId);
    final batch = _firestore.batch();
    for (final item in items) {
      batch.set(col.doc(scheduleSubDocId(item.id)),
          UserService.sanitizeForFirestore(item.toJson()));
    }
    await batch.commit();
    debugPrint('✅ ${items.length} schedules added atomically (subcollection): '
        '${items.map((i) => i.id).join(", ")}');
    lastMirror = runMirror(userId, 'sub.addAll->array', () {
      return applyArrayTxn(_mirrorFirestore, userId, (current) {
        var acc = current;
        for (final item in items) {
          acc = upsertInto(acc, item);
        }
        return acc;
      });
    });
  }

  @override
  Future<void> remove(String userId, String scheduleId) async {
    await _col(userId).doc(scheduleSubDocId(scheduleId)).delete();
    debugPrint('✅ Schedule removed (subcollection): $scheduleId');
    lastMirror = runMirror(
        userId,
        'sub.remove->array',
        () => applyArrayTxn(_mirrorFirestore, userId,
            (current) => current.where((s) => s.id != scheduleId).toList()));
  }

  @override
  Future<void> update(String userId, ScheduleItem schedule) async {
    await _col(userId).doc(scheduleSubDocId(schedule.id)).set(
          UserService.sanitizeForFirestore(schedule.toJson()),
        );
    debugPrint('✅ Schedule updated (subcollection): ${schedule.id}');
    lastMirror = runMirror(
        userId,
        'sub.update->array',
        () => applyArrayTxn(_mirrorFirestore, userId,
            (current) => upsertInto(current, schedule)));
  }
}
