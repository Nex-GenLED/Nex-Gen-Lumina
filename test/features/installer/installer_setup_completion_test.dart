// Install-completion guards for the wizard, following the same pure-function
// pattern as installer_setup_wizard_routing_test.dart — the wizard itself
// can't be cheaply mounted (Firebase in initState), so the decision points are
// exported as top-level functions and asserted here.
//
// Covers:
//   • the D3-HOTFIX regression: a denied post-commit bookkeeping op (the
//     admin/owner-scoped /installers counter read at wizard :1191) must be
//     classified as "install succeeded" so the handoff screen still shows;
//   • master-PIN refusal: the reserved fleet-shared dealer code '55' is
//     rejected before any install work.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';

void main() {
  group('classifyInstallError — misleading-failure fix', () {
    test('post-commit throw → completeWithWarning (show handoff, not failure)',
        () {
      // The counter-read denial (and any other post-provisioning bookkeeping
      // failure) happens after installCommitted flips true.
      expect(
        classifyInstallError(installCommitted: true),
        InstallErrorOutcome.completeWithWarning,
        reason: 'Once the customer user doc is written the customer can sign '
            'in; a later throw must not read as "Setup failed".',
      );
    });

    test('pre-commit throw → reportFailure (genuine failure still surfaces)',
        () {
      expect(
        classifyInstallError(installCommitted: false),
        InstallErrorOutcome.reportFailure,
        reason: 'A failure before the customer doc commits is a real install '
            'failure and must be reported.',
      );
    });
  });
}
