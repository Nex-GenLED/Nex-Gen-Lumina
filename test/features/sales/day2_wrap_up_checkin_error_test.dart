import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/screens/day2_wrap_up_screen.dart';
import 'package:nexgen_command/features/sales/services/inventory_service.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';

/// Day 2 wrap-up, step 2: a failed dealer-stock check-in must be visible.
///
/// `_persistMaterialUsage` writes the usage onto the job, then reconciles
/// dealer stock through InventoryService.checkInFinal. The reconcile is
/// deliberately best-effort (it must not block closing the job), but its
/// failure used to go to debugPrint only, so the installer moved on
/// believing stock had been updated. It now shows a plain error. Nothing
/// else changes: the step still advances.
class _InventoryStub extends InventoryService {
  _InventoryStub(super.db, {this.list, this.fail});

  final JobMaterialList? list;
  final Object? fail;
  int checkInCalls = 0;

  @override
  Stream<JobMaterialList?> watchJobMaterialList(String jobId) =>
      Stream.value(list);

  @override
  Future<void> checkInFinal({
    required String jobId,
    required String dealerCode,
    required String installerId,
    required List<JobMaterialLine> finalLines,
  }) async {
    checkInCalls++;
    if (fail != null) throw fail!;
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final created = DateTime(2026, 11, 1, 9);

  final job = SalesJob(
    id: 'job1',
    jobNumber: 'NXG-20261101-001',
    dealerCode: '01',
    salespersonUid: 'staff_sales_TESTPIN',
    prospect: SalesProspect(
      id: 'job1',
      firstName: 'Pat',
      lastName: 'Customer',
      email: 'pat@example.com',
      phone: '',
      address: '1 Main St',
      city: 'Springfield',
      state: 'MO',
      zipCode: '65800',
      createdAt: created,
    ),
    zones: const [],
    status: SalesJobStatus.installScheduled,
    totalPriceUsd: 0,
    createdAt: created,
    updatedAt: created,
  );

  JobMaterialList materialList() => JobMaterialList(
        jobId: 'job1',
        jobNumber: 'NXG-20261101-001',
        dealerCode: '01',
        status: JobMaterialStatus.day1Complete,
        lines: [
          JobMaterialLine(
            materialId: 'mat1',
            materialName: 'Rail',
            unit: MaterialUnit.each,
            calculatedQty: 10,
            checkedOutQty: 10,
          ),
        ],
        calculatedBy: 'staff_sales_TESTPIN',
        calculatedAt: created,
      );

  /// Pumps the wrap-up, moves from step 1 to step 2, then presses Continue
  /// on step 2 (which runs the material check-in).
  Future<FakeFirebaseFirestore> runStep2(
    WidgetTester tester,
    _InventoryStub Function(FirebaseFirestore db) inventory,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_jobs').doc(job.id).set(job.toJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesJobServiceProvider.overrideWithValue(SalesJobService(db)),
          inventoryServiceProvider.overrideWithValue(inventory(db)),
        ],
        child: MaterialApp(
          home: Day2WrapUpScreen(jobId: job.id, firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 1 of 4'), findsOneWidget);

    await tester.tap(find.text('Continue →'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 2 of 4'), findsOneWidget);

    await tester.tap(find.text('Continue →'));
    await tester.pump(); // start the async save
    await tester.pump(const Duration(milliseconds: 50)); // snackbar enters
    return db;
  }

  testWidgets('a denied stock check-in shows a visible error and still advances',
      (tester) async {
    late _InventoryStub stub;
    final db = await runStep2(tester, (db) {
      return stub = _InventoryStub(
        db,
        list: materialList(),
        fail: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
    });

    expect(stub.checkInCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('dealer stock was not updated'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsOneWidget);

    await tester.pumpAndSettle();
    // Unchanged behaviour: the usage is on the job and the flow moves on.
    expect(find.textContaining('Step 3 of 4'), findsOneWidget);
    final saved = await db.collection('sales_jobs').doc('job1').get();
    expect(saved.data()!['actualMaterialUsage'], isNotNull);
  });

  testWidgets('a successful stock check-in shows no error', (tester) async {
    late _InventoryStub stub;
    await runStep2(tester, (db) => stub = _InventoryStub(db, list: materialList()));

    expect(stub.checkInCalls, 1);
    expect(find.textContaining('dealer stock was not updated'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 3 of 4'), findsOneWidget);
  });

  testWidgets('no material list means nothing to reconcile and no error',
      (tester) async {
    late _InventoryStub stub;
    await runStep2(tester, (db) => stub = _InventoryStub(db));

    expect(stub.checkInCalls, 0);
    expect(find.textContaining('dealer stock was not updated'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 3 of 4'), findsOneWidget);
  });
}
