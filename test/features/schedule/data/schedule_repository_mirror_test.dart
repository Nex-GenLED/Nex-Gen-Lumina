// test/features/schedule/data/schedule_repository_mirror_test.dart
//
// Prompt 4 coverage for the dual-write ScheduleRepository layer:
//   • add/update/remove/saveAll converge the array and subcollection shapes,
//     in BOTH directions (legacy-primary and subcollection-primary).
//   • the transactional per-user lock closes the concurrent update+remove
//     lost-update race (proven against the old bare read-modify-write below).
//   • a mirror failure never fails the primary write.
//   • a nested-array wledPayload survives array→sub and sub→array mirroring
//     byte-identical (the #84 regression guard).
//   • Addition A: an id containing '/' round-trips add→mirror→remove→mirror
//     with both stores converging (sub doc uses the sanitized id, array uses
//     the raw id, remove translates).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/data/legacy_array_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/data/schedule_store_sync.dart';
import 'package:nexgen_command/features/schedule/data/subcollection_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

ScheduleItem _mk(
  String id, {
  String actionLabel = 'Pattern: Warm White',
  bool enabled = true,
  Map<String, dynamic>? wledPayload,
}) =>
    ScheduleItem(
      id: id,
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Mon', 'Wed', 'Fri'],
      actionLabel: actionLabel,
      enabled: enabled,
      wledPayload: wledPayload,
    );

/// Order-independent set of encoded items for convergence comparison.
Set<String> _enc(List<ScheduleItem> items) =>
    items.map((e) => jsonEncode(e.toJson())).toSet();

Future<List<ScheduleItem>> _arrayItems(
    FakeFirebaseFirestore fs, String uid) async {
  final doc = await fs.collection('users').doc(uid).get();
  return decodeScheduleArray(doc.data());
}

Future<List<ScheduleItem>> _subItems(
    FakeFirebaseFirestore fs, String uid) async {
  final snap =
      await fs.collection('users').doc(uid).collection('schedules').get();
  return snap.docs.map((d) => ScheduleItem.fromJson(d.data())).toList();
}

/// Asserts the array field and the subcollection hold the same item set.
Future<void> _expectConverged(FakeFirebaseFirestore fs, String uid) async {
  expect(_enc(await _arrayItems(fs, uid)), _enc(await _subItems(fs, uid)),
      reason: 'array and subcollection must converge');
}

/// A Firestore whose every collection() access throws — used as the mirror
/// target to prove a mirror failure can't fail the primary write.
class _ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    throw StateError('mirror boom');
  }
}

/// Seeds an empty user doc so array .update()/transactions have a doc to hit.
Future<void> _seedUser(FakeFirebaseFirestore fs, String uid) =>
    fs.collection('users').doc(uid).set({'schedules': <dynamic>[]});

