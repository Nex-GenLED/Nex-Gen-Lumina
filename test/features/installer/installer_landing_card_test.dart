import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/installer/installer_landing_screen.dart';
import 'package:nexgen_command/features/installer/widgets/info_expansion_card.dart';

// Minimal GoRouter so InstallerLandingScreen's `context.push(...)` calls
// don't throw when the user taps a nav button. The destination routes
// don't matter for these tests — we never tap navigation.
GoRouter _testRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const InstallerLandingScreen(),
        ),
      ],
    );

Future<void> _mount(WidgetTester tester) async {
  // The default 800x600 test surface overflows once the new info card
  // sits above the 2x2 grid; give the layout enough vertical room to
  // settle without clipping.
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter()),
    ),
  );
  await tester.pump();
}

void main() {
  group('InstallerLandingScreen info card', () {
    testWidgets('InfoExpansionCard renders collapsed by default',
        (tester) async {
      await _mount(tester);
      // Title visible.
      expect(
        find.text('Installing a SKIKBILY or dual-network controller?'),
        findsOneWidget,
      );
      // Body text hidden in collapsed state.
      expect(
        find.textContaining('use Ethernet whenever a wall jack'),
        findsNothing,
      );
      expect(find.byType(InfoExpansionCard), findsOneWidget);
    });

    testWidgets('tap expands → body visible; tap again collapses',
        (tester) async {
      await _mount(tester);
      // Expand.
      await tester.tap(
        find.text('Installing a SKIKBILY or dual-network controller?'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('use Ethernet whenever a wall jack'),
        findsOneWidget,
      );
      // Collapse.
      await tester.tap(
        find.text('Installing a SKIKBILY or dual-network controller?'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('use Ethernet whenever a wall jack'),
        findsNothing,
      );
    });

    testWidgets('existing 5 navigation buttons unchanged', (tester) async {
      await _mount(tester);
      expect(find.text('New Install'), findsOneWidget);
      expect(find.text('Existing Customer'), findsOneWidget);
      expect(find.text('Day 1 Queue'), findsOneWidget);
      expect(find.text('Day 2 Queue'), findsOneWidget);
      expect(find.text('Dealer Dashboard'), findsOneWidget);
    });

    testWidgets('2x2 grid stays bottom-aligned (visually below the card)',
        (tester) async {
      await _mount(tester);
      // The "New Install" tile must render BELOW the info card on the
      // y-axis — the card sits above the Spacer, the grid sits below.
      final cardTopLeft = tester.getTopLeft(find.byType(InfoExpansionCard));
      final gridTopLeft = tester.getTopLeft(find.text('New Install'));
      expect(
        gridTopLeft.dy,
        greaterThan(cardTopLeft.dy),
        reason: 'New Install grid tile must sit below the info card',
      );
    });
  });
}
