// #163 — the reply card says what a look was SENT to, from the write's own
// report, and never the "All Zones" default that claimed every channel while
// a segment-0 payload lit one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/lumina_response_card.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';

LuminaLightingSuggestion _suggestion({String? appliedTo}) =>
    LuminaLightingSuggestion.fromPreview(
      responseText: 'Royals look, coming up.',
      preview: LuminaPatternPreview(
        patternName: 'Royals',
        colors: const [Color(0xFF004687), Color(0xFFBD9B60)],
        effectId: 12,
        appliedTo: appliedTo,
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  LuminaLightingSuggestion s, {
  double scale = 1.0,
  bool bold = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
          boldText: bold,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: LuminaResponseCard(suggestion: s, onApply: () {}),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('no write report → no channel claim at all', (tester) async {
    await _pump(tester, _suggestion());
    expect(find.text('All Zones'), findsNothing);
    expect(find.text('Sent to'), findsNothing);
  });

  for (final (scale, bold) in [(1.0, false), (1.75, true), (2.0, true)]) {
    testWidgets('the reported channels are shown (text ×$scale, bold $bold)',
        (tester) async {
      await _pump(tester, _suggestion(appliedTo: 'All 3 channels'),
          scale: scale, bold: bold);
      expect(find.text('Sent to'), findsOneWidget);
      expect(find.text('All 3 channels'), findsOneWidget);
      expect(find.text('All Zones'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });
  }

  testWidgets('a zone picked in the adjustment panel still shows as a zone',
      (tester) async {
    await _pump(
        tester,
        _suggestion().copyWithChanges(
            zone: const ZoneInfo(id: '192.0.2.10', name: 'Patio')));
    expect(find.text('Zone'), findsOneWidget);
    expect(find.text('Patio'), findsOneWidget);
  });
}
