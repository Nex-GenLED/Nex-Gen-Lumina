// Tests for the untilDate field on GameDayAutopilotConfig — the optional end
// bound set by a Lumina recurring-sports rule ("...through Oct 2026").
// Mirrors the participatingChannelIndices test conventions (snake_case keys,
// additive/legacy-safe deserialization).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('GameDayAutopilotConfig.untilDate', () {
    test('toFirestore omits the key when untilDate is null', () {
      final cfg = _baseConfig();
      expect(cfg.untilDate, isNull);
      expect(cfg.toFirestore().containsKey('until_date'), isFalse);
    });

    // Use local DateTimes: the intent model parses date-only strings to local
    // midnight, and Firestore Timestamp round-trips through the local zone via
    // toDate(), so the stored/restored instant is local — matching production.
    test('toFirestore writes a Timestamp when untilDate is set', () {
      final cfg = _baseConfig(until: DateTime(2026, 10, 31));
      final map = cfg.toFirestore();
      expect(map['until_date'], isA<Timestamp>());
      expect((map['until_date'] as Timestamp).toDate(), DateTime(2026, 10, 31));
    });

    test('fromFirestore returns null when absent (legacy doc)', () {
      final cfg = GameDayAutopilotConfig.fromFirestore(_baseMap());
      expect(cfg.untilDate, isNull);
    });

    test('fromFirestore parses a present Timestamp', () {
      final map = _baseMap()
        ..['until_date'] = Timestamp.fromDate(DateTime(2026, 10, 31));
      final cfg = GameDayAutopilotConfig.fromFirestore(map);
      expect(cfg.untilDate, DateTime(2026, 10, 31));
    });

    test('round-trips through toFirestore/fromFirestore', () {
      final original = _baseConfig(until: DateTime(2026, 9, 30));
      final restored =
          GameDayAutopilotConfig.fromFirestore(original.toFirestore());
      expect(restored.untilDate, DateTime(2026, 9, 30));
    });

    test('copyWith sets a value when supplied', () {
      final updated = _baseConfig().copyWith(untilDate: DateTime(2026, 10, 31));
      expect(updated.untilDate, DateTime(2026, 10, 31));
    });

    test('copyWith without arg preserves the existing bound (null = no change)',
        () {
      final base = _baseConfig(until: DateTime(2026, 10, 31));
      final updated = base.copyWith(enabled: true);
      expect(updated.untilDate, DateTime(2026, 10, 31));
    });

    test('copyWith with clearUntilDate: true sets it back to null', () {
      final base = _baseConfig(until: DateTime(2026, 10, 31));
      expect(base.copyWith(clearUntilDate: true).untilDate, isNull);
    });
  });
}

GameDayAutopilotConfig _baseConfig({DateTime? until}) {
  return GameDayAutopilotConfig(
    teamSlug: 'mlb_royals',
    teamName: 'Kansas City Royals',
    espnTeamId: '7',
    sport: SportType.mlb,
    primaryColorValue: 0xFF004687,
    secondaryColorValue: 0xFFBD9B60,
    untilDate: until,
    createdAt: DateTime.utc(2026, 5, 21),
    updatedAt: DateTime.utc(2026, 5, 21),
  );
}

Map<String, dynamic> _baseMap() => <String, dynamic>{
      'team_slug': 'mlb_royals',
      'team_name': 'Kansas City Royals',
      'espn_team_id': '7',
      'sport': 'mlb',
      'primary_color': 0xFF004687,
      'secondary_color': 0xFFBD9B60,
      'enabled': false,
      'design_mode': 'fallback',
      'effect_id': 52,
      'speed': 160,
      'intensity': 128,
      'brightness': 200,
      'score_celebration_enabled': true,
      'skip_day_games': true,
      'design_variety': 'rotating',
      'motion_style': 0.5,
      'created_at': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
      'updated_at': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
    };
