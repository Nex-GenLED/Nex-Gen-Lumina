// test/features/ai/lumina_surfaces_source_guard_test.dart
//
// Source-level guard for UX audit pattern P7 — "two hand-copied Lumina
// conversation drivers". The send, schedule, ephemeral-session, navigation,
// preview-extraction and apply routines live ONCE, in
// lumina_conversation_driver.dart. Both surfaces call it. This test reads
// the two surface files as text and fails if either grows its own copy back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _surfaces = [
  'lib/features/ai/lumina_bottom_sheet.dart',
  'lib/features/ai/lumina_ai_screen.dart',
];

const _driver = 'lib/features/ai/lumina_conversation_driver.dart';

/// Routines that must not be defined on a surface any more.
const _movedRoutines = [
  '_extractPreview',
  '_handleNavigation',
  '_buildEphemeralAugmentation',
  '_handleScheduleResult',
  '_handleEphemeralSession',
  '_priorUserPrompt',
];

/// Calls that only the driver makes. A surface reaching for one of these is
/// a second copy of a driver routine under a new name.
const _driverOnlyCalls = [
  'LuminaCommandRouter.route(',
  '.applyToDevice(',
  'EphemeralSessionDispatcher.dispatch(',
  'handleSchedulingIntents(',
  'handleRecurringSportsAutopilot(',
  '.importSmartSchedule(',
  '.setLuminaPatternMetadata(',
  'resolveLuminaDisplayName(',
  "['isSchedule']",
];

void main() {
  for (final path in _surfaces) {
    group(path, () {
      final source = File(path).readAsStringSync();

      for (final name in _movedRoutines) {
        test('does not define or call $name', () {
          expect(RegExp('\\b$name\\b').hasMatch(source), isFalse,
              reason: '$name belongs to $_driver');
        });
      }

      for (final call in _driverOnlyCalls) {
        test('does not call $call', () {
          expect(source.contains(call), isFalse,
              reason: '$call belongs to $_driver');
        });
      }

      test('sends and applies through the shared driver', () {
        expect(source.contains('lumina_conversation_driver.dart'), isTrue);
        expect(source.contains('LuminaConversationDriver('), isTrue);
        expect(source.contains('_driver.send('), isTrue);
        expect(source.contains('_driver.applyFromBubble('), isTrue);
      });
    });
  }

  group(_driver, () {
    final source = File(_driver).readAsStringSync();

    test('holds the schedule branch exactly once', () {
      expect('scheduleFlags.hasOccurrences'.allMatches(source).length, 1);
      expect(
          RegExp(r'Future<void> _handleScheduleResult\(')
              .allMatches(source)
              .length,
          1);
    });

    // Each audit row package E fixes is tagged at its edit point.
    for (final row in [7, 74, 105, 109, 112]) {
      test('tags the edit point for UX audit row $row', () {
        expect(source.contains('UX audit row $row'), isTrue);
      });
    }
  });
}
