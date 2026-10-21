// The +120 large-text matrix: text scales 1.0 / 1.3 / 1.6 / 2.0 at the
// logical widths an iPhone reports with and without Display Zoom (320, 375,
// 390, 430). A screen passes when no cell throws and no RenderFlex overflow
// is reported by the text-scale harness. Ellipsis and truncation are NOT
// failures here — this gate is about overflow exceptions only, as agreed for
// the first store build; the finer defects stay in e1_text_scale_test.dart.
//
// Hosting mirrors MainScaffold: an extendBody Scaffold with NavBarInsetShell
// and the real GlassDockNavBar, the page inside its own Navigator, the app
// theme, and the app-wide 2.0 clamp (TextScaleClamp.appBuilder) untouched.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';
import 'package:nexgen_command/widgets/navigation/nav_bar_inset.dart';

import 'text_scale_harness.dart';

const List<double> kLargeTextScales = [1.0, 1.3, 1.6, 2.0];

/// Width/height/dpr/safe-area per device class. 320x568 and 375x667 are what
/// Display Zoom reports on the current phones; 390x844 and 430x932 are the
/// standard 6.1" and Max sizes.
const List<({String tag, Size size, double dpr, EdgeInsets safe})>
    kLargeTextWidths = [
  (tag: '320x568', size: Size(320, 568), dpr: 2.0, safe: EdgeInsets.only(top: 20)),
  (tag: '375x667', size: Size(375, 667), dpr: 2.0, safe: EdgeInsets.only(top: 20)),
  (tag: '390x844', size: Size(390, 844), dpr: 3.0, safe: EdgeInsets.only(top: 47, bottom: 34)),
  (tag: '430x932', size: Size(430, 932), dpr: 3.0, safe: EdgeInsets.only(top: 59, bottom: 34)),
];

List<(String, TextScaleProfile)> largeTextProfiles() => [
      for (final w in kLargeTextWidths)
        for (final s in kLargeTextScales)
          (
            '${w.tag}@$s',
            TextScaleProfile(
              textScale: s,
              boldText: false,
              screenSize: w.size,
              devicePixelRatio: w.dpr,
              safeArea: w.safe,
            )
          ),
    ];

/// The MainScaffold host. [dock] null hosts the page bare (no dock).
Widget largeTextHost({
  required List<Override> overrides,
  required Widget page,
  int? dock,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: nexGenPremiumDarkTheme,
      builder: TextScaleClamp.appBuilder,
      home: dock == null
          ? page
          : Scaffold(
              extendBody: true,
              body: NavBarInsetShell(
                navBar: GlassDockNavBar(index: dock, onTap: (_) {}),
                body: Navigator(
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: (_) => page),
                ),
              ),
            ),
    ),
  );
}

/// Pumps [build]'s widget at every cell of the matrix and fails on the first
/// cell that throws or reports a RenderFlex overflow. [frames]/[settle] let a
/// screen with entrance tweens finish them before measuring.
Future<void> expectNoOverflowAcrossLargeTextMatrix(
  WidgetTester tester,
  Widget Function() build, {
  required String label,
  int frames = 3,
  Duration settle = const Duration(milliseconds: 600),
}) async {
  for (final (tag, profile) in largeTextProfiles()) {
    final report = await pumpAtTextScale(
      tester,
      build(),
      profile: profile,
      host: TextScaleHost.none,
      frames: frames,
      settle: settle,
    );
    final thrown = tester.takeException();
    expect(thrown, isNull, reason: '$label @ $tag threw: $thrown');
    final overflow = report.ofKind(TextScaleDefectKind.overflow);
    expect(overflow, isEmpty,
        reason: '$label @ $tag overflowed: '
            '${overflow.map((d) => d.message.split('\n').first).join(' | ')}');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}
