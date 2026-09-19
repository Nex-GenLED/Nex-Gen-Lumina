// M3 (audit F1) — the control that SAYS "Manual controls" opens the manual
// editor. `_showManualControls` was written in four places and read in none.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/screens/ai_design_studio_screen.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designsStreamProvider.overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('u'),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 40, gpioPin: 2),
      ]),
    ],
    child: const MaterialApp(home: AIDesignStudioScreen()),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the studio opens in AI mode — no paint editor yet', (tester) async {
    await _pump(tester);
    expect(find.byType(ManualDesignEditor), findsNothing);
    expect(find.byTooltip('Manual controls'), findsOneWidget);
  });

  testWidgets('"Manual controls" opens the paint editor', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Manual controls'));
    await tester.pump();
    expect(find.byType(ManualDesignEditor), findsOneWidget,
        reason: 'used to set a flag nothing reads');
    // Once there, the redundant door is gone; the title toggle shows the mode.
    expect(find.byTooltip('Manual controls'), findsNothing);
  });

  testWidgets('the AI | Manual title toggle is still the working entry point',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Manual'));
    await tester.pump();
    expect(find.byType(ManualDesignEditor), findsOneWidget);
    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(find.byType(ManualDesignEditor), findsNothing);
    expect(find.byTooltip('Manual controls'), findsOneWidget);
  });
}
