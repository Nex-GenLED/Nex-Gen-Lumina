// test/features/schedule/data/schedule_order_convergence_test.dart
//
// A-5-prime — proves the stable `sortKey` makes the SUBCOLLECTION backend's
// read order reproduce the LEGACY array's insertion order, so every consumer
// the A-5 order-sensitivity gate flagged now CONVERGES under both repos.
//
// This is the re-run (as PERMANENT tests) of the A-5 Step-5 analysis. Before
// sortKey, SubcollectionScheduleRepository ordered by documentId (lexicographic
// id), which diverged from insertion order and changed:
//   • which WLED timers armed (buildCfgPayload / splitByTimerCapacity truncate
//     at 8 slots in list order), and
//   • which schedule won a findCurrentSchedule start-time tie (first-in-list).
// Ordering by `sortKey` (= insertion order) removes both divergences.
//
// RELEASE NOTE (cosmetic, acceptable): the *visible card list* order can still
// differ for a user between the pre-migration array read and the post-migration
// subcollection read IF their existing docs carry the pre-A-5 default sortKey 0
// (they tie) until the backfill stamps index-derived keys. That is card order
// only — no logic (timer arming, current-schedule selection) is affected.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/data/legacy_array_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/data/subcollection_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

/// Item whose id order (lexicographic) is the REVERSE of its sortKey order,
/// so documentId ordering and sortKey ordering are demonstrably different.
ScheduleItem mk(String id, int sortKey, {String time = '7:00 PM'}) => ScheduleItem(
      id: id,
      timeLabel: time,
      offTimeLabel: '11:00 PM', // on+off => 2 timer slots each
      repeatDays: const ['Daily'],
      actionLabel: 'Pattern: $id',
      enabled: true,
      sortKey: sortKey,
    );

Future<void> seedUser(FakeFirebaseFirestore fs, String uid) =>
    fs.collection('users').doc(uid).set({'schedules': <dynamic>[]});

