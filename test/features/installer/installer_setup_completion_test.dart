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
import 'package:nexgen_command/models/dealer_code.dart';

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

  group('installUsesReservedDealerCode — master-PIN refusal', () {
    test('reserved master code 55 is refused', () {
      expect(installUsesReservedDealerCode(DealerCode.masterReserved), isTrue);
      expect(installUsesReservedDealerCode('55'), isTrue);
    });

    test('genuine per-dealer codes are allowed', () {
      for (final code in ['01', '07', '42', '54', '56', '99', '00']) {
        expect(installUsesReservedDealerCode(code), isFalse,
            reason: '$code is a real dealer code and must be installable');
      }
    });

    test('the reserved constant is exactly the staffAuth MASTER_DEALER_CODE', () {
      // Guards against a future drift between the client constant and the
      // server's MASTER_DEALER_CODE = "55" (staffAuth.ts:119).
      expect(DealerCode.masterReserved, '55');
    });
  });
}
