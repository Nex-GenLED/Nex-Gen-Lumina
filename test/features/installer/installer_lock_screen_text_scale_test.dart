// +113 — the shared installer lock screen, in both shapes it is shown (with
// and without a customer alternative), through the accessibility matrix:
// 1.0, 1.75 and 2.0 text scale, all with Bold Text.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_lock_screen.dart';

import '../../helpers/text_scale_harness.dart';

void main() {
  testWidgets('wizard shape — Go Back only', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      const InstallerLockScreen(
        title: 'Roofline Setup',
        featureName: 'The Roofline Setup Wizard',
      ),
    );
  });

  testWidgets('Segment Setup shape — with Mark Your Roofline', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      InstallerLockScreen(
        title: 'Roofline Segments',
        featureName: 'The Roofline Segments editor',
        alternativeLabel: 'Mark Your Roofline instead',
        onAlternative: () {},
      ),
    );
  });
}