void main() {
  // Insertion order e5,d4,c3,b2,a1 with sortKeys 0..4.
  // Lexicographic id order is the REVERSE (a1,b2,c3,d4,e5) — so orderBy(id)
  // would have produced a different sequence; orderBy(sortKey) reproduces
  // insertion order.
  List<ScheduleItem> fixture() => [
        mk('e5', 0),
        mk('d4', 1),
        mk('c3', 2),
        mk('b2', 3),
        mk('a1', 4),
      ];

  group('dual-write mirror carries sortKey (Step 5)', () {
    test('legacy write mirrors sortKey into subcollection docs verbatim', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-sk-mirror-legacy';
      await seedUser(fs, uid);
      final legacy = LegacyArrayScheduleRepository(firestore: fs);

      await legacy.saveAll(uid, fixture()); // saveAll awaits its sub mirror

      // Array element carries sortKey.
      final arr = (await fs.collection('users').doc(uid).get())
          .data()!['schedules'] as List;
      expect((arr.first as Map)['sortKey'], 0);
      // Subcollection doc carries the same sortKey.
      final subDoc =
          await fs.collection('users').doc(uid).collection('schedules').doc('e5').get();
      expect(subDoc.data()!['sortKey'], 0);
    });

    test('subcollection write mirrors sortKey back into the array', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-sk-mirror-sub';
      await seedUser(fs, uid);
      final sub = SubcollectionScheduleRepository(firestore: fs);

      await sub.saveAll(uid, fixture()); // saveAll awaits its array mirror

      final arr = (await fs.collection('users').doc(uid).get())
          .data()!['schedules'] as List;
      final byId = {for (final e in arr) (e as Map)['id']: e['sortKey']};
      expect(byId['e5'], 0);
      expect(byId['a1'], 4);
    });
  });

  group('read order converges: subcollection(sortKey) == legacy(insertion)', () {
    test('both repos yield identical id order', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-order-converge';
      await seedUser(fs, uid);
      final legacy = LegacyArrayScheduleRepository(firestore: fs);
      final sub = SubcollectionScheduleRepository(firestore: fs);

      // Write once through legacy; dual-write mirror populates the subcollection.
      await legacy.saveAll(uid, fixture());

      final legacyIds = (await legacy.fetchSchedules(uid)).map((e) => e.id).toList();
      final subIds = (await sub.fetchSchedules(uid)).map((e) => e.id).toList();

      expect(legacyIds, ['e5', 'd4', 'c3', 'b2', 'a1'], reason: 'insertion order');
      expect(subIds, legacyIds,
          reason: 'orderBy(sortKey) reproduces insertion order (NOT id order)');
      // Sanity: id order would have been the reverse — proving the fix matters.
      expect(subIds, isNot(equals([...legacyIds]..sort())));
    });
  });

  group('previously-divergent consumers now converge (Step 6)', () {
    test('buildCfgPayload/splitByTimerCapacity: SAME timer subset arms', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-timer-converge';
      await seedUser(fs, uid);
      final legacy = LegacyArrayScheduleRepository(firestore: fs);
      final sub = SubcollectionScheduleRepository(firestore: fs);
      await legacy.saveAll(uid, fixture());

      final legacyList = await legacy.fetchSchedules(uid);
      final subList = await sub.fetchSchedules(uid);

      // 5 off-time schedules => 10 slots wanted, capacity 8 => 4 arm, 1 overflows.
      final armedLegacy =
          ScheduleSyncService.splitByTimerCapacity(legacyList).armed.map((e) => e.id).toList();
      final armedSub =
          ScheduleSyncService.splitByTimerCapacity(subList).armed.map((e) => e.id).toList();

      expect(armedLegacy, ['e5', 'd4', 'c3', 'b2']);
      expect(armedSub, armedLegacy, reason: 'identical arm set + order under both repos');
      expect(ScheduleSyncService.splitByTimerCapacity(legacyList).overflowed, isTrue);
    });

    test('findCurrentSchedule tie: SAME schedule wins under both repos', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-tie-converge';
      await seedUser(fs, uid);
      final legacy = LegacyArrayScheduleRepository(firestore: fs);
      final sub = SubcollectionScheduleRepository(firestore: fs);

      // Two schedules with the SAME on/off window (a start-time tie). Insertion
      // order puts 'zzz' first (sortKey 0) though its id sorts LAST — under the
      // old documentId ordering the subcollection would have iterated 'aaa'
      // first and picked a different winner.
      final tied = [
        mk('zzz', 0, time: '7:00 PM'),
        mk('aaa', 1, time: '7:00 PM'),
      ];
      await legacy.saveAll(uid, tied);

      final legacyList = await legacy.fetchSchedules(uid);
      final subList = await sub.fetchSchedules(uid);

      // now = 8:00 PM, inside the 7-11 window on any day (Daily).
      final now = DateTime(2026, 1, 5, 20, 0);
      final winnerLegacy = ScheduleFinder.findCurrentSchedule(legacyList, now);
      final winnerSub = ScheduleFinder.findCurrentSchedule(subList, now);

      expect(winnerLegacy?.id, 'zzz', reason: 'first in insertion order wins the tie');
      expect(winnerSub?.id, winnerLegacy?.id, reason: 'same winner under both repos');
    });
  });

  group('#84 guard still holds under sortKey', () {
    test('nested-array wledPayload survives with sortKey present, byte-identical', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-sk-wled';
      await seedUser(fs, uid);
      final legacy = LegacyArrayScheduleRepository(firestore: fs);
      final wled = <String, dynamic>{
        'on': true,
        'seg': [
          {'col': [[255, 0, 0, 0], [0, 255, 0, 0]]}
        ],
      };
      final item = ScheduleItem(
        id: 'w', timeLabel: '7:00 PM', repeatDays: const ['Daily'],
        actionLabel: 'Pattern: W', enabled: true, wledPayload: wled, sortKey: 7,
      );
      await legacy.add(uid, item);
      await legacy.lastMirror;

      final subDoc =
          await fs.collection('users').doc(uid).collection('schedules').doc('w').get();
      expect(subDoc.data()!['wledPayload'], jsonEncode(wled));
      expect(subDoc.data()!['sortKey'], 7);
    });
  });
}
