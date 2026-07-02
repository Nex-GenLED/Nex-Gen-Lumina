// Design Studio Slice 2 — the integrity guarantee: a wizard-captured pixelMap
// MUST arrive under the customer uid at handoff. Also covers the Slice-1 save
// path writing docs under the current (staff) uid, and skip → no docs.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

const _staff = 'staff_installer_55';
const _customer = 'customer_abc';
const _ctrl = 'ctrlA';

Future<void> _seedControllerWithMap(FakeFirebaseFirestore db) async {
  // Controller doc under the staff uid (as the wizard writes it).
  await db
      .collection('users')
      .doc(_staff)
      .collection('controllers')
      .doc(_ctrl)
      .set({'ip': '192.168.1.250', 'name': 'Front'});

  // A captured 2-channel map saved via the Slice-1 service under the staff uid.
  final segsCh0 = compileMarksToChannelSegments(
    channelIndex: 0,
    pixelCount: 128,
    marks: const [
      CaptureMark(pixel: 0, kind: MarkKind.corner),
      CaptureMark(pixel: 64, kind: MarkKind.peak, slopeLength: 8),
    ],
  );
  final segsCh1 = compileMarksToChannelSegments(
    channelIndex: 1,
    pixelCount: 60,
    marks: const [CaptureMark(pixel: 30, kind: MarkKind.corner)],
  );
  final config = RooflineConfiguration(
    id: _ctrl,
    controllerId: _ctrl,
    name: 'Roofline',
    segments: [...segsCh0, ...segsCh1],
    createdAt: DateTime(2026, 7, 2),
    updatedAt: DateTime(2026, 7, 2),
    totalChannelCount: 2,
  );
  await RooflineConfigService(firestore: db).savePixelMap(
    _staff,
    _ctrl,
    config,
    sourceCounts: const {0: 128, 1: 60},
    createdBy: _staff,
  );
}

Future<List<String>> _pixelMapIds(
    FakeFirebaseFirestore db, String uid) async {
  final snap = await db
      .collection('users')
      .doc(uid)
      .collection('controllers')
      .doc(_ctrl)
      .collection('pixelMap')
      .get();
  return snap.docs.map((d) => d.id).toList()..sort();
}

void main() {
  test('Slice-1 save writes per-channel docs under the CURRENT (staff) uid',
      () async {
    final db = FakeFirebaseFirestore();
    await _seedControllerWithMap(db);
    expect(await _pixelMapIds(db, _staff), ['0', '1']);
    // created_by stamped with the staff uid (owner write under staff subtree).
    final ch0 = await db
        .collection('users')
        .doc(_staff)
        .collection('controllers')
        .doc(_ctrl)
        .collection('pixelMap')
        .doc('0')
        .get();
    expect(ch0.data()!['created_by'], _staff);
    expect(ch0.data()!['source_pixel_count'], 128);
  });

  test('MIGRATION carries pixelMap docs to the customer + clears staff side',
      () async {
    final db = FakeFirebaseFirestore();
    await _seedControllerWithMap(db);

    await migrateInstallerControllersToCustomer(
      firestore: db,
      fromUid: _staff,
      toUid: _customer,
      controllerIds: {_ctrl},
    );

    // The map now lives under the customer, with identical channel docs.
    expect(await _pixelMapIds(db, _customer), ['0', '1']);
    // Staff-side pixelMap docs are deleted (consistent with controller doc).
    expect(await _pixelMapIds(db, _staff), isEmpty);
    // Controller doc migrated too.
    final ctrl = await db
        .collection('users')
        .doc(_customer)
        .collection('controllers')
        .doc(_ctrl)
        .get();
    expect(ctrl.exists, isTrue);
    expect(ctrl.data()!['ip'], '192.168.1.250');
    // Channel data preserved through the migration.
    final ch0 = await db
        .collection('users')
        .doc(_customer)
        .collection('controllers')
        .doc(_ctrl)
        .collection('pixelMap')
        .doc('0')
        .get();
    expect(ch0.data()!['source_pixel_count'], 128);
    expect((ch0.data()!['segments'] as List).isNotEmpty, isTrue);
  });

  test('migration is a no-op for controllers not in the id set', () async {
    final db = FakeFirebaseFirestore();
    await _seedControllerWithMap(db);
    await migrateInstallerControllersToCustomer(
      firestore: db,
      fromUid: _staff,
      toUid: _customer,
      controllerIds: {'someOtherController'},
    );
    // Nothing moved.
    expect(await _pixelMapIds(db, _customer), isEmpty);
    expect(await _pixelMapIds(db, _staff), ['0', '1']);
  });

  test('same-uid migration is a no-op (no data loss)', () async {
    final db = FakeFirebaseFirestore();
    await _seedControllerWithMap(db);
    await migrateInstallerControllersToCustomer(
      firestore: db,
      fromUid: _staff,
      toUid: _staff,
      controllerIds: {_ctrl},
    );
    expect(await _pixelMapIds(db, _staff), ['0', '1']);
  });

  test('skipped mapping leaves no pixelMap docs to migrate', () async {
    final db = FakeFirebaseFirestore();
    // Controller exists but the installer skipped mapping (no pixelMap docs).
    await db
        .collection('users')
        .doc(_staff)
        .collection('controllers')
        .doc(_ctrl)
        .set({'ip': '10.0.0.5', 'name': 'Front'});

    await migrateInstallerControllersToCustomer(
      firestore: db,
      fromUid: _staff,
      toUid: _customer,
      controllerIds: {_ctrl},
    );

    // Controller migrated; no pixelMap docs anywhere.
    final ctrl = await db
        .collection('users')
        .doc(_customer)
        .collection('controllers')
        .doc(_ctrl)
        .get();
    expect(ctrl.exists, isTrue);
    expect(await _pixelMapIds(db, _customer), isEmpty);
    expect(await _pixelMapIds(db, _staff), isEmpty);
  });
}
