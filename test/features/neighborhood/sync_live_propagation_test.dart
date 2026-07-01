// Tests for the Neighborhood Sync LIVE-PROPAGATION fix (restart-required bug).
//
// Symptom: a design change made by one member only applied on the OTHER
// member's lights after a full app relaunch. Audit traced three compounding
// causes, all in the #52 dead-listener class:
//   1. Subscription scope — the apply listener was mounted only by
//      NeighborhoodSyncScreen, so an off-screen receiver had no live listener.
//      Fix: app-level keepalive + app-wide active-group resolution
//      (resolveAutoActiveGroupId).
//   2. Stream death — a single unparseable command doc / stream error killed
//      the listener permanently. Fix: parse-guard in watchLatestCommand +
//      error→re-subscribe in handleCommandSnapshot.
//   3. Missed-on-resubscribe — ref.listen without fireImmediately skipped the
//      current design on a stop→start churn. Fix: fireImmediately replay,
//      guarded against double-apply by the id-dedup.
//   4. Resume — returning from background re-asserts via handleAppResume.
//
// These tests exercise the pure decision surfaces (resolveAutoActiveGroupId,
// handleCommandSnapshot) and the resume seam, using a spy engine so no real
// Firestore command stream or WLED apply is needed.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';

void main() {
  // Engine constructor calls WidgetsBinding.instance.addObserver.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveAutoActiveGroupId — app-wide active-group resolution', () {
    test('no groups → null (do NOT keep a stale id after a leave — outage '
        'fix: a stale pointer drove denied command reads that blanked the '
        'dashboard)', () {
      expect(resolveAutoActiveGroupId('g1', const []), isNull);
      expect(resolveAutoActiveGroupId(null, const []), isNull);
    });

    test('single idle group, no selection → auto-select it (so the command '
        'listener is already watching when a sync STARTS)', () {
      final groups = [_group('g1', isActive: false)];
      expect(resolveAutoActiveGroupId(null, groups), 'g1');
    });

    test('RECEIVER-NOT-ON-SCREEN: a group becomes active with no selection → '
        'auto-tune to the active group so the off-screen receiver applies the '
        'remote design change', () {
      final groups = [
        _group('g1', isActive: false),
        _group('g2', isActive: true),
      ];
      expect(resolveAutoActiveGroupId(null, groups), 'g2');
    });

    test('explicit valid selection is respected (not overridden out from '
        'under an on-screen user), even if another group is active', () {
      final groups = [
        _group('g1', isActive: false),
        _group('g2', isActive: true),
      ];
      expect(resolveAutoActiveGroupId('g1', groups), 'g1');
    });

    test('stale selection (group left / no longer in list) + active group → '
        'retarget to the active group', () {
      final groups = [_group('g2', isActive: true)];
      expect(resolveAutoActiveGroupId('gone', groups), 'g2');
    });

    test('multi-group, none active, no valid selection → leave (ambiguous; '
        'defer to explicit on-screen selection)', () {
      final groups = [
        _group('g1', isActive: false),
        _group('g2', isActive: false),
      ];
      expect(resolveAutoActiveGroupId(null, groups), isNull);
    });

    test('stale selection (not in list) + multi-group none active → null, NOT '
        'the stale id (never auto-activate a non-member group — outage fix)',
        () {
      final groups = [
        _group('g1', isActive: false),
        _group('g2', isActive: false),
      ];
      expect(resolveAutoActiveGroupId('gone', groups), isNull);
    });
  });

  group('handleCommandSnapshot — apply / dedup / error resilience', () {
    test('new command (previous null = fireImmediately replay shape) → applies '
        'once', () {
      final spy = _spyEngine();
      spy.handleCommandSnapshot(null, AsyncData<SyncCommand?>(_cmd('a')));
      expect(spy.applied.map((c) => c.id).toList(), ['a']);
      expect(spy.resubscribeScheduled, 0);
    });

    test('DOUBLE-APPLY GUARD: same command id on consecutive emissions → NOT '
        're-applied (fireImmediately replay of the already-applied command is '
        'deduped)', () {
      final spy = _spyEngine();
      final prev = AsyncData<SyncCommand?>(_cmd('a'));
      final next = AsyncData<SyncCommand?>(_cmd('a'));
      spy.handleCommandSnapshot(prev, next);
      expect(spy.applied, isEmpty);
    });

    test('genuine design change (new id) → applies', () {
      final spy = _spyEngine();
      spy.handleCommandSnapshot(
        AsyncData<SyncCommand?>(_cmd('a')),
        AsyncData<SyncCommand?>(_cmd('b')),
      );
      expect(spy.applied.map((c) => c.id).toList(), ['b']);
    });

    test('null command (empty collection / unparseable doc mapped to null) → '
        'no apply, no re-subscribe', () {
      final spy = _spyEngine();
      spy.handleCommandSnapshot(
        const AsyncData<SyncCommand?>(null),
        const AsyncData<SyncCommand?>(null),
      );
      expect(spy.applied, isEmpty);
      expect(spy.resubscribeScheduled, 0);
    });

    test('STREAM ERROR does not kill the listener: schedules a re-subscribe '
        'and does NOT apply (#52 class)', () {
      final spy = _spyEngine();
      spy.handleCommandSnapshot(
        AsyncData<SyncCommand?>(_cmd('a')),
        AsyncError<SyncCommand?>(Exception('permission-denied'), StackTrace.empty),
      );
      expect(spy.applied, isEmpty);
      expect(spy.resubscribeScheduled, 1);
    });
  });

  group('handleAppResume — foreground-from-background recovery', () {
    test('re-subscribes the command stream so a change made while suspended '
        'is re-applied without a full relaunch', () {
      final spy = _spyEngine();
      spy.handleAppResume();
      expect(spy.resubscribeNow, 1);
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────────

NeighborhoodGroup _group(String id, {required bool isActive}) {
  return NeighborhoodGroup(
    id: id,
    name: id,
    inviteCode: 'INV',
    creatorUid: 'owner',
    createdAt: DateTime.utc(2026, 6, 2),
    memberUids: const ['owner', 'u1'],
    isActive: isActive,
  );
}

SyncCommand _cmd(String id) {
  return SyncCommand(
    id: id,
    groupId: 'g1',
    effectId: 0,
    colors: const [0xFFFFFFFF],
    speed: 128,
    intensity: 128,
    brightness: 200,
    startTimestamp: DateTime.utc(2026, 6, 2),
    memberDelays: const {'u1': 0},
    timingConfig: const SyncTimingConfig(),
    patternName: 'Pattern $id',
  );
}

_SpyEngine _spyEngine() {
  final container = ProviderContainer(
    overrides: [
      neighborhoodSyncEngineProvider.overrideWith((ref) => _SpyEngine(ref)),
    ],
  );
  addTearDown(container.dispose);
  return container.read(neighborhoodSyncEngineProvider) as _SpyEngine;
}

/// Records apply / re-subscribe seam calls instead of touching Firestore or
/// the WLED device.
class _SpyEngine extends NeighborhoodSyncEngine {
  _SpyEngine(super.ref);

  final List<SyncCommand> applied = [];
  int resubscribeScheduled = 0;
  int resubscribeNow = 0;

  @override
  void onNewSyncCommand(SyncCommand command) => applied.add(command);

  @override
  void scheduleCommandStreamResubscribe() => resubscribeScheduled++;

  @override
  void resubscribeCommandStreamNow() => resubscribeNow++;
}
