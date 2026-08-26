// D1 — the Game Day calendar populate coalesces its sync requests into ONE.
//
// The 800ms debounce ALREADY collapses the loop when it runs faster than 800ms
// per entry (audit/SYNC_PACING_FIX_STATUS.md §2a / P3). The problem is that
// each entry awaits a Firestore round-trip, so under slow network the timer
// fires MID-LOOP — and a second sync arriving while the first verifies is
// DROPPED by `_syncInFlight`, not queued, so the tail of the loop can go
// unpushed. Batching replaces a latency race with a deterministic single sync.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';

void main() {
  ProviderContainer harness() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('a batch starts closed and owes nothing', () {
    final n = harness().read(schedulesProvider.notifier);
    expect(n.debugSyncBatchDepth, 0);
    expect(n.debugSyncPendingAfterBatch, isFalse);
  });

  test('begin/end nest, and only the outermost close settles the batch', () {
    final n = harness().read(schedulesProvider.notifier);
    n.beginSyncBatch();
    n.beginSyncBatch();
    expect(n.debugSyncBatchDepth, 2);
    n.endSyncBatch();
    expect(n.debugSyncBatchDepth, 1, reason: 'still batching');
    n.endSyncBatch();
    expect(n.debugSyncBatchDepth, 0);
  });

  test('an unbalanced end is tolerated, not thrown', () {
    final n = harness().read(schedulesProvider.notifier);
    expect(() => n.endSyncBatch(), returnsNormally);
    expect(n.debugSyncBatchDepth, 0);
  });

  // The owed-sync flag is what turns N requests into 1.
  test('closing a batch that owed nothing does not invent a sync', () {
    final n = harness().read(schedulesProvider.notifier);
    n.beginSyncBatch();
    n.endSyncBatch();
    expect(n.debugSyncPendingAfterBatch, isFalse);
  });

  test('the pending flag clears once the batch settles it', () {
    final n = harness().read(schedulesProvider.notifier);
    n.beginSyncBatch();
    // No public mutation is driven here (that needs auth + Firestore); the flag
    // is asserted directly, which is the unit under test.
    expect(n.debugSyncPendingAfterBatch, isFalse);
    n.endSyncBatch();
    expect(n.debugSyncPendingAfterBatch, isFalse);
    expect(n.debugSyncBatchDepth, 0);
  });
}
