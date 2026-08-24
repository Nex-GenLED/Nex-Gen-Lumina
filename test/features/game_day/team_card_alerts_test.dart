// Alerts folded onto the Game Day team card.
//
// The retired Sports Alerts screen owned two things the card did not: the
// alerts on/off, and the SENSITIVITY. On/off maps onto Live Scoring (a second
// arming switch would be exactly the redundancy this consolidation removes);
// sensitivity moves onto the card as its own row, backed by the
// `game_day_autopilot` doc rather than the device-local prefs store
// (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.1-4.3).
//
// SCOPE. GameDayScreen has no widget-test harness in this repo — nothing in
// test/ pumps it — and `setAlertSensitivity` writes through a hardcoded
// FirebaseFirestore.instance, so it cannot be driven against a fake. These
// therefore pin the DOC CONTRACT the row reads and writes, and the arming
// behavior a migrated card must have. The row itself renders straight off
// `config.alertSensitivity`.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/autopilot/unified_monitoring.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

GameDayAutopilotConfig _cfg({
  bool enabled = false,
  bool liveScoring = true,
  AlertSensitivity sensitivity = AlertSensitivity.majorOnly,
}) =>
    GameDayAutopilotConfig(
      teamSlug: 'nfl_chiefs',
      teamName: 'Kansas City Chiefs',
      espnTeamId: '12',
      sport: SportType.nfl,
      primaryColorValue: 0xFFE31837,
      secondaryColorValue: 0xFFFFB81C,
      enabled: enabled,
      liveScoringEnabled: liveScoring,
      scoreCelebrationEnabled: liveScoring,
      alertSensitivity: sensitivity,
      createdAt: DateTime.utc(2026, 8, 24),
      updatedAt: DateTime.utc(2026, 8, 24),
    );

void main() {
  group('alerts toggle state round-trips through the Game Day doc', () {
    // The exact field `setAlertSensitivity` writes and the row reads back.
    for (final s in AlertSensitivity.values) {
      test('${s.name} survives toFirestore → fromFirestore', () {
        final round = GameDayAutopilotConfig.fromFirestore(
          _cfg(sensitivity: s).toFirestore(),
        );
        expect(round.alertSensitivity, s);
      });
    }

    test('sensitivity is written under the key the notifier updates', () {
      expect(_cfg(sensitivity: AlertSensitivity.clutchOnly).toFirestore(),
          containsPair('alert_sensitivity', 'clutchOnly'));
    });

    // A doc written before alerts moved onto the card has no sensitivity field.
    test('a doc with no sensitivity degrades to a default, it does not throw',
        () {
      final raw = _cfg().toFirestore()..remove('alert_sensitivity');
      expect(GameDayAutopilotConfig.fromFirestore(raw).alertSensitivity,
          isA<AlertSensitivity>());
    });

    test('an unknown sensitivity string degrades rather than throwing', () {
      final raw = _cfg().toFirestore()
        ..['alert_sensitivity'] = 'not_a_sensitivity';
      expect(GameDayAutopilotConfig.fromFirestore(raw).alertSensitivity,
          isA<AlertSensitivity>());
    });

    test('the live-scoring pair round-trips as the row shows it', () {
      final round =
          GameDayAutopilotConfig.fromFirestore(_cfg(liveScoring: false).toFirestore());
      expect(round.liveScoringEnabled, isFalse);
      expect(round.scoreCelebrationEnabled, isFalse);
    });
  });

  // THE MIGRATED CARD. Step F's shape: alerts on, autopilot off. It must be
  // monitored (so the user keeps the celebrations they had) while staying
  // invisible to the server planner (so nothing lights up unasked).
  group('alerts on + autopilot off', () {
    test('is monitored — the user keeps score monitoring', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [
          BackgroundGameDayAutopilotConfig.fromConfig(
              _cfg(enabled: false, liveScoring: true))
        ],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored.map((c) => c.teamSlug), ['nfl_chiefs']);
    });

    test('carries its sensitivity into the monitoring config', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [
          BackgroundGameDayAutopilotConfig.fromConfig(
              _cfg(sensitivity: AlertSensitivity.clutchOnly))
        ],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored.single.sensitivity, AlertSensitivity.clutchOnly);
    });

    // `enabled` is the field the SERVER planner queries
    // (planGameDayFires.ts:342). Monitoring must not imply a scheduled show.
    test('stays invisible to the planner — no lighting changes', () {
      expect(_cfg(enabled: false, liveScoring: true).toFirestore()['enabled'],
          isFalse);
    });

    test('turning alerts off genuinely stops monitoring', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [
          BackgroundGameDayAutopilotConfig.fromConfig(
              _cfg(enabled: false, liveScoring: false))
        ],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored, isEmpty);
    });
  });

  group('the migrated-orphan card has everything it needs to render', () {
    test('name, colors and sport are real, not slug placeholders', () {
      final c = GameDayAutopilotConfig.fromFirestore(_cfg().toFirestore());
      expect(c.teamName, 'Kansas City Chiefs');
      expect(c.teamSlug, 'nfl_chiefs');
      expect(c.primaryColorValue, 0xFFE31837);
      expect(c.secondaryColorValue, 0xFFFFB81C);
      expect(c.sport, SportType.nfl);
    });

    test('the card shows alerts ON and autopilot OFF', () {
      final c = GameDayAutopilotConfig.fromFirestore(
          _cfg(enabled: false, liveScoring: true).toFirestore());
      expect(c.enabled, isFalse, reason: 'Autopilot row reads this');
      expect(c.scoreCelebrationEnabled, isTrue,
          reason: 'Live Scoring row reads this');
    });

    test('created_at/updated_at survive as Timestamps', () {
      final raw = _cfg().toFirestore();
      expect(raw['created_at'], isA<Timestamp>());
      expect(raw['updated_at'], isA<Timestamp>());
    });
  });
}
