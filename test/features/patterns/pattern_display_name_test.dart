import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';

void main() {
  group('displayNameFor — Tyler\'s spec cases', () {
    test('KC_Royals_Game_Day → "KC Royals Game Day"', () {
      expect(displayNameFor('KC_Royals_Game_Day'), 'KC Royals Game Day');
    });

    test('St_Louis_Cardinals_Twinkle → "St Louis Cardinals Twinkle"', () {
      // No override for "St Louis Cardinals" (not in the team-short-name map,
      // its .split().last default of "Cardinals" is correct). Falls through
      // to title-case path; "St" is NOT in the acronyms allowlist so it
      // stays as "St" not "ST".
      expect(displayNameFor('St_Louis_Cardinals_Twinkle'),
          'St Louis Cardinals Twinkle');
    });

    test('warm_white → "Warm White"', () {
      expect(displayNameFor('warm_white'), 'Warm White');
    });

    test('"Already Named Properly" → unchanged (has spaces)', () {
      expect(displayNameFor('Already Named Properly'), 'Already Named Properly');
    });

    test('"" → ""', () {
      expect(displayNameFor(''), '');
    });
  });

  group('displayNameFor — acronym preservation', () {
    test('KC at start → uppercase', () {
      expect(displayNameFor('KC_Mood'), 'KC Mood');
    });

    test('AI at start → uppercase', () {
      expect(displayNameFor('AI_Pulse'), 'AI Pulse');
    });

    test('case-insensitive match: kc_pulse → "KC Pulse"', () {
      // _kAcronyms membership check uppercases the chunk before testing.
      expect(displayNameFor('kc_pulse'), 'KC Pulse');
    });

    test('NY, LA, SF, DC at any position → uppercase', () {
      expect(displayNameFor('NY_Knicks'), 'NY Knicks');
      expect(displayNameFor('LA_Lakers'), 'LA Lakers');
      expect(displayNameFor('SF_Giants'), 'SF Giants');
      expect(displayNameFor('DC_Tour'), 'DC Tour');
    });

    test('3-letter league acronyms', () {
      expect(displayNameFor('NFL_Wave'), 'NFL Wave');
      expect(displayNameFor('NBA_Pulse'), 'NBA Pulse');
      expect(displayNameFor('MLB_Twinkle'), 'MLB Twinkle');
      expect(displayNameFor('NHL_Flash'), 'NHL Flash');
      expect(displayNameFor('MLS_Theme'), 'MLS Theme');
    });

    test('US, UK acronyms', () {
      expect(displayNameFor('US_Flag'), 'US Flag');
      expect(displayNameFor('UK_Theme'), 'UK Theme');
    });

    test('"St" (not in allowlist) stays title-cased, not uppercased', () {
      expect(displayNameFor('St_Patrick'), 'St Patrick');
    });

    test('"Mr" (not in allowlist) stays title-cased', () {
      expect(displayNameFor('Mr_Glow'), 'Mr Glow');
    });
  });

  group('displayNameFor — edge cases', () {
    test('multiple underscores collapsed (empty chunks filtered)', () {
      expect(displayNameFor('warm__white'), 'Warm White');
      expect(displayNameFor('_warm_white_'), 'Warm White');
    });

    test('single word slug → title case', () {
      expect(displayNameFor('shimmer'), 'Shimmer');
    });

    test('all-caps slug chunks fall through to title case unless allowlist',
        () {
      expect(displayNameFor('SHIMMER'), 'Shimmer');
      expect(displayNameFor('MULTI_WORD'), 'Multi Word');
    });

    test('numeric chunks pass through', () {
      expect(displayNameFor('pattern_2024'), 'Pattern 2024');
    });

    test('input with punctuation returned unchanged', () {
      expect(displayNameFor("Tyler's House"), "Tyler's House");
      expect(displayNameFor('Foo-Bar'), 'Foo-Bar');
    });
  });

  group('displayNameFor — team override slug variants', () {
    test('Boston_Red_Sox_Game_Day → "Red Sox Game Day"', () {
      expect(displayNameFor('Boston_Red_Sox_Game_Day'), 'Red Sox Game Day');
    });

    test('Boston_Red_Sox_Twinkle → "Red Sox Twinkle"', () {
      expect(displayNameFor('Boston_Red_Sox_Twinkle'), 'Red Sox Twinkle');
    });

    test('Boston_Red_Sox_Wave → "Red Sox Wave"', () {
      expect(displayNameFor('Boston_Red_Sox_Wave'), 'Red Sox Wave');
    });

    test('Manchester_United_Game_Day → "Man United Game Day"', () {
      expect(displayNameFor('Manchester_United_Game_Day'), 'Man United Game Day');
    });

    test('Inter_Miami_CF_Twinkle → "Inter Miami Twinkle"', () {
      expect(displayNameFor('Inter_Miami_CF_Twinkle'), 'Inter Miami Twinkle');
    });

    test('Vegas_Golden_Knights_Wave → "Golden Knights Wave"', () {
      expect(displayNameFor('Vegas_Golden_Knights_Wave'), 'Golden Knights Wave');
    });

    test(
        'Paris_Saint-Germain_Game_Day (hyphen inside slug) → humanized '
        'via the mixed-input branch. The hyphen rejects the pure-slug '
        'regex; the mixed-input branch tokenizes on whitespace (one '
        'token here) and humanizes the embedded underscore chunks. The '
        '"germain" segment lowercases because _titleCaseOrAcronym only '
        'capitalizes the first character of each underscore chunk and '
        'lowercases the rest — proper-noun casing inside a chunk '
        'containing a hyphen is lost. Acceptable trade-off: production '
        'never generates this slug (Paris Saint-Germain is in the '
        'short-name override map and resolves directly to "PSG"); the '
        'key win is that the underscore no longer leaks through.',
        () {
      expect(displayNameFor('Paris_Saint-Germain_Game_Day'),
          'Paris Saint-germain Game Day');
    });
  });

  group('displayNameFor — override map exhaustiveness', () {
    test('every team in _kTeamShortNames generates 3 slug entries', () {
      final overrides = debugAllSlugOverridesForTest;
      final teams = debugTeamShortNamesForTest;
      for (final teamEntry in teams.entries) {
        final slugBase = teamEntry.key.replaceAll(' ', '_');
        final shortName = teamEntry.value;
        for (final suffix in const ['Game_Day', 'Twinkle', 'Wave']) {
          final slug = '${slugBase}_$suffix';
          final humanSuffix = suffix.replaceAll('_', ' ');
          expect(overrides[slug], '$shortName $humanSuffix',
              reason: 'Missing or wrong override for $slug');
        }
      }
    });

    test('KC_Royals_Game_Day extra override is present', () {
      expect(debugAllSlugOverridesForTest['KC_Royals_Game_Day'],
          'KC Royals Game Day');
    });

    test('total override count = (teams × 3) + extras', () {
      final teamCount = debugTeamShortNamesForTest.length;
      // 1 extra (KC_Royals_Game_Day) plus 3 entries per team.
      expect(debugAllSlugOverridesForTest.length, teamCount * 3 + 1);
    });

    test('acronym allowlist matches Tyler\'s spec', () {
      // CL added 2026-05-23 (Fix 3 Part 2) — Champions League prefix,
      // appears in production slugs as `cl_*`. Tyler's spec named it
      // explicitly alongside NFL/MLB/NHL/NBA.
      expect(debugAcronymsForTest,
          {'KC', 'AI', 'NY', 'LA', 'SF', 'DC', 'US', 'UK', 'CL', 'NFL', 'NBA', 'MLB', 'NHL', 'MLS'});
    });
  });

  group('teamShortName — spaced official-name lookup', () {
    test('override hit returns short form', () {
      expect(teamShortName('Boston Red Sox'), 'Red Sox');
      expect(teamShortName('Manchester United'), 'Man United');
      expect(teamShortName('Vegas Golden Knights'), 'Golden Knights');
      expect(teamShortName('Paris Saint-Germain'), 'PSG');
    });

    test('no override falls back to .split(" ").last', () {
      expect(teamShortName('Kansas City Royals'), 'Royals');
      expect(teamShortName('Los Angeles Dodgers'), 'Dodgers');
      expect(teamShortName('Chicago Bears'), 'Bears');
    });

    test('empty returns empty', () {
      expect(teamShortName(''), '');
    });

    test('every entry in _kTeamShortNames round-trips through teamShortName',
        () {
      for (final entry in debugTeamShortNamesForTest.entries) {
        expect(teamShortName(entry.key), entry.value,
            reason: 'teamShortName("${entry.key}") should equal "${entry.value}"');
      }
    });
  });

  group('displayNameFor — mixed input (Fix 3 Part 2 defense-in-depth)', () {
    test(
        '"Nfl_bills Game Day" → "NFL Bills Game Day". The pre-fix Game '
        'Day leak path: shortTeamName produced "Nfl_bills", composer '
        'appended " Game Day", consumer used to bail on space-bearing '
        'input. Now we humanize underscore chunks within each space-'
        'separated token.', () {
      expect(displayNameFor('Nfl_bills Game Day'),
          equals('NFL Bills Game Day'));
    });

    test(
        '"Pattern: warm_white" → "Pattern: Warm White". The '
        'autopilot_providers / lumina_ai_screen risk shape.', () {
      expect(displayNameFor('Pattern: warm_white'),
          equals('Pattern: Warm White'));
    });

    test('chunks without underscores stay untouched in mixed input', () {
      expect(displayNameFor('Already Clean Label'),
          equals('Already Clean Label'));
    });

    test(
        'mixed input with acronym chunk → acronym preserved on the '
        'embedded slug chunk', () {
      expect(displayNameFor('Pattern: KC_Royals'),
          equals('Pattern: KC Royals'));
    });

    test('pure-slug path unchanged by the mixed-input branch', () {
      expect(displayNameFor('warm_white'), equals('Warm White'));
      expect(displayNameFor('KC_Royals_Game_Day'),
          equals('KC Royals Game Day'));
    });
  });

  group('displayNameFor — CL acronym (Champions League prefix)', () {
    test(
        'CL is in the acronym allowlist (Tyler\'s spec named '
        'NFL/MLB/NHL/NBA/CL).', () {
      expect(debugAcronymsForTest, contains('CL'));
    });

    test(
        'cl_ac_milan_game_day → "CL Ac Milan Game Day". CL uppercased '
        'via the allowlist; AC stays title-cased ("Ac") because it is '
        'NOT in the explicit allowlist (Tyler\'s spec did not name AC). '
        'Defense-in-depth — primary fix in shortTeamName means this '
        'slug should not normally reach displayNameFor.', () {
      expect(displayNameFor('cl_ac_milan_game_day'),
          equals('CL Ac Milan Game Day'));
    });
  });
}
