// Tests for [lightItUpNow] — the Convergence-Phase-2b orchestrator
// for the unified Light-it-Up-Now button. Verifies the four outcome
// branches + the skip-broadcast-when-apply-fails guard.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/game_day/light_it_up_now.dart';
import 'package:nexgen_command/features/neighborhood/models/group_game_day_autopilot.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('lightItUpNow', () {
    final now = DateTime.utc(2026, 5, 22, 12, 0, 0);

    GameDayAutopilotConfig configFor() {
      final created = DateTime.utc(2026, 5, 1);
      return GameDayAutopilotConfig(
        teamSlug: 'mlb_royals',
        teamName: 'Kansas City Royals',
        espnTeamId: '7',
        sport: SportType.mlb,
        primaryColorValue: 0xFF004687,
        secondaryColorValue: 0xFFBD9B60,
        effectId: 52,
        speed: 200,
        intensity: 180,
        brightness: 220,
        createdAt: created,
        updatedAt: created,
      );
    }

    GroupGameDayAutopilot stubAssembled() => GroupGameDayAutopilot(
          teamId: 'mlb_royals',
          teamName: 'Kansas City Royals',
          sport: SportType.mlb,
          enabled: true,
          hostDesignId: 'mlb_royals:fx52',
          hostUserId: 'host-uid-1',
          activeMemberIds: const ['host-uid-1', 'member-uid-2'],
          updatedAt: now,
        );

    test(
        'broadcast=false: applies + returns LightItUpApplied — '
        'configureForTeam NOT called (DECISION 1 default OFF)', () async {
      var applyCalls = 0;
      var configureCalls = 0;
      final outcome = await lightItUpNow(
        applyPayloadWithLabel:
            (payload, {required labelHint}) async {
          applyCalls += 1;
          return true;
        },
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async {
          configureCalls += 1;
          return stubAssembled();
        },
        config: configFor(),
        broadcastToGroup: false,
        groupId: 'group-abc',
      );
      expect(outcome, isA<LightItUpApplied>());
      expect(applyCalls, 1);
      expect(configureCalls, 0,
          reason: 'broadcast must not fire when checkbox is OFF, '
              'even with a valid group context');
    });

    test(
        'broadcast=true + apply succeeds + configure succeeds: returns '
        'LightItUpAppliedAndBroadcasted with the assembled doc', () async {
      final assembled = stubAssembled();
      final outcome = await lightItUpNow(
        applyPayloadWithLabel:
            (payload, {required labelHint}) async => true,
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async =>
            assembled,
        config: configFor(),
        broadcastToGroup: true,
        groupId: 'group-abc',
        now: now,
      );
      expect(outcome, isA<LightItUpAppliedAndBroadcasted>());
      expect(
        (outcome as LightItUpAppliedAndBroadcasted).assembled,
        same(assembled),
      );
    });

    test(
        'apply fails → LightItUpApplyFailed, configureForTeam NOT called '
        '(skip-broadcast-when-apply-fails guard)', () async {
      var configureCalls = 0;
      final outcome = await lightItUpNow(
        applyPayloadWithLabel:
            (payload, {required labelHint}) async => false,
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async {
          configureCalls += 1;
          return stubAssembled();
        },
        config: configFor(),
        broadcastToGroup: true, // would broadcast if apply succeeded
        groupId: 'group-abc',
      );
      expect(outcome, isA<LightItUpApplyFailed>());
      expect(configureCalls, 0,
          reason: 'broadcasting an unlit local state would mislead neighbors');
    });

    test(
        'apply succeeds but broadcast throws → LightItUpAppliedButBroadcastFailed '
        'carrying the error', () async {
      final boom = StateError('firestore write denied');
      final outcome = await lightItUpNow(
        applyPayloadWithLabel:
            (payload, {required labelHint}) async => true,
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async =>
            throw boom,
        config: configFor(),
        broadcastToGroup: true,
        groupId: 'group-abc',
      );
      expect(outcome, isA<LightItUpAppliedButBroadcastFailed>());
      expect((outcome as LightItUpAppliedButBroadcastFailed).error, same(boom));
    });

    test(
        'broadcast=true but groupId=null → LightItUpApplied (broadcast '
        'silently skipped — defensive against no-active-group state)',
        () async {
      var configureCalls = 0;
      final outcome = await lightItUpNow(
        applyPayloadWithLabel:
            (payload, {required labelHint}) async => true,
        configureForTeam: ({
          required String groupId,
          required GameDayAutopilotConfig sourceConfig,
          DateTime? now,
        }) async {
          configureCalls += 1;
          return stubAssembled();
        },
        config: configFor(),
        broadcastToGroup: true,
        groupId: null,
      );
      expect(outcome, isA<LightItUpApplied>());
      expect(configureCalls, 0);
    });
  });
}
