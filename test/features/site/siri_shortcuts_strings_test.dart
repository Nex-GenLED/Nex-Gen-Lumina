// Strings proposal item 4 (FACTS T-VA1): the Simple Mode dialog and the
// installer handoff list name what works, "Siri Shortcuts (iPhone)", in
// place of a general voice-assistant setup claim. The two strings live in
// large screens, so this pins them at the source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const files = [
    'lib/features/site/settings_page.dart',
    'lib/features/installer/handoff_screen.dart',
  ];

  test('both surfaces say "Siri Shortcuts (iPhone)" and nothing broader', () {
    for (final path in files) {
      final src = File(path).readAsStringSync();
      expect(src, contains('Siri Shortcuts (iPhone)'), reason: path);
      expect(src, isNot(contains('Voice assistant setup')), reason: path);
    }
  });
}
