import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/screens/day1_blueprint_screen.dart';
import 'package:nexgen_command/features/sales/screens/day2_blueprint_screen.dart';

/// Day 1 / Day 2 blueprints for jobs that have zones but no channel runs.
///
/// `channelRuns` is written only by the estimate wizard, which has no entry
/// point, so every job that reaches the Day 1 and Day 2 queues today was
/// built on the visit's zone builder: it carries `zones` and an empty
/// `channelRuns`. Both blueprints used to show "No channels on this job" for
/// all of them. They now render the zones in the channels section. A job
/// with neither still says "No channels on this job".
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final created = DateTime(2026, 11, 1, 9);

  SalesJob jobWith(List<InstallZone> zones) => SalesJob(
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
        zones: zones,
        status: SalesJobStatus.prewireScheduled,
        totalPriceUsd: 0,
        createdAt: created,
        updatedAt: created,
      );

  const zones = [
    InstallZone(
      id: 'z1',
      name: 'Front roofline',
      runLengthFt: 120,
      productType: ProductType.roofline,
      pixelsPerFoot: 1.333,
      colorPreset: ColorPreset.rgbw,
      injections: [
        InjectionPoint(
          id: 'i1',
          positionFt: 60,
          servedByController: false,
          wireGauge: WireGauge.g12_2,
          wireRunFt: 45,
          architecturalNote: 'Behind the downspout',
        ),
      ],
      mounts: [
        PowerMount(
          id: 'm1',
          positionFt: 0,
          isController: true,
          supplySize: 'controller',
          servesInjectionIds: ['i1'],
          mountLocationNote: 'Garage, left of the panel',
        ),
      ],
      photoUrls: [],
      notes: 'Avoid the gutter guard',
      railType: RailType.onePiece,
      railColor: RailColor.black,
      cornerCount: 2,
    ),
    InstallZone(
      id: 'z2',
      name: 'Garage peak',
      runLengthFt: 40,
      productType: ProductType.roofline,
      pixelsPerFoot: 1.333,
      colorPreset: ColorPreset.warmWhite,
      injections: [],
      mounts: [],
      photoUrls: [],
    ),
  ];

  Future<FakeFirebaseFirestore> seed(SalesJob job) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_jobs').doc(job.id).set(job.toJson());
    return db;
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: screen)));
    await tester.pumpAndSettle();
  }

  final screens = <String, Widget Function(FakeFirebaseFirestore)>{
    'Day 1': (db) => Day1BlueprintScreen(jobId: 'job1', firestore: db),
    'Day 2': (db) => Day2BlueprintScreen(jobId: 'job1', firestore: db),
  };

  screens.forEach((day, build) {
    group('$day blueprint', () {
      testWidgets('renders the job zones when there are no channel runs',
          (tester) async {
        final db = await seed(jobWith(zones));
        await pump(tester, build(db));

        expect(find.text('CHANNELS'), findsOneWidget);
        expect(find.text('No channels on this job'), findsNothing);

        expect(find.text('Front roofline'), findsOneWidget);
        expect(find.text('Garage peak'), findsOneWidget);
        expect(find.textContaining('120 ft'), findsWidgets);
        expect(find.textContaining('1-Piece Rail'), findsOneWidget);
        expect(find.textContaining('Behind the downspout'), findsOneWidget);
        expect(find.textContaining('Garage, left of the panel'),
            findsOneWidget);
        expect(find.textContaining('Avoid the gutter guard'), findsOneWidget);
      });

      testWidgets('zone cards fit a phone-width screen', (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final db = await seed(jobWith(zones));
        await pump(tester, build(db));

        // A RenderFlex overflow would already have failed the test.
        expect(find.text('Front roofline'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('still says "No channels" when the job has neither',
          (tester) async {
        final db = await seed(jobWith(const []));
        await pump(tester, build(db));

        expect(find.text('No channels on this job'), findsOneWidget);
        expect(find.text('Front roofline'), findsNothing);
      });
    });
  });
}
