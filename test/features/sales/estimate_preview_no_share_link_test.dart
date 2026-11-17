import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/screens/estimate_preview_screen.dart';

/// The estimate preview no longer offers "Share with customer".
///
/// The button copied and opened https://nex-genled.com/estimate/{jobId}, a
/// page that does not exist, so the customer would have been sent a dead
/// link. There is no customer-facing estimate page or estimate PDF yet, so
/// the button is gone rather than pointed at a guessed URL.
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
    zones: const [
      InstallZone(
        id: 'z1',
        name: 'Front roofline',
        runLengthFt: 120,
        productType: ProductType.roofline,
        pixelsPerFoot: 1.333,
        colorPreset: ColorPreset.rgbw,
        injections: [],
        mounts: [],
        photoUrls: [],
        priceUsd: 2400,
      ),
    ],
    status: SalesJobStatus.draft,
    totalPriceUsd: 2400,
    createdAt: created,
    updatedAt: created,
  );

  testWidgets('no "Share with customer" button; Back to review remains',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeJobProvider.overrideWith((ref) => job)],
        child: const MaterialApp(home: EstimatePreviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Front roofline'), findsWidgets,
        reason: 'the estimate itself still renders');
    expect(find.text('Share with customer'), findsNothing);
    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.text('Back to review'), findsOneWidget);
  });

  test('no client code links to the non-existent estimate page', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.readAsStringSync().contains('nex-genled.com/estimate')) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });
}
