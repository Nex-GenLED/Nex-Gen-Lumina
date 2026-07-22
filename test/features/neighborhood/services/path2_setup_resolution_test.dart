// Tests for [resolvePath2GameDaySetup] — the Convergence-Phase-2b
// resolver that maps the 3-state [Path1SnapshotResolution] (Loading /
// Ready / Absent) into the Path 2 UI decision (Loading / Ready /
// NeedsPath1).
//
// 1b configure-twice regression sentinel: the Loading branch MUST NOT
// collapse to NeedsPath1. Tapping a configured team mid-load previously
// deep-linked to the Fan Zone builder, defeating Phase 2b. Lock that
// behavior in with a dedicated test.

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
        'Loading → Path2SetupLoading — MUST NOT collapse to NeedsPath1 '
        '(1b configure-twice regression sentinel)', () {
      final result = resolvePath2GameDaySetup(
        resolution: const Path1SnapshotLoading(),
      );
      expect(result, isA<Path2SetupLoading>());
      expect(result, isNot(isA<Path2SetupNeedsPath1>()),
          reason: 'collapsing Loading to NeedsPath1 deep-links the user to '
              'the Path 1 Fan Zone (a builder) mid-stream-load, defeating '
              'Phase 2b. The 1b regression on Pulla traced exactly here.');
    });

    test('Ready → Path2SetupReady carrying the snapshot', () {
      final snap = Path1GameDaySnapshot.fromConfig(configFor());
      final result = resolvePath2GameDaySetup(
        resolution: Path1SnapshotReady(snap),
      );
      expect(result, isA<Path2SetupReady>());
      expect((result as Path2SetupReady).snapshot, same(snap));
    });

    test(
        'Absent → Path2SetupNeedsPath1 carrying the team slug for deep-linking',
        () {
      final result = resolvePath2GameDaySetup(
        resolution: const Path1SnapshotAbsent('mlb_royals'),
      );
      expect(result, isA<Path2SetupNeedsPath1>());
      expect(
        (result as Path2SetupNeedsPath1).teamSlug,
        'mlb_royals',
        reason:
            'team slug carried through so the UI can deep-link into the '
            'correct team\'s Path 1 setup screen',
      );
    });

    test(
        'a disabled Path 1 config still resolves to Path2SetupReady — the '
        'UI shows the existing design and offers an enable + broadcast '
        'action, NOT a deep-link to setup-from-scratch', () {
      final disabled = Path1GameDaySnapshot.fromConfig(
        configFor(enabled: false),
      );
      final result = resolvePath2GameDaySetup(
        resolution: Path1SnapshotReady(disabled),
      );
      expect(result, isA<Path2SetupReady>());
      expect((result as Path2SetupReady).snapshot.autopilotEnabled, isFalse);
    });
  });
}
