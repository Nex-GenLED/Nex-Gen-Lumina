// Tests for [resolvePath2GameDaySetup] — the Convergence-Phase-2
// resolver that decides whether the Path 2 (Sync→Complement→Game Day)
// setup screen renders against the user's Path 1 snapshot or deep-
// links into Path 1 setup.
//
// Pure-function: feeds in pre-built [Path1GameDaySnapshot] values + a
// team slug, asserts on the sealed result branches.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_game_day_snapshot.dart';
import 'package:nexgen_command/features/neighborhood/services/path2_setup_resolution.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('resolvePath2GameDaySetup', () {
    GameDayAutopilotConfig configFor({
      String teamSlug = 'mlb_royals',
      bool enabled = true,
    }) {
      final created = DateTime.utc(2026, 5, 1);
      return GameDayAutopilotConfig(
        teamSlug: teamSlug,
        teamName: 'Kansas City Royals',
        espnTeamId: '7',
        sport: SportType.mlb,
        primaryColorValue: 0xFF004687,
        secondaryColorValue: 0xFFBD9B60,
        effectId: 52,
        enabled: enabled,
        createdAt: created,
        updatedAt: created,
      );
    }

    test(
        'returns Path2SetupNeedsPath1 carrying the team slug when '
        'snapshot is null (no Path 1 config exists)', () {
      final result = resolvePath2GameDaySetup(
        teamSlug: 'mlb_royals',
        snapshot: null,
      );

      expect(result, isA<Path2SetupNeedsPath1>());
      expect(
        (result as Path2SetupNeedsPath1).teamSlug,
        'mlb_royals',
        reason: 'team slug carried through so the UI can deep-link into '
            'the correct team\'s Path 1 setup screen',
      );
    });

    test('returns Path2SetupReady carrying the snapshot when present', () {
      final snap = Path1GameDaySnapshot.fromConfig(configFor());
      final result = resolvePath2GameDaySetup(
        teamSlug: 'mlb_royals',
        snapshot: snap,
      );

      expect(result, isA<Path2SetupReady>());
      expect((result as Path2SetupReady).snapshot, same(snap));
    });

    test(
        'a disabled Path 1 config still resolves to Path2SetupReady — the '
        'UI shows the existing design and offers an enable + broadcast '
        'action, NOT a deep-link to setup-from-scratch', () {
      final disabled = Path1GameDaySnapshot.fromConfig(
        configFor(enabled: false),
      );
      final result = resolvePath2GameDaySetup(
        teamSlug: 'mlb_royals',
        snapshot: disabled,
      );

      expect(result, isA<Path2SetupReady>());
      expect((result as Path2SetupReady).snapshot.autopilotEnabled, isFalse);
    });
  });
}
