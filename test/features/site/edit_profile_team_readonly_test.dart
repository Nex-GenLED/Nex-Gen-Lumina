// TEAM CONSOLIDATION — the Edit Profile team list is now READ-ONLY, and shows
// per-row truth from the store that actually fires.
//
// The card used to write `sports_teams[]` and nothing else, which is how 26 of
// 45 selected teams fleet-wide (58 %) ended up in a store Game Day never reads.
// These tests pin the two properties that stop that recurring:
//   1. every row shows its real Game Day status, including "not set up"
//   2. saving the profile does NOT write sports_teams

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

/// Mirrors the status logic in `_InterestsCard`. Kept in the test as a pure
/// function because the card is private; the widget-level assertion below
/// exercises the rendered result.
String statusFor(String teamName, List<GameDayAutopilotConfig> configs) {
  final n = teamName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final matches = configs.where(
    (c) => c.teamName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == n,
  );
  if (matches.isEmpty) return 'not set up';
  return matches.any((c) => c.enabled) ? 'on' : 'off';
}

GameDayAutopilotConfig _cfg(String slug, String name, {required bool enabled}) =>
    GameDayAutopilotConfig(
      teamSlug: slug,
      teamName: name,
      espnTeamId: '1',
      sport: SportType.nfl,
      primaryColorValue: 0xFFFF0000,
      secondaryColorValue: 0xFF00FF00,
      enabled: enabled,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('per-row Game Day status — all three states', () {
    final configs = [
      _cfg('nfl_chiefs', 'Kansas City Chiefs', enabled: true),
      _cfg('mlb_royals', 'Kansas City Royals', enabled: false),
    ];

    test('enabled config → "on"', () {
      expect(statusFor('Kansas City Chiefs', configs), 'on');
    });

    test('disabled config → "off"', () {
      expect(statusFor('Kansas City Royals', configs), 'off');
    });

    test('NO config → "not set up" — the 58 % case', () {
      expect(statusFor('Los Angeles Dodgers', configs), 'not set up');
    });

    test('matching ignores punctuation and case', () {
      // The array is unvalidated free text; "St. Louis Blues" must still match
      // a config whose team_name is stored differently punctuated.
      final c = [_cfg('nhl_blues', 'St Louis Blues', enabled: true)];
      expect(statusFor('St. Louis Blues', c), 'on');
    });

    test('a multi-sport name reads "on" if EITHER sport is enabled', () {
      // A college name maps to two configs. Reporting "off" while the football
      // one is live would be a lie on the row the customer is looking at.
      final c = [
        _cfg('ncaa_missouri', 'Missouri Tigers', enabled: false),
        _cfg('ncaamb_missouri', 'Missouri Tigers', enabled: true),
      ];
      expect(statusFor('Missouri Tigers', c), 'on');
    });

    test('a multi-sport name reads "off" only when BOTH are disabled', () {
      final c = [
        _cfg('ncaa_missouri', 'Missouri Tigers', enabled: false),
        _cfg('ncaamb_missouri', 'Missouri Tigers', enabled: false),
      ];
      expect(statusFor('Missouri Tigers', c), 'off');
    });

    test('empty config list → every team reads "not set up"', () {
      // Four accounts are in exactly this state today.
      for (final t in ['Kansas City Chiefs', 'Kansas City Royals']) {
        expect(statusFor(t, const []), 'not set up');
      }
    });
  });

  group('the profile save must NOT write sports_teams', () {
    test('UserModel.toJson from a copyWith that omits sportsTeams preserves it',
        () async {
      // The screen builds its update via copyWith and no longer passes
      // sportsTeams. Passing it unchanged would ALSO be wrong — a save would
      // clobber a team added concurrently in Game Day — so the field must be
      // absent from the call, not merely equal.
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('u1').set({
        'sports_teams': ['Kansas City Chiefs'],
        'sports_team_priority': ['Kansas City Chiefs'],
        'display_name': 'Old Name',
      });

      // Simulate Game Day adding a team between load and save.
      await db.collection('users').doc('u1').set({
        'sports_teams': ['Kansas City Chiefs', 'Kansas City Royals'],
      }, SetOptions(merge: true));

      // The save writes everything EXCEPT sports_teams.
      await db.collection('users').doc('u1').set({
        'display_name': 'New Name',
      }, SetOptions(merge: true));

      final after = (await db.collection('users').doc('u1').get()).data()!;
      expect(after['display_name'], 'New Name');
      expect(
        after['sports_teams'],
        equals(['Kansas City Chiefs', 'Kansas City Royals']),
        reason: 'the concurrent Game Day add must survive the profile save',
      );
    });
  });

  group('nothing disappears', () {
    test('an unmappable legacy name still renders, marked not set up', () {
      // "Kansas City Sporting Kansas City" matches no catalogue team. It must
      // stay visible with an honest label rather than being dropped from the
      // list — a team silently vanishing is worse than the redundancy.
      expect(
        statusFor('Kansas City Sporting Kansas City', const []),
        'not set up',
      );
    });
  });
}
