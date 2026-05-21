// Tests for the participatingChannelIndices field on GameDayAutopilotConfig.
// Parallel to NeighborhoodMember's tests but using snake_case keys per this
// model's existing serialization convention.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('GameDayAutopilotConfig.participatingChannelIndices', () {
    test('toFirestore omits the key when participatingChannelIndices is null',
        () {
      final cfg = _baseConfig();
      expect(cfg.participatingChannelIndices, isNull);
      final map = cfg.toFirestore();
      expect(map.containsKey('participating_channel_indices'), isFalse);
    });

    test('toFirestore includes the key when participatingChannelIndices is set',
        () {
      final cfg = _baseConfig(participating: const [0, 1]);
      final map = cfg.toFirestore();
      expect(map['participating_channel_indices'], equals([0, 1]));
    });

    test('toFirestore includes an empty list explicitly (distinct from null)',
        () {
      final cfg = _baseConfig(participating: const []);
      final map = cfg.toFirestore();
      expect(map.containsKey('participating_channel_indices'), isTrue);
      expect(map['participating_channel_indices'], isEmpty);
    });

    test('fromFirestore returns null when the field is absent (legacy doc)',
        () {
      final map = _baseMap();
      // intentionally no participating_channel_indices
      final cfg = GameDayAutopilotConfig.fromFirestore(map);
      expect(cfg.participatingChannelIndices, isNull);
    });

    test('fromFirestore parses a present list of ints', () {
      final map = _baseMap()
        ..['participating_channel_indices'] = <dynamic>[0, 2];
      final cfg = GameDayAutopilotConfig.fromFirestore(map);
      expect(cfg.participatingChannelIndices, equals([0, 2]));
    });

    test('fromFirestore parses an empty list as []', () {
      final map = _baseMap()..['participating_channel_indices'] = <dynamic>[];
      final cfg = GameDayAutopilotConfig.fromFirestore(map);
      expect(cfg.participatingChannelIndices, isNotNull);
      expect(cfg.participatingChannelIndices, isEmpty);
    });

    test('copyWith sets a value when supplied', () {
      final base = _baseConfig();
      final updated = base.copyWith(participatingChannelIndices: [1]);
      expect(updated.participatingChannelIndices, equals([1]));
    });

    test('copyWith without arg preserves the existing non-null value', () {
      final base = _baseConfig(participating: const [0, 1]);
      final updated = base.copyWith(speed: 200);
      expect(updated.participatingChannelIndices, equals([0, 1]));
    });

    test(
        'copyWith with clearParticipatingChannelIndices: true sets it back to '
        'null', () {
      final base = _baseConfig(participating: const [0, 1]);
      final cleared = base.copyWith(clearParticipatingChannelIndices: true);
      expect(cleared.participatingChannelIndices, isNull);
    });
  });
}

GameDayAutopilotConfig _baseConfig({List<int>? participating}) {
  return GameDayAutopilotConfig(
    teamSlug: 'mlb_royals',
    teamName: 'Kansas City Royals',
    espnTeamId: '7',
    sport: SportType.mlb,
    primaryColorValue: 0xFF004687,
    secondaryColorValue: 0xFFBD9B60,
    createdAt: DateTime.utc(2026, 5, 21),
    updatedAt: DateTime.utc(2026, 5, 21),
    participatingChannelIndices: participating,
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
