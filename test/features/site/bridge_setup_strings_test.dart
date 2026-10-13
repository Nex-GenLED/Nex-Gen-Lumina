// Strings proposal item 1 (FACTS T-R5): a bridge that cannot pair is serviced
// by the installer. Customers never reflash a bridge.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/site/bridge_setup_screen.dart';

void main() {
  test('the pair error says servicing, never reflash', () {
    expect(kBridgeNeedsServicingMessage,
        'This bridge needs servicing. Contact your installer.');
    expect(kBridgeNeedsServicingMessage.toLowerCase(),
        isNot(contains('reflash')));
    expect(kBridgeNeedsServicingMessage.toLowerCase(),
        isNot(contains('firmware')));
  });
}
