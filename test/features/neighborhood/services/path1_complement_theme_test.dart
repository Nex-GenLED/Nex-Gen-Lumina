// Tests for [path1ToComplementTheme] — the snapshot→ComplementTheme
// converter that replaces the legacy GameDaySyncConfig.toComplementTheme
// after Phase 2b. Verifies field-for-field parity with the legacy shape
// so the Path 2 swap is behaviorally identical.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_complement_theme.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_game_day_snapshot.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('path1ToComplementTheme', () {
    Path1GameDaySnapshot snapFor({
      String teamSlug = 'mlb_royals',
      String teamName = 'Kansas City Royals',
      SportType sport = SportType.mlb,
      int primary = 0xFF004687,
      int secondary = 0xFFBD9B60,
      int effectId = 52,
    }) {
      final created = DateTime.utc(2026, 5, 1);
      return Path1GameDaySnapshot.fromConfig(
        GameDayAutopilotConfig(
          teamSlug: teamSlug,
          teamName: teamName,
          espnTeamId: '7',
          sport: sport,
          primaryColorValue: primary,
          secondaryColorValue: secondary,
          effectId: effectId,
          createdAt: created,
          updatedAt: created,
        ),
      );
    }

    test('id is "gameday_<teamSlug>"', () {
      expect(path1ToComplementTheme(snapFor()).id, 'gameday_mlb_royals');
    });

    test('name is "Game Day - <teamName>"', () {
      expect(
        path1ToComplementTheme(snapFor()).name,
        'Game Day - Kansas City Royals',
      );
    });

    test('description is "<sport.displayName> team colors"', () {
      expect(
        path1ToComplementTheme(snapFor(sport: SportType.nhl)).description,
        'NHL team colors',
      );
    });

    test('themeColors masks ARGB to RGB (alpha stripped)', () {
      final t = path1ToComplementTheme(
        snapFor(primary: 0xFFAABBCC, secondary: 0xFF112233),
      );
      expect(t.themeColors, [0xAABBCC, 0x112233],
          reason: 'alpha byte must be masked off — ComplementTheme '
              'expects RGB-only ints');
    });

    test('recommendedEffectId mirrors snapshot.effectId', () {
      expect(
        path1ToComplementTheme(snapFor(effectId: 88)).recommendedEffectId,
        88,
      );
    });

    test('icon maps per sport', () {
      expect(path1ToComplementTheme(snapFor(sport: SportType.nfl)).icon,
          Icons.sports_football);
      expect(path1ToComplementTheme(snapFor(sport: SportType.mlb)).icon,
          Icons.sports_baseball);
      expect(path1ToComplementTheme(snapFor(sport: SportType.nhl)).icon,
          Icons.sports_hockey);
      expect(path1ToComplementTheme(snapFor(sport: SportType.nba)).icon,
          Icons.sports_basketball);
      expect(path1ToComplementTheme(snapFor(sport: SportType.mls)).icon,
          Icons.sports_soccer);
    });
  });
}
