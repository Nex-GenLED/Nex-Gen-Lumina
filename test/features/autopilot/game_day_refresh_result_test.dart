// Pins the refresh-report classification.
//
// The bug being foreclosed: "Schedule refreshed!" fired unconditionally,
// including after every team's populate failed. The classification is pure so
// that "did this actually work" can be asserted without a Firestore, an ESPN
// endpoint or a controller — which is exactly why it lives in its own file
// rather than inline in the notifier.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_refresh_result.dart';

void main() {
  group('GameDayRefreshResult.fromPopulate — classification', () {
    test('no failures over N teams is success', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 3,
        entriesWritten: 11,
        failedTeams: const [],
      );
      expect(r.outcome, GameDayRefreshOutcome.success);
      expect(r.isProblem, isFalse);
      expect(r.userMessage, contains('3 teams'));
      expect(r.userMessage, contains('11 games'));
    });

    test('some failed, some wrote is partial — and says which failed', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 3,
        entriesWritten: 4,
        failedTeams: const ['Kansas City Chiefs'],
      );
      expect(r.outcome, GameDayRefreshOutcome.partial);
      expect(r.isProblem, isTrue);
      expect(r.userMessage, contains('Kansas City Chiefs'));
      // Two of three succeeded, so the count reported is the successes.
      expect(r.userMessage, contains('2 teams'));
    });

    test('EVERY team failed is failed, never success', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 2,
        entriesWritten: 0,
        failedTeams: const ['Chiefs', 'Jets'],
      );
      expect(r.outcome, GameDayRefreshOutcome.failed);
      expect(r.isProblem, isTrue);
      // THE REGRESSION GUARD. This is the exact string the old unconditional
      // snackbar showed after a total failure.
      expect(r.userMessage, isNot(contains('Refreshed')));
    });

    test('a duplicate slug in the failure list cannot downgrade a total '
        'failure to partial', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 2,
        entriesWritten: 0,
        failedTeams: const ['Chiefs', 'Chiefs', 'Jets'],
      );
      expect(r.outcome, GameDayRefreshOutcome.failed);
    });

    test('zero enabled teams is noTeams, not a failure', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 0,
        entriesWritten: 0,
        failedTeams: const [],
      );
      expect(r.outcome, GameDayRefreshOutcome.noTeams);
      expect(r.isProblem, isFalse);
    });

    test('a quiet week is success, and says so rather than implying a fault',
        () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 1,
        entriesWritten: 0,
        failedTeams: const [],
      );
      expect(r.outcome, GameDayRefreshOutcome.success);
      expect(r.isProblem, isFalse);
      expect(r.userMessage, contains('no games scheduled'));
    });

    test('failure list is unmodifiable — the result cannot be edited after '
        'classification', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 2,
        entriesWritten: 1,
        failedTeams: ['Chiefs'],
      );
      expect(() => r.failedTeams.add('Jets'), throwsUnsupportedError);
    });
  });

  group('refusal outcomes', () {
    test('alreadyRunning does not claim to have refreshed anything', () {
      const r = GameDayRefreshResult.alreadyRunning();
      expect(r.outcome, GameDayRefreshOutcome.alreadyRunning);
      expect(r.entriesWritten, 0);
      expect(r.wroteAnything, isFalse);
      expect(r.userMessage, isNot(contains('Refreshed')));
      // Not a problem to report in red — it is the guard working.
      expect(r.isProblem, isFalse);
    });

    test('skippedByGate does not claim to have refreshed anything', () {
      const r = GameDayRefreshResult.skippedByGate();
      expect(r.outcome, GameDayRefreshOutcome.skippedByGate);
      expect(r.userMessage, isNot(contains('Refreshed')));
      expect(r.isProblem, isFalse);
    });
  });

  group('message shaping', () {
    test('singular team and game read naturally', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 1,
        entriesWritten: 1,
        failedTeams: const [],
      );
      expect(r.userMessage, contains('1 team,'));
      expect(r.userMessage, contains('1 game'));
      expect(r.userMessage, isNot(contains('1 teams')));
      expect(r.userMessage, isNot(contains('1 games')));
    });

    test('a single total failure names the team', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 1,
        entriesWritten: 0,
        failedTeams: const ['Kansas City Chiefs'],
      );
      expect(r.outcome, GameDayRefreshOutcome.failed);
      expect(r.userMessage, contains('Kansas City Chiefs'));
    });

    test('many failures are bounded rather than listed in full', () {
      final r = GameDayRefreshResult.fromPopulate(
        teamsAttempted: 9,
        entriesWritten: 2,
        failedTeams: const ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'],
      );
      expect(r.outcome, GameDayRefreshOutcome.partial);
      expect(r.userMessage, contains('and 6 more'));
      // The eighth name must not appear — that is the whole point of bounding.
      expect(r.userMessage, isNot(contains('H')));
    });

    test('every outcome yields a non-empty message', () {
      for (final o in GameDayRefreshOutcome.values) {
        final r = GameDayRefreshResult(
          outcome: o,
          teamsAttempted: 2,
          entriesWritten: 1,
          failedTeams: const ['Chiefs'],
        );
        expect(r.userMessage, isNotEmpty, reason: 'no message for $o');
      }
    });
  });
}
