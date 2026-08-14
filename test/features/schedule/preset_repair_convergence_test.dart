// The non-convergence guard: a repair that does not converge is a bug report,
// not a retry.
//
// WHAT IT FORECLOSES. `psaveIfChanged` saves whenever a stored preset fails its
// predicate — correct when the save can fix it. If the predicate is
// UNSATISFIABLE (firmware cannot store the field it demands, or the predicate
// drifted out of step with its builder), every sync re-saves forever. `psave`
// APPLIES its state live on this firmware, so that is a visible flicker on
// every connect, on every controller, with each individual save reporting
// success and nothing in the logs calling it a failure.
//
// Surfaced by the root-on investigation (2026-08-14). That case turned out
// SATISFIABLE — the app sends `ib:true` and WLED stores root `on:false`
// correctly — but the failure mode it implied is real, so it is foreclosed
// here rather than waiting for the next predicate to drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';

void main() {
  group('mayAttemptRepair', () {
    test('allows up to the limit, refuses at it', () {
      expect(mayAttemptRepair(0), isTrue);
      expect(mayAttemptRepair(kMaxRepairAttempts - 1), isTrue);
      expect(mayAttemptRepair(kMaxRepairAttempts), isFalse);
      expect(mayAttemptRepair(kMaxRepairAttempts + 5), isFalse);
    });

    // One failure is ordinarily a transient write or an unreadable readback.
    // Refusing after one would turn a flaky network into a permanent refusal.
    test('the limit is above 1 on purpose', () {
      expect(kMaxRepairAttempts, greaterThan(1));
      expect(mayAttemptRepair(1), isTrue);
    });
  });

  group('decideRepair', () {
    test('a fresh preset is allowed', () async {
      final s = InMemoryRepairAttemptStore();
      final d = await decideRepair(presetId: 2, presetName: 'NGL Off', store: s);
      expect(d.allowed, isTrue);
      expect(d.attempts, 0);
      expect(d.refusal, isNull);
    });

    // THE SCENARIO. A predicate no save can satisfy: attempts accumulate and
    // the guard stops the loop instead of flickering the strip forever.
    test('an unsatisfiable repair is refused after the limit', () async {
      final s = InMemoryRepairAttemptStore();
      var saves = 0;
      for (var sync = 0; sync < 10; sync++) {
        final d = await decideRepair(presetId: 2, presetName: 'NGL Off', store: s);
        if (!d.allowed) continue;
        saves++;
        await s.recordAttempt(2); // the save "succeeds" but never satisfies
      }
      expect(saves, kMaxRepairAttempts,
          reason: 'ten syncs must produce exactly $kMaxRepairAttempts saves');
    });

    test('the refusal names the preset, the name, and the count', () async {
      final s = InMemoryRepairAttemptStore();
      for (var i = 0; i < kMaxRepairAttempts; i++) {
        await s.recordAttempt(2);
      }
      final d = await decideRepair(presetId: 2, presetName: 'NGL Off', store: s);
      expect(d.allowed, isFalse);
      expect(d.refusal, contains('preset 2'));
      expect(d.refusal, contains('NGL Off'));
      expect(d.refusal, contains('$kMaxRepairAttempts'));
      // Actionable, not merely negative.
      expect(d.refusal, contains('out of step'));
    });

    // CONVERGENCE RESETS. An intermittent failure must never accumulate across
    // unrelated syncs into a permanent refusal.
    test('a satisfied predicate clears the counter', () async {
      final s = InMemoryRepairAttemptStore();
      await s.recordAttempt(2);
      await s.recordAttempt(2);
      await s.recordSatisfied(2);
      final d = await decideRepair(presetId: 2, presetName: 'NGL Off', store: s);
      expect(d.allowed, isTrue);
      expect(d.attempts, 0);
    });

    test('counters are per preset — one bad slot does not gag the others',
        () async {
      final s = InMemoryRepairAttemptStore();
      for (var i = 0; i < kMaxRepairAttempts; i++) {
        await s.recordAttempt(2);
      }
      expect((await decideRepair(presetId: 2, presetName: 'Off', store: s)).allowed,
          isFalse);
      expect((await decideRepair(presetId: 1, presetName: 'On', store: s)).allowed,
          isTrue);
    });

    // A broken counter must never block a repair that might work: the guard
    // exists to stop pointless writes, not to become a new way to fail.
    test('a throwing store fails OPEN', () async {
      final d = await decideRepair(
          presetId: 2, presetName: 'NGL Off', store: _ThrowingStore());
      expect(d.allowed, isTrue);
    });
  });

  test('the store is process-scoped — a relaunch re-attempts', () async {
    // Correct, not a bug: a new session may be talking to a repaired
    // controller, and refusing on stale in-memory state would be its own
    // permanent failure.
    final a = InMemoryRepairAttemptStore();
    for (var i = 0; i < kMaxRepairAttempts; i++) {
      await a.recordAttempt(2);
    }
    final fresh = InMemoryRepairAttemptStore();
    expect((await decideRepair(presetId: 2, presetName: 'Off', store: fresh)).allowed,
        isTrue);
  });
}

class _ThrowingStore implements RepairAttemptStore {
  @override
  Future<int> attempts(int presetId) async => throw StateError('boom');
  @override
  Future<void> recordAttempt(int presetId) async {}
  @override
  Future<void> recordSatisfied(int presetId) async {}
}
