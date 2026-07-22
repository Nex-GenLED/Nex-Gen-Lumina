// Tests for TeamRegistrationService (#63 Step 1).
//
// Three surfaces:
//   1. resolveFreeTextToKTeamSlug (static, no scaffold) — pure resolver.
//   2. addTeam/removeTeam against FakeFirebaseFirestore — Firestore writes.
//   3. onTeamsChanged callback fires on success.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/services/team_registration_service.dart';

void main() {
  group('resolveFreeTextToKTeamSlug', () {
    test('exact official team name resolves to its kTeamColors slug', () {
      expect(
        TeamRegistrationService.resolveFreeTextToKTeamSlug('Kansas City Chiefs'),
        equals('nfl_chiefs'),
      );
    });

    test('canonical alias (city) resolves to slug', () {
      // "kansas city" is a registered alias in TeamColorDatabase + has
      // high enough resolver confidence to pass the 0.8 threshold.
      expect(
        TeamRegistrationService.resolveFreeTextToKTeamSlug('kansas city chiefs'),
        equals('nfl_chiefs'),
      );
    });

    test('unresolvable free-text returns null', () {
      expect(
        TeamRegistrationService.resolveFreeTextToKTeamSlug('blargh fizzbuzz'),
        isNull,
      );
    });

    test('empty / whitespace input returns null without calling resolver', () {
      expect(TeamRegistrationService.resolveFreeTextToKTeamSlug(''), isNull);
      expect(TeamRegistrationService.resolveFreeTextToKTeamSlug('   '), isNull);
    });
  });

  group('addTeam', () {
    late FakeFirebaseFirestore firestore;
    late TeamRegistrationService svc;
    const uid = 'test-uid';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      svc = TeamRegistrationService(firestore: firestore);
    });

    test('creates subcollection doc with enabled:false + correct metadata',
        () async {
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('game_day_autopilot')
          .doc('nfl_chiefs')
          .get();

      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['team_slug'], 'nfl_chiefs');
      expect(data['team_name'], 'Kansas City Chiefs');
      expect(data['enabled'], isFalse);
      expect(data['espn_team_id'], isNotEmpty);
      expect(data['primary_color'], isA<int>());
      expect(data['secondary_color'], isA<int>());
    });

    test('appends team name to sports_teams and sports_team_priority',
        () async {
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');

      final profile = await firestore.collection('users').doc(uid).get();
      final data = profile.data()!;
      expect(data['sports_teams'], contains('Kansas City Chiefs'));
      expect(
          data['sports_team_priority'], contains('Kansas City Chiefs'));
    });

    test('throws ArgumentError on unknown slug', () async {
      expect(
        () => svc.addTeam(uid: uid, teamSlug: 'bogus_team'),
        throwsArgumentError,
      );
    });

    test('idempotent profile append (no duplicates on second add)', () async {
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');

      final profile = await firestore.collection('users').doc(uid).get();
      final teams = List<String>.from(profile.data()!['sports_teams'] as List);
      final priority =
          List<String>.from(profile.data()!['sports_team_priority'] as List);
      expect(teams.where((t) => t == 'Kansas City Chiefs').length, 1);
      expect(priority.where((t) => t == 'Kansas City Chiefs').length, 1);
    });

    test('preserves existing subcollection doc state on re-add', () async {
      // Seed an existing doc with enabled:true to verify addTeam doesn't
      // clobber it. This protects the "user already enabled the team,
      // installer hands off again" case.
      await firestore
          .collection('users')
          .doc(uid)
          .collection('game_day_autopilot')
          .doc('nfl_chiefs')
          .set({
        'team_slug': 'nfl_chiefs',
        'team_name': 'Kansas City Chiefs',
        'enabled': true,
        'saved_design_name': 'My Custom Design',
      });

      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('game_day_autopilot')
          .doc('nfl_chiefs')
          .get();
      expect(doc.data()!['enabled'], isTrue);
      expect(doc.data()!['saved_design_name'], 'My Custom Design');
    });

    test('fires onTeamsChanged callback on success', () async {
      var fired = 0;
      svc.onTeamsChanged = () => fired++;
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');
      expect(fired, 1);
    });
  });

  group('removeTeam', () {
    late FakeFirebaseFirestore firestore;
    late TeamRegistrationService svc;
    const uid = 'test-uid';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      svc = TeamRegistrationService(firestore: firestore);
    });

    test('strips team name from both profile arrays + deletes subcollection doc',
        () async {
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');
      await svc.addTeam(uid: uid, teamSlug: 'mlb_royals');

      await svc.removeTeam(
        uid: uid,
        teamSlug: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
      );

      final profile = await firestore.collection('users').doc(uid).get();
      final teams = List<String>.from(profile.data()!['sports_teams'] as List);
      final priority =
          List<String>.from(profile.data()!['sports_team_priority'] as List);
      expect(teams, isNot(contains('Kansas City Chiefs')));
      expect(priority, isNot(contains('Kansas City Chiefs')));
      // Sibling team untouched.
      expect(teams, contains('Kansas City Royals'));

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('game_day_autopilot')
          .doc('nfl_chiefs')
          .get();
      expect(doc.exists, isFalse);
    });

    test('case-insensitive teamName match on profile strip', () async {
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');

      await svc.removeTeam(
        uid: uid,
        teamSlug: 'nfl_chiefs',
        teamName: 'kansas city CHIEFS',
      );

      final profile = await firestore.collection('users').doc(uid).get();
      final teams = List<String>.from(profile.data()!['sports_teams'] as List);
      expect(teams, isEmpty);
    });

    test('inverse of addTeam — clean round-trip leaves profile empty',
        () async {
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');
      await svc.removeTeam(
        uid: uid,
        teamSlug: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
      );

      final profile = await firestore.collection('users').doc(uid).get();
      final teams = List<String>.from(
          (profile.data()?['sports_teams'] as List?) ?? const []);
      expect(teams, isEmpty);
    });

    test('throws StateError on empty uid', () async {
      expect(
        () => svc.removeTeam(
          uid: '',
          teamSlug: 'nfl_chiefs',
          teamName: 'Kansas City Chiefs',
        ),
        throwsStateError,
      );
    });

    test('fires onTeamsChanged callback on success', () async {
      await svc.addTeam(uid: uid, teamSlug: 'nfl_chiefs');
      var fired = 0;
      svc.onTeamsChanged = () => fired++;
      await svc.removeTeam(
        uid: uid,
        teamSlug: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
      );
      expect(fired, 1);
    });
  });
}
