// +110 package G — row 84: the feature tour describes only controls that
// exist on Home in this build.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';

String _screenText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((t) => t.text.toPlainText())
    .join(' | ');

void main() {
  testWidgets(
      '"Take the Tour" walks steps that name real Home controls; the invented '
      'Quick Presets and status indicator are gone', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: FeatureTourOverlay(
          child: Scaffold(body: TourLaunchButton()),
        ),
      ),
    ));
    await tester.tap(find.text('Take the Tour'));
    await tester.pumpAndSettle();

    final seen = <String>[];
    for (var i = 0; i < 20; i++) {
      seen.add(_screenText(tester));
      final next = find.text('Next');
      if (next.evaluate().isEmpty) break;
      // A long step scrolls; Next must be reachable by scrolling to it.
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    final all = seen.join('\n');

    for (final invented in [
      'Quick Presets',
      'Run Schedule',
      'Bright White',
      'Holiday Mode',
      'Connection Status',
      'Green pulse',
    ]) {
      expect(all, isNot(contains(invented)),
          reason: '"$invented" is not on Home');
    }
    expect(all, contains('My Favorites'));
    expect(all, contains('Choose Your Channels'));
    expect(find.text('Get Started'), findsOneWidget, reason: 'reached the end');
  });
}
