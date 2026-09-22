// test/features/autopilot/game_day_priority_resolver_test.dart
//
// The unit test GameDayPriorityResolver never had.
//
// It shipped as pure, well-commented, fully-specified code with exactly one
// caller — the background worker, which is compiled off — and no test. That
// combination is what let a real defect sit in it unnoticed: `_priorityRank`
// looks the candidate up by SLUG, every caller fed it a list of DISPLAY
// NAMES, so every lookup missed, every team ranked last, and the resolver
// quietly degraded to first-come-first-served while reading like an arbiter
// (audit/gameday-game-selection-2026-09-21 §3).
//
// So the ranking cases below are not ceremony. `ranks by slug` and
// `display-name list ranks NOBODY` are the two that would have caught it.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_priority_resolver.dart';

GameDayEventCandidate _c(
  String slug, {
  GameDayEventSource source = GameDayEventSource.personalAutopilot,
  String espnTeamId = '0',
  String? gameId,
  DateTime? activatedAt,
}) =>
    GameDayEventCandidate(
      id: slug,
      source: source,
      teamSlug: slug,
      espnTeamId: espnTeamId,
      activatedAt: activatedAt ?? DateTime(2026, 9, 22, 12),
      gameId: gameId,
    );

void main() {
  // The production shape: Chiefs ranked above Royals.
  const priority = ['nfl_chiefs', 'mlb_royals'];

  group('resolve — no contention', () {
    test('empty active set always activates', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('mlb_royals'),
        activeEvents: const [],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.activate);
      expect(r.affectedBy, isNull);
    });

    test('an unranked team with no competition still activates — the '
        'hierarchy gates contention, never participation', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nhl_blues'),
        activeEvents: const [],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.activate);
    });
  });

  group('resolve — ranking (the defect this file exists for)', () {
    test('ranks by SLUG: #1 preempts #2 even though #2 got there first', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs'),
        activeEvents: [_c('mlb_royals', activatedAt: DateTime(2026, 9, 22, 9))],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.preempt);
      expect(r.affectedBy?.teamSlug, 'mlb_royals');
      expect(r.reason, contains('#1'));
    });

    test('#2 defers to #1 regardless of which activated first', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('mlb_royals'),
        activeEvents: [_c('nfl_chiefs', activatedAt: DateTime(2026, 9, 22, 18))],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.defer);
      expect(r.affectedBy?.teamSlug, 'nfl_chiefs');
    });

    test(
        'a DISPLAY-NAME list ranks NOBODY — the shipped bug. Both teams fall '
        'to "unlisted", so the outcome is decided by arrival time, not by the '
        'order the user set. This is why the arbiter is fed '
        'game_day_team_priority and not sports_team_priority.', () {
      const namesList = ['Kansas City Chiefs', 'Kansas City Royals'];
      // Chiefs is #1 in that list, but arrives second.
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs', activatedAt: DateTime(2026, 9, 22, 18)),
        activeEvents: [_c('mlb_royals', activatedAt: DateTime(2026, 9, 22, 9))],
        teamPriority: namesList,
      );
      // Not preempt: the #1 team loses to a first-come tie-break.
      expect(r.decision, GameDayPriorityDecision.defer);
      expect(r.reason, contains('Equal priority'));
    });

    test('a ranked team beats an UNRANKED one', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('mlb_royals'),
        activeEvents: [_c('nhl_blues')],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.preempt);
    });

    test('an unranked team defers to a ranked one', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nhl_blues'),
        activeEvents: [_c('mlb_royals')],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.defer);
    });

    test('with three actives the candidate must beat ALL of them', () {
      // Chiefs is #1, so it preempts whichever competitor it is compared to.
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs'),
        activeEvents: [_c('nhl_blues'), _c('mlb_royals')],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.preempt);
    });

    test('the LOWEST-ranked of three defers rather than activating', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nhl_blues'),
        activeEvents: [_c('nfl_chiefs'), _c('mlb_royals')],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.defer);
    });
  });

  group('resolve — ties', () {
    test('equal rank: the one already active keeps the house', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('a_team', activatedAt: DateTime(2026, 9, 22, 14)),
        activeEvents: [_c('b_team', activatedAt: DateTime(2026, 9, 22, 13))],
        teamPriority: const [],
      );
      expect(r.decision, GameDayPriorityDecision.defer);
      expect(r.reason, contains('activated first'));
    });

    test('equal rank, candidate is the EARLIER one: it activates', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('a_team', activatedAt: DateTime(2026, 9, 22, 12)),
        activeEvents: [_c('b_team', activatedAt: DateTime(2026, 9, 22, 13))],
        teamPriority: const [],
      );
      expect(r.decision, GameDayPriorityDecision.activate);
    });

    test('identical activation instants do not deadlock — one side wins and '
        'the result is a decision, never an exception', () {
      final t = DateTime(2026, 9, 22, 12);
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('a_team', activatedAt: t),
        activeEvents: [_c('b_team', activatedAt: t)],
        teamPriority: const [],
      );
      expect(r.decision, GameDayPriorityDecision.activate);
    });
  });

  group('resolve — degenerate empty list', () {
    test('empty priority falls through to first-come-first-served, which is '
        'the pre-hierarchy behaviour — an unwired callback degrades to the '
        'old conduct, not to an error', () {
      final first = _c('mlb_royals', activatedAt: DateTime(2026, 9, 22, 9));
      final late = _c('nfl_chiefs', activatedAt: DateTime(2026, 9, 22, 18));
      final r = GameDayPriorityResolver.resolve(
        candidate: late,
        activeEvents: [first],
        teamPriority: const [],
      );
      expect(r.decision, GameDayPriorityDecision.defer);
    });

    test('a priority list naming teams that are not playing is inert', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nhl_blues'),
        activeEvents: const [],
        teamPriority: const ['nfl_bills', 'mlb_mets'],
      );
      expect(r.decision, GameDayPriorityDecision.activate);
    });
  });

  group('resolve — same game (rule 1, unchanged)', () {
    test('personal autopilot defers to a neighborhood sync on the same game',
        () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs', gameId: 'g1'),
        activeEvents: [
          _c('nfl_chiefs',
              source: GameDayEventSource.neighborhoodSync, gameId: 'g1'),
        ],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.defer);
      expect(r.reason, contains('Neighborhood sync'));
    });

    test('neighborhood sync preempts personal autopilot on the same game', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs',
            source: GameDayEventSource.neighborhoodSync, gameId: 'g1'),
        activeEvents: [_c('nfl_chiefs', gameId: 'g1')],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.preempt);
    });

    test('rule 1 beats rule 2: a #1 team still yields to a sync on its own '
        'game', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs', gameId: 'g1'),
        activeEvents: [
          _c('nfl_chiefs',
              source: GameDayEventSource.neighborhoodSync, gameId: 'g1'),
        ],
        teamPriority: const ['nfl_chiefs'],
      );
      expect(r.decision, GameDayPriorityDecision.defer);
    });

    test('a duplicate personal event for the same game defers', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs', gameId: 'g1'),
        activeEvents: [_c('nfl_chiefs', gameId: 'g1')],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.defer);
      expect(r.reason, contains('Duplicate'));
    });

    test('same slug + espn id within 6h is the same game even with no gameId',
        () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('nfl_chiefs',
            espnTeamId: '12', activatedAt: DateTime(2026, 9, 22, 12)),
        activeEvents: [
          _c('nfl_chiefs',
              espnTeamId: '12',
              source: GameDayEventSource.neighborhoodSync,
              activatedAt: DateTime(2026, 9, 22, 15)),
        ],
        teamPriority: priority,
      );
      expect(r.decision, GameDayPriorityDecision.defer);
    });

    test('same slug more than 6h apart is a DIFFERENT game (doubleheader) and '
        'falls through to the priority rules', () {
      final r = GameDayPriorityResolver.resolve(
        candidate: _c('mlb_royals',
            espnTeamId: '7', activatedAt: DateTime(2026, 9, 22, 12)),
        activeEvents: [
          _c('mlb_royals',
              espnTeamId: '7', activatedAt: DateTime(2026, 9, 22, 21)),
        ],
        teamPriority: priority,
      );
      // Equal rank (same team), candidate is earlier ⇒ activates.
      expect(r.decision, GameDayPriorityDecision.activate);
    });
  });

  group('handoffWinner — rule 5', () {
    test('no candidates left returns null, which is the ONLY licence to '
        'resume the normal schedule', () {
      expect(
        GameDayPriorityResolver.handoffWinner(
          remaining: const [],
          teamPriority: priority,
        ),
        isNull,
      );
    });

    test('single remaining candidate takes the house', () {
      final w = GameDayPriorityResolver.handoffWinner(
        remaining: [_c('mlb_royals')],
        teamPriority: priority,
      );
      expect(w?.teamSlug, 'mlb_royals');
    });

    test('highest priority wins, regardless of list position', () {
      final w = GameDayPriorityResolver.handoffWinner(
        remaining: [_c('nhl_blues'), _c('mlb_royals'), _c('nfl_chiefs')],
        teamPriority: priority,
      );
      expect(w?.teamSlug, 'nfl_chiefs');
    });

    test('an unranked team is only chosen when nothing ranked remains', () {
      final w = GameDayPriorityResolver.handoffWinner(
        remaining: [_c('nhl_blues'), _c('mlb_royals')],
        teamPriority: priority,
      );
      expect(w?.teamSlug, 'mlb_royals');
    });

    test('all unranked: earliest activation wins (matches rule 3)', () {
      final w = GameDayPriorityResolver.handoffWinner(
        remaining: [
          _c('z_team', activatedAt: DateTime(2026, 9, 22, 20)),
          _c('a_team', activatedAt: DateTime(2026, 9, 22, 10)),
        ],
        teamPriority: const [],
      );
      expect(w?.teamSlug, 'a_team');
    });

    test('equal rank ties break by earliest activation, not list order', () {
      final w = GameDayPriorityResolver.handoffWinner(
        remaining: [
          _c('b_team', activatedAt: DateTime(2026, 9, 22, 11)),
          _c('a_team', activatedAt: DateTime(2026, 9, 22, 10)),
        ],
        teamPriority: const [],
      );
      expect(w?.teamSlug, 'a_team');
    });

    test('empty priority list still picks a winner rather than going dark — '
        'the dark-mid-game bug must not reappear just because the hierarchy '
        'is unset', () {
      final w = GameDayPriorityResolver.handoffWinner(
        remaining: [_c('mlb_royals')],
        teamPriority: const [],
      );
      expect(w, isNotNull);
    });
  });
}
