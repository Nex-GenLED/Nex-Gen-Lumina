// Tests for [broadcastPath1ToGroup] — the Convergence-Phase-2 host
// broadcast orchestrator that wraps configureForTeam with a Path 1
// presence check.
//
// Verifies the three outcome branches (Needs-Path-1-Setup, Succeeded,
// Failed) without any Firebase / Riverpod dependency — the
// configureForTeam call is injected as a callback typedef.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/neighborhood/models/group_game_day_autopilot.dart';
import 'package:nexgen_command/features/neighborhood/services/path2_host_broadcast.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('broadcastPath1ToGroup', () {
    final now = DateTime.utc(2026, 5, 22, 12, 0, 0);

    GameDayAutopilotConfig configFor({
      String teamSlug = 'mlb_royals',
      String teamName = 'Kansas City Royals',
    }) {
      final created = DateTime.utc(2026, 5, 1);
      return GameDayAutopilotConfig(
        teamSlug: teamSlug,
        teamName: teamName,
        espnTeamId: '7',
        sport: SportType.mlb,
        primaryColorValue: 0xFF004687,
        secondaryColorValue: 0xFFBD9B60,
        effectId: 52,
        createdAt: created,
        updatedAt: created,
      );
    }

    GroupGameDayAutopilot stubAssembled({
      String teamId = 'mlb_royals',
      String teamName = 'Kansas City Royals',
      String hostUserId = 'host-uid-1',
      List<String> activeMemberIds = const ['host-uid-1', 'member-uid-2'],
    }) =>
        GroupGameDayAutopilot(
          teamId: teamId,
          teamName: teamName,
          sport: SportType.mlb,
          enabled: true,
          hostDesignId: 'mlb_royals:fx52',
          hostUserId: hostUserId,
          activeMemberIds: activeMemberIds,
          updatedAt: now,
        );

    test(
        'returns Path2HostBroadcastNeedsPath1Setup when path1Config is null '
        '(carrying the team slug for deep-linking)', () async {
      var configureCalls = 0;
      final result = await broadcastPath1ToGroup(
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async {
          configureCalls += 1;
          return stubAssembled();
        },
        groupId: 'group-abc',
        teamSlug: 'mlb_royals',
        path1Config: null,
      );

      expect(result, isA<Path2HostBroadcastNeedsPath1Setup>());
      expect(
        (result as Path2HostBroadcastNeedsPath1Setup).teamSlug,
        'mlb_royals',
        reason: 'team slug must be preserved so the UI can deep-link '
            'into the right team\'s Path 1 setup screen',
      );
      expect(configureCalls, 0,
          reason: 'configureForTeam must NOT be called when Path 1 is absent');
    });

    test(
        'returns Path2HostBroadcastSucceeded with assembled doc on success',
        () async {
      late String capturedGroupId;
      late GameDayAutopilotConfig capturedSource;
      DateTime? capturedNow;

      final assembled = stubAssembled();
      final result = await broadcastPath1ToGroup(
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async {
          capturedGroupId = groupId;
          capturedSource = sourceConfig;
          capturedNow = now;
          return assembled;
        },
        groupId: 'group-abc',
        teamSlug: 'mlb_royals',
        path1Config: configFor(),
        now: now,
      );

      expect(result, isA<Path2HostBroadcastSucceeded>());
      expect(
        (result as Path2HostBroadcastSucceeded).assembled,
        same(assembled),
        reason: 'the assembled doc the service returned must be passed back '
            'verbatim — caller surfaces activeMemberIds.length in the '
            'success snackbar',
      );
      expect(capturedGroupId, 'group-abc');
      expect(capturedSource.teamSlug, 'mlb_royals');
      expect(capturedNow, now,
          reason: '`now` must be forwarded so tests can fix the clock');
    });

    test(
        'forwards the path1Config verbatim — does NOT translate or '
        'derive a different config from the team slug', () async {
      late GameDayAutopilotConfig capturedSource;
      final input = configFor(teamSlug: 'nhl_avalanche');
      await broadcastPath1ToGroup(
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async {
          capturedSource = sourceConfig;
          return stubAssembled(teamId: 'nhl_avalanche');
        },
        groupId: 'group-abc',
        // teamSlug arg is intentionally different from path1Config.teamSlug
        // to verify the FUNCTION uses path1Config, not the slug arg, as the
        // source of truth for what to broadcast.
        teamSlug: 'mlb_royals',
        path1Config: input,
      );
      expect(capturedSource, same(input));
      expect(capturedSource.teamSlug, 'nhl_avalanche');
    });

    test(
        'returns Path2HostBroadcastFailed carrying the error when '
        'configureForTeam throws', () async {
      final boom = StateError('firestore write denied');
      final result = await broadcastPath1ToGroup(
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async =>
            throw boom,
        groupId: 'group-abc',
        teamSlug: 'mlb_royals',
        path1Config: configFor(),
      );

      expect(result, isA<Path2HostBroadcastFailed>());
      expect((result as Path2HostBroadcastFailed).error, same(boom));
    });

    test(
        'NeedsPath1Setup branch short-circuits even when groupId is empty — '
        'the Path 1 check runs first', () async {
      var configureCalls = 0;
      final result = await broadcastPath1ToGroup(
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async {
          configureCalls += 1;
          return stubAssembled();
        },
        groupId: '',
        teamSlug: 'mlb_royals',
        path1Config: null,
      );
      expect(result, isA<Path2HostBroadcastNeedsPath1Setup>());
      expect(configureCalls, 0);
    });
  });
}
