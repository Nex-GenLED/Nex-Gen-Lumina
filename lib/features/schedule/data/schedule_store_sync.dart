// lib/features/schedule/data/schedule_store_sync.dart
//
// Shared primitives for the two ScheduleRepository backends and the dual-write
// mirroring that keeps them convergent during the array→subcollection
// migration:
//
//   • scheduleSubDocId    — the ONE id→doc-id mapping used by BOTH the
//                           subcollection repo and every mirror path. The
//                           array field stores the RAW ScheduleItem.id; the
//                           subcollection uses this sanitized form as the
//                           document id.
//   • applyArrayTxn       — the transactional, per-user-serialized
//                           read-modify-write of the `schedules` array. Closes
//                           the lost-update race that non-transactional
//                           get-then-write suffered. Used by the legacy repo's
//                           primary remove/update AND by the subcollection
//                           repo's mirror-back-to-array.
//   • sub* / overwriteArray — the mirror write primitives.
//   • runMirror           — the single best-effort wrapper: a mirror failure is
//                           logged and swallowed, never surfaced to the user,
//                           never fails the primary write.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/utils/async_lock.dart';

/// Maps a [ScheduleItem.id] to a Firestore-legal subcollection document id.
///
/// Firestore document ids may not contain '/'. ScheduleItem.id is expected to
/// be a slash-free uuid; if one ever does contain '/', we log and fall back to
/// a sanitized copy rather than crashing a write. The array field always keeps
/// the RAW id (inside the item's toJson), so this mapping is applied ONLY at
/// the subcollection boundary — and identically on both the write and mirror
/// paths, so the two stores stay addressable from each other.
String scheduleSubDocId(String id) {
  if (id.contains('/')) {
    debugPrint(
        '⚠️ ScheduleItem.id "$id" contains "/" — sanitizing for subcollection doc id');
    return id.replaceAll('/', '_');
  }
  return id;
}