void main() {
  group('LegacyArrayScheduleRepository (array primary) mirrors to subcollection',
      () {
    test('add converges both shapes', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-add-legacy';
      await _seedUser(fs, uid);
      final repo = LegacyArrayScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('a'));
      await repo.lastMirror;

      expect(_enc(await _arrayItems(fs, uid)), {jsonEncode(_mk('a').toJson())});
      await _expectConverged(fs, uid);
    });

    test('update converges both shapes', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-upd-legacy';
      await _seedUser(fs, uid);
      final repo = LegacyArrayScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('a'));
      await repo.lastMirror;
      await repo.update(uid, _mk('a', actionLabel: 'Pattern: Red'));
      await repo.lastMirror;

      final arr = await _arrayItems(fs, uid);
      expect(arr.single.actionLabel, 'Pattern: Red');
      await _expectConverged(fs, uid);
    });

    test('remove converges both shapes', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-rem-legacy';
      await _seedUser(fs, uid);
      final repo = LegacyArrayScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('a'));
      await repo.lastMirror;
      await repo.add(uid, _mk('b'));
      await repo.lastMirror;
      await repo.remove(uid, 'a');
      await repo.lastMirror;

      expect((await _arrayItems(fs, uid)).map((e) => e.id), ['b']);
      await _expectConverged(fs, uid);
    });

    test('saveAll converges both shapes (mirror awaited, no lastMirror needed)',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-save-legacy';
      await _seedUser(fs, uid);
      final repo = LegacyArrayScheduleRepository(firestore: fs);

      // Pre-existing item that saveAll must drop from BOTH stores.
      await repo.add(uid, _mk('old'));
      await repo.lastMirror;

      await repo.saveAll(uid, [_mk('x'), _mk('y')]);
      // No await lastMirror: saveAll blocks on its mirror (Addition B).

      expect((await _arrayItems(fs, uid)).map((e) => e.id).toSet(), {'x', 'y'});
      await _expectConverged(fs, uid);
    });
  });

  group(
      'SubcollectionScheduleRepository (subcollection primary) mirrors to array',
      () {
    test('add converges both shapes', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-add-sub';
      await _seedUser(fs, uid);
      final repo = SubcollectionScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('a'));
      await repo.lastMirror;

      expect((await _subItems(fs, uid)).map((e) => e.id), ['a']);
      await _expectConverged(fs, uid);
    });

    test('update converges both shapes', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-upd-sub';
      await _seedUser(fs, uid);
      final repo = SubcollectionScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('a'));
      await repo.lastMirror;
      await repo.update(uid, _mk('a', actionLabel: 'Pattern: Blue'));
      await repo.lastMirror;

      expect((await _arrayItems(fs, uid)).single.actionLabel, 'Pattern: Blue');
      await _expectConverged(fs, uid);
    });

    test('remove converges both shapes', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-rem-sub';
      await _seedUser(fs, uid);
      final repo = SubcollectionScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('a'));
      await repo.lastMirror;
      await repo.add(uid, _mk('b'));
      await repo.lastMirror;
      await repo.remove(uid, 'a');
      await repo.lastMirror;

      expect((await _subItems(fs, uid)).map((e) => e.id), ['b']);
      await _expectConverged(fs, uid);
    });

    test('saveAll converges both shapes (mirror awaited)', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-save-sub';
      await _seedUser(fs, uid);
      final repo = SubcollectionScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('old'));
      await repo.lastMirror;

      await repo.saveAll(uid, [_mk('x'), _mk('y')]);

      expect((await _subItems(fs, uid)).map((e) => e.id).toSet(), {'x', 'y'});
      await _expectConverged(fs, uid);
    });
  });

  group('concurrent update + remove closes the lost-update race', () {
    test('serialized transactional RMW keeps both effects', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-race';
      // Seed array with X and Y directly.
      await fs.collection('users').doc(uid).set({
        'schedules': [
          _mk('x').toJson(),
          _mk('y').toJson(),
        ],
      });
      final repo = LegacyArrayScheduleRepository(firestore: fs);

      // Fire concurrently: update Y's label AND remove X. With a bare
      // get-then-write these clobber (one reads stale, overwrites the other).
      await Future.wait([
        repo.update(uid, _mk('y', actionLabel: 'Pattern: Changed')),
        repo.remove(uid, 'x'),
      ]);

      final arr = await _arrayItems(fs, uid);
      expect(arr.map((e) => e.id), ['y'],
          reason: 'X removed and Y survived — no lost update');
      expect(arr.single.actionLabel, 'Pattern: Changed',
          reason: "Y's update was not clobbered by the concurrent remove");
    });
  });

  group('mirror execution is serialized per uid (ordering chain)', () {
    // Delay ONLY the update mirror so, unchained, its write lands AFTER the
    // later remove's write and resurrects the deleted item. Chaining forces the
    // update mirror to fully complete before the remove mirror runs.
    Future<void> Function(String) delayUpdateMirror() =>
        (label) => label.contains('update')
            ? Future<void>.delayed(const Duration(milliseconds: 60))
            : Future<void>.value();

    test('legacy→sub: delayed update mirror must not resurrect deleted doc',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-order-legacy';
      await _seedUser(fs, uid);
      final repo = LegacyArrayScheduleRepository(firestore: fs);
      await repo.add(uid, _mk('x'));
      await repo.lastMirror;

      mirrorDelayHook = delayUpdateMirror();
      addTearDown(() => mirrorDelayHook = null);

      await repo.update(uid, _mk('x', actionLabel: 'Pattern: Red'));
      await repo.remove(uid, 'x');
      await repo.lastMirror; // chain tail — awaits BOTH mirrors when chained
      // Extra settle so the unchained variant's delayed update mirror (which
      // remove's future does NOT await) has time to wrongly resurrect x.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(await _subItems(fs, uid), isEmpty,
          reason: "update's delayed mirror must not resurrect removed doc");
      await _expectConverged(fs, uid);
    });

    test('sub→array: delayed update mirror must not resurrect deleted item',
        () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-order-sub';
      await _seedUser(fs, uid);
      final repo = SubcollectionScheduleRepository(firestore: fs);
      await repo.add(uid, _mk('x'));
      await repo.lastMirror;

      mirrorDelayHook = delayUpdateMirror();
      addTearDown(() => mirrorDelayHook = null);

      await repo.update(uid, _mk('x', actionLabel: 'Pattern: Blue'));
      await repo.remove(uid, 'x');
      await repo.lastMirror;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(await _arrayItems(fs, uid), isEmpty,
          reason: "update's delayed array mirror must not resurrect removed item");
      await _expectConverged(fs, uid);
    });
  });

  group('mirror failure never fails the primary write', () {
    test('legacy add: primary persists though subcollection mirror throws',
        () async {
      final good = FakeFirebaseFirestore();
      const uid = 'u-mirrorfail-legacy';
      await _seedUser(good, uid);
      final repo = LegacyArrayScheduleRepository(
          firestore: good, mirrorFirestore: _ThrowingFirestore());

      await repo.add(uid, _mk('a')); // must not throw
      await repo.lastMirror; // swallowed failure completes normally

      expect((await _arrayItems(good, uid)).map((e) => e.id), ['a']);
    });

    test('subcollection add: primary persists though array mirror throws',
        () async {
      final good = FakeFirebaseFirestore();
      const uid = 'u-mirrorfail-sub';
      await _seedUser(good, uid);
      final repo = SubcollectionScheduleRepository(
          firestore: good, mirrorFirestore: _ThrowingFirestore());

      await repo.add(uid, _mk('a'));
      await repo.lastMirror;

      expect((await _subItems(good, uid)).map((e) => e.id), ['a']);
    });
  });

  group('#84 guard: nested-array wledPayload survives mirroring byte-identical',
      () {
    final nested = <String, dynamic>{
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'col': [
            [255, 0, 0, 0],
            [0, 255, 0, 0],
          ],
        }
      ],
    };
    final encoded = jsonEncode(nested);

    test('array → subcollection', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-wled-a2s';
      await _seedUser(fs, uid);
      final repo = LegacyArrayScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('w', wledPayload: nested));
      await repo.lastMirror;

      // Typed round-trip equals the original map.
      final subItem = (await _subItems(fs, uid)).single;
      expect(jsonEncode(subItem.wledPayload), encoded);

      // Raw stored field is the verbatim encoded String (never decoded).
      final subDoc =
          await fs.collection('users').doc(uid).collection('schedules').doc('w').get();
      expect(subDoc.data()!['wledPayload'], encoded);
    });

    test('subcollection → array', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-wled-s2a';
      await _seedUser(fs, uid);
      final repo = SubcollectionScheduleRepository(firestore: fs);

      await repo.add(uid, _mk('w', wledPayload: nested));
      await repo.lastMirror;

      final arrItem = (await _arrayItems(fs, uid)).single;
      expect(jsonEncode(arrItem.wledPayload), encoded);

      final userDoc = await fs.collection('users').doc(uid).get();
      final stored = (userDoc.data()!['schedules'] as List).first
          as Map<String, dynamic>;
      expect(stored['wledPayload'], encoded);
    });
  });

  group('Addition A: id containing "/" round-trips with converging stores', () {
    test('add → mirror → remove → mirror', () async {
      final fs = FakeFirebaseFirestore();
      const uid = 'u-slash';
      const rawId = 'a/b/c';
      await _seedUser(fs, uid);
      final repo = LegacyArrayScheduleRepository(firestore: fs);

      await repo.add(uid, _mk(rawId));
      await repo.lastMirror;

      // Array keeps the RAW id.
      expect((await _arrayItems(fs, uid)).single.id, rawId);
      // Subcollection doc uses the SANITIZED id, data carries the raw id.
      final subDoc = await fs
          .collection('users')
          .doc(uid)
          .collection('schedules')
          .doc('a_b_c')
          .get();
      expect(subDoc.exists, isTrue);
      expect(subDoc.data()!['id'], rawId);
      await _expectConverged(fs, uid);

      // remove translates the raw id to the sanitized doc id on both stores.
      await repo.remove(uid, rawId);
      await repo.lastMirror;

      expect(await _arrayItems(fs, uid), isEmpty);
      final subDoc2 = await fs
          .collection('users')
          .doc(uid)
          .collection('schedules')
          .doc('a_b_c')
          .get();
      expect(subDoc2.exists, isFalse);
      await _expectConverged(fs, uid);
    });
  });
}
