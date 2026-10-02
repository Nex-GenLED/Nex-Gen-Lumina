// +114 (plan §5) — the in-app Game Day claims that were not true for customers.
//
// Source-level guard, same pattern as lumina_surfaces_source_guard_test.dart:
// read the files as text and fail if a retired promise comes back. What is true
// today: start/end fire from our servers for a served home and from the phone
// (app open at home, plus the ON-only lease) for everyone else; celebrations
// play only while the app is on screen.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// file → claims that must not appear in it any more.
const Map<String, List<String>> _retired = {
  'lib/features/game_day/game_day_screen.dart': [
    'automatically come alive',
    'celebrate every point',
  ],
  'lib/features/game_day/live_scoring_prompt.dart': [
    'celebrate every score',
  ],
  'lib/features/autopilot/base_layer_gate.dart': [
    'turns them back off',
  ],
  'lib/features/ai/recurring_sports_autopilot_handler.dart': [
    'for every game automatically',
  ],
  'lib/features/game_day/gate_status_banner.dart': [
    'Your lights will fire for upcoming games',
  ],
  'lib/features/site/edit_profile_screen.dart': [
    'Lumina will automatically schedule',
  ],
  'lib/services/notifications_service.dart': [
    'Game Day mode activating',
    'showGameDayAlert(',
  ],
};

/// file → the replacement wording that must be present.
const Map<String, List<String>> _present = {
  'lib/features/game_day/live_scoring_prompt.dart': [
    "celebrate your team\\'s scores while the app '",
  ],
  'lib/features/autopilot/base_layer_gate.dart': [
    'if our servers run Game Day for your home',
  ],
  'lib/features/ai/recurring_sports_autopilot_handler.dart': [
    'while the app is open at ',
    'Our servers run Game Day for ',
  ],
};

void main() {
  _retired.forEach((path, claims) {
    group(path, () {
      final source = File(path).readAsStringSync();
      for (final claim in claims) {
        test('no longer says "$claim"', () {
          expect(source.contains(claim), isFalse);
        });
      }
    });
  });

  _present.forEach((path, phrases) {
    group(path, () {
      final source = File(path).readAsStringSync();
      for (final phrase in phrases) {
        test('says "$phrase"', () {
          expect(source.contains(phrase), isTrue);
        });
      }
    });
  });

  test('nothing in lib/ calls the removed Game Day notification', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('showGameDayAlert'))
        .toList();
    expect(hits, isEmpty);
  });
}