/// Decodes the `schedules` array field into typed items. Non-map elements are
/// skipped (matches every prior read path).
List<ScheduleItem> decodeScheduleArray(Map<String, dynamic>? data) {
  return (data?['schedules'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map((e) => ScheduleItem.fromJson(e))
          .toList() ??
      <ScheduleItem>[];
}

/// Pure upsert: replace the item with a matching id, else append.
List<ScheduleItem> upsertInto(List<ScheduleItem> current, ScheduleItem item) {
  final idx = current.indexWhere((s) => s.id == item.id);
  if (idx >= 0) {
    final next = List<ScheduleItem>.from(current);
    next[idx] = item;
    return next;
  }
  return [...current, item];
}

// Per-user FIFO mutex over the array field. Two schedule mutations issued from
// different surfaces in the SAME isolate (the notifier fires remove/update from
// multiple pages) each read the whole array and write it back; the lock
// serializes that read-modify-write so neither loses the other's change.
//
// Honest scope — the lock is NOT the sole race guard:
//   • Real Firestore runTransaction already RETRIES on a conflicting commit,
//     including same-isolate concurrent transactions, so production correctness
//     does not hinge on this lock.
//   • What the lock actually buys us: (i) deterministic tests under
//     fake_cloud_firestore, whose runTransaction is a passthrough with no
//     isolation or retry; and (ii) avoiding transaction-retry latency on the
//     write hot path by serializing locally before we ever hit the server.
//   • Cross-process races (another device / the bridge) are covered by
//     runTransaction, not the lock.
// Keyed by uid so distinct users never contend.
final Map<String, AsyncLock> _arrayLocks = <String, AsyncLock>{};
AsyncLock _arrayLockFor(String uid) =>
    _arrayLocks.putIfAbsent(uid, () => AsyncLock());

/// Transactional, per-user-serialized read-modify-write of the `schedules`
/// array. [transform] receives the current decoded list and returns the next
/// list. A missing user doc is a no-op (matches legacy remove/update, which
/// early-returned when the doc did not exist).
Future<void> applyArrayTxn(
  FirebaseFirestore firestore,
  String uid,
  List<ScheduleItem> Function(List<ScheduleItem> current) transform,
) {
  return _arrayLockFor(uid).synchronized(() async {
    final ref = firestore.collection('users').doc(uid);
    await firestore.runTransaction((txn) async {
      final snap = await txn.get(ref);
      if (!snap.exists) return;
      final current = decodeScheduleArray(snap.data());
      final next = transform(current);
      txn.update(
        ref,
        UserService.sanitizeForFirestore({
          'schedules': next.map((e) => e.toJson()).toList(),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
    });
  });
}

/// Deliberate whole-array overwrite (saveAll's contract, and its mirror). Not
/// serialized/transactional by design — replace-everything is authoritative.
Future<void> overwriteArray(
    FirebaseFirestore firestore, String uid, List<ScheduleItem> items) {
  return firestore.collection('users').doc(uid).update(
        UserService.sanitizeForFirestore({
          'schedules': items.map((e) => e.toJson()).toList(),
          'updated_at': FieldValue.serverTimestamp(),
        }),
      );
}

CollectionReference<Map<String, dynamic>> _subCol(
        FirebaseFirestore firestore, String uid) =>
    firestore.collection('users').doc(uid).collection('schedules');

/// Upsert one item into the subcollection (doc id = [scheduleSubDocId]).
Future<void> subUpsert(
    FirebaseFirestore firestore, String uid, ScheduleItem item) {
  return _subCol(firestore, uid)
      .doc(scheduleSubDocId(item.id))
      .set(UserService.sanitizeForFirestore(item.toJson()));
}

/// Upsert many items into the subcollection in a single batch.
Future<void> subUpsertAll(
    FirebaseFirestore firestore, String uid, List<ScheduleItem> items) async {
  if (items.isEmpty) return;
  final col = _subCol(firestore, uid);
  final batch = firestore.batch();
  for (final item in items) {
    batch.set(col.doc(scheduleSubDocId(item.id)),
        UserService.sanitizeForFirestore(item.toJson()));
  }
  await batch.commit();
}

/// Delete one item from the subcollection by RAW id (translated internally).
Future<void> subDelete(
    FirebaseFirestore firestore, String uid, String rawId) {
  return _subCol(firestore, uid).doc(scheduleSubDocId(rawId)).delete();
}

/// Replace the entire subcollection with [items]: batched set of the new set +
/// delete of any existing doc absent from it.
Future<void> subReplaceAll(
    FirebaseFirestore firestore, String uid, List<ScheduleItem> items) async {
  final col = _subCol(firestore, uid);
  final existing = await col.get();
  final nextIds = items.map((s) => scheduleSubDocId(s.id)).toSet();
  final batch = firestore.batch();
  for (final doc in existing.docs) {
    if (!nextIds.contains(doc.id)) batch.delete(doc.reference);
  }
  for (final item in items) {
    batch.set(col.doc(scheduleSubDocId(item.id)),
        UserService.sanitizeForFirestore(item.toJson()));
  }
  await batch.commit();
}

/// Test-only seam: when set, [runMirror] awaits `mirrorDelayHook(label)` before
/// executing a mirror op. Lets a test force out-of-order completion to prove
/// mirror execution is serialized per uid. Never set in production.
@visibleForTesting
Future<void> Function(String label)? mirrorDelayHook;

// Per-uid mirror EXECUTION chain. Single-item mirrors are issued
// fire-and-forget so the primary write never blocks on them — but they must
// still RUN in issue order per user. Without this, an update's subUpsert
// completing after a later remove's subDelete would resurrect a just-deleted
// subcollection doc (and the reverse for the array mirror). Chaining each
// mirror onto the prior one for that uid preserves order without blocking the
// primary write; each segment swallows its own error so one failed mirror can
// never break ordering for the next.
final Map<String, Future<void>> _mirrorChains = <String, Future<void>>{};

/// The single best-effort mirror wrapper. Keeps the OTHER store in sync during
/// dual-write; a failure is logged and swallowed — it never fails, or is even
/// visible to, the primary write. Execution is serialized per [uid] via
/// [_mirrorChains]. Returns the chain tail so callers can track/await it.
Future<void> runMirror(String uid, String label, Future<void> Function() op) {
  final prior = _mirrorChains[uid] ?? Future<void>.value();
  final next = prior.then((_) async {
    try {
      final hook = mirrorDelayHook;
      if (hook != null) await hook(label);
      await op();
    } catch (e, st) {
      debugPrint('⚠️ schedule mirror failed ($label): $e\n$st');
    }
  });
  _mirrorChains[uid] = next;
  return next;
}
