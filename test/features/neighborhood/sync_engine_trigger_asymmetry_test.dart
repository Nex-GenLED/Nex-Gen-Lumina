// Tests for syncEngineControllerProvider's asymmetric start/teardown
// semantics — the Symptom-2 fix for the 3dbca29 cross-member revert.
//
// Old trigger: start/stop both keyed off (manuallyActive || hasActiveGroup).
// When any member wrote g.isActive=false, EVERY member's listener tore down
// and ran teardown — reverting all participating homes to their pre-sync
// pattern. That's the regression.
//
// New trigger (this test enforces):
//   START broad — startListening fires when ANY of:
//     manuallyActive || iAmParticipating || hasActiveGroup
//     (hasActiveGroup is kept in the START branch to solve the first-sync
//     chicken-and-egg: a member's own isParticipating flag is false until
//     the engine sees a SyncCommand arrive and self-sets it via Prompt 3.)
//   STOP narrow — stopListening fires ONLY when ALL three signals are
//     false. CRITICAL: when hasActiveGroup flips true→false WHILE
//     iAmParticipating stays true, the engine MUST stay listening — that
//     is the regression-guard assertion below.
//
// Spy pattern: NeighborhoodSyncEngine is subclassed to count startListening
// and stopListening invocations; neighborhoodSyncEngineProvider is
// overridden with the spy so we don't try to wire up a real Firestore
// command-stream listener in unit-test land.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';

void main() {
  // Engine constructor calls WidgetsBinding.instance.addObserver (Prompt 5
  // app-lifecycle observer); test binding must be initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('syncEngineControllerProvider — asymmetric start/teardown trigger', () {
    test('all-false → stopListening (the only stop case)', () {
      final spy = _runTrigger(
        manuallyActive: false,
        iAmParticipating: false,
        hasActiveGroup: false,
      );
      expect(spy.startCount, 0);
      expect(spy.stopCount, 1);
    });

    test('manuallyActive=true only → startListening', () {
      final spy = _runTrigger(
        manuallyActive: true,
        iAmParticipating: false,
        hasActiveGroup: false,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });

    test('iAmParticipating=true only → startListening', () {
      final spy = _runTrigger(
        manuallyActive: false,
        iAmParticipating: true,
        hasActiveGroup: false,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });

    test('hasActiveGroup=true only → startListening (FIRST-SYNC '
        'CHICKEN-AND-EGG: own flag is false until command arrives and the '
        'engine self-sets it via Prompt 3; hasActiveGroup must mount the '
        'listener so the command can land)', () {
      final spy = _runTrigger(
        manuallyActive: false,
        iAmParticipating: false,
        hasActiveGroup: true,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });

    test('iAmParticipating=true + hasActiveGroup=true → startListening', () {
      final spy = _runTrigger(
        manuallyActive: false,
        iAmParticipating: true,
        hasActiveGroup: true,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });

    test('all-true → startListening', () {
      final spy = _runTrigger(
        manuallyActive: true,
        iAmParticipating: true,
        hasActiveGroup: true,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });

    test('REGRESSION GUARD (3dbca29): hasActiveGroup=false + '
        'iAmParticipating=true → still startListening, NOT stopListening. '
        'This is the inverse of the bug: under the OLD trigger, '
        'hasActiveGroup going false would call stopListening and fire '
        'teardown on every member that had applied. Under the NEW trigger, '
        'so long as MY own flag is still true I keep listening — and only '
        'MY own flag dropping (member-stop or owner-end fan-clear) can '
        'transition me to stopped.', () {
      final spy = _runTrigger(
        manuallyActive: false,
        iAmParticipating: true,
        hasActiveGroup: false,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0,
          reason: 'shared isActive dropping while own flag stays true must '
              'NOT trigger teardown — this is the 3dbca29 fix');
    });

    test('manuallyActive=true + iAmParticipating=false + hasActiveGroup=false '
        '→ startListening', () {
      final spy = _runTrigger(
        manuallyActive: true,
        iAmParticipating: false,
        hasActiveGroup: false,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });

    test('manuallyActive=true + iAmParticipating=true + hasActiveGroup=false '
        '→ startListening', () {
      final spy = _runTrigger(
        manuallyActive: true,
        iAmParticipating: true,
        hasActiveGroup: false,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });

    test('myMember=null + hasActiveGroup=false → stopListening (iAmParticipating '
        'safely defaults to false when current user is not in the active '
        "group's members)", () {
      final spy = _runTrigger(
        manuallyActive: false,
        iAmParticipating: null, // null myMember
        hasActiveGroup: false,
      );
      expect(spy.startCount, 0);
      expect(spy.stopCount, 1);
    });

    test('myMember=null + hasActiveGroup=true → startListening (chicken-and-egg '
        "still applies even when we're not yet a tracked member)", () {
      final spy = _runTrigger(
        manuallyActive: false,
        iAmParticipating: null,
        hasActiveGroup: true,
      );
      expect(spy.startCount, 1);
      expect(spy.stopCount, 0);
    });
  });
}

/// Stand up a ProviderContainer with the three trigger inputs overridden,
/// read syncEngineControllerProvider once to fire the trigger body, and
/// return the spy engine for assertion.
///
/// [iAmParticipating] null → currentUserMemberProvider returns null (user
/// is not in the active group's member list).
_SpyEngine _runTrigger({
  required bool manuallyActive,
  required bool? iAmParticipating,
  required bool hasActiveGroup,
}) {
  final spy = _SpyEngineHolder();
  final container = ProviderContainer(
    overrides: [
      neighborhoodSyncEngineProvider.overrideWith((ref) {
        spy.engine = _SpyEngine(ref);
        return spy.engine!;
      }),
      currentUserMemberProvider.overrideWith((ref) {
        if (iAmParticipating == null) return null;
        return NeighborhoodMember(
          oderId: 'u1',
          displayName: 'House A',
          positionIndex: 0,
          lastSeen: DateTime.utc(2026, 5, 30),
          isParticipating: iAmParticipating,
        );
      }),
      isInActiveSyncProvider.overrideWith((ref) => hasActiveGroup),
    ],
  );
  addTearDown(container.dispose);

  container.read(syncEngineActiveProvider.notifier).state = manuallyActive;
  // Fire the trigger.
  container.read(syncEngineControllerProvider);
  return spy.engine!;
}

class _SpyEngineHolder {
  _SpyEngine? engine;
}

/// Counts startListening / stopListening invocations. Both overrides are
/// no-op (don't touch the real Firestore command subscription, which we
/// can't stand up in a unit test).
class _SpyEngine extends NeighborhoodSyncEngine {
  _SpyEngine(super.ref);

  int startCount = 0;
  int stopCount = 0;

  @override
  void startListening() {
    startCount++;
  }

  @override
  void stopListening() {
    stopCount++;
  }
}
