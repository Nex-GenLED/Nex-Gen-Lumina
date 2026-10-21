// +120 large-text slice, group 1: the glass dock. The Lumina button is a
// fixed 84 pt circle and the dock a fixed-height strip; their labels now
// scale to 1.3x and stay on one or two lines, so nothing overflows at 2.0x
// on a 320 pt screen (where "Schedule" used to wrap mid-word and the button's
// Column overflowed by 23 px).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';
import 'package:nexgen_command/widgets/navigation/nav_bar_inset.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/large_text_matrix.dart';

Widget _dock({required bool listening, required int index}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: nexGenPremiumDarkTheme,
      builder: TextScaleClamp.appBuilder,
      home: Scaffold(
        extendBody: true,
        body: NavBarInsetShell(
          navBar: GlassDockNavBar(
            index: index,
            onTap: (_) {},
            isVoiceListening: listening,
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('dock at rest: no overflow across the matrix', (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => _dock(listening: false, index: 1),
      label: 'dock',
    );
  });

  testWidgets('dock while listening ("Listening..." label): no overflow',
      (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => _dock(listening: true, index: 3),
      label: 'dock/listening',
    );
  });
}
