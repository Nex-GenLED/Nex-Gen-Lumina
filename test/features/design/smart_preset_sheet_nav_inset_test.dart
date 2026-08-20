import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_presets_section.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';

/// Layout regression — the Smart Presets quick-select sheet is presented from
/// the Home branch navigator, which is a SIBLING of MainScaffold's always-
/// visible GlassDockNavBar in the same Stack. The dock therefore paints OVER
/// the sheet's lower edge, and without an explicit inset the Apply button (the
/// sheet's lowest interactive element) sits behind the glassbar.
///
/// The pin: every interactive element's bottom edge must clear the glassbar's
/// top edge, where the glassbar occupies navBarTotalHeight(context) =
/// kNavBarContentHeight + the device's bottom safe-area inset.
void main() {
  // A device with a home indicator, so the test also proves the safe-area
  // term is included and not just the 100px dock content height.
  const bottomSafeArea = 34.0;
  const screenSize = Size(390, 844);

  /// The safe area must be set on the VIEW, not via a MediaQuery inside
  /// `home:` — the modal sheet is a route in MaterialApp's Navigator, which
  /// sits ABOVE anything `home:` wraps, so an inner MediaQuery never reaches
  /// the sheet.
  Future<void> openSheet(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screenSize;
    tester.view.padding = const FakeViewPadding(bottom: bottomSafeArea);
    tester.view.viewPadding = const FakeViewPadding(bottom: bottomSafeArea);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [hasRooflineConfigProvider.overrideWithValue(true)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SmartPresetsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(kSmartPresets.first.name).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the Apply button clears the glassbar top edge', (tester) async {
    await openSheet(tester);

    final applyFinder = find.widgetWithText(FilledButton, 'Apply ${kSmartPresets.first.name}');
    expect(applyFinder, findsOneWidget,
        reason: 'the sheet should be open with its Apply control mounted');

    // The glassbar is pinned to the bottom of the screen.
    final glassbarHeight =
        kNavBarContentHeight + bottomSafeArea; // navBarTotalHeight
    final glassbarTop = screenSize.height - glassbarHeight;

    final applyBottom = tester.getRect(applyFinder).bottom;
    expect(applyBottom, lessThanOrEqualTo(glassbarTop),
        reason: 'the Apply button must sit fully above the glassbar '
            '(bottom $applyBottom vs glassbar top $glassbarTop)');
  });

  testWidgets('the last accent swatch clears the glassbar top edge',
      (tester) async {
    await openSheet(tester);

    // Every swatch in both rows is a GestureDetector inside the sheet; the
    // lowest one is the strictest bound on the interactive content.
    final swatches = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(GestureDetector),
    );
    expect(swatches, findsWidgets);

    var lowest = 0.0;
    for (final e in swatches.evaluate()) {
      final b = tester.getRect(find.byWidget(e.widget)).bottom;
      if (b > lowest) lowest = b;
    }

    final glassbarTop = screenSize.height - (kNavBarContentHeight + bottomSafeArea);
    expect(lowest, lessThanOrEqualTo(glassbarTop),
        reason: 'the lowest color swatch must sit fully above the glassbar '
            '(bottom $lowest vs glassbar top $glassbarTop)');
  });
}
