// test/features/ai/recurring_sports_autopilot_intent_test.dart
//
// Parser tests for RecurringSportsAutopilotIntent.fromJson — the compact
// "every game / all season" sports rule the cloud AI emits instead of
// enumerating ~80 game dates. Pure-function tests with fixture maps; no
// model call, no Firebase, no Riverpod.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_intent.dart';

void main() {
  group('RecurringSportsAutopilotIntent.fromJson', () {
    test('null input → null', () {
      expect(RecurringSportsAutopilotIntent.fromJson(null), isNull);
    });

    test('missing teamSlug → null', () {
      expect(
        RecurringSportsAutopilotIntent.fromJson({'untilDate': '2026-10-31'}),
        isNull,
      );
    });

    test('empty teamSlug → null', () {
      expect(
        RecurringSportsAutopilotIntent.fromJson({'teamSlug': '   '}),
        isNull,
      );
    });

    test('slug only (open-ended) → parsed, untilDate null', () {
      final intent =
          RecurringSportsAutopilotIntent.fromJson({'teamSlug': 'mlb_royals'});
      expect(intent, isNotNull);
      expect(intent!.teamSlug, 'mlb_royals');
      expect(intent.untilDate, isNull);
    });

    test('slug + valid untilDate → both parsed', () {
      final intent = RecurringSportsAutopilotIntent.fromJson({
        'teamSlug': 'mlb_royals',
        'untilDate': '2026-10-31',
      });
      expect(intent, isNotNull);
      expect(intent!.teamSlug, 'mlb_royals');
      expect(intent.untilDate, DateTime(2026, 10, 31));
    });

    test('slug trimmed', () {
      final intent = RecurringSportsAutopilotIntent.fromJson({
        'teamSlug': '  nfl_chiefs  ',
      });
      expect(intent!.teamSlug, 'nfl_chiefs');
    });

    test('malformed untilDate is dropped, intent still valid (open-ended)', () {
      final intent = RecurringSportsAutopilotIntent.fromJson({
        'teamSlug': 'nba_lakers',
        'untilDate': 'next October',
      });
      expect(intent, isNotNull);
      expect(intent!.teamSlug, 'nba_lakers');
      expect(intent.untilDate, isNull);
    });

    test('rollover date (2026-02-30) rejected → untilDate null', () {
      final intent = RecurringSportsAutopilotIntent.fromJson({
        'teamSlug': 'mlb_royals',
        'untilDate': '2026-02-30',
      });
      expect(intent, isNotNull);
      expect(intent!.untilDate, isNull);
    });

    test('non-padded date (2026-3-1) rejected → untilDate null', () {
      final intent = RecurringSportsAutopilotIntent.fromJson({
        'teamSlug': 'mlb_royals',
        'untilDate': '2026-3-1',
      });
      expect(intent!.untilDate, isNull);
    });
  });
}
