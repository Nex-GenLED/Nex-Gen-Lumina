// test/features/schedule/data/schedule_read_flip_test.dart
//
// A-5 — flag-gated read-path flip + lazy client backfill. Full matrix:
//   • flag OFF                → legacy array stream, insertion order (identical)
//   • flag ON + unmigrated    → lazy backfill fires EXACTLY once (sortKey=index),
//                               then the subcollection stream
//   • flag ON + migrated      → subcollection only, no re-migration
//   • dual-write convergence in every state
//   • eviction sweep's update half works under the subcollection backend
//   • client sortKey assignment == server backfill rule (index-derived)
//
// NOTE: the migrator writes the subcollection directly (one-way from the array,
// like the server backfill) so there is no dangling fire-and-forget mirror; the
// marker is injected as a concrete Timestamp because fake_cloud_firestore
// deadlocks a read that races a serverTimestamp write (real Firestore is fine).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/data/legacy_array_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/data/schedule_lazy_migrator.dart';
import 'package:nexgen_command/features/schedule/data/schedule_repository.dart';
import 'package:nexgen_command/features/schedule/data/schedule_store_sync.dart';
import 'package:nexgen_command/features/schedule/data/subcollection_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedules_subcollection_feature_flag.dart';

ScheduleItem mk(String id, {int sortKey = 0}) => ScheduleItem(
      id: id,
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Daily'],
      actionLabel: 'Pattern: $id',
      enabled: true,
      sortKey: sortKey,
    );

ScheduleLazyMigrator migratorFor(FakeFirebaseFirestore fs) =>
    ScheduleLazyMigrator(firestore: fs, markerValue: Timestamp.now());

/// Seed the legacy array as PRE-migration data (raw maps; sortKey defaults 0).
Future<void> seedArray(
    FakeFirebaseFirestore fs, String uid, List<dynamic> raw,
    {bool migrated = false}) async {
  await fs.collection('users').doc(uid).set({
    'schedules': raw,
    if (migrated) 'schedulesMigratedAt': Timestamp.now(),
  });
}

Future<List<Map<String, dynamic>>> subDocs(
    FakeFirebaseFirestore fs, String uid) async {
  final snap = await fs
      .collection('users')
      .doc(uid)
      .collection('schedules')
      .orderBy('sortKey')
      .get();
  return snap.docs.map((d) => d.data()).toList();
}

