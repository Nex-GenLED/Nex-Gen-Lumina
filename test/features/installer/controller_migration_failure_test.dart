// P0-6 REGRESSION GATE — the controller migration must not fail silently.
//
// `migrateInstallerControllersToCustomer` used to wrap its whole body in
// `try { ... } catch (e) { debugPrint('...(non-blocking)'); }`. A denied or
// dropped migration therefore returned NORMALLY, the wizard carried on to the
// handoff screen, and the installer drove away from a customer whose app would
// be empty on first login. It is also what would have made the P0-5 rules
// denial invisible.
//
// These tests pin: (a) failure propagates, (b) failure leaves the source intact
// so a retry is safe, (c) a retry after a commit that already landed is a
// harmless no-op rather than an error, and (d) the decline path reports the
// install as FAILED.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';

const _staff = 'staff_installer_0101';
const _customer = 'CUST_A';
const _ctrl = 'ctrlA';

/// A WriteBatch whose commit always fails — stands in for a rules denial or a
/// dead network at exactly the wrong moment.
class _ThrowingBatch implements WriteBatch {
  @override
  Future<void> commit() async => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );

  @override
  void delete(DocumentReference<Object?> document) {}

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {}

  @override
  void update(DocumentReference<Object?> document, Map<String, Object?> data) {}
}

/// Reads work normally; only the batch commit explodes.
class _CommitFailsFirestore extends FakeFirebaseFirestore {
  @override
  WriteBatch batch() => _ThrowingBatch();
}

Future<void> _seed(FirebaseFirestore db) async {
  final ctrl =
      db.collection('users').doc(_staff).collection('controllers').doc(_ctrl);
  await ctrl.set({'ip': '192.168.1.150', 'name': 'Front'});
  await ctrl.collection('pixelMap').doc('0').set({'segments': []});
  await ctrl.collection('pixelMap').doc('1').set({'segments': []});
}

Future<List<String>> _controllerIds(FirebaseFirestore db, String uid) async {
  final s = await db.collection('users').doc(uid).collection('controllers').get();
  return s.docs.map((d) => d.id).toList()..sort();
}

void main() {
  group('P0-6 — migration failure propagates instead of being swallowed', () {
    test('THE DEFECT: a failed commit THROWS (it used to return normally)',
        () async {
      final db = _CommitFailsFirestore();
      await _seed(db);

      await expectLater(
        migrateInstallerControllersToCustomer(
          firestore: db,
          fromUid: _staff,
          toUid: _customer,
          controllerIds: {_ctrl},
        ),
        throwsA(isA<FirebaseException>()),
        reason: 'a swallowed failure is reported to the installer as success',
      );
    });

    test('the thrown error carries the specific cause, not a generic message',
        () async {
      final db = _CommitFailsFirestore();
      await _seed(db);

      try {
        await migrateInstallerControllersToCustomer(
          firestore: db,
          fromUid: _staff,
          toUid: _customer,
          controllerIds: {_ctrl},
        );
        fail('should have thrown');
      } on FirebaseException catch (e) {
        // This string is what reaches the installer's dialog.
        expect(e.code, 'permission-denied');
        expect('$e', contains('insufficient permissions'));
      }
    });

    test('a failed migration leaves the SOURCE intact — retry is safe',
        () async {
      final db = _CommitFailsFirestore();
      await _seed(db);

      await expectLater(
        migrateInstallerControllersToCustomer(
          firestore: db,
          fromUid: _staff,
          toUid: _customer,
          controllerIds: {_ctrl},
        ),
        throwsA(isA<FirebaseException>()),
      );

      // Batch writes are atomic: none of them applied.
      expect(await _controllerIds(db, _staff), [_ctrl],
          reason: 'source must survive so Retry has something to move');
      expect(await _controllerIds(db, _customer), isEmpty,
          reason: 'destination must have nothing half-written');
    });
  });

  group('P0-6 — retry semantics', () {
    test('retry after a transient failure completes the migration', () async {
      // First attempt fails, second attempt uses a working backend seeded
      // identically — i.e. the source was never consumed.
      final failing = _CommitFailsFirestore();
      await _seed(failing);
      await expectLater(
        migrateInstallerControllersToCustomer(
          firestore: failing,
          fromUid: _staff,
          toUid: _customer,
          controllerIds: {_ctrl},
        ),
        throwsA(isA<FirebaseException>()),
      );

      final ok = FakeFirebaseFirestore();
      await _seed(ok);
      final result = await migrateInstallerControllersToCustomer(
        firestore: ok,
        fromUid: _staff,
        toUid: _customer,
        controllerIds: {_ctrl},
      );

      expect(result.movedAnything, isTrue);
      expect(result.controllers, 1);
      expect(result.pixelMapDocs, 2);
      expect(await _controllerIds(ok, _customer), [_ctrl]);
      expect(await _controllerIds(ok, _staff), isEmpty);
    });

    test('retry after a commit that ALREADY landed is a harmless no-op',
        () async {
      // The ambiguous case: the client saw a timeout but the server applied the
      // write. The retry must not error or duplicate — it must notice the
      // source is drained and skip.
      final db = FakeFirebaseFirestore();
      await _seed(db);

      final first = await migrateInstallerControllersToCustomer(
        firestore: db, fromUid: _staff, toUid: _customer,
        controllerIds: {_ctrl},
      );
      expect(first.movedAnything, isTrue);

      final second = await migrateInstallerControllersToCustomer(
        firestore: db, fromUid: _staff, toUid: _customer,
        controllerIds: {_ctrl},
      );
      expect(second.movedAnything, isFalse);
      expect(second.skipReason, 'source-empty');

      // And the customer's data is unchanged by the second pass.
      expect(await _controllerIds(db, _customer), [_ctrl]);
      final pm = await db
          .collection('users').doc(_customer)
          .collection('controllers').doc(_ctrl)
          .collection('pixelMap').get();
      expect(pm.docs.map((d) => d.id).toList()..sort(), ['0', '1']);
    });

    test('skip reasons are distinguishable from a real migration', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db);

      expect(
        (await migrateInstallerControllersToCustomer(
          firestore: db, fromUid: null, toUid: _customer, controllerIds: {},
        )).skipReason,
        'no-source-uid',
      );
      expect(
        (await migrateInstallerControllersToCustomer(
          firestore: db, fromUid: _staff, toUid: _staff, controllerIds: {},
        )).skipReason,
        'same-uid',
      );
      expect(
        (await migrateInstallerControllersToCustomer(
          firestore: db, fromUid: _staff, toUid: _customer,
          controllerIds: {'not-this-one'},
        )).skipReason,
        'no-match',
      );
      // None of those touched anything.
      expect(await _controllerIds(db, _staff), [_ctrl]);
      expect(await _controllerIds(db, _customer), isEmpty);
    });
  });

  group('P0-6 — the DECLINE path is not a seventh silent success', () {
    test('a migration failure is PRE-commit, so declining reports FAILURE',
        () {
      // _migrateControllersWithRetry rethrows when the installer taps Stop.
      // The migration runs before the customer user-doc write, so
      // installCommitted is still false when that rethrow reaches the outer
      // catch — which is what makes the wizard say "Setup failed" rather than
      // showing the handoff screen as though the install worked.
      expect(
        classifyInstallError(installCommitted: false),
        InstallErrorOutcome.reportFailure,
        reason: 'declining must NOT complete-with-warning; the customer has '
            'no controllers, so the install genuinely failed',
      );
    });
  });
}
