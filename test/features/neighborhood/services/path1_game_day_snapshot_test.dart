// Tests for [Path1GameDaySnapshot] — the Path 2 view-model that reads
// a host's canonical Path 1 [GameDayAutopilotConfig].
//
// Convergence-Phase-1B: this snapshot is the read-side foundation that
// the Sync→Complement→Game Day flow will use to display an already-
// configured Path 1 team. Pure-function tests; no Firestore.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_game_day_snapshot.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('Path1GameDaySnapshot.fromConfig', () {
    GameDayAutopilotConfig configFor({
      String teamSlug = 'mlb_royals',
      String teamName = 'Kansas City Royals',
      String espnTeamId = '7',
      SportType sport = SportType.mlb,
      int effectId = 52,
      int speed = 160,
      int intensity = 128,
      int brightness = 200,
      bool enabled = true,
      bool scoreCelebrationEnabled = true,
      String? savedDesignName,
      int primary = 0xFF004687,
      int secondary = 0xFFBD9B60,
    }) {
      final t = DateTime.utc(2026, 5, 1);
      return GameDayAutopilotConfig(
        teamSlug: teamSlug,
        teamName: teamName,
        espnTeamId: espnTeamId,
        sport: sport,
        primaryColorValue: primary,
        secondaryColorValue: secondary,
        enabled: enabled,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
        scoreCelebrationEnabled: scoreCelebrationEnabled,
        savedDesignName: savedDesignName,
        createdAt: t,
        updatedAt: t,
      );
    }

    test('copies team identity fields verbatim', () {
      final snap = Path1GameDaySnapshot.fromConfig(configFor());
      expect(snap.teamSlug, 'mlb_royals');
      expect(snap.teamName, 'Kansas City Royals');
      expect(snap.espnTeamId, '7');
      expect(snap.sport, SportType.mlb);
    });

    test('copies broadcast-shaped effect parameters', () {
      final snap = Path1GameDaySnapshot.fromConfig(
        configFor(effectId: 28, speed: 100, intensity: 220, brightness: 180),
      );
      expect(snap.effectId, 28);
      expect(snap.speed, 100);
      expect(snap.intensity, 220);
      expect(snap.brightness, 180);
    });

    test('copies color values + exposes Color getters', () {
      final snap = Path1GameDaySnapshot.fromConfig(
        configFor(primary: 0xFF0033CC, secondary: 0xFFFFCC00),
      );
      expect(snap.primaryColorValue, 0xFF0033CC);
      expect(snap.secondaryColorValue, 0xFFFFCC00);
      // ignore: deprecated_member_use
      expect(snap.primaryColor.value, 0xFF0033CC);
      // ignore: deprecated_member_use
      expect(snap.secondaryColor.value, 0xFFFFCC00);
    });

    test('mirrors scoreCelebrationEnabled flag', () {
      final on = Path1GameDaySnapshot.fromConfig(
        configFor(scoreCelebrationEnabled: true),
      );
      final off = Path1GameDaySnapshot.fromConfig(
        configFor(scoreCelebrationEnabled: false),
      );
      expect(on.scoreCelebrationEnabled, isTrue);
      expect(off.scoreCelebrationEnabled, isFalse);
    });

    test(
        'designLabel matches the Path 1 config.designLabel resolution '
        '(savedDesignName wins)', () {
      final snap = Path1GameDaySnapshot.fromConfig(
        configFor(savedDesignName: 'Royals Heritage', effectId: 28),
      );
      expect(snap.designLabel, 'Royals Heritage');
    });

    test(
        'designLabel falls back to effect-derived "<team> <Effect>" when '
        'no saved name and effectId != 0', () {
      final snap = Path1GameDaySnapshot.fromConfig(
        configFor(effectId: 28),
      );
      // _effectShortName(28) is "Chase" per game_day_autopilot_config.dart.
      expect(snap.designLabel, 'Kansas City Royals Chase');
    });

    test('autopilotEnabled reflects the Path 1 enabled flag', () {
      final enabled = Path1GameDaySnapshot.fromConfig(
        configFor(enabled: true),
      );
      final disabled = Path1GameDaySnapshot.fromConfig(
        configFor(enabled: false),
      );
      expect(enabled.autopilotEnabled, isTrue);
      expect(disabled.autopilotEnabled, isFalse);
    });
  });

  group('Path1GameDaySnapshot.fromConfigOrNull', () {
    test('returns null when the Path 1 config is null (team not set up)', () {
      expect(Path1GameDaySnapshot.fromConfigOrNull(null), isNull);
    });

    test('returns a non-null snapshot when a disabled config exists', () {
      final config = GameDayAutopilotConfig(
        teamSlug: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
        espnTeamId: '12',
        sport: SportType.nfl,
        primaryColorValue: 0xFFE31837,
        secondaryColorValue: 0xFFFFB81C,
        enabled: false,
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final snap = Path1GameDaySnapshot.fromConfigOrNull(config);
      expect(snap, isNotNull);
      expect(snap!.autopilotEnabled, isFalse);
      expect(snap.teamSlug, 'nfl_chiefs');
    });
  });
}
