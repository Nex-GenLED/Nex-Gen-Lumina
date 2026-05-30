// Tests for Prompt 3 — Option β self-set: on SyncCommand receive (in
// _scheduleLocalExecution, before the timing branch), the engine writes
// isParticipating=true to its OWN /neighborhoods/{groupId}/members/{uid}
// doc. Idempotent (skip if already true), fire-and-forget (failure
// doesn't block apply).
//
// Spy pattern: NeighborhoodSyncEngine is subclassed to capture
// markSelfParticipating(groupId, memberUid) calls without touching real
// Firestore. SyncCommands are constructed with startTimestamp in the
// future so _executePattern (which would require wledRepositoryProvider)
// is scheduled to a Timer that never fires during the test — only the
// pre-timing self-set path is exercised.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';

void main() {
  group('β self-set on SyncCommand receive', () {
    test('member.isParticipating=false → markSelfParticipating called once '
        'with (command.groupId, member.oderId)', () async {
      final spy = _runReceive(
        currentMember: _baseMember(isParticipating: false),
        command: _baseCommand(),
      );
      // Allow the unawaited future a microtask to dispatch.
      await Future<void>.delayed(Duration.zero);
      expect(spy.markCalls.length, 1);
      expect(spy.markCalls.single.groupId, equals('g1'));
      expect(spy.markCalls.single.memberUid, equals('u1'));
    });

    test('IDEMPOTENCY GUARD: member.isParticipating=true → '
        'markSelfParticipating NOT called (avoids redundant write on every '
        'subsequent command in the same session)', () async {
      final spy = _runReceive(
        currentMember: _baseMember(isParticipating: true),
        command: _baseCommand(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(spy.markCalls, isEmpty);
    });

    test('currentMember=null → markSelfParticipating NOT called (early '
        'return before self-write)', () async {
      final spy = _runReceive(
        currentMember: null,
        command: _baseCommand(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(spy.markCalls, isEmpty);
    });

    test('member offline → markSelfParticipating NOT called '
        '(participation gate runs before self-write)', () async {
      final spy = _runReceive(
        currentMember: _baseMember(isParticipating: false, isOnline: false),
        command: _baseCommand(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(spy.markCalls, isEmpty);
    });

    test('member paused → markSelfParticipating NOT called', () async {
      final spy = _runReceive(
        currentMember: _baseMember(
          isParticipating: false,
          participationStatus: MemberParticipationStatus.paused,
        ),
        command: _baseCommand(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(spy.markCalls, isEmpty);
    });

    test('member not in command.memberDelays → markSelfParticipating NOT '
        'called (member-not-included gate runs before self-write)', () async {
      final spy = _runReceive(
        currentMember: _baseMember(isParticipating: false),
        command: _baseCommand(memberDelays: const {'someone_else': 0}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(spy.markCalls, isEmpty);
    });
  });
}

NeighborhoodMember _baseMember({
  bool isParticipating = false,
  bool isOnline = true,
  MemberParticipationStatus participationStatus =
      MemberParticipationStatus.active,
}) =>
    NeighborhoodMember(
      oderId: 'u1',
      displayName: 'House A',
      positionIndex: 0,
      isOnline: isOnline,
      lastSeen: DateTime.utc(2026, 5, 30),
      participationStatus: participationStatus,
      isParticipating: isParticipating,
    );

SyncCommand _baseCommand({
  String groupId = 'g1',
  Map<String, int>? memberDelays,
}) =>
    SyncCommand(
      id: 'cmd1',
      groupId: groupId,
      effectId: 0,
      colors: const [0xFFFFFF],
      speed: 128,
      intensity: 128,
      brightness: 200,
      // Future timestamp so _scheduleLocalExecution takes the Timer branch
      // and never calls _executePattern during the test — only the
      // pre-timing self-set path is exercised.
      startTimestamp: DateTime.utc(2099, 1, 1),
      memberDelays: memberDelays ?? const {'u1': 0},
      timingConfig: const SyncTimingConfig(),
      patternName: 'Test Pattern',
    );

_SpyEngine _runReceive({
  required NeighborhoodMember? currentMember,
  required SyncCommand command,
}) {
  final spyHolder = _SpyEngineHolder();
  final container = ProviderContainer(
    overrides: [
      neighborhoodSyncEngineProvider.overrideWith((ref) {
        spyHolder.engine = _SpyEngine(ref);
        return spyHolder.engine!;
      }),
      currentUserMemberProvider.overrideWith((ref) => currentMember),
    ],
  );
  addTearDown(container.dispose);
  final engine = container.read(neighborhoodSyncEngineProvider) as _SpyEngine;
  engine.scheduleLocalExecutionForTest(command);
  return engine;
}

class _SpyEngineHolder {
  _SpyEngine? engine;
}

class _MarkCall {
  _MarkCall(this.groupId, this.memberUid);
  final String groupId;
  final String memberUid;
}

/// Records markSelfParticipating calls without touching real Firestore.
class _SpyEngine extends NeighborhoodSyncEngine {
  _SpyEngine(super.ref);
  final List<_MarkCall> markCalls = [];

  @override
  Future<void> markSelfParticipating(String groupId, String memberUid) async {
    markCalls.add(_MarkCall(groupId, memberUid));
  }
}
