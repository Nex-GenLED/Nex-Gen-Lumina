// +114 step C — the reader for users/{uid}.gameday_server.
//
// The parser may only err toward NOT SERVED: a wrong "not served" costs a
// duplicate fire; a wrong "served" silences the phone while nothing fires.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';

final DateTime _now = DateTime(2026, 10, 11, 12, 0);
Timestamp _ts(DateTime d) => Timestamp.fromDate(d);

/// What the planner writes for a served, pre-flight-ok account.
Map<String, Object?> _served({
  DateTime? checkedAt,
  List<Object?> teams = const ['kansas_city_chiefs'],
  Object? nextFire,
  Object? lastFire,
  Object? preflight,
}) =>
    {
      'served': true,
      'teams': teams,
      'checked_at': _ts(checkedAt ?? _now.subtract(const Duration(minutes: 4))),
      'preflight': preflight ??
          {
            'ok': true,
            'reasons': <String>[],
            'info': <String>[],
            'mode': 'enforce',
            'at': _ts(_now),
          },
      'next_fire': nextFire,
      'last_fire': lastFire,
    };

void main() {
  group('fail paths — every one reads NOT SERVED', () {
    for (final (label, raw) in <(String, Object?)>[
      ('absent', null),
      ('a string', 'served'),
      ('a list', [true]),
      ('served:false', {'served': false, 'teams': ['x'], 'checked_at': _ts(_now)}),
      ('served as a string', {'served': 'true', 'checked_at': _ts(_now)}),
      ('served with no heartbeat', {'served': true, 'teams': ['x']}),
      ('heartbeat not a Timestamp',
          {'served': true, 'teams': ['x'], 'checked_at': '2026-10-11'}),
    ]) {
      test(label, () {
        final s = GameDayServerStatus.fromUserDoc(raw);
        expect(s.servedAt(_now), isFalse);
        expect(s.servedTeamsAt(_now), isEmpty);
      });
    }
  });

  group('staleness (D1) — a dead planner degrades to the phone, never dark', () {
    test('29 min old → served', () {
      final s = GameDayServerStatus.fromUserDoc(
          _served(checkedAt: _now.subtract(const Duration(minutes: 29))));
      expect(s.servedAt(_now), isTrue);
    });

    test('exactly 30 min old → still served (the edge is inclusive)', () {
      final s = GameDayServerStatus.fromUserDoc(
          _served(checkedAt: _now.subtract(kServerStatusStaleAfter)));
      expect(s.servedAt(_now), isTrue);
    });

    test('31 min old → NOT served, and reported stale', () {
      final s = GameDayServerStatus.fromUserDoc(
          _served(checkedAt: _now.subtract(const Duration(minutes: 31))));
      expect(s.servedAt(_now), isFalse);
      expect(s.staleAt(_now), isTrue);
      expect(s.servesTeamAt('kansas_city_chiefs', _now), isFalse);
    });

    test('the SAME parsed value ages out as time passes (no new snapshot)', () {
      final s = GameDayServerStatus.fromUserDoc(_served());
      expect(s.servedAt(_now), isTrue);
      expect(s.servedAt(_now.add(const Duration(minutes: 40))), isFalse);
    });
  });

  group('per team (D2)', () {
    test('only listed teams are served', () {
      final s = GameDayServerStatus.fromUserDoc(_served());
      expect(s.servesTeamAt('kansas_city_chiefs', _now), isTrue);
      expect(s.servesTeamAt('kansas_city_royals', _now), isFalse);
    });

    test('non-string and empty team entries are dropped', () {
      final s = GameDayServerStatus.fromUserDoc(
          _served(teams: ['kansas_city_chiefs', 7, '', null]));
      expect(s.teams, ['kansas_city_chiefs']);
    });

    test('teams non-list → no team is served', () {
      final raw = _served()..['teams'] = 'kansas_city_chiefs';
      expect(GameDayServerStatus.fromUserDoc(raw).servedTeamsAt(_now), isEmpty);
    });
  });

  group('preflight, next_fire, last_fire', () {
    test('preflight present ⇔ allowlisted; observe mode is read', () {
      expect(GameDayServerStatus.fromUserDoc(_served()).allowlisted, isTrue);
      final notListed = _served()..['preflight'] = null;
      expect(GameDayServerStatus.fromUserDoc(notListed).allowlisted, isFalse);
      final obs = GameDayServerStatus.fromUserDoc(_served(preflight: {
        'ok': false,
        'reasons': ['preflight_bridge_stale'],
        'info': [],
        'mode': 'observe',
      }));
      expect(obs.preflight!.observeOnly, isTrue);
      expect(obs.preflight!.reasons, ['preflight_bridge_stale']);
    });

    test('next_fire parsed; malformed next_fire dropped, status kept', () {
      final s = GameDayServerStatus.fromUserDoc(_served(nextFire: {
        'event_id': 'gd_kansas_city_chiefs_401772',
        'team_slug': 'kansas_city_chiefs',
        'seq': 'start',
        'fire_at': _ts(DateTime(2026, 10, 11, 14, 55)),
      }));
      expect(s.nextFire!.seq, 'start');
      expect(s.nextFire!.fireAt, DateTime(2026, 10, 11, 14, 55));
      final bad = GameDayServerStatus.fromUserDoc(
          _served(nextFire: {'event_id': 'x', 'seq': 'start'}));
      expect(bad.nextFire, isNull);
      expect(bad.servedAt(_now), isTrue);
    });

    test('last_fire parsed with latency', () {
      final s = GameDayServerStatus.fromUserDoc(_served(lastFire: {
        'event_id': 'gd_kansas_city_chiefs_401772',
        'seq': 'start',
        'state': 'completed',
        'completed_at': _ts(DateTime(2026, 10, 11, 14, 55, 2)),
        'latency_ms': 2100,
      }));
      expect(s.lastFire!.completed, isTrue);
      expect(s.lastFire!.latencyMs, 2100);
    });
  });

  group('pre-flight copy', () {
    test('every server reason has words; gated is the Blocked state', () {
      for (final r in [
        PreflightReason.noBridge,
        PreflightReason.bridgeStale,
        PreflightReason.noParticipation,
        PreflightReason.ladderUnknown,
        PreflightReason.ladderBad,
        PreflightReason.controllerUnreachable,
        'preflight_something_new',
      ]) {
        expect(preflightReasonCopy(r), isNotEmpty, reason: r);
      }
      expect(preflightReasonCopy(PreflightReason.gated), isNull);
    });
  });

  group('serverLiveReasonAt — the ladder repair\'s server signal', () {
    GameDayServerStatus withFires({Object? next, Object? last}) =>
        GameDayServerStatus.fromUserDoc(_served(nextFire: next, lastFire: last));

    test('nothing scheduled → null', () {
      expect(serverLiveReasonAt(withFires(), _now), isNull);
    });

    test('a start completed 2 h ago with no end yet → live', () {
      final s = withFires(last: {
        'event_id': 'e',
        'seq': 'start',
        'state': 'completed',
        'completed_at': _ts(_now.subtract(const Duration(hours: 2))),
      });
      expect(serverLiveReasonAt(s, _now), isNotNull);
    });

    test('an end pending → live', () {
      final s = withFires(next: {
        'event_id': 'e',
        'seq': 'end',
        'fire_at': _ts(_now.add(const Duration(hours: 1))),
      });
      expect(serverLiveReasonAt(s, _now), isNotNull);
    });

    test('a start 9 min away → live; 2 h away → null', () {
      Map<String, Object?> start(Duration d) =>
          {'event_id': 'e', 'seq': 'start', 'fire_at': _ts(_now.add(d))};
      expect(
          serverLiveReasonAt(
              withFires(next: start(const Duration(minutes: 9))), _now),
          isNotNull);
      expect(
          serverLiveReasonAt(
              withFires(next: start(const Duration(hours: 2))), _now),
          isNull);
    });

    test('read even when the heartbeat is stale (jobs may still fire)', () {
      final raw = _served(
        checkedAt: _now.subtract(const Duration(hours: 2)),
        nextFire: {
          'event_id': 'e',
          'seq': 'end',
          'fire_at': _ts(_now.add(const Duration(minutes: 30))),
        },
      );
      expect(
          serverLiveReasonAt(GameDayServerStatus.fromUserDoc(raw), _now),
          isNotNull);
    });
  });
}
