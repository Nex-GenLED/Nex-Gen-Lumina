// TEAM CONSOLIDATION — the removal cascade, against a fake Firestore.
//
// This is the path that used to strip `sports_teams[]` and leave
// `game_day_autopilot/{slug}` firing: the customer removed a team from the
// screen they were looking at and Game Day kept running it. Live path, zero
// instances only because nobody had exercised it.
//
// It writes to TWO stores and, for a college name, iterates MULTIPLE slugs —
// which is why it is covered here rather than trusted.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/services/team_registration_service.dart';

const _uid = 'u1';

Future<void> _seed(
  FakeFirebaseFirestore db, {
  required List<String> teams,
  required List<String> slugs,
  List<String>? priority,
}) async {
  await db.collection('users').doc(_uid).set({
    'sports_teams': teams,
    'sports_team_priority': priority ?? teams,
  });
  for (final s in slugs) {
    await db
        .collection('users')
        .doc(_uid)
        .collection('game_day_autopilot')
        .doc(s)
        .set({'team_slug': s, 'enabled': true});
  }
}

Future<List<String>> _slugs(FakeFirebaseFirestore db) async {
  final snap =
      await db.collection('users').doc(_uid).collection('game_day_autopilot').get();
  return snap.docs.map((d) => d.id).toList()..sort();
}

Future<Map<String, dynamic>> _profile(FakeFirebaseFirestore db) async =>
    (await db.collection('users').doc(_uid).get()).data() ?? {};

