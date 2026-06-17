// Verifies SportsLibraryBuilder.resolveTeamNodeId — the Game Day "Design"
// picker's slug→catalog-leaf-node resolver. Pure data resolution; no Firebase.
//
// Covers the Phase-0/Phase-1 verification matrix:
//   - regression: a coincidentally-working domestic team (Royals)
//   - previously-broken: MLS city-strip (Atlanta United), Champions League
//     (AC Milan, incl. espn fast-path)
//   - NCAA sport-aware tiebreak: same school name resolves to the
//     sport-correct node (football vs basketball)
//   - no-match → null (honest message, never wrong team)

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/sports_library_builder.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';

LibraryNode? _nodeById(String id) {
  final leaves = <LibraryNode>[
    ...SportsLibraryBuilder.getTeamPaletteNodes(),
    ...SportsLibraryBuilder.getInternationalSoccerNodes(),
    ...NcaaConferences.getAllSchoolNodes(),
  ];
  for (final n in leaves) {
    if (n.id == id) return n;
  }
  return null;
}

void main() {
  group('resolveTeamNodeId', () {
    test('regression: domestic Royals resolves to its MLB leaf', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Kansas City Royals',
        sport: SportType.mlb,
        espnTeamId: '7', // ESPN Royals id; catalog domestic espn is null so
        // this exercises the name path, which is the real domestic case.
      );
      expect(id, isNotNull);
      expect(id, 'team_mlb_royals');
      final node = _nodeById(id!);
      expect(node, isNotNull);
      expect(node!.isPalette, isTrue);
      expect(node.metadata?['league'], 'MLB');
    });

    test('previously-broken: MLS Atlanta United (city-strip) resolves', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Atlanta United FC',
        sport: SportType.mls,
        espnTeamId: '18512',
      );
      expect(id, isNotNull);
      // Catalog strips the city: name "United FC" → team_mls_united_fc.
      expect(id, 'team_mls_united_fc');
      expect(_nodeById(id!)?.metadata?['league'], 'MLS');
    });

    test('previously-broken: Champions League AC Milan resolves (+espn)', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'AC Milan',
        sport: SportType.championsLeague,
        espnTeamId: '103',
      );
      expect(id, isNotNull);
      final node = _nodeById(id!);
      expect(node, isNotNull);
      // Must land on the Champions League node, not a Serie A "AC Milan".
      expect(node!.metadata?['league'], 'Champions League');
      expect(node.metadata?['espnTeamId'], '103');
    });

    test('Champions League resolves even without espn (name path)', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Arsenal',
        sport: SportType.championsLeague,
        espnTeamId: '', // force the name path
      );
      expect(id, isNotNull);
      expect(_nodeById(id!)?.metadata?['league'], 'Champions League');
    });

    test('NCAA tiebreak: football context → football node', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Duke Blue Devils',
        sport: SportType.ncaaFB,
      );
      expect(id, isNotNull);
      expect(_nodeById(id!)?.metadata?['sport'], 'football');
    });

    test('NCAA tiebreak: basketball context → basketball node', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Duke Blue Devils',
        sport: SportType.ncaaMB,
      );
      expect(id, isNotNull);
      expect(_nodeById(id!)?.metadata?['sport'], 'basketball');
    });

    test('football and basketball Duke resolve to DIFFERENT nodes', () {
      final fb = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Duke Blue Devils', sport: SportType.ncaaFB);
      final bb = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Duke Blue Devils', sport: SportType.ncaaMB);
      expect(fb, isNotNull);
      expect(bb, isNotNull);
      expect(fb, isNot(bb));
    });

    test('MLS city-prefix club FC Cincinnati resolves (teamName form)', () {
      // Display name is "Cincinnati FC Cincinnati"; the match must hit the
      // city-stripped teamName form "FC Cincinnati".
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'FC Cincinnati',
        sport: SportType.mls,
        espnTeamId: '18644',
      );
      expect(id, isNotNull);
      expect(_nodeById(id!)?.metadata?['league'], 'MLS');
    });

    test('diacritics fold: CF Montréal resolves', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'CF Montreal', // no accent on the config side
        sport: SportType.mls,
      );
      expect(id, isNotNull);
      expect(_nodeById(id!)?.metadata?['league'], 'MLS');
    });

    test('unknown team → null (honest message, never wrong team)', () {
      final id = SportsLibraryBuilder.resolveTeamNodeId(
        teamName: 'Totally Not A Real Team 9000',
        sport: SportType.nfl,
      );
      expect(id, isNull);
    });

    test('resolved node is always a selectable leaf palette', () {
      for (final t in [
        ('Buffalo Bills', SportType.nfl),
        ('Boston Celtics', SportType.nba),
        ('Boston Red Sox', SportType.mlb),
      ]) {
        final id = SportsLibraryBuilder.resolveTeamNodeId(
            teamName: t.$1, sport: t.$2);
        expect(id, isNotNull, reason: '${t.$1} should resolve');
        expect(_nodeById(id!)?.isPalette, isTrue, reason: '${t.$1} leaf');
      }
    });
  });
}
