// lib/features/schedule/data/schedule_lazy_migrator.dart
//
// A-5 lazy-migration safety net. When the schedules_subcollection flag is ON
// but a user's doc has no `schedulesMigratedAt` marker (the server backfill
// hasn't reached them yet), the client migrates their legacy `schedules` array
// into the /users/{uid}/schedules subcollection ONCE, then stamps the marker —
// so a flag-ON-but-unmigrated user never reads an empty subcollection.
//
// This mirrors the SERVER backfill (planBackfill in
// functions/src/scheduleMigrationShared.ts) exactly:
//   • it is array → subcollection ONE-WAY (the array is the source; we do NOT
//     mirror back — writing the subcollection directly via the shared
//     `subUpsertAll` upsert primitive, same as the server writes only the
//     subcollection);
//   • sortKey = RAW array index (non-map elements are skipped but still consume
//     their index slot), preserving any already-positive key. For a fresh
//     (unmigrated) user — array items at the pre-A-5 default sortKey 0 — both
//     sides therefore assign [0,1,2,…] over the valid items, so the
//     subcollection reproduces exact legacy insertion order regardless of which
//     path migrates first.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/data/schedule_store_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

/// Field marker (camelCase) stamped on the user doc once migrated. MUST match
/// the server backfill's field name (backfillSchedulesSubcollection.ts) so the
/// two paths recognize each other's work and neither double-migrates.
const String kSchedulesMigratedAtField = 'schedulesMigratedAt';

// Per-uid in-flight guard, module-level so it survives provider rebuilds (a
// flag re-eval must not let two migrations race). The durable guard is the
// `schedulesMigratedAt` marker; this only dedups concurrent same-session calls.
final Map<String, Future<void>> _migrationInFlight = <String, Future<void>>{};

@visibleForTesting
void resetScheduleLazyMigrationLocks() => _migrationInFlight.clear();

class ScheduleLazyMigrator {
  ScheduleLazyMigrator({
    required FirebaseFirestore firestore,
    Object? markerValue,
  })  : _firestore = firestore,
        _markerValue = markerValue ?? FieldValue.serverTimestamp();

  final FirebaseFirestore _firestore;

  /// Value written to [kSchedulesMigratedAtField]. Defaults to a server
  /// timestamp (server-consistent with the CF backfill). Overridable ONLY as a
  /// test seam: fake_cloud_firestore deadlocks a read when a serverTimestamp
  /// write races a pending transaction. Its actual value is never used for
  /// logic — migration is gated purely on the marker's PRESENCE.
  final Object _markerValue;

  /// Test-only: number of times an actual migration body ran. The in-flight
  /// lock means concurrent [ensureMigrated] calls share ONE run.
  @visibleForTesting
  int migrationRunCount = 0;

  /// Migrate [uid]'s array → subcollection exactly once. Idempotent: a no-op
  /// when the marker is already set (server or a prior client run). Concurrent
  /// calls share one in-flight future.
  Future<void> ensureMigrated(String uid) {
    final existing = _migrationInFlight[uid];
    if (existing != null) return existing;
    // NB: block body — an arrow `=> _migrationInFlight.remove(uid)` would RETURN
    // the removed future (this very future) from the whenComplete callback,
    // making it await itself → deadlock.
    final future = _run(uid).whenComplete(() {
      _migrationInFlight.remove(uid);
    });
    _migrationInFlight[uid] = future;
    return future;
  }

  Future<void> _run(String uid) async {
    migrationRunCount++;
    final userRef = _firestore.collection('users').doc(uid);
    final snap = await userRef.get();
    if (!snap.exists) return;
    final data = snap.data()!;

    // Already migrated (by the server backfill or a prior client run).
    if (data[kSchedulesMigratedAtField] != null) return;

    final rawArray = data['schedules'];
    if (rawArray is List && rawArray.isNotEmpty) {
      // Iterate the RAW array so a non-map element consumes its index slot,
      // byte-for-byte matching the server's planBackfill index accounting.
      final items = <ScheduleItem>[];
      for (var i = 0; i < rawArray.length; i++) {
        final e = rawArray[i];
        if (e is! Map<String, dynamic>) continue; // malformed → skip, keep index
        final item = ScheduleItem.fromJson(e);
        items.add(item.sortKey > 0 ? item : item.copyWith(sortKey: i));
      }
      if (items.isNotEmpty) {
        // Direct subcollection upsert (the same primitive the repository uses),
        // NOT a mirror-bearing repo write: migration is one-way from the array,
        // matching the server backfill which writes only the subcollection.
        await subUpsertAll(_firestore, uid, items);
      }
    }

    // Stamp the marker last, so a mid-migration crash re-runs next launch.
    await userRef.update({kSchedulesMigratedAtField: _markerValue});
    debugPrint('ScheduleLazyMigrator: migrated $uid to subcollection');
  }
}

/// Injects the migrator with the app Firestore. Reachable only under flag ON
/// (the only state in which [ensureMigrated] is invoked).
final scheduleLazyMigratorProvider = Provider<ScheduleLazyMigrator>((ref) {
  return ScheduleLazyMigrator(firestore: FirebaseFirestore.instance);
});