void main() {
  late FakeFirebaseFirestore db;
  late TeamRegistrationService svc;

  setUp(() {
    db = FakeFirebaseFirestore();
    svc = TeamRegistrationService(firestore: db);
  });

  group('removeTeam — single-slug name', () {
    test('deletes exactly one config and the array entry', () async {
      await _seed(db,
          teams: ['Kansas City Chiefs', 'Kansas City Royals'],
          slugs: ['nfl_chiefs', 'mlb_royals']);

      await svc.removeTeam(
          uid: _uid, teamSlug: 'nfl_chiefs', teamName: 'Kansas City Chiefs');

      expect(await _slugs(db), equals(['mlb_royals']),
          reason: 'only the removed team\'s config should go');
      final p = await _profile(db);
      expect(p['sports_teams'], equals(['Kansas City Royals']));
      expect(p['sports_team_priority'], equals(['Kansas City Royals']),
          reason: 'priority must be stripped too, not just sports_teams');
    });

    test('leaves the OTHER team\'s config completely untouched', () async {
      await _seed(db,
          teams: ['Kansas City Chiefs', 'Kansas City Royals'],
          slugs: ['nfl_chiefs', 'mlb_royals']);
      await svc.removeTeam(
          uid: _uid, teamSlug: 'nfl_chiefs', teamName: 'Kansas City Chiefs');
      final kept = await db
          .collection('users')
          .doc(_uid)
          .collection('game_day_autopilot')
          .doc('mlb_royals')
          .get();
      expect(kept.exists, isTrue);
      expect(kept.get('enabled'), isTrue, reason: 'enabled state preserved');
    });
  });

  group('removeTeam — MULTI-SPORT name (the second hole)', () {
    // A college display name maps to two slugs. Removing by name must clear
    // BOTH, or the other sport's config keeps firing for a team the customer
    // just removed — reproducing the exact orphan this work exists to delete.
    test('removing both slugs clears both configs and the single array entry',
        () async {
      await _seed(db,
          teams: ['Missouri Tigers', 'Kansas City Chiefs'],
          slugs: ['ncaa_missouri', 'ncaamb_missouri', 'nfl_chiefs']);

      // What the Edit Profile handler does: iterate every slug sharing the name.
      for (final slug in ['ncaa_missouri', 'ncaamb_missouri']) {
        await svc.removeTeam(
            uid: _uid, teamSlug: slug, teamName: 'Missouri Tigers');
      }

      expect(await _slugs(db), equals(['nfl_chiefs']),
          reason: 'BOTH Missouri configs must be gone');
      expect((await _profile(db))['sports_teams'], equals(['Kansas City Chiefs']));
    });

    test('removing only ONE slug leaves an orphan — the bug this guards', () async {
      // Documents the failure mode explicitly: if the handler stopped at the
      // first match, the basketball config would survive.
      await _seed(db,
          teams: ['Missouri Tigers'],
          slugs: ['ncaa_missouri', 'ncaamb_missouri']);

      await svc.removeTeam(
          uid: _uid, teamSlug: 'ncaa_missouri', teamName: 'Missouri Tigers');

      expect(await _slugs(db), equals(['ncaamb_missouri']));
      expect((await _profile(db))['sports_teams'], isEmpty,
          reason: 'array cleared while a config survives — the orphan shape');
    });
  });

  group('removeTeamByNameOnly — unmappable legacy entry', () {
    test('strips both arrays and touches NO config', () async {
      // `sports_teams[]` was unvalidated free text; the fleet carries values
      // like this that match no catalogue team and never had a config.
      await _seed(db,
          teams: ['Kansas City Sporting Kansas City', 'Kansas City Chiefs'],
          slugs: ['nfl_chiefs']);

      await svc.removeTeamByNameOnly(
          uid: _uid, teamName: 'Kansas City Sporting Kansas City');

      expect(await _slugs(db), equals(['nfl_chiefs']),
          reason: 'it must not be able to delete a config');
      final p = await _profile(db);
      expect(p['sports_teams'], equals(['Kansas City Chiefs']));
      expect(p['sports_team_priority'], equals(['Kansas City Chiefs']));
    });

    test('rejects an empty uid rather than writing somewhere unexpected', () async {
      expect(
        () => svc.removeTeamByNameOnly(uid: '', teamName: 'x'),
        throwsA(isA<StateError>()),
      );
    });

    test('is a no-op for a name that is not present', () async {
      await _seed(db, teams: ['Kansas City Chiefs'], slugs: ['nfl_chiefs']);
      await svc.removeTeamByNameOnly(uid: _uid, teamName: 'Nobody FC');
      expect((await _profile(db))['sports_teams'], equals(['Kansas City Chiefs']));
      expect(await _slugs(db), equals(['nfl_chiefs']));
    });
  });

  group('addTeam still propagates to BOTH stores', () {
    test('creates the config disabled AND appends to both arrays', () async {
      await db.collection('users').doc(_uid).set({
        'sports_teams': <String>[],
        'sports_team_priority': <String>[],
      });

      await svc.addTeam(uid: _uid, teamSlug: 'nfl_chiefs');

      expect(await _slugs(db), equals(['nfl_chiefs']));
      final cfg = await db
          .collection('users')
          .doc(_uid)
          .collection('game_day_autopilot')
          .doc('nfl_chiefs')
          .get();
      expect(cfg.get('enabled'), isFalse,
          reason: 'adding a team must not auto-enable autopilot');
      final p = await _profile(db);
      expect(p['sports_teams'], contains('Kansas City Chiefs'));
      expect(p['sports_team_priority'], contains('Kansas City Chiefs'),
          reason: 'the priority gap — profile-added teams used to miss this');
    });

    test('re-adding preserves an existing ENABLED config', () async {
      await _seed(db, teams: ['Kansas City Chiefs'], slugs: ['nfl_chiefs']);
      await svc.addTeam(uid: _uid, teamSlug: 'nfl_chiefs');
      final cfg = await db
          .collection('users')
          .doc(_uid)
          .collection('game_day_autopilot')
          .doc('nfl_chiefs')
          .get();
      expect(cfg.get('enabled'), isTrue,
          reason: 'must not clobber the customer\'s enabled state back to false');
    });

    test('rejects an unknown slug', () async {
      expect(
        () => svc.addTeam(uid: _uid, teamSlug: 'nfl_not_a_team'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('round trip', () {
    test('add then remove leaves both stores exactly as they started', () async {
      await db.collection('users').doc(_uid).set({
        'sports_teams': <String>[],
        'sports_team_priority': <String>[],
      });
      await svc.addTeam(uid: _uid, teamSlug: 'mlb_royals');
      await svc.removeTeam(
          uid: _uid, teamSlug: 'mlb_royals', teamName: 'Kansas City Royals');

      expect(await _slugs(db), isEmpty);
      final p = await _profile(db);
      expect(p['sports_teams'], isEmpty);
      expect(p['sports_team_priority'], isEmpty);
    });
  });
}
