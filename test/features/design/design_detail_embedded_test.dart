// The routed design-detail path must render ONE header, not two.
//
// `LibraryBrowserScreen` owns the `/explore/library/design_{id}` route and
// renders its own Scaffold + AppBar + breadcrumb, then hands the body to
// DesignDetailScreen. The screen also built its own Scaffold + GlassAppBar,
// titled with the same design name — two stacked bars plus a breadcrumb, and
// ~142px of duplicate chrome pushing the action row toward the glass dock.
//
// `embedded: true` drops the inner chrome. The STANDALONE push (`_duplicate`'s
// pushReplacement onto the new doc — the only such call site) keeps it, because
// nothing else would supply an app bar or a way back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';

CustomDesign _design() => CustomDesign(
      id: 'd1',
      name: 'Sunset Fade',
      createdAt: DateTime(2026, 5, 29),
      updatedAt: DateTime(2026, 6, 1),
      ownerId: 'u',
      brightness: 180,
      channels: [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          included: true,
          effectId: 12,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 9, color: const [255, 80, 0, 0]),
          ],
          ledCount: 10,
        ),
      ],
    );

List<Override> _overrides(CustomDesign d) => [
      designsStreamProvider.overrideWith((_) => Stream.value([d])),
      designByIdProvider(d.id).overrideWith((_) async => d),
    ];

/// Stands in for LibraryBrowserScreen: a Scaffold whose AppBar is already
/// titled with the design name, exactly as the real parent's is (its title
/// comes from `extra['name']`, which the row tap sets to the design's name).
Widget _parentChrome({required Widget child, required String title}) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(8), child: Text('Library')),
      Expanded(child: child),
    ]),
  );
}

void main() {
  group('routed (embedded) path', () {
    testWidgets('renders exactly one AppBar and one title for the design',
        (tester) async {
      final d = _design();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(d),
        child: MaterialApp(
          home: _parentChrome(
            title: d.name,
            child: DesignDetailScreen(designId: d.id, embedded: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget,
          reason: 'the parent supplies the only app bar');

      // The design name appears once in the app bar and once as the body
      // heading — two Texts, but only ONE of them inside an AppBar. Before the
      // fix there were two app-bar titles.
      final titlesInAppBars = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(d.name),
      );
      expect(titlesInAppBars, findsOneWidget);
    });

    testWidgets('builds no Scaffold of its own', (tester) async {
      final d = _design();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(d),
        child: MaterialApp(
          home: _parentChrome(
            title: d.name,
            child: DesignDetailScreen(designId: d.id, embedded: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget,
          reason: 'a nested Scaffold is what produced the second header');
    });

    testWidgets('the content itself is unchanged — actions still present',
        (tester) async {
      final d = _design();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(d),
        child: MaterialApp(
          home: _parentChrome(
            title: d.name,
            child: DesignDetailScreen(designId: d.id, embedded: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(ListView), const Offset(0, -1200), 3000);
      await tester.pumpAndSettle();

      for (final label in [
        'Apply to Lights',
        'Edit',
        'Rename',
        'Duplicate',
        'Delete'
      ]) {
        expect(find.text(label), findsOneWidget,
            reason: 'dropping the chrome must not drop content');
      }
    });
  });

  group('standalone path (the _duplicate push)', () {
    testWidgets('keeps its own Scaffold and app bar', (tester) async {
      final d = _design();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(d),
        // No parent chrome — this is what pushReplacement lands on.
        child: MaterialApp(home: DesignDetailScreen(designId: d.id)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget,
          reason: 'without this the duplicate lands on a headerless screen '
              'with no way back');
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(d.name)),
        findsOneWidget,
      );
    });

    testWidgets('defaults to standalone — embedded must be opt-IN',
        (tester) async {
      // A future call site that forgets the flag should get the safe shape
      // (its own chrome), not a headerless screen.
      const screen = DesignDetailScreen(designId: 'x');
      expect(screen.embedded, isFalse);
    });
  });
}
