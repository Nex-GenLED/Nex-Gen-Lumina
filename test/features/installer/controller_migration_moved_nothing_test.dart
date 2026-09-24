// P0 REGRESSION GATE — a migration that moves ZERO controllers when the
// installer selected some is a FAILED install, not a finished one.
//
// The defect (residential path audit 2026-09-23 §9.1 item 3 / S6): the four
// "legitimate skip" outcomes — `no-source-uid`, `same-uid`, `source-empty`,
// `no-match` — returned NORMALLY from
// `migrateInstallerControllersToCustomer`. `_migrateControllersWithRetry` only
// opens its Retry/Stop dialog on a THROW, so every one of them sailed straight
// through to "Setup Complete" and the installer drove away from a customer
// whose account had no controllers on it. Production census 2026-09-23: 2 of
// 23 primary users have zero controller docs.
//
// The fix must not break the retry-after-an-unacknowledged-commit case, which
// legitimately finds the source drained. That is why "nothing moved" is only
// an error when the DESTINATION does not already hold what was selected — and
// that distinction is what these tests pin.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';

const _staff = 'staff_installer_0101';
const _customer = 'CUST_A';

Future<void> _seedController(
  FirebaseFirestore db,
  String uid,
  String id,
) async {
  await db
      .collection('users')
      .doc(uid)
      .collection('controllers')
      .doc(id)
      .set({'ip': '192.168.1.173', 'name': 'Front'});
}

void main() {
  group('migration moved nothing', () {
    test('THE REGRESSION: no-match with a selection THROWS instead of '
        'reporting a clean skip', () async {
      final db = FakeFirebaseFirestore();
      // The staff account holds a leftover from a previous install, but NOT
      // the controller this installer ticked.
      await _seedController(db, _staff, 'someone_elses');

      expect(
        () => migrateInstallerControllersToCustomer(
          firestore: db,
          fromUid: _staff,
          toUid: _customer,
          controllerIds: {'the_one_i_picked'},
        ),
        throwsA(isA<ControllerMigrationEmptyException>()),
      );
    });

    test('source-empty with a selection and an empty destination THROWS',
        () async {
      final db = FakeFirebaseFirestore();
      // Nothing under the staff uid at all — e.g. the wizard captured the
      // wrong source uid, or the docs were written elsewhere.
      expect(
        () => migrateInstallerControllersToCustomer(
          firestore: db,
          fromUid: _staff,
          toUid: _customer,
          controllerIds: {'ctrlA'},
        ),
        throwsA(isA<ControllerMigrationEmptyException>()),
      );
    });

    test('no-source-uid with a selection THROWS', () async {
      final db = FakeFirebaseFirestore();
      expect(
        () => migrateInstallerControllersToCustomer(
          firestore: db,
          fromUid: null,
          toUid: _customer,
          controllerIds: {'ctrlA'},
        ),
        throwsA(isA<ControllerMigrationEmptyException>()),
      );
    });

    test('the exception carries what the installer needs to see', () async {
      final db = FakeFirebaseFirestore();
      await _seedController(db, _customer, 'ctrlA'); // one of two arrived
      try {
        await migrateInstallerControllersToCustomer(
          firestore: db,
          fromUid: _staff,
          toUid: _customer,
          controllerIds: {'ctrlA', 'ctrlB'},
        );
        fail('expected ControllerMigrationEmptyException');
      } on ControllerMigrationEmptyException catch (e) {
        expect(e.skipReason, 'source-empty');
        expect(e.selectedCount, 2);
        expect(e.presentAtDestination, 1);
        expect('$e', contains('2 selected'));
      }
    });

    test('RETRY SAFETY: a commit that already landed is still a clean skip',
        () async {
      final db = FakeFirebaseFirestore();
      // The first commit succeeded but the client never saw the ack: the
      // source is drained and the customer already has everything.
      await _seedController(db, _customer, 'ctrlA');
      await _seedController(db, _customer, 'ctrlB');

      final result = await migrateInstallerControllersToCustomer(
        firestore: db,
        fromUid: _staff,
        toUid: _customer,
        controllerIds: {'ctrlA', 'ctrlB'},
      );

      expect(result.skipReason, 'source-empty');
      expect(result.movedAnything, isFalse);
    });

    test('same-uid is a clean skip when the controllers are there', () async {
      final db = FakeFirebaseFirestore();
      await _seedController(db, _customer, 'ctrlA');

      final result = await migrateInstallerControllersToCustomer(
        firestore: db,
        fromUid: _customer,
        toUid: _customer,
        controllerIds: {'ctrlA'},
      );

      expect(result.skipReason, 'same-uid');
    });

    test('the legacy migrate-everything call is unaffected by the new gate',
        () async {
      final db = FakeFirebaseFirestore();
      // Empty controllerIds means "move whatever is there"; with nothing to
      // move there is no expectation to violate.
      final result = await migrateInstallerControllersToCustomer(
        firestore: db,
        fromUid: _staff,
        toUid: _customer,
        controllerIds: const {},
      );
      expect(result.skipReason, 'source-empty');
    });

    test('a real migration still succeeds and still carries pixelMap docs',
        () async {
      final db = FakeFirebaseFirestore();
      final ctrl =
          db.collection('users').doc(_staff).collection('controllers').doc('c1');
      await ctrl.set({'ip': '192.168.1.173'});
      await ctrl.collection('pixelMap').doc('0').set({'segments': []});

      final result = await migrateInstallerControllersToCustomer(
        firestore: db,
        fromUid: _staff,
        toUid: _customer,
        controllerIds: {'c1'},
      );

      expect(result.controllers, 1);
      expect(result.pixelMapDocs, 1);
      expect(result.skipReason, isNull);
      final moved = await db
          .collection('users')
          .doc(_customer)
          .collection('controllers')
          .doc('c1')
          .get();
      expect(moved.exists, isTrue);
    });
  });
}
