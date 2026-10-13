// Strings proposal item 2 (FACTS T-VA1, T-VA2): the Settings card names what
// works — Siri Shortcuts on iPhone, App Shortcuts on Android — with no Alexa
// or Google claim and no permanent "New" badge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/site/settings_page.dart';

void main() {
  test('the strings', () {
    expect(kVoiceAssistantsCardTitle, 'Voice Assistants');
    expect(kVoiceAssistantsCardSubtitle,
        'Siri Shortcuts on iPhone. App shortcuts on Android.');
    for (final word in const ['Alexa', 'Google']) {
      expect(kVoiceAssistantsCardSubtitle, isNot(contains(word)));
    }
  });

  testWidgets('the card shows them and carries no badge', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VoiceAssistantsCard()),
    ));
    expect(find.text('Voice Assistants'), findsOneWidget);
    expect(find.text('Siri Shortcuts on iPhone. App shortcuts on Android.'),
        findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(find.textContaining('Alexa'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
  });
}
