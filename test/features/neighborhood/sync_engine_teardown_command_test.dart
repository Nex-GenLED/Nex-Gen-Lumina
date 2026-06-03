// Tests for the explicit teardown-command path on NeighborhoodSyncEngine.
//
// Background: owner End Group / self-leave used to only MUTATE Firestore flags
// and trust each member's local flag-trigger to self-revert — which was
// unreliable (the `|| hasActiveGroup` term kept members mounted, and the
// un-deleted design command got replayed on resume, re-lighting the member).
//
// The fix broadcasts an explicit teardown SyncCommand on the SAME /commands
// channel propagation uses. The engine's command handler branches on
// [SyncCommand.isTeardown] and runs the local teardown restore instead of
// applying a design. These tests pin that routing:
//   • a teardown command for me → dispatchTeardown fires; apply path does NOT
//   • a teardown command targeted at ANOTHER member → ignored
//   • dedup across re-subscribes (fireImmediately replay) → fires once
//   • the apply gate is reset so the flag-trigger can't double-revert
//   • a design command after a teardown still applies (not deduped against it)
//
// Spy pattern: subclass the engine to count dispatchTeardown / onNewSyncCommand
// (both overridden no-ops) so we don't need a real WLED repo or command stream.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';

void main() {
  // Engine constructor calls WidgetsBinding.instance.addObserver.
  TestWidgetsFlutterBinding.ensureInitialized();

  SyncCommand teardownCmd(String id, {String? target}) => SyncCommand(
        id: id,
        groupId: 'g',
        effectId: 0,
        colors: const [],
        speed: 0,
        intensity: 0,
        brightness: 0,
        startTimestamp: DateTime.utc(2026, 6, 3, 12),
        memberDelays: const {},
        timingConfig: const SyncTimingConfig(),
        isTeardown: true,
        targetMemberUid: target,
      );

  SyncCommand designCmd(String id) => SyncCommand(
        id: id,
        groupId: 'g',
        effectId: 5,
        colors: const [0xFF0000],
        speed: 128,
        intensity: 128,
        brightness: 200,
        startTimestamp: DateTime.utc(2026, 6, 3, 11),
        memberDelays: const {'u1': 0},
        timingConfig: const SyncTimingConfig(),
      );

  /// Builds a spy engine wired to a container whose current member is [myUid].
  _SpyEngine engineFor({String myUid = 'u1'}) {
    late _SpyEngine spy;
    final container = ProviderContainer(overrides: [
      neighborhoodSyncEngineProvider.overrideWith((ref) {
        spy = _SpyEngine(ref);
        return spy;
      }),
      currentUserMemberProvider.overrideWith((ref) => NeighborhoodMember(
            oderId: myUid,
            displayName: 'Me',
            positionIndex: 0,
            lastSeen: DateTime.utc(2026, 6, 3),
            isParticipating: true,
          )),
    ]);
    addTearDown(container.dispose);
    container.read(neighborhoodSyncEngineProvider);
    return spy;
  }

  group('handleTeardownCommand — scope + dedup + gate reset', () {
    test('GLOBAL teardown (target null) → reverts me and resets the apply gate',
        () {
      final spy = engineFor(myUid: 'u1');
      spy.setHasAppliedForTest(hasApplied: true);

      spy.handleTeardownCommand(teardownCmd('t1'));

      expect(spy.teardownCount, 1, reason: 'global teardown reverts every member');
      expect(spy.hasAppliedForTest, isFalse,
          reason: 'apply gate reset so the flag-trigger can\'t double-revert');
    });

    test('teardown TARGETED at me → reverts', () {
      final spy = engineFor(myUid: 'u1');
      spy.handleTeardownCommand(teardownCmd('t1', target: 'u1'));
      expect(spy.teardownCount, 1);
    });

    test('teardown targeted at ANOTHER member → ignored (no revert)', () {
      final spy = engineFor(myUid: 'u1');
      spy.handleTeardownCommand(teardownCmd('t1', target: 'u2'));
      expect(spy.teardownCount, 0,
          reason: 'a self-leave teardown must not tear down everyone else');
    });

    test('dedup: replaying the SAME teardown id (fireImmediately/resume) fires '
        'once', () {
      final spy = engineFor(myUid: 'u1');
      spy.handleTeardownCommand(teardownCmd('t1'));
      spy.handleTeardownCommand(teardownCmd('t1'));
      spy.handleTeardownCommand(teardownCmd('t1'));
      expect(spy.teardownCount, 1,
          reason: 'resume replay of the latest (teardown) command must not '
              'repeatedly re-run the off/restore');
    });
  });

  group('handleCommandSnapshot — routes teardown vs design', () {
    test('isTeardown command → teardown path, NOT the apply path', () {
      final spy = engineFor(myUid: 'u1');
      spy.handleCommandSnapshot(null, AsyncData(teardownCmd('t1')));
      expect(spy.teardownCount, 1);
      expect(spy.applyCount, 0,
          reason: 'a teardown must never route through the design-apply / '
              'β-self-set path that would re-flag participating + re-light');
    });

    test('design command → apply path, NOT teardown', () {
      final spy = engineFor(myUid: 'u1');
      spy.handleCommandSnapshot(null, AsyncData(designCmd('d1')));
      expect(spy.applyCount, 1);
      expect(spy.teardownCount, 0);
    });

    test('a NEW design after a teardown still applies (not deduped against it)',
        () {
      final spy = engineFor(myUid: 'u1');
      spy.handleCommandSnapshot(
          AsyncData(teardownCmd('t1')), AsyncData(designCmd('d2')));
      expect(spy.applyCount, 1, reason: 'a fresh sync after teardown must apply');
    });
  });
}

class _SpyEngine extends NeighborhoodSyncEngine {
  _SpyEngine(super.ref);

  int teardownCount = 0;
  int applyCount = 0;

  @override
  void dispatchTeardown() {
    teardownCount++;
  }

  @override
  void onNewSyncCommand(SyncCommand command) {
    applyCount++;
  }
}
