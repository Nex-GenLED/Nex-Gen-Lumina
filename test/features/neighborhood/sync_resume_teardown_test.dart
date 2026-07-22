// Behavioral tests for the lifecycle persistence change:
//   #1  app paused/detached must NOT end a sync (no revert on background).
//   #3 REMOVED  the resume teardown-suppression guard is gone — resume now
//      re-applies the latest command verbatim, deferring to the idempotent
//      handleTeardownCommand dedup. This locks in the regression fix: a real
//      End-Group teardown that lands while the member is asleep MUST revert on
//      resume (the case the #3 guard wrongly suppressed).
//
// These exercise the engine seams (onNewSyncCommand, dispatchTeardown) via a
// spy subclass — no real Firestore command stream or WLED apply. currentUser
// MemberProvider is overridden so handleTeardownCommand does not reach
// FirebaseAuth.instance (which would throw without Firebase.initializeApp).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';

void main() {
  // Engine constructor calls WidgetsBinding.instance.addObserver.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#3 removed — resume replays the latest command verbatim', () {
    test('latest = design → applies once, never reverts (C-A: a stale prior '
        'teardown can never be latest while a design is live)', () {
      final spy = _spy();
      spy.handleCommandSnapshot(null, AsyncData<SyncCommand?>(_design('d1')));
      expect(spy.applied.map((c) => c.id).toList(), ['d1']);
      expect(spy.teardowns, 0, reason: 'a design must never trigger a revert');
    });

    test('latest = current End-Group teardown while member was asleep → '
        'REVERTS on resume (the #3 regression case)', () {
      final spy = _spy();
      // All-targeted teardown (owner End-Group), surfaced as the newest command.
      spy.handleCommandSnapshot(null, AsyncData<SyncCommand?>(_teardown('t1')));
      expect(spy.teardowns, 1, reason: 'a legitimate end must revert on resume');
      expect(spy.applied, isEmpty);
    });

    test('C-self: an already-handled teardown id is deduped → no double-revert',
        () {
      final spy = _spy();
      spy.handleTeardownCommand(_teardown('t1'));
      spy.handleTeardownCommand(_teardown('t1'));
      expect(spy.teardowns, 1, reason: ':449 _lastHandledTeardownId dedup');
    });

    test('C-partial: a fresh teardown after one handled still reverts — no '
        'poisoned dedup blocking a later legitimate end', () {
      final spy = _spy();
      spy.handleTeardownCommand(_teardown('t1'));
      spy.handleTeardownCommand(_teardown('t2'));
      expect(spy.teardowns, 2);
    });
  });

  group('#1 — app paused/detached is a no-op (no revert on background)', () {
    test('handleAppLifecyclePauseForTest performs no teardown and no apply',
        () async {
      final spy = _spy();
      await spy.handleAppLifecyclePauseForTest();
      expect(spy.teardowns, 0);
      expect(spy.applied, isEmpty);
    });

    test('paused + detached dispatch → no teardown, no apply', () async {
      final spy = _spy();
      spy.didChangeAppLifecycleState(AppLifecycleState.paused);
      spy.didChangeAppLifecycleState(AppLifecycleState.detached);
      await Future<void>.delayed(Duration.zero); // flush the unawaited handler
      expect(spy.teardowns, 0);
      expect(spy.applied, isEmpty);
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────────

SyncCommand _design(String id) => SyncCommand(
      id: id,
      groupId: 'g1',
      effectId: 0,
      colors: const [0xFFFFFFFF],
      speed: 128,
      intensity: 128,
      brightness: 200,
      startTimestamp: DateTime.utc(2026, 6, 3),
      memberDelays: const {'u1': 0},
      timingConfig: const SyncTimingConfig(),
      patternName: 'Pattern $id',
    );

// All-targeted teardown (owner End-Group): targetMemberUid == null.
SyncCommand _teardown(String id) => SyncCommand(
      id: id,
      groupId: 'g1',
      effectId: 0,
      colors: const [0xFFFFFFFF],
      speed: 128,
      intensity: 128,
      brightness: 0,
      startTimestamp: DateTime.utc(2026, 6, 3),
      memberDelays: const {},
      timingConfig: const SyncTimingConfig(),
      isTeardown: true,
    );

_SpyEngine _spy() {
  final container = ProviderContainer(
    overrides: [
      neighborhoodSyncEngineProvider.overrideWith((ref) => _SpyEngine(ref)),
      // Avoid FirebaseAuth.instance inside currentUserMemberProvider; an
      // all-targeted teardown (targetMemberUid == null) is honored regardless
      // of member identity, so null is sufficient here.
      currentUserMemberProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return container.read(neighborhoodSyncEngineProvider) as _SpyEngine;
}

/// Records the apply / teardown seams instead of touching Firestore or WLED.
class _SpyEngine extends NeighborhoodSyncEngine {
  _SpyEngine(super.ref);

  final List<SyncCommand> applied = [];
  int teardowns = 0;

  @override
  void onNewSyncCommand(SyncCommand command) => applied.add(command);

  @override
  void dispatchTeardown() => teardowns++;
}
