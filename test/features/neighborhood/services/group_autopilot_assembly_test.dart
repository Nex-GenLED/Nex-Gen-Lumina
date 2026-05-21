// Tests for [buildGroupAutopilotFromPath1] — the pure builder that
// converts a host's Path 1 [GameDayAutopilotConfig] into the group-
// shaped [GroupGameDayAutopilot] document.
//
// Convergence-Phase-1B: this builder is the missing piece that lets
// [GroupAutopilotService.configureForTeam] wire setGroupAutopilot up to
// the host's per-team Path 1 config. Pure-function on purpose so it can
// be exercised without Firestore.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/neighborhood/services/group_autopilot_assembly.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('buildGroupAutopilotFromPath1', () {
    final now = DateTime.utc(2026, 5, 21, 12, 0, 0);

    GameDayAutopilotConfig configFor({
      String teamSlug = 'mlb_royals',
      String teamName = 'Kansas City Royals',
      String espnTeamId = '7',
      SportType sport = SportType.mlb,
      int effectId = 52,
      String? savedDesignName,
    }) {
      final created = DateTime.utc(2026, 5, 1);
      return GameDayAutopilotConfig(
        teamSlug: teamSlug,
        teamName: teamName,
        espnTeamId: espnTeamId,
        sport: sport,
        primaryColorValue: 0xFF004687,
        secondaryColorValue: 0xFFBD9B60,
        effectId: effectId,
        savedDesignName: savedDesignName,
        createdAt: created,
        updatedAt: created,
      );
    }

    test('copies teamId/teamName/sport from the Path 1 config', () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(),
        hostUserId: 'host-uid-1',
        now: now,
      );
      expect(group.teamId, 'mlb_royals');
      expect(group.teamName, 'Kansas City Royals');
      expect(group.sport, SportType.mlb);
    });

    test('sets hostUserId from arg and updatedAt from now', () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(),
        hostUserId: 'host-uid-1',
        now: now,
      );
      expect(group.hostUserId, 'host-uid-1');
      expect(group.updatedAt, now);
    });

    test('defaults enabled=true and activeMemberIds=[] when not provided',
        () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(),
        hostUserId: 'host-uid-1',
        now: now,
      );
      expect(group.enabled, isTrue);
      expect(group.activeMemberIds, isEmpty);
    });

    test('respects explicit enabled=false', () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(),
        hostUserId: 'host-uid-1',
        now: now,
        enabled: false,
      );
      expect(group.enabled, isFalse);
    });

    test(
        'preserves initialActiveMemberIds list as given, '
        'without de-duping or sorting', () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(),
        hostUserId: 'host-uid-1',
        now: now,
        initialActiveMemberIds: const ['b', 'a', 'c'],
      );
      expect(group.activeMemberIds, ['b', 'a', 'c']);
    });

    test(
        'hostDesignId uses savedDesignName when set '
        '(matches designLabel resolution order)', () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(savedDesignName: 'Royals Heritage'),
        hostUserId: 'host-uid-1',
        now: now,
      );
      expect(group.hostDesignId, 'Royals Heritage');
    });

    test(
        'hostDesignId falls back to deterministic {teamSlug}:fx{effectId} '
        'when no saved design name exists', () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(effectId: 28),
        hostUserId: 'host-uid-1',
        now: now,
      );
      expect(group.hostDesignId, 'mlb_royals:fx28');
    });

    test(
        'hostDesignId falls back to the deterministic id when saved name '
        'is empty (treats empty string the same as null)', () {
      final group = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(savedDesignName: '', effectId: 0),
        hostUserId: 'host-uid-1',
        now: now,
      );
      expect(group.hostDesignId, 'mlb_royals:fx0');
    });

    test(
        'same Path 1 effect choice round-trips to the same fallback id '
        '(deterministic, not random)', () {
      final a = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(effectId: 12),
        hostUserId: 'host-uid-1',
        now: now,
      );
      final b = buildGroupAutopilotFromPath1(
        sourceConfig: configFor(effectId: 12),
        hostUserId: 'host-uid-2',
        now: now.add(const Duration(minutes: 5)),
      );
      expect(a.hostDesignId, b.hostDesignId);
    });

    test('rejects an empty hostUserId', () {
      expect(
        () => buildGroupAutopilotFromPath1(
          sourceConfig: configFor(),
          hostUserId: '',
          now: now,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
