// Neighborhood Sync v1 — SyncFireStatus (the per-house read-back model).
//
// The banner must never claim more than the server's read-back shows. These
// tests pin the roll-up from targets to houses and the wording for each
// outcome, including the shapes a callable result actually arrives in
// (Map<Object?, Object?>).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/sync_fire_status.dart';

Map<String, dynamic> _t(
  String uid,
  String status, {
  String name = '',
  String cid = 'c',
  String reason = '',
  String error = '',
}) =>
    {
      'key': '${uid}__$cid',
      'uid': uid,
      'displayName': name,
      'controllerId': cid,
      'route': 'bridge',
      'status': status,
      'reason': reason,
      'error': error,
    };

SyncFireStatus _fire(List<Map<String, dynamic>> targets, {bool? settled}) =>
    SyncFireStatus.fromJson({
      'fireId': 'f1',
      'groupId': 'g1',
      'expiresAtMs': 1700000090000,
      'targets': targets,
      if (settled != null) 'summary': {'settled': settled},
    });

void main() {
  group('SyncFireStatus.fromJson', () {
    test('accepts the Map<Object?, Object?> shape a callable returns', () {
      final raw = <Object?, Object?>{
        'fireId': 'f1',
        'groupId': 'g1',
        'expiresAtMs': 1700000090000,
        'targets': <Object?>[
          <Object?, Object?>{
            'key': 'a__c',
            'uid': 'a',
            'displayName': 'Alice',
            'controllerId': 'c',
            'route': 'bridge',
            'status': 'completed',
            'reason': 'heartbeat_fresh',
            'error': '',
          },
        ],
        'summary': <Object?, Object?>{'settled': true},
      };
      final s = SyncFireStatus.fromJson(raw);
      expect(s.fireId, 'f1');
      expect(s.targets.single.displayName, 'Alice');
      expect(s.settled, isTrue);
      expect(s.expiresAt, DateTime.fromMillisecondsSinceEpoch(1700000090000));
    });

    test('settled falls back to "nothing waiting" when the summary is absent', () {
      expect(_fire([_t('a', 'pending')]).settled, isFalse);
      expect(_fire([_t('a', 'completed')]).settled, isTrue);
    });
  });

  group('house roll-up + headline', () {
    test('all confirmed', () {
      final s = _fire([
        _t('a', 'completed', name: 'Alice'),
        _t('b', 'completed', name: 'Bob'),
      ]);
      expect(s.houses, 2);
      expect(s.confirmedHouses, 2);
      expect(s.headline, '2 of 2 houses confirmed');
      expect(s.houseNotes, isEmpty);
    });

    test('still waiting on one house', () {
      final s = _fire([
        _t('a', 'completed', name: 'Alice'),
        _t('b', 'executing', name: 'Bob'),
      ]);
      expect(s.settled, isFalse);
      expect(s.headline, '1 of 2 houses confirmed · 1 waiting…');
    });

    test('a house that never responded is named, with the reason', () {
      final s = _fire([
        _t('a', 'completed', name: 'Alice'),
        _t('b', 'no_response', name: 'Bob', error: 'No response before expiry'),
      ], settled: true);
      expect(s.headline, '1 of 2 houses confirmed · 1 did not change');
      expect(s.houseNotes, ['Bob — no response (bridge offline?)']);
    });

    test('a house with no live bridge is explained, not counted as confirmed', () {
      final s = _fire([
        _t('a', 'completed', name: 'Alice'),
        _t('b', 'no_bridge', name: 'Bob', reason: 'heartbeat_stale_400s'),
      ], settled: true);
      expect(s.confirmedHouses, 1);
      expect(s.problemHouses, 1);
      expect(s.houseNotes,
          ['Bob — bridge offline — only changes if their app is open']);
    });

    test('bridge-reported controller failure is worded as unreachable', () {
      final s = _fire([
        _t('b', 'failed', name: 'Bob', error: 'ERROR: HTTP -1'),
      ], settled: true);
      expect(s.headline, '0 of 1 house confirmed · 1 did not change');
      expect(s.houseNotes, ['Bob — controller not reachable from their bridge']);
    });

    test('a two-controller house is confirmed only when BOTH controllers are', () {
      final s = _fire([
        _t('a', 'completed', name: 'Alice', cid: 'c1'),
        _t('a', 'failed', name: 'Alice', cid: 'c2', error: 'ERROR: HTTP -1'),
      ], settled: true);
      expect(s.houses, 1);
      expect(s.confirmedHouses, 0);
      expect(s.problemHouses, 1);
    });

    test('skipped (paused) members are not houses, but are listed', () {
      final s = _fire([
        _t('a', 'completed', name: 'Alice'),
        _t('b', 'skipped', name: 'Bob', reason: 'paused'),
      ], settled: true);
      expect(s.houses, 1);
      expect(s.skippedHouses, 1);
      expect(s.headline, '1 of 1 house confirmed');
      expect(s.houseNotes, ['Bob — paused']);
    });

    test('nothing to sync', () {
      expect(_fire([]).headline, 'No houses to sync');
      expect(
        _fire([_t('b', 'skipped', reason: 'paused')]).headline,
        'No houses to sync — 1 paused or opted out',
      );
    });
  });
}