void main() {
  setUp(resetScheduleLazyMigrationLocks);

  group('ScheduleLazyMigrator', () {
    test('unmigrated user → backfills subcollection with sortKey = array index',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-mig';
      // Insertion order e5..a1 (ids sort the OTHER way — proves order matters).
      await seedArray(fs, uid, [
        mk('e5').toJson(),
        mk('d4').toJson(),
        mk('c3').toJson(),
        mk('b2').toJson(),
        mk('a1').toJson(),
      ]);

      await migratorFor(fs).ensureMigrated(uid);

      final docs = await subDocs(fs, uid);
      expect(docs.map((d) => d['id']), ['e5', 'd4', 'c3', 'b2', 'a1'],
          reason: 'sortKey order == array insertion order');
      expect(docs.map((d) => d['sortKey']), [0, 1, 2, 3, 4]);
      final user = await fs.collection('users').doc(uid).get();
      expect(user.data()!['schedulesMigratedAt'], isNotNull);
    });

    test('fires EXACTLY once under concurrent calls (in-flight lock)', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-once';
      await seedArray(fs, uid, [mk('a').toJson(), mk('b').toJson()]);
      final migrator = migratorFor(fs);

      await Future.wait([
        migrator.ensureMigrated(uid),
        migrator.ensureMigrated(uid),
        migrator.ensureMigrated(uid),
      ]);

      expect(migrator.migrationRunCount, 1,
          reason: 'concurrent calls share one run');
      expect((await subDocs(fs, uid)).length, 2);
    });

    test('already-migrated (marker present) → no-op, no subcollection writes',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-done';
      await seedArray(fs, uid, [mk('a').toJson()], migrated: true);

      await migratorFor(fs).ensureMigrated(uid);

      expect(await subDocs(fs, uid), isEmpty);
    });

    test('malformed array element consumes its index slot (server parity)',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-malformed';
      // index 0 = valid, index 1 = non-map (skipped), index 2 = valid.
      await seedArray(fs, uid, [mk('a').toJson(), 'not-a-map', mk('c').toJson()]);

      await migratorFor(fs).ensureMigrated(uid);

      final docs = await subDocs(fs, uid);
      expect({for (final d in docs) d['id']: d['sortKey']}, {'a': 0, 'c': 2},
          reason: 'valid items keep TRUE array index; gap at 1 is harmless');
    });

    test('empty array + no marker → stamps marker, no writes', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-empty';
      await seedArray(fs, uid, <dynamic>[]);

      await migratorFor(fs).ensureMigrated(uid);

      expect(await subDocs(fs, uid), isEmpty);
      expect((await fs.collection('users').doc(uid).get())
          .data()!['schedulesMigratedAt'], isNotNull);
    });

    test('client sortKey assignment == server planBackfill rule (index-derived)',
        () async {
      // The server (planBackfill, jest-tested) stamps sortKey = array index for
      // a fresh user; the client does the same. Same input array → [0,1,2].
      final fs = FakeFirebaseFirestore();
      const uid = 'u-parity';
      await seedArray(fs, uid,
          [mk('a').toJson(), mk('b/c').toJson(), mk('d').toJson()]);

      await migratorFor(fs).ensureMigrated(uid);

      final docs = await subDocs(fs, uid);
      // docId uses scheduleSubDocId (b/c → b_c); sortKey = index, matching the
      // functions/test/unit/scheduleMigrationShared.test.js expectation.
      expect(docs.map((d) => d['sortKey']), [0, 1, 2]);
      expect(docs.map((d) => d['id']), ['a', 'b/c', 'd']);
    });
  });

  group('read-path flip matrix (userSchedulesStreamProvider)', () {
    ProviderContainer container({
      required bool flagOn,
      required FakeFirebaseFirestore fs,
      required String uid,
    }) {
      final sub = SubcollectionScheduleRepository(firestore: fs);
      final legacy = LegacyArrayScheduleRepository(firestore: fs);
      final c = ProviderContainer(overrides: [
        effectiveUserUidProvider.overrideWithValue(uid),
        schedulesSubcollectionEnabledSyncProvider.overrideWithValue(flagOn),
        scheduleRepositoryProvider.overrideWithValue(flagOn ? sub : legacy),
        scheduleLazyMigratorProvider.overrideWithValue(migratorFor(fs)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('flag OFF → legacy array stream, insertion order (identical)',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-off';
      await seedArray(fs, uid,
          [mk('e5').toJson(), mk('d4').toJson(), mk('c3').toJson()]);
      final c = container(flagOn: false, fs: fs, uid: uid);

      final list = await c.read(userSchedulesStreamProvider.future);
      expect(list.map((e) => e.id), ['e5', 'd4', 'c3']);
      // No migration under flag OFF.
      expect(await subDocs(fs, uid), isEmpty);
    });

    test('flag ON + unmigrated → lazy backfill then subcollection (sortKey order)',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-on-unmig';
      await seedArray(fs, uid, [
        mk('e5').toJson(),
        mk('d4').toJson(),
        mk('c3').toJson(),
        mk('b2').toJson(),
        mk('a1').toJson(),
      ]);
      final c = container(flagOn: true, fs: fs, uid: uid);

      final list = await c.read(userSchedulesStreamProvider.future);
      // Subcollection read (orderBy sortKey) reproduces insertion order.
      expect(list.map((e) => e.id), ['e5', 'd4', 'c3', 'b2', 'a1']);
      // Migration happened: subcollection populated + marker set.
      expect((await subDocs(fs, uid)).length, 5);
      expect((await fs.collection('users').doc(uid).get())
          .data()!['schedulesMigratedAt'], isNotNull);
    });

    test('flag ON + migrated → subcollection only, no re-migration', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-on-mig';
      // Pre-seed subcollection directly (as if a backfill ran) + marker.
      await seedArray(fs, uid, [mk('x', sortKey: 0).toJson()], migrated: true);
      await subUpsertAll(fs, uid, [mk('x', sortKey: 0), mk('y', sortKey: 1)]);

      final c = container(flagOn: true, fs: fs, uid: uid);
      final list = await c.read(userSchedulesStreamProvider.future);
      expect(list.map((e) => e.id), ['x', 'y']);
    });
  });

  group('dual-write convergence holds with sortKey', () {
    test('legacy write converges array + subcollection', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-conv';
      await fs.collection('users').doc(uid).set({'schedules': <dynamic>[]});
      final legacy = LegacyArrayScheduleRepository(firestore: fs);
      await legacy.saveAll(uid, [mk('a', sortKey: 0), mk('b', sortKey: 1)]);

      final arr = decodeScheduleArray(
          (await fs.collection('users').doc(uid).get()).data());
      final sub = await SubcollectionScheduleRepository(firestore: fs)
          .fetchSchedules(uid);
      expect(arr.map((e) => e.id), sub.map((e) => e.id));
      expect(arr.map((e) => e.sortKey), [0, 1]);
      expect(sub.map((e) => e.sortKey), [0, 1]);
    });
  });

  group('50-capped set persists identically under both repos', () {
    // The notifier caps to 50 before persistence (see schedule_addall_test);
    // here we confirm each backend faithfully stores the capped set of 50.
    List<ScheduleItem> capped() =>
        [for (var i = 0; i < 50; i++) mk('c$i', sortKey: i)];

    test('legacy array backend stores exactly 50', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-cap-legacy';
      await fs.collection('users').doc(uid).set({'schedules': <dynamic>[]});
      await LegacyArrayScheduleRepository(firestore: fs).saveAll(uid, capped());
      final arr = decodeScheduleArray(
          (await fs.collection('users').doc(uid).get()).data());
      expect(arr.length, 50);
    });

    test('subcollection backend stores exactly 50', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-cap-sub';
      await fs.collection('users').doc(uid).set({'schedules': <dynamic>[]});
      await SubcollectionScheduleRepository(firestore: fs).saveAll(uid, capped());
      final items =
          await SubcollectionScheduleRepository(firestore: fs).fetchSchedules(uid);
      expect(items.length, 50);
    });
  });

  group('eviction sweep update-half works under subcollection backend', () {
    test('clearing disabledUntil via subcollection repo re-enables the item',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-evict';
      await fs.collection('users').doc(uid).set({'schedules': <dynamic>[]});
      final sub = SubcollectionScheduleRepository(firestore: fs);
      final past = DateTime.now().subtract(const Duration(minutes: 10));
      final evicted = mk('s1', sortKey: 0).copyWith(disabledUntil: past);
      await sub.add(uid, evicted);
      await sub.lastMirror;

      // The sweep's update half: clear the field (mirrors the calendar sweep).
      await sub.update(uid, evicted.copyWith(clearDisabledUntil: true));
      await sub.lastMirror;

      final after = await sub.fetchSchedules(uid);
      expect(after.single.disabledUntil, isNull);
      expect(after.single.isCurrentlyEvicted, isFalse);
      expect(after.single.sortKey, 0, reason: 'sortKey preserved through update');
    });
  });
}
