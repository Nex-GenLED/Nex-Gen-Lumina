// Stop the healer re-saving a preset that a save can never satisfy.
//
// WHY THIS EXISTS. `psaveIfChanged` saves whenever a stored preset fails its
// predicate. That is correct when the save can fix it. If a predicate is
// UNSATISFIABLE — the firmware cannot store the field it demands, or the
// predicate asks for something the builder never writes — then every sync
// re-saves, forever. And `psave` APPLIES its state live on this firmware, so
// each one is a visible disruption: a strip that flickers on every connect, on
// every controller, with nothing in the logs calling it a failure because each
// individual save "succeeded".
//
// The root-on investigation (2026-08-14) is what surfaced the class. That
// specific case turned out to be satisfiable — the app sends `ib:true` and WLED
// stores root `on:false` correctly — but the failure mode it implied is real
// and cheap to foreclose, so it is foreclosed here rather than left to the next
// predicate that drifts out of step with its builder.
//
// THE RULE: a repair that does not converge is a bug report, not a retry.

import 'package:flutter/foundation.dart';

/// Attempts against one preset before the repair is declared non-convergent.
///
/// Three, not one: a single failure is ordinarily a transient write or an
/// unreadable readback, and refusing after one would turn a flaky network into
/// a permanent refusal. Three consecutive attempts with the predicate never
/// flipping is not bad luck.
const int kMaxRepairAttempts = 3;

/// PURE. May the healer attempt this repair?
///
/// [priorAttempts] counts consecutive attempts that did NOT result in the
/// predicate being satisfied on a later evaluation. A satisfied predicate
/// resets it to zero, so an intermittent failure can never accumulate to a
/// refusal across unrelated syncs.
bool mayAttemptRepair(int priorAttempts, {int max = kMaxRepairAttempts}) =>
    priorAttempts < max;

/// PURE. The operator-facing reason, naming the preset and what was tried.
///
/// Legible per the #68 convention: a counter that says "skipped" without saying
/// which preset or why reconciles perfectly and tells nobody anything.
String nonConvergenceReason(int presetId, String presetName, int attempts) =>
    'preset $presetId ($presetName) still fails its check after $attempts '
    'saves — refusing to re-save. The save is not fixing it, so repeating it '
    'only disrupts the strip. Predicate and builder are out of step.';

/// Per-preset attempt counters.
///
/// IN-MEMORY, not persisted. A cloud round-trip on the repair path would be a
/// new failure mode for a guard whose whole job is to stop making things
/// worse, and persisting to disk would outlive the condition: the counter
/// describes one session's conversation with one controller. If a repair is
/// genuinely unsatisfiable it re-proves that within three syncs of the next
/// launch, which is fast enough to catch and cheap enough to be wrong about.
/// The interface is abstract so a persisted store can replace it if that
/// judgement turns out wrong.
abstract class RepairAttemptStore {
  Future<int> attempts(int presetId);
  Future<void> recordAttempt(int presetId);
  Future<void> recordSatisfied(int presetId);
}

/// In-memory implementation. Process-scoped, mirroring the facts-publisher
/// memos: a relaunch re-attempts, which is correct — a new session may be
/// talking to a repaired controller, and refusing on stale memory would be its
/// own permanent failure.
class InMemoryRepairAttemptStore implements RepairAttemptStore {
  final Map<int, int> _counts = <int, int>{};

  @override
  Future<int> attempts(int presetId) async => _counts[presetId] ?? 0;

  @override
  Future<void> recordAttempt(int presetId) async {
    _counts[presetId] = (_counts[presetId] ?? 0) + 1;
  }

  @override
  Future<void> recordSatisfied(int presetId) async {
    _counts.remove(presetId);
  }

  @visibleForTesting
  Map<int, int> get raw => _counts;
}

/// The process-wide store the healer uses.
final RepairAttemptStore repairAttempts = InMemoryRepairAttemptStore();

/// Clear the process-wide counters.
///
/// REQUIRED IN TEST setUp. The store is deliberately process-scoped so that
/// non-convergence is detected ACROSS syncs — which means a test file running
/// several syncs in one process accumulates attempts across unrelated tests,
/// and the fourth one gets refused for the third one's sins. That is not a
/// flaw in the guard; it is the cost of the property that makes it work.
void resetRepairAttempts() {
  final s = repairAttempts;
  if (s is InMemoryRepairAttemptStore) s.raw.clear();
}

/// Outcome of consulting the guard, so the caller can log one line and move on.
@immutable
class RepairDecision {
  final bool allowed;
  final int attempts;
  final String? refusal;

  const RepairDecision.allow(this.attempts)
      : allowed = true,
        refusal = null;

  const RepairDecision.refuse(this.attempts, this.refusal) : allowed = false;
}

/// Consult the guard for one preset. Never throws.
Future<RepairDecision> decideRepair({
  required int presetId,
  required String presetName,
  RepairAttemptStore? store,
  int max = kMaxRepairAttempts,
}) async {
  final s = store ?? repairAttempts;
  int n;
  try {
    n = await s.attempts(presetId);
  } catch (_) {
    // A broken counter must not block a repair that might work.
    return const RepairDecision.allow(0);
  }
  if (mayAttemptRepair(n, max: max)) return RepairDecision.allow(n);
  return RepairDecision.refuse(n, nonConvergenceReason(presetId, presetName, n));
}
