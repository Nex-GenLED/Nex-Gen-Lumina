// Tests for GameDayAutopilotConfig.shortTeamName — the Now Playing
// labelHint composition path (Fix 3 / Bug A Part 2: no raw symbols).
//
// Pre-fix: shortTeamName splits teamSlug on hyphen only. Real slugs
// from kTeamColors use underscores ('nfl_bills', 'cl_ac_milan'), so
// the split was a no-op and the result leaked the league prefix +
// the underscore into Game Day labels (e.g. "Nfl_bills Game Day").
//
// Post-fix behavior:
//   1. Prefer teamShortName(teamName) lookup — handles AC Milan,
//      Inter Milan, Red Sox, Manchester City, etc. via the curated
//      override map. Falls back to .split(' ').last for the ~354
//      standard "City Mascot" team names.
//   2. Fallback (empty teamName): split slug on either - or _,
//      capitalize last meaningful chunk.
//   3. Guarantee: the result NEVER contains '_' for any non-empty
//      teamSlug or teamName.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';

void main() {
  group("shortTeamName — Tyler's primary teams", () {
    test('mlb_royals + "Kansas City Royals" → "Royals"', () {
      final cfg = _cfg(teamSlug: 'mlb_royals', teamName: 'Kansas City Royals');
      expect(cfg.shortTeamName, equals('Royals'));
    });

    test('nfl_chiefs + "Kansas City Chiefs" → "Chiefs"', () {
      final cfg = _cfg(teamSlug: 'nfl_chiefs', teamName: 'Kansas City Chiefs');
      expect(cfg.shortTeamName, equals('Chiefs'));
    });

    test('cl_ac_milan + "AC Milan" → "AC Milan" (override map preserves '
        'the acronym + city pair)', () {
      final cfg = _cfg(teamSlug: 'cl_ac_milan', teamName: 'AC Milan');
      expect(cfg.shortTeamName, equals('AC Milan'));
    });
  });

  group("shortTeamName — multi-word nicknames where .last alone is wrong",
      () {
    test('Boston Red Sox → "Red Sox" (NOT just "Sox")', () {
      final cfg = _cfg(teamSlug: 'mlb_red_sox', teamName: 'Boston Red Sox');
      expect(cfg.shortTeamName, equals('Red Sox'));
    });

    test('Chicago White Sox → "White Sox"', () {
      final cfg = _cfg(teamSlug: 'mlb_white_sox', teamName: 'Chicago White Sox');
      expect(cfg.shortTeamName, equals('White Sox'));
    });

    test('Toronto Blue Jays → "Blue Jays"', () {
      final cfg = _cfg(teamSlug: 'mlb_blue_jays', teamName: 'Toronto Blue Jays');
      expect(cfg.shortTeamName, equals('Blue Jays'));
    });

    test('Vegas Golden Knights → "Golden Knights"', () {
      final cfg =
          _cfg(teamSlug: 'nhl_golden_knights', teamName: 'Vegas Golden Knights');
      expect(cfg.shortTeamName, equals('Golden Knights'));
    });
  });

  group("shortTeamName — league suffixes / ambiguous city share", () {
    test('Manchester City → "Man City" (NOT "City")', () {
      final cfg = _cfg(teamSlug: 'epl_man_city', teamName: 'Manchester City');
      expect(cfg.shortTeamName, equals('Man City'));
    });

    test('Inter Miami CF → "Inter Miami" (strips CF suffix)', () {
      final cfg = _cfg(teamSlug: 'mls_inter_miami', teamName: 'Inter Miami CF');
      expect(cfg.shortTeamName, equals('Inter Miami'));
    });

    test('Inter Milan → "Inter" (distinct from AC Milan)', () {
      final cfg = _cfg(teamSlug: 'sa_inter', teamName: 'Inter Milan');
      expect(cfg.shortTeamName, equals('Inter'));
    });
  });

  group("shortTeamName — fallback path (empty teamName)", () {
    test('underscore-only slug → split-and-take-last works', () {
      final cfg = _cfg(teamSlug: 'nfl_bills', teamName: '');
      expect(cfg.shortTeamName, equals('Bills'));
    });

    test('hyphen-only slug (legacy doc path) → still split correctly', () {
      final cfg = _cfg(teamSlug: 'kansas-city-royals', teamName: '');
      expect(cfg.shortTeamName, equals('Royals'));
    });

    test('mixed - and _ slug → split on either', () {
      final cfg = _cfg(teamSlug: 'cl_ac-milan', teamName: '');
      expect(cfg.shortTeamName, equals('Milan'));
    });

    test('empty slug + empty teamName → empty teamName (the existing edge)',
        () {
      final cfg = _cfg(teamSlug: '', teamName: '');
      expect(cfg.shortTeamName, equals(''));
    });
  });

  group("shortTeamName — REGRESSION: no underscore leak for any "
      "kTeamColors entry", () {
    test('every team slug in kTeamColors → shortTeamName has NO underscore '
        'and NO unstripped league prefix', () {
      for (final entry in kTeamColors.entries) {
        final slug = entry.key;
        final teamName = entry.value.teamName;
        final cfg = _cfg(teamSlug: slug, teamName: teamName);
        final short = cfg.shortTeamName;
        expect(short, isNot(contains('_')),
            reason: 'shortTeamName for slug=$slug teamName=$teamName '
                'returned "$short" — must NOT contain underscore.');
        // Cheap sanity: should not be the raw slug either (e.g. "nfl_bills"
        // capitalized).
        expect(short.toLowerCase(), isNot(equals(slug.toLowerCase())),
            reason: 'shortTeamName for slug=$slug returned the raw slug.');
      }
    });

    test('every team slug + composed Game Day labelHint → no underscore '
        'anywhere in the result (the on-device symptom)', () {
      for (final entry in kTeamColors.entries) {
        final slug = entry.key;
        final teamName = entry.value.teamName;
        final cfg = _cfg(teamSlug: slug, teamName: teamName);
        final label = '${cfg.shortTeamName} Game Day';
        expect(label, isNot(contains('_')),
            reason: 'Game Day labelHint for $slug = "$label" — '
                'must NOT contain underscore.');
      }
    });
  });
}

GameDayAutopilotConfig _cfg({
  required String teamSlug,
  required String teamName,
}) {
  return GameDayAutopilotConfig(
    teamSlug: teamSlug,
    teamName: teamName,
    espnTeamId: '0',
    sport: SportType.mlb,
    primaryColorValue: 0xFFFFFFFF,
    secondaryColorValue: 0xFF000000,
    createdAt: DateTime.utc(2026, 5, 23),
    updatedAt: DateTime.utc(2026, 5, 23),
  );
}
