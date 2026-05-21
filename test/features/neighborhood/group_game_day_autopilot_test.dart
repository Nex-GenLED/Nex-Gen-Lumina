// Tests for the GroupGameDayAutopilot model used by the
// /neighborhoods/{groupId}/game_day_autopilot/config document.
//
// Locks in toFirestore + fromFirestore semantics so the Phase 2 wiring
// (setGroupAutopilot writer + schedule card consumer) has a stable
// serialization contract.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/models/group_game_day_autopilot.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('GroupGameDayAutopilot.toFirestore', () {
    test('round-trips all required fields', () {
      final now = DateTime.utc(2026, 5, 21, 18, 30);
      final cfg = GroupGameDayAutopilot(
        teamId: 'mlb_royals',
        teamName: 'Kansas City Royals',
        sport: SportType.mlb,
        hostDesignId: 'design_42',
        hostUserId: 'host-uid',
        activeMemberIds: const ['u1', 'u2'],
        updatedAt: now,
      );

      final map = cfg.toFirestore();
      expect(map['teamId'], 'mlb_royals');
      expect(map['teamName'], 'Kansas City Royals');
      expect(map['sport'], 'mlb');
      expect(map['enabled'], isTrue);
      expect(map['hostDesignId'], 'design_42');
      expect(map['hostUserId'], 'host-uid');
      expect(map['activeMemberIds'], equals(['u1', 'u2']));
      expect(map['updatedAt'], isA<Timestamp>());
      // Compare Timestamps directly to sidestep DateTime UTC/local
      // conversion: Timestamp.toDate() returns local time, which doesn't
      // equal the UTC DateTime we constructed.
      expect(map['updatedAt'], equals(Timestamp.fromDate(now)));
    });

    test('defaults enabled=true when not overridden', () {
      final cfg = GroupGameDayAutopilot(
        teamId: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
        sport: SportType.nfl,
        hostDesignId: '',
        hostUserId: 'host-uid',
        updatedAt: DateTime.utc(2026, 5, 21),
      );
      expect(cfg.enabled, isTrue);
      expect(cfg.toFirestore()['enabled'], isTrue);
    });

    test('persists enabled=false when host disables', () {
      final cfg = GroupGameDayAutopilot(
        teamId: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
        sport: SportType.nfl,
        enabled: false,
        hostDesignId: '',
        hostUserId: 'host-uid',
        updatedAt: DateTime.utc(2026, 5, 21),
      );
      expect(cfg.toFirestore()['enabled'], isFalse);
    });

    test('persists empty activeMemberIds as empty list (not null)', () {
      final cfg = GroupGameDayAutopilot(
        teamId: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
        sport: SportType.nfl,
        hostDesignId: '',
        hostUserId: 'host-uid',
        updatedAt: DateTime.utc(2026, 5, 21),
      );
      final map = cfg.toFirestore();
      expect(map.containsKey('activeMemberIds'), isTrue);
      expect(map['activeMemberIds'], isA<List>());
      expect(map['activeMemberIds'], isEmpty);
    });
  });

  group('GroupGameDayAutopilot.fromFirestore', () {
    test('parses a fully-populated doc', () {
      final ts = Timestamp.fromDate(DateTime.utc(2026, 5, 21, 18, 30));
      final snap = _FakeDocumentSnapshot('config', {
        'teamId': 'mlb_royals',
        'teamName': 'Kansas City Royals',
        'sport': 'mlb',
        'enabled': true,
        'hostDesignId': 'design_42',
        'hostUserId': 'host-uid',
        'activeMemberIds': ['u1', 'u2'],
        'updatedAt': ts,
      });
      final cfg = GroupGameDayAutopilot.fromFirestore(snap);
      expect(cfg.teamId, 'mlb_royals');
      expect(cfg.teamName, 'Kansas City Royals');
      expect(cfg.sport, SportType.mlb);
      expect(cfg.enabled, isTrue);
      expect(cfg.hostDesignId, 'design_42');
      expect(cfg.hostUserId, 'host-uid');
      expect(cfg.activeMemberIds, equals(['u1', 'u2']));
      expect(cfg.updatedAt, ts.toDate());
    });

    test('defaults sport to nfl when field missing (legacy/partial doc)', () {
      final snap = _FakeDocumentSnapshot('config', {
        'teamId': 't',
        'teamName': 'T',
        'hostDesignId': '',
        'hostUserId': 'u',
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
      });
      final cfg = GroupGameDayAutopilot.fromFirestore(snap);
      expect(cfg.sport, SportType.nfl);
    });

    test('defaults enabled=true when field missing', () {
      final snap = _FakeDocumentSnapshot('config', {
        'teamId': 't',
        'teamName': 'T',
        'sport': 'nfl',
        'hostDesignId': '',
        'hostUserId': 'u',
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
      });
      final cfg = GroupGameDayAutopilot.fromFirestore(snap);
      expect(cfg.enabled, isTrue);
    });

    test('defaults activeMemberIds to [] when field missing', () {
      final snap = _FakeDocumentSnapshot('config', {
        'teamId': 't',
        'teamName': 'T',
        'sport': 'nfl',
        'hostDesignId': '',
        'hostUserId': 'u',
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
      });
      final cfg = GroupGameDayAutopilot.fromFirestore(snap);
      expect(cfg.activeMemberIds, isEmpty);
    });
  });

  group('GroupGameDayAutopilot.copyWith', () {
    final base = GroupGameDayAutopilot(
      teamId: 'mlb_royals',
      teamName: 'Kansas City Royals',
      sport: SportType.mlb,
      hostDesignId: 'd',
      hostUserId: 'host',
      activeMemberIds: const ['u1', 'u2'],
      updatedAt: DateTime.utc(2026, 5, 21),
    );

    test('preserves all fields when no overrides supplied', () {
      final copy = base.copyWith();
      expect(copy.teamId, base.teamId);
      expect(copy.teamName, base.teamName);
      expect(copy.sport, base.sport);
      expect(copy.enabled, base.enabled);
      expect(copy.hostDesignId, base.hostDesignId);
      expect(copy.hostUserId, base.hostUserId);
      expect(copy.activeMemberIds, base.activeMemberIds);
      expect(copy.updatedAt, base.updatedAt);
    });

    test('updates activeMemberIds when supplied', () {
      final copy = base.copyWith(activeMemberIds: ['u1', 'u2', 'u3']);
      expect(copy.activeMemberIds, equals(['u1', 'u2', 'u3']));
    });

    test('updates enabled flag', () {
      final copy = base.copyWith(enabled: false);
      expect(copy.enabled, isFalse);
      expect(copy.teamId, base.teamId);
    });

    test('updates updatedAt', () {
      final later = DateTime.utc(2026, 5, 22);
      final copy = base.copyWith(updatedAt: later);
      expect(copy.updatedAt, later);
    });
  });

  group('GroupGameDayAutopilot.optedInCount', () {
    test('returns 0 for empty activeMemberIds', () {
      final cfg = GroupGameDayAutopilot(
        teamId: 't',
        teamName: 'T',
        sport: SportType.nfl,
        hostDesignId: '',
        hostUserId: 'u',
        updatedAt: DateTime.utc(2026, 5, 21),
      );
      expect(cfg.optedInCount, 0);
    });

    test('returns the size of activeMemberIds', () {
      final cfg = GroupGameDayAutopilot(
        teamId: 't',
        teamName: 'T',
        sport: SportType.nfl,
        hostDesignId: '',
        hostUserId: 'u',
        activeMemberIds: const ['a', 'b', 'c'],
        updatedAt: DateTime.utc(2026, 5, 21),
      );
      expect(cfg.optedInCount, 3);
    });
  });

  group('GroupGameDayAutopilot.sportEmoji', () {
    test('returns football emoji for NFL', () {
      final cfg = _withSport(SportType.nfl);
      expect(cfg.sportEmoji, '\u{1F3C8}');
    });

    test('returns basketball emoji for NBA + WNBA + NCAA MB', () {
      expect(_withSport(SportType.nba).sportEmoji, '\u{1F3C0}');
      expect(_withSport(SportType.wnba).sportEmoji, '\u{1F3C0}');
      expect(_withSport(SportType.ncaaMB).sportEmoji, '\u{1F3C0}');
    });

    test('returns baseball emoji for MLB', () {
      expect(_withSport(SportType.mlb).sportEmoji, '\u{26BE}');
    });

    test('returns hockey emoji for NHL', () {
      expect(_withSport(SportType.nhl).sportEmoji, '\u{1F3D2}');
    });

    test('returns soccer emoji for MLS/NWSL/FIFA/UCL', () {
      expect(_withSport(SportType.mls).sportEmoji, '\u{26BD}');
      expect(_withSport(SportType.nwsl).sportEmoji, '\u{26BD}');
      expect(_withSport(SportType.fifa).sportEmoji, '\u{26BD}');
      expect(_withSport(SportType.championsLeague).sportEmoji, '\u{26BD}');
    });
  });
}

GroupGameDayAutopilot _withSport(SportType sport) => GroupGameDayAutopilot(
      teamId: 't',
      teamName: 'T',
      sport: sport,
      hostDesignId: '',
      hostUserId: 'u',
      updatedAt: DateTime.utc(2026, 5, 21),
    );

// DocumentSnapshot is sealed in cloud_firestore; implementing it for a
// scoped test fake is intentional. Only `id` and `data()` are exercised.
// ignore: subtype_of_sealed_class
class _FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocumentSnapshot(this._id, this._data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}
