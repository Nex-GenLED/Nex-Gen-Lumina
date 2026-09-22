// Pins the signal that makes drag-to-reorder actually take effect.
//
// THE BUG. `teamRegistrationServiceProvider` built the service with no
// `onTeamsChanged` callback, so `setTeamPriority` wrote two Firestore fields
// and nothing re-ran the populate. Since the hierarchy is read at populate
// time to decide which team owns a shared night, reordering changed nothing on
// the controller until some unrelated event triggered a regeneration.
//
// What is pinned here is the SIGNAL, not the widget: that a priority write
// reports itself as a reorder, that membership writes report themselves as
// membership, and that a heal does not fire at all. The listener keys off
// exactly that distinction — reacting to membership too would double-fire
// against `toggleAutopilot`'s own populate.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/team_priority.dart';
import 'package:nexgen_command/features/autopilot/team_priority_repopulate.dart';
import 'package:nexgen_command/features/sports_alerts/services/team_registration_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late TeamRegistrationService service;
  late List<TeamsChangedReason> fired;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    fired = <TeamsChangedReason>[];
    service = TeamRegistrationService(firestore: firestore)
      ..onTeamsChanged = fired.add;
  });

  group('setTeamPriority — the reorder signal', () {
    test('fires priorityReordered, the reason the repopulate listens for',
        () async {
      await service.setTeamPriority(
        uid: 'u1',
        entries: const [
          TeamPriorityEntry(displayName: 'Kansas City Chiefs', slug: 'nfl_chiefs'),
          TeamPriorityEntry(displayName: 'New York Jets', slug: 'nfl_jets'),
        ],
      );
      expect(fired, [TeamsChangedReason.priorityReordered]);
    });

    test('persists both fields in the new order, so a repopulate triggered '
        'afterwards reads the order the user just set', () async {
      await service.setTeamPriority(
        uid: 'u1',
        entries: const [
          TeamPriorityEntry(displayName: 'New York Jets', slug: 'nfl_jets'),
          TeamPriorityEntry(displayName: 'Kansas City Chiefs', slug: 'nfl_chiefs'),
        ],
      );
      final doc = await firestore.collection('users').doc('u1').get();
      expect(doc.data()!['game_day_team_priority'], ['nfl_jets', 'nfl_chiefs']);
      expect(doc.data()!['sports_team_priority'],
          ['New York Jets', 'Kansas City Chiefs']);
    });

    test('an empty uid throws rather than writing somewhere unexpected',
        () async {
      expect(
        () => service.setTeamPriority(uid: '', entries: const []),
        throwsStateError,
      );
      expect(fired, isEmpty);
    });
  });

  group('membership writes are a DIFFERENT reason', () {
    test('addTeam reports membership, never priorityReordered', () async {
      await service.addTeam(uid: 'u1', teamSlug: 'nfl_chiefs');
      expect(fired, [TeamsChangedReason.membership]);
      // If this ever became priorityReordered, the repopulate listener would
      // fire alongside toggleAutopilot's own populate and race it over the
      // same calendar_entries map.
      expect(fired, isNot(contains(TeamsChangedReason.priorityReordered)));
    });

    test('removeTeam reports membership', () async {
      await service.addTeam(uid: 'u1', teamSlug: 'nfl_chiefs');
      fired.clear();
      await service.removeTeam(
        uid: 'u1',
        teamSlug: 'nfl_chiefs',
        teamName: 'Kansas City Chiefs',
      );
      expect(fired, [TeamsChangedReason.membership]);
    });

    test('removeTeamByNameOnly reports membership', () async {
      await service.removeTeamByNameOnly(
        uid: 'u1',
        teamName: 'Kansas City Chiefs',
      );
      expect(fired, [TeamsChangedReason.membership]);
    });
  });

  group('the heal is silent', () {
    test('writeHealedGameDayPriority fires NOTHING', () async {
      await service.writeHealedGameDayPriority(
        uid: 'u1',
        slugs: const ['nfl_chiefs', 'nfl_jets'],
      );
      // Heal-on-read runs whenever the Game Day screen opens. Firing a
      // repopulate from it would turn opening a screen into an ESPN fetch, a
      // whole-document rewrite and a round of controller preset saves.
      expect(fired, isEmpty);
    });
  });

  group('debounce window', () {
    test('is long enough to collapse a multi-drag rearrangement, short '
        'enough to land while the user is still on the screen', () {
      expect(kTeamPriorityRepopulateDebounce.inSeconds, greaterThanOrEqualTo(2));
      expect(kTeamPriorityRepopulateDebounce.inSeconds, lessThanOrEqualTo(10));
    });
  });
}
