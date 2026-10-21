// Strings proposal item 3 (FACTS T-VA1): the voice guide keeps what works
// (Siri Shortcuts, the Android App Shortcuts box, Home Assistant) and no
// longer advertises assistant linking that has never worked. The removed
// cards are not replaced with another claim.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/voice/voice_assistant_guide_screen.dart';

void main() {
  test('the hero sentence is the proposal wording', () {
    expect(
        kVoiceGuideHeroText,
        'Say "Hey Siri, [your phrase]" to put a saved look on your lights. '
        'On Android, long-press the Lumina icon for shortcuts.');
  });

  test('the iPhone hero names no other platform (2.3.10)', () {
    expect(kVoiceGuideHeroTextIos,
        'Say "Hey Siri, [your phrase]" to put a saved look on your lights.');
    expect(kVoiceGuideHeroTextIos, isNot(contains('Android')));
  });

  test('the App Shortcuts box makes no assistant claim', () {
    expect(kAppShortcutsText,
        'Long-press the Lumina app icon to access quick shortcuts without linking.');
    expect(kAppShortcutsText, isNot(contains('Hey')));
  });

  test('the screen source carries no linking card or brand', () {
    final src =
        File('lib/features/voice/voice_assistant_guide_screen.dart').readAsStringSync();
    for (final word in const ['Alexa', 'alexa', 'Google', 'google']) {
      expect(src, isNot(contains(word)), reason: word);
    }
    expect(src, contains('_buildSiriSection('));
    expect(src, contains('_buildAppShortcutsSection('));
    expect(src, contains('_buildHomeAssistantSection('));
  });
}
