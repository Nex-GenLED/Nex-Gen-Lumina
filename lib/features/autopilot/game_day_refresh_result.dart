// lib/features/autopilot/game_day_refresh_result.dart
//
// What a Game Day calendar refresh actually did, so the UI can say so.
//
// WHY THIS EXISTS. `refreshAllCalendars` returned `void`. The populate loop
// has always computed `totalEntries` and `failedTeams`
// (game_day_autopilot_providers.dart) and then thrown both away into a
// debugPrint, so the Game Day screen showed an unconditional "Schedule
// refreshed!" — after a partial write, after every team's ESPN fetch failed,
// and after a run that was refused before it started. A success message that
// cannot fail is not a success message; it is decoration.
//
// The shape is deliberately a value object rather than a bool: "did it work"
// has four distinct answers here (did nothing, did everything, did some of it,
// was already running) and collapsing them is what produced the original bug.

import 'package:flutter/foundation.dart';

/// How a refresh attempt ended.
enum GameDayRefreshOutcome {
  /// Every enabled team populated without error.
  success,

  /// At least one team wrote entries and at least one team failed.
  partial,

  /// Every enabled team failed. Nothing usable reached the calendar.
  failed,

  /// The account has no enabled teams. Not a failure — the clear still ran,
  /// which is the #63 E5 teardown contract (disabling the last team must
  /// still strip its future rows).
  noTeams,

  /// The 7-day cadence gate declined the run. Only reachable with
  /// `force: false`; the manual button always forces.
  skippedByGate,

  /// A populate was already in flight and this call was refused. The refusal
  /// is the feature — see the in-flight guard in
  /// [GameDayAutopilotNotifier].
  alreadyRunning,
}

/// The outcome of one calendar refresh, with enough detail to report it.
@immutable
class GameDayRefreshResult {
  final GameDayRefreshOutcome outcome;

  /// Teams the run attempted (enabled configs at the moment it started).
  final int teamsAttempted;

  /// Calendar entries written across all teams.
  final int entriesWritten;

  /// Display names (falling back to slugs) of teams whose populate threw or
  /// returned zero after an error. Names, not slugs, because this list is
  /// read out to the user.
  final List<String> failedTeams;

  const GameDayRefreshResult({
    required this.outcome,
    this.teamsAttempted = 0,
    this.entriesWritten = 0,
    this.failedTeams = const <String>[],
  });

  const GameDayRefreshResult.alreadyRunning()
      : outcome = GameDayRefreshOutcome.alreadyRunning,
        teamsAttempted = 0,
        entriesWritten = 0,
        failedTeams = const <String>[];

  const GameDayRefreshResult.skippedByGate()
      : outcome = GameDayRefreshOutcome.skippedByGate,
        teamsAttempted = 0,
        entriesWritten = 0,
        failedTeams = const <String>[];

  /// Classify a completed populate. PURE — the whole point is that the
  /// success/partial/failed decision is testable without a Firestore, an
  /// ESPN endpoint or a controller.
  ///
  /// `failed` requires that teams were actually attempted: a run over zero
  /// enabled teams is [GameDayRefreshOutcome.noTeams], never a failure.
  factory GameDayRefreshResult.fromPopulate({
    required int teamsAttempted,
    required int entriesWritten,
    required List<String> failedTeams,
  }) {
    if (teamsAttempted == 0) {
      return const GameDayRefreshResult(
        outcome: GameDayRefreshOutcome.noTeams,
      );
    }
    final GameDayRefreshOutcome outcome;
    if (failedTeams.isEmpty) {
      outcome = GameDayRefreshOutcome.success;
    } else if (failedTeams.length >= teamsAttempted) {
      // Every attempted team failed. Note `>=` rather than `==`: a duplicate
      // slug in the failure list must not downgrade a total failure to a
      // partial one.
      outcome = GameDayRefreshOutcome.failed;
    } else {
      outcome = GameDayRefreshOutcome.partial;
    }
    return GameDayRefreshResult(
      outcome: outcome,
      teamsAttempted: teamsAttempted,
      entriesWritten: entriesWritten,
      failedTeams: List<String>.unmodifiable(failedTeams),
    );
  }

  /// True when the run put something on the calendar.
  bool get wroteAnything => entriesWritten > 0;

  /// The line the Game Day screen shows. Lives here, next to the outcome it
  /// describes, so a new outcome cannot be added without the analyzer
  /// pointing at the message for it.
  String get userMessage {
    switch (outcome) {
      case GameDayRefreshOutcome.alreadyRunning:
        return 'Already refreshing — hang tight.';
      case GameDayRefreshOutcome.skippedByGate:
        return 'Schedules are already up to date.';
      case GameDayRefreshOutcome.noTeams:
        return 'No teams have Game Day turned on.';
      case GameDayRefreshOutcome.failed:
        return failedTeams.length == 1
            ? "Couldn't reach the schedule for ${failedTeams.first}."
            : "Couldn't reach any team's schedule. Check your connection.";
      case GameDayRefreshOutcome.partial:
        return 'Refreshed ${_teamsLine(teamsAttempted - failedTeams.length)}, '
            '${_gamesLine(entriesWritten)} — '
            "couldn't reach ${_joinNames(failedTeams)}.";
      case GameDayRefreshOutcome.success:
        return entriesWritten == 0
            ? 'Refreshed ${_teamsLine(teamsAttempted)} — no games scheduled '
                'in the next week.'
            : 'Refreshed ${_teamsLine(teamsAttempted)}, '
                '${_gamesLine(entriesWritten)}.';
    }
  }

  /// True when the message describes something going wrong, so the caller can
  /// colour the snackbar without re-deriving the classification.
  bool get isProblem =>
      outcome == GameDayRefreshOutcome.failed ||
      outcome == GameDayRefreshOutcome.partial;

  static String _teamsLine(int n) => n == 1 ? '1 team' : '$n teams';

  static String _gamesLine(int n) => n == 1 ? '1 game' : '$n games';

  /// "the Chiefs", "the Chiefs and the Jets", "the Chiefs, the Jets and 2
  /// more" — bounded so a ten-team failure does not produce a paragraph.
  static String _joinNames(List<String> names) {
    if (names.isEmpty) return 'some teams';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    return '${names[0]}, ${names[1]} and ${names.length - 2} more';
  }

  @override
  String toString() => 'GameDayRefreshResult($outcome, '
      'teams=$teamsAttempted, entries=$entriesWritten, '
      'failed=$failedTeams)';
}
