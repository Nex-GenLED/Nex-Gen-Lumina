// Strings proposal item 6 (FACTS T-R9): no "cut the strips" advice. The
// install is permanent and professional; the rest of the list is item 8,
// which is not in this build.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/site/help_center_screen.dart';

void main() {
  test('no FAQ tells a customer to cut a strip', () {
    expect(kHelpCenterFaqs, hasLength(3));
    for (final (q, a) in kHelpCenterFaqs) {
      expect(q.toLowerCase(), isNot(contains('cut')));
      expect(a.toLowerCase(), isNot(contains('copper')));
      expect(a.toLowerCase(), isNot(contains('cut lines')));
    }
    expect(kHelpCenterFaqs.map((f) => f.$1), [
      'Lights are not responding.',
      'How to reset Wi-Fi?',
      "Schedule didn't run.",
    ]);
  });
}
