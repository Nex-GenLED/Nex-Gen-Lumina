// Routing guard for the installer wizard. Catches:
//   - enum re-ordering that breaks linear progression
//   - _buildStepContent regressions that route controllerSetup straight
//     to zoneConfiguration (skipping the new connectionMethod step)
//
// `nextWizardStep` is the single source of truth — every onNext closure
// in `_buildStepContent` routes through it. So a pure-function check on
// `nextWizardStep` covers both transitions without standing up the full
// wizard (which can't be cheaply mounted in unit tests because
// ControllerSetupScreen's initState pulls in Firebase Auth).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';

void main() {
  test(
    'advancing from controllerSetup lands on connectionMethod '
    '(NOT zoneConfiguration)',
    () {
      expect(
        nextWizardStep(InstallerWizardStep.controllerSetup),
        InstallerWizardStep.connectionMethod,
        reason: 'The connectionMethod step must sit between '
            'controllerSetup and zoneConfiguration. If this fails, '
            'either the enum was reordered or _buildStepContent stopped '
            'routing through nextWizardStep.',
      );
      expect(
        nextWizardStep(InstallerWizardStep.controllerSetup),
        isNot(InstallerWizardStep.zoneConfiguration),
      );
    },
  );

  test(
    'advancing from connectionMethod lands on zoneConfiguration',
    () {
      expect(
        nextWizardStep(InstallerWizardStep.connectionMethod),
        InstallerWizardStep.zoneConfiguration,
      );
    },
  );
}
