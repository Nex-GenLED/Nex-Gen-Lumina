// The STAGING ribbon and the refusal screen
// (lib/config/environment_widgets.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/config/environment_widgets.dart';
import 'package:nexgen_command/config/lumina_env.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';

/// Only the STAGING ribbon — Flutter's own debug-mode "DEBUG" corner is a
/// [Banner] too, so the finders must not count it.
final _stagingRibbon =
    find.byWidgetPredicate((w) => w is Banner && w.message == 'STAGING');

Widget _app(TransitionBuilder builder, {VoidCallback? onTap}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: builder,
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: const SizedBox.expand(child: Text('home')),
        ),
      ),
    );

void main() {
  group('production builder', () {
    test('is TextScaleClamp.appBuilder itself — the tree is unchanged', () {
      expect(identical(luminaAppBuilderFor(LuminaEnv.prod),
          TextScaleClamp.appBuilder), isTrue);
      // ...and this (no-define) binary selects it.
      expect(identical(luminaAppBuilderFor(luminaEnv),
          TextScaleClamp.appBuilder), isTrue);
    });

    test('an unrecognised env also gets no ribbon (it never runs the app)', () {
      expect(identical(luminaAppBuilderFor(null), TextScaleClamp.appBuilder),
          isTrue);
    });

    testWidgets('shows no STAGING ribbon', (tester) async {
      await tester.pumpWidget(_app(luminaAppBuilderFor(LuminaEnv.prod)));
      expect(_stagingRibbon, findsNothing);
      expect(find.byType(TextScaleClamp), findsOneWidget);
    });
  });

  group('staging builder', () {
    testWidgets('puts a STAGING ribbon over the app, text clamp kept',
        (tester) async {
      await tester.pumpWidget(_app(luminaAppBuilderFor(LuminaEnv.staging)));
      final banner = tester.widget<Banner>(_stagingRibbon);
      expect(banner.message, 'STAGING');
      expect(banner.color, kStagingBannerColor);
      expect(find.byType(TextScaleClamp), findsOneWidget);
      expect(
        find.descendant(
            of: _stagingRibbon, matching: find.byType(Navigator)),
        findsOneWidget,
        reason: 'the ribbon wraps the Navigator, so it covers every route',
      );
    });

    testWidgets('covers pushed routes and dialogs too', (tester) async {
      await tester.pumpWidget(_app(luminaAppBuilderFor(LuminaEnv.staging)));
      final ctx = tester.element(find.text('home'));
      Navigator.of(ctx).push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('second'))));
      await tester.pumpAndSettle();
      expect(find.ancestor(of: find.text('second'), matching: _stagingRibbon),
          findsOneWidget);
      showDialog<void>(
          context: tester.element(find.text('second')),
          builder: (_) => const AlertDialog(content: Text('dialog')));
      await tester.pumpAndSettle();
      expect(find.ancestor(of: find.text('dialog'), matching: _stagingRibbon),
          findsOneWidget);
    });

    testWidgets('only paints: a tap under the ribbon reaches the app',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
          _app(luminaAppBuilderFor(LuminaEnv.staging), onTap: () => taps++));
      // Top-left corner, where the ribbon is drawn.
      await tester.tapAt(const Offset(20, 20));
      expect(taps, 1);
    });
  });

  group('EnvironmentRefusedApp', () {
    testWidgets('shows the reason and nothing of the app', (tester) async {
      await tester.pumpWidget(const EnvironmentRefusedApp(
          reason: 'This is a staging build, but it loaded Firebase project "x".'));
      expect(find.text('This build cannot start'), findsOneWidget);
      expect(find.textContaining('loaded Firebase project "x"'), findsOneWidget);
      // This binary is production, so no ribbon.
      expect(_stagingRibbon, findsNothing);
    });
  });
}
